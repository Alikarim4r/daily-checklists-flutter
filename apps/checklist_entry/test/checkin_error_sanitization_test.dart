import 'package:checklist_entry/design/checkin_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const unsafeErrors = <String>[
    'PostgrestException(message: permission denied for relation, code: 42501)',
    'StorageException(message: upload failed, statusCode: 403)',
    'SQLSTATE P0001 row-level security policy violation',
    '{"code":"23505","details":"duplicate key"}',
    'SocketException: Failed host lookup: api.example.invalid',
    'JWT expired: refresh token rejected',
    'Sync conflict: server version 9, offline version 8',
  ];

  for (final language in const ['en', 'ar']) {
    test('backend diagnostics are sanitized in $language', () {
      for (final raw in unsafeErrors) {
        final message = checkInUserMessage(Exception(raw), language);
        expect(message, isNotEmpty);
        expect(containsUnsafeDiagnostic(message), isFalse, reason: message);
        expect(message, isNot(contains('42501')));
        expect(message, isNot(contains('23505')));
      }
    });
  }

  test('known validation failures are actionable', () {
    expect(
      checkInUserMessage(
        Exception('All checklist items must be answered; missing: 2, 7'),
        'en',
      ),
      contains('2, 7'),
    );
    expect(
      checkInUserMessage(Exception('Inspector name is required'), 'ar'),
      contains('اسم المفتش'),
    );
    expect(
      checkInUserMessage(Exception('signature is required'), 'en'),
      contains('signature'),
    );
  });
}
