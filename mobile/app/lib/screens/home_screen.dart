import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/vpn_service.dart';
import '../services/config_storage.dart';
import '../services/deep_link_service.dart';
import '../services/admin_api_service.dart';
import '../services/event_log.dart';
import '../models/vpn_config.dart';
import '../models/traffic_stats.dart';
import '../utils/validators.dart';
import '../theme/app_theme.dart';
import '../widgets/stamp_widget.dart';
import '../widgets/connect_animation.dart';
import '../widgets/header_widget.dart';
import '../widgets/footer_card.dart';
import '../widgets/status_copy.dart';
import '../widgets/pulse_rings.dart';
import '../widgets/kill_switch_badge.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _vpnService = VpnService();
  final _storage = ConfigStorage();
  final _deepLinkService = DeepLinkService();
  final _adminApi = AdminApiService();
  final _log = EventLog();
  VpnStatus _status = const VpnStatusDisconnected();
  VpnConfig? _config;
  bool _loading = true;
  bool _actionInProgress = false;
  bool _killSwitch = false;
  bool _adminConfigured = false;
  TrafficSnapshot? _trafficSnapshot;
  StreamSubscription<TrafficSnapshot>? _trafficSub;
  StreamSubscription<VpnConfig>? _deepLinkSub;

  late final AnimationController _stampPulseController;
  late final AnimationController _stampShakeController;
  late final AnimationController _connectAnimController;

  DateTime? _connectedAt;
  Timer? _uptimeTimer;
  Duration _uptime = Duration.zero;
  bool _visualDisconnecting = false;
  bool _connectAnimPlaying = false;

  int _connectedSecondsForAnim = 0;

  @override
  void initState() {
    super.initState();

    _stampPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _stampShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _connectAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    _vpnService.addListener(_onStatusChanged);
    _trafficSub = _vpnService.trafficStream.listen((snapshot) {
      if (mounted) setState(() => _trafficSnapshot = snapshot);
    });
    _loadConfig();
    _checkAdminConfigured();
    _vpnService.checkInitialStatus();
    _initDeepLinks();
    _log.info('App started');
  }

  void _onStatusChanged(VpnStatus status) {
    final prevStatus = _status;
    setState(() {
      _status = status;
      _actionInProgress = false;
    });

    if (status is VpnStatusConnecting && prevStatus is! VpnStatusConnecting) {
      _connectAnimPlaying = true;
      _connectAnimController.forward(from: 0).then((_) {
        if (!mounted) return;
        if (_status is! VpnStatusConnected) {
          setState(() => _connectAnimPlaying = false);
        }
      });
      _stampShakeController.repeat();
    }

    if (status is VpnStatusConnected && prevStatus is! VpnStatusConnected) {
      _stampShakeController.stop();
      _connectedAt = DateTime.now();
      _connectedSecondsForAnim = 0;
      _startUptimeTimer();
    }

    if (status is VpnStatusDisconnected || status is VpnStatusError) {
      _stampShakeController.stop();
      _connectAnimController.stop();
      _connectAnimController.reset();
      _connectAnimPlaying = false;
      _stopUptimeTimer();
      _connectedAt = null;
      _connectedSecondsForAnim = 0;
      _visualDisconnecting = false;
    }

    _storage.getKillSwitch().then((v) {
      if (mounted) setState(() => _killSwitch = v);
    });
  }

  void _startUptimeTimer() {
    _stopUptimeTimer();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null && mounted) {
        setState(() {
          _uptime = DateTime.now().difference(_connectedAt!);
          _connectedSecondsForAnim++;
        });
      }
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    _uptime = Duration.zero;
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
        title: const Text('Настроить VPN?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Получена конфигурация VPN:'),
            const SizedBox(height: 12),
            Text('Сервер: ${config.server}'),
            Text('Пользователь: ${config.username}'),
            if (config.sni.isNotEmpty) Text('SNI: ${config.sni}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Принять'),
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
          const SnackBar(content: Text('VPN настроен по ссылке')),
        );
      }
    }
  }

  String? _validateConfig(VpnConfig config) {
    final serverError = validateServerAddress(config.server);
    if (serverError != null) return serverError;
    if (config.serverKey.isEmpty) return 'Server key is empty';
    if (config.username.isEmpty) return 'Username is empty';
    if (config.password.isEmpty) return 'Password is empty';
    return null;
  }

  bool get _showConnectAnim {
    if (_connectAnimPlaying) return true;
    if (_status is VpnStatusConnecting) return true;
    if (_status is VpnStatusConnected && _connectedSecondsForAnim < 4) return true;
    return false;
  }

  String get _subtitle => switch (_status) {
        VpnStatusConnected() => 'твой трафик забрали мы, а не они',
        _ => 'VPN от тебя, против них',
      };

  String get _statusCaption {
    if (_visualDisconnecting) return "// ЗАКРЫВАЕМ ТОННЕЛЬ…";
    return switch (_status) {
      VpnStatusDisconnected() => "// СТАТУС: НА ВИДУ",
      VpnStatusConnecting() => "// ИЩЕМ МАРШРУТ…",
      VpnStatusReconnecting() => "// ПЕРЕПОДКЛЮЧЕНИЕ…",
      VpnStatusConnected() => "// СТАТУС: СКРЫТ",
      VpnStatusError() => "// СТАТУС: ОШИБКА",
    };
  }

  String get _statusCta {
    if (_visualDisconnecting) return "ПОКА";
    return switch (_status) {
      VpnStatusDisconnected() => _config == null ? "НАСТРОИТЬ" : "НАЖМИ, ЧТОБЫ СКРЫТЬСЯ",
      VpnStatusConnecting() => "ПОДОЖДИ",
      VpnStatusReconnecting() => "ПОДОЖДИ",
      VpnStatusConnected() => "НАЖМИ, ЧТОБЫ ВЫЙТИ",
      VpnStatusError() => "НАЖМИ, ЧТОБЫ СКРЫТЬСЯ",
    };
  }

  Color get _ctaColor {
    if (_visualDisconnecting) return AppColors.magenta;
    return switch (_status) {
      VpnStatusConnected() => AppColors.cyan,
      _ => AppColors.magenta,
    };
  }

  Color get _stampColor => switch (_status) {
        VpnStatusConnected() => AppColors.cyan,
        _ => AppColors.magenta,
      };

  String _formatUptime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  double get _latestDownKbps {
    final samples = _trafficSnapshot?.samples;
    if (samples == null || samples.isEmpty) return 0;
    return samples.last.kbpsIn;
  }

  double get _latestUpKbps {
    final samples = _trafficSnapshot?.samples;
    if (samples == null || samples.isEmpty) return 0;
    return samples.last.kbpsOut;
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _status is VpnStatusConnected;
    final glowColor = isConnected ? AppColors.cyan : AppColors.magenta;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.ease,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: isConnected
                      ? const Alignment(0, -0.3)
                      : Alignment.center,
                  radius: 0.6,
                  colors: [
                    glowColor.withValues(alpha: 0.13),
                    glowColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: _loading ? _buildLoading() : _buildMain(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.magenta),
    );
  }

  Widget _buildMain() {
    return Column(
      children: [
        HeaderWidget(
          subtitle: _subtitle,
          onSettingsTap: _openSettings,
          showAdmin: _adminConfigured,
          onAdminTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminScreen()),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_canToggle) {
                _toggleConnection();
              } else if (_config == null) {
                _openSettings();
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCenterStage(),
                const SizedBox(height: 24),
                _buildStatusArea(),
              ],
            ),
          ),
        ),
        FooterCard(
          route: _status is VpnStatusConnected
              ? (_config?.sni ?? _config?.server ?? '—')
              : '— выбери маршрут —',
          publicIp: _status is VpnStatusConnected
              ? (_config?.server.split(':').first ?? '—')
              : '—',
          uptime: _status is VpnStatusConnected
              ? _formatUptime(_uptime)
              : '—',
          downKbps: _latestDownKbps,
          upKbps: _latestUpKbps,
          isConnected: _status is VpnStatusConnected,
        ),
      ],
    );
  }

  Widget _buildCenterStage() {
    if (_showConnectAnim) {
      return AnimatedBuilder(
        animation: _connectAnimController,
        builder: (context, _) {
          double animT;
          if (_connectAnimController.isAnimating || _connectAnimController.value < 1.0) {
            animT = _connectAnimController.value * 3.6;
          } else {
            animT = 3.6 + (_connectedSecondsForAnim / 4.0).clamp(0.0, 1.0) * 2.4;
          }
          return SizedBox(
            width: 300,
            height: 360,
            child: ConnectAnimation(t: animT),
          );
        },
      );
    }

    if (_config == null) {
      return Opacity(
        opacity: 0.4,
        child: StampWidget(size: 220, color: AppColors.dim),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        if (_status is VpnStatusDisconnected) const PulseRings(),
        AnimatedBuilder(
          animation: _stampPulseController,
          builder: (context, child) {
            double scale = 1.0;
            double rotation = -7.0;

            if (_status is VpnStatusDisconnected) {
              scale = 1.0 + 0.04 * (0.5 + 0.5 * _pulseValue());
            } else if (_status is VpnStatusConnected) {
              scale = 1.0 + 0.04 * (0.5 + 0.5 * _pulseValue());
            } else if (_status is VpnStatusReconnecting) {
              scale = 1.0 + 0.04 * (0.5 + 0.5 * _pulseValue());
            } else if (_status is VpnStatusError) {
              scale = 1.0;
            }

            if (_status is VpnStatusReconnecting || _stampShakeController.isAnimating) {
              final shakeVal = _stampShakeController.value;
              rotation = -7.0 + 3.0 * (shakeVal < 0.5 ? -1 : 1) * (1 - (2 * shakeVal - 1).abs());
            }

            return StampWidget(
              size: 220,
              color: _stampColor,
              scale: scale,
              rotation: rotation,
            );
          },
        ),
        if (_status case VpnStatusReconnecting(:final attempt, :final max))
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Text(
                'Attempt $attempt / $max',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: Colors.orange,
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _pulseValue() {
    final t = _stampPulseController.value * 2 * 3.14159;
    return (t.clamp(0, 6.28) < 3.14) ? _stampPulseController.value : 1 - _stampPulseController.value;
  }

  Widget _buildStatusArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_status is VpnStatusError && _vpnService.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _vpnService.errorMessage!,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: Color(0xFFFF4444),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        if (_status is VpnStatusError &&
            (_status as VpnStatusError).errorKind == 'unsupported_kill_switch')
          KillSwitchBadge(
            kind: KillSwitchBadgeKind.unsupported,
            onTap: _openSettings,
          )
        else if (_killSwitch &&
            (_status is VpnStatusDisconnected ||
                (_status is VpnStatusError &&
                    (_status as VpnStatusError).message?.contains('kill switch') == true)))
          KillSwitchBadge(
            kind: KillSwitchBadgeKind.blocked,
            onTap: () async {
              await _openSettings();
              _loadConfig();
            },
          ),
        StatusCopy(
          caption: _statusCaption,
          cta: _statusCta,
          ctaColor: _ctaColor,
        ),
      ],
    );
  }

  bool get _canToggle =>
      _config != null &&
      !_actionInProgress &&
      _status is! VpnStatusConnecting &&
      _status is! VpnStatusReconnecting &&
      (_status is VpnStatusConnected ||
          validateServerAddress(_config!.server) == null);

  Future<void> _toggleConnection() async {
    if (_status is VpnStatusConnected) {
      _log.info('User pressed Disconnect');
      setState(() {
        _actionInProgress = true;
        _visualDisconnecting = true;
      });
      _stampShakeController.repeat();
      _vpnService.disconnect();
    } else if (_config != null) {
      _log.info('User pressed Connect');
      _log.debug('Config: server=${_config!.server}, sni=${_config!.sni}, skipVerify=${_config!.skipVerify}');
      final validationError = _validateConfig(_config!);
      if (validationError != null) {
        _log.error('Config validation failed: $validationError');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(validationError)),
          );
        }
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _loadConfig();
    _checkAdminConfigured();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _deepLinkService.dispose();
    _uptimeTimer?.cancel();
    _trafficSub?.cancel();
    _stampPulseController.dispose();
    _stampShakeController.dispose();
    _connectAnimController.dispose();
    _vpnService.removeListener(_onStatusChanged);
    _vpnService.dispose();
    super.dispose();
  }
}
