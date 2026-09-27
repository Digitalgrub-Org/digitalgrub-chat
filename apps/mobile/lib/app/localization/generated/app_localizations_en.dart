// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Digitalgrub Chat';

  @override
  String get appTagline => 'Your conversations, on your server.';

  @override
  String get onboardingFastTitle => 'Fast, focused conversations';

  @override
  String get onboardingFastBody =>
      'Move from a quick hello to a real conversation without getting in your way.';

  @override
  String get onboardingOfflineTitle => 'Messages stay close';

  @override
  String get onboardingOfflineBody =>
      'Open recent conversations and prepare replies even when your connection drops.';

  @override
  String get onboardingHostedTitle => 'Hosted by Digitalgrub';

  @override
  String get onboardingHostedBody =>
      'Your chat service runs on infrastructure controlled by Digitalgrub, not a paid chat platform.';

  @override
  String get skip => 'Skip';

  @override
  String get continueLabel => 'Continue';

  @override
  String get getStarted => 'Get started';

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to continue your conversations.';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get registrationTitle => 'Create your account';

  @override
  String get displayName => 'Display name';

  @override
  String get optionalMobileNumber => 'Mobile number (optional)';

  @override
  String get mobileNumberPrivacyHint =>
      'Stored privately for your account. SMS login is not enabled yet.';

  @override
  String get requiredField => 'This field is required.';

  @override
  String get usernameValidation =>
      'Use 3–32 lowercase letters, numbers, dots, underscores, equals signs, or hyphens.';

  @override
  String passwordValidation(int count) {
    return 'Use at least $count characters.';
  }

  @override
  String get mobileNumberValidation => 'Enter a valid mobile number.';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get creatingAccount => 'Creating account…';

  @override
  String get invalidCredentials => 'The username or password is incorrect.';

  @override
  String get registrationDisabled =>
      'New account registration is currently disabled.';

  @override
  String get usernameTaken => 'That username is already in use.';

  @override
  String get invalidUsername => 'That username is not allowed.';

  @override
  String get rateLimited => 'Too many attempts. Please try again shortly.';

  @override
  String get serverUnavailable =>
      'Digitalgrub Chat cannot reach the server right now.';

  @override
  String get sessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get unknownAuthenticationError =>
      'Authentication failed. Please try again.';

  @override
  String get profileSetupIncomplete =>
      'Your account was created, but some profile details could not be saved.';

  @override
  String get startupFailed => 'Digitalgrub Chat could not initialize.';

  @override
  String get retry => 'Retry';

  @override
  String get logOut => 'Log out';

  @override
  String get loggingOut => 'Logging out…';

  @override
  String get logOutConfirmation =>
      'Log out of Digitalgrub Chat on this device?';

  @override
  String get cancel => 'Cancel';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contacts';

  @override
  String get settings => 'Settings';

  @override
  String get startNewChat => 'Start new chat';

  @override
  String get createGroup => 'Create group';

  @override
  String get noConversationsTitle => 'No conversations yet';

  @override
  String get noConversationsBody =>
      'Find someone or create a private group to begin.';

  @override
  String get findPeople => 'Find people';

  @override
  String get noContactsTitle => 'Your people will appear here';

  @override
  String get noContactsBody => 'Search by username or display name.';

  @override
  String get appearance => 'Appearance';

  @override
  String get notificationPreviews => 'Message previews';

  @override
  String get notificationPreviewsSubtitle =>
      'Show who wrote and what they said in notifications';

  @override
  String get themeSystem => 'Use device setting';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get searchPeople => 'Search people';

  @override
  String get newGroup => 'New group';

  @override
  String get groupDetails => 'Group details';

  @override
  String get userProfile => 'User profile';

  @override
  String get blockedUsers => 'Blocked users';

  @override
  String get close => 'Close';

  @override
  String get voiceRecord => 'Record a voice message';

  @override
  String get voicePlay => 'Play';

  @override
  String get voicePause => 'Pause';

  @override
  String get voiceDiscard => 'Discard recording';

  @override
  String get voiceRecording => 'Recording…';

  @override
  String get voiceSendFailed => 'Could not send the voice message.';

  @override
  String get newMeeting => 'New meeting';

  @override
  String get meetingDefaultTitle => 'Digitalgrub meeting';

  @override
  String get meetingReady => 'Your meeting is ready';

  @override
  String get meetingShareHint =>
      'Anyone on the team who opens this link joins the meeting.';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get emailInvite => 'Email invite';

  @override
  String get joinNow => 'Join now';

  @override
  String get meetingCreateFailed => 'Could not create the meeting.';

  @override
  String get meetJoining => 'Joining the meeting…';

  @override
  String get meetLinkDead => 'This meeting link does not work any more.';

  @override
  String get meetJoinFailed => 'Could not join the meeting.';

  @override
  String get meetingInviteSubject => 'Join my meeting on Digitalgrub Chat';

  @override
  String meetingInviteBody(String link) {
    return 'Join my meeting on Digitalgrub Chat:\n\n$link\n\nOpen the link and sign in — you will land straight in the call.';
  }

  @override
  String get startCall => 'Voice call';

  @override
  String get startVideoCall => 'Video call';

  @override
  String incomingCallFrom(String name) {
    return '$name is calling';
  }

  @override
  String get callAcceptAudio => 'Answer';

  @override
  String get callAcceptVideo => 'Answer with video';

  @override
  String get callDecline => 'Decline';

  @override
  String get callHangUp => 'Hang up';

  @override
  String get callMuteMic => 'Mute';

  @override
  String get callUnmuteMic => 'Unmute';

  @override
  String get callCameraOn => 'Camera on';

  @override
  String get callCameraOff => 'Camera off';

  @override
  String get callSwitchCamera => 'Switch camera';

  @override
  String get callSpeaker => 'Speaker';

  @override
  String readBy(String names) {
    return 'Read by $names';
  }

  @override
  String get mentionEveryoneHint => 'Notifies everyone in this group';

  @override
  String get callReact => 'React';

  @override
  String get callShareScreen => 'Share screen';

  @override
  String get callStopSharing => 'Stop sharing';

  @override
  String get callSomeoneSharing => 'Someone is sharing their screen';

  @override
  String get callConnecting => 'Connecting…';

  @override
  String get callReconnecting => 'Reconnecting…';

  @override
  String get callWaitingForOthers => 'Waiting for others to join…';

  @override
  String get callFailed => 'The call could not be connected.';

  @override
  String get callPermissionDenied =>
      'Microphone or camera access was denied. Allow it in system settings to make calls.';

  @override
  String callParticipantCount(int count) {
    return '$count in call';
  }

  @override
  String get messagesSection => 'Messages';

  @override
  String get noMessagesFound => 'No messages found';

  @override
  String get messageSearchFailed => 'Message search is unavailable right now.';

  @override
  String get attachmentUnavailable => 'Image unavailable';

  @override
  String get attachmentFile => 'File';

  @override
  String get attachmentPhoto => 'Photo';

  @override
  String get attachmentVideo => 'Video';

  @override
  String get attachmentAudio => 'Audio';

  @override
  String get attachmentVoice => 'Voice message';

  @override
  String get sendPhoto => 'Photo';

  @override
  String get sendFile => 'File';

  @override
  String get takePhoto => 'Camera';

  @override
  String get attachmentTooLarge => 'That file is too large to send.';

  @override
  String get attachmentSendFailed => 'Could not send that file.';

  @override
  String get searchConversations => 'Search conversations';

  @override
  String get noMatchingConversations => 'No conversations match your search.';

  @override
  String get noMessagesYet => 'No messages yet';

  @override
  String get chatListFailed => 'Your cached conversations could not be opened.';

  @override
  String get peopleSearchHint => 'Name or @username:server';

  @override
  String get peopleSearchInstructions =>
      'Enter at least two characters to find someone by display name or username.';

  @override
  String get noPeopleFound => 'No people found.';

  @override
  String get peopleSearchFailed =>
      'People search is unavailable right now. Please try again.';

  @override
  String get messageInputHint => 'Message';

  @override
  String get formatBold => 'Bold';

  @override
  String get formatItalic => 'Italic';

  @override
  String get formatStrikethrough => 'Strikethrough';

  @override
  String get formatCode => 'Code';

  @override
  String get insertEmoji => 'Insert emoji';

  @override
  String get emojiSearchHint => 'Search emoji';

  @override
  String get sendMessage => 'Send message';

  @override
  String get messageSendFailed =>
      'Message could not be sent. Your text has been restored.';

  @override
  String get messageLoadFailed => 'This conversation could not be opened.';

  @override
  String get messagesWaitingToSend => 'Messages waiting to send';

  @override
  String get messagesFailedToSend => 'Messages failed to send';

  @override
  String get connecting => 'Connecting…';

  @override
  String get synchronizing => 'Synchronizing…';

  @override
  String get online => 'Online';

  @override
  String get offlineCachedContent => 'Offline — showing saved conversations';

  @override
  String get historyLoadFailed => 'Older messages could not be loaded.';

  @override
  String get reply => 'Reply';

  @override
  String get react => 'React';

  @override
  String get editMessage => 'Edit message';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get copyMessage => 'Copy';

  @override
  String get messageDetails => 'Message details';

  @override
  String get reportMessage => 'Report';

  @override
  String get deleteForMe => 'Delete for me';

  @override
  String get deleteForEveryone => 'Delete for everyone';

  @override
  String get deleteMessageConfirmation =>
      'Choose how this message should be removed.';

  @override
  String get copiedToClipboard => 'Message copied.';

  @override
  String get edited => 'edited';

  @override
  String get messageDeleted => 'Message deleted';

  @override
  String get replyingTo => 'Replying to';

  @override
  String get editingMessage => 'Editing message';

  @override
  String get typing => 'typing…';

  @override
  String get read => 'Read';

  @override
  String get chooseReaction => 'Choose a reaction';

  @override
  String get messageActionFailed =>
      'That message action could not be completed.';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get groupNameHint => 'Product crew';

  @override
  String get groupDescriptionLabel => 'Description (optional)';

  @override
  String get groupDescriptionHint => 'What is this group for?';

  @override
  String get groupNameRequired => 'Enter a group name.';

  @override
  String groupNameTooLong(int count) {
    return 'Group names can be at most $count characters.';
  }

  @override
  String groupDescriptionTooLong(int count) {
    return 'Descriptions can be at most $count characters.';
  }

  @override
  String get addPeople => 'Add people';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String memberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get creatingGroup => 'Creating group…';

  @override
  String groupMemberLimitReached(int count) {
    return 'A group can hold up to $count people.';
  }

  @override
  String get selectAtLeastOneMember => 'Select at least one person to add.';

  @override
  String get groupCreationFailed =>
      'The group could not be created. Please try again.';

  @override
  String get members => 'Members';

  @override
  String get addMembers => 'Add members';

  @override
  String get removeFromGroup => 'Remove from group';

  @override
  String removeMemberConfirmation(String name) {
    return 'Remove $name from this group?';
  }

  @override
  String get remove => 'Remove';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get leaveGroupConfirmation =>
      'Leave this group? You will stop receiving its messages.';

  @override
  String get leave => 'Leave';

  @override
  String get editGroupName => 'Edit group name';

  @override
  String get editGroupDescription => 'Edit description';

  @override
  String get save => 'Save';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleModerator => 'Moderator';

  @override
  String get roleMember => 'Member';

  @override
  String get changeRole => 'Change role';

  @override
  String get invited => 'Invited';

  @override
  String get you => 'You';

  @override
  String get noGroupDescription => 'No description yet.';

  @override
  String get groupDetailsFailed => 'Group details could not be opened.';

  @override
  String get groupUpdateFailed => 'That group change could not be saved.';

  @override
  String get groupNotPermitted => 'You do not have permission to do that.';

  @override
  String get groupNotFound => 'This group is no longer available.';

  @override
  String get invitationsSent => 'Invitations sent.';

  @override
  String get myProfile => 'My profile';

  @override
  String get about => 'About';

  @override
  String get noAboutYet => 'No about text yet.';

  @override
  String get matrixUsername => 'Username';

  @override
  String get mobileNumber => 'Mobile number';

  @override
  String get noMobileNumber => 'Not added';

  @override
  String get mobileNumberUnverified => 'Not verified';

  @override
  String get changePhoto => 'Change photo';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String get photoUpdated => 'Photo updated.';

  @override
  String get photoTooLarge => 'That image is too large. Choose a smaller one.';

  @override
  String get photoPickFailed => 'That image could not be opened.';

  @override
  String get displayNameRequired => 'Enter a display name.';

  @override
  String aboutTooLong(int count) {
    return 'About text can be at most $count characters.';
  }

  @override
  String get profileLoadFailed => 'This profile could not be opened.';

  @override
  String get profileUpdateFailed => 'That profile change could not be saved.';

  @override
  String get profileNotFound => 'That user could not be found.';

  @override
  String get sendMessageTo => 'Message';

  @override
  String get blockUser => 'Block user';

  @override
  String get unblockUser => 'Unblock';

  @override
  String blockUserConfirmation(String name) {
    return 'Block $name? You will stop seeing their messages and they cannot start new chats with you.';
  }

  @override
  String get block => 'Block';

  @override
  String get userBlocked => 'User blocked.';

  @override
  String get userUnblocked => 'User unblocked.';

  @override
  String get blockFailed => 'That block change could not be saved.';

  @override
  String get noBlockedUsers => 'You have not blocked anyone.';

  @override
  String get noBlockedUsersBody =>
      'People you block will appear here so you can unblock them later.';

  @override
  String get blockedUsersFailed => 'Your blocked users could not be loaded.';

  @override
  String get blockedMessageHidden => 'Message from a blocked user';

  @override
  String get reportUser => 'Report user';

  @override
  String get reportCategory => 'What is the problem?';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportHarassment => 'Harassment';

  @override
  String get reportAbuse => 'Abuse';

  @override
  String get reportFraud => 'Fraud';

  @override
  String get reportInappropriate => 'Inappropriate content';

  @override
  String get reportOther => 'Other';

  @override
  String get reportComment => 'Anything else we should know? (optional)';

  @override
  String get submitReport => 'Submit report';

  @override
  String get reportSubmitted => 'Report submitted. Thank you.';

  @override
  String get reportFailed =>
      'That report could not be submitted. Please try again.';

  @override
  String reportCommentTooLong(int count) {
    return 'Comments can be at most $count characters.';
  }

  @override
  String get alsoBlockUser => 'Also block this user';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountWarning =>
      'This permanently deletes your Digitalgrub Chat account. Your username can never be used again, and your messages will be removed where the server is able to remove them. This cannot be undone.';

  @override
  String get deleteAccountPasswordPrompt => 'Enter your password to confirm.';

  @override
  String get deletingAccount => 'Deleting account…';

  @override
  String get deleteAccountFailed =>
      'Your account could not be deleted. Please try again.';

  @override
  String get accountDeleted => 'Your account has been deleted.';

  @override
  String get confirmDelete => 'Delete';

  @override
  String get contentAgreementTitle => 'Our community rules';

  @override
  String get contentAgreementBody =>
      'Digitalgrub Chat carries messages written by other people. There is no tolerance for abusive, hateful, or illegal content, or for harassing other members.';

  @override
  String get contentAgreementReport =>
      'Report any message or person that breaks these rules. We review reports and act within 24 hours.';

  @override
  String get contentAgreementBlock =>
      'Block anyone you do not want to hear from. Their messages disappear from your app immediately.';

  @override
  String contentAgreementContact(String email) {
    return 'Questions or concerns: $email';
  }

  @override
  String get contentAgreementAccept => 'I agree';

  @override
  String get contentAgreementDecline => 'Not now';

  @override
  String get rulesConsent => 'I agree to the community rules';

  @override
  String get rulesConsentRead => 'Read the community rules';

  @override
  String get contentAgreementRequired =>
      'You need to accept the community rules before sending messages.';

  @override
  String invitedYou(String name) {
    return '$name invited you to chat';
  }

  @override
  String get invitedYouGeneric => 'You have been invited to chat';

  @override
  String get acceptInvite => 'Accept';

  @override
  String get declineInvite => 'Decline';

  @override
  String get declineInviteConfirmation =>
      'Decline this invitation? You will not see their messages.';

  @override
  String get inviteAccepted => 'Invitation accepted.';

  @override
  String get inviteDeclined => 'Invitation declined.';

  @override
  String get inviteActionFailed =>
      'That invitation could not be updated. Please try again.';

  @override
  String get newMessageNotification => 'New message';

  @override
  String get newMessage => 'New message';

  @override
  String get selectConversationTitle => 'Pick up a conversation';

  @override
  String get selectConversationBody =>
      'Choose one from the list, or start a new one.';

  @override
  String get userManagement => 'User management';

  @override
  String get inviteCodeLabel => 'Invite code';

  @override
  String get inviteCodeHint =>
      'Ask your admin for a code. Digitalgrub Chat is invite-only.';

  @override
  String get invalidInviteCode =>
      'That invite code isn\'t valid or has already been used.';

  @override
  String get refresh => 'Refresh';

  @override
  String userManagementCount(int total) {
    return '$total accounts';
  }

  @override
  String get forwardMessage => 'Forward';

  @override
  String get forwardTo => 'Forward to';

  @override
  String get forwarded => 'Forwarded';

  @override
  String get forwardNoChats => 'No other chats to forward to.';

  @override
  String get forwardedLabel => 'Forwarded';

  @override
  String get pinMessage => 'Pin';

  @override
  String get unpinMessage => 'Unpin';

  @override
  String get pinnedMessage => 'Pinned message';

  @override
  String pinnedCount(int index, int total) {
    return 'Pinned $index of $total';
  }

  @override
  String get pinNotAllowed =>
      'You don\'t have permission to pin messages in this chat. Ask a group admin.';

  @override
  String get pinFailed => 'Couldn\'t change the pinned messages. Try again.';

  @override
  String get enableNotificationsPrompt =>
      'Get notified when a message arrives while this tab is in the background.';

  @override
  String get enableNotifications => 'Turn on';

  @override
  String get notificationsBlocked =>
      'Your browser is blocking notifications for this site. Turn them on in its site settings.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get returnToCall => 'Tap to return to your call';

  @override
  String get onACallNow => 'On a call now';

  @override
  String get joinCall => 'Join';

  @override
  String liveCallParticipants(int count) {
    return '$count on the call';
  }

  @override
  String callStartedBy(String name) {
    return '$name started a call';
  }

  @override
  String get youStartedCall => 'You started a call';

  @override
  String get missedCall => 'Missed call';

  @override
  String get callBack => 'Call back';

  @override
  String get someoneInCall => 'Someone\'s in a call — tap to join';

  @override
  String get messageActions => 'More';

  @override
  String get meetGuestTitle => 'Join this meeting';

  @override
  String get meetGuestNameLabel => 'Your name';

  @override
  String get meetJoinAsGuest => 'Join meeting';

  @override
  String get meetSignInInstead => 'Sign in instead';

  @override
  String get incomingCall => 'Incoming call';

  @override
  String get groupActivity => 'Activity';

  @override
  String get groupActivityEmpty => 'Nothing has happened here yet.';

  @override
  String activityCreated(String name) {
    return '$name created the group';
  }

  @override
  String activityJoined(String name) {
    return '$name joined';
  }

  @override
  String activityLeft(String name) {
    return '$name left';
  }

  @override
  String activityInvited(String name, String target) {
    return '$name invited $target';
  }

  @override
  String activityRemoved(String name, String target) {
    return '$name removed $target';
  }

  @override
  String activityRenamed(String name, String detail) {
    return '$name named the group “$detail”';
  }

  @override
  String activityPhotoChanged(String name) {
    return '$name changed the group photo';
  }

  @override
  String activityCallStarted(String name) {
    return '$name started a call';
  }

  @override
  String activityPinsChanged(String name) {
    return '$name changed the pinned messages';
  }

  @override
  String activityRolesChanged(String name) {
    return '$name changed member roles';
  }

  @override
  String get resetPasswordTitle => 'Reset your password';

  @override
  String get resetPasswordSubtitle =>
      'Enter the email address on your account and we will send you a link.';

  @override
  String get emailAddress => 'Email address';

  @override
  String get emailValidation => 'Enter a valid email address';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get sendingResetLink => 'Sending…';

  @override
  String get resetLinkSentTitle => 'Check your email';

  @override
  String resetLinkSentBody(String email) {
    return 'If $email is on an account, a link is on its way. Open it, then come back here and set your new password.';
  }

  @override
  String get resendResetLink => 'Send it again';

  @override
  String get resetLinkResent => 'Sent again. It can take a minute to arrive.';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get passwordsDoNotMatch => 'Those two passwords are different';

  @override
  String get setNewPassword => 'Set new password';

  @override
  String get passwordResetDone => 'Password changed. Sign in with the new one.';

  @override
  String get emailNotVerified =>
      'Open the link in the email first, then try again.';

  @override
  String get emailNotConfigured =>
      'This server cannot send email yet. Ask your admin to reset it for you.';

  @override
  String get emailInUse => 'Another account already uses that address.';

  @override
  String get emailAddresses => 'Email address';

  @override
  String get emailAddressesSubtitle => 'Used only to reset your password';

  @override
  String get noEmailAddress =>
      'No email address yet. Without one, only an admin can reset your password.';

  @override
  String get addEmailAddress => 'Add email address';

  @override
  String get removeEmailAddress => 'Remove';

  @override
  String get emailAddressAdded => 'Email address added.';

  @override
  String get emailAddressRemoved => 'Email address removed.';

  @override
  String get confirmWithPassword => 'Confirm with your password';

  @override
  String get currentPassword => 'Current password';

  @override
  String verifyEmailSent(String email) {
    return 'We sent a link to $email. Open it, then confirm below.';
  }

  @override
  String get confirmEmail => 'I have opened the link';

  @override
  String get callFullScreen => 'Full screen';

  @override
  String get callExitFullScreen => 'Exit full screen';

  @override
  String get callChat => 'Chat';

  @override
  String get callCloseChat => 'Close chat';

  @override
  String get callRaiseHand => 'Raise hand';

  @override
  String get callLowerHand => 'Lower hand';

  @override
  String get callPeople => 'People';

  @override
  String get callMute => 'Mute';

  @override
  String get callMuteAll => 'Mute all';

  @override
  String get callHandRaised => 'Hand raised';

  @override
  String callYou(String name) {
    return '$name (you)';
  }

  @override
  String get adminNewUser => 'New user';

  @override
  String get adminNewUserTitle => 'Create an account';

  @override
  String get adminNewUserHint =>
      'They sign in with this username and password. Share the password with them yourself; it is not sent anywhere.';

  @override
  String get adminCreateUser => 'Create';

  @override
  String adminUserCreated(String userId) {
    return 'Account created: $userId';
  }

  @override
  String get adminResetPassword => 'Reset password';

  @override
  String adminResetPasswordTitle(String name) {
    return 'Reset password for $name';
  }

  @override
  String get adminResetPasswordHint =>
      'Every session they have is signed out. Tell them the new password yourself.';

  @override
  String get adminPasswordReset =>
      'Password reset. Their sessions were signed out.';

  @override
  String get adminNotAdmin =>
      'Only a server admin can do this. Sign in again as the admin account.';

  @override
  String get adminUsernameTaken => 'Somebody already has that username.';

  @override
  String get adminAccountOnServer =>
      'Admin accounts are reset on the server, not from here.';

  @override
  String get adminUserNotFound => 'No account with that username.';

  @override
  String get adminUnavailable =>
      'Admin actions are switched off in this build.';

  @override
  String get adminActions => 'More';

  @override
  String get presenceOnline => 'Online';

  @override
  String presenceLastSeen(String when) {
    return 'Last seen $when';
  }

  @override
  String get meet => 'Meet';

  @override
  String get joinWithCode => 'Join with a code';

  @override
  String get meetingCodeHint => 'Paste a meeting link or code';

  @override
  String get meetingCodeInvalid => 'That is not a meeting link or code.';

  @override
  String get shareLink => 'Share';

  @override
  String get joinMeeting => 'Join';
}
