import 'dart:convert';
import '../models/vpn_config.dart';
import '../services/deep_link_service.dart' show encodeConfigToBase64Url;

/// Raised when an imported config (QR / link / pasted text) can't be turned
/// into a valid [VpnConfig]. The message is human-readable Russian, safe to
/// show directly to the user (never contains secrets).
class ConfigImportException implements Exception {
  final String message;
  ConfigImportException(this.message);
  @override
  String toString() => message;
}

/// Parses any supported config payload into a [VpnConfig], or throws a
/// [ConfigImportException] with a human-readable reason.
///
/// Accepts:
///  * raw JSON `{"server":...}`
///  * deep link `simplevpn://connect/<base64url>`
///  * join link `http(s)://host[:port]/join#<base64url>`
VpnConfig parseImportedConfig(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw ConfigImportException('Пустой код или ссылка');
  }

  final String jsonStr;
  if (text.startsWith('{')) {
    jsonStr = text;
  } else {
    final payload = _extractPayload(text);
    if (payload == null) {
      throw ConfigImportException('Неизвестный формат ссылки или кода');
    }
    try {
      jsonStr = _base64UrlDecode(payload);
    } catch (_) {
      throw ConfigImportException('Не удалось декодировать конфигурацию');
    }
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(jsonStr);
  } on FormatException {
    throw ConfigImportException('Неверный формат: это не похоже на конфигурацию');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ConfigImportException('Неверный формат конфигурации');
  }

  return configFromMap(decoded);
}

/// Validates a decoded config map and builds a [VpnConfig], throwing a
/// [ConfigImportException] with a human-readable reason on any problem.
VpnConfig configFromMap(Map<String, dynamic> map) {
  String require(String key, String label) {
    final v = map[key];
    if (v == null || (v is String && v.trim().isEmpty)) {
      throw ConfigImportException('Отсутствует поле: $label');
    }
    if (v is! String) {
      throw ConfigImportException('Неверное значение поля: $label');
    }
    return v;
  }

  final server = require('server', 'сервер').trim();
  _validateServerHostPort(server);
  final serverKey = require('server_key', 'ключ сервера');
  final username = require('username', 'логин');
  final password = require('password', 'пароль');

  return VpnConfig(
    server: server,
    serverKey: serverKey,
    username: username,
    password: password,
    sni: (map['sni'] as String?) ?? '',
    skipVerify: (map['skip_verify'] as bool?) ?? false,
    transport: (map['transport'] as String?) ?? '',
    fingerprint: (map['fingerprint'] as String?) ?? '',
  );
}

/// Builds the universal join link for a config JSON, e.g.
/// `http://<host>:8080/join#<base64url>`. [host] is the bare server host
/// (no port). Scannable by any camera and decodable offline by the in-app
/// scanner — unlike raw JSON, it neither leaks the password in plaintext nor
/// confuses a generic QR reader.
String buildJoinLink(String configJson, String host) {
  final encoded = encodeConfigToBase64Url(configJson);
  return 'http://$host:8080/join#$encoded';
}

// Lenient host:port check — accepts both IPv4 and domain hosts (sni mode),
// only insisting on a host and a valid port so we don't reject valid configs.
void _validateServerHostPort(String server) {
  final colon = server.lastIndexOf(':');
  if (colon <= 0 || colon == server.length - 1) {
    throw ConfigImportException('Сервер должен быть в формате host:port');
  }
  final host = server.substring(0, colon);
  final portStr = server.substring(colon + 1);
  if (host.trim().isEmpty) {
    throw ConfigImportException('Не указан адрес сервера');
  }
  final port = int.tryParse(portStr);
  if (port == null || port < 1 || port > 65535) {
    throw ConfigImportException('Неверный порт сервера (1–65535)');
  }
}

String? _extractPayload(String text) {
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme == 'simplevpn' && uri.host == 'connect') {
    final p = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return p.isEmpty ? null : p;
  }
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    if (uri.fragment.isNotEmpty) return uri.fragment;
  }
  return null;
}

String _base64UrlDecode(String input) {
  var s = input.replaceAll('-', '+').replaceAll('_', '/');
  switch (s.length % 4) {
    case 2:
      s += '==';
      break;
    case 3:
      s += '=';
      break;
  }
  return utf8.decode(base64.decode(s));
}
