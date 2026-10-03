import 'dart:convert';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_widgets.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key, required this.language});

  final String language;

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  List<ChecklistAuditEvent> events = const [];
  bool loading = true;
  String? error;
  int days = 7;
  String? action;

  bool get ar => widget.language == 'ar';

  static const actions = <String>[
    'inspection.created',
    'inspection.updated',
    'inspection.submitted',
    'inspection.approved',
    'inspection.date_changed',
    'inspection.deleted',
    'evidence.deleted',
  ];

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
          .listEvents(
            action: action,
            from: now.subtract(Duration(days: days)),
            to: now.add(const Duration(minutes: 1)),
            limit: 250,
          );
      if (mounted) setState(() => events = rows);
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = checkAdminUserMessage(exception, widget.language),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _actionLabel(String value) {
    final label = switch (value) {
      'inspection.created' => ('Inspection created', 'إنشاء فحص'),
      'inspection.updated' => ('Inspection updated', 'تعديل فحص'),
      'inspection.submitted' => ('Inspection submitted', 'إرسال فحص'),
      'inspection.approved' => ('Inspection approved', 'اعتماد فحص'),
      'inspection.date_changed' => ('Inspection date corrected', 'تصحيح تاريخ'),
      'inspection.deleted' => ('Inspection deleted', 'حذف فحص'),
      'evidence.deleted' => ('Evidence deleted', 'حذف دليل'),
      _ => null,
    };
    if (label != null) return ar ? label.$2 : label.$1;
    return value.replaceAll('.', ' · ').replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'سجل التدقيق' : 'Audit log'),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: ar ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: CaPanel(
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
                      value: action,
                      hint: Text(ar ? 'كل العمليات' : 'All actions'),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(ar ? 'كل العمليات' : 'All actions'),
                        ),
                        for (final value in actions)
                          DropdownMenuItem<String?>(
                            value: value,
                            child: Text(_actionLabel(value)),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => action = value);
                        _load();
                      },
                    ),
                    Text(
                      ar ? '${events.length} عملية' : '${events.length} events',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: CaInlineNotice(
                  message: error!,
                  tone: CaTone.danger,
                  onDismiss: () => setState(() => error = null),
                ),
              ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : events.isEmpty
                  ? Center(
                      child: Text(
                        ar ? 'لا توجد عمليات ضمن الفترة' : 'No events in range',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final local = event.createdAt.toLocal();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CaPanel(
                            padding: EdgeInsets.zero,
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  event.action == 'evidence.deleted'
                                      ? Icons.delete_outline
                                      : event.action.endsWith('approved')
                                      ? Icons.verified_outlined
                                      : Icons.history,
                                ),
                              ),
                              title: Text(
                                _actionLabel(event.action),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${event.actorName ?? (ar ? 'النظام' : 'System')} · '
                                '${DateFormat('yyyy-MM-dd HH:mm:ss').format(local)}',
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              children: [
                                _detail(
                                  ar ? 'الكيان' : 'Entity',
                                  '${event.entityType} · ${event.entityId ?? '—'}',
                                ),
                                if (event.reason?.isNotEmpty == true)
                                  _detail(
                                    ar ? 'السبب' : 'Reason',
                                    event.reason!,
                                  ),
                                if (event.oldValue != null)
                                  _detail(
                                    ar ? 'القيمة السابقة' : 'Previous value',
                                    const JsonEncoder.withIndent(
                                      '  ',
                                    ).convert(event.oldValue),
                                  ),
                                if (event.newValue != null)
                                  _detail(
                                    ar ? 'القيمة الجديدة' : 'New value',
                                    const JsonEncoder.withIndent(
                                      '  ',
                                    ).convert(event.newValue),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
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
            width: 130,
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
