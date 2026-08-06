import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('photo policy', () {
    InspectionItem problemItem({String? photo}) => InspectionItem(
          itemIndex: 1,
          description: 'Leak?',
          defaultAnswer: 'N',
          response: ChecklistResponse.yes,
          issueImagePath: photo,
        );

    test('blocks when critical and photo missing', () {
      final insp = Inspection(
        id: 'i1',
        siteId: 's1',
        buildingCode: 'B1',
        inspectionDate: DateTime(2026, 7, 28),
        items: [problemItem()],
      );
      final result = validateProblemPhotos(
        inspection: insp,
        policy: const ChecklistOrgPolicy(
          organizationId: 'o1',
          photoRequiredOnProblem: true,
          missingPhotoSeverity: PolicySeverity.critical,
        ),
      );
      expect(result.ok, isFalse);
      expect(result.blocksSubmit, isTrue);
    });

    test('ok when photo present', () {
      final insp = Inspection(
        id: 'i1',
        siteId: 's1',
        buildingCode: 'B1',
        inspectionDate: DateTime(2026, 7, 28),
        items: [problemItem(photo: 'path.jpg')],
      );
      final result = validateProblemPhotos(
        inspection: insp,
        policy: const ChecklistOrgPolicy(
          organizationId: 'o1',
          photoRequiredOnProblem: true,
          missingPhotoSeverity: PolicySeverity.critical,
        ),
      );
      expect(result.ok, isTrue);
    });
  });

  group('overdue streak', () {
    test('marks overdue after consecutive problem days', () {
      final asOf = DateTime(2026, 7, 28);
      final history = <String, Map<int, bool>>{
        '2026-07-28': {1: true},
        '2026-07-27': {1: true},
        '2026-07-26': {1: true},
      };
      expect(
        isItemOverdue(
          itemIndex: 1,
          asOfDate: asOf,
          overdueDays: 3,
          problemByDateIso: history,
        ),
        isTrue,
      );
      expect(
        isItemOverdue(
          itemIndex: 1,
          asOfDate: asOf,
          overdueDays: 4,
          problemByDateIso: history,
        ),
        isFalse,
      );
    });

    test('uses per-item overdue days', () {
      final asOf = DateTime(2026, 7, 28);
      final insp = Inspection(
        id: 'i1',
        siteId: 's1',
        buildingCode: 'B1',
        inspectionDate: asOf,
        items: [
          InspectionItem(
            itemIndex: 1,
            description: 'A',
            defaultAnswer: 'Y',
            response: ChecklistResponse.no,
            overdueAfterDays: 2,
          ),
          InspectionItem(
            itemIndex: 2,
            description: 'B',
            defaultAnswer: 'Y',
            response: ChecklistResponse.no,
            overdueAfterDays: 5,
          ),
        ],
      );
      final history = <String, Map<int, bool>>{
        '2026-07-28': {1: true, 2: true},
        '2026-07-27': {1: true, 2: true},
      };
      final overdue = overdueItemIndexes(
        inspection: insp,
        problemByDateIso: history,
      );
      expect(overdue.contains(1), isTrue);
      expect(overdue.contains(2), isFalse);
    });
  });
}
