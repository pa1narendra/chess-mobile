import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isInitialized = false;
  bool _isAuthenticated = false;
  String? _token;
  Map<String, dynamic>? _user;

  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;

  // Callback to disconnect socket on logout
  VoidCallback? onLogout;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');

      if (_token != null && _token!.isNotEmpty) {
        // Verify token
        try {
          final result = await ApiService.getMe(_token!);
          // Backend returns user object directly from /auth/me
          if (result['_id'] != null || result['username'] != null) {
            _user = result;
            _isAuthenticated = true;
          } else {
             // Response valid but data missing? Rare constraint.
             // Keep authenticated but maybe without user details for now
             _isAuthenticated = true;
          }
        } catch (e) {
          // Only clear session if we KNOW the token is invalid (401)
          if (e is ApiException && e.statusCode == 401) {
             print('[Auth] Token expired or invalid (401). Clearing session.');
             await _clearSession(prefs);
          } else {
             print('[Auth] Verification failed ($e) but keeping session. Offline/Network issue?');
             // Assume token is valid for now to avoid logging out user on network glitch
             _isAuthenticated = true;
          }
        }
      }
    } catch (e) {
      // SharedPreferences error - continue without auth
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove('token');
    _token = null;
    _isAuthenticated = false;
    _user = null;
  }

  Future<void> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      throw ApiException('Username and password are required');
    }

    final result = await ApiService.login(username, password);

    // Validate response has token
    final token = result['token'];
    if (token == null || token is! String || token.isEmpty) {
      throw ApiException('Invalid login response');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);

    _token = token;
    _user = result['user'];
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> register(String username, String email, String password) async {
    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      throw ApiException('All fields are required');
    }

    await ApiService.register(username, email, password);
    // Auto login after register
    await login(username, password);
  }

  Future<void> logout() async {
    // Notify any listeners to disconnect (e.g., socket)
    onLogout?.call();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _token = null;
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
