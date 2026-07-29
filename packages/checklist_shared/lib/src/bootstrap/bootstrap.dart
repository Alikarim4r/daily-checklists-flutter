import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

Future<void> bootstrapSupabase({
  SupabaseConfig config = SupabaseConfig.fromEnvironment,
}) async {
  config.validate();
  await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
}

SupabaseClient get supabase => Supabase.instance.client;
