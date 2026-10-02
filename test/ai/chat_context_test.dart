import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_chat_service.dart';
import 'package:quiz_app/ai/chat_context.dart';
import 'package:quiz_app/ai/llm_chat.dart';

const _sources = [
  ChatSourceRef(number: 1, type: AiSourceType.note, id: 'n1', title: 'Cells'),
  ChatSourceRef(
    number: 2,
    type: AiSourceType.file,
    id: 'a1',
    title: 'lecture.pdf',
  ),
  ChatSourceRef(
    number: 3,
    type: AiSourceType.file,
    id: 'a2',
    title: 'talk.mp3',
    status: ChatSourceStatus.unreadable,
    note: "can't read audio",
  ),
  ChatSourceRef(
    number: 4,
    type: AiSourceType.text,
    title: 'Pasted text',
    status: ChatSourceStatus.excerpt,
  ),
];

void main() {
  group('ChatCitations', () {
    test('parses single, grouped, adjacent and range markers in order', () {
      const text =
          'ATP [S2]. Membranes [S1, S4][s2]. Range [S1-S2]; '
          'loose [S 4] and [S2–4].';
      expect(ChatCitations.numbersIn(text), [2, 1, 4, 3]);
      final cites = ChatCitations.parse(text, _sources);
      expect(cites.map((c) => c.marker), ['S2', 'S1', 'S4']);
      expect(
        cites.first,
        const ChatCitation(
          number: 2,
          type: AiSourceType.file,
          id: 'a1',
          title: 'lecture.pdf',
        ),
      );
    });

    test('ignores unknown numbers, unreadable sources and look-alikes', () {
      const text = 'See [S3] and [S9]; array[1], [Source 1], [S1a], S1.';
      expect(ChatCitations.parse(text, _sources), isEmpty);
    });

    test('strip removes markers and the space before them', () {
      expect(
        ChatCitations.strip('ATP is energy [S1][S2]. Yes [S1, S3].'),
        'ATP is energy. Yes.',
      );
    });

    test('json round trip', () {
      const c = ChatCitation(
        number: 1,
        type: AiSourceType.note,
        id: 'n1',
        title: 'Cells',
      );
      expect(ChatCitation.fromJson(c.toJson()), c);
      expect(c.toJson(), {
        'n': 1,
        'type': 'note',
        'id': 'n1',
        'title': 'Cells',
      });
    });
  });

  group('allocateTextBudget', () {
    test('everything fits -> unchanged', () {
      expect(allocateTextBudget([10, 20], 100, 50), [10, 20]);
    });

    test('earlier sources whole first, later ones excerpted', () {
      expect(allocateTextBudget([2500, 2500, 2500], 5000, 1000), [
        2500,
        1500,
        1000,
      ]);
    });

    test('short sources keep their floor, overflow omitted', () {
      // S2's floor (1000) doesn't fit after S1's; S3 (300) still does.
      expect(allocateTextBudget([2500, 2500, 300], 1500, 1000), [1200, 0, 300]);
    });
  });

  group('excerptText', () {
    final long = [
      'Intro line.',
      for (var i = 0; i < 60; i++) ...[
        '## Section $i',
        'Body text of section $i with some words in it.',
      ],
      'Final conclusion.',
    ].join('\n');

    test('keeps start and end, lists omitted headings', () {
      final out = excerptText(long, 600);
      expect(out, startsWith('Intro line.'));
      expect(out, endsWith('Final conclusion.'));
      expect(out, contains('characters omitted to fit the context'));
      expect(out, contains('Omitted sections: Section'));
      expect(out.length, lessThan(long.length));
    });

    test('short text unchanged', () {
      expect(excerptText('abc', 10), 'abc');
    });
  });

  group('fitHistory', () {
    test('keeps newest turns within budget, counts dropped', () {
      final r = fitHistory(const [
        ChatTurn.user('aaaaaaaaaa'),
        ChatTurn.assistant('bbbbbbbbbb'),
        ChatTurn.user('cccccccccc'),
        ChatTurn.assistant('dddddddddd'),
      ], 25);
      expect(r.messages.map((m) => m.text), ['cccccccccc', 'dddddddddd']);
      expect(r.messages.first.role, LlmChatRole.user);
      expect(r.dropped, 2);
    });

    test('single huge newest turn is cut to its end', () {
      final r = fitHistory([ChatTurn.assistant('x' * 50 + 'END')], 10);
      expect(r.messages.single.text, '…${'x' * 7}END');
      expect(r.dropped, 0);
    });
  });

  test('sourcesBlock labels every status', () {
    final block = ChatPrompts.sourcesBlock(
      sources: [
        ..._sources,
        const ChatSourceRef(
          number: 5,
          type: AiSourceType.note,
          title: 'Big "note"',
          status: ChatSourceStatus.omitted,
        ),
      ],
      texts: {1: 'Cell text', 4: 'Excerpt text'},
      attached: {2},
    );
    expect(block, contains('[S1] note "Cells"\n<source id="S1">\nCell text'));
    expect(block, contains('[S2] file "lecture.pdf": attached'));
    expect(
      block,
      contains("[S3] file \"talk.mp3\": unavailable (can't read audio)"),
    );
    expect(block, contains('[S4] text "Pasted text" (excerpt'));
    expect(block, contains("[S5] note \"Big 'note'\": omitted"));
  });
}
