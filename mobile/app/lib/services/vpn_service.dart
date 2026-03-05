import 'package:flutter/services.dart';

enum VpnStatus { disconnected, connecting, connected, error }

class VpnService {
  static const _channel = MethodChannel('com.simplevpn/vpn');

  VpnStatus _status = VpnStatus.disconnected;
  String? _errorMessage;
  final List<void Function(VpnStatus)> _listeners = [];

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
    _setStatus(VpnStatus.connecting);
    try {
      await _channel.invokeMethod('connect', {'config': configJson});
    } on PlatformException catch (e) {
      _errorMessage = e.message;
      _setStatus(VpnStatus.error);
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
      _setStatus(VpnStatus.disconnected);
    } on PlatformException catch (e) {
      _errorMessage = e.message;
      _setStatus(VpnStatus.error);
    }
  }

  Future<String> getStatus() async {
    final result = await _channel.invokeMethod<String>('status');
    return result ?? 'unknown';
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatusChanged':
        final statusStr = call.arguments as String;
        switch (statusStr) {
          case 'connected':
            _setStatus(VpnStatus.connected);
          case 'connecting':
            _setStatus(VpnStatus.connecting);
          case 'disconnected':
            _setStatus(VpnStatus.disconnected);
          default:
            _errorMessage = statusStr;
            _setStatus(VpnStatus.error);
        }
    }
  }

  void _setStatus(VpnStatus status) {
    _status = status;
    for (final listener in _listeners) {
      listener(status);
    }
  }
}
