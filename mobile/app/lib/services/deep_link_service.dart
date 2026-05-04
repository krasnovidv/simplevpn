import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import '../models/vpn_config.dart';
import 'event_log.dart';

class DeepLinkService {
  final _log = EventLog();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  final _controller = StreamController<VpnConfig>.broadcast();

  Stream<VpnConfig> get configStream => _controller.stream;

  Future<VpnConfig?> getInitialConfig() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri == null) return null;
      _log.debug('Deep link initial: $uri');
      return _parseUri(uri);
    } catch (e) {
      _log.error('Deep link initial error: $e');
      return null;
    }
  }

  void startListening() {
    _sub = _appLinks.uriLinkStream.listen((uri) {
      _log.debug('Deep link stream: $uri');
      final config = _parseUri(uri);
      if (config != null) {
        _controller.add(config);
      }
    }, onError: (e) {
      _log.error('Deep link stream error: $e');
    });
    _log.debug('Deep link listener started');
  }

  VpnConfig? _parseUri(Uri uri) {
    // simplevpn://connect/BASE64URL_CONFIG
    if (uri.scheme != 'simplevpn' || uri.host != 'connect') {
      _log.debug('Deep link ignored: scheme=${uri.scheme}, host=${uri.host}');
      return null;
    }

    final path = uri.path;
    if (path.isEmpty || path == '/') {
      _log.error('Deep link missing payload');
      return null;
    }

    // Remove leading slash
    final payload = path.startsWith('/') ? path.substring(1) : path;
    try {
      final json = _base64UrlDecode(payload);
      _log.debug('Deep link decoded: ${_maskJson(json)}');
      return VpnConfig.fromJson(json);
    } catch (e) {
      _log.error('Deep link decode error: $e');
      return null;
    }
  }

  String _base64UrlDecode(String input) {
    // RFC 4648 base64url: replace -_ back to +/, add padding
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

  String _maskJson(String json) {
    try {
      var masked = json;
      masked = masked.replaceAllMapped(
        RegExp(r'"server_key"\s*:\s*"([^"]*)"'),
        (m) {
          final key = m.group(1) ?? '';
          final shown = key.length > 4 ? '${key.substring(0, 4)}...' : key;
          return '"server_key":"$shown"';
        },
      );
      masked = masked.replaceAllMapped(
        RegExp(r'"password"\s*:\s*"([^"]*)"'),
        (m) => '"password":"***"',
      );
      return masked;
    } catch (_) {
      return '<unparseable>';
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

String encodeConfigToBase64Url(String json) {
  final bytes = utf8.encode(json);
  var encoded = base64.encode(bytes);
  encoded = encoded.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  return encoded;
}
