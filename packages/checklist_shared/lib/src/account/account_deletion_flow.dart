import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/offline_inspection_queue.dart';
import '../providers/providers.dart';
import '../providers/session_security_provider.dart';

const checklistSupportEmail = 'Support@alielhassan.com';
const checklistPrivacyPolicyUrl =
    'https://inspection.alielhassan.com/privacy.html';
const checklistAccountDeletionUrl =
    'https://inspection.alielhassan.com/account-deletion.html';

/// Runs a re-authenticated account deletion flow with deliberately generic,
/// user-facing failures. Backend diagnostics never appear in the UI.
Future<void> showChecklistAccountDeletionFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String language,
}) async {
  final ar = language == 'ar';
  final password = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeleteAccountDialog(language: language),
  );
  if (password == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                ar
                    ? 'جارٍ حذف الحساب والبيانات الشخصية…'
                    : 'Deleting account and personal data…',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    await ref
        .read(authRepositoryProvider)
        .deleteAccount(currentPassword: password);
    try {
      await OfflineInspectionQueue.instance.purgeUserData();
      await ref
          .read(sessionSecurityProvider.notifier)
          .clearForAccountDeletion();
    } catch (_) {
      // Server deletion is authoritative. Local cleanup is best-effort; the
      // encrypted outbox is also inaccessible after clearing on next startup.
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ar
                ? 'تم حذف الحساب وإزالة البيانات الشخصية المرتبطة به.'
                : 'Your account and linked personal data were deleted.',
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ar
                ? 'تعذر حذف الحساب. تحقق من كلمة المرور والاتصال ثم حاول مرة أخرى.'
                : 'Could not delete the account. Check your password and connection, then try again.',
          ),
          action: SnackBarAction(label: ar ? 'حسنًا' : 'OK', onPressed: () {}),
        ),
      );
    }
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.language});

  final String language;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _confirmed = false;
  bool _attempted = false;

  bool get ar => widget.language == 'ar';
  bool get _canDelete => _confirmed && _password.text.isNotEmpty;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canDelete) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
      title: Text(ar ? 'حذف الحساب نهائيًا' : 'Delete account permanently'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ar
                  ? 'سيتم حذف تسجيل الدخول والملف الشخصي والصلاحيات، وإزالة هويتك من السجلات التشغيلية المحتفظ بها. لا يمكن التراجع عن هذا الإجراء.'
                  : 'Your login, profile and access assignments will be deleted, and your identity will be removed from retained operational records. This cannot be undone.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: ar ? 'كلمة المرور الحالية' : 'Current password',
                helperText: ar
                    ? 'مطلوبة لتأكيد هويتك قبل الحذف.'
                    : 'Required to verify your identity before deletion.',
                errorText: _attempted && _password.text.isEmpty
                    ? (ar
                          ? 'أدخل كلمة المرور الحالية'
                          : 'Enter your current password')
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value == true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                ar
                    ? 'أفهم أن حذف الحساب نهائي ولا يمكن التراجع عنه.'
                    : 'I understand that account deletion is permanent and cannot be undone.',
              ),
              subtitle: _attempted && !_confirmed
                  ? Text(
                      ar
                          ? 'يجب تأكيد هذه العبارة.'
                          : 'Confirm this statement to continue.',
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _canDelete
              ? _submit
              : () => setState(() => _attempted = true),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(ar ? 'حذف الحساب' : 'Delete account'),
        ),
      ],
    );
  }
}
