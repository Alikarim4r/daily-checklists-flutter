import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design/checkadmin_errors.dart';
import 'design/checkadmin_theme.dart';
import 'design/checkadmin_tokens.dart';
import 'design/checkadmin_widgets.dart';
import 'screens/audit_log_screen.dart';
import 'screens/checklists_tab.dart';
import 'screens/client_error_log_screen.dart';
import 'screens/delete_tab.dart';
import 'screens/policies_screen.dart';
import 'screens/reviews_tab.dart';
import 'screens/structure_tab.dart';
import 'screens/users_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  ChecklistChrome.use(checkAdminBrand);
  await bootstrapSupabase();
  StructuredErrorReporter.install(appKey: 'admin');
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionSecurityAppKeyProvider.overrideWithValue('admin'),
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
    return MaterialApp(
      title: checkAdminName,
      debugShowCheckedModeBanner: false,
      theme: CheckAdminTheme.light,
      darkTheme: CheckAdminTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 180),
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: checkAdminName,
        subtitle: language == 'ar'
            ? 'مركز قيادة للهيكل والقوائم والمستخدمين والحوكمة'
            : 'Command center for structure, checklists, users and governance',
        language: language,
        onLanguageChanged: (v) => setState(() => language = v),
        allowSelfRegistration: false,
        brandMarkAsset: 'assets/branding/app_icon_simple.png',
        userErrorMessage: (error) => checkAdminUserMessage(error, language),
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

class _AdminDestination {
  const _AdminDestination({
    required this.labelEn,
    required this.labelAr,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
  final String labelEn, labelAr;
  final IconData icon, selectedIcon;
  final Widget page;
  String label(bool ar) => ar ? labelAr : labelEn;
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int tab = 0;

  bool get ar => widget.language == 'ar';

  List<_AdminDestination> get _destinations {
    final p = widget.profile;
    return [
      _AdminDestination(
        labelEn: 'Structure',
        labelAr: 'الهيكل',
        icon: Icons.account_tree_outlined,
        selectedIcon: Icons.account_tree,
        page: StructureTab(profile: p, language: widget.language),
      ),
      _AdminDestination(
        labelEn: 'Checklists',
        labelAr: 'القوائم',
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check,
        page: ChecklistsTab(profile: p, language: widget.language),
      ),
      _AdminDestination(
        labelEn: 'Users',
        labelAr: 'المستخدمون',
        icon: Icons.manage_accounts_outlined,
        selectedIcon: Icons.manage_accounts,
        page: UsersTab(profile: p, language: widget.language),
      ),
      if (p.canReviewInspections)
        _AdminDestination(
          labelEn: 'Reviews',
          labelAr: 'الاعتمادات',
          icon: Icons.approval_outlined,
          selectedIcon: Icons.approval,
          page: ReviewsTab(profile: p, language: widget.language),
        ),
    ];
  }

  String get _roleLabel {
    final p = widget.profile;
    if (p.isPlatformOwner) return ar ? 'مالك المنصة' : 'Platform owner';
    return ar ? p.role.labelAr : p.role.dbValue.replaceAll('_', ' ');
  }

  void _openTools() => _scaffoldKey.currentState?.openEndDrawer();

  Widget _advancedItem({
    required IconData icon,
    required String titleEn,
    required String titleAr,
    String? subtitleEn,
    String? subtitleAr,
    required VoidCallback onTap,
    CaTone tone = CaTone.neutral,
  }) => CaCommandRow(
    leading: Icon(icon, color: caToneColor(CheckAdminColors.of(context), tone)),
    title: ar ? titleAr : titleEn,
    subtitle: ar ? subtitleAr : subtitleEn,
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final c = CheckAdminColors.of(context);
    final p = widget.profile;
    final destinations = _destinations;
    if (tab >= destinations.length) tab = 0;
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= CaBreakpoint.rail;
    final extended = width >= CaBreakpoint.extendedRail;
    final current = destinations[tab];
    final pages = IndexedStack(
      index: tab,
      children: destinations.map((d) => d.page).toList(),
    );

    final drawer = ChecklistSettingsDrawer(
      profile: p,
      language: widget.language,
      onLanguageChanged: widget.onLanguageChanged,
      languages: supportedLanguages,
      appIconAsset: 'assets/branding/app_icon_simple.png',
      advancedItems: [
        _advancedItem(
          icon: Icons.manage_history_outlined,
          titleEn: 'Audit log',
          titleAr: 'سجل التدقيق',
          subtitleEn: 'Changes, deletion and approval',
          subtitleAr: 'التغييرات والحذف والاعتماد',
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AuditLogScreen(language: widget.language),
              ),
            );
          },
        ),
        if (p.isPlatformOwner)
          _advancedItem(
            icon: Icons.monitor_heart_outlined,
            titleEn: 'Error monitoring',
            titleAr: 'مراقبة الأخطاء',
            subtitleEn: 'Privacy-sanitized application failures',
            subtitleAr: 'أعطال التطبيقات المنقحة من البيانات الحساسة',
            tone: CaTone.warning,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ClientErrorLogScreen(language: widget.language),
                ),
              );
            },
          ),
        _advancedItem(
          icon: Icons.policy_outlined,
          titleEn: 'Policies',
          titleAr: 'السياسات',
          subtitleEn: 'Evidence and problem-photo governance',
          subtitleAr: 'حوكمة الأدلة وصور المشاكل',
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    PoliciesScreen(profile: p, language: widget.language),
              ),
            );
          },
        ),
        if (p.canDeleteInspections)
          _advancedItem(
            icon: Icons.delete_outline,
            titleEn: 'Delete inspections',
            titleAr: 'حذف الفحوصات',
            tone: CaTone.danger,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                      title: Text(ar ? 'حذف الفحوصات' : 'Delete inspections'),
                    ),
                    body: SafeArea(
                      top: false,
                      child: DeleteTab(profile: p, language: widget.language),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );

    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      // Keep a visible scrim strip on 320–360dp phones so the drawer can be
      // dismissed by tapping outside it.
      endDrawer: Theme(
        data: theme.copyWith(
          drawerTheme: theme.drawerTheme.copyWith(
            width: math.min(360, width - 56),
          ),
        ),
        child: drawer,
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: useRail ? 20 : 16,
        title: Row(
          children: [
            if (!useRail) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(CaRadius.control),
                child: Image.asset(
                  'assets/branding/app_icon_simple.png',
                  width: 28,
                  height: 28,
                  errorBuilder: (_, _, _) =>
                      const SizedBox.square(dimension: 28),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                current.label(ar),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        actions: [
          if (width < 340)
            Tooltip(
              message: _roleLabel,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.brassSoft,
                  borderRadius: BorderRadius.circular(CaRadius.mark),
                ),
                child: Icon(Icons.shield_outlined, size: 18, color: c.brass),
              ),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: Center(
                child: CaRoleBadge(
                  label: width < 400 && p.isPlatformOwner
                      ? (ar ? 'المالك' : 'Owner')
                      : _roleLabel,
                ),
              ),
            ),
          IconButton(
            tooltip: ar
                ? 'أدوات الإدارة والإعدادات'
                : 'Admin tools and settings',
            onPressed: _openTools,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: useRail
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  top: false,
                  child: NavigationRail(
                    extended: extended,
                    minWidth: 72,
                    minExtendedWidth: 210,
                    useIndicator: false,
                    selectedIndex: tab,
                    onDestinationSelected: (i) => setState(() => tab = i),
                    groupAlignment: -1,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: extended
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    CaRadius.control,
                                  ),
                                  child: Image.asset(
                                    'assets/branding/app_icon_simple.png',
                                    width: 28,
                                    height: 28,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.square(dimension: 28),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  checkAdminName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(
                                CaRadius.control,
                              ),
                              child: Image.asset(
                                'assets/branding/app_icon_simple.png',
                                width: 28,
                                height: 28,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.square(dimension: 28),
                              ),
                            ),
                    ),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label(ar)),
                        ),
                    ],
                  ),
                ),
                VerticalDivider(width: 1, color: c.rule),
                Expanded(child: pages),
              ],
            )
          : pages,
      bottomNavigationBar: useRail
          ? null
          : Material(
              color: c.surface,
              child: SafeArea(
                top: false,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.rule)),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        Expanded(
                          child: Semantics(
                            selected: tab == i,
                            button: true,
                            label: destinations[i].label(ar),
                            child: InkWell(
                              onTap: () => setState(() => tab = i),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: tab == i
                                          ? c.primaryStrong
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      tab == i
                                          ? destinations[i].selectedIcon
                                          : destinations[i].icon,
                                      size: 22,
                                      color: tab == i
                                          ? c.primaryStrong
                                          : c.inkMuted,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      destinations[i].label(ar),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: tab == i
                                                ? c.primaryStrong
                                                : c.inkMuted,
                                            fontWeight: tab == i
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
