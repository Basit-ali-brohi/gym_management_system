import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({http.Client? httpClient, required this.baseUrl})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? token,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final res = await _http.get(uri, headers: _headers(token));
    return _decode(res);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    String? token,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _http.post(uri, headers: _headers(token), body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    String? token,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _http.delete(uri, headers: _headers(token), body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    String? token,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _http.patch(uri, headers: _headers(token), body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    String? token,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _http.put(uri, headers: _headers(token), body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<Uint8List> getBytes(
    String path, {
    String? token,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final res = await _http.get(uri, headers: _headers(token));
    if (res.statusCode >= 400) {
      final text = res.body;
      try {
        final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          final error = decoded['error']?.toString() ?? 'request_failed';
          throw ApiException(error, statusCode: res.statusCode);
        }
      } catch (_) {
        throw ApiException('request_failed', statusCode: res.statusCode);
      }
      throw ApiException('request_failed', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  Map<String, String> _headers(String? token) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response res) {
    final bodyText = res.body;
    final decoded = bodyText.isEmpty ? <String, dynamic>{} : jsonDecode(bodyText);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('invalid_response', statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      final error = decoded['error']?.toString() ?? 'request_failed';
      throw ApiException(error, statusCode: res.statusCode);
    }
    return decoded;
  }
}
