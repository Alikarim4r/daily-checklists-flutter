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
import 'screens/company_onboarding_screen.dart';
import 'screens/company_tab.dart';
import 'screens/delete_tab.dart';
import 'screens/first_company_setup_screen.dart';
import 'screens/policies_screen.dart';
import 'screens/ppm_tab.dart';
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

  void _setLanguage(String value) => setState(() {
    language = adminLanguages.contains(value) ? value : 'en';
  });

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
        onLanguageChanged: _setLanguage,
        allowSelfRegistration: true,
        registrationRequestedRole: 'company_owner_request',
        registrationIntroEn:
            'Create the company owner account. After sign-in, set up the company and choose its Google Play subscription.',
        registrationIntroAr:
            'أنشئ حساب مالك الشركة، ثم أكمل بيانات الشركة واختر اشتراكها عبر Google Play.',
        registrationSuccessEn:
            'Account created. Verify your email if requested, then sign in to finish company setup.',
        registrationSuccessAr:
            'تم إنشاء الحساب. أكّد بريدك إذا طُلب منك ذلك، ثم سجّل الدخول لإكمال إعداد الشركة.',
        registrationActionLabelEn: 'Create company account',
        registrationActionLabelAr: 'إنشاء حساب شركة',
        pendingProfileBuilder: (context, profile) =>
            CompanyOnboardingScreen(profile: profile, language: language),
        brandMarkAsset: 'assets/branding/app_icon_simple.png',
        userErrorMessage: (error) => checkAdminUserMessage(error, language),
        allowedForProfile: (p) => p.canUseAdminApp,
        homeBuilder: (context, profile) => AdminHomeGate(
          profile: profile,
          language: language,
          onLanguageChanged: _setLanguage,
        ),
      ),
    );
  }
}

class AdminHomeGate extends StatefulWidget {
  const AdminHomeGate({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<AdminHomeGate> createState() => _AdminHomeGateState();
}

class _AdminHomeGateState extends State<AdminHomeGate> {
  late Future<_AdminCompanyAccess> _future = _resolve();

  bool get ar => widget.language == 'ar';

  @override
  void didUpdateWidget(covariant AdminHomeGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.homeOrganizationId !=
            widget.profile.homeOrganizationId) {
      _future = _resolve();
    }
  }

  Future<_AdminCompanyAccess> _resolve() async {
    if (widget.profile.isPlatformOwner) {
      return const _AdminCompanyAccess.allowed();
    }
    final orgId = widget.profile.homeOrganizationId;
    if (orgId == null) {
      return const _AdminCompanyAccess.blocked(
        'Administrator account is not linked to a company.',
      );
    }
    final organization = await OrganizationRepository(supabase).getById(orgId);
    if (organization == null) {
      return const _AdminCompanyAccess.blocked('Company not found.');
    }
    if (!organization.selfService) {
      return _AdminCompanyAccess.allowed(organization: organization);
    }
    final entitlement = await SubscriptionRepository().currentEntitlement();
    if (entitlement?.isActive == true) {
      if (!organization.setupCompleted) {
        return _AdminCompanyAccess.setupRequired(
          organization: organization,
          entitlement: entitlement!,
        );
      }
      return _AdminCompanyAccess.allowed(
        organization: organization,
        entitlement: entitlement,
      );
    }
    return _AdminCompanyAccess.subscriptionRequired(
      organization: organization,
      entitlement: entitlement,
    );
  }

  void _refresh() => setState(() => _future = _resolve());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminCompanyAccess>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 46),
                    const SizedBox(height: 12),
                    Text(
                      checkAdminUserMessage(snapshot.error, widget.language),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(ar ? 'إعادة المحاولة' : 'Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final access = snapshot.data;
        if (access == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (access.blockedMessage != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  ar
                      ? 'تعذر ربط حساب الإدارة بالشركة. تواصل مع الدعم.'
                      : access.blockedMessage!,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (access.requiresSubscription) {
          return SubscriptionManagementScreen(
            profile: widget.profile,
            language: widget.language,
            onEntitlementChanged: (entitlement) {
              if (entitlement?.isActive == true) _refresh();
            },
          );
        }
        if (access.requiresSetup) {
          return FirstCompanySetupScreen(
            profile: widget.profile,
            language: widget.language,
            onCompleted: _refresh,
          );
        }
        return AdminShell(
          profile: widget.profile,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged,
        );
      },
    );
  }
}

class _AdminCompanyAccess {
  const _AdminCompanyAccess._({
    this.organization,
    this.entitlement,
    this.requiresSubscription = false,
    this.requiresSetup = false,
    this.blockedMessage,
  });

  const _AdminCompanyAccess.allowed({
    Organization? organization,
    SubscriptionEntitlement? entitlement,
  }) : this._(organization: organization, entitlement: entitlement);

  const _AdminCompanyAccess.subscriptionRequired({
    required Organization organization,
    SubscriptionEntitlement? entitlement,
  }) : this._(
         organization: organization,
         entitlement: entitlement,
         requiresSubscription: true,
       );

  const _AdminCompanyAccess.setupRequired({
    required Organization organization,
    required SubscriptionEntitlement entitlement,
  }) : this._(
         organization: organization,
         entitlement: entitlement,
         requiresSetup: true,
       );

  const _AdminCompanyAccess.blocked(String message)
    : this._(blockedMessage: message);

  final Organization? organization;
  final SubscriptionEntitlement? entitlement;
  final bool requiresSubscription;
  final bool requiresSetup;
  final String? blockedMessage;
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
        labelEn: 'Assets & PPM',
        labelAr: 'الأصول والصيانة',
        icon: Icons.handyman_outlined,
        selectedIcon: Icons.handyman,
        page: PpmTab(profile: p, language: widget.language),
      ),
      _AdminDestination(
        labelEn: 'Users',
        labelAr: 'المستخدمون',
        icon: Icons.manage_accounts_outlined,
        selectedIcon: Icons.manage_accounts,
        page: UsersTab(profile: p, language: widget.language),
      ),
      _AdminDestination(
        labelEn: 'Organization',
        labelAr: 'المنظمة',
        icon: Icons.business_outlined,
        selectedIcon: Icons.business,
        page: CompanyTab(profile: p, language: widget.language),
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

  Widget _adminMark(CheckAdminColors c, {double size = 36}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: c.primarySoft,
      borderRadius: BorderRadius.circular(CaRadius.control),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.admin_panel_settings_outlined,
      size: size * .56,
      color: c.primaryStrong,
    ),
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
    final pages = IndexedStack(
      index: tab,
      children: destinations.map((d) => d.page).toList(),
    );

    final drawer = ChecklistSettingsDrawer(
      profile: p,
      language: widget.language,
      onLanguageChanged: widget.onLanguageChanged,
      languages: adminLanguages,
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
            if (!useRail) ...[_adminMark(c), const SizedBox(width: 10)],
            Expanded(
              child: Text(
                checkAdminName,
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
                    useIndicator: true,
                    selectedIndex: tab,
                    onDestinationSelected: (i) => setState(() => tab = i),
                    groupAlignment: -1,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: extended
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _adminMark(c, size: 32),
                                const SizedBox(width: 10),
                                Text(
                                  checkAdminName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ],
                            )
                          : _adminMark(c, size: 32),
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
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.rule)),
              ),
              child: SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label(ar),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
