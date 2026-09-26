import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/vpn_service.dart';
import '../services/config_storage.dart';
import '../services/deep_link_service.dart';
import '../services/admin_api_service.dart';
import '../services/event_log.dart';
import '../services/update_service.dart';
import '../models/vpn_config.dart';
import '../models/update_info.dart';

import '../utils/validators.dart';
import '../utils/vpn_error.dart';
import '../theme/app_theme.dart';
import '../widgets/stamp_widget.dart';
import '../widgets/connect_animation.dart';
import '../widgets/header_widget.dart';
import '../widgets/footer_common.dart';
import '../widgets/footer_render.dart';
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
  final _updateService = UpdateService();
  VpnStatus _status = const VpnStatusDisconnected();
  VpnConfig? _config;
  bool _loading = true;
  bool _actionInProgress = false;
  bool _killSwitch = false;
  bool _adminConfigured = false;
  StreamSubscription<VpnConfig>? _deepLinkSub;
  StreamSubscription<String>? _deepLinkErrorSub;
  UpdateInfo? _updateInfo;
  Timer? _updateTimer;
  // A critical update opens its dialog by itself, but only once per app run.
  bool _criticalUpdatePrompted = false;

  late final AnimationController _stampPulseController;
  late final AnimationController _stampShakeController;
  late final AnimationController _connectAnimController;

  DateTime? _connectedAt;
  Timer? _uptimeTimer;
  Duration _uptime = Duration.zero;
  bool _visualDisconnecting = false;
  bool _connectAnimPlaying = false;

  int _connectedSecondsForAnim = 0;

  // Status-widget footer preference. _footerPref is the stored choice (may be
  // FooterKind.random); _rolledFooter is the concrete footer random resolves to
  // for this launch, re-rolled on each idle→connecting transition.
  FooterKind _footerPref = footerDefault;
  FooterKind _rolledFooter = footerRandomPool.first;

  FooterConnState get _footerState {
    if (_visualDisconnecting) return FooterConnState.disconnecting;
    return switch (_status) {
      VpnStatusConnected() => FooterConnState.connected,
      VpnStatusConnecting() || VpnStatusReconnecting() =>
        FooterConnState.connecting,
      _ => FooterConnState.idle,
    };
  }

  FooterKind get _resolvedFooter =>
      _footerPref == FooterKind.random ? _rolledFooter : _footerPref;

  FooterKind _rollFooter() =>
      footerRandomPool[Random().nextInt(footerRandomPool.length)];

  Future<void> _loadFooterPref() async {
    final id = await _storage.getFooterWidget();
    if (mounted) setState(() => _footerPref = footerKindFromId(id));
  }

  @override
  void initState() {
    super.initState();
    _rolledFooter = _rollFooter();

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
    _loadConfig();
    _checkAdminConfigured();
    _maybeAutoConnectOnLaunch();
    _initDeepLinks();
    _checkForUpdate();
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) => _checkForUpdate());
    _loadFooterPref();
    _checkWhatsNew();
    _log.info('App started');
  }

  Future<void> _checkWhatsNew() async {
    final applied = await _updateService.consumeAppliedUpdate();
    if (applied == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          'Что нового · v${applied.version}',
          style: const TextStyle(fontFamily: AppFonts.display, color: AppColors.cyan),
        ),
        content: SingleChildScrollView(
          child: Text(
            applied.changelog,
            style: const TextStyle(fontFamily: AppFonts.body, color: AppColors.white),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  /// On cold start, sync the UI to any already-running tunnel and — if the user
  /// enabled "Автозапуск" — kick off a connection automatically when nothing is
  /// connected yet and a config is saved. Replaces the bare checkInitialStatus()
  /// call so both behaviours share one ordered async flow.
  Future<void> _maybeAutoConnectOnLaunch() async {
    await _vpnService.checkInitialStatus();
    if (!mounted) return;
    if (!await _storage.getAutoConnectOnLaunch()) return;
    // A tunnel is already up (or negotiating) — don't start a second connect.
    if (_vpnService.status is! VpnStatusDisconnected) return;
    final config = await _storage.loadConfig();
    if (config == null || !mounted) return;
    if (_config == null) setState(() => _config = config);
    _log.info('Auto-connect on launch enabled — starting connection');
    _toggleConnection();
  }

  void _onStatusChanged(VpnStatus status) {
    if (!mounted) return;
    final prevStatus = _status;
    setState(() {
      _status = status;
      _actionInProgress = false;
    });

    if (status is VpnStatusConnecting && prevStatus is! VpnStatusConnecting) {
      // Re-roll the random footer at the start of each connection.
      if (_footerPref == FooterKind.random) _rolledFooter = _rollFooter();
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
    if (config != null) {
      // Keep the home-screen widget's connect cache in sync with the saved
      // config + settings so it can toggle the VPN without opening the app.
      final splitConfig = await _storage.getSplitTunnelConfig();
      await _vpnService.cacheWidgetParams(
        config.toJson(),
        killSwitch: killSwitch,
        splitTunnelMode: splitConfig.mode.name,
        splitTunnelApps: splitConfig.apps,
      );
    }
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
    _deepLinkErrorSub = _deepLinkService.errorStream.listen((message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось импортировать: $message')),
        );
      }
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
      VpnStatusReconnecting(:final attempt, :final max) =>
        max > 0 ? "// ПЕРЕПОДКЛЮЧЕНИЕ $attempt/$max" : "// ПЕРЕПОДКЛЮЧЕНИЕ…",
      VpnStatusConnected() => "// СТАТУС: СКРЫТ",
      VpnStatusError(:final errorKind, :final message) =>
        "// ${friendlyVpnError(errorKind, message)}",
    };
  }

  String get _statusCta {
    if (_visualDisconnecting) return "ПОКА";
    return switch (_status) {
      VpnStatusDisconnected() => _config == null ? "НАСТРОИТЬ" : "НАЖМИ, ЧТОБЫ СКРЫТЬСЯ",
      VpnStatusConnecting() => "ПОДОЖДИ · ТАП — ОТМЕНА",
      VpnStatusReconnecting() => "ПОДОЖДИ · ТАП — ОТМЕНА",
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


  Future<void> _checkForUpdate() async {
    _log.debug('Checking for updates...');
    final info = await _updateService.checkForUpdate();
    if (mounted) {
      // The check may have merged newly announced endpoints into the stored
      // config; re-read it so this screen and the widget's cached connect
      // params see them, not the pre-check snapshot.
      _loadConfig();
      setState(() => _updateInfo = info);
      if (info != null) {
        _log.info('Update available: ${info.version} (code=${info.versionCode})'
            '${info.critical ? ' [CRITICAL]' : ''}');
        // A critical update announces itself rather than waiting to be noticed:
        // a banner is far too easy to walk past when the consequence of missing
        // it is losing the connection entirely. Once per app session, so the
        // 30-minute re-check does not nag.
        if (info.critical && !_criticalUpdatePrompted) {
          _criticalUpdatePrompted = true;
          _showUpdateDialog();
        }
      }
    }
  }

  /// The update banner. A critical update gets the loud treatment — red, taller,
  /// spelling out the consequence — because it is the only warning a user who
  /// closes the dialog will still see on the way to the connect button.
  Widget _buildUpdateBanner(UpdateInfo info) {
    final critical = info.critical;
    final accent = critical ? AppColors.red : AppColors.cyan;

    return Semantics(
      button: true,
      label: critical
          ? 'Важное обновление ${info.version}. Без него VPN перестанет работать. Нажмите, чтобы обновить.'
          : 'Доступно обновление ${info.version}. Нажмите, чтобы обновить.',
      child: GestureDetector(
        onTap: _showUpdateDialog,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: critical ? 14 : 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: critical ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: critical ? 0.65 : 0.3),
              width: critical ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                critical ? Icons.warning_amber_rounded : Icons.system_update,
                color: accent,
                size: critical ? 26 : 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: critical
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ОБЯЗАТЕЛЬНО ОБНОВИТЕСЬ',
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 15,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Иначе VPN перестанет работать',
                            style: TextStyle(
                              fontFamily: AppFonts.body,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Доступно обновление v${info.version}',
                        style: const TextStyle(
                          fontFamily: AppFonts.body,
                          fontSize: 13,
                          color: AppColors.cyan,
                        ),
                      ),
              ),
              Icon(Icons.chevron_right, color: accent, size: critical ? 24 : 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpdateDialog() {
    final info = _updateInfo;
    if (info == null) return;
    final critical = info.critical;

    showDialog(
      context: context,
      // A critical update cannot be waved away by tapping outside it.
      barrierDismissible: !critical,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            if (critical) ...[
              const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 28),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                critical ? 'ВАЖНОЕ ОБНОВЛЕНИЕ' : 'Обновление v${info.version}',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: critical ? 21 : null,
                  color: critical ? AppColors.red : AppColors.cyan,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (critical) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.55)),
                ),
                child: const Text(
                  'Если не обновиться — VPN перестанет подключаться.\n'
                  'Обновитесь прямо сейчас, это займёт минуту.',
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              info.changelog.isNotEmpty ? info.changelog : 'Доступна новая версия приложения.',
              style: const TextStyle(
                fontFamily: AppFonts.body,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          // "Пропустить" silences the version permanently — deliberately absent
          // for a critical update, where that choice strands the user.
          if (!critical)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateService.dismissVersion(info.versionCode);
                setState(() => _updateInfo = null);
                _log.info('User skipped version ${info.versionCode}');
              },
              child: const Text('Пропустить', style: TextStyle(color: Colors.white38)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              critical ? 'Позже' : 'Не сейчас',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: critical ? AppColors.red : AppColors.cyan,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _startDownload(info);
            },
            child: Text(
              critical ? 'ОБНОВИТЬ СЕЙЧАС' : 'Обновить',
              style: TextStyle(
                color: critical ? AppColors.white : Colors.black,
                fontWeight: critical ? FontWeight.w800 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startDownload(UpdateInfo info) {
    // Progress and error are driven by ValueNotifiers so the download is
    // kicked off exactly once (before the dialog builds), not re-triggered on
    // every rebuild, and the dialog is popped via a captured navigator rather
    // than a BuildContext held across the async gap.
    final progress = ValueNotifier<double>(0);
    final downloading = ValueNotifier<bool>(true);
    final error = ValueNotifier<String?>(null);
    final navigator = Navigator.of(context);

    _updateService.downloadApk(info, (p) => progress.value = p).then((path) {
      if (path != null) {
        navigator.pop();
        _updateService.markPendingInstall(info);
        _updateService.installApk(path);
      } else {
        downloading.value = false;
        error.value = 'Ошибка загрузки';
      }
    }).catchError((e) {
      downloading.value = false;
      error.value = 'Ошибка: $e';
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AnimatedBuilder(
        animation: Listenable.merge([progress, downloading, error]),
        builder: (ctx, _) {
          final isDownloading = downloading.value;
          final err = error.value;
          final p = progress.value;
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: Text(
              isDownloading ? 'Скачивание…' : 'Ошибка',
              style: const TextStyle(
                fontFamily: AppFonts.display,
                color: AppColors.cyan,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDownloading) ...[
                  LinearProgressIndicator(
                    value: p > 0 ? p : null,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${(p * 100).toInt()}%',
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      color: Colors.white54,
                    ),
                  ),
                ],
                if (err != null)
                  Text(err, style: const TextStyle(color: Color(0xFFFF4444))),
              ],
            ),
            actions: [
              if (!isDownloading) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Закрыть', style: TextStyle(color: Colors.white54)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.cyan),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _startDownload(info);
                  },
                  child: const Text('Повторить', style: TextStyle(color: Colors.black)),
                ),
              ],
            ],
          );
        },
      ),
    );
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
        if (_updateInfo != null) _buildUpdateBanner(_updateInfo!),
        Expanded(
          child: Semantics(
            button: true,
            label: _connectSemanticLabel(),
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
        ),
        FooterRender(
          kind: _resolvedFooter,
          state: _footerState,
          secs: _uptime.inSeconds,
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
      return const Opacity(
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
                'Попытка $attempt / $max',
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

  /// Screen-reader label for the main tap target — describes the action the tap
  /// will perform given the current state.
  String _connectSemanticLabel() {
    if (_config == null) return 'Открыть настройки VPN';
    return switch (_status) {
      VpnStatusConnected() => 'Отключить VPN',
      VpnStatusConnecting() => 'Отменить подключение',
      VpnStatusReconnecting() => 'Отменить переподключение',
      _ => 'Подключить VPN',
    };
  }

  bool get _isActive =>
      _status is VpnStatusConnected ||
      _status is VpnStatusConnecting ||
      _status is VpnStatusReconnecting;

  // A tap while connecting cancels: the native side aborts the dial.
  bool get _canToggle =>
      _config != null &&
      !_actionInProgress &&
      (_isActive || validateServerAddress(_config!.server) == null);

  Future<void> _toggleConnection() async {
    if (_isActive) {
      _log.info('User pressed Disconnect');
      setState(() {
        _actionInProgress = true;
        _visualDisconnecting = true;
      });
      _stampShakeController.repeat();
      _vpnService.disconnect();
    } else if (_config != null) {
      _log.info('User pressed Connect');
      // Connect from the stored config, not the in-memory snapshot: the update
      // check merges announced endpoints into storage while this screen is
      // open, and a server move announced after launch must reach the dialer
      // without waiting for an app restart.
      final fresh = await _storage.loadConfig();
      if (fresh != null) {
        _config = fresh;
      }
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
      final killSwitch = await _storage.getKillSwitch();
      final splitConfig = await _storage.getSplitTunnelConfig();
      _vpnService.connect(
        _config!.toJson(),
        killSwitch: killSwitch,
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
    _loadFooterPref();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _deepLinkErrorSub?.cancel();
    _deepLinkService.dispose();
    _uptimeTimer?.cancel();
    _updateTimer?.cancel();

    _stampPulseController.dispose();
    _stampShakeController.dispose();
    _connectAnimController.dispose();
    _vpnService.removeListener(_onStatusChanged);
    _vpnService.dispose();
    super.dispose();
  }
}
