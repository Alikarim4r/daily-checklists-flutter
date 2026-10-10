import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Yes is blue only when Yes is ideal, otherwise red', () {
    final idealYes = InspectionItem(
      itemIndex: 1,
      description: 'Clean',
      defaultAnswer: 'Y',
      response: ChecklistResponse.yes,
    );
    final badYes = InspectionItem(
      itemIndex: 2,
      description: 'Leak present?',
      defaultAnswer: 'N',
      response: ChecklistResponse.yes,
    );
    expect(idealYes.checkColorFor(ChecklistResponse.yes), ColorCode.ok);
    expect(badYes.checkColorFor(ChecklistResponse.yes), ColorCode.problem);
  });
  test('No is blue only when No is ideal, otherwise red', () {
    final idealNo = InspectionItem(
      itemIndex: 1,
      description: 'Leak present?',
      defaultAnswer: 'N',
      response: ChecklistResponse.no,
    );
    final badNo = InspectionItem(
      itemIndex: 2,
      description: 'Clean?',
      defaultAnswer: 'Y',
      response: ChecklistResponse.no,
    );
    expect(idealNo.checkColorFor(ChecklistResponse.no), ColorCode.ok);
    expect(badNo.checkColorFor(ChecklistResponse.no), ColorCode.problem);
  });
  test(
    'N/A is black for either ideal answer and unselected blank stays empty',
    () {
      for (final ideal in ['Y', 'N']) {
        final item = InspectionItem(
          itemIndex: 1,
          description: 'Item',
          defaultAnswer: ideal,
          response: ChecklistResponse.na,
        );
        expect(item.checkColorFor(ChecklistResponse.na), ColorCode.na);
        expect(item.checkColorFor(ChecklistResponse.yes), ColorCode.empty);
        expect(item.checkColorFor(ChecklistResponse.no), ColorCode.empty);
      }
    },
  );
}
