import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget sampleSheet() => LayoutBuilder(
  builder: (context, constraints) {
    const paperWidth = 794.0;
    final width = math.min(paperWidth, math.max(280.0, constraints.maxWidth));
    final sheet = Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Daily Facilities Inspection Report'),
            for (var i = 0; i < 24; i++)
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Text('Question $i'),
                    const Spacer(),
                    const Text('Yes  No  N/A'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return Center(
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: width >= paperWidth
            ? SizedBox(width: paperWidth, child: sheet)
            : SizedBox(
                width: width,
                child: FittedBox(
                  alignment: Alignment.topCenter,
                  fit: BoxFit.fitWidth,
                  child: SizedBox(width: paperWidth, child: sheet),
                ),
              ),
      ),
    );
  },
);

void main() {
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('stacked A4 paper remains laid out at $width dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: 5,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(8),
                child: sampleSheet(),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Daily Facilities Inspection Report'), findsWidgets);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
