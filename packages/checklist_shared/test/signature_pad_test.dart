import 'dart:convert';
import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signature/signature.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('the upper edge of the signature pad accepts drawing', (
    tester,
  ) async {
    final controller = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.blue,
      exportBackgroundColor: Colors.white,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ChecklistSignatureEditor(
                controller: controller,
                title: 'Signature',
                clearLabel: 'Clear signature',
                onClear: controller.clear,
                height: 160,
              ),
            ),
          ),
        ),
      ),
    );

    final canvas = find.byKey(const ValueKey('checklist-signature-canvas'));
    final toolbar = find.byKey(const ValueKey('checklist-signature-toolbar'));
    final clear = find.byKey(const ValueKey('checklist-signature-clear'));
    final canvasRect = tester.getRect(canvas);

    expect(tester.getRect(toolbar).overlaps(canvasRect), isFalse);
    expect(tester.getRect(clear).overlaps(canvasRect), isFalse);

    final topLeft = tester.getTopLeft(canvas);
    final gesture = await tester.startGesture(topLeft + const Offset(20, 3));
    await gesture.moveBy(const Offset(130, 30));
    await gesture.up();
    await tester.pump();

    expect(controller.isNotEmpty, isTrue);
    expect(controller.points.any((point) => point.offset.dy < 12), isTrue);
  });

  testWidgets('a saved signature is visible before an editable blank pad', (
    tester,
  ) async {
    final controller = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.blue,
      exportBackgroundColor: Colors.white,
    );
    addTearDown(controller.dispose);
    final preview = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP4z8Dwn4GBgYGJAQoAHgQCAQFQJhoAAAAASUVORK5CYII=',
      ),
    );
    final inspection = Inspection(
      id: 'inspection',
      siteId: 'site',
      buildingCode: 'B1',
      inspectionDate: DateTime(2026, 8, 12),
      signaturePath: 'org/site/inspection/signature.png',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: ChecklistFormLayout(
                inspection: inspection,
                language: 'en',
                signatureController: controller,
                signaturePreviewBytes: preview,
                onClearSignature: controller.clear,
                forceTableLayout: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsWidgets);
    expect(
      find.byKey(const ValueKey('checklist-signature-canvas')),
      findsNothing,
    );
  });
}
