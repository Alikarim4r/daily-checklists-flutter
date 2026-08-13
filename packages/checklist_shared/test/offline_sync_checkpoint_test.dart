import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Inspection serverInspection() => Inspection(
    id: 'inspection-1',
    siteId: 'site-1',
    buildingCode: 'B2-DC',
    inspectionDate: DateTime(2026, 8, 10),
    inspectorName: 'Ali Karim',
    inspectionTime: '12:30 AM',
    floorLabel: 'ALL',
    signaturePath: 'org/site/inspection/signature.png',
    version: 8,
    items: [
      InspectionItem(
        itemIndex: 1,
        description: 'Item',
        response: ChecklistResponse.yes,
        actionsTaken: 'Checked',
      ),
    ],
  );

  Map<String, dynamic> queuedPayload() => {
    'inspectorName': 'Ali Karim',
    'inspectionTime': '12:30 AM',
    'floorLabel': 'ALL',
    'signaturePath': 'offline://signature/0/signature.png',
    'items': [
      {
        'item_index': 1,
        'response': 'yes',
        'actions_taken': 'Checked',
        'image_path': null,
        'issue_image_path': null,
        'fix_image_path': null,
      },
    ],
  };

  test('recognizes a save checkpoint with uploaded offline signature', () {
    expect(
      queuedInspectionMatchesServer(
        server: serverInspection(),
        payload: queuedPayload(),
      ),
      isTrue,
    );
  });

  test('rejects a concurrent server edit', () {
    final server = serverInspection()..items.first.actionsTaken = 'Changed';
    expect(
      queuedInspectionMatchesServer(server: server, payload: queuedPayload()),
      isFalse,
    );
  });

  test('discards a stale snapshot after the inspection is finalized', () {
    final server = serverInspection()
      ..status = InspectionStatus.submitted
      ..reviewStatus = ReviewStatus.approved
      ..version = 13;
    final payload = queuedPayload()
      ..['baseVersion'] = 4
      ..['action'] = 'submit';

    expect(
      resolveOfflineSync(server: server, payload: payload),
      OfflineSyncResolution.discardFinalizedSnapshot,
    );
  });

  test('resumes an exact checkpoint after multiple workflow version bumps', () {
    final server = serverInspection()..version = 11;
    final payload = queuedPayload()..['baseVersion'] = 7;

    expect(
      resolveOfflineSync(server: server, payload: payload),
      OfflineSyncResolution.resumeSavedCheckpoint,
    );
  });

  test('keeps a genuine draft conflict for explicit review', () {
    final server = serverInspection()
      ..version = 6
      ..items.first.actionsTaken = 'Newer server value';
    final payload = queuedPayload()..['baseVersion'] = 2;

    expect(
      resolveOfflineSync(server: server, payload: payload),
      OfflineSyncResolution.conflict,
    );
  });
}
