import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_capabilities.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/attachment_repository.dart';
import 'package:quiz_app/features/ai_generate/data/ai_file_picker.dart';

import '../quizzes/support/fakes.dart';
import 'support/ai_fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Note _note(
  String id,
  String title, {
  String subjectId = 's1',
  String owner = userId,
  String content = 'Mitochondria are the powerhouse of the cell.',
}) => Note(
  id: id,
  subjectId: subjectId,
  ownerId: owner,
  title: title,
  contentMd: content,
  createdAt: fixedNow,
  updatedAt: fixedNow,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _pdfOnly =
    "This model can't read PDFs — switch to Gemini/OpenAI/Claude in Settings.";

void main() {
  testWidgets('not configured: only a set-up state linking to Settings', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()..subjects.add(subject('s1', 'Astronomy'));
    env.ai.selection = null;
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-not-ready')), findsOneWidget);
    expect(find.text('Set up AI to generate'), findsOneWidget);
    expect(find.byKey(const Key('ai-context')), findsNothing);
    expect(find.byKey(const Key('ai-add-files')), findsNothing);
    expect(find.byKey(const Key('ai-generate')), findsNothing);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings page'), findsOneWidget);
  });

  testWidgets('quiz: text + YouTube -> progress -> edit preview -> save', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Astronomy'))
      ..capabilities = const AiCapabilities(youtube: true);
    final pending = Completer<QuizDraft>();
    env.ai.onQuiz = (_) => pending.future;
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI · gpt-test'), findsOneWidget);
    expect(find.byKey(const Key('ai-change-provider')), findsOneWidget);
    expect(find.text('Astronomy'), findsWidgets);

    // Validation: needs some source material.
    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(
      find.text(
        'Add some text, a note, a file or a YouTube link to generate from.',
      ),
      findsOneWidget,
    );
    expect(env.ai.quizRequests, isEmpty);

    await tester.enterText(
      find.byKey(const Key('ai-context')),
      'The solar system has eight planets.',
    );
    await tester.enterText(find.byKey(const Key('ai-youtube')), 'not a link');
    await tester.pump();
    expect(
      find.text("That doesn't look like a YouTube video link."),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('ai-youtube')),
      'https://youtu.be/dQw4w9WgXcQ',
    );
    await tester.pump();
    expect(find.text('2 sources'), findsOneWidget);
    await _tap(tester, find.text('Short answer'));
    await tester.ensureVisible(find.byKey(const Key('ai-generate')));
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pump();

    expect(find.text('Generating your quiz…'), findsOneWidget);
    final request = env.ai.quizRequests.single;
    expect(request.sources, const [
      TextSource(text: 'The solar system has eight planets.'),
      YoutubeSource('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
    ]);
    expect(request.questionTypes, isNot(contains(QuestionType.shortAnswer)));
    expect(request.topic, 'Astronomy');
    expect(request.providerId, LlmProviderId.openai);
    expect(request.model, 'gpt-test');

    pending.complete(sampleDraft);
    await tester.pumpAndSettle();
    expect(find.text('Review quiz'), findsOneWidget);
    expect(find.text('Largest planet?'), findsOneWidget);
    expect(find.text('Pluto is a planet.'), findsOneWidget);

    // Edit: rename, delete the second question.
    await tester.enterText(find.byKey(const Key('draft-title')), 'My planets');
    await tester.tap(find.byTooltip('More actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Pluto is a planet.'), findsNothing);

    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();

    final saved = env.quizzes.all.single;
    expect(saved.title, 'My planets');
    expect(saved.subjectId, 's1');
    expect(saved.noteId, isNull);
    expect(saved.questions.map((q) => q.prompt), ['Largest planet?']);
    expect(saved.source!.provider, 'openai');
    expect(saved.source!.model, 'gpt-test');
    expect(saved.source!.contextText, 'The solar system has eight planets.');
    expect(
      saved.source!.youtubeUrl,
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    expect(saved.source!.notes, isEmpty);
    expect(saved.source!.attachments, isEmpty);
    // Navigated to the new quiz.
    expect(find.byKey(const Key('play-quiz')), findsOneWidget);
  });

  testWidgets('YouTube field hidden when the model cannot use videos', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()..subjects.add(subject('s1', 'Astronomy'));
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-youtube')), findsNothing);
    expect(find.byKey(const Key('ai-youtube-unavailable')), findsOneWidget);
  });

  testWidgets('quiz: cancel returns to the form and ignores the result', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()..subjects.add(subject('s1', 'Astronomy'));
    final pending = Completer<QuizDraft>();
    env.ai.onQuiz = (_) => pending.future;
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-context')), 'text');
    await tester.ensureVisible(find.byKey(const Key('ai-generate')));
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-cancel')));
    await tester.pump();
    pending.complete(sampleDraft);
    await tester.pumpAndSettle();
    expect(find.text('Generate quiz with AI'), findsOneWidget);
    expect(find.text('Largest planet?'), findsNothing);
  });

  testWidgets('quiz for a note: note preselected, regenerate, save refs', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..notes.add(_note('n1', 'Cells'));
    var call = 0;
    env.ai.onQuiz = (r) async {
      call++;
      if (call == 1) return sampleDraft;
      return const QuizDraft(
        title: 'x',
        questions: [
          QuestionDraft(
            type: QuestionType.mcqSingle,
            prompt: 'Smallest planet?',
            options: ['Mercury', 'Earth'],
            correctIndices: [0],
          ),
        ],
      );
    };
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&noteId=n1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-chip-n1')), findsOneWidget);
    expect(find.text('Quiz for the note "Cells"'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('ai-generate')));
    final first = env.ai.quizRequests.first;
    expect(first.topic, 'Cells');
    expect(first.sources, const [
      NoteSource(
        title: 'Cells',
        markdown: 'Mitochondria are the powerhouse of the cell.',
      ),
    ]);

    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Regenerate'));
    await tester.pumpAndSettle();
    final regen = env.ai.quizRequests.last;
    expect(regen.questionCount, 1);
    expect(regen.questionTypes, {QuestionType.mcqSingle});
    expect(regen.sources, first.sources);
    expect(regen.extraInstructions, contains('Largest planet?'));
    expect(find.text('Smallest planet?'), findsOneWidget);
    expect(find.text('Largest planet?'), findsNothing);

    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final saved = env.quizzes.all.single;
    expect(saved.noteId, 'n1');
    expect(saved.subjectId, 's1');
    expect(saved.questions.first.prompt, 'Smallest planet?');
    expect(saved.source!.notes, const [QuizSourceRef(id: 'n1', name: 'Cells')]);
    expect(saved.source!.contextText, isNull);
  });

  testWidgets('note picker: search, multi-select, shared badge, remove chip', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..subjects.add(
        Subject(
          id: 's9',
          ownerId: 'u2',
          title: 'Chemistry',
          createdAt: fixedNow,
          updatedAt: fixedNow,
        ),
      )
      ..notes.add(_note('n1', 'Cells'))
      ..notes.add(_note('n2', 'Photosynthesis', content: 'Plants use light.'))
      ..notes.add(
        _note(
          'n3',
          'Acids and bases',
          subjectId: 's9',
          owner: 'u2',
          content: '## pH scale\n\nAcids have a **low** pH.',
        ),
      );
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const Key('ai-add-notes')));
    expect(find.byKey(const ValueKey('note-option-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-option-n2')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-option-n3')), findsOneWidget);
    // Shared note: badge, its subject's name and a plain-text snippet.
    expect(find.text('Shared'), findsOneWidget);
    expect(
      find.text('Chemistry · pH scale Acids have a low pH.'),
      findsOneWidget,
    );
    expect(
      find.text('Biology · Mitochondria are the powerhouse of the cell.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('note-picker-search')),
      'acids',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-option-n1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-option-n3')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('note-picker-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-option-n2')));
    await tester.pumpAndSettle();
    expect(find.text('Use 2 notes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-picker-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-chip-n3')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-chip-n2')), findsOneWidget);

    // Remove one chip.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('note-chip-n2')),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-chip-n2')), findsNothing);

    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(env.ai.quizRequests.single.sources, const [
      NoteSource(
        title: 'Acids and bases',
        markdown: '## pH scale\n\nAcids have a **low** pH.',
      ),
    ]);
  });

  testWidgets('files: kinds gated by capabilities', (tester) async {
    _tall(tester);
    final env = AiTestEnv()..subjects.add(subject('s1', 'Biology'));
    env.attachments
      ..put('a1', 's1', 'lecture.pdf')
      ..put('a2', 's1', 'summary.txt', extractedText: 'Summary text')
      ..put('a3', 's1', 'talk.mp3');
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Text and Word files from the subject library, or upload new '
        'ones.',
      ),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(const Key('ai-add-files')));
    expect(find.text(_pdfOnly), findsOneWidget);
    expect(
      find.text(
        "This model can't listen to audio — switch to Gemini in Settings.",
      ),
      findsOneWidget,
    );
    // Disabled rows can't be selected.
    await tester.tap(find.byKey(const ValueKey('attachment-option-a1')));
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('attachment-option-a2')));
    await tester.pump();
    expect(find.text('Use 1 file'), findsOneWidget);

    // Upload offers only text kinds for this model.
    await tester.tap(find.byKey(const Key('attachment-upload')));
    await tester.pumpAndSettle();
    expect(env.picker.requests.single, ['txt', 'md', 'docx']);

    await tester.tap(find.byKey(const Key('attachment-picker-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file-chip-a2')), findsOneWidget);
  });

  testWidgets('files: PDF-capable model can pick PDFs, audio still gated', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..capabilities = const AiCapabilities(pdf: true, image: true);
    env.attachments
      ..put('a1', 's1', 'lecture.pdf')
      ..put('a3', 's1', 'talk.mp3');
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const Key('ai-add-files')));
    expect(find.text(_pdfOnly), findsNothing);
    expect(
      find.text(
        "This model can't listen to audio — switch to Gemini in Settings.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('attachment-option-a1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('attachment-upload')));
    await tester.pumpAndSettle();
    expect(env.picker.requests.single, [
      'txt',
      'md',
      'docx',
      'pdf',
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
    ]);
    await tester.tap(find.byKey(const Key('attachment-picker-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file-chip-a1')), findsOneWidget);
  });

  testWidgets('files: needs a subject before adding files', (tester) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..subjects.add(subject('s2', 'History'));
    env.attachments.put('a1', 's2', 'war.txt', extractedText: 'War text');
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-files-need-subject')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('ai-add-files')))
          .onPressed,
      isNull,
    );

    await _tap(tester, find.byKey(const Key('ai-subject')));
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-files-need-subject')), findsNothing);
    await _tap(tester, find.byKey(const Key('ai-add-files')));
    expect(find.text('war.txt'), findsOneWidget);
  });

  testWidgets('upload new: saved to the library, selected, sent as text', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()..subjects.add(subject('s1', 'Biology'));
    env.attachments.uploadPhase = AttachmentUploadPhase.queued;
    env.picker.next = [
      PickedFile(
        name: 'notes.md',
        bytes: Uint8List.fromList(utf8.encode('# Hello\n\nWorld')),
      ),
    ];
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const Key('ai-add-files')));
    expect(find.text('No files yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('attachment-upload')));
    await tester.pumpAndSettle();

    final added = env.attachments.added.single;
    expect(added.subjectId, 's1');
    expect(added.name, 'notes.md');
    expect(added.extractedText, '# Hello\n\nWorld');
    expect(find.text('Use 1 file'), findsOneWidget);
    expect(find.text('Waiting to upload'), findsOneWidget);

    await tester.tap(find.byKey(const Key('attachment-picker-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('file-chip-${added.id}')), findsOneWidget);
    expect(find.text('Waiting to upload'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(env.ai.quizRequests.single.sources, const [
      TextSource(label: 'notes.md', text: '# Hello\n\nWorld'),
    ]);
    // Text files never need their bytes.
    expect(env.attachments.bytesRequested, isEmpty);
  });

  testWidgets('sources -> request mapping and saved provenance', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..notes.add(_note('n1', 'Cells'))
      ..capabilities = const AiCapabilities(pdf: true, youtube: true);
    final pdf = env.attachments.put('a1', 's1', 'lecture.pdf', size: 2048);
    env.attachments.put('a2', 's1', 'summary.docx', extractedText: 'Docx');
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-context')), 'Typed');
    await _tap(tester, find.byKey(const Key('ai-add-notes')));
    await tester.tap(find.byKey(const ValueKey('note-option-n1')));
    await tester.tap(find.byKey(const Key('note-picker-done')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('ai-add-files')));
    await tester.tap(find.byKey(const ValueKey('attachment-option-a1')));
    await tester.tap(find.byKey(const ValueKey('attachment-option-a2')));
    await tester.tap(find.byKey(const Key('attachment-picker-done')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-youtube')),
      'https://youtu.be/dQw4w9WgXcQ',
    );
    await tester.pump();
    expect(
      find.text('5 sources · 2 KB of files (max 50 MB per request)'),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(const Key('ai-generate')));
    final sources = env.ai.quizRequests.single.sources;
    expect(sources, [
      const TextSource(text: 'Typed'),
      const NoteSource(
        title: 'Cells',
        markdown: 'Mitochondria are the powerhouse of the cell.',
      ),
      FileSource(
        name: 'lecture.pdf',
        mimeType: 'application/pdf',
        bytes: env.attachments.bytes['a1']!,
      ),
      const TextSource(label: 'summary.docx', text: 'Docx'),
      const YoutubeSource('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
    ]);
    expect(env.attachments.bytesRequested, [pdf.id]);

    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final source = env.quizzes.all.single.source!;
    expect(source.contextText, 'Typed');
    expect(source.youtubeUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(source.notes, const [QuizSourceRef(id: 'n1', name: 'Cells')]);
    expect(source.attachments, const [
      QuizSourceRef(id: 'a1', name: 'lecture.pdf'),
      QuizSourceRef(id: 'a2', name: 'summary.docx'),
    ]);
  });

  testWidgets('files over the request limit block generation', (tester) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..capabilities = const AiCapabilities(pdf: true);
    env.ai.selection = const AiSelection(
      providerId: LlmProviderId.anthropic,
      model: 'claude-test',
    );
    env.attachments.put('a1', 's1', 'big.pdf', size: 30 * 1024 * 1024);
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('ai-add-files')));
    await tester.tap(find.byKey(const ValueKey('attachment-option-a1')));
    await tester.tap(find.byKey(const Key('attachment-picker-done')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(
      find.text(
        'The files total 30 MB; Anthropic accepts up to 24 MB per request. '
        'Remove some files.',
      ),
      findsOneWidget,
    );
    expect(env.ai.quizRequests, isEmpty);
  });

  testWidgets('note: subject required, style options, save -> editor', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..subjects.add(subject('s2', 'History'));
    env.ai.onNote = (_) async => const NoteDraft(
      title: 'Cell notes',
      contentMarkdown: '# Cells\n\nThey are small.',
    );
    await tester.pumpWidget(env.app('/ai/generate?kind=note'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-context')), 'Cells...');
    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(find.text('Choose where to save the result.'), findsOneWidget);
    expect(env.ai.noteRequests, isEmpty);

    await _tap(tester, find.byKey(const Key('ai-subject')));
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Outline'));
    await _tap(tester, find.text('Short'));
    await _tap(tester, find.byKey(const Key('ai-generate')));

    final request = env.ai.noteRequests.single;
    expect(request.sources, const [TextSource(text: 'Cells...')]);
    expect(request.topic, 'History');
    expect(request.extraInstructions, contains('structured outline'));
    expect(request.extraInstructions, contains('Keep it short'));

    expect(find.text('Review note'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('They are small.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final note = env.notes.created.single;
    expect(note.subjectId, 's2');
    expect(note.title, 'Cell notes');
    expect(note.contentMd, '# Cells\n\nThey are small.');
    expect(find.text('Note editor ${note.id}'), findsOneWidget);
  });

  testWidgets('errors are mapped to friendly messages with actions', (
    tester,
  ) async {
    _tall(tester);
    final env = AiTestEnv()..subjects.add(subject('s1', 'Astronomy'));
    env.ai.onQuiz = (_) async => throw const AiException(
      'Invalid API key (401).',
      kind: AiErrorKind.invalidApiKey,
    );
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-context')), 'text');
    await _tap(tester, find.byKey(const Key('ai-generate')));

    expect(find.text('The API key was rejected'), findsOneWidget);
    expect(find.textContaining('Invalid API key (401).'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Open settings'), findsOneWidget);

    // Rate limits offer retry.
    env.ai.onQuiz = (_) async => throw const AiException(
      'Too many requests',
      kind: AiErrorKind.rateLimited,
    );
    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(find.text('Rate limit or quota reached'), findsOneWidget);
    env.ai.onQuiz = null; // next call succeeds
    await _tap(tester, find.text('Try again'));
    expect(find.text('Review quiz'), findsOneWidget);
  });

  testWidgets('wide: two columns; phone: single column + bottom sheets', (
    tester,
  ) async {
    final env = AiTestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..notes.add(_note('n1', 'Cells'));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    final sources = tester.getTopLeft(find.text('Sources'));
    final options = tester.getTopLeft(find.text('Options'));
    expect(options.dx, greaterThan(sources.dx + 300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(env.app('/ai/generate?kind=note&subjectId=s1'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Options')).dy,
      greaterThan(tester.getTopLeft(find.text('Sources')).dy),
    );
    await _tap(tester, find.byKey(const Key('ai-add-notes')));
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-option-n1')));
    await tester.tap(find.byKey(const Key('note-picker-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-chip-n1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
