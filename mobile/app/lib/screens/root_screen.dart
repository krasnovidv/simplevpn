import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/update_info.dart';
import '../models/vpn_config.dart';
import '../services/app_controller.dart';
import '../services/app_prefs.dart';
import '../theme/chrome.dart';
import '../widgets/chrome/backdrop.dart';
import '../widgets/chrome/chrome_ui.dart';
import 'app_scope.dart';
import 'apps_tab.dart';
import 'main_tab.dart';
import 'onboarding_screen.dart';
import 'settings_tab.dart';

/// Owns the [AppController] and decides between onboarding and the tabs.
/// Also hosts the app-level dialogs (deep links, updates, what's new).
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _app = AppController();
  bool? _onboarding;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(_app.deepLinkConfigs.listen(_confirmDeepLink));
    _subs.add(_app.messages.listen(_snack));
    _subs.add(_app.criticalUpdates.listen((_) => _showUpdateDialog()));
    _start();
  }

  Future<void> _start() async {
    await _app.init();
    if (!mounted) return;
    setState(() => _onboarding = _app.config == null);
    _checkWhatsNew();
    if (!_onboarding!) _app.maybeAutoConnect();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _app.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmDeepLink(VpnConfig cfg) async {
    if (!mounted) return;
    final c = Chrome.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ПРИНЯТЬ ПРИГЛАШЕНИЕ?', style: displayStyle(20, c.text)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Пользователь: ${cfg.username}', style: bodyStyle(c, color: c.text)),
          Text('Сервер: ${cfg.server}', style: bodyStyle(c, size: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Принять')),
        ],
      ),
    );
    if (ok == true) {
      await _app.saveConfig(cfg);
      _snack('Доступ настроен по ссылке');
    }
  }

  Future<void> _checkWhatsNew() async {
    final applied = await _app.updates.consumeAppliedUpdate();
    if (applied == null || !mounted) return;
    final c = Chrome.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ЧТО НОВОГО · ${applied.version}', style: displayStyle(18, c.text)),
        content: SingleChildScrollView(child: Text(applied.changelog, style: bodyStyle(c, color: c.text))),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))],
      ),
    );
  }

  void _showUpdateDialog() {
    final info = _app.updateInfo;
    if (info == null || !mounted) return;
    final c = Chrome.of(context);
    final critical = info.critical;
    showDialog(
      context: context,
      // A critical update cannot be waved away by tapping outside it.
      barrierDismissible: !critical,
      builder: (ctx) => AlertDialog(
        title: Text(critical ? 'ВАЖНОЕ ОБНОВЛЕНИЕ' : 'ОБНОВЛЕНИЕ ${info.version}',
            style: displayStyle(20, critical ? c.bad : c.text)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (critical) ...[
            Text('Если не обновиться — VPN перестанет подключаться. Это займёт минуту.',
                style: bodyStyle(c, color: c.text, weight: FontWeight.w800)),
            const SizedBox(height: 12),
          ],
          Text(info.changelog.isNotEmpty ? info.changelog : 'Доступна новая версия приложения.', style: bodyStyle(c)),
        ]),
        actions: [
          // "Пропустить" silences the version for good — never offered for a
          // critical update, where that choice strands the user.
          if (!critical)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _app.skipUpdate(info);
              },
              child: const Text('Пропустить'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(critical ? 'Позже' : 'Не сейчас')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startDownload(info);
            },
            child: Text(critical ? 'Обновить сейчас' : 'Обновить'),
          ),
        ],
      ),
    );
  }

  void _startDownload(UpdateInfo info) {
    // Progress lives in notifiers so the download starts exactly once and the
    // dialog just reflects it.
    final progress = ValueNotifier<double>(0);
    final error = ValueNotifier<String?>(null);
    final navigator = Navigator.of(context);
    final updates = _app.updates;

    updates.downloadApk(info, (p) => progress.value = p).then((path) {
      if (path != null) {
        navigator.pop();
        updates.markPendingInstall(info);
        updates.installApk(path);
      } else {
        error.value = 'Не удалось скачать';
      }
    }).catchError((e) {
      error.value = 'Ошибка: $e';
    });

    final c = Chrome.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AnimatedBuilder(
        animation: Listenable.merge([progress, error]),
        builder: (ctx, _) => AlertDialog(
          title: Text(error.value == null ? 'СКАЧИВАЕМ…' : 'НЕ ВЫШЛО', style: displayStyle(20, c.text)),
          content: error.value != null
              ? Text(error.value!, style: bodyStyle(c, color: c.bad))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: progress.value > 0 ? progress.value : null, minHeight: 8),
                  ),
                  const SizedBox(height: 12),
                  Text('${(progress.value * 100).toInt()}%', style: bodyStyle(c, weight: FontWeight.w800)),
                ]),
          actions: [
            if (error.value != null) ...[
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _startDownload(info);
                },
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final overlay = (c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );
    return AppScope(
      controller: _app,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: switch (_onboarding) {
          null => Scaffold(body: ColoredBox(color: c.bg)),
          true => OnboardingScreen(onDone: () => setState(() => _onboarding = false)),
          false => _Shell(onUpdateTap: _showUpdateDialog),
        },
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  final VoidCallback onUpdateTap;
  const _Shell({required this.onUpdateTap});

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  int _tab = 0;
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);

  static const _items = [
    NavItem(Icons.shield_outlined, 'Главная'),
    NavItem(Icons.grid_view_rounded, 'Приложения'),
    NavItem(Icons.settings_outlined, 'Настройки'),
  ];

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    if (!MediaQuery.of(context).disableAnimations) _enter.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      extendBody: true,
      body: ChromeBackdrop(
        mood: app.mood,
        animate: AppPrefs.instance.animate(context),
        child: Stack(children: [
          AnimatedBuilder(
            animation: _enter,
            builder: (context, child) {
              final v = enterCurve.transform(_enter.value);
              return Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 18 * (1 - v)),
                  child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
                ),
              );
            },
            child: IndexedStack(index: _tab, children: [
              MainTab(onUpdateTap: widget.onUpdateTap),
              const AppsTab(),
              const SettingsTab(),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ChromeNavBar(items: _items, index: _tab, onTap: _go),
          ),
        ]),
      ),
    );
  }
}
