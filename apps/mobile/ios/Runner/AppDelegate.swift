import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Carries the tapped room to Dart.
  private var notificationChannel: FlutterMethodChannel?

  /// Whoever held the delegate before this one took it, so notifications this
  /// app did not send still reach the plugin that is waiting for them.
  private weak var previousCenterDelegate: UNUserNotificationCenterDelegate?

  /// A tap that arrived before Dart was listening, held until it asks.
  private var pendingRoomId: String?

  /// PushKit registry for VoIP pushes — the only push Apple lets become a
  /// real incoming-call screen on a locked phone.
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let started = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Claimed on the next runloop turn, after every plugin has installed its
    // own delegate, because this has to sit at the head of the chain to see a
    // tap at all. firebase_messaging forwards a tap to Dart only when the
    // payload carries a gcm.message_id, which a notification sent straight to
    // APNs does not have; flutter_local_notifications drops any notification
    // it did not itself create, without passing it on. Between them a tapped
    // push would simply open the app on whatever screen it was left at.
    DispatchQueue.main.async { [weak self] in
      guard let self, UNUserNotificationCenter.current().delegate !== self else { return }
      self.previousCenterDelegate = UNUserNotificationCenter.current().delegate
      UNUserNotificationCenter.current().delegate = self
    }

    // VoIP pushes queue until a delegate exists, so registering here — after
    // the Flutter engine and its plugins are up — means the push callback
    // below never races the CallKit plugin it hands the call to.
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry

    return started
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    notificationChannel = FlutterMethodChannel(
      name: "digitalgrub.chat/notification_taps",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notificationChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takePendingRoom" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // A tap that launched the app lands before Dart is listening, so it is
      // claimed once here rather than delivered and lost.
      let roomId = self?.pendingRoomId
      self?.pendingRoomId = nil
      result(roomId)
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Only a tap on the notification body opens a room. A dismissal, or a
    // custom action, must not navigate anywhere.
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let roomId = response.notification.request.content.userInfo["room_id"] as? String,
      !roomId.isEmpty
    {
      pendingRoomId = roomId
      notificationChannel?.invokeMethod("openRoom", arguments: roomId) { [weak self] handled in
        // Cleared only once Dart confirms it routed, so a tap that arrived
        // before the app was listening is still waiting to be claimed, and one
        // that was handled is not replayed at the next launch.
        if let handled = handled as? Bool, handled, self?.pendingRoomId == roomId {
          self?.pendingRoomId = nil
        }
      }
    }

    forward(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  /// Hands the response to the delegate that was displaced, so notifications
  /// raised by the app itself keep working.
  private func forward(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard
      let previous = previousCenterDelegate,
      previous.responds(
        to: #selector(
          UNUserNotificationCenterDelegate.userNotificationCenter(
            _:didReceive:withCompletionHandler:)))
    else {
      // No displaced delegate: FlutterAppDelegate fans the response out to
      // plugins registered as application lifecycle delegates, so it has to
      // see this rather than the callback being answered here.
      super.userNotificationCenter(
        center, didReceive: response, withCompletionHandler: completionHandler)
      return
    }
    // The displaced delegate owns the completion handler from here. Calling it
    // here as well would be a double call, which UIKit treats as a fault.
    previous.userNotificationCenter?(
      center, didReceive: response, withCompletionHandler: completionHandler)
  }

  /// Keeps a notification arriving in the foreground looking the way the
  /// displaced delegate intended, rather than silently changing behaviour by
  /// taking the delegate over.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard
      let previous = previousCenterDelegate,
      previous.responds(
        to: #selector(
          UNUserNotificationCenterDelegate.userNotificationCenter(
            _:willPresent:withCompletionHandler:)))
    else {
      super.userNotificationCenter(
        center, willPresent: notification, withCompletionHandler: completionHandler)
      return
    }
    previous.userNotificationCenter?(
      center, willPresent: notification, withCompletionHandler: completionHandler)
  }
}

extension AppDelegate: PKPushRegistryDelegate {
  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    // Handed to the plugin, which hands it to Dart, which registers it as a
    // second pusher on the homeserver — the ring channel.
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    // Apple's contract: every VoIP push reports a call, immediately, or the
    // app stops receiving them. The gateway only sends ring events down this
    // channel, so reporting unconditionally is both required and correct.
    guard type == .voIP else {
      completion()
      return
    }
    let roomId = payload.dictionaryPayload["room_id"] as? String ?? ""
    let data = flutter_callkit_incoming.Data(args: [
      "id": UUID().uuidString,
      "nameCaller": "Incoming call",
      "appName": "Digitalgrub Chat",
      "handle": "",
      "type": 0,
      "duration": 30000,
      "extra": ["roomId": roomId],
      "ios": [
        "supportsVideo": true,
        "ringtonePath": "system_ringtone_default",
      ],
    ])
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data, fromPushKit: true, completion: completion)
  }
}
