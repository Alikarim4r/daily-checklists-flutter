import 'package:checklist_shared/checklist_shared.dart';
import 'package:checklist_admin/screens/form_theme_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin role gates', () {
    expect(UserRole.superAdmin.canUseAdmin, isTrue);
    expect(UserRole.viewer.canUseAdmin, isFalse);
    expect(UserRole.superAdmin.canDeleteInspections, isTrue);
  });

  testWidgets('hierarchical theme picker saves the selected preset', (
    tester,
  ) async {
    String? savedTheme;
    String? savedAccent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormThemePickerDialog(
            language: 'en',
            scopeName: 'Doha Center',
            currentTheme: 'inherit',
            currentAccent: null,
            inheritedTheme: FormPaperTheme.teal,
            onSave: (theme, accent) async {
              savedTheme = theme;
              savedAccent = accent;
            },
          ),
        ),
      ),
    );

    expect(find.text('Inherit from parent level'), findsOneWidget);
    await tester.tap(find.text('Forest'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedTheme, 'forest');
    expect(savedAccent, isNull);
  });
}
