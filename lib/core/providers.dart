import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'utils/clock.dart';

/// The initialized Supabase client. Only valid when `Env.isConfigured`
/// (bootstrap calls `Supabase.initialize`). Override in tests.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Clock returning UTC now. Override in tests for deterministic timestamps.
final clockProvider = Provider<Clock>((ref) => systemClock);

/// Client-side UUID generator. Override in tests for deterministic ids.
final idGeneratorProvider = Provider<IdGenerator>((ref) => uuidV4);
