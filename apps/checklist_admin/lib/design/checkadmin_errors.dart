import 'package:flutter/foundation.dart';

/// Converts backend/runtime failures into concise administrator-facing copy.
String checkAdminUserMessage(Object? error, String language) {
  final ar = language == 'ar';
  final raw = error?.toString() ?? '';
  final lower = raw.toLowerCase();
  assert(() {
    debugPrint('[CheckAdmin diagnostic] $raw');
    return true;
  }());

  if (lower.contains('row-level security') ||
      lower.contains('rls') ||
      lower.contains('permission denied') ||
      lower.contains('unauthorized') ||
      lower.contains('forbidden') ||
      lower.contains('statuscode: 403') ||
      lower.contains('status code: 403')) {
    return ar
        ? 'لا تملك صلاحية تنفيذ هذا التغيير. راجع نطاق دورك أو صلاحيات الجهة.'
        : 'You do not have permission for this change. Review your role or organization scope.';
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
        ? 'تعذر الاتصال بالخدمة. تحقق من الشبكة ثم أعد المحاولة.'
        : 'Could not reach the service. Check your connection and try again.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return ar
        ? 'استغرقت العملية وقتًا أطول من المتوقع. حاول مرة أخرى.'
        : 'The operation took longer than expected. Try again.';
  }
  if (lower.contains('23505') ||
      lower.contains('duplicate key') ||
      lower.contains('unique constraint')) {
    return ar
        ? 'يوجد سجل بهذه البيانات بالفعل. حدّث القائمة أو عدّل القيم ثم حاول مجددًا.'
        : 'A record with these details already exists. Refresh or change the values and try again.';
  }
  if (lower.contains('23503') ||
      lower.contains('foreign key') ||
      lower.contains('still referenced')) {
    return ar
        ? 'لا يمكن حذف هذا السجل لأنه مرتبط ببيانات أخرى. أزل الارتباطات أولًا.'
        : 'This record cannot be removed because other data still depends on it. Remove those links first.';
  }
  if (lower.contains('not found') || lower.contains('no rows')) {
    return ar
        ? 'لم يعد السجل المطلوب متاحًا. حدّث البيانات وحاول مرة أخرى.'
        : 'The requested record is no longer available. Refresh and try again.';
  }
  if (lower.contains('storageexception') ||
      lower.contains('storage exception') ||
      lower.contains('upload') ||
      lower.contains('bucket')) {
    return ar
        ? 'تعذر رفع الملف. تحقق من نوع الملف والاتصال ثم حاول مرة أخرى.'
        : 'The file could not be uploaded. Check the file and connection, then try again.';
  }
  if (lower.contains('email') &&
      (lower.contains('invalid') || lower.contains('already'))) {
    return ar
        ? 'تحقق من البريد الإلكتروني؛ قد يكون غير صالح أو مستخدمًا مسبقًا.'
        : 'Check the email address; it may be invalid or already in use.';
  }
  if (lower.contains('password') &&
      (lower.contains('weak') || lower.contains('least'))) {
    return ar
        ? 'كلمة المرور لا تستوفي متطلبات الأمان. استخدم كلمة أقوى.'
        : 'The password does not meet security requirements. Use a stronger password.';
  }
  if (lower.contains('p0001') ||
      lower.contains('postgrestexception') ||
      lower.contains('rejected')) {
    return ar
        ? 'تعذر تنفيذ التغيير بالقيم الحالية. راجع الحقول المطلوبة وحاول مرة أخرى.'
        : 'The change could not be applied with the current values. Review the required fields and try again.';
  }
  return ar
      ? 'تعذر إكمال الإجراء. حدّث البيانات وحاول مرة أخرى.'
      : 'Could not complete the action. Refresh the data and try again.';
}

bool checkAdminContainsUnsafeDiagnostic(String text) {
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
