// Operations / supervision KPI models for the Viewer Ops dashboard.

enum OpsPeriod {
  today,
  thisWeek,
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  thisYear;

  (DateTime from, DateTime to) range(DateTime now) {
    final to = DateTime(now.year, now.month, now.day);
    switch (this) {
      case OpsPeriod.today:
        return (to, to);
      case OpsPeriod.thisWeek:
        // Qatar business week begins on Sunday.
        return (to.subtract(Duration(days: to.weekday % 7)), to);
      case OpsPeriod.thisMonth:
        return (DateTime(to.year, to.month), to);
      case OpsPeriod.lastMonth:
        final start = DateTime(to.year, to.month - 1);
        final end = DateTime(
          to.year,
          to.month,
        ).subtract(const Duration(days: 1));
        return (start, end);
      case OpsPeriod.last3Months:
        return (DateTime(to.year, to.month - 2), to);
      case OpsPeriod.last6Months:
        return (DateTime(to.year, to.month - 5), to);
      case OpsPeriod.thisYear:
        return (DateTime(to.year), to);
    }
  }
}

/// Current Qatar wall-clock time, independent of the device timezone.
DateTime qatarBusinessNow([DateTime? instant]) {
  final qatar = (instant ?? DateTime.now()).toUtc().add(
    const Duration(hours: 3),
  );
  return DateTime(
    qatar.year,
    qatar.month,
    qatar.day,
    qatar.hour,
    qatar.minute,
    qatar.second,
    qatar.millisecond,
    qatar.microsecond,
  );
}

enum FollowUpKind { pendingReview, overdue, openProblems }

class FollowUpItem {
  const FollowUpItem({
    required this.kind,
    required this.inspectionId,
    required this.siteId,
    required this.buildingCode,
    required this.dateIso,
    required this.title,
    required this.subtitle,
  });

  final FollowUpKind kind;
  final String inspectionId;
  final String siteId;
  final String buildingCode;
  final String dateIso;
  final String title;
  final String subtitle;
}

class SiteKpiRow {
  const SiteKpiRow({
    required this.siteId,
    required this.buildingCode,
    required this.siteName,
    required this.inspectionsInPeriod,
    required this.approvedCount,
    required this.idealRate,
    required this.openProblemCount,
    required this.overdueCount,
    required this.hasTodaySubmission,
  });

  final String siteId;
  final String buildingCode;
  final String siteName;
  final int inspectionsInPeriod;
  final int approvedCount;

  /// 0..1 share of answered items that match ideal (Yes path).
  final double idealRate;
  final int openProblemCount;
  final int overdueCount;
  final bool hasTodaySubmission;

  double get approvalRate =>
      inspectionsInPeriod == 0 ? 0 : approvedCount / inspectionsInPeriod;

  /// Composite score for ranking (higher is better).
  double get score {
    final compliance = hasTodaySubmission ? 0.25 : 0.0;
    return (idealRate * 0.45) + (approvalRate * 0.30) + compliance;
  }
}

class OpsSnapshot {
  const OpsSnapshot({
    required this.period,
    required this.dateFrom,
    required this.dateTo,
    required this.asOf,
    required this.siteCount,
    required this.dailyCompliance,
    required this.pendingReviewCount,
    required this.overdueInspectionCount,
    required this.openProblemCount,
    required this.completionRate,
    required this.totalInspectionsInPeriod,
    required this.approvedInPeriod,
    required this.sites,
    required this.followUps,
  });

  final OpsPeriod period;
  final DateTime dateFrom;
  final DateTime dateTo;
  final DateTime asOf;
  final int siteCount;

  /// Sites with submitted/approved inspection today ÷ siteCount (0..1).
  final double dailyCompliance;
  final int pendingReviewCount;
  final int overdueInspectionCount;
  final int openProblemCount;

  /// Approved ÷ non-draft inspections in period (0..1).
  final double completionRate;
  final int totalInspectionsInPeriod;
  final int approvedInPeriod;

  final List<SiteKpiRow> sites;
  final List<FollowUpItem> followUps;

  List<SiteKpiRow> get bestSites {
    final ranked = [...sites]..sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(5).toList();
  }

  List<SiteKpiRow> get worstSites {
    final ranked = [...sites]..sort((a, b) => a.score.compareTo(b.score));
    return ranked.take(5).toList();
  }

  List<FollowUpItem> followUpsOf(FollowUpKind kind) =>
      followUps.where((f) => f.kind == kind).toList();
}
