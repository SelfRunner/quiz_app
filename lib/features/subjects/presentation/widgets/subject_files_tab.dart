import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../ai/text_extractor.dart' show TextExtractor;
import '../../../../core/router/routes.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/error_message.dart';
import '../../../../core/widgets/sync_status_indicator.dart';
import '../../../../data/data_providers.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/attachment_repository.dart';
import '../../../ai_generate/presentation/ai_generate_screen.dart';
import '../../../chat/widgets/chat_launcher.dart';
import '../../application/attachment_actions.dart';
import '../../application/attachment_picker.dart';
import '../../application/file_saver.dart';

/// Line icon for an attachment kind.
IconData attachmentKindIcon(AttachmentKind kind) => switch (kind) {
  AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
  AttachmentKind.image => Icons.image_outlined,
  AttachmentKind.text => Icons.article_outlined,
  AttachmentKind.docx => Icons.description_outlined,
  AttachmentKind.audio => Icons.audiotrack_outlined,
  AttachmentKind.video => Icons.movie_outlined,
  AttachmentKind.other => Icons.insert_drive_file_outlined,
};

/// Short label for an attachment kind ("PDF", "Image", ...).
String attachmentKindLabel(AttachmentKind kind) => switch (kind) {
  AttachmentKind.pdf => 'PDF',
  AttachmentKind.image => 'Image',
  AttachmentKind.text => 'Text',
  AttachmentKind.docx => 'Word',
  AttachmentKind.audio => 'Audio',
  AttachmentKind.video => 'Video',
  AttachmentKind.other => 'File',
};

/// The "Files" tab of a subject: the attachment library. Owners upload,
/// rename and delete; files of shared subjects are read-only.
class SubjectFilesTab extends ConsumerStatefulWidget {
  const SubjectFilesTab({
    super.key,
    required this.subject,
    required this.isOwner,
  });

  final Subject subject;
  final bool isOwner;

  @override
  ConsumerState<SubjectFilesTab> createState() => _SubjectFilesTabState();
}

class _SubjectFilesTabState extends ConsumerState<SubjectFilesTab> {
  bool _uploading = false;
  List<String> _errors = const [];

  Future<void> _upload() async {
    if (_uploading) return;
    final List<PickedAttachmentFile> files;
    try {
      files = await ref.read(attachmentFilePickerProvider).pickFiles();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e, prefix: 'Could not pick files');
      }
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _errors = const [];
    });
    try {
      final outcome = await addAttachments(
        ref.read(attachmentRepositoryProvider),
        widget.subject.id,
        files,
      );
      if (!mounted) return;
      setState(() => _errors = outcome.errors);
      final n = outcome.added.length;
      if (n > 0) {
        showAppSnackBar(
          context,
          n == 1 ? 'Added "${outcome.added.single.name}"' : 'Added $n files',
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(attachmentsForSubjectProvider(widget.subject.id));
    final count = files.value?.length;
    return SingleChildScrollView(
      key: const PageStorageKey('subject-files'),
      padding: const EdgeInsets.only(bottom: Insets.xxxl),
      child: ContentContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Files',
              count: count,
              subtitle: widget.isOwner
                  ? 'PDFs, images, text, Word, audio and video — up to '
                        '${formatFileSize(Attachment.maxSizeBytes)} each. '
                        'Use them as sources for AI.'
                  : null,
              trailing: widget.isOwner
                  ? FilledButton.tonalIcon(
                      key: const Key('files-upload'),
                      onPressed: _uploading ? null : _upload,
                      icon: _uploading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_outlined, size: 18),
                      label: const Text('Upload'),
                    )
                  : null,
            ),
            if (!widget.isOwner) ...[
              const InfoBanner(
                key: Key('files-read-only'),
                icon: Icons.visibility_outlined,
                message:
                    'Files shared with you are read-only. You can open and '
                    'download them.',
              ),
              Gaps.h8,
            ],
            if (_errors.isNotEmpty) ...[
              InfoBanner(
                key: const Key('files-upload-errors'),
                kind: InfoBannerKind.error,
                title: _errors.length == 1
                    ? 'A file was not added'
                    : '${_errors.length} files were not added',
                message: _errors.join('\n'),
                onDismiss: () => setState(() => _errors = const []),
              ),
              Gaps.h8,
            ],
            AsyncValueView<List<Attachment>>(
              value: files,
              loading: const LoadingSkeleton(),
              onRetry: () => ref.invalidate(
                attachmentsForSubjectProvider(widget.subject.id),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    compact: true,
                    icon: Icons.folder_open_outlined,
                    title: 'No files yet',
                    message: widget.isOwner
                        ? 'Upload lecture slides, readings or recordings to '
                              'keep them with this subject.'
                        : 'The owner has not added files to this subject.',
                    action: widget.isOwner
                        ? OutlinedButton.icon(
                            onPressed: _uploading ? null : _upload,
                            icon: const Icon(Icons.upload_outlined, size: 18),
                            label: const Text('Upload files'),
                          )
                        : null,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final a in items)
                      AttachmentRow(
                        key: ValueKey('attachment-${a.id}'),
                        attachment: a,
                        canEdit: widget.isOwner,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _FileAction { open, download, rename, delete }

/// One file: kind icon, name, size and upload status, with row actions.
class AttachmentRow extends ConsumerWidget {
  const AttachmentRow({
    super.key,
    required this.attachment,
    required this.canEdit,
  });

  final Attachment attachment;

  /// Owner of the subject: may rename, delete and use it in AI.
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = attachment;
    final colors = AppColors.of(context);
    final upload = canEdit
        ? ref.watch(attachmentUploadProvider(a.id)).value
        : null;
    final meta = [
      attachmentKindLabel(a.kind),
      if (a.sizeBytes > 0) formatFileSize(a.sizeBytes),
      'Added ${formatRelativeTime(a.createdAt)}',
    ].join(' · ');

    void useInAi() => context.push(
      AppRoutes.generate(kind: AiGenerateKind.quiz, subjectId: a.subjectId),
    );

    return ListRowTile(
      leading: Icon(
        attachmentKindIcon(a.kind),
        key: Key('attachment-icon-${a.kind.name}'),
      ),
      title: Text(a.name),
      subtitle: Text(meta),
      trailing: upload == null ? null : _UploadStatus(state: upload),
      onTap: () => openAttachment(context, ref, a),
      actions: [
        ChatLauncherButton(
          scopeType: ChatScopeType.attachment,
          scopeId: a.id,
          title: a.name,
          compact: true,
          tooltip: 'Ask AI about this file',
        ),
        if (canEdit)
          AiGate(
            onReady: useInAi,
            child: IconButton(
              key: Key('attachment-ai-${a.id}'),
              tooltip: 'Use in AI',
              icon: const Icon(Icons.auto_awesome_outlined),
              visualDensity: VisualDensity.compact,
              onPressed: useInAi,
            ),
          ),
        PopupMenuButton<_FileAction>(
          key: Key('attachment-menu-${a.id}'),
          tooltip: 'More',
          icon: Icon(Icons.more_horiz, color: colors.mutedText),
          onSelected: (action) => switch (action) {
            _FileAction.open => openAttachment(context, ref, a),
            _FileAction.download => downloadAttachment(context, ref, a),
            _FileAction.rename => _rename(context, ref, a),
            _FileAction.delete => _delete(context, ref, a),
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _FileAction.open,
              child: ListTile(
                leading: Icon(Icons.open_in_new),
                title: Text('Open'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: _FileAction.download,
              child: ListTile(
                leading: Icon(Icons.download_outlined),
                title: Text('Download'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (canEdit) ...const [
              PopupMenuItem(
                value: _FileAction.rename,
                child: ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('Rename'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _FileAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Attachment a,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: a.name),
    );
    if (name == null || name == a.name) return;
    try {
      await ref.read(attachmentRepositoryProvider).rename(a.id, name);
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, e, prefix: 'Could not rename');
      }
    }
  }

  static Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Attachment a,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete "${a.name}"?',
      message:
          'The file is removed from this subject, for you and everyone it is '
          'shared with.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(attachmentRepositoryProvider).delete(a.id);
      if (context.mounted) showAppSnackBar(context, 'File deleted');
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
    }
  }
}

class _UploadStatus extends StatelessWidget {
  const _UploadStatus({required this.state});

  final AttachmentUploadState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (Widget icon, String label) = switch (state.phase) {
      AttachmentUploadPhase.done => (
        Icon(Icons.cloud_done_outlined, size: 16, color: colors.faintText),
        'Uploaded',
      ),
      AttachmentUploadPhase.queued => (
        Icon(Icons.cloud_queue_outlined, size: 16, color: colors.mutedText),
        'Waiting to upload',
      ),
      AttachmentUploadPhase.uploading => (
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        'Uploading…',
      ),
      AttachmentUploadPhase.retrying => (
        Icon(Icons.sync_problem_outlined, size: 16, color: colors.warning),
        'Upload failed — retrying',
      ),
    };
    final wide = Breakpoints.isMedium(context);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Row(
          key: const Key('attachment-upload-status'),
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            if (wide && state.phase != AttachmentUploadPhase.done) ...[
              Gaps.w4,
              Text(label),
            ],
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    // Select the name without its extension.
    final dot = widget.initial.lastIndexOf('.');
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : widget.initial.length,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename file'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('attachment-rename'),
          controller: _name,
          autofocus: true,
          maxLength: Attachment.maxNameLength,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('attachment-rename-save'),
        onPressed: _submit,
        child: const Text('Rename'),
      ),
    ],
  );
}

/// Opens [a]: images in an inline viewer, text/Word files as their extracted
/// text, everything else is downloaded (saved) to open in another app.
Future<void> openAttachment(
  BuildContext context,
  WidgetRef ref,
  Attachment a,
) async {
  switch (a.kind) {
    case AttachmentKind.image:
      await showDialog<void>(
        context: context,
        builder: (_) => _ImagePreviewDialog(attachment: a),
      );
    case AttachmentKind.text || AttachmentKind.docx:
      await showDialog<void>(
        context: context,
        builder: (_) => _TextPreviewDialog(attachment: a),
      );
    case _:
      await downloadAttachment(context, ref, a);
  }
}

/// Fetches [a]'s bytes and hands them to [fileSaverProvider].
Future<void> downloadAttachment(
  BuildContext context,
  WidgetRef ref,
  Attachment a,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text('Preparing "${a.name}"…'),
      behavior: SnackBarBehavior.floating,
    ),
  );
  try {
    final bytes = await ref.read(attachmentRepositoryProvider).getBytes(a);
    final path = await ref
        .read(fileSaverProvider)
        .save(a.name, bytes, mimeType: a.mimeType);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      path == null ? 'Downloading "${a.name}"' : 'Saved to $path',
    );
  } catch (e) {
    if (context.mounted) {
      showErrorSnackBar(context, e, prefix: 'Could not open "${a.name}"');
    }
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.attachment,
    required this.child,
    this.maxWidth = 900,
  });

  final Attachment attachment;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(Insets.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.xs,
                Insets.sm,
              ),
              child: Row(
                children: [
                  Icon(attachmentKindIcon(attachment.kind), size: 18),
                  Gaps.w8,
                  Expanded(
                    child: Text(
                      attachment.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) => IconButton(
                      tooltip: 'Download',
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () =>
                          downloadAttachment(context, ref, attachment),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.of(context).hairline),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewDialog extends ConsumerStatefulWidget {
  const _ImagePreviewDialog({required this.attachment});

  final Attachment attachment;

  @override
  ConsumerState<_ImagePreviewDialog> createState() =>
      _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends ConsumerState<_ImagePreviewDialog> {
  late final Future<Uint8List> _bytes = ref
      .read(attachmentRepositoryProvider)
      .getBytes(widget.attachment);

  @override
  Widget build(BuildContext context) => _PreviewFrame(
    attachment: widget.attachment,
    child: FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: InfoBanner(
              kind: InfoBannerKind.error,
              message: errorMessage(snapshot.error),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Padding(
            padding: EdgeInsets.all(Insets.xxl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return InteractiveViewer(
          maxScale: 6,
          child: Image.memory(
            bytes,
            key: const Key('attachment-image-preview'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(Insets.xl),
              child: EmptyState(
                compact: true,
                icon: Icons.broken_image_outlined,
                title: 'This image cannot be shown',
                message: 'Download it to open it in another app.',
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TextPreviewDialog extends ConsumerStatefulWidget {
  const _TextPreviewDialog({required this.attachment});

  final Attachment attachment;

  @override
  ConsumerState<_TextPreviewDialog> createState() => _TextPreviewDialogState();
}

class _TextPreviewDialogState extends ConsumerState<_TextPreviewDialog> {
  late final Future<String> _text = _load();

  Future<String> _load() async {
    final a = widget.attachment;
    final stored = a.extractedText;
    if (stored != null) return stored;
    final bytes = await ref.read(attachmentRepositoryProvider).getBytes(a);
    return TextExtractor.extract(a.name, a.mimeType, bytes) ?? '';
  }

  @override
  Widget build(BuildContext context) => _PreviewFrame(
    attachment: widget.attachment,
    maxWidth: ContentWidth.readable,
    child: FutureBuilder<String>(
      future: _text,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: InfoBanner(
              kind: InfoBannerKind.error,
              message: errorMessage(snapshot.error),
            ),
          );
        }
        final text = snapshot.data;
        if (text == null) {
          return const Padding(
            padding: EdgeInsets.all(Insets.xxl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (text.trim().isEmpty) {
          return const EmptyState(
            compact: true,
            icon: Icons.notes_outlined,
            title: 'No text found in this file',
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.xl),
          child: SelectableText(
            text,
            key: const Key('attachment-text-preview'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      },
    ),
  );
}
