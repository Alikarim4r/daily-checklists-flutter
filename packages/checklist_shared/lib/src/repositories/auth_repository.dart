import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../offline/offline_inspection_queue.dart';
import '../models/profile.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  /// Ensures a persisted session is usable before network work resumes.
  ///
  /// Supabase persists sessions by default, but a device can come back online
  /// after the access token has expired. Refreshing explicitly here prevents
  /// offline queue replay from being misclassified as a record failure while
  /// Auth is still recovering. No password is stored locally.
  Future<bool> ensureActiveSession() async {
    final session = _client.auth.currentSession;
    if (session == null) return false;
    try {
      final response = await _client.auth.refreshSession();
      return response.session != null || _client.auth.currentSession != null;
    } catch (error) {
      final text = '$error'.toLowerCase();
      if (text.contains('socketexception') ||
          text.contains('failed host lookup') ||
          text.contains('network') ||
          text.contains('timed out') ||
          text.contains('timeout')) {
        return false;
      }
      // A still-current session may remain usable even when the refresh
      // endpoint returns a transient/non-fatal response. Let the first real
      // request decide; callers keep offline data queued on auth failures.
      return _client.auth.currentSession != null;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.session != null) {
      try {
        await _client.rpc(
          'record_session_audit',
          params: {
            'p_action': 'login',
            'p_metadata': {'auth_provider': 'password'},
          },
        );
      } catch (_) {
        // Audit transport failure must not turn a valid login into a lockout.
      }
    }
    return response;
  }

  /// Self-registration. Profile is created pending via `handle_new_user`.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String requestedRole = 'technician_request',
    String? accessCode,
  }) {
    final code = accessCode?.trim();
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'requested_role': requestedRole,
        if (code != null && code.isNotEmpty) 'access_code': code.toUpperCase(),
      },
    );
  }

  Future<void> signOut() async {
    if (_client.auth.currentSession != null) {
      try {
        await _client.rpc(
          'record_session_audit',
          params: {'p_action': 'logout', 'p_metadata': const {}},
        );
      } catch (_) {}
    }
    await _client.auth.signOut();
    await OfflineInspectionQueue.instance.purgeUserDataIfReady();
  }

  /// Create Auth user + pending profile (owner / super_admin RPC).
  Future<String> createUser({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final id = await _client.rpc(
      'admin_create_user',
      params: {
        'p_email': email.trim(),
        'p_password': password,
        'p_full_name': fullName,
      },
    );
    return id as String;
  }

  Future<Map<String, dynamic>> createOrganizationInvitation({
    required String email,
    String? fullName,
    required UserRole role,
    required List<Map<String, String>> scopes,
    String? organizationId,
  }) async {
    final raw = await _client.rpc(
      'create_organization_invitation',
      params: {
        'p_email': email.trim(),
        'p_full_name': fullName?.trim(),
        'p_role': role.dbValue,
        'p_scopes': scopes,
        'p_organization_id': organizationId,
      },
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> cancelOrganizationInvitation(String invitationId) async {
    await _client.rpc(
      'cancel_organization_invitation',
      params: {'p_invitation_id': invitationId},
    );
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Permanently deletes the signed-in account after password re-authentication.
  ///
  /// The server owns all destructive work. The client never receives the
  /// service-role credential and never attempts to delete database rows itself.
  Future<void> deleteAccount({required String currentPassword}) async {
    final user = currentUser;
    final email = user?.email?.trim();
    if (user == null || email == null || email.isEmpty) {
      throw StateError('account_reauthentication_unavailable');
    }

    final reauthenticated = await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    if (reauthenticated.session == null) {
      throw StateError('account_reauthentication_failed');
    }

    final response = await _client.functions.invoke(
      'delete-account',
      body: const {'confirm': true},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('account_deletion_failed');
    }
    final data = response.data;
    if (data is! Map || data['deleted'] != true) {
      throw StateError('account_deletion_failed');
    }

    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The remote user is already gone; local auth listeners will refresh on
      // the next auth operation even if session cleanup itself reports an error.
    }
  }

  Future<Profile?> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    final ownerFlag = await _client.rpc('is_platform_owner');
    return Profile.fromJson({
      ...Map<String, dynamic>.from(row),
      'is_platform_owner': ownerFlag == true,
    });
  }

  Future<List<Profile>> listProfiles() async {
    final rows = await _client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    final ownerRows = await _client.rpc('list_platform_owner_ids');
    final ownerIds = <String>{
      for (final row in ownerRows as List)
        if ((row as Map)['user_id'] case final String id) id,
    };
    return (rows as List).map((e) {
      final json = Map<String, dynamic>.from(e as Map);
      json['is_platform_owner'] = ownerIds.contains(json['id']);
      return Profile.fromJson(json);
    }).toList();
  }

  /// Atomic approve: role + site assignments via RPC.
  /// [organizationId] required when [role] is [UserRole.superAdmin].
  Future<void> approveUser({
    required String userId,
    required UserRole role,
    required List<String> siteIds,
    String? note,
    String? organizationId,
  }) async {
    await _client.rpc(
      'admin_approve_user',
      params: {
        'p_user_id': userId,
        'p_role': role.dbValue,
        'p_site_ids': siteIds,
        'p_note': note,
        'p_organization_id': organizationId,
      },
    );
  }

  Future<void> setUserStatus({
    required String userId,
    required ApprovalStatus status,
    String? note,
  }) async {
    await _client.rpc(
      'admin_set_user_status',
      params: {'p_user_id': userId, 'p_status': status.dbValue, 'p_note': note},
    );
  }

  Future<void> setReopenApprovedPermission({
    required String userId,
    required bool enabled,
  }) async {
    await _client.rpc(
      'admin_set_reopen_permission',
      params: {'p_user_id': userId, 'p_enabled': enabled},
    );
  }
}
