import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bootstrap/bootstrap.dart';
import '../models/profile.dart';
import '../repositories/auth_repository.dart';
import '../repositories/correction_repository.dart';
import '../repositories/inspection_repository.dart';
import '../repositories/site_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => supabase);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final siteRepositoryProvider = Provider<SiteRepository>(
  (ref) => SiteRepository(ref.watch(supabaseClientProvider)),
);

final inspectionRepositoryProvider = Provider<InspectionRepository>(
  (ref) => InspectionRepository(ref.watch(supabaseClientProvider)),
);

final correctionRepositoryProvider = Provider<CorrectionRepository>(
  (ref) => CorrectionRepository(ref.watch(supabaseClientProvider)),
);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth?.session == null) return null;
  return ref.watch(authRepositoryProvider).fetchCurrentProfile();
});
