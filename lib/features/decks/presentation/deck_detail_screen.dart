import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

/// Wave 2 placeholder — replaced by the owning feature agent.
class DeckDetailScreen extends StatelessWidget {
  const DeckDetailScreen({super.key, required this.deckId});

  final String deckId;

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Deck');
}
