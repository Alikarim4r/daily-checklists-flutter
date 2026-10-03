import 'package:checklist_entry/design/checkin_theme.dart';
import 'package:checklist_entry/design/checkin_tokens.dart';
import 'package:checklist_entry/design/checkin_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Arabic field UI fits 320dp at 1.3x text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CheckInTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 760),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(title: const Text(checkInName)),
              bottomNavigationBar: CiBottomActions(
                primaryLabel: 'إرسال للمراجعة',
                secondaryLabel: 'حفظ المسودة',
                onPrimary: () {},
                onSecondary: () {},
              ),
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const CiWorkHeader(
                    title: 'جولة التفتيش اليومية للمبنى الرئيسي',
                    subtitle: 'الموقع الشمالي — مبنى الخدمات والمرافق',
                    progress: .42,
                    progressLabel: 'خمسة من اثني عشر بندًا مكتملًا',
                    meta: [
                      CiMeta('أربع مشكلات', icon: Icons.warning_amber_rounded),
                      CiMeta(
                        'صورتان مطلوبتان',
                        icon: Icons.add_a_photo_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CiQueuePanel(
                    children: [
                      CiQueueRow(
                        title: 'وزارة الأوقاف والشؤون الإسلامية',
                        subtitle: 'المجمع الإداري والخدمات الفنية',
                        meta: const [CiMeta('١٢ قائمة فحص')],
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('إرسال للمراجعة'), findsOneWidget);
    expect(find.text('وزارة الأوقاف والشؤون الإسلامية'), findsOneWidget);
  });

  testWidgets('bottom actions clear the system gesture safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CheckInTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(bottom: 34),
            viewPadding: EdgeInsets.only(bottom: 34),
          ),
          child: Scaffold(
            bottomNavigationBar: CiBottomActions(
              primaryLabel: 'Submit for review',
              secondaryLabel: 'Save',
              onPrimary: () {},
              onSecondary: () {},
            ),
          ),
        ),
      ),
    );

    final primaryBottom = tester.getBottomLeft(find.byType(FilledButton)).dy;
    expect(primaryBottom, lessThanOrEqualTo(844 - 34));
    expect(tester.takeException(), isNull);
  });

  test('light and dark themes preserve core contrast', () {
    double luminanceRatio(Color first, Color second) {
      final light = first.computeLuminance();
      final dark = second.computeLuminance();
      final high = light > dark ? light : dark;
      final low = light > dark ? dark : light;
      return (high + .05) / (low + .05);
    }

    expect(
      luminanceRatio(CheckInColors.light.ink, CheckInColors.light.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      luminanceRatio(CheckInColors.dark.ink, CheckInColors.dark.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      luminanceRatio(CheckInColors.light.inkMuted, CheckInColors.light.surface),
      greaterThanOrEqualTo(4.5),
    );
  });
}
