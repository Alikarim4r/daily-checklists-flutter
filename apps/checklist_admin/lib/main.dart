import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/checklists_tab.dart';
import 'screens/delete_tab.dart';
import 'screens/policies_screen.dart';
import 'screens/structure_tab.dart';
import 'screens/users_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ChecklistChrome.use(ChecklistBrand.admin);
  await bootstrapSupabase();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const AdminRoot(),
    ),
  );
}

class AdminRoot extends ConsumerStatefulWidget {
  const AdminRoot({super.key});

  @override
  ConsumerState<AdminRoot> createState() => _AdminRootState();
}

class _AdminRootState extends ConsumerState<AdminRoot> {
  String language = 'en';

  @override
  Widget build(BuildContext context) {
    final rtl = isRtlLanguage(language);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: language == 'ar' ? 'فحص يومي — إدارة' : 'Daily Checklists — Admin',
      debugShowCheckedModeBanner: false,
      theme: ChecklistChrome.theme(),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: ChecklistChrome.accent,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: language == 'ar' ? 'إدارة الفحص اليومي' : 'Checklist Admin',
        subtitle: language == 'ar'
            ? 'هيكل • قوائم • مستخدمون • سياسات'
            : 'Structure • Checklists • Users • Policies',
        allowedForProfile: (p) => p.canUseAdminApp,
        homeBuilder: (context, profile) => AdminShell(
          profile: profile,
          language: language,
          onLanguageChanged: (v) => setState(() => language = v),
        ),
      ),
    );
  }
}

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final ar = widget.language == 'ar';
    final tabs = <Widget>[
      StructureTab(profile: p),
      ChecklistsTab(profile: p),
      UsersTab(profile: p),
    ];
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.account_tree_outlined),
        label: ar ? 'الهيكل' : 'Structure',
      ),
      NavigationDestination(
        icon: const Icon(Icons.checklist_outlined),
        label: ar ? 'القوائم' : 'Lists',
      ),
      NavigationDestination(
        icon: const Icon(Icons.people_outline),
        label: ar ? 'مستخدمون' : 'Users',
      ),
    ];

    return Scaffold(
      endDrawer: ChecklistSettingsDrawer(
        profile: p,
        language: widget.language,
        onLanguageChanged: widget.onLanguageChanged,
        languages: const ['en', 'ar'],
        appIconAsset: 'assets/branding/app_icon_simple.png',
        advancedItems: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.policy_outlined),
            title: Text(ar ? 'السياسات' : 'Policies'),
            subtitle: Text(ar ? 'صور المشكلة' : 'Problem photos'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PoliciesScreen(profile: p),
                ),
              );
            },
          ),
          if (p.canDeleteInspections)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline),
              title: Text(ar ? 'حذف الفحوصات' : 'Delete inspections'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                        title: Text(
                          ar ? 'حذف الفحوصات' : 'Delete inspections',
                        ),
                      ),
                      body: DeleteTab(profile: p),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      appBar: checklistGradientAppBar(
        title: ar ? 'إدارة الفحص اليومي' : 'Checklist Admin',
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                p.isPlatformOwner
                    ? (ar ? 'مالك المنصة' : 'Owner')
                    : p.role.labelAr,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: ar ? 'الإعدادات' : 'Settings',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: tab.clamp(0, tabs.length - 1),
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.clamp(0, tabs.length - 1),
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: destinations,
      ),
    );
  }
}
