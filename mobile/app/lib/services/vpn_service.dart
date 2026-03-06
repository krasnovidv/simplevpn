import 'dart:async';
import 'package:flutter/services.dart';
import 'event_log.dart';

enum VpnStatus { disconnected, connecting, connected, error }

class VpnService {
  static const _channel = MethodChannel('com.simplevpn/vpn');
  static const _pollInterval = Duration(seconds: 2);

  final _log = EventLog();
  VpnStatus _status = VpnStatus.disconnected;
  String? _errorMessage;
  final List<void Function(VpnStatus)> _listeners = [];
  Timer? _pollTimer;

  VpnStatus get status => _status;
  String? get errorMessage => _errorMessage;

  VpnService() {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  void addListener(void Function(VpnStatus) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(VpnStatus) listener) {
    _listeners.remove(listener);
  }

  Future<void> connect(String configJson) async {
    _log.info('Connecting to server...');
    _setStatus(VpnStatus.connecting);
    try {
      await _channel.invokeMethod('connect', {'config': configJson});
      _log.info('Connect request sent');
      _startPolling();
    } on PlatformException catch (e) {
      _log.error('Connect failed: ${e.message}');
      _errorMessage = e.message;
      _setStatus(VpnStatus.error);
    }
  }

  Future<void> disconnect() async {
    _log.info('Disconnecting...');
    try {
      await _channel.invokeMethod('disconnect');
      _log.info('Disconnected');
      _setStatus(VpnStatus.disconnected);
      _stopPolling();
    } on PlatformException catch (e) {
      _log.error('Disconnect failed: ${e.message}');
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
      final statusStr = await getStatus();
      final newStatus = _parseStatus(statusStr);
      if (newStatus != _status) {
        _log.debug('Status changed: $_status -> $newStatus');
        if (newStatus == VpnStatus.connected && _status == VpnStatus.connecting) {
          _log.info('VPN connected');
        }
        if (newStatus == VpnStatus.disconnected && _status == VpnStatus.connected) {
          _log.info('VPN disconnected unexpectedly');
          _stopPolling();
        }
        _setStatus(newStatus);
      }
    } on PlatformException catch (e) {
      _log.error('Status poll failed: ${e.message}');
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
  }
}
