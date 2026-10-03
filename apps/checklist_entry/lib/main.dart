import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

import 'design/checkin_errors.dart';
import 'design/checkin_theme.dart';
import 'design/checkin_tokens.dart';
import 'design/checkin_widgets.dart';

part 'screens/entry_home.dart';
part 'screens/sync_status_screen.dart';
part 'screens/entry_hierarchy_screens.dart';
part 'screens/entry_site_screen.dart';
part 'widgets/entry_form_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  ChecklistChrome.use(checkInBrand);
  await bootstrapSupabase();
  StructuredErrorReporter.install(appKey: 'entry');
  await OfflineInspectionQueue.init();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionSecurityAppKeyProvider.overrideWithValue('entry'),
      ],
      child: const EntryRoot(),
    ),
  );
}

class EntryRoot extends ConsumerStatefulWidget {
  const EntryRoot({super.key});

  @override
  ConsumerState<EntryRoot> createState() => _EntryRootState();
}

Map<String, dynamic> _encodeSite(ChecklistSite site) => {
  'id': site.id,
  'organization_id': site.organizationId,
  'zone_id': site.zoneId,
  'parent_site_id': site.parentSiteId,
  'name_en': site.nameEn,
  'name_ar': site.nameAr,
  'building_code': site.buildingCode,
  'pin': site.pin,
  'checklist_type': site.checklistType,
  'location': site.location,
  'is_active': site.isActive,
  'report_logo_path': site.reportLogoPath,
  'form_theme': site.formTheme,
  'form_theme_accent': site.formThemeAccent,
  '_effective_form_theme': site.effectiveFormTheme,
  '_effective_form_theme_accent': site.effectiveFormThemeAccent,
  '_form_theme_source': site.formThemeSource,
};

Map<String, dynamic> _encodeOrganization(Organization organization) => {
  'id': organization.id,
  'name_en': organization.nameEn,
  'name_ar': organization.nameAr,
  'is_active': organization.isActive,
  'logo_en_path': organization.logoEnPath,
  'logo_ar_path': organization.logoArPath,
  'form_theme': organization.formTheme,
  'form_theme_accent': organization.formThemeAccent,
};

Map<String, dynamic> _encodeZone(Zone zone) => {
  'id': zone.id,
  'organization_id': zone.organizationId,
  'code': zone.code,
  'name_en': zone.nameEn,
  'name_ar': zone.nameAr,
  'is_active': zone.isActive,
  'sort_order': zone.sortOrder,
  'report_logo_path': zone.reportLogoPath,
  'form_theme': zone.formTheme,
  'form_theme_accent': zone.formThemeAccent,
};

List<Map<String, dynamic>> _encodeOrgSections(
  List<OrgBrowseSection> sections,
) => [
  for (final section in sections)
    {
      'organization': _encodeOrganization(section.organization),
      'zones': [
        for (final zone in section.zones)
          {
            'zone': zone.zone == null ? null : _encodeZone(zone.zone!),
            'groups': [
              for (final group in zone.groups)
                {
                  'campus': group.campus == null
                      ? null
                      : _encodeSite(group.campus!),
                  'checklists': [
                    for (final site in group.checklists) _encodeSite(site),
                  ],
                },
            ],
          },
      ],
    },
];

List<OrgBrowseSection> _decodeOrgSections(List<dynamic> raw) => [
  for (final sectionRaw in raw)
    if (sectionRaw is Map)
      OrgBrowseSection(
        organization: Organization.fromJson(
          Map<String, dynamic>.from(sectionRaw['organization'] as Map),
        ),
        zones: [
          for (final zoneRaw in sectionRaw['zones'] as List? ?? const [])
            if (zoneRaw is Map)
              ZoneBrowseSection(
                zone: zoneRaw['zone'] is Map
                    ? Zone.fromJson(
                        Map<String, dynamic>.from(zoneRaw['zone'] as Map),
                      )
                    : null,
                groups: [
                  for (final groupRaw in zoneRaw['groups'] as List? ?? const [])
                    if (groupRaw is Map)
                      CampusChecklistGroup(
                        campus: groupRaw['campus'] is Map
                            ? ChecklistSite.fromJson(
                                Map<String, dynamic>.from(
                                  groupRaw['campus'] as Map,
                                ),
                              )
                            : null,
                        checklists: [
                          for (final siteRaw
                              in groupRaw['checklists'] as List? ?? const [])
                            if (siteRaw is Map)
                              ChecklistSite.fromJson(
                                Map<String, dynamic>.from(siteRaw),
                              ),
                        ],
                      ),
                ],
              ),
        ],
      ),
];

class _EntryRootState extends ConsumerState<EntryRoot> {
  String language = 'en';

  @override
  Widget build(BuildContext context) {
    final rtl = isRtlLanguage(language);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: checkInName,
      debugShowCheckedModeBanner: false,
      theme: CheckInTheme.light,
      darkTheme: CheckInTheme.dark,
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 180),
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: checkInName,
        subtitle: language == 'ar'
            ? 'فحص ميداني سريع وواضح، حتى دون اتصال'
            : 'Focused field inspections, online or offline',
        language: language,
        onLanguageChanged: (v) => setState(() => language = v),
        allowSelfRegistration: true,
        registrationRequestedRole: 'technician_request',
        brandMarkAsset: 'assets/branding/app_icon_simple.png',
        userErrorMessage: (error) => checkInUserMessage(error, language),
        allowedForProfile: (p) => p.isPlatformOwner || p.role.canUseEntry,
        siteAccessRequirement: SiteAccessRequirement.write,
        homeBuilder: (context, profile) => EntryHome(
          profile: profile,
          language: language,
          onLanguageChanged: (v) => setState(() => language = v),
        ),
      ),
    );
  }
}
