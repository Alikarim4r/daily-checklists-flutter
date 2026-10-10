import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checklist_viewer/screens/inspection_dialogs.dart';

void main() {
  testWidgets('Combined PDF restores output and photo mode options', (
    tester,
  ) async {
    ReportRequest? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showReportOptionsSheet(context, 'en'),
              child: const Text('PDF report'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('PDF report'));
    await tester.pumpAndSettle();
    expect(find.text('Photo references and secure links'), findsOneWidget);
    expect(find.text('Include photos in the PDF'), findsOneWidget);
    expect(find.text('Print directly'), findsOneWidget);
    await tester.tap(find.text('Include photos in the PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create report'));
    await tester.pumpAndSettle();
    expect(picked?.photoMode, ReportPhotoMode.embedded);
    expect(picked?.delivery, ReportDelivery.share);
  });
}
