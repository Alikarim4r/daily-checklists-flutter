import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 encode/decode keeps pair linkage', () {
    final pairs = [
      InspectionPhotoPair(
        id: 'a',
        issuePath: 'org/issue_1.jpg',
        fixPath: 'org/fix_1.jpg',
      ),
      InspectionPhotoPair(id: 'b', issuePath: 'org/issue_2.jpg'),
    ];
    final encoded = encodePhotoPairsV2(pairs);
    expect(isPhotoPairsV2Payload(encoded), isTrue);
    final decoded = decodePhotoPairs(issueImagePath: encoded);
    expect(decoded, hasLength(2));
    expect(decoded[0].id, 'a');
    expect(decoded[0].issuePath, 'org/issue_1.jpg');
    expect(decoded[0].fixPath, 'org/fix_1.jpg');
    expect(decoded[1].hasFix, isFalse);
  });

  test('legacy lists zip into pairs by index', () {
    final decoded = decodePhotoPairs(
      issueImagePath: '["issue:org/i1.jpg","issue:org/i2.jpg"]',
      fixImagePath: 'fix:org/f1.jpg',
    );
    expect(decoded, hasLength(2));
    expect(decoded[0].issuePath, 'org/i1.jpg');
    expect(decoded[0].fixPath, 'org/f1.jpg');
    expect(decoded[1].issuePath, 'org/i2.jpg');
    expect(decoded[1].hasFix, isFalse);
  });

  test('InspectionItem addPairWithIssue and setFixForPair', () {
    final item = InspectionItem(itemIndex: 1, description: 'AC');
    final id1 = item.addPairWithIssue('path/issue_a.jpg');
    final id2 = item.addPairWithIssue('path/issue_b.jpg');
    item.setFixForPair(id1, 'path/fix_a.jpg');
    expect(item.photoPairs, hasLength(2));
    expect(
      item.photoPairs.firstWhere((p) => p.id == id1).fixPath,
      'path/fix_a.jpg',
    );
    expect(item.photoPairs.firstWhere((p) => p.id == id2).hasFix, isFalse);
    expect(isPhotoPairsV2Payload(item.issueImagePath), isTrue);
    expect(item.remarkPhotos, hasLength(3));
  });

  test('closing problem to ideal requires fix photo', () {
    final item = InspectionItem(
      itemIndex: 1,
      description: 'Leak?',
      defaultAnswer: 'N',
      response: ChecklistResponse.yes, // problem
    );
    item.addPairWithIssue('issue.jpg');
    final blocked = item.trySetResponse(ChecklistResponse.no, language: 'en');
    expect(blocked, isNotNull);
    expect(item.response, ChecklistResponse.yes);

    item.setFixForPair(item.photoPairs.first.id, 'fix.jpg');
    expect(item.response, ChecklistResponse.no); // auto ideal
    expect(item.isIdealAnswer, isTrue);
  });

  test('ideal default Yes: fix flips from No problem to Yes', () {
    final item = InspectionItem(
      itemIndex: 2,
      description: 'OK?',
      defaultAnswer: 'Y',
      response: ChecklistResponse.no,
    );
    final id = item.addPairWithIssue('i.jpg');
    item.setFixForPair(id, 'f.jpg');
    expect(item.response, ChecklistResponse.yes);
  });
}
