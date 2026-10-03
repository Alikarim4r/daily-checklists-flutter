import 'dart:io';
import 'dart:math' as math;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:checklist_viewer/design/checkview_errors.dart';
import 'package:checklist_viewer/design/checkview_theme.dart';
import 'package:checklist_viewer/design/checkview_tokens.dart';
import 'package:checklist_viewer/design/checkview_widgets.dart';
import 'package:checklist_viewer/screens/checkview_settings_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecurityStore extends Fake implements SessionSecurityStore {
  @override
  bool biometricEnabled = false;

  @override
  Future<void> load() async {}

  @override
  Future<void> setBiometricEnabled(bool value) async =>
      biometricEnabled = value;
}

class _FakeBiometrics extends Fake implements BiometricAuthService {
  @override
  Future<bool> canUseBiometrics() async => false;

  @override
  Future<String> preferredLabel({required bool isArabic}) async => 'Biometrics';
}

const _profile = Profile(
  id: 'p1',
  fullName: 'Test Reviewer',
  email: 'reviewer@example.com',
  role: UserRole.siteAdmin,
  isActive: true,
  approvalStatus: ApprovalStatus.approved,
);

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

Widget _host(Widget child, {String language = 'en', double width = 360}) {
  return MaterialApp(
    theme: CheckViewTheme.light,
    home: Directionality(
      textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: width,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
}

void main() {
  group('CheckView tokens', () {
    for (final colors in [CheckViewColors.light, CheckViewColors.dark]) {
      final mode = colors.isDark ? 'dark' : 'light';

      test('$mode text meets WCAG AA on canvas and surface', () {
        for (final background in [colors.canvas, colors.surface]) {
          expect(_contrast(colors.ink, background), greaterThanOrEqualTo(7));
          expect(
            _contrast(colors.inkMuted, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(colors.accent, background),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      test('$mode status colors are readable as text on surfaces', () {
        for (final status in [
          colors.approved,
          colors.pending,
          colors.returned,
          colors.rejected,
          colors.neutral,
        ]) {
          expect(_contrast(status, colors.surface), greaterThanOrEqualTo(4.5));
        }
      });

      test('$mode primary action label contrast', () {
        expect(
          _contrast(colors.onAccentFill, colors.accentFill),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('CheckView components', () {
    testWidgets('title block fits a narrow Arabic phone', (tester) async {
      await tester.pumpWidget(
        _host(
          const CvTitleBlock(
            loading: true,
            fields: [
              CvTitleField(
                label: 'الموقع',
                value: 'وزارة التربية والتعليم  /  المنطقة الشمالية  /  مجمع',
                flex: 3,
                maxLines: 2,
              ),
              CvTitleField(label: 'تاريخ الفحص', value: '2026-10-03'),
              CvTitleField(label: 'العرض', value: 'بانتظار الاعتماد'),
            ],
          ),
          language: 'ar',
          width: 320,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('ledger rows and tally do not overflow at 320dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              const CvTally(
                items: [
                  CvTallyItem(
                    label: 'Approved',
                    count: 12,
                    tone: CvTone.approved,
                  ),
                  CvTallyItem(
                    label: 'Awaiting approval',
                    count: 3,
                    tone: CvTone.pending,
                  ),
                  CvTallyItem(
                    label: 'Returned for correction',
                    count: 0,
                    tone: CvTone.returned,
                  ),
                ],
              ),
              CvLedger(
                children: [
                  CvLedgerRow(
                    title: 'B-114 Mechanical plant room inspection, level 3',
                    subtitle: 'A very long site name that has to wrap safely',
                    onTap: () {},
                    meta: const [
                      CvStatusMark(
                        label: 'Awaiting approval',
                        tone: CvTone.pending,
                      ),
                      CvMeta('Inspector with a long name'),
                      CvMeta('10:30 AM', icon: Icons.schedule_outlined),
                    ],
                  ),
                ],
              ),
            ],
          ),
          width: 320,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Awaiting approval'), findsWidgets);
    });

    testWidgets('choice sheet returns the tapped value', (tester) async {
      int? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: CheckViewTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await showCvChoiceSheet<int>(
                    context: context,
                    title: 'Show inspections',
                    selected: 0,
                    choices: const [
                      CvChoice(value: 0, label: 'All states'),
                      CvChoice(value: 1, label: 'Awaiting approval'),
                    ],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awaiting approval'));
      await tester.pumpAndSettle();
      expect(picked, 1);
    });
  });

  group('CheckView settings', () {
    Future<void> pumpDrawer(WidgetTester tester, String language) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final scaffoldKey = GlobalKey<ScaffoldState>();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            sessionSecurityAppKeyProvider.overrideWithValue('viewer-test'),
            sessionSecurityStoreProvider.overrideWithValue(
              _FakeSecurityStore(),
            ),
            biometricAuthServiceProvider.overrideWithValue(_FakeBiometrics()),
          ],
          child: MaterialApp(
            theme: CheckViewTheme.light,
            home: Directionality(
              textDirection: language == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Scaffold(
                key: scaffoldKey,
                endDrawer: CheckViewSettingsDrawer(
                  profile: _profile,
                  language: language,
                  onLanguageChanged: (_) {},
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      scaffoldKey.currentState!.openEndDrawer();
      await tester.pumpAndSettle();
    }

    for (final language in ['en', 'ar']) {
      testWidgets('shows only the support email as contact ($language)', (
        tester,
      ) async {
        await pumpDrawer(tester, language);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.textContaining(checkViewSupportEmail),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.textContaining(checkViewSupportEmail), findsOneWidget);

        final texts = tester
            .widgetList<Text>(find.byType(Text, skipOffstage: false))
            .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
            .join('\n');
        for (final forbidden in [
          '+974',
          '3005',
          'AliMind',
          'Ali Karim',
          'About',
          'حول التطبيق',
          'Created & developed',
          'تطوير وتصميم',
          'Version',
          'الإصدار',
          'WhatsApp',
          'Telegram',
          'http',
        ]) {
          expect(texts, isNot(contains(forbidden)), reason: forbidden);
        }
      });
    }
  });

  group('CheckView user-facing errors', () {
    test('hides backend exception syntax and explains missing items', () {
      const raw =
          'PostgrestException(message: all checklist items must be answered; '
          'missing: 1, 6, 7, code: P0001, details: Bad Request)';
      final message = cvUserMessage(Exception(raw), 'en');
      expect(message, contains('Missing items: 1, 6, 7'));
      expect(message, isNot(contains('PostgrestException')));
      expect(message, isNot(contains('P0001')));
    });

    test('explains inspector requirement in Arabic', () {
      final message = cvUserMessage(
        Exception('PostgrestException(message: inspector name is required)'),
        'ar',
      );
      expect(message, 'يرجى إدخال اسم المفتش قبل المتابعة.');
    });

    test('turns RLS storage failures into permission language', () {
      final message = cvUserMessage(
        Exception(
          'StorageException(message: new row violates row-level security policy, '
          'statusCode: 403, error: Unauthorized)',
        ),
        'en',
      );
      expect(message, 'You do not have permission to perform this action.');
      expect(message, isNot(contains('StorageException')));
    });
  });

  group('CheckView source guard', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    test('no creator, phone, social or About content in the viewer', () {
      for (final forbidden in [
        'tel:',
        '+974',
        'AliMind',
        'Ali Karim',
        'wa.me',
        'whatsapp',
        't.me/',
        'telegram',
        'ChecklistSettingsDrawer',
        'PackageInfo',
      ]) {
        expect(
          sources.toLowerCase(),
          isNot(contains(forbidden.toLowerCase())),
          reason: forbidden,
        );
      }
    });

    test('support uses the exact mailto address', () {
      expect(checkViewSupportEmail, 'Support@alielhassan.com');
      expect(sources, contains(r"'mailto:$checkViewSupportEmail'"));
    });

    test('MaterialApp is not keyed on the theme', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, isNot(contains('ValueKey(useDark')));
      expect(main, isNot(contains("'viewer-dark'")));
    });
  });
}
