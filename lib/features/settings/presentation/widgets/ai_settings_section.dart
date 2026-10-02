import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../ai/ai_capabilities.dart';
import '../../../../ai/ai_providers.dart';
import '../../../../ai/ai_readiness.dart';
import '../../../../ai/ai_source.dart' show AiInputKind;
import '../../../../ai/base_url_policy.dart';
import '../../../../ai/llm_provider.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/error_message.dart';

/// Parses `Header: value` lines (blank lines ignored). Throws [FormatException]
/// with a user-facing message on a malformed line.
Map<String, String> parseHeaderLines(String text) {
  final headers = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) {
      throw FormatException('Use "Name: value" per line ("$line")');
    }
    final name = line.substring(0, colon).trim();
    final value = line.substring(colon + 1).trim();
    if (name.contains(' ') || name.isEmpty) {
      throw FormatException('Invalid header name "$name"');
    }
    headers[name] = value;
  }
  return headers;
}

String formatHeaderLines(Map<String, String> headers) =>
    headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');

enum _TestState { idle, running, ok, failed }

/// Bumped after the AI settings were wiped elsewhere on the Settings screen
/// ("Danger zone"), so [AiSettingsSection] reloads its form.
final aiSettingsResetProvider = NotifierProvider<AiSettingsReset, int>(
  AiSettingsReset.new,
);

class AiSettingsReset extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// AI provider configuration: readiness, active provider, API key
/// (device-only), model with its input capabilities, and base URL / headers
/// (plus a manual image/PDF capability override) for OpenAI-compatible
/// endpoints.
class AiSettingsSection extends ConsumerStatefulWidget {
  const AiSettingsSection({super.key});

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  final _formKey = GlobalKey<FormState>();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  final _headers = TextEditingController();
  final _modelFocus = FocusNode();

  LlmProviderId _provider = LlmProviderId.gemini;
  Set<LlmProviderId> _configured = {};
  bool _hasStoredKey = false;
  bool _obscureKey = true;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  List<String>? _models;
  bool _loadingModels = false;
  String? _modelsError;

  _TestState _testState = _TestState.idle;
  String? _testMessage;

  /// Guards against out-of-order async loads when switching providers fast.
  int _loadToken = 0;

  /// Input kinds of the provider + model in the form.
  AiCapabilities? _caps;

  /// Manual capability override of the model in the form.
  Set<AiInputKind> _override = const {};
  Timer? _capsDebounce;
  int _capsToken = 0;

  @override
  void initState() {
    super.initState();
    for (final c in [_apiKey, _model, _baseUrl, _headers]) {
      c.addListener(_markDirty);
    }
    for (final c in [_model, _baseUrl]) {
      c.addListener(_scheduleCapabilities);
    }
    unawaited(_init());
  }

  @override
  void dispose() {
    _capsDebounce?.cancel();
    _apiKey.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _headers.dispose();
    _modelFocus.dispose();
    super.dispose();
  }

  bool _suppressDirty = false;

  void _markDirty() {
    if (_suppressDirty || _loading) return;
    if (!_dirty || _testState != _TestState.idle) {
      setState(() {
        _dirty = true;
        _testState = _TestState.idle;
        _testMessage = null;
      });
    }
  }

  Future<void> _init() async {
    final store = ref.read(apiKeyStoreProvider);
    try {
      final selected = await store.getSelectedProvider();
      final configured = await store.configuredProviders();
      _configured = configured;
      _provider =
          selected ??
          (configured.isNotEmpty ? configured.first : LlmProviderId.gemini);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    await _loadProvider(_provider);
  }

  Future<void> _loadProvider(LlmProviderId provider) async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _provider = provider;
      _models = null;
      _modelsError = null;
      _testState = _TestState.idle;
      _testMessage = null;
    });
    final store = ref.read(apiKeyStoreProvider);
    String? key;
    String? model;
    String? baseUrl;
    var headers = <String, String>{};
    try {
      key = await store.getApiKey(provider);
      model = await store.getSelectedModel(provider);
      if (provider.requiresBaseUrl) {
        baseUrl = await store.getBaseUrl(provider);
        headers = await store.getExtraHeaders(provider);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (!mounted || token != _loadToken) return;
    _suppressDirty = true;
    _apiKey.text = key ?? '';
    _model.text = model ?? '';
    _baseUrl.text = baseUrl ?? '';
    _headers.text = formatHeaderLines(headers);
    _suppressDirty = false;
    setState(() {
      _hasStoredKey = key != null && key.isNotEmpty;
      _obscureKey = true;
      _loading = false;
      _dirty = false;
    });
    await _refreshCapabilities();
  }

  String get _modelOrDefault {
    final m = _model.text.trim();
    return m.isEmpty ? _provider.defaultModel : m;
  }

  /// The override store, when the key store supports it.
  AiCapabilityOverrideStore? get _overrideStore {
    final Object store = ref.read(apiKeyStoreProvider);
    return store is AiCapabilityOverrideStore ? store : null;
  }

  /// OpenAI-compatible endpoint whose capabilities cannot be detected (not
  /// OpenRouter): the user may declare image / PDF support.
  bool get _canOverride =>
      _provider == LlmProviderId.openaiCompatible &&
      _overrideStore != null &&
      !AiCapabilityResolver.isOpenRouterUrl(
        _effectiveBaseUrl ?? _provider.defaultBaseUrl,
      );

  void _scheduleCapabilities() {
    if (_loading || _suppressDirty) return;
    _capsDebounce?.cancel();
    _capsDebounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_refreshCapabilities()),
    );
  }

  Future<void> _refreshCapabilities() async {
    _capsDebounce?.cancel();
    final token = ++_capsToken;
    final p = _provider;
    final model = _modelOrDefault;
    final baseUrl = _effectiveBaseUrl ?? p.defaultBaseUrl;
    try {
      final store = _overrideStore;
      final override = store != null && p == LlmProviderId.openaiCompatible
          ? await store.getInputOverride(p, model)
          : const <AiInputKind>{};
      final caps = await ref
          .read(aiCapabilityResolverProvider)
          .resolve(
            provider: p,
            model: model,
            baseUrl: baseUrl,
            manualOverride: override,
          );
      if (!mounted || token != _capsToken) return;
      setState(() {
        _caps = caps;
        _override = override;
      });
    } catch (_) {
      if (!mounted || token != _capsToken) return;
      setState(() => _caps = null);
    }
  }

  Future<void> _setOverride(AiInputKind kind, bool enabled) async {
    final store = _overrideStore;
    if (store == null) return;
    final next = {..._override};
    enabled ? next.add(kind) : next.remove(kind);
    try {
      await store.setInputOverride(_provider, _modelOrDefault, next);
      ref.invalidate(aiReadinessProvider);
      await _refreshCapabilities();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _selectProvider(LlmProviderId? provider) async {
    if (provider == null || provider == _provider) return;
    if (_dirty) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard changes?',
        message:
            'You have unsaved changes for ${_provider.displayName}. Switch '
            'provider anyway?',
        confirmLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    try {
      await ref.read(apiKeyStoreProvider).setSelectedProvider(provider);
      ref.invalidate(aiReadinessProvider);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) await _loadProvider(provider);
  }

  String? get _unsavedKey {
    final k = _apiKey.text.trim();
    return k.isEmpty ? null : k;
  }

  String? get _effectiveBaseUrl {
    final u = _baseUrl.text.trim();
    return u.isEmpty ? null : u;
  }

  Map<String, String>? _parsedHeadersOrNull() {
    try {
      return parseHeaderLines(_headers.text);
    } on FormatException {
      return null;
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final store = ref.read(apiKeyStoreProvider);
    final p = _provider;
    try {
      final key = _apiKey.text.trim();
      if (key.isEmpty) {
        await store.deleteApiKey(p);
      } else {
        await store.setApiKey(p, key);
      }
      final model = _model.text.trim();
      if (model.isNotEmpty) await store.setSelectedModel(p, model);
      if (p.requiresBaseUrl) {
        await store.setBaseUrl(p, _effectiveBaseUrl);
        await store.setExtraHeaders(p, parseHeaderLines(_headers.text));
      }
      await store.setSelectedProvider(p);
      ref.invalidate(aiReadinessProvider);
      final configured = await store.configuredProviders();
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _hasStoredKey = key.isNotEmpty;
        _dirty = false;
      });
      showAppSnackBar(context, '${p.displayName} settings saved');
      unawaited(_refreshCapabilities());
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, prefix: 'Could not save');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearKey() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove ${_provider.displayName} key?',
      message:
          'The key is deleted from this device. You can add it again '
          'any time.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final store = ref.read(apiKeyStoreProvider);
      await store.deleteApiKey(_provider);
      ref.invalidate(aiReadinessProvider);
      final configured = await store.configuredProviders();
      if (!mounted) return;
      _suppressDirty = true;
      _apiKey.clear();
      _suppressDirty = false;
      setState(() {
        _configured = configured;
        _hasStoredKey = false;
        _models = null;
      });
      showAppSnackBar(context, 'API key removed');
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final models = await ref
          .read(aiServiceProvider)
          .listModels(
            _provider,
            apiKey: _unsavedKey,
            baseUrl: _effectiveBaseUrl,
            extraHeaders: _parsedHeadersOrNull(),
          );
      if (!mounted) return;
      setState(() {
        _models = [...models]..sort();
        if (models.isEmpty) {
          _modelsError = 'No models returned. Type a model id instead.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _modelsError = '${errorMessage(e)} You can still type a model id.',
      );
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testState = _TestState.running;
      _testMessage = null;
    });
    try {
      await ref
          .read(aiServiceProvider)
          .testConnection(
            _provider,
            apiKey: _unsavedKey,
            baseUrl: _effectiveBaseUrl,
            extraHeaders: _parsedHeadersOrNull(),
          );
      if (!mounted) return;
      setState(() {
        _testState = _TestState.ok;
        _testMessage = 'Connection works.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testState = _TestState.failed;
        _testMessage = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(aiSettingsResetProvider, (_, _) => unawaited(_init()));
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final p = _provider;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AiReadinessBanner(),
          if (kIsWeb) ...[Gaps.h12, const _WebKeyWarning()],
          Gaps.h16,
          KeyedSubtree(
            key: const Key('ai-provider'),
            child: DropdownButtonFormField<LlmProviderId>(
              // Re-created on provider change so it reflects _provider.
              key: ValueKey(p),
              initialValue: p,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Provider used for generation',
              ),
              items: [
                for (final id in LlmProviderId.values)
                  DropdownMenuItem(
                    value: id,
                    child: Row(
                      children: [
                        Expanded(child: Text(id.displayName)),
                        if (_configured.contains(id))
                          Icon(
                            Icons.key,
                            size: 16,
                            color: colors.mutedText,
                            semanticLabel: 'Key saved',
                          ),
                      ],
                    ),
                  ),
              ],
              onChanged: _loading || _saving ? null : _selectProvider,
            ),
          ),
          Gaps.h16,
          if (_loading)
            const LoadingSkeleton(rows: 3, leading: false, subtitle: false)
          else ...[
            TextFormField(
              key: const Key('ai-api-key'),
              controller: _apiKey,
              obscureText: _obscureKey,
              enableSuggestions: false,
              autocorrect: false,
              autofillHints: const <String>[],
              decoration: InputDecoration(
                labelText: '${p.displayName} API key',
                helperText: _hasStoredKey
                    ? 'Saved on this device'
                    : p.requiresBaseUrl
                    ? 'Optional for local endpoints (e.g. Ollama)'
                    : 'Required to generate with ${p.displayName}',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key('ai-api-key-visibility'),
                      tooltip: _obscureKey ? 'Show key' : 'Hide key',
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                    if (_hasStoredKey)
                      IconButton(
                        key: const Key('ai-api-key-clear'),
                        tooltip: 'Remove saved key',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: _clearKey,
                      ),
                  ],
                ),
              ),
            ),
            if (p.requiresBaseUrl) ...[
              Gaps.h16,
              TextFormField(
                key: const Key('ai-base-url'),
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: p.defaultBaseUrl,
                  helperText:
                      'Leave empty for ${p.defaultBaseUrl} (OpenRouter). '
                      'https:// required; http:// only for local servers, '
                      'e.g. http://localhost:11434/v1 for Ollama',
                  helperMaxLines: 3,
                  errorMaxLines: 3,
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => baseUrlProblem(v ?? ''),
              ),
              Gaps.h16,
              TextFormField(
                key: const Key('ai-headers'),
                controller: _headers,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Extra headers (optional)',
                  hintText:
                      'HTTP-Referer: https://myapp.example\nX-Title: Quiz',
                  helperText: 'One "Name: value" per line',
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  try {
                    parseHeaderLines(v ?? '');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
            ],
            Gaps.h16,
            _ModelField(
              controller: _model,
              focusNode: _modelFocus,
              models: _models,
              defaultModel: p.defaultModel,
              loading: _loadingModels,
              error: _modelsError,
              onLoad: _loadModels,
            ),
            Gaps.h12,
            _CapabilitySummary(caps: _caps, model: _modelOrDefault),
            if (_canOverride) ...[
              Gaps.h8,
              _OverrideToggle(
                key: const Key('ai-override-image'),
                label: 'Model supports images',
                value: _override.contains(AiInputKind.image),
                onChanged: (v) => _setOverride(AiInputKind.image, v),
              ),
              _OverrideToggle(
                key: const Key('ai-override-pdf'),
                label: 'Model supports PDFs',
                value: _override.contains(AiInputKind.pdf),
                onChanged: (v) => _setOverride(AiInputKind.pdf, v),
              ),
              Text(
                'Turn these on only if your endpoint accepts image or PDF '
                'input for this model; otherwise requests with files fail.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ],
            Gaps.h16,
            if (_testMessage != null) ...[
              InfoBanner(
                key: const Key('ai-test-result'),
                kind: _testState == _TestState.ok
                    ? InfoBannerKind.success
                    : InfoBannerKind.error,
                message: _testMessage!,
              ),
              Gaps.h12,
            ],
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: const Key('ai-test'),
                  onPressed: _testState == _TestState.running ? null : _test,
                  icon: _testState == _TestState.running
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check, size: 18),
                  label: const Text('Test connection'),
                ),
                FilledButton.icon(
                  key: const Key('ai-save'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(_dirty ? 'Save' : 'Saved'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether AI is usable: "ready" with provider + model, or what is missing.
class AiReadinessBanner extends ConsumerWidget {
  const AiReadinessBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(aiReadinessProvider).value;
    if (readiness == null) {
      return const LoadingSkeleton(
        key: Key('ai-readiness'),
        rows: 1,
        leading: false,
      );
    }
    if (readiness.isConfigured) {
      return InfoBanner(
        key: const Key('ai-readiness'),
        kind: InfoBannerKind.success,
        title: 'AI is ready',
        message:
            'Using ${readiness.providerId?.displayName ?? 'AI'} · '
            '${readiness.model ?? ''}',
      );
    }
    return InfoBanner(
      key: const Key('ai-readiness'),
      kind: InfoBannerKind.warning,
      title: switch (readiness.issue) {
        AiReadinessIssue.invalidBaseUrl => 'Base URL not allowed',
        AiReadinessIssue.storageError => 'Settings could not be read',
        AiReadinessIssue.missingModel => 'Choose a model',
        _ => 'AI is not set up',
      },
      message:
          readiness.reason ??
          'Add an API key and choose a model to use AI features.',
    );
  }
}

/// One input kind of the selected model: check when supported, dimmed when
/// not.
class CapabilityChip extends StatelessWidget {
  const CapabilityChip({
    super.key,
    required this.label,
    required this.supported,
    this.tooltip,
  });

  final String label;
  final bool supported;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final fg = supported ? theme.colorScheme.onSurface : colors.faintText;
    final chip = Semantics(
      label: '$label: ${supported ? 'supported' : 'not supported'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xxs + 1,
        ),
        decoration: BoxDecoration(
          color: supported ? colors.hover : null,
          borderRadius: Radii.smAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              supported ? Icons.check : Icons.remove,
              size: 14,
              color: supported ? colors.success : colors.faintText,
            ),
            Gaps.w4,
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                decoration: supported ? null : TextDecoration.lineThrough,
                decorationColor: colors.faintText,
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}

class _CapabilitySummary extends StatelessWidget {
  const _CapabilitySummary({required this.caps, required this.model});

  final AiCapabilities? caps;
  final String model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final c = caps;
    return Column(
      key: const Key('ai-capabilities'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What $model can read',
          style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedText),
        ),
        Gaps.h8,
        if (c == null)
          const LoadingSkeleton(rows: 1, leading: false, subtitle: false)
        else
          Wrap(
            spacing: Insets.xs + 2,
            runSpacing: Insets.xs + 2,
            children: [
              const CapabilityChip(
                key: Key('ai-cap-text'),
                label: 'Text',
                supported: true,
                tooltip: 'Pasted text, notes, .txt/.md/.docx files',
              ),
              CapabilityChip(
                key: const Key('ai-cap-pdf'),
                label: 'PDF',
                supported: c.pdf,
              ),
              CapabilityChip(
                key: const Key('ai-cap-image'),
                label: 'Images',
                supported: c.image,
              ),
              CapabilityChip(
                key: const Key('ai-cap-audio'),
                label: 'Audio',
                supported: c.audio,
              ),
              CapabilityChip(
                key: const Key('ai-cap-video'),
                label: 'Video',
                supported: c.video,
              ),
              CapabilityChip(
                key: const Key('ai-cap-youtube'),
                label: 'YouTube',
                supported: c.youtube,
                tooltip: c.youtubeNative
                    ? 'The video itself is sent to the model'
                    : c.youtube
                    ? 'Uses the video transcript'
                    : 'Not available here (YouTube blocks transcripts on '
                          'the web)',
              ),
            ],
          ),
      ],
    );
  }
}

class _OverrideToggle extends StatelessWidget {
  const _OverrideToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value,
    onChanged: onChanged,
  );
}

class _ModelField extends StatelessWidget {
  const _ModelField({
    required this.controller,
    required this.focusNode,
    required this.models,
    required this.defaultModel,
    required this.loading,
    required this.error,
    required this.onLoad,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String>? models;
  final String defaultModel;
  final bool loading;
  final String? error;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final options = models ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => RawAutocomplete<String>(
            textEditingController: controller,
            focusNode: focusNode,
            optionsBuilder: (value) {
              final q = value.text.trim().toLowerCase();
              if (options.isEmpty) return const Iterable<String>.empty();
              return q.isEmpty
                  ? options
                  : options.where((m) => m.toLowerCase().contains(q));
            },
            fieldViewBuilder: (context, textController, focusNode, onSubmit) =>
                TextFormField(
                  key: const Key('ai-model'),
                  controller: textController,
                  focusNode: focusNode,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Model',
                    hintText: defaultModel,
                    helperText: models == null
                        ? 'Leave empty for $defaultModel, or load the list'
                        : '${options.length} models available — type to '
                              'filter',
                    suffixIcon: loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            key: const Key('ai-load-models'),
                            tooltip: 'Load available models',
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: onLoad,
                          ),
                  ),
                  onFieldSubmitted: (_) => onSubmit(),
                ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 280,
                    maxWidth: constraints.maxWidth,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final m = options.elementAt(i);
                      return ListTile(
                        dense: true,
                        title: Text(m),
                        onTap: () => onSelected(m),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.of(context).danger),
            ),
          ),
      ],
    );
  }
}

class _WebKeyWarning extends StatelessWidget {
  const _WebKeyWarning();

  @override
  Widget build(BuildContext context) => const InfoBanner(
    icon: Icons.shield_outlined,
    message:
        "On the web, keys are kept in this browser's storage, which is less "
        'protected than the system keychain on desktop and mobile. Remove the '
        'key when using a shared computer.',
  );
}
