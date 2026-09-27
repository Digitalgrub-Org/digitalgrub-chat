import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ta'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Digitalgrub Chat'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Your conversations, on your server.'**
  String get appTagline;

  /// No description provided for @onboardingFastTitle.
  ///
  /// In en, this message translates to:
  /// **'Fast, focused conversations'**
  String get onboardingFastTitle;

  /// No description provided for @onboardingFastBody.
  ///
  /// In en, this message translates to:
  /// **'Move from a quick hello to a real conversation without getting in your way.'**
  String get onboardingFastBody;

  /// No description provided for @onboardingOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages stay close'**
  String get onboardingOfflineTitle;

  /// No description provided for @onboardingOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Open recent conversations and prepare replies even when your connection drops.'**
  String get onboardingOfflineBody;

  /// No description provided for @onboardingHostedTitle.
  ///
  /// In en, this message translates to:
  /// **'Hosted by Digitalgrub'**
  String get onboardingHostedTitle;

  /// No description provided for @onboardingHostedBody.
  ///
  /// In en, this message translates to:
  /// **'Your chat service runs on infrastructure controlled by Digitalgrub, not a paid chat platform.'**
  String get onboardingHostedBody;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue your conversations.'**
  String get loginSubtitle;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @registrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get registrationTitle;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @optionalMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number (optional)'**
  String get optionalMobileNumber;

  /// No description provided for @mobileNumberPrivacyHint.
  ///
  /// In en, this message translates to:
  /// **'Stored privately for your account. SMS login is not enabled yet.'**
  String get mobileNumberPrivacyHint;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get requiredField;

  /// No description provided for @usernameValidation.
  ///
  /// In en, this message translates to:
  /// **'Use 3–32 lowercase letters, numbers, dots, underscores, equals signs, or hyphens.'**
  String get usernameValidation;

  /// No description provided for @passwordValidation.
  ///
  /// In en, this message translates to:
  /// **'Use at least {count} characters.'**
  String passwordValidation(int count);

  /// No description provided for @mobileNumberValidation.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid mobile number.'**
  String get mobileNumberValidation;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @creatingAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating account…'**
  String get creatingAccount;

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'The username or password is incorrect.'**
  String get invalidCredentials;

  /// No description provided for @registrationDisabled.
  ///
  /// In en, this message translates to:
  /// **'New account registration is currently disabled.'**
  String get registrationDisabled;

  /// No description provided for @usernameTaken.
  ///
  /// In en, this message translates to:
  /// **'That username is already in use.'**
  String get usernameTaken;

  /// No description provided for @invalidUsername.
  ///
  /// In en, this message translates to:
  /// **'That username is not allowed.'**
  String get invalidUsername;

  /// No description provided for @rateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again shortly.'**
  String get rateLimited;

  /// No description provided for @serverUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Digitalgrub Chat cannot reach the server right now.'**
  String get serverUnavailable;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get sessionExpired;

  /// No description provided for @unknownAuthenticationError.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Please try again.'**
  String get unknownAuthenticationError;

  /// No description provided for @profileSetupIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Your account was created, but some profile details could not be saved.'**
  String get profileSetupIncomplete;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Digitalgrub Chat could not initialize.'**
  String get startupFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @loggingOut.
  ///
  /// In en, this message translates to:
  /// **'Logging out…'**
  String get loggingOut;

  /// No description provided for @logOutConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Log out of Digitalgrub Chat on this device?'**
  String get logOutConfirmation;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @startNewChat.
  ///
  /// In en, this message translates to:
  /// **'Start new chat'**
  String get startNewChat;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @noConversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noConversationsTitle;

  /// No description provided for @noConversationsBody.
  ///
  /// In en, this message translates to:
  /// **'Find someone or create a private group to begin.'**
  String get noConversationsBody;

  /// No description provided for @findPeople.
  ///
  /// In en, this message translates to:
  /// **'Find people'**
  String get findPeople;

  /// No description provided for @noContactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your people will appear here'**
  String get noContactsTitle;

  /// No description provided for @noContactsBody.
  ///
  /// In en, this message translates to:
  /// **'Search by username or display name.'**
  String get noContactsBody;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @notificationPreviews.
  ///
  /// In en, this message translates to:
  /// **'Message previews'**
  String get notificationPreviews;

  /// No description provided for @notificationPreviewsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show who wrote and what they said in notifications'**
  String get notificationPreviewsSubtitle;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Use device setting'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @searchPeople.
  ///
  /// In en, this message translates to:
  /// **'Search people'**
  String get searchPeople;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @groupDetails.
  ///
  /// In en, this message translates to:
  /// **'Group details'**
  String get groupDetails;

  /// No description provided for @userProfile.
  ///
  /// In en, this message translates to:
  /// **'User profile'**
  String get userProfile;

  /// No description provided for @blockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get blockedUsers;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @voiceRecord.
  ///
  /// In en, this message translates to:
  /// **'Record a voice message'**
  String get voiceRecord;

  /// No description provided for @voicePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get voicePlay;

  /// No description provided for @voicePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get voicePause;

  /// No description provided for @voiceDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard recording'**
  String get voiceDiscard;

  /// No description provided for @voiceRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get voiceRecording;

  /// No description provided for @voiceSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the voice message.'**
  String get voiceSendFailed;

  /// No description provided for @newMeeting.
  ///
  /// In en, this message translates to:
  /// **'New meeting'**
  String get newMeeting;

  /// No description provided for @meetingDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Digitalgrub meeting'**
  String get meetingDefaultTitle;

  /// No description provided for @meetingReady.
  ///
  /// In en, this message translates to:
  /// **'Your meeting is ready'**
  String get meetingReady;

  /// No description provided for @meetingShareHint.
  ///
  /// In en, this message translates to:
  /// **'Anyone on the team who opens this link joins the meeting.'**
  String get meetingShareHint;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @emailInvite.
  ///
  /// In en, this message translates to:
  /// **'Email invite'**
  String get emailInvite;

  /// No description provided for @joinNow.
  ///
  /// In en, this message translates to:
  /// **'Join now'**
  String get joinNow;

  /// No description provided for @meetingCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the meeting.'**
  String get meetingCreateFailed;

  /// No description provided for @meetJoining.
  ///
  /// In en, this message translates to:
  /// **'Joining the meeting…'**
  String get meetJoining;

  /// No description provided for @meetLinkDead.
  ///
  /// In en, this message translates to:
  /// **'This meeting link does not work any more.'**
  String get meetLinkDead;

  /// No description provided for @meetJoinFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not join the meeting.'**
  String get meetJoinFailed;

  /// No description provided for @meetingInviteSubject.
  ///
  /// In en, this message translates to:
  /// **'Join my meeting on Digitalgrub Chat'**
  String get meetingInviteSubject;

  /// No description provided for @meetingInviteBody.
  ///
  /// In en, this message translates to:
  /// **'Join my meeting on Digitalgrub Chat:\n\n{link}\n\nOpen the link and sign in — you will land straight in the call.'**
  String meetingInviteBody(String link);

  /// No description provided for @startCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get startCall;

  /// No description provided for @startVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get startVideoCall;

  /// No description provided for @incomingCallFrom.
  ///
  /// In en, this message translates to:
  /// **'{name} is calling'**
  String incomingCallFrom(String name);

  /// No description provided for @callAcceptAudio.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get callAcceptAudio;

  /// No description provided for @callAcceptVideo.
  ///
  /// In en, this message translates to:
  /// **'Answer with video'**
  String get callAcceptVideo;

  /// No description provided for @callDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get callDecline;

  /// No description provided for @callHangUp.
  ///
  /// In en, this message translates to:
  /// **'Hang up'**
  String get callHangUp;

  /// No description provided for @callMuteMic.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get callMuteMic;

  /// No description provided for @callUnmuteMic.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get callUnmuteMic;

  /// No description provided for @callCameraOn.
  ///
  /// In en, this message translates to:
  /// **'Camera on'**
  String get callCameraOn;

  /// No description provided for @callCameraOff.
  ///
  /// In en, this message translates to:
  /// **'Camera off'**
  String get callCameraOff;

  /// No description provided for @callSwitchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get callSwitchCamera;

  /// No description provided for @callSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get callSpeaker;

  /// No description provided for @readBy.
  ///
  /// In en, this message translates to:
  /// **'Read by {names}'**
  String readBy(String names);

  /// No description provided for @mentionEveryoneHint.
  ///
  /// In en, this message translates to:
  /// **'Notifies everyone in this group'**
  String get mentionEveryoneHint;

  /// No description provided for @callReact.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get callReact;

  /// No description provided for @callShareScreen.
  ///
  /// In en, this message translates to:
  /// **'Share screen'**
  String get callShareScreen;

  /// No description provided for @callStopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get callStopSharing;

  /// No description provided for @callSomeoneSharing.
  ///
  /// In en, this message translates to:
  /// **'Someone is sharing their screen'**
  String get callSomeoneSharing;

  /// No description provided for @callConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get callConnecting;

  /// No description provided for @callReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get callReconnecting;

  /// No description provided for @callWaitingForOthers.
  ///
  /// In en, this message translates to:
  /// **'Waiting for others to join…'**
  String get callWaitingForOthers;

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'The call could not be connected.'**
  String get callFailed;

  /// No description provided for @callPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone or camera access was denied. Allow it in system settings to make calls.'**
  String get callPermissionDenied;

  /// No description provided for @callParticipantCount.
  ///
  /// In en, this message translates to:
  /// **'{count} in call'**
  String callParticipantCount(int count);

  /// No description provided for @messagesSection.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messagesSection;

  /// No description provided for @noMessagesFound.
  ///
  /// In en, this message translates to:
  /// **'No messages found'**
  String get noMessagesFound;

  /// No description provided for @messageSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Message search is unavailable right now.'**
  String get messageSearchFailed;

  /// No description provided for @attachmentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Image unavailable'**
  String get attachmentUnavailable;

  /// No description provided for @attachmentFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get attachmentFile;

  /// No description provided for @attachmentPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get attachmentPhoto;

  /// No description provided for @attachmentVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get attachmentVideo;

  /// No description provided for @attachmentAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get attachmentAudio;

  /// No description provided for @attachmentVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get attachmentVoice;

  /// No description provided for @sendPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get sendPhoto;

  /// No description provided for @sendFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get sendFile;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get takePhoto;

  /// No description provided for @attachmentTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That file is too large to send.'**
  String get attachmentTooLarge;

  /// No description provided for @attachmentSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send that file.'**
  String get attachmentSendFailed;

  /// No description provided for @searchConversations.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get searchConversations;

  /// No description provided for @noMatchingConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations match your search.'**
  String get noMatchingConversations;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// No description provided for @chatListFailed.
  ///
  /// In en, this message translates to:
  /// **'Your cached conversations could not be opened.'**
  String get chatListFailed;

  /// No description provided for @peopleSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Name or @username:server'**
  String get peopleSearchHint;

  /// No description provided for @peopleSearchInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter at least two characters to find someone by display name or username.'**
  String get peopleSearchInstructions;

  /// No description provided for @noPeopleFound.
  ///
  /// In en, this message translates to:
  /// **'No people found.'**
  String get noPeopleFound;

  /// No description provided for @peopleSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'People search is unavailable right now. Please try again.'**
  String get peopleSearchFailed;

  /// No description provided for @messageInputHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageInputHint;

  /// No description provided for @formatBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get formatBold;

  /// No description provided for @formatItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get formatItalic;

  /// No description provided for @formatStrikethrough.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get formatStrikethrough;

  /// No description provided for @formatCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get formatCode;

  /// No description provided for @insertEmoji.
  ///
  /// In en, this message translates to:
  /// **'Insert emoji'**
  String get insertEmoji;

  /// No description provided for @emojiSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search emoji'**
  String get emojiSearchHint;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// No description provided for @messageSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Message could not be sent. Your text has been restored.'**
  String get messageSendFailed;

  /// No description provided for @messageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'This conversation could not be opened.'**
  String get messageLoadFailed;

  /// No description provided for @messagesWaitingToSend.
  ///
  /// In en, this message translates to:
  /// **'Messages waiting to send'**
  String get messagesWaitingToSend;

  /// No description provided for @messagesFailedToSend.
  ///
  /// In en, this message translates to:
  /// **'Messages failed to send'**
  String get messagesFailedToSend;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @synchronizing.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing…'**
  String get synchronizing;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offlineCachedContent.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing saved conversations'**
  String get offlineCachedContent;

  /// No description provided for @historyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Older messages could not be loaded.'**
  String get historyLoadFailed;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @react.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get react;

  /// No description provided for @editMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get editMessage;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessage;

  /// No description provided for @copyMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyMessage;

  /// No description provided for @messageDetails.
  ///
  /// In en, this message translates to:
  /// **'Message details'**
  String get messageDetails;

  /// No description provided for @reportMessage.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportMessage;

  /// No description provided for @deleteForMe.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get deleteForMe;

  /// No description provided for @deleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteForEveryone;

  /// No description provided for @deleteMessageConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Choose how this message should be removed.'**
  String get deleteMessageConfirmation;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Message copied.'**
  String get copiedToClipboard;

  /// No description provided for @edited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get edited;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// No description provided for @replyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to'**
  String get replyingTo;

  /// No description provided for @editingMessage.
  ///
  /// In en, this message translates to:
  /// **'Editing message'**
  String get editingMessage;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'typing…'**
  String get typing;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @chooseReaction.
  ///
  /// In en, this message translates to:
  /// **'Choose a reaction'**
  String get chooseReaction;

  /// No description provided for @messageActionFailed.
  ///
  /// In en, this message translates to:
  /// **'That message action could not be completed.'**
  String get messageActionFailed;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Product crew'**
  String get groupNameHint;

  /// No description provided for @groupDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get groupDescriptionLabel;

  /// No description provided for @groupDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What is this group for?'**
  String get groupDescriptionHint;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a group name.'**
  String get groupNameRequired;

  /// No description provided for @groupNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Group names can be at most {count} characters.'**
  String groupNameTooLong(int count);

  /// No description provided for @groupDescriptionTooLong.
  ///
  /// In en, this message translates to:
  /// **'Descriptions can be at most {count} characters.'**
  String groupDescriptionTooLong(int count);

  /// No description provided for @addPeople.
  ///
  /// In en, this message translates to:
  /// **'Add people'**
  String get addPeople;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @memberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String memberCount(int count);

  /// No description provided for @creatingGroup.
  ///
  /// In en, this message translates to:
  /// **'Creating group…'**
  String get creatingGroup;

  /// No description provided for @groupMemberLimitReached.
  ///
  /// In en, this message translates to:
  /// **'A group can hold up to {count} people.'**
  String groupMemberLimitReached(int count);

  /// No description provided for @selectAtLeastOneMember.
  ///
  /// In en, this message translates to:
  /// **'Select at least one person to add.'**
  String get selectAtLeastOneMember;

  /// No description provided for @groupCreationFailed.
  ///
  /// In en, this message translates to:
  /// **'The group could not be created. Please try again.'**
  String get groupCreationFailed;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @addMembers.
  ///
  /// In en, this message translates to:
  /// **'Add members'**
  String get addMembers;

  /// No description provided for @removeFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get removeFromGroup;

  /// No description provided for @removeMemberConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this group?'**
  String removeMemberConfirmation(String name);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @leaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get leaveGroup;

  /// No description provided for @leaveGroupConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Leave this group? You will stop receiving its messages.'**
  String get leaveGroupConfirmation;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @editGroupName.
  ///
  /// In en, this message translates to:
  /// **'Edit group name'**
  String get editGroupName;

  /// No description provided for @editGroupDescription.
  ///
  /// In en, this message translates to:
  /// **'Edit description'**
  String get editGroupDescription;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleModerator.
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get roleModerator;

  /// No description provided for @roleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// No description provided for @changeRole.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get changeRole;

  /// No description provided for @invited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get invited;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @noGroupDescription.
  ///
  /// In en, this message translates to:
  /// **'No description yet.'**
  String get noGroupDescription;

  /// No description provided for @groupDetailsFailed.
  ///
  /// In en, this message translates to:
  /// **'Group details could not be opened.'**
  String get groupDetailsFailed;

  /// No description provided for @groupUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'That group change could not be saved.'**
  String get groupUpdateFailed;

  /// No description provided for @groupNotPermitted.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to do that.'**
  String get groupNotPermitted;

  /// No description provided for @groupNotFound.
  ///
  /// In en, this message translates to:
  /// **'This group is no longer available.'**
  String get groupNotFound;

  /// No description provided for @invitationsSent.
  ///
  /// In en, this message translates to:
  /// **'Invitations sent.'**
  String get invitationsSent;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get myProfile;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @noAboutYet.
  ///
  /// In en, this message translates to:
  /// **'No about text yet.'**
  String get noAboutYet;

  /// No description provided for @matrixUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get matrixUsername;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get mobileNumber;

  /// No description provided for @noMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Not added'**
  String get noMobileNumber;

  /// No description provided for @mobileNumberUnverified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get mobileNumberUnverified;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get changePhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @photoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Photo updated.'**
  String get photoUpdated;

  /// No description provided for @photoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That image is too large. Choose a smaller one.'**
  String get photoTooLarge;

  /// No description provided for @photoPickFailed.
  ///
  /// In en, this message translates to:
  /// **'That image could not be opened.'**
  String get photoPickFailed;

  /// No description provided for @displayNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a display name.'**
  String get displayNameRequired;

  /// No description provided for @aboutTooLong.
  ///
  /// In en, this message translates to:
  /// **'About text can be at most {count} characters.'**
  String aboutTooLong(int count);

  /// No description provided for @profileLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'This profile could not be opened.'**
  String get profileLoadFailed;

  /// No description provided for @profileUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'That profile change could not be saved.'**
  String get profileUpdateFailed;

  /// No description provided for @profileNotFound.
  ///
  /// In en, this message translates to:
  /// **'That user could not be found.'**
  String get profileNotFound;

  /// No description provided for @sendMessageTo.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get sendMessageTo;

  /// No description provided for @blockUser.
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get blockUser;

  /// No description provided for @unblockUser.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblockUser;

  /// No description provided for @blockUserConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Block {name}? You will stop seeing their messages and they cannot start new chats with you.'**
  String blockUserConfirmation(String name);

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @userBlocked.
  ///
  /// In en, this message translates to:
  /// **'User blocked.'**
  String get userBlocked;

  /// No description provided for @userUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User unblocked.'**
  String get userUnblocked;

  /// No description provided for @blockFailed.
  ///
  /// In en, this message translates to:
  /// **'That block change could not be saved.'**
  String get blockFailed;

  /// No description provided for @noBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'You have not blocked anyone.'**
  String get noBlockedUsers;

  /// No description provided for @noBlockedUsersBody.
  ///
  /// In en, this message translates to:
  /// **'People you block will appear here so you can unblock them later.'**
  String get noBlockedUsersBody;

  /// No description provided for @blockedUsersFailed.
  ///
  /// In en, this message translates to:
  /// **'Your blocked users could not be loaded.'**
  String get blockedUsersFailed;

  /// No description provided for @blockedMessageHidden.
  ///
  /// In en, this message translates to:
  /// **'Message from a blocked user'**
  String get blockedMessageHidden;

  /// No description provided for @reportUser.
  ///
  /// In en, this message translates to:
  /// **'Report user'**
  String get reportUser;

  /// No description provided for @reportCategory.
  ///
  /// In en, this message translates to:
  /// **'What is the problem?'**
  String get reportCategory;

  /// No description provided for @reportSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportSpam;

  /// No description provided for @reportHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get reportHarassment;

  /// No description provided for @reportAbuse.
  ///
  /// In en, this message translates to:
  /// **'Abuse'**
  String get reportAbuse;

  /// No description provided for @reportFraud.
  ///
  /// In en, this message translates to:
  /// **'Fraud'**
  String get reportFraud;

  /// No description provided for @reportInappropriate.
  ///
  /// In en, this message translates to:
  /// **'Inappropriate content'**
  String get reportInappropriate;

  /// No description provided for @reportOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportOther;

  /// No description provided for @reportComment.
  ///
  /// In en, this message translates to:
  /// **'Anything else we should know? (optional)'**
  String get reportComment;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get submitReport;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted. Thank you.'**
  String get reportSubmitted;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'That report could not be submitted. Please try again.'**
  String get reportFailed;

  /// No description provided for @reportCommentTooLong.
  ///
  /// In en, this message translates to:
  /// **'Comments can be at most {count} characters.'**
  String reportCommentTooLong(int count);

  /// No description provided for @alsoBlockUser.
  ///
  /// In en, this message translates to:
  /// **'Also block this user'**
  String get alsoBlockUser;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your Digitalgrub Chat account. Your username can never be used again, and your messages will be removed where the server is able to remove them. This cannot be undone.'**
  String get deleteAccountWarning;

  /// No description provided for @deleteAccountPasswordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to confirm.'**
  String get deleteAccountPasswordPrompt;

  /// No description provided for @deletingAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleting account…'**
  String get deletingAccount;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Your account could not be deleted. Please try again.'**
  String get deleteAccountFailed;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get accountDeleted;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get confirmDelete;

  /// No description provided for @contentAgreementTitle.
  ///
  /// In en, this message translates to:
  /// **'Our community rules'**
  String get contentAgreementTitle;

  /// No description provided for @contentAgreementBody.
  ///
  /// In en, this message translates to:
  /// **'Digitalgrub Chat carries messages written by other people. There is no tolerance for abusive, hateful, or illegal content, or for harassing other members.'**
  String get contentAgreementBody;

  /// No description provided for @contentAgreementReport.
  ///
  /// In en, this message translates to:
  /// **'Report any message or person that breaks these rules. We review reports and act within 24 hours.'**
  String get contentAgreementReport;

  /// No description provided for @contentAgreementBlock.
  ///
  /// In en, this message translates to:
  /// **'Block anyone you do not want to hear from. Their messages disappear from your app immediately.'**
  String get contentAgreementBlock;

  /// No description provided for @contentAgreementContact.
  ///
  /// In en, this message translates to:
  /// **'Questions or concerns: {email}'**
  String contentAgreementContact(String email);

  /// No description provided for @contentAgreementAccept.
  ///
  /// In en, this message translates to:
  /// **'I agree'**
  String get contentAgreementAccept;

  /// No description provided for @contentAgreementDecline.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get contentAgreementDecline;

  /// No description provided for @rulesConsent.
  ///
  /// In en, this message translates to:
  /// **'I agree to the community rules'**
  String get rulesConsent;

  /// No description provided for @rulesConsentRead.
  ///
  /// In en, this message translates to:
  /// **'Read the community rules'**
  String get rulesConsentRead;

  /// No description provided for @contentAgreementRequired.
  ///
  /// In en, this message translates to:
  /// **'You need to accept the community rules before sending messages.'**
  String get contentAgreementRequired;

  /// No description provided for @invitedYou.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you to chat'**
  String invitedYou(String name);

  /// No description provided for @invitedYouGeneric.
  ///
  /// In en, this message translates to:
  /// **'You have been invited to chat'**
  String get invitedYouGeneric;

  /// No description provided for @acceptInvite.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptInvite;

  /// No description provided for @declineInvite.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineInvite;

  /// No description provided for @declineInviteConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Decline this invitation? You will not see their messages.'**
  String get declineInviteConfirmation;

  /// No description provided for @inviteAccepted.
  ///
  /// In en, this message translates to:
  /// **'Invitation accepted.'**
  String get inviteAccepted;

  /// No description provided for @inviteDeclined.
  ///
  /// In en, this message translates to:
  /// **'Invitation declined.'**
  String get inviteDeclined;

  /// No description provided for @inviteActionFailed.
  ///
  /// In en, this message translates to:
  /// **'That invitation could not be updated. Please try again.'**
  String get inviteActionFailed;

  /// No description provided for @newMessageNotification.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessageNotification;

  /// No description provided for @newMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// No description provided for @selectConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick up a conversation'**
  String get selectConversationTitle;

  /// No description provided for @selectConversationBody.
  ///
  /// In en, this message translates to:
  /// **'Choose one from the list, or start a new one.'**
  String get selectConversationBody;

  /// No description provided for @userManagement.
  ///
  /// In en, this message translates to:
  /// **'User management'**
  String get userManagement;

  /// No description provided for @inviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCodeLabel;

  /// No description provided for @inviteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Ask your admin for a code. Digitalgrub Chat is invite-only.'**
  String get inviteCodeHint;

  /// No description provided for @invalidInviteCode.
  ///
  /// In en, this message translates to:
  /// **'That invite code isn\'t valid or has already been used.'**
  String get invalidInviteCode;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @userManagementCount.
  ///
  /// In en, this message translates to:
  /// **'{total} accounts'**
  String userManagementCount(int total);

  /// No description provided for @forwardMessage.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forwardMessage;

  /// No description provided for @forwardTo.
  ///
  /// In en, this message translates to:
  /// **'Forward to'**
  String get forwardTo;

  /// No description provided for @forwarded.
  ///
  /// In en, this message translates to:
  /// **'Forwarded'**
  String get forwarded;

  /// No description provided for @forwardNoChats.
  ///
  /// In en, this message translates to:
  /// **'No other chats to forward to.'**
  String get forwardNoChats;

  /// No description provided for @forwardedLabel.
  ///
  /// In en, this message translates to:
  /// **'Forwarded'**
  String get forwardedLabel;

  /// No description provided for @pinMessage.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinMessage;

  /// No description provided for @unpinMessage.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinMessage;

  /// No description provided for @pinnedMessage.
  ///
  /// In en, this message translates to:
  /// **'Pinned message'**
  String get pinnedMessage;

  /// No description provided for @pinnedCount.
  ///
  /// In en, this message translates to:
  /// **'Pinned {index} of {total}'**
  String pinnedCount(int index, int total);

  /// No description provided for @pinNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to pin messages in this chat. Ask a group admin.'**
  String get pinNotAllowed;

  /// No description provided for @pinFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change the pinned messages. Try again.'**
  String get pinFailed;

  /// No description provided for @enableNotificationsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Get notified when a message arrives while this tab is in the background.'**
  String get enableNotificationsPrompt;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get enableNotifications;

  /// No description provided for @notificationsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Your browser is blocking notifications for this site. Turn them on in its site settings.'**
  String get notificationsBlocked;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @returnToCall.
  ///
  /// In en, this message translates to:
  /// **'Tap to return to your call'**
  String get returnToCall;

  /// No description provided for @onACallNow.
  ///
  /// In en, this message translates to:
  /// **'On a call now'**
  String get onACallNow;

  /// No description provided for @joinCall.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinCall;

  /// No description provided for @liveCallParticipants.
  ///
  /// In en, this message translates to:
  /// **'{count} on the call'**
  String liveCallParticipants(int count);

  /// No description provided for @callStartedBy.
  ///
  /// In en, this message translates to:
  /// **'{name} started a call'**
  String callStartedBy(String name);

  /// No description provided for @youStartedCall.
  ///
  /// In en, this message translates to:
  /// **'You started a call'**
  String get youStartedCall;

  /// No description provided for @missedCall.
  ///
  /// In en, this message translates to:
  /// **'Missed call'**
  String get missedCall;

  /// No description provided for @callBack.
  ///
  /// In en, this message translates to:
  /// **'Call back'**
  String get callBack;

  /// No description provided for @someoneInCall.
  ///
  /// In en, this message translates to:
  /// **'Someone\'s in a call — tap to join'**
  String get someoneInCall;

  /// No description provided for @messageActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get messageActions;

  /// No description provided for @meetGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Join this meeting'**
  String get meetGuestTitle;

  /// No description provided for @meetGuestNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get meetGuestNameLabel;

  /// No description provided for @meetJoinAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Join meeting'**
  String get meetJoinAsGuest;

  /// No description provided for @meetSignInInstead.
  ///
  /// In en, this message translates to:
  /// **'Sign in instead'**
  String get meetSignInInstead;

  /// No description provided for @incomingCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get incomingCall;

  /// No description provided for @groupActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get groupActivity;

  /// No description provided for @groupActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing has happened here yet.'**
  String get groupActivityEmpty;

  /// No description provided for @activityCreated.
  ///
  /// In en, this message translates to:
  /// **'{name} created the group'**
  String activityCreated(String name);

  /// No description provided for @activityJoined.
  ///
  /// In en, this message translates to:
  /// **'{name} joined'**
  String activityJoined(String name);

  /// No description provided for @activityLeft.
  ///
  /// In en, this message translates to:
  /// **'{name} left'**
  String activityLeft(String name);

  /// No description provided for @activityInvited.
  ///
  /// In en, this message translates to:
  /// **'{name} invited {target}'**
  String activityInvited(String name, String target);

  /// No description provided for @activityRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed {target}'**
  String activityRemoved(String name, String target);

  /// No description provided for @activityRenamed.
  ///
  /// In en, this message translates to:
  /// **'{name} named the group “{detail}”'**
  String activityRenamed(String name, String detail);

  /// No description provided for @activityPhotoChanged.
  ///
  /// In en, this message translates to:
  /// **'{name} changed the group photo'**
  String activityPhotoChanged(String name);

  /// No description provided for @activityCallStarted.
  ///
  /// In en, this message translates to:
  /// **'{name} started a call'**
  String activityCallStarted(String name);

  /// No description provided for @activityPinsChanged.
  ///
  /// In en, this message translates to:
  /// **'{name} changed the pinned messages'**
  String activityPinsChanged(String name);

  /// No description provided for @activityRolesChanged.
  ///
  /// In en, this message translates to:
  /// **'{name} changed member roles'**
  String activityRolesChanged(String name);

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the email address on your account and we will send you a link.'**
  String get resetPasswordSubtitle;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddress;

  /// No description provided for @emailValidation.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get emailValidation;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get sendResetLink;

  /// No description provided for @sendingResetLink.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sendingResetLink;

  /// No description provided for @resetLinkSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get resetLinkSentTitle;

  /// No description provided for @resetLinkSentBody.
  ///
  /// In en, this message translates to:
  /// **'If {email} is on an account, a link is on its way. Open it, then come back here and set your new password.'**
  String resetLinkSentBody(String email);

  /// No description provided for @resendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send it again'**
  String get resendResetLink;

  /// No description provided for @resetLinkResent.
  ///
  /// In en, this message translates to:
  /// **'Sent again. It can take a minute to arrive.'**
  String get resetLinkResent;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Those two passwords are different'**
  String get passwordsDoNotMatch;

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get setNewPassword;

  /// No description provided for @passwordResetDone.
  ///
  /// In en, this message translates to:
  /// **'Password changed. Sign in with the new one.'**
  String get passwordResetDone;

  /// No description provided for @emailNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Open the link in the email first, then try again.'**
  String get emailNotVerified;

  /// No description provided for @emailNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'This server cannot send email yet. Ask your admin to reset it for you.'**
  String get emailNotConfigured;

  /// No description provided for @emailInUse.
  ///
  /// In en, this message translates to:
  /// **'Another account already uses that address.'**
  String get emailInUse;

  /// No description provided for @emailAddresses.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddresses;

  /// No description provided for @emailAddressesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used only to reset your password'**
  String get emailAddressesSubtitle;

  /// No description provided for @noEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'No email address yet. Without one, only an admin can reset your password.'**
  String get noEmailAddress;

  /// No description provided for @addEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Add email address'**
  String get addEmailAddress;

  /// No description provided for @removeEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeEmailAddress;

  /// No description provided for @emailAddressAdded.
  ///
  /// In en, this message translates to:
  /// **'Email address added.'**
  String get emailAddressAdded;

  /// No description provided for @emailAddressRemoved.
  ///
  /// In en, this message translates to:
  /// **'Email address removed.'**
  String get emailAddressRemoved;

  /// No description provided for @confirmWithPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm with your password'**
  String get confirmWithPassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @verifyEmailSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a link to {email}. Open it, then confirm below.'**
  String verifyEmailSent(String email);

  /// No description provided for @confirmEmail.
  ///
  /// In en, this message translates to:
  /// **'I have opened the link'**
  String get confirmEmail;

  /// No description provided for @callFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get callFullScreen;

  /// No description provided for @callExitFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get callExitFullScreen;

  /// No description provided for @callChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get callChat;

  /// No description provided for @callCloseChat.
  ///
  /// In en, this message translates to:
  /// **'Close chat'**
  String get callCloseChat;

  /// No description provided for @callRaiseHand.
  ///
  /// In en, this message translates to:
  /// **'Raise hand'**
  String get callRaiseHand;

  /// No description provided for @callLowerHand.
  ///
  /// In en, this message translates to:
  /// **'Lower hand'**
  String get callLowerHand;

  /// No description provided for @callPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get callPeople;

  /// No description provided for @callMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get callMute;

  /// No description provided for @callMuteAll.
  ///
  /// In en, this message translates to:
  /// **'Mute all'**
  String get callMuteAll;

  /// No description provided for @callHandRaised.
  ///
  /// In en, this message translates to:
  /// **'Hand raised'**
  String get callHandRaised;

  /// No description provided for @callYou.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String callYou(String name);

  /// No description provided for @adminNewUser.
  ///
  /// In en, this message translates to:
  /// **'New user'**
  String get adminNewUser;

  /// No description provided for @adminNewUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get adminNewUserTitle;

  /// No description provided for @adminNewUserHint.
  ///
  /// In en, this message translates to:
  /// **'They sign in with this username and password. Share the password with them yourself; it is not sent anywhere.'**
  String get adminNewUserHint;

  /// No description provided for @adminCreateUser.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminCreateUser;

  /// No description provided for @adminUserCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created: {userId}'**
  String adminUserCreated(String userId);

  /// No description provided for @adminResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get adminResetPassword;

  /// No description provided for @adminResetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password for {name}'**
  String adminResetPasswordTitle(String name);

  /// No description provided for @adminResetPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Every session they have is signed out. Tell them the new password yourself.'**
  String get adminResetPasswordHint;

  /// No description provided for @adminPasswordReset.
  ///
  /// In en, this message translates to:
  /// **'Password reset. Their sessions were signed out.'**
  String get adminPasswordReset;

  /// No description provided for @adminNotAdmin.
  ///
  /// In en, this message translates to:
  /// **'Only a server admin can do this. Sign in again as the admin account.'**
  String get adminNotAdmin;

  /// No description provided for @adminUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'Somebody already has that username.'**
  String get adminUsernameTaken;

  /// No description provided for @adminAccountOnServer.
  ///
  /// In en, this message translates to:
  /// **'Admin accounts are reset on the server, not from here.'**
  String get adminAccountOnServer;

  /// No description provided for @adminUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'No account with that username.'**
  String get adminUserNotFound;

  /// No description provided for @adminUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Admin actions are switched off in this build.'**
  String get adminUnavailable;

  /// No description provided for @adminActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get adminActions;

  /// No description provided for @presenceOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get presenceOnline;

  /// No description provided for @presenceLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen {when}'**
  String presenceLastSeen(String when);

  /// No description provided for @meet.
  ///
  /// In en, this message translates to:
  /// **'Meet'**
  String get meet;

  /// No description provided for @joinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get joinWithCode;

  /// No description provided for @meetingCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a meeting link or code'**
  String get meetingCodeHint;

  /// No description provided for @meetingCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'That is not a meeting link or code.'**
  String get meetingCodeInvalid;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareLink;

  /// No description provided for @joinMeeting.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinMeeting;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ta':
      return AppLocalizationsTa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
