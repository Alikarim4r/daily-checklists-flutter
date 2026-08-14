import 'package:flutter/material.dart';

import '../models/inspection.dart';
import '../models/workflow_notification.dart';
import '../theme/checklist_brand.dart';

enum ChecklistNoticeKind {
  pendingReview,
  overdue,
  missingPhoto,
  missingSignature,
  approvedToday,
  submitted,
  unsignedSubmit,
  offlineQueue,
  failedSync,
  readyToStart,
  workflow,
}

class ChecklistNotice {
  const ChecklistNotice({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.inspectionId,
  });

  final ChecklistNoticeKind kind;
  final String title;
  final String subtitle;
  final String? inspectionId;

  IconData get icon => switch (kind) {
    ChecklistNoticeKind.pendingReview => Icons.rate_review_outlined,
    ChecklistNoticeKind.overdue => Icons.warning_amber_rounded,
    ChecklistNoticeKind.missingPhoto => Icons.photo_camera_outlined,
    ChecklistNoticeKind.missingSignature => Icons.draw_outlined,
    ChecklistNoticeKind.approvedToday => Icons.verified_outlined,
    ChecklistNoticeKind.submitted => Icons.send_outlined,
    ChecklistNoticeKind.unsignedSubmit => Icons.edit_off_outlined,
    ChecklistNoticeKind.offlineQueue => Icons.cloud_upload_outlined,
    ChecklistNoticeKind.failedSync => Icons.sync_problem_outlined,
    ChecklistNoticeKind.readyToStart => Icons.assignment_outlined,
    ChecklistNoticeKind.workflow => Icons.notification_important_outlined,
  };

  Color get color => switch (kind) {
    ChecklistNoticeKind.pendingReview => ChecklistChrome.accent,
    ChecklistNoticeKind.overdue => const Color(0xFFB91C1C),
    ChecklistNoticeKind.missingPhoto => const Color(0xFFEA580C),
    ChecklistNoticeKind.missingSignature => const Color(0xFF7C3AED),
    ChecklistNoticeKind.approvedToday => const Color(0xFF15803D),
    ChecklistNoticeKind.submitted => ChecklistChrome.primary,
    ChecklistNoticeKind.unsignedSubmit => const Color(0xFFB45309),
    ChecklistNoticeKind.offlineQueue => const Color(0xFF2563EB),
    ChecklistNoticeKind.failedSync => const Color(0xFFB91C1C),
    ChecklistNoticeKind.readyToStart => const Color(0xFF15803D),
    ChecklistNoticeKind.workflow => const Color(0xFF2563EB),
  };
}

List<ChecklistNotice> workflowNotificationsToNotices({
  required List<WorkflowNotification> notifications,
  required String language,
}) => [
  for (final notification in notifications)
    ChecklistNotice(
      kind: ChecklistNoticeKind.workflow,
      title: notification.titleFor(language),
      subtitle: notification.bodyFor(language),
      inspectionId: notification.inspectionId,
    ),
];

/// Build actionable field notices without requiring a network read.
List<ChecklistNotice> buildEntryNotices({
  required int pendingSyncCount,
  required int failedSyncCount,
  required int writableChecklistCount,
  required String language,
}) {
  final ar = language == 'ar';
  final notices = <ChecklistNotice>[];
  if (failedSyncCount > 0) {
    notices.add(
      ChecklistNotice(
        kind: ChecklistNoticeKind.failedSync,
        title: ar
            ? '$failedSyncCount عملية تعذرت مزامنتها'
            : '$failedSyncCount sync operation(s) failed',
        subtitle: ar
            ? 'افتح المزامنة لإعادة المحاولة ومراجعة الاتصال'
            : 'Retry sync and check the network connection',
      ),
    );
  }
  if (pendingSyncCount > 0) {
    notices.add(
      ChecklistNotice(
        kind: ChecklistNoticeKind.offlineQueue,
        title: ar
            ? '$pendingSyncCount فحص محفوظ دون اتصال'
            : '$pendingSyncCount inspection(s) queued offline',
        subtitle: ar
            ? 'البيانات آمنة على الجهاز وجاهزة للمزامنة'
            : 'Data is secured on this device and ready to sync',
      ),
    );
  }
  notices.add(
    ChecklistNotice(
      kind: ChecklistNoticeKind.readyToStart,
      title: ar
          ? '$writableChecklistCount قائمة متاحة للإدخال'
          : '$writableChecklistCount checklist(s) ready for entry',
      subtitle: ar
          ? 'اختر الجهة والمنطقة والموقع لبدء الفحص'
          : 'Choose an organization, zone, and site to begin',
    ),
  );
  return notices;
}

/// Build viewer notices from loaded inspections + overdue indexes map.
List<ChecklistNotice> buildViewerNotices({
  required List<Inspection> records,
  required Map<String, Set<int>> overdueByInspectionId,
  required bool canReview,
  required String language,
}) {
  final ar = language == 'ar';
  final out = <ChecklistNotice>[];

  final pending = records.where((r) => r.awaitingReview).toList();
  if (canReview && pending.isNotEmpty) {
    out.add(
      ChecklistNotice(
        kind: ChecklistNoticeKind.pendingReview,
        title: ar
            ? '${pending.length} فحص بانتظار الاعتماد'
            : '${pending.length} inspection(s) awaiting approval',
        subtitle: ar
            ? 'افتح السجل للتعديل ثم الاعتماد'
            : 'Open a record to edit and approve',
        inspectionId: pending.first.id,
      ),
    );
  }

  for (final r in records) {
    final overdue = overdueByInspectionId[r.id] ?? {};
    if (overdue.isNotEmpty) {
      out.add(
        ChecklistNotice(
          kind: ChecklistNoticeKind.overdue,
          title: ar
              ? 'بنود متأخرة — ${r.buildingCode}'
              : 'Overdue items — ${r.buildingCode}',
          subtitle: ar
              ? 'البنود: ${overdue.join(', ')}'
              : 'Items: ${overdue.join(', ')}',
          inspectionId: r.id,
        ),
      );
    }
    final missingPhotos = r.items
        .where((i) => i.isProblem && !i.hasIssuePhoto)
        .map((i) => i.itemIndex)
        .toList();
    if (missingPhotos.isNotEmpty && r.isSubmitted) {
      out.add(
        ChecklistNotice(
          kind: ChecklistNoticeKind.missingPhoto,
          title: ar
              ? 'صور ناقصة — ${r.buildingCode}'
              : 'Missing photos — ${r.buildingCode}',
          subtitle: ar
              ? 'البنود: ${missingPhotos.join(', ')}'
              : 'Items: ${missingPhotos.join(', ')}',
          inspectionId: r.id,
        ),
      );
    }
    final hasSignature =
        r.signaturePath != null && r.signaturePath!.trim().isNotEmpty;
    if (r.isSubmitted && !hasSignature) {
      out.add(
        ChecklistNotice(
          kind: ChecklistNoticeKind.missingSignature,
          title: ar
              ? 'توقيع ناقص — ${r.buildingCode}'
              : 'Missing signature — ${r.buildingCode}',
          subtitle: ar
              ? 'يفضّل وجود توقيع الفني في خانة التوقيع'
              : 'Technician signature should appear in the form',
          inspectionId: r.id,
        ),
      );
    }
  }

  final approvedToday = records.where((r) => r.isApproved).toList();
  if (approvedToday.isNotEmpty) {
    out.add(
      ChecklistNotice(
        kind: ChecklistNoticeKind.approvedToday,
        title: ar
            ? '${approvedToday.length} فحص معتمد للعرض'
            : '${approvedToday.length} approved for viewing',
        subtitle: ar ? 'جاهزة للقراءة والتصدير' : 'Ready to view and export',
        inspectionId: approvedToday.first.id,
      ),
    );
  }

  final submitted = records.where((r) => r.awaitingReview).length;
  if (!canReview && submitted > 0) {
    out.add(
      ChecklistNotice(
        kind: ChecklistNoticeKind.submitted,
        title: ar ? 'فحوصات قيد المراجعة' : 'Inspections under review',
        subtitle: ar
            ? 'ستظهر بعد اعتماد المسؤول'
            : 'They appear after admin approval',
      ),
    );
  }

  return out;
}

class ChecklistNoticeBell extends StatelessWidget {
  const ChecklistNoticeBell({
    super.key,
    required this.notices,
    required this.onOpen,
  });

  final List<ChecklistNotice> notices;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final count = notices.length;
    return IconButton(
      tooltip: count == 0 ? 'Notifications' : 'Notifications ($count)',
      onPressed: onOpen,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

Future<void> showChecklistNoticesSheet({
  required BuildContext context,
  required List<ChecklistNotice> notices,
  required String language,
  required void Function(String? inspectionId) onTap,
}) {
  final ar = language == 'ar';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      if (notices.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            ar ? 'لا توجد إشعارات حالياً' : 'No notifications right now',
            textAlign: TextAlign.center,
          ),
        );
      }
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    ChecklistIconWell(
                      icon: Icons.notifications_active_outlined,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ar ? 'مركز الإشعارات' : 'Notification centre',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            ar
                                ? '${notices.length} تنبيهات تشغيلية'
                                : '${notices.length} operational alert(s)',
                            style: TextStyle(
                              color: ChecklistChrome.inkMutedFor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  shrinkWrap: true,
                  itemCount: notices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = notices[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: n.color.withValues(alpha: 0.15),
                        child: Icon(n.icon, color: n.color),
                      ),
                      title: Text(
                        n.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(n.subtitle),
                      trailing: n.inspectionId == null
                          ? null
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        onTap(n.inspectionId);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
