import 'package:checklist_entry/main.dart';
import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('zone hierarchy text stays readable in dark mode', (
    tester,
  ) async {
    ChecklistChrome.use(ChecklistBrand.entry);
    const profile = Profile(
      id: 'user-1',
      fullName: 'Field User',
      email: 'field@example.com',
      role: UserRole.technician,
      isActive: true,
      approvalStatus: ApprovalStatus.approved,
    );
    const section = OrgBrowseSection(
      organization: Organization(
        id: 'org-1',
        nameEn: 'Ministry of Awqaf and Islamic Affairs',
        nameAr: 'وزارة الأوقاف والشؤون الإسلامية',
      ),
      zones: [
        ZoneBrowseSection(
          zone: Zone(
            id: 'zone-1',
            organizationId: 'org-1',
            code: 'DOHA',
            nameEn: 'Doha Center',
          ),
          groups: [
            CampusChecklistGroup(campus: null, checklists: []),
            CampusChecklistGroup(campus: null, checklists: []),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ChecklistChrome.darkTheme(),
          home: EntryZonesScreen(
            profile: profile,
            section: section,
            language: 'en',
            onLanguageChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.text('Select a zone')).style?.color,
      ChecklistChrome.darkInkMuted,
    );
    expect(
      tester.widget<Text>(find.text('Doha Center')).style?.color,
      ChecklistChrome.darkInk,
    );
    expect(
      tester.widget<Text>(find.text('2 sites')).style?.color,
      ChecklistChrome.darkInkMuted,
    );
  });
}
