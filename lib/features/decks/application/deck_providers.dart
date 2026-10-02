import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/card_review.dart';

/// The current user's live review rows of one deck, by card id.
final deckReviewsProvider = StreamProvider.autoDispose
    .family<Map<String, CardReview>, String>(
      (ref, deckId) => ref
          .watch(reviewRepositoryProvider)
          .watchAll()
          .map(
            (rows) => {
              for (final r in rows)
                if (r.deckId == deckId && r.deletedAt == null) r.cardId: r,
            },
          ),
    );
