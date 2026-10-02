import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/search/search_index.dart';
import 'package:quiz_app/search/search_models.dart';
import 'package:quiz_app/search/search_providers.dart';

import 'org_fakes.dart';

final DateTime kSearchNow = DateTime.utc(2026, 1, 10, 12);

SearchDocument doc(
  SearchItemType type,
  String id,
  String title, {
  String body = '',
  List<String> tags = const [],
  String? subjectId = 's1',
  bool pinned = false,
}) => SearchDocument(
  type: type,
  id: id,
  title: title,
  body: body,
  tags: tags,
  subjectId: subjectId,
  updatedAt: DateTime.utc(2026, 1, 9),
  pinned: pinned,
);

/// One item of every type mentioning "cell", plus unrelated ones.
SearchIndex buildSearchIndex() {
  final index = SearchIndex()
    ..subjectTitles = {'s1': 'Biology', 's2': 'History'}
    ..archivedSubjectIds = {'s2'};
  for (final d in [
    doc(SearchItemType.subject, 's1', 'Biology', body: 'Study of cells'),
    doc(SearchItemType.subject, 's2', 'History', subjectId: 's2'),
    doc(
      SearchItemType.note,
      'n1',
      'Cell biology',
      body: 'The mitochondria is the powerhouse of the cell.',
      tags: ['exam'],
    ),
    doc(
      SearchItemType.note,
      'n2',
      'Cell membranes',
      body: 'Membranes are lipid bilayers.',
      pinned: true,
    ),
    doc(SearchItemType.note, 'n3', 'Romans', body: 'Empire', subjectId: 's2'),
    doc(
      SearchItemType.quiz,
      'q1',
      'Cell quiz',
      body: 'Which organelle makes energy for the cell?',
      tags: ['exam'],
    ),
    doc(SearchItemType.deck, 'd1', 'Cell cards', body: 'nucleus ribosome'),
    doc(
      SearchItemType.attachment,
      'a1',
      'cells.pdf',
      body: 'Cell diagrams and notes',
    ),
    doc(SearchItemType.chat, 'c1', 'Chat about cells', subjectId: null),
  ]) {
    index.upsert(d);
  }
  return index;
}

/// Overrides `searchProvider` with [index] and the organization repository
/// with [org] (subject / tag filters).
List<Override> searchOverrides(
  SearchIndex index,
  FakeOrganizationRepository org,
) => [
  searchProvider.overrideWith(
    (ref, request) => AsyncData(
      index.search(request.query, filters: request.filters, now: kSearchNow),
    ),
  ),
  organizationRepositoryProvider.overrideWithValue(org),
];

/// Finds `RichText` whose plain text is [text].
Finder richTextWith(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText() == text,
);

/// Substrings of [span] drawn with a bold (w600) style.
List<String> boldParts(InlineSpan span) {
  final parts = <String>[];
  span.visitChildren((s) {
    if (s is TextSpan &&
        s.text != null &&
        s.style?.fontWeight == FontWeight.w600) {
      parts.add(s.text!);
    }
    return true;
  });
  return parts;
}
