import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/profile.dart';
import '../offline/offline_inspection_queue.dart';
import '../providers/providers.dart';
import '../providers/session_security_provider.dart';
import '../services/checklist_connectivity.dart';
import '../theme/checklist_brand.dart';

typedef ProfilePredicate = bool Function(Profile profile);
typedef HomeBuilder = Widget Function(BuildContext context, Profile profile);
typedef PendingProfileBuilder =
    Widget Function(BuildContext context, Profile profile);
typedef UserErrorMessage = String Function(Object error);

/// Login → approval → role gate → optional site access → home.
/// Layout aligned with smart-meters AppLoginPanel.
class ChecklistAuthGate extends ConsumerStatefulWidget {
  const ChecklistAuthGate({
    super.key,
    required this.appTitle,
    required this.subtitle,
    required this.allowedForProfile,
    required this.homeBuilder,
    this.language = 'en',
    this.onLanguageChanged,
    this.allowSelfRegistration = true,
    this.registrationRequestedRole = 'technician_request',
    this.registrationAccessCodeRequired = false,
    this.registrationIntroEn,
    this.registrationIntroAr,
    this.registrationSuccessEn,
    this.registrationSuccessAr,
    this.registrationActionLabelEn,
    this.registrationActionLabelAr,
    this.pendingProfileBuilder,
    this.brandMarkAsset,
    this.siteAccessRequirement = SiteAccessRequirement.none,
    this.accessDeniedMessage = 'لا تملك صلاحية استخدام هذا التطبيق.',
    this.noSiteAccessMessage =
        'لم تُعيَّن لك مواقع بعد. تواصل مع المسؤول لاعتماد الحساب وربطه بالمواقع.',
    this.userErrorMessage,
    this.allowOfflineAccess = false,
    this.compactPremiumLogin = false,
  });

  final String appTitle;
  final String subtitle;
  final ProfilePredicate allowedForProfile;
  final HomeBuilder homeBuilder;
  final String language;
  final ValueChanged<String>? onLanguageChanged;
  final bool allowSelfRegistration;
  final String registrationRequestedRole;
  final bool registrationAccessCodeRequired;
  final String? registrationIntroEn;
  final String? registrationIntroAr;
  final String? registrationSuccessEn;
  final String? registrationSuccessAr;
  final String? registrationActionLabelEn;
  final String? registrationActionLabelAr;
  final PendingProfileBuilder? pendingProfileBuilder;
  final String? brandMarkAsset;
  final SiteAccessRequirement siteAccessRequirement;
  final String accessDeniedMessage;
  final String noSiteAccessMessage;
  final UserErrorMessage? userErrorMessage;

  /// Allows a previously approved user to keep working from encrypted local
  /// data when the backend is unreachable. Passwords are never cached.
  final bool allowOfflineAccess;
  final bool compactPremiumLogin;

  @override
  ConsumerState<ChecklistAuthGate> createState() => _ChecklistAuthGateState();
}

class _ChecklistAuthGateState extends ConsumerState<ChecklistAuthGate>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final fullName = TextEditingController();
  final accessCode = TextEditingController();
  bool loading = false;
  bool obscurePassword = true;
  bool registerMode = false;
  String? error;
  String? info;
  String? _accessFutureKey;
  Future<int>? _accessFuture;

  /// Trial login credentials (owner account unchanged).
  static const _demoEnabled = bool.fromEnvironment(
    'DEMO_LOGIN',
    defaultValue: false,
  );
  static const _demoEmail = String.fromEnvironment(
    'DEMO_EMAIL',
    defaultValue: '',
  );
  static const _demoPassword = String.fromEnvironment(
    'DEMO_PASSWORD',
    defaultValue: '',
  );

  bool get _demoConfigured =>
      _demoEnabled && _demoEmail.isNotEmpty && _demoPassword.isNotEmpty;

  bool get ar => widget.language == 'ar';

  String _messageFor(Object error) =>
      widget.userErrorMessage?.call(error) ?? error.toString();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    fullName.dispose();
    accessCode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChecklistAuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteAccessRequirement != widget.siteAccessRequirement) {
      _accessFutureKey = null;
      _accessFuture = null;
    }
  }

  Profile? _cachedOfflineProfile() {
    if (!widget.allowOfflineAccess ||
        !OfflineInspectionQueue.instance.isReady) {
      return null;
    }
    final queue = OfflineInspectionQueue.instance;
    final profile = queue.cachedOfflineProfile();
    if (profile == null ||
        !(profile.isApprovedActive || profile.isPlatformOwner) ||
        !widget.allowedForProfile(profile)) {
      return null;
    }
    if (widget.siteAccessRequirement != SiteAccessRequirement.none &&
        !profile.isPlatformOwner &&
        profile.role != UserRole.superAdmin) {
      final hasValidGrant = queue
          .cachedOfflineSiteAccess()
          .where((access) => access.userId == profile.id)
          .any((access) => access.allows(widget.siteAccessRequirement));
      if (!hasValidGrant) return null;
    }
    return profile;
  }

  void _rememberOfflineProfile(Profile profile) {
    if (!widget.allowOfflineAccess ||
        !(profile.isApprovedActive || profile.isPlatformOwner) ||
        !widget.allowedForProfile(profile)) {
      return;
    }
    unawaited(_cacheOfflineAuthorization(profile));
  }

  Future<void> _cacheOfflineAuthorization(Profile profile) async {
    try {
      final needsGrantSnapshot =
          widget.siteAccessRequirement != SiteAccessRequirement.none &&
          !profile.isPlatformOwner &&
          profile.role != UserRole.superAdmin;
      final siteAccess = needsGrantSnapshot
          ? await ref.read(siteRepositoryProvider).listMySiteAccess()
          : const <UserSiteAccess>[];
      await OfflineInspectionQueue.instance.cacheOfflineProfile(
        profile,
        siteAccess: siteAccess,
      );
    } catch (_) {
      // Never overwrite a previously valid encrypted authorization snapshot
      // when the backend cannot refresh it.
    }
  }

  Widget _offlineHome(Profile profile) {
    return _maybeBiometricGate(context, widget.homeBuilder(context, profile));
  }

  Widget _offlineWhenBackendUnavailable({required Widget onlineFallback}) {
    final cached = _cachedOfflineProfile();
    // Explicit sign-out purges the encrypted offline profile. Therefore a
    // valid cached profile is a durable local statement that this user chose
    // to stay signed in. Do not bounce a field technician back to Login merely
    // because Auth/session restoration is still catching up after process
    // restart or a long offline period.
    if (cached != null) return _offlineHome(cached);
    return onlineFallback;
  }

  Future<int> _countSiteAccess(Profile profile) {
    final key = '${profile.id}:${widget.siteAccessRequirement.name}';
    if (_accessFutureKey != key || _accessFuture == null) {
      _accessFutureKey = key;
      _accessFuture = ref
          .read(siteRepositoryProvider)
          .countMyAccess(requirement: widget.siteAccessRequirement);
    }
    return _accessFuture!;
  }

  Future<void> _signIn({
    String? overrideEmail,
    String? overridePassword,
  }) async {
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      final mail = (overrideEmail ?? email.text).trim();
      final pass = overridePassword ?? password.text;
      await ref
          .read(authRepositoryProvider)
          .signIn(email: mail, password: pass);
      ref.read(sessionSecurityProvider.notifier).onPasswordSignIn();
      ref.invalidate(currentProfileProvider);
    } catch (e) {
      setState(() => error = _messageFor(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signUp(
            email: email.text.trim(),
            password: password.text,
            fullName: fullName.text.trim(),
            requestedRole: widget.registrationRequestedRole,
            accessCode: widget.registrationAccessCodeRequired
                ? accessCode.text
                : null,
          );
      setState(() {
        registerMode = false;
        info = ar
            ? (widget.registrationSuccessAr ??
                  'تم إرسال طلب التسجيل. انتظر موافقة المسؤول قبل الدخول.')
            : (widget.registrationSuccessEn ??
                  'Registration submitted. Wait for admin approval before signing in.');
        password.clear();
        accessCode.clear();
      });
    } catch (e) {
      setState(() => error = _messageFor(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _submit() async {
    if (registerMode && widget.allowSelfRegistration) {
      await _signUp();
    } else {
      if (!_formKey.currentState!.validate()) return;
      await _signIn();
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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) {
        final cached = _cachedOfflineProfile();
        if (cached != null && ChecklistConnectivity.isTransportFailure(e)) {
          return _offlineHome(cached);
        }
        return Scaffold(body: Center(child: Text(_messageFor(e))));
      },
      data: (state) {
        if (state.session == null) {
          return _offlineWhenBackendUnavailable(
            onlineFallback: _loginScaffold(),
          );
        }
        final profileAsync = ref.watch(currentProfileProvider);
        return profileAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) {
            final cached = _cachedOfflineProfile();
            if (cached != null && ChecklistConnectivity.isTransportFailure(e)) {
              return _offlineHome(cached);
            }
            return Scaffold(body: Center(child: Text(_messageFor(e))));
          },
          data: (profile) {
            if (profile == null) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ar
                            ? 'لم يتم العثور على الملف الشخصي.'
                            : 'Profile not found.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.read(authRepositoryProvider).signOut(),
                        child: Text(ar ? 'خروج' : 'Sign out'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!profile.isApprovedActive && !profile.isPlatformOwner) {
              final pendingBuilder = widget.pendingProfileBuilder;
              if (pendingBuilder != null) {
                return pendingBuilder(context, profile);
              }
              return _statusScaffold(
                ar
                    ? 'الحساب بانتظار الموافقة أو غير نشط.'
                    : 'Account pending approval or inactive.',
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
                future: _countSiteAccess(profile),
                builder: (context, snap) {
                  if (snap.hasError) {
                    final cached = _cachedOfflineProfile();
                    if (cached != null &&
                        cached.id == profile.id &&
                        ChecklistConnectivity.isTransportFailure(snap.error!)) {
                      return _offlineHome(cached);
                    }
                    return _statusScaffold(_messageFor(snap.error!), profile);
                  }
                  if (!snap.hasData) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.data! < 1) {
                    return _statusScaffold(widget.noSiteAccessMessage, profile);
                  }
                  _rememberOfflineProfile(profile);
                  return _maybeBiometricGate(
                    context,
                    widget.homeBuilder(context, profile),
                  );
                },
              );
            }
            _rememberOfflineProfile(profile);
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
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fingerprint, size: 56, color: ChecklistChrome.accent),
              const SizedBox(height: 16),
              Text(
                ar
                    ? 'افتح التطبيق عبر ${security.biometricLabel}'
                    : 'Unlock with ${security.biometricLabel}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  await ref
                      .read(sessionSecurityProvider.notifier)
                      .unlock(
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
                child: Text(ar ? 'خروج' : 'Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandMark({double size = 72, double radius = 16}) {
    final asset = widget.brandMarkAsset;
    if (asset != null && asset.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackMark(size: size, radius: radius),
        ),
      );
    }
    return _fallbackMark(size: size, radius: radius);
  }

  Widget _fallbackMark({double size = 72, double radius = 16}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: ChecklistChrome.iconWellGradient,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.fact_check_rounded,
        size: size * .5,
        color: ChecklistChrome.iconGlyph,
      ),
    );
  }

  Widget _loginScaffold() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final registering = widget.allowSelfRegistration && registerMode;
    final subtitle = registering
        ? (ar
              ? (widget.registrationIntroAr ??
                    'أنشئ حساباً. سيظهر لدى المشرف للموافقة قبل الدخول.')
              : (widget.registrationIntroEn ??
                    'Create an account. An admin must approve before access.'))
        : widget.subtitle;

    return Scaffold(
      backgroundColor: widget.compactPremiumLogin
          ? theme.scaffoldBackgroundColor
          : dark
          ? ChecklistChrome.darkCanvas
          : Color.alphaBlend(
              ChecklistChrome.accentSoft.withValues(alpha: 0.55),
              Colors.white,
            ),
      body: SafeArea(
        child: Align(
          alignment: widget.compactPremiumLogin
              ? Alignment.topCenter
              : Alignment.center,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: widget.compactPremiumLogin ? 16 : 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: widget.compactPremiumLogin
                    ? const BoxDecoration()
                    : BoxDecoration(
                        color: dark
                            ? ChecklistChrome.darkSurface
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: ChecklistChrome.accent.withValues(alpha: 0.28),
                        ),
                        boxShadow: dark
                            ? null
                            : [
                                BoxShadow(
                                  color: ChecklistChrome.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                      ),
                child: Padding(
                  padding: widget.compactPremiumLogin
                      ? const EdgeInsets.fromLTRB(4, 4, 4, 24)
                      : const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.onLanguageChanged != null)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: SegmentedButton<String>(
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: const [
                                ButtonSegment(value: 'en', label: Text('E')),
                                ButtonSegment(value: 'ar', label: Text('ع')),
                              ],
                              selected: {widget.language},
                              onSelectionChanged: (s) =>
                                  widget.onLanguageChanged!(s.first),
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (widget.compactPremiumLogin)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _brandMark(size: 52, radius: 12),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.appTitle,
                                      style: theme.textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else ...[
                          Center(child: _brandMark()),
                          const SizedBox(height: 16),
                          Text(
                            widget.appTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dark
                                  ? ChecklistChrome.darkInk
                                  : ChecklistChrome.ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: dark
                                  ? ChecklistChrome.darkInkMuted
                                  : ChecklistChrome.inkMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                        SizedBox(height: widget.compactPremiumLogin ? 28 : 22),
                        if (registering) ...[
                          TextFormField(
                            controller: fullName,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: ar ? 'الاسم الكامل' : 'Full name',
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return ar ? 'الاسم مطلوب' : 'Name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (registering &&
                            widget.registrationAccessCodeRequired) ...[
                          TextFormField(
                            controller: accessCode,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.characters,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: ar
                                  ? 'رمز الشركة أو الدعوة'
                                  : 'Company or invitation code',
                              hintText: 'ORG-XXXXXX / INV-XXXXXXXX',
                              prefixIcon: const Icon(Icons.vpn_key_outlined),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (!registering ||
                                  !widget.registrationAccessCodeRequired) {
                                return null;
                              }
                              if (value == null || value.trim().isEmpty) {
                                return ar
                                    ? 'رمز الشركة أو الدعوة مطلوب'
                                    : 'Company or invitation code is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: ar ? 'البريد الإلكتروني' : 'Email',
                            prefixIcon: const Icon(Icons.mail_outline_rounded),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return ar
                                  ? 'البريد الإلكتروني مطلوب'
                                  : 'Email is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: password,
                          obscureText: obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => loading ? null : _submit(),
                          decoration: InputDecoration(
                            labelText: ar ? 'كلمة المرور' : 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: ar
                                  ? (obscurePassword
                                        ? 'إظهار كلمة المرور'
                                        : 'إخفاء كلمة المرور')
                                  : (obscurePassword
                                        ? 'Show password'
                                        : 'Hide password'),
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => obscurePassword = !obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return ar
                                  ? 'كلمة المرور مطلوبة'
                                  : 'Password is required';
                            }
                            if (registering && v.length < 6) {
                              return ar
                                  ? 'كلمة المرور يجب ألا تقل عن 6 أحرف'
                                  : 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        if (info != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: ChecklistChrome.accent.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: ChecklistChrome.accent.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text(
                              info!,
                              style: TextStyle(
                                color: ChecklistChrome.accentDeep,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.error.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: ChecklistChrome.accent,
                            foregroundColor: ChecklistChrome.onAccent,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: loading ? null : _submit,
                          child: loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  registering
                                      ? (ar
                                            ? (widget.registrationActionLabelAr ??
                                                  'إنشاء حساب')
                                            : (widget.registrationActionLabelEn ??
                                                  'Create account'))
                                      : (ar ? 'تسجيل الدخول' : 'Sign in'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                        if (widget.allowSelfRegistration) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: loading
                                ? null
                                : () => setState(() {
                                    registerMode = !registerMode;
                                    error = null;
                                    info = null;
                                  }),
                            child: Text(
                              registering
                                  ? (ar
                                        ? 'لديك حساب؟ تسجيل الدخول'
                                        : 'Have an account? Sign in')
                                  : (ar ? 'حساب جديد' : 'Create an account'),
                            ),
                          ),
                        ],
                        if (_demoConfigured && !registering) ...[
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: loading ? null : _demoSignIn,
                            icon: const Icon(Icons.science_outlined),
                            label: Text(ar ? 'دخول تجريبي' : 'Trial login'),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ar
                                ? 'للتجربة فقط — لا يغيّر حساب المالك'
                                : 'Trial only — owner account unchanged',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: ChecklistChrome.inkMutedFor(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
