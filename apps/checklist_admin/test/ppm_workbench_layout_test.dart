import 'package:checklist_admin/design/checkadmin_theme.dart';
import 'package:checklist_admin/screens/ppm_tab.dart';
import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PPM dashboard stays responsive at 320dp Arabic RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = Profile(
      id: 'profile-a',
      fullName: 'Admin',
      email: 'a@example.com',
      role: UserRole.superAdmin,
      isActive: true,
      approvalStatus: ApprovalStatus.approved,
      homeOrganizationId: 'org-a',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: CheckAdminTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PpmTab(profile: profile, language: 'ar'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('الأصول والصيانة الوقائية'), findsOneWidget);
    expect(find.text('إضافة أصل'), findsOneWidget);
    expect(find.text('خطة PPM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
