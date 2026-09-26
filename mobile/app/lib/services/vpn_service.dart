import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../models/traffic_stats.dart';
import 'config_storage.dart';
import 'event_log.dart';

sealed class VpnStatus {
  const VpnStatus();
}

final class VpnStatusDisconnected extends VpnStatus {
  const VpnStatusDisconnected();
  @override
  bool operator ==(Object other) => other is VpnStatusDisconnected;
  @override
  int get hashCode => runtimeType.hashCode;
}

final class VpnStatusConnecting extends VpnStatus {
  const VpnStatusConnecting();
  @override
  bool operator ==(Object other) => other is VpnStatusConnecting;
  @override
  int get hashCode => runtimeType.hashCode;
}

final class VpnStatusConnected extends VpnStatus {
  const VpnStatusConnected();
  @override
  bool operator ==(Object other) => other is VpnStatusConnected;
  @override
  int get hashCode => runtimeType.hashCode;
}

final class VpnStatusReconnecting extends VpnStatus {
  final int attempt;
  final int max;
  const VpnStatusReconnecting({required this.attempt, required this.max});
  @override
  bool operator ==(Object other) =>
      other is VpnStatusReconnecting && other.attempt == attempt && other.max == max;
  @override
  int get hashCode => Object.hash(runtimeType, attempt, max);
}

final class VpnStatusError extends VpnStatus {
  final String? message;
  final String errorKind;
  const VpnStatusError({this.message, this.errorKind = 'transient'});
  @override
  bool operator ==(Object other) =>
      other is VpnStatusError && other.message == message && other.errorKind == errorKind;
  @override
  int get hashCode => Object.hash(runtimeType, message, errorKind);
}

class VpnService with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.simplevpn/vpn');
  static const _pollInterval = Duration(seconds: 5);

  final _log = EventLog();
  final _configStorage = ConfigStorage();
  // Last address handed to _maybePromoteEndpoint, so the 1 Hz stats poll does
  // not hit secure storage every second for an address already dealt with.
  String? _promotedServer;
  VpnStatus _status = const VpnStatusDisconnected();
  final List<void Function(VpnStatus)> _listeners = [];
  Timer? _pollTimer;
  bool _wasPolling = false;

  // Traffic stats polling (1 Hz when connected)
  Timer? _statsTimer;
  bool _wasStatsPolling = false;
  TrafficStats _lastStats = TrafficStats.zero;
  DateTime _lastStatsTime = DateTime.now();
  final List<TrafficSample> _samples = [];
  static const _maxSamples = 60;
  int _statsPollCount = 0;
  bool _disposed = false;
  late final StreamController<TrafficSnapshot> _statsController =
      StreamController<TrafficSnapshot>.broadcast(
    onListen: _onStatsListen,
    onCancel: _stopStatsPolling,
  );

  Stream<TrafficSnapshot> get trafficStream => _statsController.stream;

  // Only poll traffic stats while something is actually listening to the
  // stream. With no subscribers this avoids a method-channel round-trip + JSON
  // parse every second for the entire duration of every connection.
  void _onStatsListen() {
    if (_status is VpnStatusConnected) {
      _startStatsPolling();
    }
  }
  List<TrafficSample> get samples => List.unmodifiable(_samples);

  VpnStatus get status => _status;

  String? get errorMessage {
    final s = _status;
    return s is VpnStatusError ? s.message : null;
  }

  VpnService() {
    _channel.setMethodCallHandler(_handlePlatformCall);
    WidgetsBinding.instance.addObserver(this);
  }

  // [FIX] Pause polling when app is backgrounded, resume when foregrounded
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _log.debug('[FIX] App backgrounded ($state), pausing polling');
      // OR preserves flags across hidden→paused sequence (hidden stops timers,
      // paused would then see null timers and overwrite to false)
      _wasPolling = _wasPolling || _pollTimer != null;
      _wasStatsPolling = _wasStatsPolling || _statsTimer != null;
      _stopPolling();
      _stopStatsPolling();
    } else if (state == AppLifecycleState.resumed) {
      _log.debug('[FIX] App resumed, restoring polling=$_wasPolling, stats=$_wasStatsPolling');
      if (_wasPolling) {
        _startPolling();
        _pollStatus();
      }
      if (_wasStatsPolling) {
        _startStatsPolling();
      }
      _wasPolling = false;
      _wasStatsPolling = false;
    }
  }

  /// Check native VPN status on startup to sync UI with already-running tunnel.
  Future<void> checkInitialStatus() async {
    try {
      final statusStr = await getStatus();
      final nativeStatus = _parseStatusResult(statusStr);
      _log.debug('Initial status check: native="$statusStr" -> ${nativeStatus.runtimeType}');
      if (nativeStatus is! VpnStatusDisconnected) {
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

  // Reconnect policy is fixed: always retry transient failures with backoff.
  // Android decides this natively; iOS still reads these from the call.
  static const _reconnectArgs = {
    'auto_reconnect': true,
    'reconnect_max_attempts': 8,
    'reconnect_max_backoff_s': 60,
  };

  Future<void> connect(
    String configJson, {
    bool killSwitch = false,
    String splitTunnelMode = 'off',
    List<String> splitTunnelApps = const [],
    List<String> splitTunnelRoutes = const [],
  }) async {
    _log.info('Connecting to server...');
    _log.debug('Config: ${_maskConfig(configJson)}, killSwitch=$killSwitch');
    _setStatus(const VpnStatusConnecting());
    try {
      await _channel.invokeMethod('connect', {
        'config': configJson,
        'kill_switch': killSwitch,
        'split_tunnel_mode': splitTunnelMode,
        'split_tunnel_apps': splitTunnelApps,
        'split_tunnel_routes': splitTunnelRoutes,
        ..._reconnectArgs,
      });
      _log.info('Connect request sent to native layer');
      _startPolling();
    } on PlatformException catch (e) {
      _log.error('Connect failed: ${e.message} (code: ${e.code})');
      _setStatus(e.code == 'VPN_PERMISSION'
          // The system consent dialog is up; the user connects again after it.
          ? const VpnStatusDisconnected()
          : VpnStatusError(message: e.message));
    } catch (e) {
      _log.error('Connect unexpected error: $e');
      _setStatus(VpnStatusError(message: e.toString()));
    }
  }

  /// Mirrors the current config + connect settings into the native widget cache
  /// so the home-screen widget can (re)connect without opening the app. Safe to
  /// call often; a no-op on platforms without the native handler.
  Future<void> cacheWidgetParams(
    String configJson, {
    bool killSwitch = false,
    String splitTunnelMode = 'off',
    List<String> splitTunnelApps = const [],
  }) async {
    try {
      await _channel.invokeMethod('cacheWidgetParams', {
        'config': configJson,
        'kill_switch': killSwitch,
        'split_tunnel_mode': splitTunnelMode,
        'split_tunnel_apps': splitTunnelApps,
      });
    } catch (e) {
      _log.debug('cacheWidgetParams failed (non-fatal): $e');
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
      _setStatus(const VpnStatusDisconnected());
      _stopPolling();
    } on PlatformException catch (e) {
      _log.error('Disconnect failed: ${e.message} (code: ${e.code})');
      _setStatus(VpnStatusError(message: e.message));
    }
  }

  final _network = StreamController<bool>.broadcast();

  /// Emits when the device gains or loses its last usable (non-VPN) network.
  Stream<bool> get networkChanges => _network.stream;

  /// Whether any non-VPN network with internet is up. Platforms without the
  /// native method are assumed online.
  Future<bool> isOnline() async {
    try {
      return await _channel.invokeMethod<bool>('isOnline') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Asks for the system VPN permission if it has not been granted yet.
  /// Resolves to false when the user declines.
  Future<bool> prepare() async {
    try {
      return await _channel.invokeMethod<bool>('prepareVpn') ?? true;
    } on MissingPluginException {
      return true;
    } catch (e) {
      _log.error('VPN permission request failed: $e');
      return false;
    }
  }

  /// Opens the system internet-connectivity panel (Wi-Fi / mobile data).
  Future<void> openNetworkSettings() async {
    try {
      await _channel.invokeMethod('openNetworkSettings');
    } catch (_) {}
  }

  /// Opens Android's VPN settings, where "Always-on VPN" and "Block
  /// connections without VPN" live.
  Future<void> openVpnSettings() async {
    try {
      await _channel.invokeMethod('openVpnSettings');
    } catch (_) {}
  }

  Future<TrafficStats> getStats() async {
    try {
      final raw = await _channel.invokeMethod<String>('getStats');
      return raw == null ? TrafficStats.zero : TrafficStats.fromJson(raw);
    } catch (_) {
      return TrafficStats.zero;
    }
  }

  /// Native status: a structured map on Android, a legacy string on iOS.
  Future<Object?> getStatus() => _channel.invokeMethod<Object>('status');

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
      _log.debug('Poll: native status="$statusStr", dart status=${_status.runtimeType}');
      final newStatus = _parseStatusResult(statusStr);
      if (newStatus != _status) {
        _log.info('Status changed: ${_status.runtimeType} -> ${newStatus.runtimeType}');
        if (newStatus is VpnStatusConnected && _status is VpnStatusConnecting) {
          _log.info('VPN connected!');
        }
        if (newStatus is VpnStatusError) {
          _log.error('VPN error: ${newStatus.message}');
        }
        if (newStatus is VpnStatusDisconnected && _status is VpnStatusConnected) {
          _log.info('VPN disconnected unexpectedly');
          _stopPolling();
        }
        if (newStatus is VpnStatusDisconnected && _status is! VpnStatusConnected) {
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

  VpnStatus _parseStatusResult(dynamic result) => vpnStatusFromResult(result);

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onNetworkChanged':
        if (!_network.isClosed) _network.add(call.arguments == true);
      case 'onStatusChanged':
        final newStatus = _parseStatusResult(call.arguments);
        final logStr = call.arguments is Map
            ? (call.arguments as Map).toString()
            : call.arguments.toString();
        _log.debug('Platform status update: $logStr');
        _setStatus(newStatus);
    }
  }

  void _setStatus(VpnStatus status) {
    // A late native onStatusChanged can arrive after dispose(); ignore it so we
    // never touch the closed stats controller or notify freed listeners.
    if (_disposed) return;
    final prev = _status;
    _status = status;
    for (final listener in _listeners) {
      listener(status);
    }
    // Start/stop stats polling based on connection state
    if (status is VpnStatusConnected && prev is! VpnStatusConnected) {
      _startStatsPolling();
      _promoteActiveServer();
    } else if (status is VpnStatusReconnecting || status is VpnStatusDisconnected) {
      _stopStatsPolling();
    }
  }

  /// Persists the address this session actually came up on, independent of the
  /// stats poll. The poll only runs while some widget listens to the traffic
  /// stream, so promotion must not ride on it: with no subscribers a config
  /// would keep its dead primary forever — which is exactly how phones were
  /// still carrying 193.23.3.93 a year after that server died.
  Future<void> _promoteActiveServer() async {
    try {
      final raw = await _channel.invokeMethod<String>('getStats');
      if (raw == null) return;
      final stats = TrafficStats.fromJson(raw);
      await _maybePromoteEndpoint(stats.activeServer);
    } catch (e) {
      _log.debug('Active-server check failed (non-fatal): $e');
    }
  }

  void _startStatsPolling() {
    // No subscribers → nothing consumes the samples, so don't burn a poll/sec.
    if (!_statsController.hasListener) return;
    _stopStatsPolling();
    _lastStats = TrafficStats.zero;
    _lastStatsTime = DateTime.now();
    _statsPollCount = 0;
    _log.debug('Stats polling started (1 Hz)');
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollStats());
  }

  void _stopStatsPolling() {
    if (_statsTimer != null) {
      _statsTimer!.cancel();
      _statsTimer = null;
      _log.debug('Stats polling stopped');
    }
  }

  Future<void> _pollStats() async {
    try {
      final raw = await _channel.invokeMethod<String>('getStats');
      if (raw == null) return;
      final stats = TrafficStats.fromJson(raw);
      final now = DateTime.now();
      final elapsed = now.difference(_lastStatsTime);

      if (_lastStats.sinceMs != 0 && stats.sinceMs != _lastStats.sinceMs) {
        // Counter reset (new session) — restart rolling window
        _samples.clear();
        _log.debug('Stats: counter reset detected, clearing samples');
      } else if (_lastStats.sinceMs != 0) {
        final sample = TrafficSample.fromDelta(_lastStats, stats, elapsed);
        _samples.add(sample);
        if (_samples.length > _maxSamples) {
          _samples.removeAt(0);
        }
      }

      _lastStats = stats;
      _lastStatsTime = now;
      _statsPollCount++;

      if (_statsPollCount % 10 == 0) {
        _log.debug('Stats: poll #$_statsPollCount, in=${stats.bytesIn}, out=${stats.bytesOut}');
      }

      _statsController.add(TrafficSnapshot(cumulative: stats, samples: List.of(_samples)));

      await _maybePromoteEndpoint(stats.activeServer);
    } catch (e) {
      _log.debug('Stats poll error: $e');
    }
  }

  /// Persists the address the tunnel actually came up on as the new primary.
  /// After the server moves, the old address is dead but still first in the
  /// config, so every connect would pay a full dial timeout before falling
  /// through to the live one; promoting it makes the move a one-time cost.
  Future<void> _maybePromoteEndpoint(String activeServer) async {
    if (activeServer.isEmpty || activeServer == _promotedServer) return;
    _promotedServer = activeServer; // set first: never retry-loop on a failure

    try {
      final cfg = await _configStorage.loadConfig();
      if (cfg == null || cfg.server == activeServer) return;

      await _configStorage.saveConfig(cfg.promoteEndpoint(activeServer));
      _log.info('Server address changed to $activeServer — saved as primary');
    } catch (e) {
      _log.debug('Endpoint promotion failed (non-fatal): $e');
    }
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _stopPolling();
    _stopStatsPolling();
    _statsController.close();
    _network.close();
    WidgetsBinding.instance.removeObserver(this);
  }
}

// Package-level parsing functions — used by VpnService internally and directly by tests.

VpnStatus vpnStatusFromResult(dynamic result) {
  final Map<String, dynamic> map;
  if (result is Map) {
    map = Map<String, dynamic>.from(result);
  } else if (result is String) {
    map = _vpnStringToMap(result);
  } else {
    return const VpnStatusDisconnected();
  }

  final state = map['state'] as String? ?? 'disconnected';
  return switch (state) {
    'connected' => const VpnStatusConnected(),
    'connecting' => const VpnStatusConnecting(),
    'reconnecting' => VpnStatusReconnecting(
        attempt: (map['attempt'] as num?)?.toInt() ?? 0,
        max: (map['max'] as num?)?.toInt() ?? 0,
      ),
    'error' => VpnStatusError(
        message: map['errorMessage'] as String?,
        errorKind: map['errorKind'] as String? ?? 'transient',
      ),
    _ => const VpnStatusDisconnected(),
  };
}

Map<String, dynamic> _vpnStringToMap(String s) {
  if (s.startsWith('error')) {
    final msg = s.replaceFirst('error: ', '');
    final kind = msg.contains('auth')
        ? 'auth'
        : msg.contains('fatal')
            ? 'fatal'
            : 'transient';
    return {'state': 'error', 'errorMessage': msg, 'errorKind': kind};
  }
  // "connecting (retry N/M)" — Android legacy string format
  final retryMatch = RegExp(r'connecting \(retry (\d+)/(\d+)\)').firstMatch(s);
  if (retryMatch != null) {
    return {
      'state': 'reconnecting',
      'attempt': int.parse(retryMatch.group(1)!),
      'max': int.parse(retryMatch.group(2)!),
    };
  }
  return switch (s) {
    'connected' => {'state': 'connected'},
    'connecting' => {'state': 'connecting'},
    _ => {'state': 'disconnected'},
  };
}
