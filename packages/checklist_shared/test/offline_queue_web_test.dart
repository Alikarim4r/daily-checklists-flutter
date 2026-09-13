@TestOn('browser')
library;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'browser outbox generates distinct snapshots without integer overflow',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      await OfflineInspectionQueue.init(storagePath: 'browser-regression');
      final queue = OfflineInspectionQueue.instance;
      try {
        await queue.enqueue(
          localId: 'browser-test',
          payload: {'baseVersion': 1},
        );
        final first = queue.generationFor('browser-test');
        await queue.enqueue(
          localId: 'browser-test',
          payload: {'baseVersion': 2},
        );
        expect(queue.generationFor('browser-test'), isNot(first));
        expect(await queue.removeIfGeneration('browser-test', first), isFalse);
        expect(queue.pending().single.value['baseVersion'], 2);
    } finally {
      await Hive.box<String>('checklist_offline_queue').close();
      await Hive.deleteBoxFromDisk('checklist_offline_queue');
      }
    },
  );
}
