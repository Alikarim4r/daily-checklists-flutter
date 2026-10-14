import 'package:checklist_viewer/design/checkview_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Inactive page animation reaches transparent and reopens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var active = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                ElevatedButton(
                  onPressed: () => setState(() => active = 1),
                  child: const Text('Open Operations'),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => active = 0),
                  child: const Text('Back to Inspections'),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      CvPagePresence(
                        active: active == 0,
                        child: const Center(child: Text('Inspections list')),
                      ),
                      CvPagePresence(
                        active: active == 1,
                        child: const Center(
                          child: Text('Operations dashboard'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      1,
    );
    await tester.tap(find.text('Open Operations'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      0,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).last).opacity,
      1,
    );
    final fades = find.descendant(
      of: find.byType(AnimatedOpacity).first,
      matching: find.byType(FadeTransition),
    );
    expect(fades, findsWidgets);
    expect(tester.widget<FadeTransition>(fades.first).opacity.value, 0);
    await tester.tap(find.text('Back to Inspections'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      1,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).last).opacity,
      0,
    );
    expect(tester.takeException(), isNull);
  });
}
