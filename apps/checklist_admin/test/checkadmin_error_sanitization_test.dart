import 'package:checklist_admin/design/checkadmin_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rawFailures = <String>[
    'PostgrestException(message: permission denied, code: P0001)',
    'StorageException(message: upload failed, statusCode: 403)',
    'SQLSTATE 23505 duplicate key value violates unique constraint',
    'new row violates row-level security policy',
    'SocketException: Failed host lookup: api.example.invalid',
    'JWT expired; refresh token invalid',
  ];

  for (final language in const ['en', 'ar']) {
    test('technical diagnostics are hidden from users in $language', () {
      for (final raw in rawFailures) {
        final message = checkAdminUserMessage(Exception(raw), language);
        expect(message, isNotEmpty);
        expect(checkAdminContainsUnsafeDiagnostic(message), isFalse);
        expect(message.toLowerCase(), isNot(contains('exception')));
        expect(message.toLowerCase(), isNot(contains('sqlstate')));
      }
    });
  }
}
