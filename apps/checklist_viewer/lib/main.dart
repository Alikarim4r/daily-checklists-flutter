import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design/checkview_theme.dart';
import 'design/checkview_tokens.dart';
import 'screens/checkview_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ChecklistChrome.use(checkViewBrand);
  await bootstrapSupabase();
  StructuredErrorReporter.install(appKey: 'viewer');
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionSecurityAppKeyProvider.overrideWithValue('viewer'),
      ],
      child: const ViewerRoot(),
    ),
  );
}

class ViewerRoot extends ConsumerStatefulWidget {
  const ViewerRoot({super.key});

  @override
  ConsumerState<ViewerRoot> createState() => _ViewerRootState();
}

class _ViewerRootState extends ConsumerState<ViewerRoot> {
  String language = 'en';

  void _setLanguage(String value) => setState(() {
    language = viewerLanguages.contains(value) ? value : 'en';
  });

  @override
  Widget build(BuildContext context) {
    final rtl = isRtlLanguage(language);
    final ar = language == 'ar';
    final themeMode = ref.watch(themeModeProvider);
    // Resolve a single ThemeData into `theme:` only (no light/dark AnimatedTheme
    // cross-fade). ThemeMode.system follows the platform brightness.
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final useDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformDark,
    };
    return MaterialApp(
      title: checkViewName,
      debugShowCheckedModeBanner: false,
      theme: useDark ? CheckViewTheme.dark : CheckViewTheme.light,
      themeMode: ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      themeAnimationStyle: AnimationStyle.noAnimation,
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: checkViewName,
        subtitle: ar
            ? 'مراجعة الفحوصات واعتمادها ومتابعة الإجراءات التصحيحية'
            : 'Review, approve and follow up facility inspections',
        language: language,
        onLanguageChanged: _setLanguage,
        allowSelfRegistration: true,
        registrationRequestedRole: 'viewer',
        brandMarkAsset: 'assets/branding/app_icon_simple.png',
        allowedForProfile: (p) => p.isPlatformOwner || p.role.canUseViewer,
        siteAccessRequirement: SiteAccessRequirement.read,
        homeBuilder: (context, profile) => CheckViewShell(
          profile: profile,
          language: language,
          onLanguageChanged: _setLanguage,
        ),
      ),
    );
  }
}
