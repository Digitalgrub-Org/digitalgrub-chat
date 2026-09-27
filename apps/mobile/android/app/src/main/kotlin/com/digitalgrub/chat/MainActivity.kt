package com.digitalgrub.chat

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.SystemClock
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /// The room whose call was answered from the system incoming-call screen
    /// while the app was dead, held until the Dart side collects it.
    ///
    /// The call plugin's own cold-start API (activeCalls) hangs once the push
    /// isolate's engine has run, and its accept event is not replayed to a
    /// listener that attaches later. The launch intent is the one signal that
    /// cannot race anything: Accept starts this activity with the plugin's
    /// action on it, Decline starts nothing, and a person opening the app by
    /// hand arrives with a plain MAIN intent.
    private var acceptedCallRoomId: String? = null

    /// When the accept above was captured, so a stale one can be told apart
    /// from a fresh one. Answering a call is a decision with a shelf life of
    /// seconds; acting on one the user has long forgotten opens a microphone
    /// they did not ask to open.
    private var acceptedAtElapsedMs: Long = 0L

    /// Whether leaving the app should shrink it to a picture-in-picture
    /// window. Set by Dart while the call screen is up and cleared when it
    /// goes, so a chat or the settings never end up floating in a corner.
    private var pipEligible = false
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureAcceptedCall(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureAcceptedCall(intent)
    }

    private fun captureAcceptedCall(intent: Intent?) {
        if (intent == null) return
        // Launching from the recents list hands back the intent that started
        // the activity the first time. Without this, an Accept from days ago
        // arrives looking exactly like one from a second ago.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        if (intent.action != "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT") return
        val data = intent.getBundleExtra("EXTRA_CALLKIT_CALL_DATA") ?: return
        @Suppress("UNCHECKED_CAST", "DEPRECATION")
        val extra = data.getSerializable("EXTRA_CALLKIT_EXTRA") as? Map<String, Any?> ?: return
        val roomId = extra["roomId"] as? String
        if (!roomId.isNullOrEmpty()) {
            acceptedCallRoomId = roomId
            acceptedAtElapsedMs = SystemClock.elapsedRealtime()
            // Retire the intent that carried it. This activity can be recreated
            // from the same intent -- process death, configuration change --
            // and one Accept must be answered exactly once.
            setIntent(Intent(Intent.ACTION_MAIN))
        }
    }

    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            // Portrait video, which is what a phone's camera produces.
            .setAspectRatio(Rational(9, 16))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // From Android 12 the system enters the window itself on the
            // home gesture, which is smoother than doing it from
            // onUserLeaveHint after the fact.
            builder.setAutoEnterEnabled(pipEligible)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            setPictureInPictureParams(pipParams())
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 8-11: no auto-enter, so ask when the person leaves.
        if (pipEligible &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            enterPictureInPictureMode(pipParams())
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val launch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "in.digitalgrub.chat/launch",
        )
        channel = launch
        launch.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPipEligible" -> {
                    pipEligible = call.arguments as? Boolean ?: false
                    updatePipParams()
                    result.success(true)
                }
                // Consumed, not read: answering one call must not re-join it
                // on every later warm start of the same activity. An accept
                // older than the window is dropped rather than served -- the
                // call it belonged to is long over.
                "takeAcceptedCallRoom" -> {
                    val age = SystemClock.elapsedRealtime() - acceptedAtElapsedMs
                    result.success(acceptedCallRoomId?.takeIf { age < ACCEPT_MAX_AGE_MS })
                    acceptedCallRoomId = null
                }
                // The microphone keeps working in the background only while
                // a foreground service of type `microphone` is up. Started
                // from Dart when a call connects rather than from here, so a
                // call that never connects never raises a notification.
                "startCallService" -> {
                    CallForegroundService.start(applicationContext)
                    result.success(true)
                }
                "stopCallService" -> {
                    CallForegroundService.stop(applicationContext)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        /// Generous enough for a cold start on a slow phone, far short of the
        /// hours a forgotten accept could otherwise survive.
        const val ACCEPT_MAX_AGE_MS = 120_000L
    }
}
