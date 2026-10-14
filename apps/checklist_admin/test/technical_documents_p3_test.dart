import 'package:checklist_admin/screens/technical_payload_form.dart';
import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('All P3 document kinds are represented in the global library', () {
    expect(technicalDocumentKinds.keys, {
      'method_statement',
      'risk_assessment',
      'jsa',
      'sop',
      'cop',
      'ptw',
      'itp',
      'ncr',
    });
    for (final kind in technicalDocumentKinds.keys) {
      expect(technicalDocumentKindsAr[kind], isNotEmpty);
    }
  });

  test(
    'Technical document/version JSON preserves canonical audit metadata',
    () {
      final document = TechnicalDocument.fromJson({
        'id': 'doc-1',
        'organization_id': 'org-1',
        'document_code': 'RA-001',
        'document_kind': 'risk_assessment',
        'title': 'Risk register',
        'status': 'approved',
        'created_by': 'user-1',
        'site_id': 'site-1',
        'current_version': 3,
        'approved_version': 3,
      });
      expect(document.isApproved, isTrue);
      expect(document.isEditable, isFalse);
      expect(document.labelFor('ar'), 'تقييم المخاطر');
      final v = TechnicalVersion.fromJson({
        'document_id': 'doc-1',
        'version_no': 3,
        'payload': {
          'hazards': [
            {'hazard': 'Slipping'},
          ],
        },
        'author_id': 'user-1',
        'created_at': '2026-10-14T10:00:00Z',
      });
      expect(v.versionNo, 3);
      expect(v.payload['hazards'], hasLength(1));
    },
  );

  testWidgets('Risk assessment editor emits a numeric 5x5 risk matrix', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? payload;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 780,
            child: TechnicalPayloadForm(
              kind: 'risk_assessment',
              language: 'en',
              onChanged: (value) => payload = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(payload, isNotNull);
    expect((payload!['hazards'] as List).length, 1);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Electrical energy');
    await tester.enterText(fields.at(1), 'Authorized isolation and LOTO');
    await tester.pump();
    final row = (payload!['hazards'] as List).first as Map;
    expect(row['hazard'], 'Electrical energy');
    expect(row['controls'], 'Authorized isolation and LOTO');
    expect(row['severity'], 3);
    expect(row['residual_severity'], 1);
  });

  testWidgets('ITP editor supports adding auditable checkpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(450, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? payload;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 920,
            child: TechnicalPayloadForm(
              kind: 'itp',
              language: 'ar',
              onChanged: (value) => payload = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect((payload!['checkpoints'] as List).length, 1);
    await tester.tap(find.text('إضافة نقطة فحص'));
    await tester.pumpAndSettle();
    expect((payload!['checkpoints'] as List).length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Method statement editor generates ordered steps', (
    tester,
  ) async {
    Map<String, dynamic>? payload;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 680,
            child: TechnicalPayloadForm(
              kind: 'method_statement',
              language: 'en',
              onChanged: (value) => payload = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Scope of work'),
      'Replacement of equipment',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Steps — one per line'),
      'Isolate\nVerify zero energy\nTest',
    );
    await tester.pump();
    expect(payload!['scope'], 'Replacement of equipment');
    expect(payload!['steps'], ['Isolate', 'Verify zero energy', 'Test']);
  });
}
