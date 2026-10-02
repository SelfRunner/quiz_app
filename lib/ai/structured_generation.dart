import 'dart:convert';

import '../core/errors/app_exception.dart';
import 'draft_validator.dart';
import 'llm_provider.dart';
import 'prompts.dart';
import 'providers/http_support.dart';

/// Calls [provider] for a JSON object matching [schema], validates it and on
/// invalid JSON / validation errors sends ONE repair request containing the
/// previous output and the problems. The second attempt is accepted if it
/// yields any usable value ([DraftValidation.value] non-null).
///
/// Throws `AiException(invalidOutput)` when both attempts fail (or the
/// output was cut off), and passes provider errors through.
Future<T> generateValidatedJson<T>({
  required LlmProvider provider,
  required String system,
  required String user,
  required Map<String, Object?> schema,
  required String schemaName,
  required List<LlmAttachment> attachments,
  required String what,
  required DraftValidation<T> Function(Map<String, dynamic> json) validate,
}) async {
  Future<Map<String, dynamic>> call(String prompt) => provider.generateJson(
    prompt: prompt,
    schema: schema,
    schemaName: schemaName,
    systemPrompt: system,
    attachments: attachments,
  );

  String previous;
  List<String> problems;
  try {
    final json = await call(user);
    final result = validate(json);
    if (result.isValid) return result.value as T;
    previous = jsonEncode(json);
    problems = result.errors;
  } on AiException catch (e) {
    final raw = e.cause;
    if (e.kind != AiErrorKind.invalidOutput ||
        (raw is RawModelOutput && raw.truncated)) {
      rethrow;
    }
    previous = raw is RawModelOutput ? raw.text : '';
    problems = const [
      'The answer was not a single valid JSON object matching the schema.',
    ];
  }

  final repairPrompt = Prompts.repair(
    originalPrompt: user,
    previousOutput: previous,
    problems: problems,
  );
  try {
    final json = await call(repairPrompt);
    final result = validate(json);
    final value = result.value;
    if (value != null) return value;
    throw AiException(
      'The AI returned an unusable $what twice. Try again, add more source '
      'material, or pick a different model.',
      kind: AiErrorKind.invalidOutput,
      cause: result.errors.join('\n'),
    );
  } on AiException catch (e) {
    if (e.kind != AiErrorKind.invalidOutput) rethrow;
    final raw = e.cause;
    if (raw is RawModelOutput && raw.truncated) rethrow;
    if (e.cause is String) rethrow; // our own message above
    throw AiException(
      'The AI returned an unusable $what twice. Try again or pick a '
      'different model.',
      kind: AiErrorKind.invalidOutput,
      cause: e,
    );
  }
}
