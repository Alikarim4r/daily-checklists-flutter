import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

const testPath = 'org/site/inspection/01_issue_uploaded.jpg';

Inspection record({bool linked = false, int version = 1, bool fix = false}) {
  final item = InspectionItem(
    itemIndex: 1,
    description: 'Tap working?',
    response: ChecklistResponse.no,
  );
  if (linked) {
    if (fix) {
      item.appendFixImage(testPath);
    } else {
      item.appendIssueImage(testPath);
    }
  }
  return Inspection(
    id: 'inspection',
    siteId: 'site',
    buildingCode: 'B1',
    inspectionDate: DateTime(2026, 10, 10),
    items: [item],
    version: version,
  );
}

void main() {
  test(
    'confirms issue photo only after remote saved inspection contains path',
    () async {
      final local = record(linked: true);
      var saveCount = 0;
      final remote = await VerifiedPhotoSave.saveAndConfirm(
        local: local,
        photoPath: testPath,
        save: (inspection) async {
          saveCount++;
          inspection.version = 2;
        },
        reload: (id) async => record(linked: true, version: 2),
      );
      expect(saveCount, 1);
      expect(local.version, 2);
      expect(VerifiedPhotoSave.isLinked(remote, testPath), isTrue);
    },
  );
  test(
    'confirms image when RPC committed but network lost its response',
    () async {
      final local = record(linked: true);
      var saveCount = 0;
      final remote = await VerifiedPhotoSave.saveAndConfirm(
        local: local,
        photoPath: testPath,
        save: (inspection) async {
          saveCount++;
          throw StateError('504 timeout');
        },
        reload: (id) async => record(linked: true, version: 2),
      );
      expect(saveCount, 1);
      expect(local.version, 2);
      expect(VerifiedPhotoSave.isLinked(remote, testPath), isTrue);
    },
  );
  test(
    'does not claim success when uploaded evidence is not linked to item',
    () async {
      final local = record(linked: true);
      var saveCount = 0;
      await expectLater(
        VerifiedPhotoSave.saveAndConfirm(
          local: local,
          photoPath: testPath,
          save: (inspection) async {
            saveCount++;
          },
          reload: (id) async => record(linked: false, version: 1),
        ),
        throwsStateError,
      );
      expect(saveCount, 1);
      expect(VerifiedPhotoSave.isLinked(local, testPath), isTrue);
    },
  );
  test('stale server version rejects save, never blindly retries it', () async {
    final local = record(linked: true);
    var calls = 0;
    await expectLater(
      VerifiedPhotoSave.saveAndConfirm(
        local: local,
        photoPath: testPath,
        save: (inspection) async {
          calls++;
          throw StateError('version conflict');
        },
        reload: (id) async => record(linked: false, version: 2),
      ),
      throwsA(isA<StateError>()),
    );
    expect(calls, 1);
    expect(local.version, 1);
    expect(VerifiedPhotoSave.isLinked(local, testPath), isTrue);
  });
  test('recognizes fix photos inside paired evidence snapshot', () {
    final remote = record(linked: true, fix: true);
    expect(VerifiedPhotoSave.isLinked(remote, testPath), isTrue);
    expect(VerifiedPhotoSave.isLinked(remote, 'different-path.jpg'), isFalse);
  });
  test(
    'no remote record fails verification rather than showing saved',
    () async {
      await expectLater(
        VerifiedPhotoSave.saveAndConfirm(
          local: record(linked: true),
          photoPath: testPath,
          save: (_) async {},
          reload: (_) async => null,
        ),
        throwsStateError,
      );
    },
  );
}
