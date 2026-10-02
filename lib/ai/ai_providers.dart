import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_service.dart';
import 'api_key_store.dart';
import 'llm_provider.dart';
import 'transcript_service.dart';

// The AI agent replaces the `throw` bodies with real implementations.

Never _unimplemented(String name) =>
    throw UnimplementedError('$name is not implemented yet (AI layer).');

final apiKeyStoreProvider = Provider<ApiKeyStore>(
  (ref) => _unimplemented('ApiKeyStore'),
);

final llmProviderFactoryProvider = Provider<LlmProviderFactory>(
  (ref) => _unimplemented('LlmProviderFactory'),
);

final transcriptServiceProvider = Provider<TranscriptService>(
  (ref) => _unimplemented('TranscriptService'),
);

final aiServiceProvider = Provider<AiService>(
  (ref) => _unimplemented('AiService'),
);
