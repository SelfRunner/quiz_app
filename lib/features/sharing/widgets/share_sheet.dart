import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../sharing_ui.dart';

/// Content of the share sheet / dialog: explanation, invite-by-email field
/// and the list of people who currently have access (with revoke).
///
/// Use `showShareSheet` from `share_actions.dart` to open it.
class ShareSheet extends ConsumerStatefulWidget {
  const ShareSheet({
    super.key,
    required this.type,
    required this.resourceId,
    required this.title,
    this.inDialog = false,
  });

  final ShareResourceType type;
  final String resourceId;
  final String title;

  /// Rendered inside a dialog (wide screens) rather than a bottom sheet.
  final bool inDialog;

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  final _email = TextEditingController();
  final _emailFocus = FocusNode();
  bool _busy = false;
  String? _fieldError;
  String? _notice;
  bool _noticeIsError = false;
  final Set<String> _revoking = {};

  ({ShareResourceType type, String id}) get _key =>
      (type: widget.type, id: widget.resourceId);

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  void _setNotice(String? text, {bool error = false}) {
    setState(() {
      _notice = text;
      _noticeIsError = error;
    });
  }

  Future<void> _share() async {
    if (_busy) return;
    final email = _email.text.trim();
    setState(() {
      _fieldError = null;
      _notice = null;
    });
    if (email.isEmpty) {
      setState(
        () => _fieldError = 'Enter the email of the person to share with.',
      );
      return;
    }
    if (!looksLikeEmail(email)) {
      setState(() => _fieldError = 'Enter a valid email address.');
      return;
    }
    final me =
        ref.read(authStateProvider).value ??
        ref.read(authRepositoryProvider).currentUser;
    if (me?.email != null &&
        me!.email!.trim().toLowerCase() == email.toLowerCase()) {
      setState(() => _fieldError = "You can't share with yourself.");
      return;
    }

    setState(() => _busy = true);
    final repo = ref.read(shareRepositoryProvider);
    Profile? profile;
    try {
      final found = profile = await repo.findUserByEmail(email);
      if (!mounted) return;
      if (found == null) {
        setState(
          () => _fieldError =
              'No account found for $email. Ask them to sign up first, then '
              'try again.',
        );
        return;
      }
      if (found.id == ref.read(currentUserIdProvider)) {
        setState(() => _fieldError = "You can't share with yourself.");
        return;
      }
      // Fast path from the loaded list; the server's unique constraint
      // (AlreadySharedException below) is the source of truth.
      final existing = ref.read(sharesForResourceProvider(_key)).value;
      if (existing != null && existing.any((s) => s.recipientId == found.id)) {
        setState(() => _fieldError = _alreadySharedText(found, email));
        return;
      }
      final share = await repo.share(
        resourceType: widget.type,
        resourceId: widget.resourceId,
        recipientId: found.id,
      );
      if (!mounted) return;
      _email.clear();
      ref.invalidate(sharesForResourceProvider(_key));
      _setNotice(
        'Shared with ${profileLabel(share.recipient ?? found, fallback: email)}.',
      );
    } on AlreadySharedException catch (e) {
      if (!mounted) return;
      // The list was stale (e.g. shared from another device): refresh it.
      ref.invalidate(sharesForResourceProvider(_key));
      final who = profile;
      setState(
        () => _fieldError = who == null
            ? e.message
            : _alreadySharedText(who, email),
      );
    } on ValidationException catch (e) {
      if (mounted) setState(() => _fieldError = e.message);
    } catch (e) {
      if (mounted) _setNotice(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _alreadySharedText(Profile profile, String email) =>
      'Already shared with ${profileLabel(profile, fallback: email)}.';

  Future<void> _revoke(Share share) async {
    final name = profileLabel(share.recipient);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_remove_outlined),
        title: const Text('Remove access?'),
        content: Text(
          '$name will no longer be able to view “${widget.title}”. '
          'Copies they already made stay in their account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _revoking.add(share.id);
      _notice = null;
    });
    try {
      await ref.read(shareRepositoryProvider).revoke(share.id);
      if (!mounted) return;
      ref.invalidate(sharesForResourceProvider(_key));
      _setNotice('Removed access for $name.');
    } catch (e) {
      if (mounted) _setNotice(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _revoking.remove(share.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shares = ref.watch(sharesForResourceProvider(_key));

    return Padding(
      padding: EdgeInsets.fromLTRB(24, widget.inDialog ? 24 : 0, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.type.icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Share “${widget.title}”',
                  style: theme.textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.inDialog)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoBox(text: widget.type.shareExplanation),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('share-email-field'),
                  controller: _email,
                  focusNode: _emailFocus,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _share(),
                  onChanged: (_) {
                    if (_fieldError != null) setState(() => _fieldError = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'Email address',
                    hintText: 'name@example.com',
                    prefixIcon: const Icon(Icons.alternate_email),
                    border: const OutlineInputBorder(),
                    errorText: _fieldError,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const ValueKey('share-submit'),
                    onPressed: _busy ? null : _share,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: const Text('Share'),
                  ),
                ),
              ),
            ],
          ),
          if (_notice != null) ...[
            const SizedBox(height: 12),
            _Notice(text: _notice!, isError: _noticeIsError),
          ],
          const SizedBox(height: 20),
          Text('People with access', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Flexible(
            child: switch (shares) {
              AsyncValue(:final value?, hasValue: true) => _RecipientList(
                shares: value,
                revoking: _revoking,
                onRevoke: _revoke,
              ),
              AsyncValue(:final error?) => _ListMessage(
                icon: error is NetworkException
                    ? Icons.cloud_off_outlined
                    : Icons.error_outline,
                text: error is NetworkException
                    ? "You're offline. Connect to the internet to see and "
                          'manage who has access.'
                    : friendlyError(error),
                onRetry: () => ref.invalidate(sharesForResourceProvider(_key)),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _RecipientList extends StatelessWidget {
  const _RecipientList({
    required this.shares,
    required this.revoking,
    required this.onRevoke,
  });

  final List<Share> shares;
  final Set<String> revoking;
  final ValueChanged<Share> onRevoke;

  @override
  Widget build(BuildContext context) {
    if (shares.isEmpty) {
      return const _ListMessage(
        icon: Icons.lock_outline,
        text: 'Only you can see this. Add someone by email above.',
      );
    }
    final sorted = [...shares]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      shrinkWrap: true,
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final share = sorted[i];
        final label = profileLabel(share.recipient);
        final email = profileSecondary(share.recipient);
        final busy = revoking.contains(share.id);
        return ListTile(
          key: ValueKey('recipient-${share.id}'),
          contentPadding: EdgeInsets.zero,
          leading: InitialsAvatar(label: label),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [?email, 'Shared ${formatShareDate(share.createdAt)}'].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: busy
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Remove access',
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () => onRevoke(share),
                ),
        );
      },
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.visibility_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = isError ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 20,
              color: fg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListMessage extends StatelessWidget {
  const _ListMessage({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
