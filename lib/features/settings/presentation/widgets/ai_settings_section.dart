import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../ai/ai_providers.dart';
import '../../../../ai/base_url_policy.dart';
import '../../../../ai/llm_provider.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/error_message.dart';
import '../../../../data/data_providers.dart';

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

/// AI provider configuration: active provider, API key (device-only), model,
/// and base URL / headers for OpenAI-compatible endpoints.
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

  @override
  void initState() {
    super.initState();
    for (final c in [_apiKey, _model, _baseUrl, _headers]) {
      c.addListener(_markDirty);
    }
    unawaited(_init());
  }

  @override
  void dispose() {
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
      final configured = await store.configuredProviders();
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _hasStoredKey = key.isNotEmpty;
        _dirty = false;
      });
      showAppSnackBar(context, '${p.displayName} settings saved');
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

  Future<void> _clearAll() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove all saved keys?',
      message:
          'All API keys and AI settings saved for your account on this '
          'device are deleted. Keys of other accounts are not affected.',
      confirmLabel: 'Remove all',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    try {
      await ref.read(apiKeyStoreProvider).clearForUser(userId);
      if (!mounted) return;
      showAppSnackBar(context, 'All saved keys removed');
      await _init();
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
    final theme = Theme.of(context);
    final p = _provider;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KeyPrivacyNote(isWeb: kIsWeb),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: const Key('ai-provider'),
            child: DropdownButtonFormField<LlmProviderId>(
              // Re-created on provider change so it reflects _provider.
              key: ValueKey(p),
              initialValue: p,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Provider used for generation',
                prefixIcon: Icon(Icons.auto_awesome_outlined),
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
                            color: theme.colorScheme.primary,
                            semanticLabel: 'Key saved',
                          ),
                      ],
                    ),
                  ),
              ],
              onChanged: _loading || _saving ? null : _selectProvider,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
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
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key('ai-api-key-visibility'),
                      tooltip: _obscureKey ? 'Show key' : 'Hide key',
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                    if (_hasStoredKey)
                      IconButton(
                        key: const Key('ai-api-key-clear'),
                        tooltip: 'Remove saved key',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _clearKey,
                      ),
                  ],
                ),
              ),
            ),
            if (p.requiresBaseUrl) ...[
              const SizedBox(height: 16),
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
                  prefixIcon: const Icon(Icons.link),
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => baseUrlProblem(v ?? ''),
              ),
              const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            _ModelField(
              controller: _model,
              focusNode: _modelFocus,
              models: _models,
              defaultModel: p.defaultModel,
              loading: _loadingModels,
              error: _modelsError,
              onLoad: _loadModels,
            ),
            const SizedBox(height: 16),
            if (_testMessage != null) ...[
              _TestResult(
                ok: _testState == _TestState.ok,
                message: _testMessage!,
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
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
                      : const Icon(Icons.network_check),
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
                      : const Icon(Icons.save_outlined),
                  label: Text(_dirty ? 'Save' : 'Saved'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('ai-clear-all'),
                onPressed: _saving ? null : _clearAll,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Remove all saved keys'),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
                    prefixIcon: const Icon(Icons.memory),
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
                            icon: const Icon(Icons.refresh),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _TestResult extends StatelessWidget {
  const _TestResult({required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = ok ? scheme.primaryContainer : scheme.errorContainer;
    final fg = ok ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    return Container(
      key: const Key('ai-test-result'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: fg)),
          ),
        ],
      ),
    );
  }
}

class _KeyPrivacyNote extends StatelessWidget {
  const _KeyPrivacyNote({required this.isWeb});

  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bring your own API key. Keys are stored only on this device '
              '(never uploaded to your account) and are sent directly to the '
              'provider you choose.'
              '${isWeb ? '\n\nOn the web, keys are kept in this browser\'s '
                        'storage, which is less protected than the system '
                        'keychain on desktop and mobile. Remove the key when '
                        'using a shared computer.' : ''}',
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
