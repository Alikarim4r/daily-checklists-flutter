import 'package:flutter/material.dart';

/// Typed editor for P3-B/C: no raw JSON required from the end user.
/// Reference material and professional approvals are never auto-certified.
class TechnicalPayloadForm extends StatefulWidget {
  const TechnicalPayloadForm({
    super.key,
    required this.kind,
    required this.onChanged,
    this.initial = const {},
    required this.language,
  });
  final String kind, language;
  final Map<String, dynamic> initial;
  final ValueChanged<Map<String, dynamic>> onChanged;
  @override
  State<TechnicalPayloadForm> createState() => _TechnicalPayloadFormState();
}

class _TechnicalPayloadFormState extends State<TechnicalPayloadForm> {
  final fields = <String, TextEditingController>{};
  final hazardRows = <Map<String, TextEditingController>>[];
  final checkpointRows = <Map<String, TextEditingController>>[];
  bool get ar => widget.language == 'ar';
  String t(String en, String arabic) => ar ? arabic : en;
  TextEditingController field(String key, {String defaultValue = ''}) =>
      fields.putIfAbsent(
        key,
        () => TextEditingController(
          text: widget.initial[key] is List
              ? (widget.initial[key] as List).join('\n')
              : (widget.initial[key]?.toString() ?? defaultValue),
        ),
      );

  @override
  void initState() {
    super.initState();
    if (widget.kind == 'risk_assessment' || widget.kind == 'jsa') {
      final raw = widget.initial['hazards'];
      if (raw is List) {
        for (final x in raw) {
          if (x is Map) {
            hazardRows.add(_makeHazard(Map<String, dynamic>.from(x)));
          }
        }
      }
      if (hazardRows.isEmpty) hazardRows.add(_makeHazard({}));
    }
    if (widget.kind == 'itp') {
      final raw = widget.initial['checkpoints'];
      if (raw is List) {
        for (final x in raw) {
          if (x is Map) {
            checkpointRows.add(_makeCheckpoint(Map<String, dynamic>.from(x)));
          }
        }
      }
      if (checkpointRows.isEmpty) checkpointRows.add(_makeCheckpoint({}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  Map<String, TextEditingController> _makeHazard(Map<String, dynamic> j) => {
    for (final key in const [
      'hazard',
      'controls',
      'severity',
      'likelihood',
      'residual_severity',
      'residual_likelihood',
    ])
      key: TextEditingController(
        text: (j[key] ?? (key == 'severity' || key == 'likelihood' ? '3' : '1'))
            .toString(),
      ),
  };
  Map<String, TextEditingController> _makeCheckpoint(Map<String, dynamic> j) =>
      {
        for (final key in const [
          'id',
          'description',
          'acceptance_criteria',
          'point_type',
        ])
          key: TextEditingController(
            text: (j[key] ?? (key == 'point_type' ? 'hold' : '')).toString(),
          ),
      };

  void _emit() {
    if (!mounted) return;
    String get(String key) => field(key).text.trim();
    List<String> lines(String key) => field(
      key,
    ).text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final result = <String, dynamic>{};
    switch (widget.kind) {
      case 'method_statement':
      case 'sop':
        result.addAll({
          'scope': get('scope'),
          'steps': lines('steps'),
          'resources': lines('resources'),
          'ppe': lines('ppe'),
        });
      case 'risk_assessment':
      case 'jsa':
        result['hazards'] = [
          for (final row in hazardRows)
            {
              'hazard': row['hazard']!.text.trim(),
              'controls': row['controls']!.text.trim(),
              for (final key in const [
                'severity',
                'likelihood',
                'residual_severity',
                'residual_likelihood',
              ])
                key: int.tryParse(row[key]!.text) ?? 0,
            },
        ];
      case 'cop':
        result.addAll({
          'source': get('source'),
          'edition': get('edition'),
          'reference_url': get('reference_url'),
          'notes': get('notes'),
        });
      case 'ptw':
        result.addAll({
          'work_scope': get('work_scope'),
          'hazards': lines('hazards'),
          'controls': lines('controls'),
          'isolations': lines('isolations'),
          'emergency_plan': get('emergency_plan'),
        });
      case 'itp':
        result['checkpoints'] = [
          for (final row in checkpointRows)
            {
              for (final entry in row.entries)
                entry.key: entry.value.text.trim(),
            },
        ];
      case 'ncr':
        result.addAll({
          'finding': get('finding'),
          'root_cause': get('root_cause'),
          'corrective_action': get('corrective_action'),
          'due_date': get('due_date'),
        });
    }
    widget.onChanged(result);
  }

  Widget input(String key, String en, String arabic, {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: field(key),
          maxLines: lines,
          onChanged: (_) => _emit(),
          decoration: InputDecoration(
            labelText: t(en, arabic),
            alignLabelWithHint: lines > 1,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _riskRow(Map<String, TextEditingController> row, int i) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t("Hazard", "الخطر")} ${i + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: hazardRows.length == 1
                      ? null
                      : () {
                          setState(() => hazardRows.removeAt(i));
                          _emit();
                        },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            for (final item in [
              ('hazard', t('Hazard', 'الخطر')),
              ('controls', t('Control measures', 'إجراءات التحكم')),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: row[item.$1],
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: item.$2,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 5,
              children: [
                for (final key in const [
                  'severity',
                  'likelihood',
                  'residual_severity',
                  'residual_likelihood',
                ])
                  SizedBox(
                    width: 135,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('hazard-$i-$key'),
                      initialValue: row[key]!.text,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: switch (key) {
                          'severity' => t('Severity', 'الشدة'),
                          'likelihood' => t('Likelihood', 'الاحتمال'),
                          'residual_severity' => t(
                            'Residual S',
                            'الشدة المتبقية',
                          ),
                          _ => t('Residual L', 'الاحتمال المتبقي'),
                        },
                        isDense: true,
                      ),
                      items: [
                        for (int n = 1; n <= 5; n++)
                          DropdownMenuItem(value: '$n', child: Text('$n')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => row[key]!.text = v);
                          _emit();
                        }
                      },
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${t("Initial risk", "الخطر الأولي")}: '
                '${(int.tryParse(row['severity']!.text) ?? 0) * (int.tryParse(row['likelihood']!.text) ?? 0)}  ·  '
                '${t("Residual risk", "الخطر المتبقي")}: '
                '${(int.tryParse(row['residual_severity']!.text) ?? 0) * (int.tryParse(row['residual_likelihood']!.text) ?? 0)}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itpRow(Map<String, TextEditingController> row, int i) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${t('Checkpoint', 'نقطة الفحص')} ${i + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                onPressed: checkpointRows.length == 1
                    ? null
                    : () {
                        setState(() => checkpointRows.removeAt(i));
                        _emit();
                      },
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          for (final entry in [
            ('id', t('Point ID', 'رمز النقطة')),
            (
              'description',
              t('Inspection / test description', 'وصف الفحص / الاختبار'),
            ),
            ('acceptance_criteria', t('Acceptance criteria', 'معايير القبول')),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: row[entry.$1],
                decoration: InputDecoration(
                  labelText: entry.$2,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _emit(),
              ),
            ),
          DropdownButtonFormField<String>(
            key: ValueKey('point-type-$i'),
            initialValue: row['point_type']!.text,
            decoration: InputDecoration(
              labelText: t('Point type', 'نوع النقطة'),
            ),
            items: [
              for (final v in const ['hold', 'witness', 'review', 'test'])
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) {
              if (v != null) {
                row['point_type']!.text = v;
                _emit();
              }
            },
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        if (widget.kind == 'method_statement' || widget.kind == 'sop') ...[
          input('scope', 'Scope of work', 'نطاق العمل', lines: 2),
          input(
            'steps',
            'Steps — one per line',
            'خطوات العمل — كل خطوة بسطر',
            lines: 5,
          ),
          input(
            'resources',
            'Equipment and resources',
            'الأدوات والموارد',
            lines: 3,
          ),
          input('ppe', 'PPE requirements', 'معدات الوقاية الشخصية', lines: 3),
        ],
        if (widget.kind == 'risk_assessment' || widget.kind == 'jsa') ...[
          Text(
            t(
              '5×5 risk matrix — residual risk cannot exceed initial risk',
              'مصفوفة مخاطر 5×5 — لا يجوز أن تزيد المخاطر المتبقية عن الأولية',
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < hazardRows.length; i++)
            _riskRow(hazardRows[i], i),
          TextButton.icon(
            onPressed: () {
              setState(() => hazardRows.add(_makeHazard({})));
              _emit();
            },
            icon: const Icon(Icons.add),
            label: Text(t('Add hazard', 'إضافة خطر')),
          ),
        ],
        if (widget.kind == 'cop') ...[
          input(
            'source',
            'Issuing organization / source',
            'الجهة المصدرة / المصدر',
          ),
          input('edition', 'Standard edition / year', 'رقم الإصدار / السنة'),
          input(
            'reference_url',
            'Reference URL (optional)',
            'رابط المرجع (اختياري)',
          ),
          input('notes', 'Notes', 'ملاحظات', lines: 3),
          Text(
            t(
              'A reference entry is not certification of compliance.',
              'تسجيل المرجع لا يعني الحصول على شهادة مطابقة.',
            ),
          ),
        ],
        if (widget.kind == 'ptw') ...[
          input(
            'work_scope',
            'Permitted work scope',
            'نطاق العمل المصرح',
            lines: 3,
          ),
          input(
            'hazards',
            'Hazards — one per line',
            'المخاطر — كل خطر في سطر',
            lines: 4,
          ),
          input(
            'controls',
            'Controls — one per line',
            'إجراءات التحكم — كل إجراء بسطر',
            lines: 4,
          ),
          input(
            'isolations',
            'Required isolations — one per line',
            'العزل المطلوب',
            lines: 3,
          ),
          input('emergency_plan', 'Emergency plan', 'خطة الطوارئ', lines: 3),
          Text(
            t(
              'Approval alone does not authorize work. Issue a time-limited permit with a linked approved RA.',
              'اعتماد المستند لا يمنح تصريح العمل؛ يجب إصدار تصريح محدد المدة مرتبط بتقييم مخاطر معتمد.',
            ),
          ),
        ],
        if (widget.kind == 'itp') ...[
          for (int i = 0; i < checkpointRows.length; i++)
            _itpRow(checkpointRows[i], i),
          TextButton.icon(
            onPressed: () {
              setState(() => checkpointRows.add(_makeCheckpoint({})));
              _emit();
            },
            icon: const Icon(Icons.add),
            label: Text(t('Add checkpoint', 'إضافة نقطة فحص')),
          ),
        ],
        if (widget.kind == 'ncr') ...[
          input(
            'finding',
            'Nonconformity finding',
            'وصف عدم المطابقة',
            lines: 3,
          ),
          input('root_cause', 'Root cause', 'السبب الجذري', lines: 3),
          input(
            'corrective_action',
            'Corrective action',
            'الإجراء التصحيحي',
            lines: 3,
          ),
          input(
            'due_date',
            'Target due date (YYYY-MM-DD)',
            'التاريخ المستهدف (YYYY-MM-DD)',
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    for (final row in [...hazardRows, ...checkpointRows]) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }
}
