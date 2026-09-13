import 'dart:async';
import 'dart:io';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDirectory;
  final queue = OfflineInspectionQueue.instance;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'checklist-outbox-test-',
    );
    FlutterSecureStorage.setMockInitialValues({});
    await OfflineInspectionQueue.init(storagePath: tempDirectory.path);
  });

  setUp(() async {
    for (final entry in queue.pending()) {
      await queue.remove(entry.key);
    }
  });

  tearDownAll(() async {
    if (Hive.isBoxOpen('checklist_offline_queue')) {
      await Hive.box<String>('checklist_offline_queue').close();
    }
    await tempDirectory.delete(recursive: true);
  });

  test(
    'successful authoritative save removes only its stale snapshot',
    () async {
      await queue.enqueue(
        localId: 'inspection-1',
        payload: {'baseVersion': 8, 'items': const []},
      );
      var serverVersion = 8;
      await queue.saveAndReconcile(
        localId: 'inspection-1',
        save: () async {
          serverVersion = 9;
        },
        editRevision: () => 1,
        enqueueLatest: () async => fail('No newer edit should be enqueued'),
      );
      expect(serverVersion, 9);
      expect(queue.pending(), isEmpty);
    },
  );

  test(
    'successful evidence mutation reconciles its earlier outbox state',
    () async {
      await queue.enqueue(
        localId: 'inspection-photo',
        payload: {
          'baseVersion': 3,
          'items': [
            {'item_index': 1, 'issue_image_path': 'offline://old-photo'},
          ],
        },
      );
      String? serverPhoto;
      await queue.saveAndReconcile(
        localId: 'inspection-photo',
        save: () async {
          serverPhoto = 'stored/new-photo';
        },
        editRevision: () => 2,
        enqueueLatest: () async => fail('No newer edit should be enqueued'),
      );
      expect(serverPhoto, 'stored/new-photo');
      expect(queue.pending(), isEmpty);
    },
  );

  test(
    'newer autosave generation cannot be deleted by an older save',
    () async {
      await queue.enqueue(
        localId: 'inspection-race',
        payload: {'baseVersion': 4, 'marker': 'older'},
      );
      final response = Completer<void>();
      final saving = queue.saveAndReconcile(
        localId: 'inspection-race',
        save: () => response.future,
        editRevision: () => 1,
        enqueueLatest: () async => fail('Must not replace a newer generation'),
      );
      await queue.enqueue(
        localId: 'inspection-race',
        payload: {'baseVersion': 5, 'marker': 'newer'},
      );

      response.complete();
      await saving;
      expect(queue.pending().single.value['marker'], 'newer');
    },
  );

  test('transport failure preserves recoverable local work', () async {
    await queue.enqueue(
      localId: 'inspection-offline',
      payload: {'baseVersion': 2, 'marker': 'recoverable'},
    );
    await expectLater(
      queue.saveAndReconcile(
        localId: 'inspection-offline',
        save: () async => throw const SocketException('offline'),
        editRevision: () => 1,
        enqueueLatest: () async =>
            fail('A failed save must retain the original'),
      ),
      throwsA(isA<SocketException>()),
    );

    final queued = queue.pending().single.value;
    expect(queued['marker'], 'recoverable');
    expect((queued['_queue'] as Map)['status'], 'pending');
  });

  test('edits during a save are queued against the returned version', () async {
    await queue.enqueue(localId: 'changed', payload: {'baseVersion': 4});
    var revision = 1;
    var version = 4;
    await queue.saveAndReconcile(
      localId: 'changed',
      editRevision: () => revision,
      save: () async {
        revision++;
        version = 5;
      },
      enqueueLatest: () => queue.enqueue(
        localId: 'changed',
        payload: {'baseVersion': version, 'marker': 'unsaved-newer-edit'},
      ),
    );
    expect(queue.pending().single.value['baseVersion'], 5);
    expect(queue.pending().single.value['marker'], 'unsaved-newer-edit');
  });

  test(
    'successful save also reconciles a pre-generation legacy entry',
    () async {
      await Hive.box<String>(
        'checklist_offline_queue',
      ).put('legacy', '{"baseVersion":2,"items":[]}');
      await queue.saveAndReconcile(
        localId: 'legacy',
        save: () async {},
        editRevision: () => 1,
        enqueueLatest: () async {},
      );
      expect(queue.pending(), isEmpty);
    },
  );
}
