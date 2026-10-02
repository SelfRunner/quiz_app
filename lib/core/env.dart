/// Compile-time configuration.
///
/// Supply values with `--dart-define-from-file=env.json` (see
/// `env.example.json`) or individual `--dart-define=KEY=value` flags.
abstract final class Env {
  /// Supabase project URL, e.g. `https://abc.supabase.co`.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon (legacy) or publishable key. Safe to ship in the client;
  /// all data access is protected by RLS.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// True when both Supabase values were provided at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
