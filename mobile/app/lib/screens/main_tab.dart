import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import '../services/app_prefs.dart';
import '../services/vpn_service.dart';
import '../theme/chrome.dart';
import '../utils/vpn_error.dart';
import '../widgets/chrome/chrome_orb.dart';
import '../widgets/chrome/chrome_ui.dart';
import 'app_scope.dart';

/// Главная: headline by state, the orb as the one big button, server card.
class MainTab extends StatefulWidget {
  final VoidCallback onUpdateTap;
  const MainTab({super.key, required this.onUpdateTap});

  @override
  State<MainTab> createState() => _MainTabState();
}

class _MainTabState extends State<MainTab> {
  bool _pressed = false;
  bool _killSnackDismissed = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final mood = app.mood;
    if (mood == OrbMood.error) return _OfflineView(app: app);

    final c = Chrome.of(context);
    final animate = AppPrefs.instance.animate(context);
    final err = app.status is VpnStatusError ? app.status as VpnStatusError : null;
    if (!app.killSwitchFired) _killSnackDismissed = false;

    final (lines, sub) = switch (mood) {
      OrbMood.connecting => (['Прячем', 'тебя…'], 'Заметаем следы, путаем провода…'),
      OrbMood.connected => (['Тебя', 'нет'], 'Для всех ты в Амстердаме. Для мамы — дома.'),
      OrbMood.disconnecting => (['Снимаем', 'маску…'], 'Возвращаем тебя в поле зрения. Сам захотел.'),
      _ => (
          ['Тебя', 'видно'],
          app.config == null
              ? 'Сначала настрой доступ — отсканируй QR-код из приглашения.'
              : err != null
                  ? '${friendlyVpnError(err.errorKind, err.message)}. Жми на штуку — попробуем ещё раз.'
                  : 'РКН уже подглядывает. Жми на штуку — исчезнешь.'
        ),
    };

    return Stack(children: [
      SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final orbSize = (box.maxHeight * 0.34).clamp(190.0, 270.0);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TopBar(trailing: StatusChip(mood: mood)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Headline(lines: lines, hot: mood == OrbMood.connected),
                const SizedBox(height: 12),
                EnterAnim(
                  key: ValueKey(sub),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(sub, style: bodyStyle(c)),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Semantics(
                button: true,
                label: switch (mood) {
                  OrbMood.connected => 'Отключить VPN',
                  OrbMood.connecting => 'Отменить подключение',
                  _ => 'Подключить VPN',
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp: (_) => setState(() => _pressed = false),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTap: app.toggle,
                  child: Center(
                    child: AnimatedScale(
                      scale: _pressed ? 0.94 : 1,
                      duration: const Duration(milliseconds: 400),
                      curve: springCurve,
                      child: ChromeOrb(mood: mood, size: orbSize, pressed: _pressed, animate: animate),
                    ),
                  ),
                ),
              ),
            ),
            if (app.updateInfo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _UpdateCard(critical: app.updateInfo!.critical, version: app.updateInfo!.version, onTap: widget.onUpdateTap),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ServerCard(app: app, mood: mood),
            ),
            SizedBox(height: 16 + navBarHeight(context)),
          ]);
        }),
      ),
      if (app.killSwitchFired && !_killSnackDismissed)
        Positioned(
          left: 16,
          right: 16,
          bottom: navBarHeight(context) + 12,
          child: _KillSwitchSnack(onOk: () => setState(() => _killSnackDismissed = true)),
        ),
    ]);
  }
}

/// Height of the bottom navigation, including the gesture inset.
double navBarHeight(BuildContext context) => 80 + MediaQuery.of(context).padding.bottom;

class _ServerCard extends StatelessWidget {
  final AppController app;
  final OrbMood mood;
  const _ServerCard({required this.app, required this.mood});

  String get _host {
    final s = app.activeServer.isNotEmpty ? app.activeServer : (app.config?.server ?? '');
    final i = s.lastIndexOf(':');
    return i > 0 ? s.substring(0, i) : s;
  }

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final small = bodyStyle(c, size: 13, weight: FontWeight.w700, height: 1.2);
    final status = app.status;
    final Widget bottom = switch (mood) {
      OrbMood.connected => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          _Uptime(since: app.connectedAt),
          const SizedBox(width: 12),
          Expanded(
            child: Text('IP $_host', style: small, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
          ),
        ]),
      OrbMood.connecting => Row(children: [
          Expanded(
            child: Text(
              status is VpnStatusReconnecting && status.max > 0
                  ? 'Переподключаемся… попытка ${status.attempt} из ${status.max}'
                  : 'Ищем самый тёмный угол…',
              style: small,
            ),
          ),
          Text('••', style: small.copyWith(color: c.accent)),
        ]),
      OrbMood.disconnecting => Row(children: [
          Expanded(child: Text('Закрываем туннель…', style: small)),
          Text('••', style: small.copyWith(color: c.accent)),
        ]),
      _ => Row(children: [
          Expanded(child: Text('Твой настоящий IP открыт', style: small)),
          Text('его видят все', style: small.copyWith(color: c.bad)),
        ]),
    };
    final lit = switch (mood) {
      OrbMood.connected => 4,
      OrbMood.connecting || OrbMood.disconnecting => 2,
      _ => 1,
    };
    return ChromeCard(
      child: Column(children: [
        Row(children: [
          const FlagNL(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Нидерланды',
                  style: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w800, fontSize: 16, color: c.text)),
              Text('Амстердам · единственный и любимый', style: bodyStyle(c, size: 13, height: 1.3)),
            ]),
          ),
          SignalBars(lit: lit, color: mood == OrbMood.connected ? c.good : c.sub),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 12),
          child: Divider(height: 1, thickness: 1, color: c.line),
        ),
        EnterAnim(key: ValueKey(mood), child: bottom),
      ]),
    );
  }
}

class _Uptime extends StatefulWidget {
  final DateTime? since;
  const _Uptime({required this.since});

  @override
  State<_Uptime> createState() => _UptimeState();
}

class _UptimeState extends State<_Uptime> {
  late final Timer _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final d = widget.since == null ? Duration.zero : DateTime.now().difference(widget.since!);
    String two(int n) => n.toString().padLeft(2, '0');
    final txt = '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return Text(txt,
        style: TextStyle(
          fontFamily: ChromeFonts.display,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: c.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        ));
  }
}

class _UpdateCard extends StatelessWidget {
  final bool critical;
  final String version;
  final VoidCallback onTap;
  const _UpdateCard({required this.critical, required this.version, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Pressable(
      onTap: onTap,
      child: ChromeCard(
        shadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(critical ? Icons.warning_amber_rounded : Icons.system_update_alt_rounded,
              color: critical ? c.bad : c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(critical ? 'Обязательно обновись' : 'Есть обновление $version',
                  style: TextStyle(
                      fontFamily: ChromeFonts.body,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: critical ? c.bad : c.text)),
              if (critical) Text('Иначе VPN перестанет работать', style: bodyStyle(c, size: 12.5, height: 1.3)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: c.sub),
        ]),
      ),
    );
  }
}

class _KillSwitchSnack extends StatelessWidget {
  final VoidCallback onOk;
  const _KillSwitchSnack({required this.onOk});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final bg = c.dark ? const Color(0xFFF4F1FA) : const Color(0xFF1E1B26);
    final fg = c.dark ? const Color(0xFF1E1B26) : const Color(0xFFF4F1FA);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: const Interval(0.33, 1, curve: enterCurve),
      builder: (context, v, child) => FractionalTranslation(translation: Offset(0, 1.2 * (1 - v)), child: child),
      child: Material(
        color: bg,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(children: [
            Icon(Icons.bolt_rounded, color: c.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Рубильник сработал: интернет выключен, ничего не утекло',
                  style: TextStyle(fontFamily: ChromeFonts.body, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.35, color: fg)),
            ),
            TextButton(
              onPressed: onOk,
              child: Text('ОК',
                  style: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w900, color: c.accent)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// «Нет сети»: shown on the main tab while the device has no network.
class _OfflineView extends StatelessWidget {
  final AppController app;
  const _OfflineView({required this.app});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: navBarHeight(context) + 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TopBar(trailing: StatusChip(mood: OrbMood.error)),
          SizedBox(
            height: 210,
            child: Center(
              child: ChromeOrb(mood: OrbMood.error, size: 190, animate: AppPrefs.instance.animate(context)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Headline(lines: ['Интернет', 'ушёл', 'за хлебом'], size: 36),
              const SizedBox(height: 12),
              Text('Проверь Wi-Fi или мобильные данные. Мы подождём — нам не привыкать.', style: bodyStyle(c)),
              const SizedBox(height: 22),
              PrimaryButton(label: 'Попробовать снова', icon: Icons.refresh_rounded, onTap: app.retryNetwork),
              const SizedBox(height: 10),
              GhostButton(label: 'Настройки Wi-Fi', onTap: app.vpn.openNetworkSettings),
            ]),
          ),
        ]),
      ),
    );
  }
}
