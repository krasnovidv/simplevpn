import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/traffic_stats.dart';
import '../models/update_info.dart';
import '../models/vpn_config.dart';
import '../utils/validators.dart';
import '../widgets/chrome/chrome_orb.dart';
import 'admin_api_service.dart';
import 'config_storage.dart';
import 'deep_link_service.dart';
import 'event_log.dart';
import 'update_service.dart';
import 'vpn_service.dart';

/// App-wide state and behaviour behind the screens: connection status and
/// commands, stored config, updates, deep links, network availability.
/// Screens listen to it and render; dialogs that need a BuildContext are
/// requested through the streams below.
class AppController extends ChangeNotifier {
  final vpn = VpnService();
  final storage = ConfigStorage();
  final _deepLinks = DeepLinkService();
  final _updates = UpdateService();
  final _admin = AdminApiService();
  final _log = EventLog();

  VpnStatus status = const VpnStatusDisconnected();
  VpnConfig? config;
  bool loading = true;
  bool killSwitch = false;
  bool adminConfigured = false;
  UpdateInfo? updateInfo;
  bool online = true;

  /// When the current session came up (from vpnlib, so it survives an app restart).
  DateTime? connectedAt;

  /// Address the session is using ("host:port"), for the server card.
  String activeServer = '';

  /// Deliberate disconnect in progress: the design plays a short
  /// "taking the mask off" state even though the native stop is instant.
  bool _disconnecting = false;
  DateTime? _disconnectStarted;
  static const _minDisconnectVisual = Duration(milliseconds: 1300);

  /// A deep-link config waiting for the user's confirmation.
  final _deepLinkConfigs = StreamController<VpnConfig>.broadcast();
  final _messages = StreamController<String>.broadcast();
  final _criticalUpdate = StreamController<UpdateInfo>.broadcast();
  Stream<VpnConfig> get deepLinkConfigs => _deepLinkConfigs.stream;
  Stream<String> get messages => _messages.stream;
  Stream<UpdateInfo> get criticalUpdates => _criticalUpdate.stream;

  bool _criticalPrompted = false;
  Timer? _updateTimer;
  StreamSubscription<VpnConfig>? _dlSub;
  StreamSubscription<String>? _dlErrSub;
  StreamSubscription<bool>? _netSub;

  OrbMood get mood {
    if (!online && status is! VpnStatusConnected) return OrbMood.error;
    if (_disconnecting) return OrbMood.disconnecting;
    return switch (status) {
      VpnStatusConnected() => OrbMood.connected,
      VpnStatusConnecting() || VpnStatusReconnecting() => OrbMood.connecting,
      _ => OrbMood.idle,
    };
  }

  bool get isActive =>
      status is VpnStatusConnected || status is VpnStatusConnecting || status is VpnStatusReconnecting;

  /// The kill switch is holding traffic after the tunnel gave up.
  bool get killSwitchFired {
    final s = status;
    return s is VpnStatusError && (s.message?.contains('kill switch') ?? false);
  }

  Future<void> init() async {
    vpn.addListener(_onStatus);
    await reloadConfig();
    adminConfigured = await _admin.isConfigured();
    online = await vpn.isOnline();
    _netSub = vpn.networkChanges.listen((v) {
      online = v;
      notifyListeners();
    });
    await vpn.checkInitialStatus();
    loading = false;
    notifyListeners();

    _initDeepLinks();
    checkForUpdate();
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) => checkForUpdate());
  }

  /// Auto-connect on launch when enabled and nothing is running yet.
  Future<void> maybeAutoConnect() async {
    if (!await storage.getAutoConnectOnLaunch()) return;
    if (status is! VpnStatusDisconnected || config == null) return;
    _log.info('Auto-connect on launch enabled — starting connection');
    await connect();
  }

  Future<void> reloadConfig() async {
    config = await storage.loadConfig();
    killSwitch = await storage.getKillSwitch();
    notifyListeners();
    final c = config;
    if (c != null) {
      // Keep the home-screen widget's connect cache in sync so it can toggle
      // the VPN without opening the app.
      final split = await storage.getSplitTunnelConfig();
      await vpn.cacheWidgetParams(
        c.toJson(),
        killSwitch: killSwitch,
        splitTunnelMode: split.mode.name,
        splitTunnelApps: split.apps,
      );
    }
  }

  Future<void> refreshAdmin() async {
    adminConfigured = await _admin.isConfigured();
    notifyListeners();
  }

  void _onStatus(VpnStatus s) {
    final prev = status;
    status = s;
    if (s is VpnStatusConnected && prev is! VpnStatusConnected) {
      connectedAt = DateTime.now();
      _loadSessionInfo();
    }
    if (s is! VpnStatusConnected) {
      connectedAt = null;
      activeServer = '';
    }
    if (_disconnecting && s is! VpnStatusConnected) _finishDisconnectVisual();
    notifyListeners();
  }

  Future<void> _loadSessionInfo() async {
    final TrafficStats st = await vpn.getStats();
    if (st.sinceMs > 0) connectedAt = DateTime.fromMillisecondsSinceEpoch(st.sinceMs);
    activeServer = st.activeServer;
    notifyListeners();
  }

  void _finishDisconnectVisual() {
    final started = _disconnectStarted ?? DateTime.now();
    final left = _minDisconnectVisual - DateTime.now().difference(started);
    Future.delayed(left.isNegative ? Duration.zero : left, () {
      _disconnecting = false;
      notifyListeners();
    });
  }

  /// The main action: connect when idle, cancel while connecting, disconnect
  /// when connected.
  Future<void> toggle() async {
    if (_disconnecting) return;
    if (isActive) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> disconnect() async {
    _log.info('User pressed Disconnect');
    if (status is VpnStatusConnected) {
      _disconnecting = true;
      _disconnectStarted = DateTime.now();
      notifyListeners();
    }
    await vpn.disconnect();
  }

  /// Returns false when there is nothing to connect with or the user refused
  /// the system VPN permission.
  Future<bool> connect() async {
    // Connect from the stored config, not the in-memory snapshot: the update
    // check merges announced endpoints into storage while the app is open.
    final fresh = await storage.loadConfig();
    if (fresh != null) config = fresh;
    final c = config;
    if (c == null) return false;
    final err = validateServerAddress(c.server);
    if (err != null || c.serverKey.isEmpty || c.username.isEmpty || c.password.isEmpty) {
      _messages.add(err ?? 'Конфигурация неполная — настрой сервер заново');
      return false;
    }
    if (!await vpn.prepare()) {
      _log.info('VPN permission denied');
      return false;
    }
    killSwitch = await storage.getKillSwitch();
    final split = await storage.getSplitTunnelConfig();
    await vpn.connect(
      c.toJson(),
      killSwitch: killSwitch,
      splitTunnelMode: split.mode.name,
      splitTunnelApps: split.apps,
      splitTunnelRoutes: split.routes,
    );
    return true;
  }

  Future<void> retryNetwork() async {
    online = await vpn.isOnline();
    notifyListeners();
    if (online) await connect();
  }

  // --- deep links -----------------------------------------------------------

  Future<void> _initDeepLinks() async {
    final initial = await _deepLinks.getInitialConfig();
    if (initial != null) _deepLinkConfigs.add(initial);
    _dlSub = _deepLinks.configStream.listen(_deepLinkConfigs.add);
    _dlErrSub = _deepLinks.errorStream.listen((m) => _messages.add('Не удалось импортировать: $m'));
    _deepLinks.startListening();
  }

  Future<void> saveConfig(VpnConfig c) async {
    await storage.saveConfig(c);
    _log.info('Config saved: server=${c.server}, user=${c.username}');
    await reloadConfig();
  }

  // --- updates ------------------------------------------------------------

  UpdateService get updates => _updates;

  Future<void> checkForUpdate() async {
    final info = await _updates.checkForUpdate();
    // The check may have merged newly announced endpoints into the stored
    // config; re-read it so the widget cache sees them too.
    await reloadConfig();
    updateInfo = info;
    notifyListeners();
    if (info != null) {
      _log.info('Update available: ${info.version} (code=${info.versionCode})${info.critical ? ' [CRITICAL]' : ''}');
      if (info.critical && !_criticalPrompted) {
        _criticalPrompted = true;
        _criticalUpdate.add(info);
      }
    }
  }

  Future<void> skipUpdate(UpdateInfo info) async {
    await _updates.dismissVersion(info.versionCode);
    updateInfo = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _dlSub?.cancel();
    _dlErrSub?.cancel();
    _netSub?.cancel();
    _deepLinks.dispose();
    vpn.removeListener(_onStatus);
    vpn.dispose();
    _deepLinkConfigs.close();
    _messages.close();
    _criticalUpdate.close();
    super.dispose();
  }
}
