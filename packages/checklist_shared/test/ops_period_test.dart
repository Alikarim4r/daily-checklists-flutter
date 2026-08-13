import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supervision quick ranges follow the Qatar Sunday business week', () {
    final now = DateTime(2026, 8, 12); // Wednesday.

    expect(OpsPeriod.today.range(now), (DateTime(2026, 8, 12), now));
    expect(OpsPeriod.thisWeek.range(now), (
      DateTime(2026, 8, 9),
      DateTime(2026, 8, 12),
    ));
    expect(OpsPeriod.thisMonth.range(now), (
      DateTime(2026, 8),
      DateTime(2026, 8, 12),
    ));
    expect(OpsPeriod.lastMonth.range(now), (
      DateTime(2026, 7),
      DateTime(2026, 7, 31),
    ));
    expect(OpsPeriod.thisYear.range(now), (
      DateTime(2026),
      DateTime(2026, 8, 12),
    ));
  });

  test('Qatar business clock does not depend on device timezone', () {
    final qatar = qatarBusinessNow(DateTime.utc(2026, 8, 11, 22, 30));
    expect(qatar, DateTime(2026, 8, 12, 1, 30));
  });
}
