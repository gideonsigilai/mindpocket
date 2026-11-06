import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants/app_constants.dart';
import '../../core/controllers/app_settings_controller.dart';
import '../../core/services/storage/preferences_service.dart';
import '../routes/app_routes.dart';

/// First frame: brand mark on the cream canvas, then either onboarding or home.
/// Errors here are rare but must never strand the user on a spinner, so a retry
/// path is provided.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    try {
      final PreferencesService preferences = Get.find<PreferencesService>();
      final AppSettingsController settings = Get.find<AppSettingsController>();
      settings.themeMode.value = switch (preferences.themeModeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      Get.offAllNamed(
        preferences.onboardingDone ? AppRoutes.home : AppRoutes.onboarding,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inverseSurface,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(14),
              child: Image.asset(
                'assets/images/brand_mark.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              AppConstants.tagline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            if (!_failed)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Column(
                children: <Widget>[
                  Text(
                    'MindPocket could not read its local settings.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() => _failed = false);
                      _decide();
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
