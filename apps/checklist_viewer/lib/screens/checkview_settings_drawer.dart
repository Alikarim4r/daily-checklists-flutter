import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/checkview_tokens.dart';
import '../design/checkview_errors.dart';
import '../design/checkview_widgets.dart';

/// CheckView settings. Viewer-local so the shared drawer (with its About
/// section) stays unchanged for Entry and Admin. The only contact channel
/// here is [checkViewSupportEmail].
class CheckViewSettingsDrawer extends ConsumerWidget {
  const CheckViewSettingsDrawer({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  bool get ar => language == 'ar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = CheckViewColors.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final soundEnabled = ref.watch(soundEnabledProvider);
    final hapticsEnabled = ref.watch(hapticsEnabledProvider);

    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IdentityHeader(profile: profile, language: language),
          Container(height: 2, color: c.datum),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: CvSpace.xl),
              children: [
                _GroupLabel(ar ? 'المظهر' : 'Appearance'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CvSpace.gutter,
                  ),
                  child: CvChoiceStrip<ThemeMode>(
                    selected: themeMode,
                    choices: [
                      CvChoice(
                        value: ThemeMode.light,
                        icon: Icons.light_mode_outlined,
                        label: ar ? 'فاتح' : 'Light',
                      ),
                      CvChoice(
                        value: ThemeMode.dark,
                        icon: Icons.dark_mode_outlined,
                        label: ar ? 'داكن' : 'Dark',
                      ),
                      CvChoice(
                        value: ThemeMode.system,
                        icon: Icons.brightness_auto_outlined,
                        label: ar ? 'النظام' : 'System',
                      ),
                    ],
                    onSelected: (next) {
                      // Defer out of the tap so MaterialApp swaps themes
                      // outside the gesture's build pass.
                      Future<void>.delayed(Duration.zero, () {
                        ref.read(themeModeProvider.notifier).setMode(next);
                      });
                    },
                  ),
                ),
                _GroupLabel(ar ? 'اللغة' : 'Language'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CvSpace.gutter,
                  ),
                  child: CvChoiceStrip<String>(
                    selected: viewerLanguages.contains(language)
                        ? language
                        : viewerLanguages.first,
                    choices: [
                      for (final code in viewerLanguages)
                        CvChoice(
                          value: code,
                          label: languageDisplayNames[code] ?? code,
                        ),
                    ],
                    onSelected: onLanguageChanged,
                  ),
                ),
                _GroupLabel(ar ? 'الإشعارات' : 'Notifications'),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_none_outlined),
                  title: Text(ar ? 'مركز الإشعارات' : 'Notification centre'),
                  subtitle: Text(
                    ar
                        ? 'التنبيهات التشغيلية والمهام المطلوبة'
                        : 'Operational alerts and required actions',
                  ),
                  value: notificationsEnabled,
                  onChanged: (enabled) => ref
                      .read(notificationsEnabledProvider.notifier)
                      .setEnabled(enabled),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: Text(ar ? 'أصوات التنبيه' : 'Alert sounds'),
                  subtitle: Text(
                    ar
                        ? 'عند الحفظ أو وجود متابعة عاجلة'
                        : 'On saves and urgent follow-ups',
                  ),
                  value: soundEnabled,
                  onChanged: (enabled) => ref
                      .read(soundEnabledProvider.notifier)
                      .setEnabled(enabled),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration_outlined),
                  title: Text(ar ? 'الاهتزاز اللمسي' : 'Haptic feedback'),
                  value: hapticsEnabled,
                  onChanged: (enabled) => ref
                      .read(hapticsEnabledProvider.notifier)
                      .setEnabled(enabled),
                ),
                _GroupLabel(ar ? 'الحساب' : 'Account'),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(ar ? 'الاشتراك' : 'Subscription'),
                  subtitle: Text(
                    ar
                        ? 'الخطة الحالية وإدارة اشتراك Google Play'
                        : 'Current plan and Google Play subscription',
                  ),
                  trailing: Icon(Icons.chevron_right, color: c.inkMuted),
                  onTap: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute<void>(
                        builder: (_) => SubscriptionManagementScreen(
                          profile: profile,
                          language: language,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(ar ? 'تغيير كلمة المرور' : 'Change password'),
                  trailing: Icon(Icons.chevron_right, color: c.inkMuted),
                  onTap: () => _changePassword(context, ref),
                ),
                _BiometricTile(language: language),
                if (!profile.isPlatformOwner)
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: c.rejected,
                    ),
                    title: Text(
                      ar ? 'حذف الحساب' : 'Delete account',
                      style: TextStyle(color: c.rejected),
                    ),
                    subtitle: Text(
                      ar
                          ? 'حذف تسجيل الدخول والبيانات الشخصية المرتبطة به نهائيًا'
                          : 'Permanently remove your login and linked personal data',
                    ),
                    trailing: Icon(Icons.chevron_right, color: c.inkMuted),
                    onTap: () => showChecklistAccountDeletionFlow(
                      context: context,
                      ref: ref,
                      language: language,
                    ),
                  ),
                _GroupLabel(ar ? 'الدعم والخصوصية' : 'Support & privacy'),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  // Isolate the address so it reads left-to-right in Arabic.
                  title: Text('\u2066$checkViewSupportEmail\u2069'),
                  subtitle: Text(
                    ar ? 'راسل فريق الدعم' : 'Email the support team',
                  ),
                  trailing: Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: c.inkMuted,
                  ),
                  onTap: () => _contactSupport(context),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(ar ? 'سياسة الخصوصية' : 'Privacy policy'),
                  trailing: Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: c.inkMuted,
                  ),
                  onTap: () => _openExternal(
                    context,
                    Uri.parse(checklistPrivacyPolicyUrl),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: Text(
                    ar ? 'معلومات حذف الحساب' : 'Account deletion information',
                  ),
                  trailing: Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: c.inkMuted,
                  ),
                  onTap: () => _openExternal(
                    context,
                    Uri.parse(checklistAccountDeletionUrl),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(CvSpace.gutter),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.rejected,
                  side: BorderSide(color: c.rejected.withValues(alpha: 0.5)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(authRepositoryProvider).signOut();
                },
                icon: const Icon(Icons.logout, size: 20),
                label: Text(ar ? 'تسجيل الخروج' : 'Sign out'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _contactSupport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var launched = false;
    try {
      launched = await launchUrl(Uri.parse('mailto:$checkViewSupportEmail'));
    } catch (_) {
      launched = false;
    }
    if (launched) return;
    await Clipboard.setData(const ClipboardData(text: checkViewSupportEmail));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ar
              ? 'لا يوجد تطبيق بريد. تم نسخ العنوان.'
              : 'No email app found. The address was copied.',
        ),
      ),
    );
  }

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ar
                ? 'تعذر فتح الرابط. استخدم $checkViewSupportEmail للدعم.'
                : 'Could not open the link. Contact $checkViewSupportEmail for support.',
          ),
        ),
      );
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(language: language),
    );
    if (password == null) return;
    try {
      await ref.read(authRepositoryProvider).updatePassword(password);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ar ? 'تم تحديث كلمة المرور' : 'Password updated'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(cvUserMessage(e, language))),
      );
    }
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.profile, required this.language});

  final Profile profile;
  final String language;

  String get _name =>
      profile.fullName.trim().isEmpty ? profile.email : profile.fullName.trim();

  String get _initials {
    final words = _name
        .split(RegExp(r'[\s@._-]+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .toList();
    if (words.isEmpty) return '?';
    return words.map((word) => word.characters.first.toUpperCase()).join();
  }

  String get _roleLabel {
    final ar = language == 'ar';
    if (profile.isPlatformOwner) return ar ? 'مالك المنصة' : 'Platform owner';
    return switch (profile.role) {
      UserRole.superAdmin => ar ? 'سوبر أدمن' : 'Super admin',
      UserRole.siteAdmin => ar ? 'أدمن' : 'Site admin',
      UserRole.technician => ar ? 'فني' : 'Technician',
      UserRole.technicianRequest => ar ? 'طلب فني' : 'Technician request',
      UserRole.viewer => ar ? 'عارض' : 'Viewer',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final ar = language == 'ar';
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        CvSpace.gutter,
        MediaQuery.paddingOf(context).top + CvSpace.md,
        CvSpace.xs,
        CvSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    ar ? 'الإعدادات' : 'Settings',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: CvSpace.md),
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(CvRadius.control),
                  ),
                  child: Text(
                    _initials,
                    style: theme.textTheme.titleMedium?.copyWith(color: c.ink),
                  ),
                ),
              ),
              const SizedBox(width: CvSpace.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: CvSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (profile.email.trim().isNotEmpty &&
                          profile.email != _name)
                        Text(
                          profile.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: 2),
                      Text(_roleLabel, style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CvSpace.gutter,
        CvSpace.xl,
        CvSpace.gutter,
        CvSpace.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _BiometricTile extends ConsumerWidget {
  const _BiometricTile({required this.language});

  final String language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    final security = ref.watch(sessionSecurityProvider);
    if (!security.ready) return const SizedBox.shrink();
    if (!security.canUseBiometrics) {
      return ListTile(
        leading: const Icon(Icons.fingerprint),
        title: Text(ar ? 'الدخول بالبصمة' : 'Biometric sign-in'),
        subtitle: Text(
          ar
              ? 'الجهاز لا يدعم البصمة أو Face ID'
              : 'This device has no fingerprint or Face ID',
        ),
      );
    }
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: Text(
        ar
            ? 'الدخول عبر ${security.biometricLabel}'
            : 'Sign in with ${security.biometricLabel}',
      ),
      value: security.biometricEnabled,
      onChanged: (enabled) async {
        if (!enabled) {
          await ref.read(sessionSecurityProvider.notifier).disableBiometrics();
          return;
        }
        final err = await ref
            .read(sessionSecurityProvider.notifier)
            .enableBiometrics(
              reason: ar
                  ? 'أكد عبر ${security.biometricLabel}'
                  : 'Confirm with ${security.biometricLabel}',
            );
        if (err != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(err)));
        }
      },
    );
  }
}

/// Returns the new password once both fields match and meet the minimum.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.language});

  final String language;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  static const _minLength = 6;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _attempted = false;

  bool get ar => widget.language == 'ar';

  String? get _error {
    if (_password.text.length < _minLength) {
      return ar
          ? 'كلمة المرور يجب ألا تقل عن $_minLength أحرف'
          : 'Use at least $_minLength characters';
    }
    if (_password.text != _confirm.text) {
      return ar ? 'كلمتا المرور غير متطابقتين' : 'Passwords do not match';
    }
    return null;
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    if (_error != null) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final error = _attempted ? _error : null;
    return AlertDialog(
      title: Text(ar ? 'تغيير كلمة المرور' : 'Change password'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: ar ? 'كلمة المرور الجديدة' : 'New password',
              ),
            ),
            const SizedBox(height: CvSpace.md),
            TextField(
              controller: _confirm,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: ar ? 'تأكيد كلمة المرور' : 'Confirm password',
                errorText: error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(onPressed: _save, child: Text(ar ? 'حفظ' : 'Save')),
      ],
    );
  }
}
