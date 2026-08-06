import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_labels.dart';
import '../models/profile.dart';
import '../providers/preferences_providers.dart';
import '../providers/providers.dart';
import '../theme/checklist_brand.dart';

/// Settings drawer aligned with smart-meters entry/admin drawers.
class ChecklistSettingsDrawer extends ConsumerWidget {
  const ChecklistSettingsDrawer({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
    this.languages = const ['en', 'ar'],
    this.advancedItems = const [],
    this.appIconAsset,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onLanguageChanged;
  final List<String> languages;
  final List<Widget> advancedItems;
  /// Optional path to launcher-style branding asset (نقوش).
  final String? appIconAsset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);
    final name = profile.fullName.trim().isEmpty
        ? profile.email
        : profile.fullName;

    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(gradient: ChecklistChrome.appBarGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (appIconAsset != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          appIconAsset!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      )
                    else
                      ChecklistIconWell(icon: Icons.settings_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ar ? 'الإعدادات' : 'Settings',
                        style: TextStyle(
                          color: ChecklistChrome.onAccent,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  style: TextStyle(
                    color: ChecklistChrome.onAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  profile.email,
                  style: TextStyle(
                    color: ChecklistChrome.onAccent.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                _section(ar ? 'المظهر' : 'Appearance', Icons.palette_outlined),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_outlined, size: 18),
                      label: Text(ar ? 'فاتح' : 'Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text(ar ? 'داكن' : 'Dark'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(Icons.brightness_auto_outlined, size: 18),
                      label: Text(ar ? 'نظام' : 'System'),
                    ),
                  ],
                  selected: {themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      ref.read(themeModeProvider.notifier).setMode(s.first),
                ),
                const SizedBox(height: 20),
                _section(ar ? 'اللغة' : 'Language', Icons.translate_outlined),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    for (final code in languages)
                      ButtonSegment(
                        value: code,
                        label: Text(languageDisplayNames[code] ?? code),
                      ),
                  ],
                  selected: {language},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => onLanguageChanged(s.first),
                ),
                const SizedBox(height: 20),
                _section(ar ? 'الحساب' : 'Account', Icons.person_outline),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline),
                  title: Text(ar ? 'تغيير كلمة المرور' : 'Change password'),
                  onTap: () => _changePassword(context, ref, ar),
                ),
                const SizedBox(height: 12),
                _section(ar ? 'حول التطبيق' : 'About', Icons.info_outline),
                const SizedBox(height: 6),
                Text(
                  ar ? 'تطوير وتصميم' : 'Created & developed by',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ChecklistChrome.inkMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ali Karim — AliMind',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ChecklistChrome.ink,
                  ),
                ),
                InkWell(
                  onTap: () => launchUrl(Uri.parse('tel:+97430058899')),
                  child: const Text('+974 3005 8899'),
                ),
                InkWell(
                  onTap: () =>
                      launchUrl(Uri.parse('mailto:Support@AliMind.com')),
                  child: const Text('Support@AliMind.com'),
                ),
                if (advancedItems.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _section(
                    ar ? 'أدوات متقدمة' : 'Advanced tools',
                    Icons.handyman_outlined,
                  ),
                  ...advancedItems,
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(authRepositoryProvider).signOut();
                },
                icon: const Icon(Icons.logout),
                label: Text(ar ? 'تسجيل الخروج' : 'Sign out'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ChecklistChrome.accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: ChecklistChrome.ink,
          ),
        ),
      ],
    );
  }

  Future<void> _changePassword(
    BuildContext context,
    WidgetRef ref,
    bool ar,
  ) async {
    final pwd = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ar ? 'تغيير كلمة المرور' : 'Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pwd,
              obscureText: true,
              decoration: InputDecoration(
                labelText: ar ? 'كلمة المرور الجديدة' : 'New password',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: InputDecoration(
                labelText: ar ? 'تأكيد' : 'Confirm',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ar ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (pwd.text.length < 6 || pwd.text != confirm.text) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ar
                  ? 'كلمة المرور غير صالحة أو غير متطابقة'
                  : 'Invalid or mismatched password',
            ),
          ),
        );
      }
      return;
    }
    try {
      await ref.read(authRepositoryProvider).updatePassword(pwd.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ar ? 'تم تحديث كلمة المرور' : 'Password updated'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}
