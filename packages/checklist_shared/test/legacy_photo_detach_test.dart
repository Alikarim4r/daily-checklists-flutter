import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const issueA = 'org/site/ins/01_old_issue.jpg';
  const fixA = 'org/site/ins/01_old_fix.jpg';
  const issueB = 'org/site/ins/02_old_issue.jpg';
  const fixB = 'org/site/ins/02_old_fix.jpg';

  InspectionItem itemWithPhotos() {
    final item = InspectionItem(
      id: 'item-1',
      itemIndex: 1,
      description: 'Leak check',
      defaultAnswer: 'Y',
      response: ChecklistResponse.yes,
    );
    item.appendIssueImage(issueA);
    item.appendFixImage(fixA);
    item.appendIssueImage(issueB);
    item.appendFixImage(fixB);
    return item;
  }

  test(
    'removing one historical issue preserves every other image and pair',
    () {
      final item = itemWithPhotos();
      final savedPairs = item.photoPairs;
      item.removeIssueImage(issueA, pairId: savedPairs.first.id);
      expect(item.issueImagePaths, [issueB]);
      expect(item.fixImagePaths, [fixA, fixB]);
      expect(item.photoPairs.length, 2);
      expect(item.photoPairs.first.fixPath, fixA);
      expect(item.imagePath, issueB);
      expect(item.toRpcJson()['issue_image_path'], contains(issueB));
      expect(item.toRpcJson()['issue_image_path'], isNot(contains(issueA)));
      expect(item.toRpcJson()['fix_image_path'], contains(fixA));
    },
  );

  test('removing one old fix keeps issue and other repairs intact', () {
    final item = itemWithPhotos();
    final firstId = item.photoPairs.first.id;
    item.removeFixImage(fixA, pairId: firstId);
    expect(item.issueImagePaths, [issueA, issueB]);
    expect(item.fixImagePaths, [fixB]);
    expect(item.photoPairs.first.id, firstId);
    expect(item.photoPairs.first.fixPath, isNull);
    expect(item.response, ChecklistResponse.yes);
  });

  test('removing the last fix reopens a problem answer', () {
    final item = InspectionItem(
      itemIndex: 3,
      description: 'Issue',
      defaultAnswer: 'Y',
      response: ChecklistResponse.yes,
    );
    item.appendIssueImage(issueA);
    item.appendFixImage(fixA);
    item.removeFixImage(fixA);
    expect(item.response, ChecklistResponse.no);
    expect(item.issueImagePaths, [issueA]);
    expect(item.fixImagePaths, isEmpty);
  });

  test('failed server detach can restore original links and answer', () {
    final item = itemWithPhotos();
    final oldPairs = item.photoPairs;
    final oldResponse = item.response;
    item.removeIssueImage(issueB);
    expect(item.issueImagePaths, [issueA]);
    item.setPhotoPairs(oldPairs);
    item.response = oldResponse;
    expect(item.issueImagePaths, [issueA, issueB]);
    expect(item.fixImagePaths, [fixA, fixB]);
    expect(item.response, oldResponse);
  });
}
