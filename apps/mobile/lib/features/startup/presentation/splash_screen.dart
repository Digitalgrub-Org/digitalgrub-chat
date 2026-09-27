import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/core/widgets/brand_mark.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _startupFailed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _continueStartup();
  }

  Future<void> _continueStartup() async {
    if (_startupFailed) setState(() => _startupFailed = false);
    try {
      await Future.wait<Object?>([
        Future<void>.delayed(const Duration(milliseconds: 700)),
        ref.read(authControllerProvider.future),
      ]);
      if (!mounted) return;

      final latestSession = ref.read(authControllerProvider).value;
      if (latestSession != null) {
        context.go(AppRoutes.chats);
        return;
      }

      final preferences = ref.read(appPreferencesProvider);
      context.go(
        preferences.isOnboardingComplete
            ? AppRoutes.login
            : AppRoutes.onboarding,
      );
    } catch (_) {
      if (mounted) setState(() => _startupFailed = true);
    }
  }

  void _retryStartup() {
    ref.invalidate(matrixClientProvider);
    ref.invalidate(authRepositoryProvider);
    ref.invalidate(authControllerProvider);
    _continueStartup();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 88),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    context.l10n.appName,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.appTagline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_startupFailed) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      context.l10n.startupFailed,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _retryStartup,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.l10n.retry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
