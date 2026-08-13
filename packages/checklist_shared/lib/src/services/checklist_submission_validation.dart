/// Server-side validation errors that mean the inspection data is safely
/// saved as a draft, but the operator must correct it before submission.
abstract final class ChecklistSubmissionValidation {
  static const _draftCorrectionMarkers = <String>[
    'inspector name is required',
    'inspection time is required',
    'a valid signature is required before submit',
    'inspection must contain at least one item',
    'all checklist items must be answered',
    'problem photo required for items',
    'fix photo required for items',
  ];

  static bool requiresDraftCorrection(Object error) {
    final value = '$error'.toLowerCase();
    return _draftCorrectionMarkers.any(value.contains);
  }

  static String messageFor(Object error, String language) {
    final value = '$error'.toLowerCase();
    final ar = language == 'ar';
    String indexesAfter(String marker) {
      final start = value.indexOf(marker);
      if (start < 0) return '';
      final tail = value.substring(start + marker.length);
      return RegExp(r'^[\s:]*([0-9,\s]+)')
              .firstMatch(tail)
              ?.group(1)
              ?.trim()
              .replaceAll(RegExp(r'[,\s]+$'), '') ??
          '';
    }

    if (value.contains('all checklist items must be answered')) {
      final indexes = indexesAfter('missing');
      return ar
          ? 'يجب الإجابة عن جميع البنود قبل الإرسال${indexes.isEmpty ? '' : '؛ البنود الناقصة: $indexes'}.'
          : 'Answer every item before submitting${indexes.isEmpty ? '' : '; missing items: $indexes'}.';
    }
    if (value.contains('a valid signature is required')) {
      return ar
          ? 'أضف توقيعًا صالحًا قبل الإرسال.'
          : 'Add a valid signature before submitting.';
    }
    if (value.contains('problem photo required for items')) {
      final indexes = indexesAfter('problem photo required for items');
      return ar
          ? 'أضف صورة للمشكلة${indexes.isEmpty ? '' : ' في البنود: $indexes'}.'
          : 'Add a problem photo${indexes.isEmpty ? '' : ' for items: $indexes'}.';
    }
    if (value.contains('fix photo required for items')) {
      final indexes = indexesAfter('fix photo required for items');
      return ar
          ? 'أضف صورة الإصلاح${indexes.isEmpty ? '' : ' في البنود: $indexes'}.'
          : 'Add a fix photo${indexes.isEmpty ? '' : ' for items: $indexes'}.';
    }
    return ar
        ? 'أكمل بيانات القائمة المطلوبة قبل الإرسال.'
        : 'Complete the required checklist fields before submitting.';
  }
}
