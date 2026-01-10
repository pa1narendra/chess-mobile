import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../utils/config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static const Duration _timeout = Duration(seconds: 30);

  static String get baseUrl => Config.baseUrl;

  static void _log(String message) {
    print('[API] $message');
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final url = '$baseUrl/auth/login';
    final bodyData = {'username': username, 'password': password};
    
    _log('Request: POST $url');
    _log('Body: $bodyData');

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyData),
      ).timeout(_timeout);

      _log('Response Status: ${response.statusCode}');
      _log('Response Body: ${response.body}');

      final body = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      } else {
        final message = body['error'] ?? 'Login failed';
        throw ApiException(message, statusCode: response.statusCode);
      }
    } on TimeoutException {
      _log('Error: Connection timed out');
      throw ApiException('Connection timed out. Please check your network.');
    } on FormatException {
      _log('Error: Invalid response format');
      throw ApiException('Invalid response from server');
    } catch (e) {
      _log('Error: $e');
      if (e is ApiException) rethrow;
      throw ApiException('Connection error. Please check your network.');
    }
  }

  static Future<Map<String, dynamic>> register(String username, String email, String password) async {
    final url = '$baseUrl/auth/register';
    final bodyData = {'username': username, 'email': email, 'password': password};

    _log('Request: POST $url');
    _log('Body: $bodyData');

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyData),
      ).timeout(_timeout);

      _log('Response Status: ${response.statusCode}');
      _log('Response Body: ${response.body}');

      final body = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      } else {
        final message = body['error'] ?? 'Registration failed';
        throw ApiException(message, statusCode: response.statusCode);
      }
    } on TimeoutException {
      _log('Error: Connection timed out');
      throw ApiException('Connection timed out. Please check your network.');
    } on FormatException {
      _log('Error: Invalid response format');
      throw ApiException('Invalid response from server');
    } catch (e) {
      _log('Error: $e');
      if (e is ApiException) rethrow;
      throw ApiException('Connection error. Please check your network.');
    }
  }

  static Future<Map<String, dynamic>> getMe(String token) async {
    final url = '$baseUrl/auth/me';
    _log('Request: GET $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);

      _log('Response Status: ${response.statusCode}');
      _log('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        throw ApiException('Failed to get user info', statusCode: response.statusCode);
      }
    } on TimeoutException {
       _log('Error: Connection timed out');
      throw ApiException('Connection timed out');
    } catch (e) {
      _log('Error: $e');
      if (e is ApiException) rethrow;
      throw ApiException('Failed to verify session');
    }
  }
}

