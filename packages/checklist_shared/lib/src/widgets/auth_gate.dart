import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/profile.dart';
import '../providers/providers.dart';
import '../providers/session_security_provider.dart';
import '../theme/viewer_palette.dart';

typedef ProfilePredicate = bool Function(Profile profile);
typedef HomeBuilder = Widget Function(BuildContext context, Profile profile);

/// Login → approval → role gate → optional site access → home.
class ChecklistAuthGate extends ConsumerStatefulWidget {
  const ChecklistAuthGate({
    super.key,
    required this.appTitle,
    required this.subtitle,
    required this.allowedForProfile,
    required this.homeBuilder,
    this.siteAccessRequirement = SiteAccessRequirement.none,
    this.accessDeniedMessage = 'لا تملك صلاحية استخدام هذا التطبيق.',
    this.noSiteAccessMessage =
        'لم تُعيَّن لك مواقع بعد. تواصل مع المسؤول لاعتماد الحساب وربطه بالمواقع.',
  });

  final String appTitle;
  final String subtitle;
  final ProfilePredicate allowedForProfile;
  final HomeBuilder homeBuilder;
  final SiteAccessRequirement siteAccessRequirement;
  final String accessDeniedMessage;
  final String noSiteAccessMessage;

  @override
  ConsumerState<ChecklistAuthGate> createState() => _ChecklistAuthGateState();
}

class _ChecklistAuthGateState extends ConsumerState<ChecklistAuthGate> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  String? error;

  /// Temporary trial login (staging/demo only). Remove when real auth is ready.
  static const _demoEnabled = bool.fromEnvironment(
    'DEMO_LOGIN',
    defaultValue: true,
  );
  static const _demoEmail = String.fromEnvironment(
    'DEMO_EMAIL',
    defaultValue: 'alikarim4r@gmail.com',
  );
  static const _demoPassword = String.fromEnvironment(
    'DEMO_PASSWORD',
    defaultValue: 'DemoTemp2026!',
  );

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _signIn({String? overrideEmail, String? overridePassword}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final mail = (overrideEmail ?? email.text).trim();
      final pass = overridePassword ?? password.text;
      await ref.read(authRepositoryProvider).signIn(
            email: mail,
            password: pass,
          );
      await ref.read(sessionSecurityProvider.notifier).onPasswordSignIn(
            email: mail,
            password: pass,
          );
      ref.invalidate(currentProfileProvider);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _biometricQuickSignIn() async {
    final security = ref.read(sessionSecurityProvider);
    final ar = Directionality.of(context) == TextDirection.rtl;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final ok = await ref.read(sessionSecurityProvider.notifier).unlock(
            reason: ar
                ? 'استخدم ${security.biometricLabel} لتسجيل الدخول'
                : 'Use ${security.biometricLabel} to sign in',
          );
      if (!ok) {
        setState(() => error = ar ? 'فشل التحقق بالبصمة' : 'Biometric failed');
        return;
      }
      final creds =
          await ref.read(sessionSecurityProvider.notifier).storedCredentials();
      if (creds == null) {
        setState(() =>
            error = ar ? 'لا توجد بيانات محفوظة' : 'No saved credentials');
        return;
      }
      await _signIn(overrideEmail: creds.email, overridePassword: creds.password);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _demoSignIn() async {
    email.text = _demoEmail;
    password.text = _demoPassword;
    await _signIn(overrideEmail: _demoEmail, overridePassword: _demoPassword);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (state) {
        if (state.session == null) return _loginScaffold();
        final profileAsync = ref.watch(currentProfileProvider);
        return profileAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
          data: (profile) {
            if (profile == null) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('لم يتم العثور على الملف الشخصي.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.read(authRepositoryProvider).signOut(),
                        child: const Text('خروج'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!profile.isApprovedActive && !profile.isPlatformOwner) {
              return _statusScaffold(
                'الحساب بانتظار الموافقة أو غير نشط.',
                profile,
              );
            }
            if (!widget.allowedForProfile(profile)) {
              return _statusScaffold(widget.accessDeniedMessage, profile);
            }
            if (widget.siteAccessRequirement != SiteAccessRequirement.none &&
                !profile.isPlatformOwner &&
                profile.role != UserRole.superAdmin) {
              return FutureBuilder<int>(
                future: ref.read(siteRepositoryProvider).countMyAccess(
                      requirement: widget.siteAccessRequirement,
                    ),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.data! < 1) {
                    return _statusScaffold(
                      widget.noSiteAccessMessage,
                      profile,
                    );
                  }
                  return _maybeBiometricGate(
                    context,
                    widget.homeBuilder(context, profile),
                  );
                },
              );
            }
            return _maybeBiometricGate(
              context,
              widget.homeBuilder(context, profile),
            );
          },
        );
      },
    );
  }

  Widget _maybeBiometricGate(BuildContext context, Widget home) {
    final security = ref.watch(sessionSecurityProvider);
    if (!security.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!security.requiresUnlock) return home;
    final ar = Directionality.of(context) == TextDirection.rtl;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fingerprint, size: 56, color: ViewerPalette.orange),
              const SizedBox(height: 16),
              Text(
                ar
                    ? 'افتح التطبيق عبر ${security.biometricLabel}'
                    : 'Unlock with ${security.biometricLabel}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  await ref.read(sessionSecurityProvider.notifier).unlock(
                        reason: ar
                            ? 'استخدم ${security.biometricLabel} للمتابعة'
                            : 'Use ${security.biometricLabel} to continue',
                      );
                },
                icon: const Icon(Icons.fingerprint),
                label: Text(ar ? 'فتح' : 'Unlock'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                child: Text(ar ? 'تسجيل الخروج' : 'Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusScaffold(String message, Profile profile) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(profile.email, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                child: const Text('خروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginScaffold() {
    return Scaffold(
      backgroundColor: ViewerPalette.orangeSoft,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.appTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ViewerPalette.orange,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: loading ? null : () => _signIn(),
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('دخول'),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final security = ref.watch(sessionSecurityProvider);
                      if (!security.ready ||
                          !security.biometricEnabled ||
                          !security.canUseBiometrics) {
                        return const SizedBox.shrink();
                      }
                      final ar =
                          Directionality.of(context) == TextDirection.rtl;
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                loading ? null : _biometricQuickSignIn,
                            icon: const Icon(Icons.fingerprint),
                            label: Text(
                              ar
                                  ? 'دخول عبر ${security.biometricLabel}'
                                  : 'Continue with ${security.biometricLabel}',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_demoEnabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: loading ? null : _demoSignIn,
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('دخول تجريبي (مؤقت)'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'للتجربة فقط — يُزال لاحقًا',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
