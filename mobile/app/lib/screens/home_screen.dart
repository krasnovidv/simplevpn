import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/vpn_service.dart';
import '../services/config_storage.dart';
import '../services/admin_api_service.dart';
import '../services/deep_link_service.dart';
import '../services/event_log.dart';
import '../models/vpn_config.dart';
import '../models/traffic_stats.dart';
import '../utils/validators.dart';
import 'settings_screen.dart';
import 'log_screen.dart';
import 'admin_screen.dart';
import '../widgets/kill_switch_badge.dart';
import '../widgets/stats_sparkline.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _vpnService = VpnService();
  final _storage = ConfigStorage();
  final _adminApi = AdminApiService();
  final _deepLinkService = DeepLinkService();
  final _log = EventLog();
  VpnStatus _status = const VpnStatusDisconnected();
  VpnConfig? _config;
  bool _loading = true;
  bool _actionInProgress = false;
  bool _adminConfigured = false;
  bool _killSwitch = false;
  String _appVersion = '';
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  TrafficSnapshot? _trafficSnapshot;
  StreamSubscription<TrafficSnapshot>? _trafficSub;
  StreamSubscription<VpnConfig>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _vpnService.addListener(_onStatusChanged);
    _trafficSub = _vpnService.trafficStream.listen((snapshot) {
      if (mounted) setState(() => _trafficSnapshot = snapshot);
    });
    _loadConfig();
    _loadAppVersion();
    _checkAdminConfigured();
    _vpnService.checkInitialStatus();
    _initDeepLinks();
    _log.info('App started');
  }

  void _onStatusChanged(VpnStatus status) {
    setState(() {
      _status = status;
      _actionInProgress = false;
    });
    // Keep kill-switch flag in sync in case it changed while VPN was active.
    _storage.getKillSwitch().then((v) {
      if (mounted) setState(() => _killSwitch = v);
    });
  }

  Future<void> _loadConfig() async {
    final config = await _storage.loadConfig();
    final killSwitch = await _storage.getKillSwitch();
    setState(() {
      _config = config;
      _killSwitch = killSwitch;
      _loading = false;
    });
  }

  Future<void> _checkAdminConfigured() async {
    final configured = await _adminApi.isConfigured();
    if (mounted) setState(() => _adminConfigured = configured);
  }

  Future<void> _initDeepLinks() async {
    final initialConfig = await _deepLinkService.getInitialConfig();
    if (initialConfig != null && mounted) {
      _showDeepLinkConfirmation(initialConfig);
    }
    _deepLinkSub = _deepLinkService.configStream.listen((config) {
      if (mounted) _showDeepLinkConfirmation(config);
    });
    _deepLinkService.startListening();
  }

  Future<void> _showDeepLinkConfirmation(VpnConfig config) async {
    _log.info('Deep link config received: server=${config.server}, user=${config.username}');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configure VPN?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A shared VPN configuration was received:'),
            const SizedBox(height: 12),
            Text('Server: ${config.server}'),
            Text('Username: ${config.username}'),
            if (config.sni.isNotEmpty) Text('SNI: ${config.sni}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _storage.saveConfig(config);
      _log.info('Deep link config saved');
      _loadConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VPN configured from shared link')),
        );
      }
    }
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    _log.debug('App version: ${info.version}+${info.buildNumber}');
    setState(() {
      _appVersion = 'v${info.version} (${info.buildNumber})';
    });
  }

  String? _validateConfig(VpnConfig config) {
    final serverError = validateServerAddress(config.server);
    if (serverError != null) return serverError;
    if (config.serverKey.isEmpty) return 'Server key is empty';
    if (config.username.isEmpty) return 'Username is empty';
    if (config.password.isEmpty) return 'Password is empty';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SimpleVPN'),
        actions: [
          if (_adminConfigured)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Connection Log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadConfig();
              _checkAdminConfigured();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Status icon with pulse when reconnecting
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final borderAlpha = _status is VpnStatusReconnecting
                            ? _pulseAnim.value
                            : 1.0;
                        return Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _statusColor.withValues(alpha: 0.15),
                            border: Border.all(
                              color: _statusColor.withValues(alpha: borderAlpha),
                              width: 3,
                            ),
                          ),
                          child: child,
                        );
                      },
                      child: _status is VpnStatusConnecting || _status is VpnStatusReconnecting
                          ? const Padding(
                              padding: EdgeInsets.all(38),
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Icon(_statusIcon, size: 64, color: _statusColor),
                    ),

                    const SizedBox(height: 24),

                    // Status text
                    Text(
                      _statusText,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),

                    // Reconnecting attempt badge
                    if (_status case VpnStatusReconnecting(:final attempt, :final max))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            'Attempt $attempt / $max',
                            style: const TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Error message
                    if (_status is VpnStatusError && _vpnService.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _vpnService.errorMessage!,
                          style: TextStyle(color: colorScheme.error, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Kill switch badge
                    if (_status is VpnStatusError &&
                        (_status as VpnStatusError).errorKind == 'unsupported_kill_switch')
                      KillSwitchBadge(
                        kind: KillSwitchBadgeKind.unsupported,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        ),
                      )
                    else if (_killSwitch &&
                        (_status is VpnStatusDisconnected ||
                            (_status is VpnStatusError &&
                                (_status as VpnStatusError).message
                                    ?.contains('kill switch') == true)))
                      KillSwitchBadge(
                        kind: KillSwitchBadgeKind.blocked,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                          _loadConfig();
                        },
                      ),

                    // Server info
                    if (_config != null)
                      Text(
                        _config!.server,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                      ),

                    if (_config == null)
                      Text(
                        'No server configured',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                            ),
                      ),

                    const SizedBox(height: 48),

                    // Connect/Disconnect button
                    SizedBox(
                      width: 220,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _canToggle ? _toggleConnection : null,
                        icon: Icon(_status is VpnStatusConnected
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded),
                        label: Text(
                          _buttonText,
                          style: const TextStyle(fontSize: 18),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _status is VpnStatusConnected
                              ? colorScheme.error
                              : null,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Configure button (when no config)
                    if (_config == null)
                      TextButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const SettingsScreen()),
                          );
                          _loadConfig();
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('Configure Server'),
                      ),

                    // Traffic stats (when connected or reconnecting)
                    if (_trafficSnapshot != null &&
                        (_status is VpnStatusConnected || _status is VpnStatusReconnecting)) ...[
                      const SizedBox(height: 24),
                      Text(
                        '${formatBytes(_trafficSnapshot!.cumulative.bytesIn)} ↓  /  '
                        '${formatBytes(_trafficSnapshot!.cumulative.bytesOut)} ↑',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 280,
                        child: StatsSparkline(
                          samples: _trafficSnapshot!.samples,
                          reconnecting: _status is VpnStatusReconnecting,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_appVersion.isNotEmpty)
            Positioned(
              left: 16,
              bottom: 16,
              child: Opacity(
                opacity: 0.5,
                child: Text(
                  _appVersion,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _canToggle =>
      _config != null &&
      !_actionInProgress &&
      _status is! VpnStatusConnecting &&
      _status is! VpnStatusReconnecting &&
      (_status is VpnStatusConnected ||
          validateServerAddress(_config!.server) == null);

  String get _buttonText => switch (_status) {
        VpnStatusConnected() => 'Disconnect',
        VpnStatusConnecting() => 'Connecting...',
        VpnStatusReconnecting() => 'Connecting...',
        VpnStatusError() => 'Connect',
        VpnStatusDisconnected() => 'Connect',
      };

  IconData get _statusIcon => switch (_status) {
        VpnStatusConnected() => Icons.shield_rounded,
        VpnStatusConnecting() => Icons.hourglass_top_rounded,
        VpnStatusReconnecting() => Icons.hourglass_top_rounded,
        VpnStatusError() => Icons.error_outline_rounded,
        VpnStatusDisconnected() => Icons.shield_outlined,
      };

  Color get _statusColor => switch (_status) {
        VpnStatusConnected() => Colors.green,
        VpnStatusConnecting() => Colors.orange,
        VpnStatusReconnecting() => Colors.orange,
        VpnStatusError() => Colors.red,
        VpnStatusDisconnected() => Colors.grey,
      };

  String get _statusText => switch (_status) {
        VpnStatusConnected() => 'Protected',
        VpnStatusConnecting() => 'Connecting...',
        VpnStatusReconnecting() => 'Reconnecting...',
        VpnStatusError() => 'Error',
        VpnStatusDisconnected() => 'Not Connected',
      };

  Future<void> _toggleConnection() async {
    if (_status is VpnStatusConnected) {
      _log.info('User pressed Disconnect');
      setState(() => _actionInProgress = true);
      _vpnService.disconnect();
    } else if (_config != null) {
      _log.info('User pressed Connect');
      _log.debug('Config: server=${_config!.server}, sni=${_config!.sni}, skipVerify=${_config!.skipVerify}');
      final validationError = _validateConfig(_config!);
      if (validationError != null) {
        _log.error('Config validation failed: $validationError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(validationError)),
        );
        return;
      }
      _log.debug('Config validated OK, starting connection');
      setState(() => _actionInProgress = true);
      final autoReconnect = await _storage.getAutoReconnect();
      final killSwitch = await _storage.getKillSwitch();
      final reconnectMaxAttempts = await _storage.getReconnectMaxAttempts();
      final reconnectMaxBackoffS = await _storage.getReconnectMaxBackoff();
      final splitConfig = await _storage.getSplitTunnelConfig();
      _vpnService.connect(
        _config!.toJson(),
        autoReconnect: autoReconnect,
        killSwitch: killSwitch,
        reconnectMaxAttempts: reconnectMaxAttempts,
        reconnectMaxBackoffS: reconnectMaxBackoffS,
        splitTunnelMode: splitConfig.mode.name,
        splitTunnelApps: splitConfig.apps,
        splitTunnelRoutes: splitConfig.routes,
      );
    } else {
      _log.error('Connect pressed but no config loaded');
    }
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _deepLinkService.dispose();
    _trafficSub?.cancel();
    _pulseController.dispose();
    _vpnService.removeListener(_onStatusChanged);
    _vpnService.dispose();
    super.dispose();
  }
}
