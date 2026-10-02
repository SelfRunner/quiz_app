import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/error_message.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/chat.dart';

/// Creates a chat about the scope with the provider / model AI readiness
/// currently selects.
Future<Chat> createScopedChat(
  WidgetRef ref, {
  required ChatScopeType scopeType,
  String? scopeId,
  required String title,
}) {
  final readiness = ref.read(aiReadinessProvider).value;
  final name = title.trim();
  return ref
      .read(chatRepositoryProvider)
      .create(
        scopeType: scopeType,
        scopeId: scopeType == ChatScopeType.general ? null : scopeId,
        title: name.isEmpty ? 'New chat' : name,
        provider: readiness?.providerId?.wireName,
        model: readiness?.model,
      );
}

/// Opens the most recent chat about the scope, or a new one ([fresh]
/// always starts a new chat). Errors are shown as a snackbar.
Future<void> openScopedChat(
  BuildContext context,
  WidgetRef ref, {
  required ChatScopeType scopeType,
  String? scopeId,
  required String title,
  bool fresh = false,
}) async {
  try {
    Chat? chat;
    if (!fresh) {
      final existing = await ref
          .read(chatRepositoryProvider)
          .watchByScope(
            scopeType,
            scopeType == ChatScopeType.general ? null : scopeId,
          )
          .first;
      if (existing.isNotEmpty) chat = existing.first;
    }
    chat ??= await createScopedChat(
      ref,
      scopeType: scopeType,
      scopeId: scopeId,
      title: title,
    );
    if (context.mounted) await context.push(AppRoutes.chat(chat.id));
  } catch (e) {
    if (context.mounted) {
      showErrorSnackBar(context, e, prefix: 'Could not open the chat');
    }
  }
}
