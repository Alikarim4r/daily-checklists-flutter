import 'enums.dart';

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.approvalStatus,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final bool isActive;
  final ApprovalStatus approvalStatus;

  bool get isPlatformOwner => isPlatformOwnerEmail(email);

  bool get isApprovedActive =>
      isActive && approvalStatus == ApprovalStatus.approved;

  /// Owner bypasses normal role ceilings for admin UI.
  bool get canUseAdminApp => isPlatformOwner || role.canUseAdmin;

  bool get canDeleteInspections =>
      isPlatformOwner || role.canDeleteInspections;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: (json['full_name'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      role: UserRole.fromDb((json['role'] ?? 'viewer') as String),
      isActive: json['is_active'] as bool? ?? true,
      approvalStatus: ApprovalStatus.fromDb(json['approval_status'] as String?),
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
    this.pin = '',
    this.checklistType = 'DEFAULT',
    this.location = 'MOEHE Permanent Headquarters',
    this.isActive = true,
  });

  final String id;
  final String organizationId;
  final String nameEn;
  final String nameAr;
  final String buildingCode;
  final String pin;
  final String checklistType;
  final String location;
  final bool isActive;

  String nameFor(String language) => language == 'ar' ? nameAr : nameEn;

  String get bldgNo {
    final m = RegExp(r'(\d+)').firstMatch(buildingCode);
    return m?.group(1) ?? buildingCode;
  }

  factory ChecklistSite.fromJson(Map<String, dynamic> json) {
    return ChecklistSite(
      id: json['id'] as String,
      organizationId: (json['organization_id'] ?? '') as String,
      nameEn: (json['name_en'] ?? '') as String,
      nameAr: (json['name_ar'] ?? '') as String,
      buildingCode: (json['building_code'] ?? '') as String,
      pin: (json['pin'] ?? '') as String,
      checklistType: (json['checklist_type'] ?? 'DEFAULT') as String,
      location: (json['location'] ?? 'MOEHE Permanent Headquarters') as String,
      isActive: json['is_active'] as bool? ?? true,
    );
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
    this.site,
  });

  final String id;
  final String userId;
  final String siteId;
  final UserRole role;
  final bool canRead;
  final bool canWrite;
  final bool canManage;
  final ChecklistSite? site;

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
      site: site,
    );
  }
}
