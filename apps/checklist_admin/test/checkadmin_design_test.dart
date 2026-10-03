import 'package:checklist_admin/design/checkadmin_theme.dart';
import 'package:checklist_admin/design/checkadmin_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpNarrow(WidgetTester tester, ThemeData theme) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: Scaffold(
          body: ListView(
            children: [
              const CaPageHeader(
                eyebrow: 'الحوكمة',
                title: 'مركز إدارة الفحوصات',
                subtitle: 'إدارة الهيكل والقوائم والمستخدمين والاعتمادات',
              ),
              const SizedBox(height: 8),
              const CaMetricStrip(
                metrics: [
                  CaMetric(
                    label: 'قيد المراجعة',
                    value: '12',
                    icon: Icons.approval_outlined,
                  ),
                  CaMetric(
                    label: 'المستخدمون',
                    value: '48',
                    icon: Icons.people_outline,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CaCommandRow(
                leading: const Icon(Icons.account_tree_outlined),
                title: 'وزارة التربية والتعليم والتعليم العالي',
                subtitle: 'إدارة الهيكل والمناطق والمواقع',
                onTap: () {},
              ),
              const SizedBox(height: 8),
              const CaInlineNotice(
                title: 'تنبيه إداري',
                message: 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
                tone: CaTone.warning,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('Arabic admin surfaces fit 320dp with large text in light mode', (
    tester,
  ) async {
    await pumpNarrow(tester, CheckAdminTheme.light);
  });

  testWidgets('Arabic admin surfaces fit 320dp with large text in dark mode', (
    tester,
  ) async {
    await pumpNarrow(tester, CheckAdminTheme.dark);
  });
}
