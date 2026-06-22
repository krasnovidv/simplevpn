import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import '../models/vpn_config.dart';
import '../utils/config_import.dart';
import 'event_log.dart';

class DeepLinkService {
  final _log = EventLog();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  final _controller = StreamController<VpnConfig>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<VpnConfig> get configStream => _controller.stream;

  /// Human-readable import errors (bad/incomplete config in a deep link), so
  /// the UI can show why an import silently did nothing before.
  Stream<String> get errorStream => _errorController.stream;

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

    if (uri.path.isEmpty || uri.path == '/') {
      _log.error('Deep link missing payload');
      _errorController.add('Ссылка не содержит конфигурации');
      return null;
    }

    try {
      final config = parseImportedConfig(uri.toString());
      _log.debug('Deep link imported: server=${config.server}');
      return config;
    } on ConfigImportException catch (e) {
      _log.error('Deep link import rejected: ${e.message}');
      _errorController.add(e.message);
      return null;
    } catch (e) {
      _log.error('Deep link decode error: $e');
      _errorController.add('Не удалось импортировать конфигурацию из ссылки');
      return null;
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
    _errorController.close();
  }
}

String encodeConfigToBase64Url(String json) {
  final bytes = utf8.encode(json);
  var encoded = base64.encode(bytes);
  encoded = encoded.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  return encoded;
}
