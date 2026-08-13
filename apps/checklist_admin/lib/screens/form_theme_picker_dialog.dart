import 'package:flutter/material.dart';

import 'package:checklist_shared/checklist_shared.dart';

/// Reusable picker for organization, zone, campus, checklist, or template.
class FormThemePickerDialog extends StatefulWidget {
  const FormThemePickerDialog({
    super.key,
    required this.language,
    required this.scopeName,
    required this.currentTheme,
    required this.currentAccent,
    required this.onSave,
    this.allowInherit = true,
    this.inheritedTheme = FormPaperTheme.classicGold,
  });

  final String language;
  final String scopeName;
  final String currentTheme;
  final String? currentAccent;
  final bool allowInherit;
  final FormPaperTheme inheritedTheme;
  final Future<void> Function(String formTheme, String? accent) onSave;

  @override
  State<FormThemePickerDialog> createState() => _FormThemePickerDialogState();
}

class _FormThemePickerDialogState extends State<FormThemePickerDialog> {
  late FormThemeKey selected;
  late TextEditingController customHex;
  bool saving = false;
  String? error;

  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;

  @override
  void initState() {
    super.initState();
    selected = FormThemeKey.fromDb(widget.currentTheme);
    customHex = TextEditingController(text: widget.currentAccent ?? '#E8C547');
  }

  @override
  void dispose() {
    customHex.dispose();
    super.dispose();
  }

  FormPaperTheme get preview => selected == FormThemeKey.inherit
      ? widget.inheritedTheme
      : FormPaperTheme.resolve(
          themeDb: selected.dbValue,
          accentHex: customHex.text,
        );

  Future<void> _save() async {
    final accent = selected == FormThemeKey.custom
        ? (FormPaperTheme.parseHex(customHex.text) == null
              ? null
              : FormPaperTheme.hexOf(FormPaperTheme.parseHex(customHex.text)!))
        : null;
    if (selected == FormThemeKey.custom && accent == null) {
      setState(
        () => error = _t(
          'Enter a valid #RRGGBB color',
          'أدخل لوناً صالحاً #RRGGBB',
        ),
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(selected.dbValue, accent);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = _t(
            'Could not save the theme. Check your permission and connection.',
            'تعذّر حفظ الثيم. تحقق من الصلاحية والاتصال.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = <FormThemeKey>[
      if (widget.allowInherit) FormThemeKey.inherit,
      ...FormThemeKey.values.where((k) => k.isSelectablePreset),
      FormThemeKey.custom,
    ];

    return AlertDialog(
      title: Text(_t('Checklist theme', 'ثيم القائمة')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.scopeName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  'Applies to entry cards, the on-screen form, and PDF reports.',
                  'يُطبّق على بطاقات الإدخال والنموذج المعروض وتقارير PDF.',
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              // Preview strip
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: preview.accent,
                  border: Border.all(color: preview.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  _t(
                    'Daily Facilities Inspection Report',
                    'تقرير الفحص اليومي للمرافق',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: preview.accentText,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in choices)
                    _ThemeChip(
                      label: key.labelFor(widget.language),
                      selected: selected == key,
                      swatch: key == FormThemeKey.custom
                          ? (FormPaperTheme.parseHex(customHex.text) ??
                                FormPaperTheme.classicGold.accent)
                          : key == FormThemeKey.inherit
                          ? widget.inheritedTheme.accent
                          : FormPaperTheme.preset(key).accent,
                      onTap: () => setState(() => selected = key),
                    ),
                ],
              ),
              if (selected == FormThemeKey.custom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customHex,
                  decoration: InputDecoration(
                    labelText: _t('Accent color (#RRGGBB)', 'اللون (#RRGGBB)'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: Text(_t('Cancel', 'إلغاء')),
        ),
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(
            saving ? _t('Saving…', 'جاري الحفظ…') : _t('Save', 'حفظ'),
          ),
        ),
      ],
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.selected,
    required this.swatch,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 118,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Colors.blue : Colors.black26,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black12),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
