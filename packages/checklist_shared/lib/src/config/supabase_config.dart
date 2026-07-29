/// Runtime Supabase configuration via `--dart-define`.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  static const SupabaseConfig fromEnvironment = SupabaseConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  void validate() {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Pass SUPABASE_URL and SUPABASE_ANON_KEY '
        'via --dart-define.',
      );
    }
  }
}
