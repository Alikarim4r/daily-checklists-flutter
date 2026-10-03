import 'package:flutter/foundation.dart';

/// Converts backend/runtime failures into concise user-facing CheckView copy.
/// Raw technical details are kept out of the UI.
String cvUserMessage(Object error, String language) {
  final ar = language == 'ar';
  final raw = error.toString();
  final lower = raw.toLowerCase();

  assert(() {
    debugPrint('[CheckView] $raw');
    return true;
  }());

  if (error is FormatException) {
    final message = error.message.toString().trim();
    if (message.isNotEmpty) return message;
  }

  final missing = RegExp(
    r'all checklist items must be answered;\s*missing:\s*([0-9,\s]+)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (missing != null) {
    final items = missing.group(1)!.trim().replaceFirst(RegExp(r',\s*$'), '');
    return ar
        ? 'يرجى الإجابة عن جميع بنود الفحص قبل الإرسال. البنود غير المكتملة: $items.'
        : 'Please answer all checklist items before submitting. Missing items: $items.';
  }

  if (lower.contains('inspector name is required')) {
    return ar
        ? 'يرجى إدخال اسم المفتش قبل المتابعة.'
        : 'Please enter the inspector name before continuing.';
  }

  if (lower.contains('row-level security') ||
      lower.contains('statuscode: 403') ||
      lower.contains('unauthorized') ||
      lower.contains('permission denied')) {
    return ar
        ? 'ليس لديك صلاحية لتنفيذ هذا الإجراء.'
        : 'You do not have permission to perform this action.';
  }

  if (lower.contains('jwt') && lower.contains('expired') ||
      lower.contains('refresh token') ||
      lower.contains('session') && lower.contains('expired')) {
    return ar
        ? 'انتهت جلسة تسجيل الدخول. يرجى تسجيل الدخول مرة أخرى.'
        : 'Your sign-in session has expired. Please sign in again.';
  }

  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('clientexception')) {
    return ar
        ? 'تعذر الاتصال بالخدمة. تحقق من اتصال الإنترنت ثم حاول مرة أخرى.'
        : 'Could not connect to the service. Check your internet connection and try again.';
  }

  if (lower.contains('timeout') || lower.contains('timed out')) {
    return ar
        ? 'استغرقت العملية وقتًا أطول من المتوقع. حاول مرة أخرى.'
        : 'This is taking longer than expected. Please try again.';
  }

  if (lower.contains('duplicate key') || lower.contains('23505')) {
    return ar ? 'هذا السجل موجود بالفعل.' : 'This record already exists.';
  }

  if (lower.contains('not found')) {
    return ar
        ? 'تعذر العثور على البيانات المطلوبة. حدّث الصفحة وحاول مرة أخرى.'
        : 'The requested information could not be found. Refresh and try again.';
  }

  if (lower.contains('storageexception') || lower.contains('upload')) {
    return ar
        ? 'تعذر رفع الملف. حاول مرة أخرى.'
        : 'The file could not be uploaded. Please try again.';
  }

  return ar
      ? 'تعذر إكمال العملية. يرجى المحاولة مرة أخرى.'
      : 'Could not complete the action. Please try again.';
}
