import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import '../data/local/hive_boxes.dart';
import 'env.dart';

/// App startup: bindings, Hive (adapters + boxes), Supabase, ProviderScope.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await HiveBoxes.init();

  if (!Env.isConfigured) {
    runApp(const ConfigMissingApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: QuizApp()));
}
