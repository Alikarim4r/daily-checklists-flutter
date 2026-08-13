import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ClientErrorLogScreen extends ConsumerStatefulWidget {
  const ClientErrorLogScreen({super.key, required this.language});

  final String language;

  @override
  ConsumerState<ClientErrorLogScreen> createState() =>
      _ClientErrorLogScreenState();
}

class _ClientErrorLogScreenState extends ConsumerState<ClientErrorLogScreen> {
  List<ClientErrorLog> events = const [];
  bool loading = true;
  String? error;
  int days = 7;
  String? appKey;

  bool get ar => widget.language == 'ar';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final now = DateTime.now();
      final rows = await ref
          .read(auditRepositoryProvider)
          .listClientErrors(
            appKey: appKey,
            from: now.subtract(Duration(days: days)),
            to: now.add(const Duration(minutes: 1)),
            limit: 250,
          );
      if (mounted) setState(() => events = rows);
    } catch (exception, stack) {
      await StructuredErrorReporter.capture(
        exception,
        stack,
        module: 'admin.client_error_log',
      );
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'مراقبة الأخطاء' : 'Error monitoring'),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: ar ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<int>(
                    value: days,
                    items: [
                      for (final value in const [1, 7, 30, 90])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            ar ? 'آخر $value يوم' : 'Last $value days',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => days = value);
                      _load();
                    },
                  ),
                  DropdownButton<String?>(
                    value: appKey,
                    hint: Text(ar ? 'كل التطبيقات' : 'All apps'),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(ar ? 'كل التطبيقات' : 'All apps'),
                      ),
                      for (final value in const ['entry', 'viewer', 'admin'])
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) {
                      setState(() => appKey = value);
                      _load();
                    },
                  ),
                  Text(
                    ar ? '${events.length} خطأ' : '${events.length} errors',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : events.isEmpty
                ? Center(
                    child: Text(
                      ar ? 'لا توجد أخطاء ضمن الفترة' : 'No errors in range',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return Card(
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.bug_report_outlined),
                          ),
                          title: Text(
                            '${event.appKey} · ${event.errorType}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${event.platform} · ${event.module}\n'
                            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(event.occurredAt.toLocal())}',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          children: [
                            _detail(
                              ar ? 'الإصدار' : 'Version',
                              '${event.appVersion}+${event.buildNumber}',
                            ),
                            _detail(
                              ar ? 'الرسالة المنقحة' : 'Sanitized message',
                              event.errorMessage,
                            ),
                            if (event.stackSummary.isNotEmpty)
                              _detail(
                                ar ? 'ملخص التتبع' : 'Stack summary',
                                event.stackSummary,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
