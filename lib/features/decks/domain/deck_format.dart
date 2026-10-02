import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../../data/models/card_review.dart';
import '../../../data/models/deck.dart';

/// `3 cards`, `1 card`.
String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// User-safe text for an error thrown by a repository.
String errorText(Object error) =>
    error is AppException ? error.message : 'Something went wrong.';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Compact interval label for rating buttons: `<1m`, `10m`, `3h`, `4d`,
/// `2mo`, `1.5y`.
String formatInterval(Duration d) {
  if (d.inSeconds < 60) return '<1m';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  final days = (d.inHours / 24).round();
  if (days < 30) return '${days}d';
  if (days < 365) {
    final months = days / 30;
    return months < 10 && (months * 10).round() % 10 != 0
        ? '${months.toStringAsFixed(1)}mo'
        : '${months.round()}mo';
  }
  final years = days / 365;
  return (years * 10).round() % 10 == 0
      ? '${years.round()}y'
      : '${years.toStringAsFixed(1)}y';
}

String ratingLabel(Rating r) => switch (r) {
  Rating.again => 'Again',
  Rating.hard => 'Hard',
  Rating.good => 'Good',
  Rating.easy => 'Easy',
};

String cardStateLabel(CardState s) => switch (s) {
  CardState.newCard => 'New',
  CardState.learning => 'Learning',
  CardState.review => 'Review',
  CardState.relearning => 'Relearning',
};

/// Problems that block saving a card (blank sides).
List<String> cardIssues(Flashcard card) => [
  if (card.front.trim().isEmpty) 'The front is empty.',
  if (card.back.trim().isEmpty) 'The back is empty.',
];

/// Trims sides, drops blank hints.
Flashcard normalizeCard(Flashcard card) {
  final hint = card.hint?.trim() ?? '';
  return card.copyWith(
    front: card.front.trim(),
    back: card.back.trim(),
    hint: hint.isEmpty ? null : hint,
  );
}

/// True when both sides and the hint are blank (dropped on save).
bool isBlankCard(Flashcard card) =>
    card.front.trim().isEmpty &&
    card.back.trim().isEmpty &&
    (card.hint?.trim().isEmpty ?? true);

/// Cards ready to save: blank ones dropped, the rest normalized. Returns
/// null when a remaining card has an empty side.
List<Flashcard>? cardsForSave(List<Flashcard> cards) {
  final kept = [
    for (final c in cards)
      if (!isBlankCard(c)) normalizeCard(c),
  ];
  return kept.any((c) => cardIssues(c).isNotEmpty) ? null : kept;
}
