import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'event_log.dart';

enum VpnStatus { disconnected, connecting, connected, error }

class VpnService with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.simplevpn/vpn');
  static const _pollInterval = Duration(seconds: 5);

  final _log = EventLog();
  VpnStatus _status = VpnStatus.disconnected;
  String? _errorMessage;
  final List<void Function(VpnStatus)> _listeners = [];
  Timer? _pollTimer;
  bool _wasPolling = false;

  VpnStatus get status => _status;
  String? get errorMessage => _errorMessage;

  VpnService() {
    _channel.setMethodCallHandler(_handlePlatformCall);
    WidgetsBinding.instance.addObserver(this);
  }

  // [FIX] Pause polling when app is backgrounded, resume when foregrounded
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _log.debug('[FIX] App backgrounded, pausing status polling');
      _wasPolling = _pollTimer != null;
      _stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      _log.debug('[FIX] App resumed, restoring polling=$_wasPolling');
      if (_wasPolling) {
        _startPolling();
        _pollStatus(); // Immediate poll to sync UI
      }
    }
  }

  /// Check native VPN status on startup to sync UI with already-running tunnel.
  Future<void> checkInitialStatus() async {
    try {
      final statusStr = await getStatus();
      final nativeStatus = _parseStatus(statusStr);
      _log.debug('Initial status check: native="$statusStr" -> $nativeStatus');
      if (nativeStatus != VpnStatus.disconnected) {
        _setStatus(nativeStatus);
        _startPolling();
      }
    } catch (e) {
      _log.debug('Initial status check failed: $e');
    }
  }

  void addListener(void Function(VpnStatus) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(VpnStatus) listener) {
    _listeners.remove(listener);
  }

  Future<void> connect(
    String configJson, {
    bool autoReconnect = false,
    bool killSwitch = false,
  }) async {
    // Log config with masked PSK
    final masked = _maskConfig(configJson);
    _log.info('Connecting to server...');
    _log.debug('Config: $masked, autoReconnect=$autoReconnect, killSwitch=$killSwitch');
    _setStatus(VpnStatus.connecting);
    try {
      _log.debug('Calling platform connect...');
      await _channel.invokeMethod('connect', {
        'config': configJson,
        'auto_reconnect': autoReconnect,
        'kill_switch': killSwitch,
      });
      _log.info('Connect request sent to native layer');
      _startPolling();
    } on PlatformException catch (e) {
      _log.error('Connect failed: ${e.message} (code: ${e.code})');
      _log.debug('Platform exception details: ${e.details}');
      _errorMessage = e.message;
      _setStatus(VpnStatus.error);
    } catch (e, st) {
      _log.error('Connect unexpected error: $e');
      _log.debug('Stack trace: $st');
      _errorMessage = e.toString();
      _setStatus(VpnStatus.error);
    }
  }

  String _maskConfig(String configJson) {
    try {
      var result = configJson;
      // Mask server_key
      result = result.replaceAllMapped(
        RegExp(r'"server_key"\s*:\s*"([^"]*)"'),
        (m) {
          final key = m.group(1) ?? '';
          final masked = key.length > 4 ? '${key.substring(0, 4)}...' : key;
          return '"server_key":"$masked"';
        },
      );
      // Mask password
      result = result.replaceAllMapped(
        RegExp(r'"password"\s*:\s*"([^"]*)"'),
        (m) => '"password":"***"',
      );
      return result;
    } catch (_) {
      return '<unparseable>';
    }
  }

  Future<void> disconnect() async {
    _log.info('Disconnecting...');
    try {
      _log.debug('Calling platform disconnect...');
      await _channel.invokeMethod('disconnect');
      // Fetch any final Go logs
      await _fetchNativeLogs();
      _log.info('Disconnected');
      _setStatus(VpnStatus.disconnected);
      _stopPolling();
    } on PlatformException catch (e) {
      _log.error('Disconnect failed: ${e.message} (code: ${e.code})');
      _errorMessage = e.message;
      _setStatus(VpnStatus.error);
    }
  }

  Future<String> getStatus() async {
    final result = await _channel.invokeMethod<String>('status');
    return result ?? 'unknown';
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollStatus());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollStatus() async {
    try {
      // Fetch native logs first
      await _fetchNativeLogs();

      final statusStr = await getStatus();
      _log.debug('Poll: native status="$statusStr", dart status=$_status');
      final newStatus = _parseStatus(statusStr);
      if (newStatus != _status) {
        _log.info('Status changed: $_status -> $newStatus');
        if (newStatus == VpnStatus.connected && _status == VpnStatus.connecting) {
          _log.info('VPN connected!');
        }
        if (newStatus == VpnStatus.error) {
          _log.error('VPN error: $_errorMessage');
        }
        if (newStatus == VpnStatus.disconnected && _status == VpnStatus.connected) {
          _log.info('VPN disconnected unexpectedly');
          _stopPolling();
        }
        if (newStatus == VpnStatus.disconnected && _status != VpnStatus.connected) {
          _stopPolling();
        }
        _setStatus(newStatus);
      }
    } on PlatformException catch (e) {
      _log.error('Status poll failed: ${e.message}');
    } catch (e) {
      _log.error('Status poll unexpected error: $e');
    }
  }

  Future<void> _fetchNativeLogs() async {
    try {
      final logs = await _channel.invokeMethod<String>('getLogs');
      if (logs != null && logs.isNotEmpty) {
        // Parse individual log lines from Go
        for (final line in logs.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            _log.native(trimmed);
          }
        }
      }
    } catch (_) {
      // Silently ignore log fetch failures
    }
  }

  VpnStatus _parseStatus(String s) {
    if (s.startsWith('error')) {
      _errorMessage = s.replaceFirst('error: ', '');
      return VpnStatus.error;
    }
    return switch (s) {
      'connected' => VpnStatus.connected,
      'connecting' => VpnStatus.connecting,
      'disconnected' => VpnStatus.disconnected,
      _ => VpnStatus.disconnected,
    };
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatusChanged':
        final statusStr = call.arguments as String;
        final newStatus = _parseStatus(statusStr);
        _log.debug('Platform status update: $statusStr');
        _setStatus(newStatus);
    }
  }

  void _setStatus(VpnStatus status) {
    _status = status;
    for (final listener in _listeners) {
      listener(status);
    }
  }

  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
  }
}
