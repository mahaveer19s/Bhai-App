import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage/local_storage.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;

  static String get _baseUrl {
    try {
      final custom = LocalStorage().customApiUrl;
      if (custom != null && custom.trim().isNotEmpty) {
        return custom.trim();
      }
    } catch (_) {}

    const envUrl = String.fromEnvironment('BHAI_API_URL');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      return 'http://$host:8000';
    }
    return 'http://10.140.120.82:8000';
  }

  Future<dynamic> get(String path) => _request('GET', path);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _request('POST', path, body);
  Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _request('PUT', path, body);
  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) => _request('PATCH', path, body);
  Future<dynamic> delete(String path) => _request('DELETE', path);

  static const _defaultToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI3ODJhODYwYy04Y2M2LTQwNDEtOTE2MS01MWI4MDhlMjdjNmEiLCJyb2xlIjoiVVNFUiIsImV4cCI6MTc5MTMwODYzN30.Jaee0J-nFW-jNRMvM9myuPk-YyNC2rwC_ghE-3R1_eg';

  Future<dynamic> _request(String method, String path, [Map<String, dynamic>? body]) async {
    final token = await LocalStorage().getToken();
    final effectiveToken = (token != null && token.isNotEmpty && token != 'demo_token') ? token : _defaultToken;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $effectiveToken',
    };
    final uri = Uri.parse('$_baseUrl$path');
    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));
        case 'POST':
          response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 4));
        case 'PUT':
          response = await http.put(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 4));
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 4));
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 4));
        default:
          throw StateError('Unsupported HTTP method $method');
      }
    } catch (_) {
      throw ApiException('BHAI could not reach the safety server. Your emergency will remain queued on this device.');
    }
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = response.body;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(detail?.toString() ?? 'The safety server rejected this request.', statusCode: response.statusCode);
    }
    return decoded;
  }
}
