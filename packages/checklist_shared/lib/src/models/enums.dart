import 'package:collection/collection.dart';

const kPlatformOwnerEmails = <String>{
  'alikarim4r@gmail.com',
};

bool isPlatformOwnerEmail(String? email) {
  if (email == null) return false;
  return kPlatformOwnerEmails.contains(email.trim().toLowerCase());
}

enum UserRole {
  superAdmin('super_admin'),
  siteAdmin('site_admin'),
  technician('technician'),
  technicianRequest('technician_request'),
  viewer('viewer');

  const UserRole(this.dbValue);
  final String dbValue;

  static UserRole fromDb(String value) => UserRole.values.firstWhere(
        (r) => r.dbValue == value,
        orElse: () => UserRole.viewer,
      );

  /// Arabic label for admin UI.
  String get labelAr => switch (this) {
        UserRole.superAdmin => 'سوبر أدمن',
        UserRole.siteAdmin => 'أدمن',
        UserRole.technician => 'فني',
        UserRole.technicianRequest => 'طلب فني',
        UserRole.viewer => 'عارض',
      };

  bool get canUseEntry =>
      this == UserRole.technician ||
      this == UserRole.siteAdmin ||
      this == UserRole.superAdmin;

  bool get canUseViewer => this != UserRole.technicianRequest;

  bool get canUseAdmin =>
      this == UserRole.superAdmin || this == UserRole.siteAdmin;

  bool get canDeleteInspections => this == UserRole.superAdmin;

  bool get isElevatedAdmin =>
      this == UserRole.superAdmin || this == UserRole.siteAdmin;

  /// Default site flags when approving this role.
  bool get defaultCanWrite =>
      this == UserRole.technician ||
      this == UserRole.siteAdmin ||
      this == UserRole.superAdmin;

  bool get defaultCanManage =>
      this == UserRole.siteAdmin || this == UserRole.superAdmin;
}

enum ApprovalStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  suspended('suspended');

  const ApprovalStatus(this.dbValue);
  final String dbValue;

  static ApprovalStatus fromDb(String? value) {
    if (value == null) return ApprovalStatus.approved;
    return ApprovalStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => ApprovalStatus.pending,
    );
  }

  String get labelAr => switch (this) {
        ApprovalStatus.pending => 'بانتظار الاعتماد',
        ApprovalStatus.approved => 'معتمد',
        ApprovalStatus.rejected => 'مرفوض',
        ApprovalStatus.suspended => 'موقوف',
      };
}

enum ChecklistResponse {
  yes('yes'),
  no('no'),
  na('na');

  const ChecklistResponse(this.dbValue);
  final String dbValue;

  static ChecklistResponse? fromDb(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.toLowerCase();
    if (normalized == 'y' || normalized == 'yes') return ChecklistResponse.yes;
    if (normalized == 'n' || normalized == 'no') return ChecklistResponse.no;
    if (normalized == 'na' || normalized == 'n/a') return ChecklistResponse.na;
    return ChecklistResponse.values
        .where((e) => e.dbValue == normalized)
        .firstOrNull;
  }

  String get label => switch (this) {
        ChecklistResponse.yes => 'Yes',
        ChecklistResponse.no => 'No',
        ChecklistResponse.na => 'NA',
      };

  /// HTML / catalog short code (Y / N / NA).
  String get shortCode => switch (this) {
        ChecklistResponse.yes => 'Y',
        ChecklistResponse.no => 'N',
        ChecklistResponse.na => 'NA',
      };
}

enum InspectionStatus {
  draft('draft'),
  submitted('submitted');

  const InspectionStatus(this.dbValue);
  final String dbValue;

  static InspectionStatus fromDb(String value) =>
      InspectionStatus.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => InspectionStatus.draft,
      );
}

enum ReviewStatus {
  draft('draft'),
  submitted('submitted'),
  approved('approved');

  const ReviewStatus(this.dbValue);
  final String dbValue;

  static ReviewStatus fromDb(String? value) => ReviewStatus.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ReviewStatus.draft,
      );

  String get labelAr => switch (this) {
        ReviewStatus.draft => 'مسودة',
        ReviewStatus.submitted => 'بانتظار الاعتماد',
        ReviewStatus.approved => 'معتمد',
      };
}

/// Field-app gate: require at least one readable / writable site.
enum SiteAccessRequirement {
  none,
  read,
  write,
}
