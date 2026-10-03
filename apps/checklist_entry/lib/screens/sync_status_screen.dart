part of '../main.dart';

class _SyncStatusScreen extends StatefulWidget {
  const _SyncStatusScreen({required this.language, required this.onRetry});

  final String language;
  final Future<void> Function() onRetry;

  @override
  State<_SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<_SyncStatusScreen> {
  DateTime? lastSuccess;
  bool retrying = false;

  bool get ar => widget.language == 'ar';

  @override
  void initState() {
    super.initState();
    _loadLastSuccess();
  }

  Future<void> _loadLastSuccess() async {
    final value = await OfflineInspectionQueue.instance.lastSuccessfulSyncAt();
    if (mounted) setState(() => lastSuccess = value);
  }

  Future<void> _retry() async {
    setState(() => retrying = true);
    await widget.onRetry();
    await _loadLastSuccess();
    if (mounted) setState(() => retrying = false);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return ar ? 'لا توجد مزامنة سابقة' : 'No previous sync';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final queue = OfflineInspectionQueue.instance;
    final entries = queue.pending();
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'حالة المزامنة' : 'Sync status')),
      bottomNavigationBar: entries.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: retrying ? null : _retry,
                  icon: retrying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(ar ? 'المزامنة الآن' : 'Sync now'),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _retry,
        child: CiPageWidth(
          maxWidth: 900,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              CiWorkHeader(
                title: entries.isEmpty
                    ? (ar ? 'كل الأعمال متزامنة' : 'All work is synced')
                    : (ar ? 'العمل محفوظ على الجهاز' : 'Work saved on device'),
                subtitle: entries.isEmpty
                    ? (ar
                          ? 'لا توجد تغييرات محلية بانتظار الرفع.'
                          : 'No local changes are waiting to upload.')
                    : (ar
                          ? 'يمكنك متابعة العمل؛ ستُرفع السجلات عند توفر الاتصال.'
                          : 'Keep working; records will upload when a connection is available.'),
                meta: [
                  CiMeta(
                    _formatDate(lastSuccess),
                    icon: Icons.cloud_done_outlined,
                    tone: CiTone.good,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CiMetricGrid(
                metrics: [
                  CiMetric(
                    icon: Icons.pending_actions_outlined,
                    label: ar ? 'سجلات معلقة' : 'Pending records',
                    value: '${queue.pendingCount}',
                    tone: queue.pendingCount == 0
                        ? CiTone.good
                        : CiTone.warning,
                  ),
                  CiMetric(
                    icon: Icons.photo_library_outlined,
                    label: ar ? 'صور معلقة' : 'Pending photos',
                    value: '${queue.pendingImageCount}',
                    tone: queue.pendingImageCount == 0
                        ? CiTone.good
                        : CiTone.accent,
                  ),
                  CiMetric(
                    icon: Icons.sync_problem_outlined,
                    label: ar ? 'تحتاج إعادة محاولة' : 'Need retry',
                    value: '${queue.failedCount}',
                    tone: queue.failedCount == 0 ? CiTone.good : CiTone.danger,
                  ),
                  CiMetric(
                    icon: Icons.history_rounded,
                    label: ar ? 'آخر مزامنة ناجحة' : 'Last successful sync',
                    value: _formatDate(lastSuccess),
                    tone: CiTone.neutral,
                  ),
                ],
              ),
              CiSectionLabel(
                title: ar ? 'السجلات المحلية' : 'Local records',
                count: entries.length,
              ),
              if (entries.isEmpty)
                CiEmptyState(
                  title: ar ? 'تمت المزامنة' : 'You are up to date',
                  message: ar
                      ? 'سيظهر هنا أي عمل محفوظ محليًا عند ضعف الاتصال.'
                      : 'Work saved during poor connectivity will appear here.',
                  icon: Icons.cloud_done_outlined,
                )
              else
                CiQueuePanel(
                  children: [for (final entry in entries) _queueTile(entry)],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _queueTile(MapEntry<String, Map<String, dynamic>> entry) {
    final meta = Map<String, dynamic>.from(
      entry.value['_queue'] as Map? ?? const {},
    );
    final status = '${meta['status'] ?? 'pending'}';
    final failed = status == 'failed';
    final building =
        '${(entry.value['site'] as Map?)?['building_code'] ?? entry.value['buildingCode'] ?? entry.key}';
    return CiQueueRow(
      title: building,
      subtitle: failed
          ? (ar
                ? 'تعذرت المحاولة الأخيرة. تحقق من الاتصال وأعد المحاولة.'
                : 'The last attempt failed. Check the connection and retry.')
          : (ar
                ? 'محفوظ محليًا وبانتظار المزامنة'
                : 'Saved locally and awaiting sync'),
      icon: failed ? Icons.error_outline_rounded : Icons.schedule_outlined,
      tone: failed ? CiTone.danger : CiTone.warning,
      meta: [
        CiMeta(
          ar
              ? '${meta['attempts'] ?? 0} محاولات'
              : '${meta['attempts'] ?? 0} attempts',
          icon: Icons.replay_rounded,
        ),
      ],
      onTap: retrying ? () {} : _retry,
    );
  }
}

/// Lists building/area checklists nested under a campus site.
