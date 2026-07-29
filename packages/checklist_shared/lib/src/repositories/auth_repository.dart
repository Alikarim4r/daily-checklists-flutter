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
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<Profile?> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<Profile>> listProfiles() async {
    final rows = await _client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Atomic approve: role + site assignments via RPC.
  Future<void> approveUser({
    required String userId,
    required UserRole role,
    required List<String> siteIds,
    String? note,
  }) async {
    await _client.rpc(
      'admin_approve_user',
      params: {
        'p_user_id': userId,
        'p_role': role.dbValue,
        'p_site_ids': siteIds,
        'p_note': note,
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
      params: {
        'p_user_id': userId,
        'p_status': status.dbValue,
        'p_note': note,
      },
    );
  }
}
