import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/core/widgets/brand_mark.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/moderation/presentation/content_agreement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuthenticationScreen extends ConsumerStatefulWidget {
  const AuthenticationScreen({super.key, this.isRegistration = false});

  final bool isRegistration;

  @override
  ConsumerState<AuthenticationScreen> createState() =>
      _AuthenticationScreenState();
}

class _AuthenticationScreenState extends ConsumerState<AuthenticationScreen> {
  static final _usernamePattern = RegExp(r'^[a-z0-9._=-]{3,32}$');
  static final _mobileNumberPattern = RegExp(r'^\+?[0-9]{7,15}$');

  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mobileNumberController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _obscurePassword = true;

  /// App Review guideline 1.2 wants the rules agreed to *before* registering
  /// or signing in, not at the first message. Deliberately never remembered
  /// across a fresh install: a reviewer opening the app has to be able to see
  /// it, and so does anyone signing in on a phone that is not theirs.
  bool _agreedToRules = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _mobileNumberController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;
    // The button is disabled without this, so reaching here means something
    // bypassed it -- a hardware keyboard's Enter, for one.
    if (!_agreedToRules) return;

    final controller = ref.read(authControllerProvider.notifier);
    final session = widget.isRegistration
        ? await controller.register(
            RegistrationRequest(
              username: _usernameController.text.trim(),
              password: _passwordController.text,
              displayName: _displayNameController.text.trim(),
              mobileNumber: _mobileNumberController.text.trim(),
              inviteCode: _inviteCodeController.text.trim(),
            ),
          )
        : await controller.login(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );

    if (!mounted) return;
    if (session != null) {
      // Accepted here, so the composer's own check never asks a second time.
      await ref.read(appPreferencesProvider).acceptContentAgreement();
      if (!mounted) return;
      if (session.profileSetupIncomplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.profileSetupIncomplete)),
        );
      }
      // An emailed meeting link must survive the sign-in it forced. Only
      // in-app destinations are honoured; anything else falls back to chats.
      final next = GoRouterState.of(context).uri.queryParameters['next'];
      context.go(
        next != null && next.startsWith('/') && !next.startsWith('//')
            ? next
            : AppRoutes.chats,
      );
      return;
    }

    final error = ref.read(authControllerProvider).error;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_errorMessage(context.l10n, error))));
  }

  /// Opens the rules. Agreeing in the sheet ticks the box, so somebody who
  /// reads them does not then have to find the checkbox as well.
  Future<void> _readRules() async {
    final accepted = await showContentAgreement(context);
    if (!mounted || !accepted) return;
    setState(() => _agreedToRules = true);
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty
        ? context.l10n.requiredField
        : null;
  }

  String? _validateUsername(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    if (widget.isRegistration && !_usernamePattern.hasMatch(value!.trim())) {
      return context.l10n.usernameValidation;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final requiredError = _required(value);
    if (requiredError != null || !widget.isRegistration) return requiredError;

    // Must not exceed what the homeserver's password policy accepts, or
    // registration fails after the form has already passed. See
    // `password_config` in deploy/synapse/render_config.py.
    if (value!.length < minimumPasswordLength) {
      return context.l10n.passwordValidation(minimumPasswordLength);
    }
    return null;
  }

  String? _validateMobileNumber(String? value) {
    final mobileNumber = value?.trim() ?? '';
    if (mobileNumber.isEmpty) return null;
    return _mobileNumberPattern.hasMatch(mobileNumber)
        ? null
        : context.l10n.mobileNumberValidation;
  }

  String _errorMessage(AppLocalizations l10n, Object? error) {
    if (error is! AuthFailure) return l10n.unknownAuthenticationError;
    return switch (error.code) {
      AuthFailureCode.invalidCredentials => l10n.invalidCredentials,
      AuthFailureCode.registrationDisabled => l10n.registrationDisabled,
      AuthFailureCode.emailUnsupported => l10n.emailNotConfigured,
      // Deliberately the same wording as success on the reset screen; here it
      // can only be reached by a code path that already knows the account.
      AuthFailureCode.emailUnknown => l10n.invalidCredentials,
      AuthFailureCode.emailNotVerified => l10n.emailNotVerified,
      AuthFailureCode.emailInUse => l10n.emailInUse,
      AuthFailureCode.invalidInviteCode => l10n.invalidInviteCode,
      AuthFailureCode.usernameTaken => l10n.usernameTaken,
      AuthFailureCode.invalidUsername => l10n.invalidUsername,
      AuthFailureCode.rateLimited => l10n.rateLimited,
      AuthFailureCode.serverUnavailable => l10n.serverUnavailable,
      AuthFailureCode.sessionExpired => l10n.sessionExpired,
      AuthFailureCode.unknown => l10n.unknownAuthenticationError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isRegistration = widget.isRegistration;
    final isSubmitting = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: isRegistration ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(child: BrandMark(size: 64)),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        isRegistration
                            ? context.l10n.registrationTitle
                            : context.l10n.loginTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (!isRegistration)
                        Text(
                          context.l10n.loginSubtitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      const SizedBox(height: AppSpacing.xl),
                      if (isRegistration) ...[
                        TextFormField(
                          controller: _displayNameController,
                          // Credentials are exact strings; handwriting recognition on them
                          // is guesswork, and the panel covers the form while you correct it.
                          stylusHandwritingEnabled: false,
                          enabled: !isSubmitting,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          decoration: InputDecoration(
                            labelText: context.l10n.displayName,
                            prefixIcon: const Icon(Icons.badge_outlined),
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      TextFormField(
                        controller: _usernameController,
                        // Credentials are exact strings; handwriting recognition on them
                        // is guesswork, and the panel covers the form while you correct it.
                        stylusHandwritingEnabled: false,
                        enabled: !isSubmitting,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: InputDecoration(
                          labelText: context.l10n.username,
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                        ),
                        validator: _validateUsername,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _passwordController,
                        // Credentials are exact strings; handwriting recognition on them
                        // is guesswork, and the panel covers the form while you correct it.
                        stylusHandwritingEnabled: false,
                        enabled: !isSubmitting,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          isRegistration
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onFieldSubmitted: isRegistration
                            ? null
                            : (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: context.l10n.password,
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: context.l10n.password,
                            onPressed: isSubmitting
                                ? null
                                : () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      if (isRegistration) ...[
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _mobileNumberController,
                          // Credentials are exact strings; handwriting recognition on them
                          // is guesswork, and the panel covers the form while you correct it.
                          stylusHandwritingEnabled: false,
                          enabled: !isSubmitting,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: InputDecoration(
                            labelText: context.l10n.optionalMobileNumber,
                            helperText: context.l10n.mobileNumberPrivacyHint,
                            helperMaxLines: 2,
                            prefixIcon: const Icon(Icons.phone_outlined),
                          ),
                          validator: _validateMobileNumber,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _inviteCodeController,
                          // Credentials are exact strings; handwriting recognition on them
                          // is guesswork, and the panel covers the form while you correct it.
                          stylusHandwritingEnabled: false,
                          enabled: !isSubmitting,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: context.l10n.inviteCodeLabel,
                            helperText: context.l10n.inviteCodeHint,
                            helperMaxLines: 2,
                            prefixIcon: const Icon(Icons.vpn_key_outlined),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? context.l10n.requiredField
                              : null,
                        ),
                      ],
                      if (!isRegistration)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => context.push(AppRoutes.passwordReset),
                            child: Text(context.l10n.forgotPassword),
                          ),
                        )
                      else
                        const SizedBox(height: AppSpacing.lg),
                      _RulesConsent(
                        agreed: _agreedToRules,
                        enabled: !isSubmitting,
                        onChanged: (value) =>
                            setState(() => _agreedToRules = value),
                        onRead: _readRules,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        onPressed: isSubmitting || !_agreedToRules
                            ? null
                            : _submit,
                        child: Text(
                          isSubmitting
                              ? isRegistration
                                    ? context.l10n.creatingAccount
                                    : context.l10n.signingIn
                              : isRegistration
                              ? context.l10n.createAccount
                              : context.l10n.signIn,
                        ),
                      ),
                      if (!isRegistration) ...[
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton(
                          onPressed: isSubmitting
                              ? null
                              : () => context.push(AppRoutes.register),
                          child: Text(context.l10n.createAccount),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rules tick-box that gates signing in and registering.
class _RulesConsent extends StatelessWidget {
  const _RulesConsent({
    required this.agreed,
    required this.enabled,
    required this.onChanged,
    required this.onRead,
  });

  final bool agreed;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: agreed,
      onChanged: enabled ? (value) => onChanged(value ?? false) : null,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(context.l10n.rulesConsent),
      subtitle: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: enabled ? onRead : null,
          child: Text(context.l10n.rulesConsentRead),
        ),
      ),
    );
  }
}
