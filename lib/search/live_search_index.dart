import 'dart:async';

import 'search_index.dart';
import 'search_models.dart';

/// A [SearchIndex] kept up to date from repository streams.
///
/// Each [attach]ed source emits full lists (as the repositories' `watch*`
/// streams do); the list is diffed against the previous one (by id, then
/// `identical` / `==`) and only changed items are re-indexed, removed ones
/// dropped. [revisions] emits after every effective change once every
/// source has emitted at least once ([isReady]).
class LiveSearchIndex {
  LiveSearchIndex({SearchIndex? index}) : index = index ?? SearchIndex();

  final SearchIndex index;
  final StreamController<int> _changes = StreamController<int>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  final Set<Object> _waiting = {};
  int _revision = 0;
  bool _disposed = false;

  int get revision => _revision;

  /// Every attached source has delivered its first list.
  bool get isReady => _waiting.isEmpty;

  /// Current revision on listen (when ready) and after each change.
  Stream<int> get revisions => Stream<int>.multi((controller) {
    if (isReady) controller.add(_revision);
    final sub = _changes.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });

  /// Indexes the items of [source] as [type] documents.
  /// [onList] sees every emitted list first (e.g. to update
  /// [SearchIndex.archivedSubjectIds]); return true from it to force a new
  /// revision even when no document changed.
  void attach<T>({
    required SearchItemType type,
    required Stream<List<T>> source,
    required String Function(T item) id,
    required SearchDocument Function(T item) toDocument,
    bool Function(List<T> items)? onList,
  }) {
    if (_disposed) return;
    final token = Object();
    _waiting.add(token);
    var previous = <String, T>{};
    _subs.add(
      source.listen(
        (items) {
          if (_disposed) return;
          var changed = onList?.call(items) ?? false;
          final next = <String, T>{};
          for (final item in items) {
            final key = id(item);
            next[key] = item;
            final old = previous[key];
            if (old != null && (identical(old, item) || old == item)) continue;
            index.upsert(toDocument(item));
            changed = true;
          }
          for (final key in previous.keys) {
            if (!next.containsKey(key)) {
              index.remove(type, key);
              changed = true;
            }
          }
          previous = next;
          final becameReady = _waiting.remove(token) && _waiting.isEmpty;
          if (changed || becameReady) _bump();
        },
        // A failing source keeps its last indexed state.
        onError: (Object _, StackTrace _) {
          if (_waiting.remove(token) && _waiting.isEmpty) _bump();
        },
      ),
    );
  }

  /// Forces a new revision (e.g. after changing [SearchIndex] settings
  /// such as `archivedSubjectIds` directly).
  void bump() => _bump();

  void _bump() {
    _revision++;
    if (isReady && !_changes.isClosed) _changes.add(_revision);
  }

  List<SearchResult> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    int limit = 50,
    DateTime? now,
  }) => index.search(query, filters: filters, limit: limit, now: now);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _changes.close();
  }
}
