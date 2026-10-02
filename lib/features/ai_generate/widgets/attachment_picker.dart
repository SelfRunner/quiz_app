import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_capabilities.dart';
import '../../../ai/text_extractor.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../data/ai_file_picker.dart';
import '../domain/generation_sources.dart';
import 'picker_panel.dart';

/// Multi-select over the "Files" library of [subjectId], plus "Upload new"
/// (saved into that library, then selected). Files the current model can't
/// read are shown disabled with the reason. Returns the new selection, or
/// null when cancelled.
Future<List<Attachment>?> showAttachmentPicker(
  BuildContext context, {
  required String subjectId,
  required AiCapabilities capabilities,
  List<Attachment> selected = const [],
}) => showPickerPanel<List<Attachment>>(
  context,
  builder: (_) => AttachmentPicker(
    subjectId: subjectId,
    capabilities: capabilities,
    initial: selected,
  ),
);

class AttachmentPicker extends ConsumerStatefulWidget {
  const AttachmentPicker({
    super.key,
    required this.subjectId,
    required this.capabilities,
    this.initial = const [],
  });

  final String subjectId;
  final AiCapabilities capabilities;
  final List<Attachment> initial;

  @override
  ConsumerState<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends ConsumerState<AttachmentPicker> {
  late final Map<String, Attachment> _selected = {
    for (final a in widget.initial) a.id: a,
  };

  /// Uploaded in this session but maybe not yet emitted by the stream.
  final Map<String, Attachment> _uploaded = {};

  /// File names currently being saved.
  final List<String> _uploading = [];
  String? _error;

  AiCapabilities get _caps => widget.capabilities;

  void _toggle(Attachment a) => setState(() {
    if (_selected.remove(a.id) == null) _selected[a.id] = a;
  });

  Future<void> _upload() async {
    setState(() => _error = null);
    final List<PickedFile> files;
    try {
      files = await ref
          .read(aiFilePickerProvider)
          .pick(extensions: uploadExtensions(_caps));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (files.isEmpty || !mounted) return;
    final repo = ref.read(attachmentRepositoryProvider);
    setState(() => _uploading.addAll(files.map((f) => f.name)));
    final errors = <String>[];
    for (final f in files) {
      try {
        final kind = AttachmentKind.detect(
          fileName: f.name,
          mimeType: f.mimeType,
        );
        final problem = fileKindProblem(kind, _caps);
        if (problem != null) {
          throw ValidationException('"${f.name}": $problem');
        }
        final text = TextExtractor.canExtract(f.name, f.mimeType)
            ? TextExtractor.extract(f.name, f.mimeType, f.bytes)
            : null;
        final a = await repo.add(
          subjectId: widget.subjectId,
          name: f.name,
          mimeType: f.mimeType,
          bytes: f.bytes,
          extractedText: text,
        );
        _uploaded[a.id] = a;
        _selected[a.id] = a;
      } on AppException catch (e) {
        errors.add(e.message);
      } on Object {
        errors.add('Could not add "${f.name}".');
      } finally {
        _uploading.remove(f.name);
        if (mounted) setState(() {});
      }
    }
    if (mounted && errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
    }
  }

  List<Attachment> _merge(List<Attachment> library) {
    final ids = library.map((a) => a.id).toSet();
    return [
      for (final a in _uploaded.values)
        if (!ids.contains(a.id)) a,
      ...library,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final subject = ref.watch(subjectProvider(widget.subjectId)).value;
    final canUpload = subject != null && subject.isOwnedBy(me);
    final library = ref.watch(attachmentsForSubjectProvider(widget.subjectId));
    final count = _selected.length;
    final colors = AppColors.of(context);

    return PickerScaffold(
      title: 'Add files',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              if (subject != null) 'From the "${subject.title}" library.',
              '${uploadKindsLabel(_caps)} work with this model.',
            ].join(' '),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.mutedText),
          ),
          if (canUpload) ...[
            Gaps.h8,
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('attachment-upload'),
                onPressed: _uploading.isEmpty ? _upload : null,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Upload new'),
              ),
            ),
          ],
          if (_error != null) ...[
            Gaps.h8,
            InfoBanner(
              kind: InfoBannerKind.error,
              message: _error!,
              onDismiss: () => setState(() => _error = null),
            ),
          ],
        ],
      ),
      body: AsyncValueView<List<Attachment>>(
        value: library,
        data: (list) {
          final files = _merge(list);
          if (files.isEmpty && _uploading.isEmpty) {
            return EmptyState(
              compact: true,
              icon: Icons.folder_open_outlined,
              title: 'No files yet',
              message: canUpload
                  ? 'Upload a file to keep it in this subject and use it '
                        'as source material.'
                  : 'This subject has no files.',
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            children: [
              for (final name in _uploading)
                ListRowTile(
                  key: ValueKey('uploading-$name'),
                  leading: const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text(name),
                  subtitle: const Text('Saving to the library…'),
                ),
              for (final a in files) _row(a, me),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('attachment-picker-done'),
          onPressed: _uploading.isNotEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.values.toList()),
          child: Text(
            count == 0 ? 'Done' : 'Use $count ${count == 1 ? 'file' : 'files'}',
          ),
        ),
      ],
    );
  }

  Widget _row(Attachment a, String? me) {
    final problem = fileKindProblem(a.kind, _caps);
    final selected = _selected.containsKey(a.id);
    final enabled = problem == null || selected;
    final tile = ListRowTile(
      key: ValueKey('attachment-option-${a.id}'),
      selected: selected,
      onTap: enabled ? () => _toggle(a) : null,
      leading: Checkbox(
        value: selected,
        onChanged: enabled ? (_) => _toggle(a) : null,
      ),
      title: Row(
        children: [
          Icon(attachmentKindIcon(a.kind), size: 16),
          Gaps.w8,
          Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(problem ?? formatFileSize(a.sizeBytes)),
      trailing: a.isOwnedBy(me) ? UploadStatusPill(attachment: a) : null,
    );
    return problem == null ? tile : Opacity(opacity: 0.6, child: tile);
  }
}

/// "Waiting to upload" / "Uploading…" / "Upload retrying" while the blob of
/// an own attachment is not in the cloud yet; nothing when done.
class UploadStatusPill extends ConsumerWidget {
  const UploadStatusPill({super.key, required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(attachmentUploadProvider(attachment.id)).value;
    final colors = AppColors.of(context);
    return switch (state?.phase) {
      AttachmentUploadPhase.queued => const TagPill(
        label: 'Waiting to upload',
        icon: Icons.cloud_queue,
      ),
      AttachmentUploadPhase.uploading => const TagPill(
        label: 'Uploading…',
        icon: Icons.cloud_upload_outlined,
      ),
      AttachmentUploadPhase.retrying => TagPill(
        label: 'Upload retrying',
        icon: Icons.cloud_off_outlined,
        color: colors.warning,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
