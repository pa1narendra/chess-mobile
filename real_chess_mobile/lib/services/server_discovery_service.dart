import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import '../utils/config.dart';

/// Discovers the backend server on the local network by probing IPs.
///
/// Strategy:
/// 1. Try the cached IP first (very fast — single request).
/// 2. If that fails, get the device's WiFi IP, extract subnet, probe all 254 IPs in parallel.
/// 3. First IP responding to /health wins.
class ServerDiscoveryService {
  static const int _port = 8080;
  static const Duration _probeTimeout = Duration(milliseconds: 600);

  /// Returns a working server IP, or null if none found.
  /// Updates Config.setServerIp() on success.
  static Future<String?> discover() async {
    // 1. Try the currently configured IP first
    final cachedIp = Config.serverIp;
    if (await _probe(cachedIp)) {
      debugPrint('[Discovery] Cached IP $cachedIp works');
      return cachedIp;
    }

    // On web, don't run a full subnet scan — browsers rate-limit and DevTools
    // gets flooded. Try a small list of common dev IPs instead.
    if (kIsWeb) {
      debugPrint('[Discovery] Web: trying common dev IPs only');
      for (final ip in ['localhost', '127.0.0.1', '192.168.1.103', '192.168.1.115']) {
        if (await _probe(ip)) {
          await Config.setServerIp(ip);
          return ip;
        }
      }
      return null;
    }

    debugPrint('[Discovery] Cached IP $cachedIp failed, scanning network...');

    // 2. Get device's WiFi IP to figure out the subnet
    String? deviceIp;
    try {
      deviceIp = await NetworkInfo().getWifiIP();
    } catch (e) {
      debugPrint('[Discovery] Could not get WiFi IP: $e');
    }

    if (deviceIp == null) {
      debugPrint('[Discovery] No WiFi IP, falling back to common subnets');
      // Try common subnets when WiFi info is unavailable (e.g., emulator)
      for (final subnet in ['192.168.1.', '192.168.0.', '10.0.0.']) {
        final found = await _scanSubnet(subnet);
        if (found != null) {
          await Config.setServerIp(found);
          return found;
        }
      }
      return null;
    }

    final parts = deviceIp.split('.');
    if (parts.length != 4) return null;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.';
    debugPrint('[Discovery] Scanning subnet $subnet*');

    final found = await _scanSubnet(subnet);
    if (found != null) {
      await Config.setServerIp(found);
      debugPrint('[Discovery] Found server at $found');
      return found;
    }

    debugPrint('[Discovery] No server found on $subnet*');
    return null;
  }

  /// Probes all IPs in a /24 subnet in parallel. Returns the first responder.
  static Future<String?> _scanSubnet(String subnetPrefix) async {
    final completer = Completer<String?>();
    final futures = <Future<void>>[];

    for (int i = 1; i <= 254; i++) {
      final ip = '$subnetPrefix$i';
      futures.add(_probe(ip).then((works) {
        if (works && !completer.isCompleted) {
          completer.complete(ip);
        }
      }));
    }

    // Wait for either a successful probe OR all probes to finish
    Future.wait(futures).then((_) {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  /// Returns true if the IP responds to /health within the timeout.
  static Future<bool> _probe(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip:$_port/health'))
          .timeout(_probeTimeout);
      return response.statusCode == 200 && response.body.contains('"status":"ok"');
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
