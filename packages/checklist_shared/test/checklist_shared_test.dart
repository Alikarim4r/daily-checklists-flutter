import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildDailyRecordId', () {
    expect(buildDailyRecordId('B1', '2026-07-28'), 'B1__2026-07-28');
  });

  test('buildings loaded', () {
    expect(BuildingConfig.all.length, 10);
    expect(BuildingConfig.byId('B1')?.type, 'DEFAULT');
  });

  test('checklist lists loaded', () {
    expect(ChecklistItem.forBuilding('B1').length, 18);
    expect(ChecklistItem.forBuilding('B2-DC').length, 12);
    expect(ChecklistItem.forBuilding('B7-BMS').length, 36);
  });

  test('platform owner identity comes from the server flag, not email', () {
    Profile profile({required String email, required bool owner}) =>
        Profile.fromJson({
          'id': '00000000-0000-4000-8000-000000000001',
          'full_name': 'Test user',
          'email': email,
          'role': 'viewer',
          'is_active': true,
          'approval_status': 'approved',
          'is_platform_owner': owner,
        });

    expect(
      profile(email: 'alikarim4r@gmail.com', owner: false).isPlatformOwner,
      isFalse,
    );
    expect(
      profile(email: 'owner@example.com', owner: true).isPlatformOwner,
      isTrue,
    );
  });

  test('inspection parses the optimistic-lock version', () {
    final inspection = Inspection.fromJson({
      'id': '00000000-0000-4000-8000-000000000010',
      'site_id': '00000000-0000-4000-8000-000000000020',
      'building_code': 'B1',
      'inspection_date': '2026-08-09',
      'version': 7,
    });

    expect(inspection.version, 7);
  });

  test('RPC item payload preserves linked issue and repair evidence', () {
    final item = InspectionItem(
      id: '00000000-0000-4000-8000-000000000030',
      itemIndex: 4,
      description: 'Emergency light',
      defaultAnswer: 'Y',
      response: ChecklistResponse.no,
    );
    final pairId = item.addPairWithIssue('org/site/inspection/issue.jpg');
    item.setFixForPair(pairId, 'org/site/inspection/fix.jpg');

    final payload = item.toRpcJson();
    expect(payload['item_index'], 4);
    expect(payload['response'], 'yes');
    expect(payload['issue_image_path'], contains(pairId));
    expect(payload['fix_image_path'], contains('fix.jpg'));
  });

  test('inspection item resolves every multilingual catalog description', () {
    final item = InspectionItem.fromJson({
      'item_index': 1,
      'description': 'English',
      'description_ar': 'العربية',
      'description_bn': 'বাংলা',
      'description_hi': 'हिन्दी',
      'description_ml': 'മലയാളം',
      'description_tl': 'Tagalog',
      'description_ta': 'தமிழ்',
    });

    expect(item.descriptionFor('en'), 'English');
    expect(item.descriptionFor('ar'), 'العربية');
    expect(item.descriptionFor('bn'), 'বাংলা');
    expect(item.descriptionFor('hi'), 'हिन्दी');
    expect(item.descriptionFor('ml'), 'മലയാളം');
    expect(item.descriptionFor('tl'), 'Tagalog');
    expect(item.descriptionFor('ta'), 'தமிழ்');
    expect(item.toRpcJson()['_localized_descriptions'], hasLength(5));
  });
}
