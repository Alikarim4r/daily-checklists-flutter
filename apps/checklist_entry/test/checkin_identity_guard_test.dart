import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'supported platform chrome uses CheckIn without changing identifiers',
    () {
      final visibleFiles = <String>[
        'android/app/src/main/AndroidManifest.xml',
        'ios/Runner/Info.plist',
        'macos/Runner/Info.plist',
        'macos/Runner/Base.lproj/MainMenu.xib',
        'web/index.html',
        'web/manifest.json',
        'windows/runner/main.cpp',
        'windows/runner/Runner.rc',
        'linux/runner/my_application.cc',
      ];
      for (final path in visibleFiles) {
        expect(
          File(path).readAsStringSync(),
          contains('CheckIn'),
          reason: path,
        );
      }

      expect(
        File('android/app/build.gradle.kts').readAsStringSync(),
        contains('applicationId = "com.moehe.checklists.checklist_entry"'),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains(r'$(PRODUCT_BUNDLE_IDENTIFIER)'),
      );
    },
  );

  test('CheckIn source exposes no prohibited contact channel', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n')
        .toLowerCase();

    expect(source, isNot(contains('whatsapp')));
    expect(source, isNot(contains('telegram')));
    expect(source, isNot(contains('mailto:')));
    expect(source, isNot(contains('tel:')));
    for (final match in RegExp(
      r'[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}',
    ).allMatches(source)) {
      expect(match.group(0), 'support@alielhassan.com');
    }
  });
}
