/// Converts the shared draft JSON Schemas (`quizDraftJsonSchema`,
/// `noteDraftJsonSchema`) into the dialect each provider's structured-output
/// mode accepts. The contract schemas stay unchanged; validation of the
/// result always happens locally (`draft_validator.dart`), so dropping a
/// constraint here never weakens correctness.
library;

typedef JsonSchema = Map<String, Object?>;

/// OpenAI strict mode (Responses `text.format` / Chat Completions
/// `response_format` with `strict: true`):
/// * every object has `additionalProperties: false`;
/// * every property is listed in `required` (optional ones become nullable);
/// * `$schema` / root `title` are dropped (not part of the subset).
JsonSchema toOpenAiStrictSchema(JsonSchema schema) {
  final out = _deepCopy(schema)
    ..remove(r'$schema')
    ..remove('title');
  _walk(out, (node) {
    if (_isObject(node)) {
      node['additionalProperties'] = false;
      final props = (node['properties'] as Map?)?.cast<String, Object?>();
      if (props != null) {
        final required = {...?(node['required'] as List?)?.cast<String>()};
        for (final entry in props.entries) {
          if (!required.contains(entry.key) && entry.value is Map) {
            _makeNullable(entry.value! as Map<String, Object?>);
          }
        }
        node['required'] = props.keys.toList();
      }
    }
  });
  return out;
}

/// Anthropic structured outputs (`output_config.format`) and tool
/// `input_schema`: no `$schema`/`title`, no numeric or string-length
/// constraints, `minItems` only 0 or 1, `additionalProperties: false` on
/// every object. Removed constraints are appended to `description`.
JsonSchema toAnthropicSchema(JsonSchema schema) {
  final out = _deepCopy(schema)
    ..remove(r'$schema')
    ..remove('title');
  _walk(out, (node) {
    node.remove('title');
    final notes = <String>[];
    for (final k in const [
      'minimum',
      'maximum',
      'exclusiveMinimum',
      'exclusiveMaximum',
      'multipleOf',
      'minLength',
      'maxLength',
      'pattern',
    ]) {
      if (node.containsKey(k)) notes.add('$k: ${node.remove(k)}');
    }
    final minItems = node['minItems'];
    if (minItems is int && minItems > 1) {
      notes.add('minItems: ${node.remove('minItems')}');
    }
    if (node.containsKey('maxItems')) {
      notes.add('maxItems: ${node.remove('maxItems')}');
    }
    if (notes.isNotEmpty) {
      final d = node['description'];
      node['description'] = [
        if (d is String && d.isNotEmpty) d,
        '(${notes.join(', ')})',
      ].join(' ');
    }
    if (_isObject(node)) node['additionalProperties'] = false;
  });
  return out;
}

/// Gemini `generationConfig.responseFormat.text.schema` (and the legacy
/// `responseJsonSchema`): a JSON Schema subset supporting `type`, `format`,
/// `title`, `description`, `enum`, `items`, `minItems`, `maxItems`,
/// `minimum`, `maximum`, `anyOf`, `properties`, `additionalProperties`,
/// `required`. Drops `$schema` and anything outside that list.
JsonSchema toGeminiSchema(JsonSchema schema) {
  final out = _deepCopy(schema)..remove(r'$schema');
  _walk(out, (node) {
    node.removeWhere((k, _) => !_geminiKeywords.contains(k));
  });
  return out;
}

const _geminiKeywords = {
  r'$id',
  r'$defs',
  r'$ref',
  r'$anchor',
  'type',
  'format',
  'title',
  'description',
  'enum',
  'items',
  'prefixItems',
  'minItems',
  'maxItems',
  'minimum',
  'maximum',
  'anyOf',
  'oneOf',
  'properties',
  'additionalProperties',
  'required',
  'propertyOrdering',
};

bool _isObject(Map<String, Object?> node) {
  final t = node['type'];
  return t == 'object' || (t is List && t.contains('object'));
}

void _makeNullable(Map<String, Object?> node) {
  final t = node['type'];
  if (t is String && t != 'null') {
    node['type'] = [t, 'null'];
  } else if (t is List && !t.contains('null')) {
    node['type'] = [...t, 'null'];
  }
}

/// Visits every schema node (the root, property schemas, `items`, `anyOf`
/// members, `$defs`). Property *names* are never visited as nodes.
void _walk(
  Map<String, Object?> node,
  void Function(Map<String, Object?> node) visit,
) {
  visit(node);
  final props = node['properties'];
  if (props is Map) {
    for (final v in props.values) {
      if (v is Map<String, Object?>) _walk(v, visit);
    }
  }
  for (final key in const ['items', 'additionalProperties']) {
    final v = node[key];
    if (v is Map<String, Object?>) _walk(v, visit);
  }
  for (final key in const ['anyOf', 'oneOf', 'allOf', 'prefixItems']) {
    final v = node[key];
    if (v is List) {
      for (final item in v) {
        if (item is Map<String, Object?>) _walk(item, visit);
      }
    }
  }
  final defs = node[r'$defs'];
  if (defs is Map) {
    for (final v in defs.values) {
      if (v is Map<String, Object?>) _walk(v, visit);
    }
  }
}

Map<String, Object?> _deepCopy(Map<String, Object?> source) => {
  for (final e in source.entries) e.key: _copyValue(e.value),
};

Object? _copyValue(Object? v) {
  if (v is Map) {
    return <String, Object?>{
      for (final e in v.entries) e.key.toString(): _copyValue(e.value),
    };
  }
  if (v is List) return [for (final x in v) _copyValue(x)];
  return v;
}
