import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

/// Wave 3 placeholder — global search (replaced by the search feature).
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Search');
}
