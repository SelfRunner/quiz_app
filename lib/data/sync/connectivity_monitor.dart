import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// Coarse online/offline signal. "Online" only means a network interface is
/// up; requests can still fail (handled as network errors).
abstract interface class ConnectivityMonitor {
  Future<bool> isOnline();

  /// Emits on changes (not necessarily distinct).
  Stream<bool> get onChanged;
}

/// [ConnectivityMonitor] backed by `connectivity_plus`.
class ConnectivityPlusMonitor implements ConnectivityMonitor {
  ConnectivityPlusMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      return _online(await _connectivity.checkConnectivity());
    } catch (_) {
      return true; // Unknown: let requests decide.
    }
  }

  @override
  Stream<bool> get onChanged => _connectivity.onConnectivityChanged
      .map(_online)
      .handleError((Object _) {});
}

/// Always-online monitor (tests, platforms without connectivity support).
class AlwaysOnlineMonitor implements ConnectivityMonitor {
  const AlwaysOnlineMonitor();

  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> get onChanged => const Stream.empty();
}

/// Emits `true` when the app is resumed/shown and `false` when it is
/// hidden/paused. Uses [AppLifecycleListener]; the listener is disposed when
/// the subscription is cancelled.
Stream<bool> appForegroundChanges() {
  AppLifecycleListener? listener;
  late final StreamController<bool> controller;
  controller = StreamController<bool>(
    onListen: () {
      listener = AppLifecycleListener(
        onResume: () => controller.add(true),
        onShow: () => controller.add(true),
        onHide: () => controller.add(false),
        onPause: () => controller.add(false),
      );
    },
    onCancel: () {
      listener?.dispose();
      listener = null;
    },
  );
  return controller.stream;
}
