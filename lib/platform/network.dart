import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// Whether the dictionary is reachable at all. Everything already downloaded
/// keeps working either way.
class NetworkStatus extends ChangeNotifier {
  var _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get online => _online;

  Future<void> start() async {
    _apply(await Connectivity().checkConnectivity());
    _sub = Connectivity().onConnectivityChanged.listen(_apply);
  }

  @visibleForTesting
  void goOffline() {
    _online = false;
    notifyListeners();
  }

  void _apply(List<ConnectivityResult> results) {
    final next = results.any((r) => r != ConnectivityResult.none);
    if (next == _online) return;
    _online = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class NetworkScope extends InheritedNotifier<NetworkStatus> {
  const NetworkScope({
    required NetworkStatus super.notifier,
    required super.child,
    super.key,
  });

  static bool online(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NetworkScope>()
          ?.notifier
          ?.online ??
      true;
}
