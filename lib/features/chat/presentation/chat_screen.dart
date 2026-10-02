import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_screen.dart';

/// Wave 3 placeholder — one chat conversation (replaced by the chat feature).
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Chat');
}
