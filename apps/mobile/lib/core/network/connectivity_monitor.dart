import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ConnectivityMonitor {
  Future<bool> get isConnected;

  Stream<bool> get changes;
}

final connectivityMonitorProvider = Provider<ConnectivityMonitor>(
  (ref) => PlatformConnectivityMonitor(Connectivity()),
);

class PlatformConnectivityMonitor implements ConnectivityMonitor {
  PlatformConnectivityMonitor(this._connectivity);

  final Connectivity _connectivity;

  @override
  Future<bool> get isConnected async =>
      _hasConnection(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_hasConnection).distinct();

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
