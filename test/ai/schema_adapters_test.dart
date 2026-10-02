import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/providers/schema_adapters.dart';
import 'package:quiz_app/data/models/models.dart';

Map<String, Object?> _questionItems(Map<String, Object?> schema) =>
    ((schema['properties']! as Map)['questions']! as Map)['items']!
        as Map<String, Object?>;

void main() {
  test('OpenAI strict: no \$schema/title, all objects closed and required', () {
    final s = toOpenAiStrictSchema(quizDraftJsonSchema);
    expect(s.containsKey(r'$schema'), isFalse);
    expect(s.containsKey('title'), isFalse);
    expect(s['additionalProperties'], false);
    expect(s['required'], ['title', 'description', 'questions']);
    final items = _questionItems(s);
    expect(items['additionalProperties'], false);
    expect(
      (items['required']! as List).toSet(),
      (items['properties']! as Map).keys.toSet(),
    );
    // the contract constant is untouched
    expect(quizDraftJsonSchema.containsKey(r'$schema'), isTrue);
  });

  test('OpenAI strict makes non-required properties nullable', () {
    final s = toOpenAiStrictSchema({
      'type': 'object',
      'properties': {
        'a': {'type': 'string'},
        'b': {'type': 'integer'},
      },
      'required': ['a'],
    });
    expect(s['required'], ['a', 'b']);
    expect(((s['properties']! as Map)['b']! as Map)['type'], [
      'integer',
      'null',
    ]);
    expect(((s['properties']! as Map)['a']! as Map)['type'], 'string');
  });

  test('Anthropic drops unsupported constraints into descriptions', () {
    final s = toAnthropicSchema(quizDraftJsonSchema);
    expect(s.containsKey(r'$schema'), isFalse);
    expect(s.containsKey('title'), isFalse);
    final items = _questionItems(s);
    final indices =
        ((items['properties']! as Map)['correct_indices']! as Map)['items']!
            as Map;
    expect(indices.containsKey('minimum'), isFalse);
    expect(indices['description'], contains('minimum: 0'));
    // minItems 1 is supported and kept
    expect(((s['properties']! as Map)['questions']! as Map)['minItems'], 1);
    expect(items['additionalProperties'], false);
  });

  test('Gemini keeps supported keywords, drops \$schema', () {
    final s = toGeminiSchema(quizDraftJsonSchema);
    expect(s.containsKey(r'$schema'), isFalse);
    expect(s['title'], 'QuizDraft');
    final items = _questionItems(s);
    expect((items['properties']! as Map).keys, contains('correct_indices'));
    expect(((items['properties']! as Map)['type']! as Map)['enum'], [
      'mcq_single',
      'mcq_multi',
      'true_false',
      'short_answer',
    ]);
  });

  test('property names are never treated as keywords', () {
    final s = toGeminiSchema({
      'type': 'object',
      'properties': {
        'pattern': {'type': 'string'},
      },
    });
    expect((s['properties']! as Map).containsKey('pattern'), isTrue);
  });
}
