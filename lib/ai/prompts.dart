import '../data/models/question.dart';
import 'ai_service.dart';
import 'transcript_service.dart';

/// A system + user prompt pair.
class PromptPair {
  const PromptPair({required this.system, required this.user});
  final String system;
  final String user;
}

/// Source material handed to a prompt builder. At least one of
/// [contextText], [transcript] or [nativeVideo] is set.
class PromptSource {
  const PromptSource({
    this.contextText,
    this.transcript,
    this.nativeVideo = false,
  });

  final String? contextText;
  final VideoTranscript? transcript;

  /// True when the video itself is attached to the request (Gemini).
  final bool nativeVideo;
}

/// Prompt templates for quiz and note generation.
abstract final class Prompts {
  static const quizSchemaName = 'QuizDraft';
  static const noteSchemaName = 'NoteDraft';

  static const _typeDescriptions = {
    QuestionType.mcqSingle:
        'mcq_single: multiple choice with 3-5 options and exactly ONE correct '
        'option. correct_indices has one zero-based index. answer_text null.',
    QuestionType.mcqMulti:
        'mcq_multi: multiple choice with 4-6 options and one or more correct '
        'options; the prompt says "Select all that apply". correct_indices '
        'lists every correct zero-based index. answer_text null.',
    QuestionType.trueFalse:
        'true_false: a statement to judge. options is exactly ["True", '
        '"False"]; correct_indices is [0] for True or [1] for False. '
        'answer_text null.',
    QuestionType.shortAnswer:
        'short_answer: a flashcard-style question answered in a word, phrase '
        'or 1-2 sentences. options and correct_indices are empty arrays; '
        'answer_text holds the expected answer.',
  };

  static String _difficulty(Difficulty d) => switch (d) {
    Difficulty.easy =>
      'easy: recall of key facts and definitions stated directly in the '
          'source.',
    Difficulty.medium =>
      'medium: mix of recall and understanding; some questions require '
          'connecting two ideas from the source.',
    Difficulty.hard =>
      'hard: application, analysis and subtle distinctions; distractors '
          'reflect common misconceptions.',
  };

  static String _language(String? language) =>
      (language == null || language.trim().isEmpty)
      ? 'Write everything in the same language as the source material.'
      : 'Write everything (title, questions, options, answers, explanations) '
            'in this language: ${language.trim()}.';

  static String quizSystem() => '''
You are an expert teacher who writes accurate, high-quality quiz questions from study material.

Rules:
- Output ONLY a JSON object that matches the provided schema exactly: keys "title", "description", "questions"; each question has "type", "prompt", "options", "correct_indices", "answer_text", "explanation". No Markdown, no extra keys, no commentary.
- Base every question strictly on the provided source material. Do not invent facts that the source does not support.
- Every answer must be unambiguously correct according to the source. Double-check correct_indices against the options (indices are zero-based).
- Distractors (wrong options) must be plausible, similar in length and style to the correct option, and clearly wrong to someone who understands the material. Avoid "All of the above" / "None of the above" and joke options.
- Each question tests a different idea; no duplicates or near-duplicates. Spread questions across the whole source.
- Prompts are self-contained and clear; do not reference "the text" or "the video" unless necessary.
- "explanation" briefly (1-2 sentences) says why the answer is correct, citing the relevant idea from the source.''';

  static String quizUser(QuizGenerationRequest request, PromptSource source) {
    final types = request.questionTypes.isEmpty
        ? QuestionType.values.toSet()
        : request.questionTypes;
    final b = StringBuffer()
      ..writeln(
        'Create a quiz with exactly ${request.questionCount} questions.',
      );
    if (request.topic != null && request.topic!.trim().isNotEmpty) {
      b.writeln('Topic (subject / note title): ${request.topic!.trim()}');
    }
    b
      ..writeln()
      ..writeln(
        'Allowed question types (use only these; mix them when more '
        'than one is allowed):',
      );
    for (final t in QuestionType.values.where(types.contains)) {
      b.writeln('- ${_typeDescriptions[t]}');
    }
    b
      ..writeln()
      ..writeln('Difficulty: ${_difficulty(request.difficulty)}')
      ..writeln(_language(request.language))
      ..writeln(
        'Give the quiz a short, specific "title" and a one-sentence '
        '"description".',
      );
    _extra(b, request.extraInstructions);
    _source(b, source);
    return b.toString().trimRight();
  }

  static String noteSystem() => '''
You are an expert note-taker who turns study material into clear, well-structured study notes.

Rules:
- Output ONLY a JSON object that matches the provided schema exactly: keys "title" and "content_markdown". No extra keys, no commentary outside the JSON.
- "content_markdown" is GitHub-flavored Markdown: start with a 1-2 sentence overview, then use "##" / "###" headings for the main sections, concise bullet points for details, **bold** for key terms on first use, and finish with a "## Key terms" section (term: short definition) and a "## Summary" of 3-5 bullets.
- Use tables or numbered steps only where they genuinely help (comparisons, processes).
- Be faithful to the source: no invented facts; keep important numbers, names and definitions exact.
- Do not include images, HTML, or a top-level "#" heading (the title is separate).''';

  static String noteUser(NoteGenerationRequest request, PromptSource source) {
    final b = StringBuffer()
      ..writeln('Write study notes for the material below.');
    if (request.topic != null && request.topic!.trim().isNotEmpty) {
      b.writeln('Topic (subject title): ${request.topic!.trim()}');
    }
    b.writeln(_language(request.language));
    _extra(b, request.extraInstructions);
    _source(b, source);
    return b.toString().trimRight();
  }

  static void _extra(StringBuffer b, String? extra) {
    if (extra == null || extra.trim().isEmpty) return;
    b
      ..writeln()
      ..writeln(
        'Additional instructions from the user (follow them unless '
        'they conflict with the rules or schema):',
      )
      ..writeln(extra.trim());
  }

  static void _source(StringBuffer b, PromptSource source) {
    b.writeln();
    if (source.nativeVideo) {
      b.writeln(
        'Source: the attached YouTube video (use both what is said and what '
        'is shown).',
      );
    }
    final transcript = source.transcript;
    if (transcript != null) {
      final title = transcript.title;
      b
        ..writeln(
          'Source: transcript of the YouTube video'
          '${title == null ? '' : ' "$title"'}'
          '${transcript.isAutoGenerated ? ' (auto-generated captions; '
                    'fix obvious transcription errors)' : ''}:',
        )
        ..writeln('<transcript>')
        ..writeln(transcript.text)
        ..writeln('</transcript>');
    }
    final context = source.contextText;
    if (context != null && context.trim().isNotEmpty) {
      b
        ..writeln(
          (source.nativeVideo || transcript != null)
              ? 'Additional source material provided by the user:'
              : 'Source material:',
        )
        ..writeln('<source>')
        ..writeln(context.trim())
        ..writeln('</source>');
    }
  }

  /// Follow-up prompt asking the model to fix its previous output.
  static String repair({
    required String originalPrompt,
    required String previousOutput,
    required List<String> problems,
  }) {
    final shown = previousOutput.length > 20000
        ? '${previousOutput.substring(0, 20000)}…'
        : previousOutput;
    return '''
$originalPrompt

---
Your previous answer was rejected by the validator.

Previous answer:
<previous>
$shown
</previous>

Problems found:
${problems.map((p) => '- $p').join('\n')}

Return a corrected, complete JSON object that fixes every problem and follows all the rules and the schema. Output only the JSON object.''';
  }
}
