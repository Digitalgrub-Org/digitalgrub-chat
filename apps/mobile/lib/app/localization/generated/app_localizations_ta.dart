// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get appName => 'டிஜிட்டல்க்ரப் சாட்';

  @override
  String get appTagline => 'உங்கள் உரையாடல்கள், உங்கள் சேவையகத்தில்.';

  @override
  String get onboardingFastTitle => 'வேகமான, நேர்த்தியான உரையாடல்கள்';

  @override
  String get onboardingFastBody =>
      'எந்தத் தடையும் இல்லாமல் ஒரு வணக்கத்திலிருந்து அர்த்தமுள்ள உரையாடலுக்கு செல்லுங்கள்.';

  @override
  String get onboardingOfflineTitle => 'செய்திகள் உங்களுடனே இருக்கும்';

  @override
  String get onboardingOfflineBody =>
      'இணைப்பு துண்டிக்கப்பட்டாலும் சமீபத்திய உரையாடல்களைத் திறந்து பதில்களைத் தயாரிக்கலாம்.';

  @override
  String get onboardingHostedTitle => 'டிஜிட்டல்க்ரப் வழங்குகிறது';

  @override
  String get onboardingHostedBody =>
      'கட்டண அரட்டை தளத்தில் அல்லாமல், டிஜிட்டல்க்ரப் கட்டுப்பாட்டிலுள்ள கட்டமைப்பில் உங்கள் அரட்டை இயங்குகிறது.';

  @override
  String get skip => 'தவிர்';

  @override
  String get continueLabel => 'தொடர்க';

  @override
  String get getStarted => 'தொடங்குங்கள்';

  @override
  String get loginTitle => 'மீண்டும் வரவேற்கிறோம்';

  @override
  String get loginSubtitle => 'உங்கள் உரையாடல்களைத் தொடர உள்நுழையுங்கள்.';

  @override
  String get username => 'பயனர்பெயர்';

  @override
  String get password => 'கடவுச்சொல்';

  @override
  String get signIn => 'உள்நுழை';

  @override
  String get createAccount => 'கணக்கை உருவாக்கு';

  @override
  String get forgotPassword => 'கடவுச்சொல் மறந்துவிட்டதா?';

  @override
  String get registrationTitle => 'உங்கள் கணக்கை உருவாக்குங்கள்';

  @override
  String get displayName => 'காட்சிப் பெயர்';

  @override
  String get optionalMobileNumber => 'கைபேசி எண் (விருப்பம்)';

  @override
  String get mobileNumberPrivacyHint =>
      'உங்கள் கணக்கிற்காகத் தனிப்பட்ட முறையில் சேமிக்கப்படும். குறுஞ்செய்தி உள்நுழைவு இன்னும் இயக்கப்படவில்லை.';

  @override
  String get requiredField => 'இந்தப் புலம் அவசியம்.';

  @override
  String get usernameValidation =>
      '3–32 சிற்றெழுத்துகள், எண்கள், புள்ளிகள், அடிக்கோடுகள், சமக்குறிகள் அல்லது இணைப்புக்குறிகளைப் பயன்படுத்துங்கள்.';

  @override
  String passwordValidation(int count) {
    return 'குறைந்தது $count எழுத்துகளைப் பயன்படுத்துங்கள்.';
  }

  @override
  String get mobileNumberValidation =>
      'செல்லுபடியாகும் கைபேசி எண்ணை உள்ளிடுங்கள்.';

  @override
  String get signingIn => 'உள்நுழைகிறது…';

  @override
  String get creatingAccount => 'கணக்கை உருவாக்குகிறது…';

  @override
  String get invalidCredentials => 'பயனர்பெயர் அல்லது கடவுச்சொல் தவறானது.';

  @override
  String get registrationDisabled =>
      'புதிய கணக்குப் பதிவு தற்போது முடக்கப்பட்டுள்ளது.';

  @override
  String get usernameTaken => 'அந்தப் பயனர்பெயர் ஏற்கனவே பயன்பாட்டில் உள்ளது.';

  @override
  String get invalidUsername => 'அந்தப் பயனர்பெயர் அனுமதிக்கப்படவில்லை.';

  @override
  String get rateLimited =>
      'அதிக முயற்சிகள் செய்யப்பட்டன. சிறிது நேரம் கழித்து மீண்டும் முயலுங்கள்.';

  @override
  String get serverUnavailable =>
      'டிஜிட்டல்க்ரப் சாட் தற்போது சேவையகத்தை அணுக முடியவில்லை.';

  @override
  String get sessionExpired =>
      'உங்கள் அமர்வு காலாவதியானது. மீண்டும் உள்நுழையுங்கள்.';

  @override
  String get unknownAuthenticationError =>
      'அங்கீகாரம் தோல்வியடைந்தது. மீண்டும் முயலுங்கள்.';

  @override
  String get profileSetupIncomplete =>
      'உங்கள் கணக்கு உருவாக்கப்பட்டது, ஆனால் சில சுயவிவர விவரங்களைச் சேமிக்க முடியவில்லை.';

  @override
  String get startupFailed => 'டிஜிட்டல்க்ரப் சாட்டைத் தொடங்க முடியவில்லை.';

  @override
  String get retry => 'மீண்டும் முயல்';

  @override
  String get logOut => 'வெளியேறு';

  @override
  String get loggingOut => 'வெளியேறுகிறது…';

  @override
  String get logOutConfirmation =>
      'இந்தச் சாதனத்தில் டிஜிட்டல்க்ரப் சாட்டிலிருந்து வெளியேறவா?';

  @override
  String get cancel => 'ரத்துசெய்';

  @override
  String get chats => 'அரட்டைகள்';

  @override
  String get contacts => 'தொடர்புகள்';

  @override
  String get settings => 'அமைப்புகள்';

  @override
  String get startNewChat => 'புதிய அரட்டையைத் தொடங்கு';

  @override
  String get createGroup => 'குழுவை உருவாக்கு';

  @override
  String get noConversationsTitle => 'இன்னும் உரையாடல்கள் இல்லை';

  @override
  String get noConversationsBody =>
      'ஒருவரைக் கண்டறியுங்கள் அல்லது தனிப்பட்ட குழுவை உருவாக்குங்கள்.';

  @override
  String get findPeople => 'நபர்களைக் கண்டறி';

  @override
  String get noContactsTitle => 'உங்கள் தொடர்புகள் இங்கே தோன்றும்';

  @override
  String get noContactsBody => 'பயனர்பெயர் அல்லது காட்சிப் பெயரால் தேடுங்கள்.';

  @override
  String get appearance => 'தோற்றம்';

  @override
  String get notificationPreviews => 'செய்தி முன்னோட்டம்';

  @override
  String get notificationPreviewsSubtitle =>
      'அறிவிப்புகளில் அனுப்பியவர் பெயரையும் செய்தியையும் காட்டு';

  @override
  String get themeSystem => 'சாதன அமைப்பைப் பயன்படுத்து';

  @override
  String get themeLight => 'வெளிச்சம்';

  @override
  String get themeDark => 'இருள்';

  @override
  String get searchPeople => 'நபர்களைத் தேடு';

  @override
  String get newGroup => 'புதிய குழு';

  @override
  String get groupDetails => 'குழு விவரங்கள்';

  @override
  String get userProfile => 'பயனர் சுயவிவரம்';

  @override
  String get blockedUsers => 'தடுக்கப்பட்ட பயனர்கள்';

  @override
  String get close => 'மூடு';

  @override
  String get voiceRecord => 'குரல் செய்தி பதிவு';

  @override
  String get voicePlay => 'இயக்கு';

  @override
  String get voicePause => 'இடைநிறுத்து';

  @override
  String get voiceDiscard => 'பதிவை நீக்கு';

  @override
  String get voiceRecording => 'பதிவாகிறது…';

  @override
  String get voiceSendFailed => 'குரல் செய்தியை அனுப்ப முடியவில்லை.';

  @override
  String get newMeeting => 'புதிய கூட்டம்';

  @override
  String get meetingDefaultTitle => 'டிஜிட்டல்கிரப் கூட்டம்';

  @override
  String get meetingReady => 'உங்கள் கூட்டம் தயார்';

  @override
  String get meetingShareHint =>
      'இந்த இணைப்பைத் திறக்கும் குழு உறுப்பினர்கள் நேரடியாக கூட்டத்தில் சேருவார்கள்.';

  @override
  String get copyLink => 'இணைப்பை நகலெடு';

  @override
  String get linkCopied => 'இணைப்பு நகலெடுக்கப்பட்டது';

  @override
  String get emailInvite => 'மின்னஞ்சல் அழைப்பு';

  @override
  String get joinNow => 'இப்போது சேர்';

  @override
  String get meetingCreateFailed => 'கூட்டத்தை உருவாக்க முடியவில்லை.';

  @override
  String get meetJoining => 'கூட்டத்தில் சேர்கிறது…';

  @override
  String get meetLinkDead => 'இந்தக் கூட்ட இணைப்பு இனி செயல்படாது.';

  @override
  String get meetJoinFailed => 'கூட்டத்தில் சேர முடியவில்லை.';

  @override
  String get meetingInviteSubject =>
      'டிஜிட்டல்கிரப் சாட்டில் என் கூட்டத்தில் சேருங்கள்';

  @override
  String meetingInviteBody(String link) {
    return 'டிஜிட்டல்கிரப் சாட்டில் என் கூட்டத்தில் சேருங்கள்:\n\n$link\n\nஇணைப்பைத் திறந்து உள்நுழையுங்கள் — நேரடியாக அழைப்பில் சேர்வீர்கள்.';
  }

  @override
  String get startCall => 'குரல் அழைப்பு';

  @override
  String get startVideoCall => 'காணொளி அழைப்பு';

  @override
  String incomingCallFrom(String name) {
    return '$name அழைக்கிறார்';
  }

  @override
  String get callAcceptAudio => 'பதிலளி';

  @override
  String get callAcceptVideo => 'காணொளியுடன் பதிலளி';

  @override
  String get callDecline => 'நிராகரி';

  @override
  String get callHangUp => 'துண்டி';

  @override
  String get callMuteMic => 'ஒலி நிறுத்து';

  @override
  String get callUnmuteMic => 'ஒலி இயக்கு';

  @override
  String get callCameraOn => 'கேமரா இயக்கு';

  @override
  String get callCameraOff => 'கேமரா நிறுத்து';

  @override
  String get callSwitchCamera => 'கேமரா மாற்று';

  @override
  String get callSpeaker => 'ஒலிபெருக்கி';

  @override
  String readBy(String names) {
    return '$names படித்துள்ளார்';
  }

  @override
  String get mentionEveryoneHint =>
      'இந்தக் குழுவில் உள்ள அனைவருக்கும் அறிவிக்கும்';

  @override
  String get callReact => 'எமோஜி அனுப்பு';

  @override
  String get callShareScreen => 'திரையைப் பகிர்';

  @override
  String get callStopSharing => 'பகிர்வை நிறுத்து';

  @override
  String get callSomeoneSharing => 'ஒருவர் தங்கள் திரையைப் பகிர்கிறார்';

  @override
  String get callConnecting => 'இணைக்கிறது…';

  @override
  String get callReconnecting => 'மீண்டும் இணைக்கிறது…';

  @override
  String get callWaitingForOthers => 'மற்றவர்கள் சேரக் காத்திருக்கிறது…';

  @override
  String get callFailed => 'அழைப்பை இணைக்க முடியவில்லை.';

  @override
  String get callPermissionDenied =>
      'மைக் அல்லது கேமரா அனுமதி மறுக்கப்பட்டது. அழைப்புகளுக்கு அமைப்புகளில் அனுமதிக்கவும்.';

  @override
  String callParticipantCount(int count) {
    return 'அழைப்பில் $count பேர்';
  }

  @override
  String get messagesSection => 'செய்திகள்';

  @override
  String get noMessagesFound => 'செய்திகள் எதுவும் கிடைக்கவில்லை';

  @override
  String get messageSearchFailed => 'செய்தி தேடல் இப்போது கிடைக்கவில்லை.';

  @override
  String get attachmentUnavailable => 'படம் கிடைக்கவில்லை';

  @override
  String get attachmentFile => 'கோப்பு';

  @override
  String get attachmentPhoto => 'படம்';

  @override
  String get attachmentVideo => 'காணொளி';

  @override
  String get attachmentAudio => 'ஒலி';

  @override
  String get attachmentVoice => 'குரல் செய்தி';

  @override
  String get sendPhoto => 'படம்';

  @override
  String get sendFile => 'கோப்பு';

  @override
  String get takePhoto => 'கேமரா';

  @override
  String get attachmentTooLarge => 'இந்தக் கோப்பு அனுப்ப மிகப் பெரியது.';

  @override
  String get attachmentSendFailed => 'அந்தக் கோப்பை அனுப்ப முடியவில்லை.';

  @override
  String get searchConversations => 'உரையாடல்களைத் தேடு';

  @override
  String get noMatchingConversations =>
      'உங்கள் தேடலுக்குப் பொருந்தும் உரையாடல்கள் இல்லை.';

  @override
  String get noMessagesYet => 'இன்னும் செய்திகள் இல்லை';

  @override
  String get chatListFailed =>
      'சேமிக்கப்பட்ட உரையாடல்களைத் திறக்க முடியவில்லை.';

  @override
  String get peopleSearchHint => 'பெயர் அல்லது @பயனர்:சேவையகம்';

  @override
  String get peopleSearchInstructions =>
      'காட்சிப் பெயர் அல்லது பயனர்பெயர் மூலம் தேட குறைந்தது இரண்டு எழுத்துகளை உள்ளிடுங்கள்.';

  @override
  String get noPeopleFound => 'பயனர்கள் யாரும் கிடைக்கவில்லை.';

  @override
  String get peopleSearchFailed =>
      'பயனர் தேடல் தற்போது கிடைக்கவில்லை. மீண்டும் முயலுங்கள்.';

  @override
  String get messageInputHint => 'செய்தி';

  @override
  String get formatBold => 'தடிமன்';

  @override
  String get formatItalic => 'சாய்வு';

  @override
  String get formatStrikethrough => 'கோடிட்ட';

  @override
  String get formatCode => 'நிரல்';

  @override
  String get insertEmoji => 'சிரிப்பான் சேர்';

  @override
  String get emojiSearchHint => 'சிரிப்பான் தேடு';

  @override
  String get sendMessage => 'செய்தியை அனுப்பு';

  @override
  String get messageSendFailed =>
      'செய்தியை அனுப்ப முடியவில்லை. உங்கள் உரை மீட்டமைக்கப்பட்டது.';

  @override
  String get messageLoadFailed => 'இந்த உரையாடலைத் திறக்க முடியவில்லை.';

  @override
  String get messagesWaitingToSend => 'அனுப்பக் காத்திருக்கும் செய்திகள்';

  @override
  String get messagesFailedToSend => 'அனுப்ப முடியாத செய்திகள்';

  @override
  String get connecting => 'இணைக்கிறது…';

  @override
  String get synchronizing => 'ஒத்திசைக்கிறது…';

  @override
  String get online => 'இணையத்தில் உள்ளது';

  @override
  String get offlineCachedContent =>
      'இணையமில்லை — சேமிக்கப்பட்ட உரையாடல்கள் காட்டப்படுகின்றன';

  @override
  String get historyLoadFailed => 'பழைய செய்திகளை ஏற்ற முடியவில்லை.';

  @override
  String get reply => 'பதில்';

  @override
  String get react => 'எதிர்வினை';

  @override
  String get editMessage => 'செய்தியைத் திருத்து';

  @override
  String get deleteMessage => 'செய்தியை நீக்கு';

  @override
  String get copyMessage => 'நகலெடு';

  @override
  String get messageDetails => 'செய்தி விவரங்கள்';

  @override
  String get reportMessage => 'புகாரளி';

  @override
  String get deleteForMe => 'எனக்கு மட்டும் நீக்கு';

  @override
  String get deleteForEveryone => 'அனைவருக்கும் நீக்கு';

  @override
  String get deleteMessageConfirmation =>
      'இந்தச் செய்தியை எவ்வாறு நீக்க வேண்டும் என்பதைத் தேர்ந்தெடுக்கவும்.';

  @override
  String get copiedToClipboard => 'செய்தி நகலெடுக்கப்பட்டது.';

  @override
  String get edited => 'திருத்தப்பட்டது';

  @override
  String get messageDeleted => 'செய்தி நீக்கப்பட்டது';

  @override
  String get replyingTo => 'பதிலளிக்கிறது';

  @override
  String get editingMessage => 'செய்தியைத் திருத்துகிறது';

  @override
  String get typing => 'தட்டச்சு செய்கிறார்…';

  @override
  String get read => 'படிக்கப்பட்டது';

  @override
  String get chooseReaction => 'எதிர்வினையைத் தேர்ந்தெடுக்கவும்';

  @override
  String get messageActionFailed => 'அந்தச் செய்தி செயலை முடிக்க முடியவில்லை.';

  @override
  String get groupNameLabel => 'குழுவின் பெயர்';

  @override
  String get groupNameHint => 'தயாரிப்புக் குழு';

  @override
  String get groupDescriptionLabel => 'விளக்கம் (விருப்பம்)';

  @override
  String get groupDescriptionHint => 'இந்தக் குழு எதற்காக?';

  @override
  String get groupNameRequired => 'குழுவின் பெயரை உள்ளிடுங்கள்.';

  @override
  String groupNameTooLong(int count) {
    return 'குழுவின் பெயர் அதிகபட்சம் $count எழுத்துகள் இருக்கலாம்.';
  }

  @override
  String groupDescriptionTooLong(int count) {
    return 'விளக்கம் அதிகபட்சம் $count எழுத்துகள் இருக்கலாம்.';
  }

  @override
  String get addPeople => 'நபர்களைச் சேர்';

  @override
  String selectedCount(int count) {
    return '$count தேர்ந்தெடுக்கப்பட்டது';
  }

  @override
  String memberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count உறுப்பினர்கள்',
      one: '1 உறுப்பினர்',
    );
    return '$_temp0';
  }

  @override
  String get creatingGroup => 'குழுவை உருவாக்குகிறது…';

  @override
  String groupMemberLimitReached(int count) {
    return 'ஒரு குழுவில் அதிகபட்சம் $count நபர்கள் இருக்கலாம்.';
  }

  @override
  String get selectAtLeastOneMember =>
      'சேர்க்க குறைந்தது ஒருவரையாவது தேர்ந்தெடுங்கள்.';

  @override
  String get groupCreationFailed =>
      'குழுவை உருவாக்க முடியவில்லை. மீண்டும் முயலுங்கள்.';

  @override
  String get members => 'உறுப்பினர்கள்';

  @override
  String get addMembers => 'உறுப்பினர்களைச் சேர்';

  @override
  String get removeFromGroup => 'குழுவிலிருந்து நீக்கு';

  @override
  String removeMemberConfirmation(String name) {
    return '$name என்பவரை இந்தக் குழுவிலிருந்து நீக்கவா?';
  }

  @override
  String get remove => 'நீக்கு';

  @override
  String get leaveGroup => 'குழுவிலிருந்து வெளியேறு';

  @override
  String get leaveGroupConfirmation =>
      'இந்தக் குழுவிலிருந்து வெளியேறவா? இதன் செய்திகள் உங்களுக்கு வராது.';

  @override
  String get leave => 'வெளியேறு';

  @override
  String get editGroupName => 'குழுவின் பெயரைத் திருத்து';

  @override
  String get editGroupDescription => 'விளக்கத்தைத் திருத்து';

  @override
  String get save => 'சேமி';

  @override
  String get roleAdmin => 'நிர்வாகி';

  @override
  String get roleModerator => 'மட்டுறுத்துநர்';

  @override
  String get roleMember => 'உறுப்பினர்';

  @override
  String get changeRole => 'பங்கை மாற்று';

  @override
  String get invited => 'அழைக்கப்பட்டுள்ளார்';

  @override
  String get you => 'நீங்கள்';

  @override
  String get noGroupDescription => 'இன்னும் விளக்கம் இல்லை.';

  @override
  String get groupDetailsFailed => 'குழு விவரங்களைத் திறக்க முடியவில்லை.';

  @override
  String get groupUpdateFailed =>
      'அந்தக் குழு மாற்றத்தைச் சேமிக்க முடியவில்லை.';

  @override
  String get groupNotPermitted => 'அதைச் செய்ய உங்களுக்கு அனுமதி இல்லை.';

  @override
  String get groupNotFound => 'இந்தக் குழு இனி கிடைக்கவில்லை.';

  @override
  String get invitationsSent => 'அழைப்புகள் அனுப்பப்பட்டன.';

  @override
  String get myProfile => 'என் சுயவிவரம்';

  @override
  String get about => 'பற்றி';

  @override
  String get noAboutYet => 'இன்னும் விவரம் இல்லை.';

  @override
  String get matrixUsername => 'பயனர்பெயர்';

  @override
  String get mobileNumber => 'கைபேசி எண்';

  @override
  String get noMobileNumber => 'சேர்க்கப்படவில்லை';

  @override
  String get mobileNumberUnverified => 'சரிபார்க்கப்படவில்லை';

  @override
  String get changePhoto => 'படத்தை மாற்று';

  @override
  String get removePhoto => 'படத்தை நீக்கு';

  @override
  String get photoUpdated => 'படம் புதுப்பிக்கப்பட்டது.';

  @override
  String get photoTooLarge =>
      'அந்தப் படம் மிகப் பெரியது. சிறிய படத்தைத் தேர்ந்தெடுங்கள்.';

  @override
  String get photoPickFailed => 'அந்தப் படத்தைத் திறக்க முடியவில்லை.';

  @override
  String get displayNameRequired => 'காட்சிப் பெயரை உள்ளிடுங்கள்.';

  @override
  String aboutTooLong(int count) {
    return 'விவரம் அதிகபட்சம் $count எழுத்துகள் இருக்கலாம்.';
  }

  @override
  String get profileLoadFailed => 'இந்தச் சுயவிவரத்தைத் திறக்க முடியவில்லை.';

  @override
  String get profileUpdateFailed =>
      'அந்தச் சுயவிவர மாற்றத்தைச் சேமிக்க முடியவில்லை.';

  @override
  String get profileNotFound => 'அந்தப் பயனரைக் கண்டறிய முடியவில்லை.';

  @override
  String get sendMessageTo => 'செய்தி அனுப்பு';

  @override
  String get blockUser => 'பயனரைத் தடு';

  @override
  String get unblockUser => 'தடையை நீக்கு';

  @override
  String blockUserConfirmation(String name) {
    return '$name என்பவரைத் தடுக்கவா? அவர்களின் செய்திகள் உங்களுக்குத் தெரியாது, புதிய அரட்டைகளையும் தொடங்க முடியாது.';
  }

  @override
  String get block => 'தடு';

  @override
  String get userBlocked => 'பயனர் தடுக்கப்பட்டார்.';

  @override
  String get userUnblocked => 'பயனர் மீது தடை நீக்கப்பட்டது.';

  @override
  String get blockFailed => 'அந்தத் தடை மாற்றத்தைச் சேமிக்க முடியவில்லை.';

  @override
  String get noBlockedUsers => 'நீங்கள் யாரையும் தடுக்கவில்லை.';

  @override
  String get noBlockedUsersBody =>
      'நீங்கள் தடுக்கும் நபர்கள் இங்கே தோன்றுவார்கள்; பின்னர் தடையை நீக்கலாம்.';

  @override
  String get blockedUsersFailed => 'தடுக்கப்பட்ட பயனர்களை ஏற்ற முடியவில்லை.';

  @override
  String get blockedMessageHidden => 'தடுக்கப்பட்ட பயனரின் செய்தி';

  @override
  String get reportUser => 'பயனரைப் புகாரளி';

  @override
  String get reportCategory => 'என்ன பிரச்சினை?';

  @override
  String get reportSpam => 'தேவையற்ற செய்தி';

  @override
  String get reportHarassment => 'தொந்தரவு';

  @override
  String get reportAbuse => 'துஷ்பிரயோகம்';

  @override
  String get reportFraud => 'மோசடி';

  @override
  String get reportInappropriate => 'பொருத்தமற்ற உள்ளடக்கம்';

  @override
  String get reportOther => 'மற்றவை';

  @override
  String get reportComment => 'வேறு ஏதேனும் தெரிவிக்க வேண்டுமா? (விருப்பம்)';

  @override
  String get submitReport => 'புகாரைச் சமர்ப்பி';

  @override
  String get reportSubmitted => 'புகார் சமர்ப்பிக்கப்பட்டது. நன்றி.';

  @override
  String get reportFailed =>
      'புகாரைச் சமர்ப்பிக்க முடியவில்லை. மீண்டும் முயலுங்கள்.';

  @override
  String reportCommentTooLong(int count) {
    return 'கருத்து அதிகபட்சம் $count எழுத்துகள் இருக்கலாம்.';
  }

  @override
  String get alsoBlockUser => 'இந்தப் பயனரையும் தடு';

  @override
  String get deleteAccount => 'கணக்கை நீக்கு';

  @override
  String get deleteAccountWarning =>
      'இது உங்கள் டிஜிட்டல்க்ரப் சாட் கணக்கை நிரந்தரமாக நீக்கும். உங்கள் பயனர்பெயரை மீண்டும் பயன்படுத்த முடியாது; சேவையகத்தால் முடிந்தவரை உங்கள் செய்திகள் நீக்கப்படும். இதைத் திரும்பப் பெற முடியாது.';

  @override
  String get deleteAccountPasswordPrompt =>
      'உறுதிப்படுத்த உங்கள் கடவுச்சொல்லை உள்ளிடுங்கள்.';

  @override
  String get deletingAccount => 'கணக்கை நீக்குகிறது…';

  @override
  String get deleteAccountFailed =>
      'உங்கள் கணக்கை நீக்க முடியவில்லை. மீண்டும் முயலுங்கள்.';

  @override
  String get accountDeleted => 'உங்கள் கணக்கு நீக்கப்பட்டது.';

  @override
  String get confirmDelete => 'நீக்கு';

  @override
  String get contentAgreementTitle => 'எங்கள் சமூக விதிகள்';

  @override
  String get contentAgreementBody =>
      'டிஜிட்டல்க்ரப் சாட்டில் மற்றவர்கள் எழுதும் செய்திகள் இருக்கும். அவமதிப்பு, வெறுப்பு, சட்டவிரோத உள்ளடக்கம் அல்லது மற்றவர்களைத் தொந்தரவு செய்வது அனுமதிக்கப்படாது.';

  @override
  String get contentAgreementReport =>
      'இந்த விதிகளை மீறும் எந்தச் செய்தியையும் நபரையும் புகாரளியுங்கள். புகார்களை 24 மணி நேரத்திற்குள் பரிசீலித்து நடவடிக்கை எடுப்போம்.';

  @override
  String get contentAgreementBlock =>
      'உங்களுக்கு வேண்டாத நபர்களைத் தடுக்கலாம். அவர்களின் செய்திகள் உடனே உங்கள் செயலியிலிருந்து மறையும்.';

  @override
  String contentAgreementContact(String email) {
    return 'கேள்விகள் அல்லது கவலைகள்: $email';
  }

  @override
  String get contentAgreementAccept => 'ஒப்புக்கொள்கிறேன்';

  @override
  String get contentAgreementDecline => 'இப்போது வேண்டாம்';

  @override
  String get rulesConsent => 'சமூக விதிகளை ஏற்கிறேன்';

  @override
  String get rulesConsentRead => 'சமூக விதிகளைப் படிக்கவும்';

  @override
  String get contentAgreementRequired =>
      'செய்திகளை அனுப்பும் முன் சமூக விதிகளை ஏற்க வேண்டும்.';

  @override
  String invitedYou(String name) {
    return '$name உங்களை அரட்டைக்கு அழைத்துள்ளார்';
  }

  @override
  String get invitedYouGeneric => 'நீங்கள் அரட்டைக்கு அழைக்கப்பட்டுள்ளீர்கள்';

  @override
  String get acceptInvite => 'ஏற்றுக்கொள்';

  @override
  String get declineInvite => 'நிராகரி';

  @override
  String get declineInviteConfirmation =>
      'இந்த அழைப்பை நிராகரிக்கவா? அவர்களின் செய்திகள் உங்களுக்குத் தெரியாது.';

  @override
  String get inviteAccepted => 'அழைப்பு ஏற்கப்பட்டது.';

  @override
  String get inviteDeclined => 'அழைப்பு நிராகரிக்கப்பட்டது.';

  @override
  String get inviteActionFailed =>
      'அந்த அழைப்பைப் புதுப்பிக்க முடியவில்லை. மீண்டும் முயலுங்கள்.';

  @override
  String get newMessageNotification => 'புதிய செய்தி';

  @override
  String get newMessage => 'புதிய செய்தி';

  @override
  String get selectConversationTitle => 'ஒரு உரையாடலைத் தேர்ந்தெடுங்கள்';

  @override
  String get selectConversationBody =>
      'பட்டியலிலிருந்து ஒன்றைத் தேர்வுசெய்யுங்கள், அல்லது புதிதாக ஒன்றைத் தொடங்குங்கள்.';

  @override
  String get userManagement => 'பயனர் மேலாண்மை';

  @override
  String get inviteCodeLabel => 'அழைப்புக் குறியீடு';

  @override
  String get inviteCodeHint =>
      'உங்கள் நிர்வாகியிடம் குறியீடு கேட்கவும். Digitalgrub Chat அழைப்பு மூலம் மட்டுமே.';

  @override
  String get invalidInviteCode =>
      'அந்த அழைப்புக் குறியீடு செல்லாது அல்லது ஏற்கனவே பயன்படுத்தப்பட்டது.';

  @override
  String get refresh => 'புதுப்பிக்க';

  @override
  String userManagementCount(int total) {
    return '$total கணக்குகள்';
  }

  @override
  String get forwardMessage => 'பகிர்';

  @override
  String get forwardTo => 'யாருக்குப் பகிர';

  @override
  String get forwarded => 'பகிரப்பட்டது';

  @override
  String get forwardNoChats => 'பகிர வேறு அரட்டைகள் இல்லை.';

  @override
  String get forwardedLabel => 'பகிரப்பட்டது';

  @override
  String get pinMessage => 'பின் செய்';

  @override
  String get unpinMessage => 'பின் நீக்கு';

  @override
  String get pinnedMessage => 'பின் செய்யப்பட்ட செய்தி';

  @override
  String pinnedCount(int index, int total) {
    return 'பின் செய்யப்பட்டவை $index / $total';
  }

  @override
  String get pinNotAllowed =>
      'இந்த அரட்டையில் செய்திகளைப் பின் செய்ய உங்களுக்கு அனுமதி இல்லை. குழு நிர்வாகியை அணுகவும்.';

  @override
  String get pinFailed =>
      'பின் செய்யப்பட்ட செய்திகளை மாற்ற முடியவில்லை. மீண்டும் முயலவும்.';

  @override
  String get enableNotificationsPrompt =>
      'இந்த தாவல் பின்னணியில் இருக்கும்போது செய்தி வந்தால் அறிவிப்பு பெறுங்கள்.';

  @override
  String get enableNotifications => 'இயக்கு';

  @override
  String get notificationsBlocked =>
      'இந்த தளத்திற்கான அறிவிப்புகளை உங்கள் உலாவி தடுக்கிறது. அதன் தள அமைப்புகளில் இயக்கவும்.';

  @override
  String get dismiss => 'நிராகரி';

  @override
  String get returnToCall => 'உங்கள் அழைப்புக்குத் திரும்ப தட்டவும்';

  @override
  String get onACallNow => 'இப்போது அழைப்பில் உள்ளார்';

  @override
  String get joinCall => 'இணை';

  @override
  String liveCallParticipants(int count) {
    return 'அழைப்பில் $count பேர்';
  }

  @override
  String callStartedBy(String name) {
    return '$name அழைப்பைத் தொடங்கினார்';
  }

  @override
  String get youStartedCall => 'நீங்கள் அழைப்பைத் தொடங்கினீர்கள்';

  @override
  String get missedCall => 'தவறிய அழைப்பு';

  @override
  String get callBack => 'திரும்ப அழை';

  @override
  String get someoneInCall => 'ஒருவர் அழைப்பில் உள்ளார் — இணைய தட்டவும்';

  @override
  String get messageActions => 'மேலும்';

  @override
  String get meetGuestTitle => 'இந்த சந்திப்பில் இணையுங்கள்';

  @override
  String get meetGuestNameLabel => 'உங்கள் பெயர்';

  @override
  String get meetJoinAsGuest => 'சந்திப்பில் இணை';

  @override
  String get meetSignInInstead => 'பதிலாக உள்நுழையவும்';

  @override
  String get incomingCall => 'உள்வரும் அழைப்பு';

  @override
  String get groupActivity => 'செயல்பாடு';

  @override
  String get groupActivityEmpty => 'இங்கு இன்னும் எதுவும் நடக்கவில்லை.';

  @override
  String activityCreated(String name) {
    return '$name குழுவை உருவாக்கினார்';
  }

  @override
  String activityJoined(String name) {
    return '$name இணைந்தார்';
  }

  @override
  String activityLeft(String name) {
    return '$name வெளியேறினார்';
  }

  @override
  String activityInvited(String name, String target) {
    return '$name $target-ஐ அழைத்தார்';
  }

  @override
  String activityRemoved(String name, String target) {
    return '$name $target-ஐ நீக்கினார்';
  }

  @override
  String activityRenamed(String name, String detail) {
    return '$name குழுவிற்கு “$detail” எனப் பெயரிட்டார்';
  }

  @override
  String activityPhotoChanged(String name) {
    return '$name குழுப் படத்தை மாற்றினார்';
  }

  @override
  String activityCallStarted(String name) {
    return '$name அழைப்பைத் தொடங்கினார்';
  }

  @override
  String activityPinsChanged(String name) {
    return '$name பின் செய்யப்பட்ட செய்திகளை மாற்றினார்';
  }

  @override
  String activityRolesChanged(String name) {
    return '$name உறுப்பினர் பங்குகளை மாற்றினார்';
  }

  @override
  String get resetPasswordTitle => 'கடவுச்சொல்லை மீட்டமைக்கவும்';

  @override
  String get resetPasswordSubtitle =>
      'உங்கள் கணக்கின் மின்னஞ்சல் முகவரியை உள்ளிடவும்; இணைப்பை அனுப்புவோம்.';

  @override
  String get emailAddress => 'மின்னஞ்சல் முகவரி';

  @override
  String get emailValidation => 'சரியான மின்னஞ்சல் முகவரியை உள்ளிடவும்';

  @override
  String get sendResetLink => 'மீட்டமைப்பு இணைப்பை அனுப்பு';

  @override
  String get sendingResetLink => 'அனுப்புகிறது…';

  @override
  String get resetLinkSentTitle => 'மின்னஞ்சலைப் பாருங்கள்';

  @override
  String resetLinkSentBody(String email) {
    return '$email ஒரு கணக்கில் இருந்தால், இணைப்பு வந்துகொண்டிருக்கிறது. அதைத் திறந்து, திரும்பி வந்து புதிய கடவுச்சொல்லை அமைக்கவும்.';
  }

  @override
  String get resendResetLink => 'மீண்டும் அனுப்பு';

  @override
  String get resetLinkResent =>
      'மீண்டும் அனுப்பப்பட்டது. வர ஒரு நிமிடம் ஆகலாம்.';

  @override
  String get newPassword => 'புதிய கடவுச்சொல்';

  @override
  String get confirmNewPassword => 'புதிய கடவுச்சொல்லை உறுதிப்படுத்தவும்';

  @override
  String get passwordsDoNotMatch => 'இரண்டு கடவுச்சொற்களும் வேறுபடுகின்றன';

  @override
  String get setNewPassword => 'புதிய கடவுச்சொல்லை அமை';

  @override
  String get passwordResetDone =>
      'கடவுச்சொல் மாற்றப்பட்டது. புதியதைக் கொண்டு உள்நுழையவும்.';

  @override
  String get emailNotVerified =>
      'முதலில் மின்னஞ்சலில் உள்ள இணைப்பைத் திறக்கவும், பிறகு முயற்சிக்கவும்.';

  @override
  String get emailNotConfigured =>
      'இந்தச் சேவையகம் இன்னும் மின்னஞ்சல் அனுப்ப முடியாது. நிர்வாகியிடம் மீட்டமைக்கச் சொல்லுங்கள்.';

  @override
  String get emailInUse =>
      'அந்த முகவரியை வேறொரு கணக்கு ஏற்கனவே பயன்படுத்துகிறது.';

  @override
  String get emailAddresses => 'மின்னஞ்சல் முகவரி';

  @override
  String get emailAddressesSubtitle =>
      'கடவுச்சொல்லை மீட்டமைக்க மட்டுமே பயன்படும்';

  @override
  String get noEmailAddress =>
      'இன்னும் மின்னஞ்சல் முகவரி இல்லை. இல்லாவிட்டால், நிர்வாகி மட்டுமே கடவுச்சொல்லை மீட்டமைக்க முடியும்.';

  @override
  String get addEmailAddress => 'மின்னஞ்சல் முகவரியைச் சேர்';

  @override
  String get removeEmailAddress => 'நீக்கு';

  @override
  String get emailAddressAdded => 'மின்னஞ்சல் முகவரி சேர்க்கப்பட்டது.';

  @override
  String get emailAddressRemoved => 'மின்னஞ்சல் முகவரி நீக்கப்பட்டது.';

  @override
  String get confirmWithPassword => 'உங்கள் கடவுச்சொல்லால் உறுதிப்படுத்தவும்';

  @override
  String get currentPassword => 'தற்போதைய கடவுச்சொல்';

  @override
  String verifyEmailSent(String email) {
    return '$email க்கு இணைப்பு அனுப்பப்பட்டது. அதைத் திறந்து, கீழே உறுதிப்படுத்தவும்.';
  }

  @override
  String get confirmEmail => 'இணைப்பைத் திறந்துவிட்டேன்';

  @override
  String get callFullScreen => 'முழுத்திரை';

  @override
  String get callExitFullScreen => 'முழுத்திரையிலிருந்து வெளியேறு';

  @override
  String get callChat => 'அரட்டை';

  @override
  String get callCloseChat => 'அரட்டையை மூடு';

  @override
  String get callRaiseHand => 'கை உயர்த்து';

  @override
  String get callLowerHand => 'கையை இறக்கு';

  @override
  String get callPeople => 'பங்கேற்பாளர்கள்';

  @override
  String get callMute => 'ஒலியடக்கு';

  @override
  String get callMuteAll => 'அனைவரையும் ஒலியடக்கு';

  @override
  String get callHandRaised => 'கை உயர்த்தப்பட்டது';

  @override
  String callYou(String name) {
    return '$name (நீங்கள்)';
  }

  @override
  String get adminNewUser => 'புதிய பயனர்';

  @override
  String get adminNewUserTitle => 'கணக்கை உருவாக்கு';

  @override
  String get adminNewUserHint =>
      'இந்தப் பயனர்பெயர் மற்றும் கடவுச்சொல்லால் அவர்கள் உள்நுழைவார்கள். கடவுச்சொல்லை நீங்களே அவர்களிடம் சொல்லுங்கள்; அது எங்கும் அனுப்பப்படாது.';

  @override
  String get adminCreateUser => 'உருவாக்கு';

  @override
  String adminUserCreated(String userId) {
    return 'கணக்கு உருவாக்கப்பட்டது: $userId';
  }

  @override
  String get adminResetPassword => 'கடவுச்சொல்லை மீட்டமை';

  @override
  String adminResetPasswordTitle(String name) {
    return '$name க்கான கடவுச்சொல்லை மீட்டமை';
  }

  @override
  String get adminResetPasswordHint =>
      'அவர்களின் எல்லா அமர்வுகளும் வெளியேற்றப்படும். புதிய கடவுச்சொல்லை நீங்களே சொல்லுங்கள்.';

  @override
  String get adminPasswordReset =>
      'கடவுச்சொல் மீட்டமைக்கப்பட்டது. அவர்களின் அமர்வுகள் வெளியேற்றப்பட்டன.';

  @override
  String get adminNotAdmin =>
      'சேவையக நிர்வாகி மட்டுமே இதைச் செய்ய முடியும். நிர்வாகக் கணக்கில் மீண்டும் உள்நுழையவும்.';

  @override
  String get adminUsernameTaken => 'அந்தப் பயனர்பெயர் ஏற்கனவே உள்ளது.';

  @override
  String get adminAccountOnServer =>
      'நிர்வாகக் கணக்குகள் சேவையகத்தில் மட்டுமே மீட்டமைக்கப்படும்.';

  @override
  String get adminUserNotFound => 'அந்தப் பயனர்பெயரில் கணக்கு இல்லை.';

  @override
  String get adminUnavailable =>
      'இந்த உருவாக்கத்தில் நிர்வாக செயல்கள் முடக்கப்பட்டுள்ளன.';

  @override
  String get adminActions => 'மேலும்';

  @override
  String get presenceOnline => 'இணைப்பில்';

  @override
  String presenceLastSeen(String when) {
    return 'கடைசியாக $when';
  }

  @override
  String get meet => 'மீட்';

  @override
  String get joinWithCode => 'குறியீட்டால் சேர்';

  @override
  String get meetingCodeHint => 'கூட்ட இணைப்பு அல்லது குறியீட்டை ஒட்டவும்';

  @override
  String get meetingCodeInvalid => 'அது கூட்ட இணைப்போ குறியீடோ அல்ல.';

  @override
  String get shareLink => 'பகிர்';

  @override
  String get joinMeeting => 'சேர்';
}
