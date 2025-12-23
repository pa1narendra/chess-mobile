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

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');

    if (_token != null) {
      // Verify token
      final result = await ApiService.getMe(_token!);
      if (result['status'] == 'success' && result['data'] != null) {
        _user = result['data'];
        _isAuthenticated = true;
      } else {
        await prefs.remove('token');
        _token = null;
        _isAuthenticated = false;
      }
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    try {
      final result = await ApiService.login(email, password);
      if (result['success'] == true || result['token'] != null) {
        final token = result['token'];
        final user = result['user'];
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        
        _token = token;
        _user = user;
        _isAuthenticated = true;
        notifyListeners();
      } else {
        throw Exception(result['message'] ?? 'Login failed');
      }
    } catch (e) {
      rethrow;
    }
  }
  
  Future<void> register(String username, String email, String password) async {
     try {
       await ApiService.register(username, email, password);
       // Auto login after register or just return?
       // Usually we might want to auto-login.
       await login(email, password);
     } catch (e) {
       rethrow;
     }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _token = null;
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
