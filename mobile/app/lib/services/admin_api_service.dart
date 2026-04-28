import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/admin_models.dart';

const _keyAdminUrl = 'admin_url';
const _keyAdminToken = 'admin_token';
const _keyAdminSkipVerify = 'admin_skip_verify';

class AdminApiException implements Exception {
  final int statusCode;
  final String message;
  const AdminApiException(this.statusCode, this.message);

  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

class AdminApiService {
  final _storage = const FlutterSecureStorage();

  Future<http.Client> _buildClient() async {
    final skipVerifyStr = await _storage.read(key: _keyAdminSkipVerify);
    final skipVerify = skipVerifyStr == 'true';

    if (skipVerify) {
      final ioClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      return IOClient(ioClient);
    }
    return http.Client();
  }

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: _keyAdminToken) ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<String> _baseUrl() async {
    final url = await _storage.read(key: _keyAdminUrl) ?? '';
    return url.replaceAll(RegExp(r'/$'), '');
  }

  Future<dynamic> _get(String path) async {
    final client = await _buildClient();
    try {
      final base = await _baseUrl();
      final headers = await _headers();
      final uri = Uri.parse('$base$path');
      final resp = await client.get(uri, headers: headers);
      _checkStatus(resp);
      return jsonDecode(resp.body);
    } finally {
      client.close();
    }
  }

  Future<dynamic> _post(String path, [Object? body]) async {
    final client = await _buildClient();
    try {
      final base = await _baseUrl();
      final headers = await _headers();
      final uri = Uri.parse('$base$path');
      final resp = await client.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
      _checkStatus(resp);
      return jsonDecode(resp.body);
    } finally {
      client.close();
    }
  }

  Future<dynamic> _delete(String path) async {
    final client = await _buildClient();
    try {
      final base = await _baseUrl();
      final headers = await _headers();
      final uri = Uri.parse('$base$path');
      final resp = await client.delete(uri, headers: headers);
      _checkStatus(resp);
      return jsonDecode(resp.body);
    } finally {
      client.close();
    }
  }

  Future<dynamic> _put(String path, Object body) async {
    final client = await _buildClient();
    try {
      final base = await _baseUrl();
      final headers = await _headers();
      final uri = Uri.parse('$base$path');
      final resp = await client.put(uri, headers: headers, body: jsonEncode(body));
      _checkStatus(resp);
      return jsonDecode(resp.body);
    } finally {
      client.close();
    }
  }

  void _checkStatus(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    String message = resp.body;
    try {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      message = decoded['error'] as String? ?? message;
    } catch (_) {}
    throw AdminApiException(resp.statusCode, message);
  }

  // -- Settings helpers --

  Future<void> saveSettings({
    required String url,
    required String token,
    required bool skipVerify,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAdminUrl, value: url),
      _storage.write(key: _keyAdminToken, value: token),
      _storage.write(key: _keyAdminSkipVerify, value: skipVerify ? 'true' : 'false'),
    ]);
  }

  Future<({String url, String token, bool skipVerify})> loadSettings() async {
    final results = await Future.wait([
      _storage.read(key: _keyAdminUrl),
      _storage.read(key: _keyAdminToken),
      _storage.read(key: _keyAdminSkipVerify),
    ]);
    return (
      url: results[0] ?? '',
      token: results[1] ?? '',
      skipVerify: results[2] == 'true',
    );
  }

  Future<bool> isConfigured() async {
    final settings = await loadSettings();
    return settings.url.isNotEmpty && settings.token.isNotEmpty;
  }

  // -- Server status --

  Future<AdminStatus> getStatus() async {
    final data = await _get('/api/status') as Map<String, dynamic>;
    return AdminStatus.fromJson(data);
  }

  // -- Users --

  Future<List<AdminUser>> listUsers() async {
    final data = await _get('/api/users') as Map<String, dynamic>;
    final list = data['users'] as List<dynamic>? ?? [];
    return list.map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createUser(String username, String password) async {
    await _post('/api/users', {'username': username, 'password': password});
  }

  Future<void> deleteUser(String username) async {
    await _delete('/api/users/$username');
  }

  Future<void> updatePassword(String username, String password) async {
    await _put('/api/users/$username/password', {'password': password});
  }

  Future<void> disable(String username) async {
    await _post('/api/users/$username/disable');
  }

  Future<void> enable(String username) async {
    await _post('/api/users/$username/enable');
  }

  // -- Connected clients --

  Future<List<ConnectedClient>> listClients() async {
    final data = await _get('/api/clients') as Map<String, dynamic>;
    final list = data['clients'] as List<dynamic>? ?? [];
    return list.map((e) => ConnectedClient.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> disconnectClient(String id) async {
    await _post('/api/clients/$id/disconnect');
  }
}
