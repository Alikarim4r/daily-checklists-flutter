import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:checklist_entry/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production app launches a Material frame without Flutter errors',
    (tester) async {
      FlutterErrorDetails? capturedError;
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        capturedError ??= details;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await app.main();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(capturedError, isNull);
    },
  );
}
