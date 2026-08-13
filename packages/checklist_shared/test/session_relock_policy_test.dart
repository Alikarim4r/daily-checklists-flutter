import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brief background transitions do not relock the session', () {
    var now = DateTime(2026, 8, 10, 12);
    final policy = SessionRelockPolicy(clock: () => now);

    policy.onBackgrounded();
    now = now.add(const Duration(minutes: 4, seconds: 59));

    expect(policy.onResumed(), isFalse);
  });

  test('a genuine five minute absence relocks the session', () {
    var now = DateTime(2026, 8, 10, 12);
    final policy = SessionRelockPolicy(clock: () => now);

    policy.onBackgrounded();
    now = now.add(const Duration(minutes: 5));

    expect(policy.onResumed(), isTrue);
    expect(policy.onResumed(), isFalse);
  });
}
