import '../models/inspection.dart';
import 'policy_enforcement.dart';
import 'storage_path_list.dart';

DateTime _inspMoment(Inspection insp) {
  return insp.submittedAt ??
      insp.createdAt ??
      DateTime(
        insp.inspectionDate.year,
        insp.inspectionDate.month,
        insp.inspectionDate.day,
      );
}

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Earliest timestamp when [issuePath] appeared on [itemIndex] without a fix.
DateTime? firstSeenOpenIssueAt({
  required List<Inspection> history,
  required Inspection? current,
  required int itemIndex,
  required String issuePath,
}) {
  final target = storagePathOf(issuePath);
  if (target.isEmpty) return null;
  DateTime? earliest;
  for (final insp in [...history, ?current]) {
    for (final item in insp.items) {
      if (item.itemIndex != itemIndex) continue;
      for (final pair in item.photoPairs) {
        if (!pair.hasIssue || pair.hasFix) continue;
        if (storagePathOf(pair.issuePath!) != target) continue;
        final t = _inspMoment(insp);
        if (earliest == null || t.isBefore(earliest)) earliest = t;
      }
    }
  }
  return earliest;
}

/// Start of the consecutive problem streak for [itemIndex] (calendar days).
DateTime? problemStreakStart({
  required int itemIndex,
  required DateTime asOfDate,
  required Map<String, Map<int, bool>> problemByDateIso,
}) {
  DateTime? start;
  for (var i = 0; i < 400; i++) {
    final d = asOfDate.subtract(Duration(days: i));
    final dayMap = problemByDateIso[_isoDay(d)];
    if (dayMap == null || dayMap[itemIndex] != true) break;
    start = DateTime(d.year, d.month, d.day);
  }
  return start;
}

Duration? openDurationForIssue({
  required List<Inspection> history,
  required Inspection current,
  required int itemIndex,
  required String issuePath,
  required Map<String, Map<int, bool>> problemByDateIso,
  DateTime? asOf,
}) {
  final now = asOf ?? DateTime.now();
  final seen = firstSeenOpenIssueAt(
    history: history,
    current: current,
    itemIndex: itemIndex,
    issuePath: issuePath,
  );
  final streak = problemStreakStart(
    itemIndex: itemIndex,
    asOfDate: current.inspectionDate,
    problemByDateIso: problemByDateIso,
  );
  DateTime? opened = seen;
  if (streak != null && (opened == null || streak.isBefore(opened))) {
    opened = streak;
  }
  if (opened == null) return null;
  final delta = now.difference(opened);
  return delta.isNegative ? Duration.zero : delta;
}

String formatOpenDuration(Duration d, {required bool arabic}) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes < 1) {
    return arabic ? 'مفتوحة منذ لحظات' : 'Just opened';
  }
  if (totalMinutes < 60) {
    return arabic ? 'مفتوحة منذ $totalMinutes د' : 'Open for $totalMinutes m';
  }
  final hours = d.inHours;
  final days = hours ~/ 24;
  final remH = hours % 24;
  if (days <= 0) {
    return arabic ? 'مفتوحة منذ $hours س' : 'Open for $hours h';
  }
  if (remH == 0) {
    return arabic ? 'مفتوحة منذ $days ي' : 'Open for $days d';
  }
  return arabic ? 'مفتوحة منذ $days ي $remH س' : 'Open for ${days}d ${remH}h';
}

String formatIssueOpenTooltip({
  required Duration openFor,
  required int overdueAfterDays,
  required bool isOverdue,
  required bool arabic,
}) {
  final parts = <String>[formatOpenDuration(openFor, arabic: arabic)];
  if (overdueAfterDays > 0) {
    parts.add(
      arabic
          ? 'مهلة الإصلاح: $overdueAfterDays يوم'
          : 'Fix deadline: $overdueAfterDays days',
    );
  }
  if (isOverdue) {
    parts.add(arabic ? 'متجاوزة' : 'OVERDUE');
  }
  return parts.join(' · ');
}

/// Tooltips keyed by storage path for open (unfixed) issue photos.
Map<String, String> buildIssueOpenTooltips({
  required Inspection inspection,
  required List<Inspection> history,
  required Set<int> overdueIndexes,
  required String language,
  DateTime? asOf,
}) {
  final arabic = language == 'ar';
  final map = buildProblemHistory(history: history, current: inspection);
  final out = <String, String>{};
  for (final item in inspection.items) {
    for (final pair in item.photoPairs) {
      if (!pair.hasIssue || pair.hasFix) continue;
      final path = storagePathOf(pair.issuePath!);
      if (path.isEmpty) continue;
      final dur = openDurationForIssue(
        history: history,
        current: inspection,
        itemIndex: item.itemIndex,
        issuePath: path,
        problemByDateIso: map,
        asOf: asOf,
      );
      if (dur == null) continue;
      out[path] = formatIssueOpenTooltip(
        openFor: dur,
        overdueAfterDays: item.overdueAfterDays,
        isOverdue: overdueIndexes.contains(item.itemIndex),
        arabic: arabic,
      );
    }
  }
  return out;
}

String formatOpenDurationCompact(Duration d, {required bool arabic}) {
  final hours = d.inHours;
  final days = hours ~/ 24;
  final remH = hours % 24;
  if (days > 0) {
    return arabic ? '$daysي $remHس' : '${days}d ${remH}h';
  }
  if (hours > 0) {
    return arabic ? '$hours س' : '${hours}h';
  }
  final m = d.inMinutes;
  return arabic ? '$m د' : '${m}m';
}
