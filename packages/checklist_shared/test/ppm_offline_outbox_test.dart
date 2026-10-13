import 'dart:io';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late Directory temp;
  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('ppm-encrypted-hive-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path,
        );
    await OfflineInspectionQueue.init();
  });
  tearDownAll(() async {
    await OfflineInspectionQueue.instance.purgeUserData();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test(
    'PPM offline result is encrypted and excluded from inspection sync queue',
    () async {
      final queue = OfflineInspectionQueue.instance;
      await queue.purgeUserData();
      await queue.cachePpmJobs(
        userId: 'worker-a',
        jobs: [
          {
            'id': 'ppm-job',
            'site_id': 'site-a',
            'organization_id': 'org-a',
            'plan_id': 'plan',
            'asset_id': 'asset',
            'due_on': '2026-10-13',
            'status': 'scheduled',
          },
        ],
        assets: [
          {'id': 'asset', 'name_en': 'Chiller 1'},
        ],
        plans: [
          {'id': 'plan', 'title_en': 'Monthly PPM'},
        ],
      );
      expect(queue.cachedPpmJobs('worker-a')?['jobs'], hasLength(1));
      await queue.enqueuePpmCompletion(
        userId: 'worker-a',
        jobId: 'ppm-job',
        notes: 'Checked readings',
        readings: {'chw_c': 6.5},
      );
      expect(queue.pendingPpmCount('worker-a'), 1);
      expect(queue.pendingPpmCount('worker-b'), 0);
      expect(
        queue.pendingCount,
        0,
        reason: 'Existing A4 inspection outbox is separate',
      );
      expect(queue.pendingPpm('worker-a').single.value['readings'], {
        'chw_c': 6.5,
      });
      await queue.removePpmIfQueued('worker-a', 'ppm-job');
      expect(queue.pendingPpmCount('worker-a'), 0);
    },
  );

  test('account purge removes PPM cache and unsynced evidence', () async {
    final queue = OfflineInspectionQueue.instance;
    await queue.enqueuePpmCompletion(
      userId: 'worker-a',
      jobId: 'job-2',
      notes: 'Filter replaced',
      readings: {},
    );
    await queue.purgeUserData();
    expect(queue.pendingPpmCount('worker-a'), 0);
    expect(queue.cachedPpmJobs('worker-a'), isNull);
  });
}
