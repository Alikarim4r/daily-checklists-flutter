import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_labels.dart';
import '../models/profile.dart';
import '../providers/preferences_providers.dart';
import '../providers/providers.dart';
import '../providers/session_security_provider.dart';
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

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    final themeMode = ref.watch(themeModeProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final soundEnabled = ref.watch(soundEnabledProvider);
    final hapticsEnabled = ref.watch(hapticsEnabledProvider);
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
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
                _ThemeModeTiles(
                  language: language,
                  selected: themeMode,
                  onSelected: (next) {
                    // Defer out of the drawer button gesture; MaterialApp swaps
                    // themes without SegmentedButton's M3 state machine mid-tree.
                    Future<void>.delayed(Duration.zero, () {
                      ref.read(themeModeProvider.notifier).setMode(next);
                    });
                  },
                ),
                const SizedBox(height: 20),
                _section(ar ? 'اللغة' : 'Language', Icons.translate_outlined),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: languages.contains(language)
                      ? language
                      : languages.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.language_outlined, size: 20),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    for (final code in languages)
                      DropdownMenuItem(
                        value: code,
                        child: Text(
                          languageDisplayNames[code] ?? code,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (code) {
                    if (code != null) onLanguageChanged(code);
                  },
                ),
                const SizedBox(height: 20),
                _section(
                  ar ? 'الإشعارات والتنبيهات' : 'Notifications & feedback',
                  Icons.notifications_active_outlined,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_outlined),
                  title: Text(ar ? 'مركز الإشعارات' : 'Notification centre'),
                  subtitle: Text(
                    ar
                        ? 'إظهار التنبيهات التشغيلية والمهام المطلوبة'
                        : 'Show operational alerts and required actions',
                  ),
                  value: notificationsEnabled,
                  onChanged: (enabled) => ref
                      .read(notificationsEnabledProvider.notifier)
                      .setEnabled(enabled),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: Text(ar ? 'أصوات التنبيه' : 'Alert sounds'),
                  subtitle: Text(
                    ar
                        ? 'صوت عند نجاح الحفظ أو وجود متابعة عاجلة'
                        : 'Sound on successful saves and urgent follow-ups',
                  ),
                  value: soundEnabled,
                  onChanged: (enabled) => ref
                      .read(soundEnabledProvider.notifier)
                      .setEnabled(enabled),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.vibration_outlined),
                  title: Text(ar ? 'الاهتزاز اللمسي' : 'Haptic feedback'),
                  value: hapticsEnabled,
                  onChanged: (enabled) => ref
                      .read(hapticsEnabledProvider.notifier)
                      .setEnabled(enabled),
                ),
                const SizedBox(height: 20),
                _section(ar ? 'الحساب' : 'Account', Icons.person_outline),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline),
                  title: Text(ar ? 'تغيير كلمة المرور' : 'Change password'),
                  onTap: () => _changePassword(context, ref, ar),
                ),
                const SizedBox(height: 8),
                _biometricTile(context, ref, ar),
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
                const SizedBox(height: 8),
                FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    if (info == null) return const SizedBox.shrink();
                    return Text(
                      ar
                          ? 'الإصدار ${info.version} · البناء ${info.buildNumber}'
                          : 'Version ${info.version} · Build ${info.buildNumber}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: ChecklistChrome.inkMuted,
                      ),
                    );
                  },
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

  Widget _biometricTile(BuildContext context, WidgetRef ref, bool ar) {
    final security = ref.watch(sessionSecurityProvider);
    if (!security.ready) return const SizedBox.shrink();
    if (!security.canUseBiometrics) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.fingerprint),
        title: Text(
          ar
              ? 'الجهاز لا يدعم البصمة أو Face ID'
              : 'This device has no fingerprint or Face ID',
        ),
      );
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _ThemeModeTiles extends StatelessWidget {
  const _ThemeModeTiles({
    required this.language,
    required this.selected,
    required this.onSelected,
  });

  final String language;
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final ar = language == 'ar';
    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.light, Icons.light_mode_outlined, ar ? 'فاتح' : 'Light'),
      (ThemeMode.dark, Icons.dark_mode_outlined, ar ? 'داكن' : 'Dark'),
      (
        ThemeMode.system,
        Icons.brightness_auto_outlined,
        ar ? 'نظام' : 'System',
      ),
    ];
    return Column(
      children: [
        for (final (mode, icon, label) in options)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(icon, size: 20),
            title: Text(label),
            trailing: selected == mode
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            selected: selected == mode,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            onTap: selected == mode ? null : () => onSelected(mode),
          ),
      ],
    );
  }
}
