import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

import '../design/checkview_tokens.dart';
import '../design/checkview_widgets.dart';

CvTone _noticeTone(ChecklistNoticeKind kind) => switch (kind) {
  ChecklistNoticeKind.pendingReview => CvTone.pending,
  ChecklistNoticeKind.overdue ||
  ChecklistNoticeKind.failedSync => CvTone.rejected,
  ChecklistNoticeKind.missingPhoto ||
  ChecklistNoticeKind.missingSignature ||
  ChecklistNoticeKind.unsignedSubmit => CvTone.returned,
  ChecklistNoticeKind.approvedToday => CvTone.approved,
  ChecklistNoticeKind.submitted ||
  ChecklistNoticeKind.offlineQueue ||
  ChecklistNoticeKind.workflow => CvTone.accent,
  ChecklistNoticeKind.readyToStart => CvTone.neutral,
};

class CvNoticeBell extends StatelessWidget {
  const CvNoticeBell({
    super.key,
    required this.count,
    required this.language,
    required this.onOpen,
  });

  final int count;
  final String language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final label = language == 'ar' ? 'الإشعارات' : 'Notifications';
    return IconButton(
      tooltip: count == 0 ? label : '$label ($count)',
      onPressed: onOpen,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_none_outlined),
      ),
    );
  }
}

/// CheckView notification centre; same data as the shared sheet.
Future<void> showCheckViewNotices({
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
    useSafeArea: true,
    builder: (sheetContext) {
      final c = CheckViewColors.of(sheetContext);
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: CvSpace.sm),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CvSheetHeader(
                title: ar ? 'الإشعارات' : 'Notifications',
                message: notices.isEmpty
                    ? null
                    : (ar
                          ? '${notices.length} تنبيهات تشغيلية'
                          : '${notices.length} operational alerts'),
              ),
              const Divider(),
              if (notices.isEmpty)
                CvEmptyState(
                  icon: Icons.notifications_none_outlined,
                  title: ar ? 'لا توجد إشعارات' : 'No notifications',
                  message: ar
                      ? 'تظهر هنا التنبيهات التشغيلية والمهام المطلوبة.'
                      : 'Operational alerts and required actions appear here.',
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: CvSpace.xl),
                    itemCount: notices.length,
                    separatorBuilder: (_, _) =>
                        const Divider(indent: CvSpace.gutter + 42),
                    itemBuilder: (context, index) {
                      final notice = notices[index];
                      return CvLedgerRow(
                        leading: Icon(
                          notice.icon,
                          size: 22,
                          color: cvToneColor(c, _noticeTone(notice.kind)),
                        ),
                        title: notice.title,
                        subtitle: notice.subtitle,
                        onTap: notice.inspectionId == null
                            ? null
                            : () {
                                Navigator.pop(sheetContext);
                                onTap(notice.inspectionId);
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
