import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

InspectionItem _item({
  required int index,
  ChecklistResponse? response,
  String defaultAnswer = 'Y',
  List<InspectionPhotoPair> pairs = const [],
  int overdue = 3,
}) {
  final item = InspectionItem(
    itemIndex: index,
    description: 'Item $index',
    defaultAnswer: defaultAnswer,
    response: response,
    overdueAfterDays: overdue,
  );
  if (pairs.isNotEmpty) item.setPhotoPairs(pairs);
  return item;
}

void main() {
  group('applyOpenProblemCarryForward', () {
    test('copies unfixed issue photos and problem answer from prior list', () {
      final prior = Inspection(
        id: 'old',
        siteId: 's1',
        buildingCode: 'B6',
        inspectionDate: DateTime(2026, 8, 7),
        items: [
          _item(
            index: 1,
            response: ChecklistResponse.no,
            pairs: [
              InspectionPhotoPair(id: 'p1', issuePath: 'org/s/old/issue1.jpg'),
              InspectionPhotoPair(
                id: 'p2',
                issuePath: 'org/s/old/issue2.jpg',
                fixPath: 'org/s/old/fix2.jpg',
              ),
            ],
          ),
        ],
      );
      final draft = Inspection(
        id: 'new',
        siteId: 's1',
        buildingCode: 'B6',
        inspectionDate: DateTime(2026, 8, 7),
        items: [_item(index: 1)],
      );

      final changed = applyOpenProblemCarryForward(
        current: draft,
        sourceByIndex: {for (final i in prior.items) i.itemIndex: i},
      );

      expect(changed, isTrue);
      expect(draft.items.first.response, ChecklistResponse.no);
      expect(draft.items.first.issueImagePaths, ['org/s/old/issue1.jpg']);
      expect(draft.items.first.fixImagePaths, isEmpty);
    });

    test('merges missing open units when draft already has a photo', () {
      final prior = Inspection(
        id: 'old',
        siteId: 's1',
        buildingCode: 'B6',
        inspectionDate: DateTime(2026, 8, 7),
        items: [
          _item(
            index: 1,
            response: ChecklistResponse.no,
            pairs: [
              InspectionPhotoPair(id: 'a', issuePath: 'a.jpg'),
              InspectionPhotoPair(id: 'b', issuePath: 'b.jpg'),
            ],
          ),
        ],
      );
      final draft = Inspection(
        id: 'new',
        siteId: 's1',
        buildingCode: 'B6',
        inspectionDate: DateTime(2026, 8, 7),
        items: [
          _item(
            index: 1,
            response: ChecklistResponse.no,
            pairs: [InspectionPhotoPair(id: 'a', issuePath: 'a.jpg')],
          ),
        ],
      );

      final changed = applyOpenProblemCarryForward(
        current: draft,
        sourceByIndex: {for (final i in prior.items) i.itemIndex: i},
      );

      expect(changed, isTrue);
      expect(draft.items.first.issueImagePaths.toSet(), {'a.jpg', 'b.jpg'});
    });
  });

  group('issue open age tooltips', () {
    test('includes open duration and SLA', () {
      final older = Inspection(
        id: 'd1',
        siteId: 's1',
        buildingCode: 'B6',
        inspectionDate: DateTime(2026, 8, 5),
        createdAt: DateTime(2026, 8, 5, 8),
        items: [
          _item(
            index: 1,
            response: ChecklistResponse.no,
            overdue: 2,
            pairs: [InspectionPhotoPair(id: 'p1', issuePath: 'path/issue.jpg')],
          ),
        ],
      );
      final current = Inspection(
        id: 'd2',
        siteId: 's1',
        buildingCode: 'B6',
        inspectionDate: DateTime(2026, 8, 7),
        createdAt: DateTime(2026, 8, 7, 10),
        items: [
          _item(
            index: 1,
            response: ChecklistResponse.no,
            overdue: 2,
            pairs: [InspectionPhotoPair(id: 'p1', issuePath: 'path/issue.jpg')],
          ),
        ],
      );
      final tips = buildIssueOpenTooltips(
        inspection: current,
        history: [older],
        overdueIndexes: {1},
        language: 'en',
        asOf: DateTime(2026, 8, 7, 12),
      );
      expect(tips['path/issue.jpg'], contains('Open for'));
      expect(tips['path/issue.jpg'], contains('Fix deadline: 2 days'));
      expect(tips['path/issue.jpg'], contains('OVERDUE'));
    });
  });
}
