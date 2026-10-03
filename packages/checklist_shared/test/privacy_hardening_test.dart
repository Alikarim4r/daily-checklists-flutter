import 'dart:io';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'public privacy and account deletion URLs stay on the official portal',
    () {
      expect(
        checklistPrivacyPolicyUrl,
        'https://inspection.alielhassan.com/privacy.html',
      );
      expect(
        checklistAccountDeletionUrl,
        'https://inspection.alielhassan.com/account-deletion.html',
      );
      expect(checklistSupportEmail, 'Support@alielhassan.com');
    },
  );

  test('structured diagnostics do not persist a durable user id', () {
    final source = File(
      'lib/src/services/structured_error_reporter.dart',
    ).readAsStringSync();
    expect(source, isNot(contains("'user_id': user.id")));
    expect(source, contains("client.from('client_error_logs').insert"));
  });

  test(
    'account deletion requires reauthentication and a server-side function',
    () {
      final source = File(
        'lib/src/repositories/auth_repository.dart',
      ).readAsStringSync();
      expect(source, contains('signInWithPassword'));
      expect(source, contains("'delete-account'"));
      expect(source, contains("'confirm': true"));
    },
  );

  test('shared settings expose only the official support email as contact', () {
    final source = File(
      'lib/src/widgets/checklist_settings_drawer.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('tel:')));
    expect(source, isNot(contains('+974')));
    expect(source, isNot(contains('AliMind')));
    expect(source, isNot(contains('Ali Karim')));
    expect(source, contains('checklistSupportEmail'));
  });
}
