import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  testWidgets('theme-aware ink tokens follow light and dark color schemes', (
    tester,
  ) async {
    for (final theme in [
      ChecklistChrome.theme(),
      ChecklistChrome.darkTheme(),
    ]) {
      late Color ink;
      late Color muted;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: Builder(
            builder: (context) {
              ink = ChecklistChrome.inkFor(context);
              muted = ChecklistChrome.inkMutedFor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ink, theme.colorScheme.onSurface);
      expect(muted, theme.colorScheme.onSurfaceVariant);
    }

    final darkCard = Color.alphaBlend(
      ChecklistChrome.darkSurface.withValues(
        alpha: ChecklistChrome.listSurfaceOpacity,
      ),
      ChecklistChrome.darkCanvas,
    );
    expect(_contrastRatio(ChecklistChrome.darkInk, darkCard), greaterThan(4.5));
    expect(
      _contrastRatio(ChecklistChrome.darkInkMuted, darkCard),
      greaterThan(4.5),
    );
  });

  testWidgets('compact operations cards stay readable in dark mode', (
    tester,
  ) async {
    ChecklistChrome.use(ChecklistBrand.viewer);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ChecklistChrome.darkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ChecklistPulseCard(
                  title: 'Follow-up needs action',
                  subtitle:
                      'The pulse combines compliance, approvals, and active issues.',
                  progress: 0.04,
                  progressLabel: '4%',
                  color: const Color(0xFFB91C1C),
                  icon: Icons.notification_important_outlined,
                  trailing: const Text('10 actions'),
                ),
                const ChecklistMetricTile(
                  label: 'Open problems',
                  value: '10',
                  icon: Icons.build_circle_outlined,
                  color: Color(0xFFEA580C),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text('Follow-up needs action'));
    expect(title.style?.color, ChecklistChrome.darkInk);
    final label = tester.widget<Text>(find.text('Open problems'));
    expect(label.style?.color, ChecklistChrome.darkInkMuted);
  });

  testWidgets('vector background and 50% list cards render in both modes', (
    tester,
  ) async {
    for (final theme in [
      ChecklistChrome.theme(),
      ChecklistChrome.darkTheme(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const ChecklistAppBackground(
            child: Center(child: ChecklistBrandCard(child: Text('List'))),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      final cardColor = theme.cardTheme.color;
      expect(cardColor, isNotNull);
      expect(cardColor!.a, closeTo(ChecklistChrome.listSurfaceOpacity, 0.001));

      final ink = tester.widget<Ink>(find.byType(Ink));
      final decoration = ink.decoration! as BoxDecoration;
      final colors = decoration.gradient!.colors;
      expect(
        colors.every(
          (color) =>
              (color.a - ChecklistChrome.listSurfaceOpacity).abs() < 0.001,
        ),
        isTrue,
      );
    }
  });
}
