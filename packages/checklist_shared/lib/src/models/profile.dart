import 'enums.dart';
import '../theme/form_paper_theme.dart';

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.approvalStatus,
    this.isPlatformOwner = false,
    this.homeOrganizationId,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final bool isActive;
  final ApprovalStatus approvalStatus;

  /// Server-derived membership; never inferred from a mutable profile field.
  final bool isPlatformOwner;

  /// Bound organization for org-scoped [UserRole.superAdmin] (one org).
  final String? homeOrganizationId;

  bool get isApprovedActive =>
      isActive && approvalStatus == ApprovalStatus.approved;

  /// Owner bypasses normal role ceilings for admin UI.
  bool get canUseAdminApp => isPlatformOwner || role.canUseAdmin;

  bool get canDeleteInspections => isPlatformOwner || role.canDeleteInspections;

  /// site_admin / super_admin can edit submitted inspections before approve.
  bool get canReviewInspections => isPlatformOwner || role.isElevatedAdmin;

  /// Add / edit / archive organizations — owner only.
  bool get canManageOrganizations => isPlatformOwner;

  /// Approve / create another super_admin — owner only.
  bool get canManageSuperAdmins => isPlatformOwner;

  /// Approve / create site_admin — owner or org super_admin.
  bool get canManageSiteAdmins =>
      isPlatformOwner || role == UserRole.superAdmin;

  /// Zones + org-wide structure — owner or org super_admin.
  bool get canManageStructure => isPlatformOwner || role == UserRole.superAdmin;

  bool get canManagePolicies => isPlatformOwner || role == UserRole.superAdmin;

  /// Form table color themes — owner or org super_admin.
  bool get canManageFormThemes =>
      isPlatformOwner || role == UserRole.superAdmin;

  /// Site admin may add/remove technicians and sites in their scope.
  bool get canManageLocalSites =>
      isPlatformOwner ||
      role == UserRole.superAdmin ||
      role == UserRole.siteAdmin;

  bool bindsToOrganization(String organizationId) {
    if (isPlatformOwner) return true;
    if (role == UserRole.superAdmin) {
      return homeOrganizationId == organizationId;
    }
    return false;
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: (json['full_name'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      role: UserRole.fromDb((json['role'] ?? 'viewer') as String),
      isActive: json['is_active'] as bool? ?? true,
      approvalStatus: ApprovalStatus.fromDb(json['approval_status'] as String?),
      isPlatformOwner: json['is_platform_owner'] as bool? ?? false,
      homeOrganizationId: json['home_organization_id'] as String?,
    );
  }
}

class ChecklistSite {
  const ChecklistSite({
    required this.id,
    required this.organizationId,
    required this.nameEn,
    required this.nameAr,
    required this.buildingCode,
    this.zoneId,
    this.parentSiteId,
    this.pin = '',
    this.checklistType = 'DEFAULT',
    this.location = 'Government HQ Demo',
    this.isActive = true,
    this.reportLogoPath,
    this.formTheme = 'classic_gold',
    this.formThemeAccent,
    this.effectiveFormTheme,
    this.effectiveFormThemeAccent,
    this.formThemeSource,
  });

  final String id;
  final String organizationId;
  final String? zoneId;

  /// Parent campus/site when this row is a building checklist unit.
  final String? parentSiteId;
  final String nameEn;
  final String nameAr;
  final String buildingCode;
  final String pin;
  final String checklistType;
  final String location;
  final bool isActive;

  /// Footer logo: EN bottom-left / AR bottom-right. Units inherit campus.
  final String? reportLogoPath;

  /// Paper chrome theme key (see [FormThemeKey]).
  final String formTheme;

  /// `#RRGGBB` when [formTheme] is custom.
  final String? formThemeAccent;
  final String? effectiveFormTheme;
  final String? effectiveFormThemeAccent;
  final String? formThemeSource;

  FormPaperTheme get paperTheme => FormPaperTheme.resolve(
    themeDb: effectiveFormTheme ?? formTheme,
    accentHex: effectiveFormThemeAccent ?? formThemeAccent,
  );

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  /// Daily checklist unit (building / area with a building_code).
  bool get isChecklistUnit => buildingCode.trim().isNotEmpty;

  /// Campus / container site that groups checklists (no building_code).
  bool get isCampus => !isChecklistUnit;

  String get displayBldgCode {
    final m = RegExp(
      r'^B?(\d+)$',
      caseSensitive: false,
    ).firstMatch(buildingCode.trim());
    if (m != null) return m.group(1)!;
    final digits = RegExp(r'(\d+)').firstMatch(buildingCode);
    if (digits != null && buildingCode.trim().length <= 4) {
      return digits.group(1)!;
    }
    return buildingCode;
  }

  String get bldgNo => displayBldgCode;

  ChecklistSite copyWith({
    String? zoneId,
    String? parentSiteId,
    String? nameEn,
    String? nameAr,
    String? buildingCode,
    String? pin,
    String? checklistType,
    String? location,
    bool? isActive,
    String? reportLogoPath,
    bool clearLogo = false,
    String? formTheme,
    String? formThemeAccent,
    bool clearThemeAccent = false,
    String? effectiveFormTheme,
    String? effectiveFormThemeAccent,
    String? formThemeSource,
    bool clearEffectiveThemeAccent = false,
  }) {
    return ChecklistSite(
      id: id,
      organizationId: organizationId,
      zoneId: zoneId ?? this.zoneId,
      parentSiteId: parentSiteId ?? this.parentSiteId,
      nameEn: nameEn ?? this.nameEn,
      nameAr: nameAr ?? this.nameAr,
      buildingCode: buildingCode ?? this.buildingCode,
      pin: pin ?? this.pin,
      checklistType: checklistType ?? this.checklistType,
      location: location ?? this.location,
      isActive: isActive ?? this.isActive,
      reportLogoPath: clearLogo
          ? null
          : (reportLogoPath ?? this.reportLogoPath),
      formTheme: formTheme ?? this.formTheme,
      formThemeAccent: clearThemeAccent
          ? null
          : (formThemeAccent ?? this.formThemeAccent),
      effectiveFormTheme: effectiveFormTheme ?? this.effectiveFormTheme,
      effectiveFormThemeAccent: clearEffectiveThemeAccent
          ? null
          : (effectiveFormThemeAccent ?? this.effectiveFormThemeAccent),
      formThemeSource: formThemeSource ?? this.formThemeSource,
    );
  }

  factory ChecklistSite.fromJson(Map<String, dynamic> json) {
    return ChecklistSite(
      id: json['id'] as String,
      organizationId: (json['organization_id'] ?? '') as String,
      zoneId: json['zone_id'] as String?,
      parentSiteId: json['parent_site_id'] as String?,
      nameEn: (json['name_en'] ?? '') as String,
      nameAr: (json['name_ar'] ?? '') as String,
      buildingCode: (json['building_code'] ?? '') as String,
      pin: (json['pin'] ?? '') as String,
      checklistType: (json['checklist_type'] ?? 'DEFAULT') as String,
      location: (json['location'] ?? 'Government HQ Demo') as String,
      isActive: json['is_active'] as bool? ?? true,
      reportLogoPath: json['report_logo_path'] as String?,
      formTheme: (json['form_theme'] as String?) ?? 'classic_gold',
      formThemeAccent: json['form_theme_accent'] as String?,
      effectiveFormTheme: json['_effective_form_theme'] as String?,
      effectiveFormThemeAccent: json['_effective_form_theme_accent'] as String?,
      formThemeSource: json['_form_theme_source'] as String?,
    );
  }
}

/// Site (campus) with the checklist units nested under it.
class CampusChecklistGroup {
  const CampusChecklistGroup({this.campus, required this.checklists});

  /// Null when checklists have no parent (orphan units).
  final ChecklistSite? campus;
  final List<ChecklistSite> checklists;

  String titleFor(String language) {
    if (campus != null) return campus!.nameFor(language);
    return language == 'ar' ? 'قوائم أخرى' : 'Other checklists';
  }
}

class UserSiteAccess {
  const UserSiteAccess({
    required this.id,
    required this.userId,
    required this.siteId,
    required this.role,
    required this.canRead,
    required this.canWrite,
    required this.canManage,
    this.validFrom,
    this.validUntil,
    this.site,
  });

  final String id;
  final String userId;
  final String siteId;
  final UserRole role;
  final bool canRead;
  final bool canWrite;
  final bool canManage;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final ChecklistSite? site;

  bool get isCurrentlyValid {
    final now = DateTime.now();
    return (validFrom == null || !validFrom!.isAfter(now)) &&
        (validUntil == null || validUntil!.isAfter(now));
  }

  factory UserSiteAccess.fromJson(Map<String, dynamic> json) {
    ChecklistSite? site;
    final rawSite = json['sites'];
    if (rawSite is Map) {
      site = ChecklistSite.fromJson(Map<String, dynamic>.from(rawSite));
    }
    return UserSiteAccess(
      id: (json['id'] ?? '') as String,
      userId: json['user_id'] as String,
      siteId: json['site_id'] as String,
      role: UserRole.fromDb((json['role'] ?? 'viewer') as String),
      canRead: json['can_read'] as bool? ?? true,
      canWrite: json['can_write'] as bool? ?? false,
      canManage: json['can_manage'] as bool? ?? false,
      validFrom: json['valid_from'] == null
          ? null
          : DateTime.tryParse(json['valid_from'] as String),
      validUntil: json['valid_until'] == null
          ? null
          : DateTime.tryParse(json['valid_until'] as String),
      site: site,
    );
  }
}
