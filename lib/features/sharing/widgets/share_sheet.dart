import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/design_system.dart';
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
    final colors = AppColors.of(context);
    final shares = ref.watch(sharesForResourceProvider(_key));
    final count = shares.value?.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.xl,
        widget.inDialog ? Insets.xl : 0,
        Insets.xl,
        Insets.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.type.icon, size: 20, color: colors.mutedText),
              Gaps.w12,
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
          Gaps.h16,
          InfoBanner(
            icon: Icons.visibility_outlined,
            message: widget.type.shareExplanation,
          ),
          Gaps.h24,
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
                    prefixIcon: const Icon(Icons.alternate_email, size: 18),
                    errorText: _fieldError,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              Gaps.w8,
              Padding(
                padding: const EdgeInsets.only(top: Insets.xs),
                child: FilledButton(
                  key: const ValueKey('share-submit'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 44),
                  ),
                  onPressed: _busy ? null : _share,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Share'),
                ),
              ),
            ],
          ),
          if (_notice != null) ...[
            Gaps.h12,
            InfoBanner(
              kind: _noticeIsError
                  ? InfoBannerKind.error
                  : InfoBannerKind.success,
              message: _notice!,
              onDismiss: () => _setNotice(null),
            ),
          ],
          SectionHeader(
            title: 'People with access',
            count: count == null || count == 0 ? null : count,
            padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.xs),
          ),
          Flexible(
            child: switch (shares) {
              AsyncValue(:final value?, hasValue: true) => _RecipientList(
                shares: value,
                revoking: _revoking,
                onRevoke: _revoke,
              ),
              AsyncValue(:final error?) => Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                child: InfoBanner(
                  kind: error is NetworkException
                      ? InfoBannerKind.warning
                      : InfoBannerKind.error,
                  icon: error is NetworkException
                      ? Icons.cloud_off_outlined
                      : null,
                  message: error is NetworkException
                      ? "You're offline. Connect to the internet to see and "
                            'manage who has access.'
                      : friendlyError(error),
                  action: TextButton(
                    onPressed: () =>
                        ref.invalidate(sharesForResourceProvider(_key)),
                    child: const Text('Retry'),
                  ),
                ),
              ),
              _ => const LoadingSkeleton(rows: 2, animate: false),
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
      final colors = AppColors.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: colors.faintText),
            Gaps.w12,
            Expanded(
              child: Text(
                'Only you can see this. Add someone by email above.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.mutedText),
              ),
            ),
          ],
        ),
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
        return ListRowTile(
          key: ValueKey('recipient-${share.id}'),
          padding: const EdgeInsets.symmetric(vertical: Insets.sm),
          revealActionsOnHover: false,
          leading: InitialsAvatar(label: label, radius: 16),
          title: Text(label),
          subtitle: Text(
            [?email, 'Shared ${formatShareDate(share.createdAt)}'].join(' · '),
          ),
          actions: [
            if (busy)
              const Padding(
                padding: EdgeInsets.all(Insets.md),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: 'Remove access',
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: () => onRevoke(share),
              ),
          ],
        );
      },
    );
  }
}
