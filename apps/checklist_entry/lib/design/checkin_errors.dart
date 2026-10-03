import 'package:flutter/foundation.dart';

/// Maps runtime/backend failures to short, actionable CheckIn copy.
///
/// Raw diagnostics remain available to structured reporting and debug logs but
/// never cross this UI boundary.
String checkInUserMessage(Object? error, String language) {
  final ar = language == 'ar';
  final raw = error?.toString() ?? '';
  final lower = raw.toLowerCase();

  assert(() {
    debugPrint('[CheckIn diagnostic] $raw');
    return true;
  }());

  final missing = RegExp(
    r'(?:missing|unanswered)[^0-9]*([0-9][0-9,\s]*)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (lower.contains('all checklist items must be answered') ||
      lower.contains('answer every item') ||
      lower.contains('unanswered item')) {
    final items = missing?.group(1)?.trim();
    return ar
        ? 'أكمل جميع بنود الفحص قبل الإرسال${items == null ? '' : '. البنود الناقصة: $items'}.'
        : 'Complete every inspection item before submitting${items == null ? '' : '. Missing items: $items'}.';
  }

  if (lower.contains('inspector name') ||
      lower.contains('inspector_name') ||
      lower.contains('missing inspector')) {
    return ar
        ? 'أدخل اسم المفتش قبل المتابعة.'
        : 'Enter the inspector name before continuing.';
  }

  if (lower.contains('signature') &&
      (lower.contains('required') || lower.contains('missing'))) {
    return ar
        ? 'أضف توقيع المفتش قبل الإرسال.'
        : 'Add the inspector signature before submitting.';
  }

  if ((lower.contains('photo') || lower.contains('image')) &&
      (lower.contains('required') || lower.contains('missing'))) {
    return ar
        ? 'أضف الصور المطلوبة للبنود الموضحة ثم حاول مرة أخرى.'
        : 'Add the required photos to the highlighted items, then try again.';
  }

  if (lower.contains('row-level security') ||
      lower.contains('rls') ||
      lower.contains('permission denied') ||
      lower.contains('not authorized') ||
      lower.contains('unauthorized') ||
      lower.contains('forbidden') ||
      lower.contains('statuscode: 403') ||
      lower.contains('status code: 403')) {
    return ar
        ? 'لا تملك صلاحية تنفيذ هذا الإجراء. اطلب من المشرف مراجعة وصولك.'
        : 'You do not have permission for this action. Ask an administrator to review your access.';
  }

  if ((lower.contains('jwt') && lower.contains('expir')) ||
      lower.contains('refresh token') ||
      (lower.contains('session') && lower.contains('expir')) ||
      lower.contains('invalid token')) {
    return ar
        ? 'انتهت جلسة تسجيل الدخول. سجّل الدخول مرة أخرى للمتابعة.'
        : 'Your sign-in session expired. Sign in again to continue.';
  }

  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('clientexception') ||
      lower.contains('xmlhttprequest')) {
    return ar
        ? 'تعذر الاتصال بالخدمة. تحقق من الشبكة وحاول مرة أخرى؛ سيبقى عملك محفوظًا محليًا.'
        : 'Could not reach the service. Check your connection and retry; your work remains saved locally.';
  }

  if (lower.contains('timeout') || lower.contains('timed out')) {
    return ar
        ? 'استغرقت العملية وقتًا أطول من المتوقع. تحقق من الشبكة وحاول مرة أخرى.'
        : 'This is taking longer than expected. Check your connection and try again.';
  }

  if (lower.contains('storageexception') ||
      lower.contains('storage exception') ||
      lower.contains('upload') ||
      lower.contains('bucket')) {
    return ar
        ? 'تعذر رفع الصورة. تحقق من الاتصال ثم حاول مرة أخرى.'
        : 'The photo could not be uploaded. Check your connection and try again.';
  }

  if (lower.contains('sync conflict') ||
      lower.contains('version conflict') ||
      lower.contains('concurrent')) {
    return ar
        ? 'تغيّر هذا الفحص على جهاز آخر. حدّث البيانات ثم راجع التعديلات.'
        : 'This inspection changed on another device. Refresh it, then review your changes.';
  }

  if (lower.contains('23505') ||
      lower.contains('duplicate key') ||
      lower.contains('unique constraint')) {
    return ar
        ? 'توجد قائمة فحص لهذا الموقع والتاريخ بالفعل. حدّث الصفحة أو افتح القائمة الموجودة.'
        : 'A checklist already exists for this site and date. Refresh or open the existing checklist.';
  }

  if (lower.contains('not found') || lower.contains('no rows')) {
    return ar
        ? 'تعذر العثور على السجل المطلوب. حدّث البيانات وحاول مرة أخرى.'
        : 'The requested record could not be found. Refresh and try again.';
  }

  if (lower.contains('rejected') ||
      lower.contains('p0001') ||
      lower.contains('postgrestexception')) {
    return ar
        ? 'رفض الخادم الطلب. راجع الحقول المطلوبة وحاول مرة أخرى.'
        : 'The server rejected this request. Review the required fields and try again.';
  }

  return ar
      ? 'تعذر إكمال الإجراء. حاول مرة أخرى، أو حدّث البيانات إذا استمرت المشكلة.'
      : 'Could not complete the action. Try again, or refresh if the problem continues.';
}

bool containsUnsafeDiagnostic(String text) {
  final lower = text.toLowerCase();
  return const [
    'postgrestexception',
    'storageexception',
    'sqlstate',
    'p0001',
    'stack trace',
    'row-level security',
    'statuscode: 403',
    '"code":',
    "'code':",
  ].any(lower.contains);
}
