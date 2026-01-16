import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  final _statusController = StreamController<bool>.broadcast();

  bool get isOnline => _isOnline;
  Stream<bool> get onStatusChange => _statusController.stream;

  Future<void> initialize() async {
    // Check initial connectivity
    final results = await _connectivity.checkConnectivity();
    _isOnline = _hasConnectivity(results);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = _hasConnectivity(results);

      if (wasOnline != _isOnline) {
        _statusController.add(_isOnline);
      }
    });
  }

  bool _hasConnectivity(List<ConnectivityResult> results) {
    return results.isNotEmpty &&
        !results.contains(ConnectivityResult.none) &&
        (results.contains(ConnectivityResult.wifi) ||
            results.contains(ConnectivityResult.mobile) ||
            results.contains(ConnectivityResult.ethernet));
  }

  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = _hasConnectivity(results);
    return _isOnline;
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
