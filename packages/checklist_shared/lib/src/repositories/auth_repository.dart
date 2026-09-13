import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/profile.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

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
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim(), 'requested_role': requestedRole},
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
  }

  /// Create an Auth user through a trusted Edge Function using Auth Admin API.
  Future<String> createUser({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await _client.functions.invoke(
      'admin-create-user',
      body: {
        'email': email.trim(),
        'password': password,
        'full_name': fullName?.trim(),
      },
    );
    final data = response.data;
    final id = data is Map ? data['id'] as String? : null;
    if (id == null || id.isEmpty) {
      throw StateError('User creation returned no user id');
    }
    return id;
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
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
}
