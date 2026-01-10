import 'package:shared_preferences/shared_preferences.dart';

class Config {
  static String? _serverIp;
  // Use 10.0.2.2 for Android emulator (maps to host localhost)
  // Use localhost for web or iOS simulator
  // Users on physical devices need to configure their server IP
  static const String _defaultIp = "10.0.2.2";
  static const int _port = 8080;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = prefs.getString('server_ip') ?? _defaultIp;
  }

  static Future<void> setServerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
    _serverIp = ip;
  }

  static String get serverIp => _serverIp ?? _defaultIp;

  static String get baseUrl => 'http://$serverIp:$_port';
  static String get wsUrl => 'ws://$serverIp:$_port/ws';
}
