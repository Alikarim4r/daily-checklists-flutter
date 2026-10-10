import 'package:checklist_viewer/widgets/responsive_filter_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> verify(WidgetTester tester, double width, int total) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 980);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final keys = [for (var i = 0; i < total; i++) Key('field-$i')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ResponsiveFilterGrid(
                fields: [
                  for (var i = 0; i < total; i++)
                    Container(
                      key: keys[i],
                      height: 58,
                      alignment: Alignment.centerLeft,
                      child: Text(i == total - 1 ? 'Completion' : 'Facet $i'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final rects = [for (final k in keys) tester.getRect(find.byKey(k))];
    expect(tester.takeException(), isNull);
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(7.9));
      expect(rect.right, lessThanOrEqualTo(width - 7.9));
      expect(rect.width, greaterThan(0));
    }
    // Adjacent items occupy the same row or the next one; never a remote
    // horizontally scrolled field. Every row reaches both screen margins.
    final rows = <double, List<Rect>>{};
    for (final rect in rects) {
      rows.putIfAbsent(rect.top, () => []).add(rect);
    }
    for (final row in rows.values) {
      expect(row.first.left, closeTo(8, 0.01));
      expect(row.last.right, closeTo(width - 8, 0.01));
      for (final r in row) {
        expect(r.width, closeTo(row.first.width, 0.01));
      }
    }
    if (width >= 1000) {
      expect(rows.length, 1);
      expect(rects.last.top, rects.first.top);
    }
    expect(find.text('Completion'), findsOneWidget);
  }

  testWidgets(
    'Desktop 1440 with 8 filters including Completion fills width',
    (tester) => verify(tester, 1440, 8),
  );
  testWidgets(
    'Desktop 1440 with only 3 authorized filters grows fields',
    (tester) => verify(tester, 1440, 3),
  );
  testWidgets(
    'Desktop 1024 keeps every filter in same row',
    (tester) => verify(tester, 1024, 8),
  );
  testWidgets(
    'Mobile 390 wraps and keeps Completion visible',
    (tester) => verify(tester, 390, 8),
  );
  testWidgets(
    'Mobile 320 wraps without overflow',
    (tester) => verify(tester, 320, 7),
  );
  testWidgets(
    'Tablet 980 shares width per row without blank right gap',
    (tester) => verify(tester, 980, 8),
  );
}
