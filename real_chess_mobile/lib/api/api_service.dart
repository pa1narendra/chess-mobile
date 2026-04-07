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
  // --- Game History ---
  static Future<Map<String, dynamic>> clearGameHistory(String token) async {
    final url = '$baseUrl/api/games/history';
    try {
      final response = await http.delete(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      throw ApiException('Failed to clear history', statusCode: response.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to clear history');
    }
  }

  static Future<Map<String, dynamic>> getGameAnalysis(String gameId) async {
    final url = '$baseUrl/api/games/$gameId/analysis';
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      throw ApiException('Analysis not available', statusCode: response.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to fetch analysis');
    }
  }

  static Future<Map<String, dynamic>> getGameHistory(String token, {int page = 1, int pageSize = 20}) async {
    final url = '$baseUrl/api/games/history?page=$page&pageSize=$pageSize';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      throw ApiException('Failed to fetch game history', statusCode: response.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to fetch game history');
    }
  }

  static Future<Map<String, dynamic>> getGameDetails(String gameId) async {
    final url = '$baseUrl/api/games/$gameId/details';
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      throw ApiException('Game not found', statusCode: response.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to fetch game details');
    }
  }

  // --- Leaderboard ---
  static Future<Map<String, dynamic>> getLeaderboard({int page = 1, int pageSize = 20}) async {
    final url = '$baseUrl/api/leaderboard?page=$page&pageSize=$pageSize';
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      throw ApiException('Failed to fetch leaderboard', statusCode: response.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to fetch leaderboard');
    }
  }

  // --- User Profile ---
  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final url = '$baseUrl/api/users/$userId/profile';
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      throw ApiException('User not found', statusCode: response.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to fetch profile');
    }
  }

  static Future<Map<String, dynamic>> updateProfile(String token, Map<String, dynamic> updates) async {
    final url = '$baseUrl/api/users/profile';
    try {
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(updates),
      ).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      throw ApiException('Failed to update profile', statusCode: response.statusCode);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to update profile');
    }
  }

  static Future<Map<String, dynamic>> analyzeGame(String gameId, String token) async {
    final url = '$baseUrl/api/games/$gameId/analyze';
    _log('Request: POST $url');

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 60)); // Analysis takes time

      _log('Response Status: ${response.statusCode}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        throw ApiException('Failed to analyze game', statusCode: response.statusCode);
      }
    } catch (e) {
      _log('Error: $e');
      if (e is ApiException) rethrow;
      throw ApiException('Analysis request failed');
    }
  }
}

