import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/split_tunnel_config.dart';
import '../services/config_storage.dart';
import '../services/vpn_service.dart';
import '../theme/chrome.dart';
import '../widgets/chrome/chrome_ui.dart';
import 'app_scope.dart';
import 'main_tab.dart' show navBarHeight;
import 'split_tunneling_screen.dart';

/// «Приложения»: split tunneling by app (Android).
class AppsTab extends StatefulWidget {
  const AppsTab({super.key});

  @override
  State<AppsTab> createState() => _AppsTabState();
}

class _App {
  final String pkg, label;
  final Uint8List? icon;
  _App(this.pkg, this.label, this.icon);
}

// A joke per well-known app; other apps get no subtitle.
const _jokes = {
  'ru.rostel': 'им и так всё известно',
  'ru.gosuslugi.pos': 'им и так всё известно',
  'ru.sberbankmobile': 'банки не любят Амстердам',
  'ru.sberbank.sberbankid': 'банки не любят Амстердам',
  'org.telegram.messenger': 'а вот тут лучше с нами',
  'org.telegram.messenger.web': 'а вот тут лучше с нами',
  'com.google.android.youtube': 'без нас — слайд-шоу',
  'ru.yandex.yandexmaps': 'чтобы такси нашло тебя',
  'com.instagram.android': 'сам знаешь почему',
  'ru.kinopoisk': 'работает и так',
  'com.android.chrome': 'всё через туннель',
};

class _AppsTabState extends State<AppsTab> {
  static const _channel = MethodChannel('com.simplevpn/vpn');
  final _storage = ConfigStorage();
  SplitTunnelConfig _cfg = SplitTunnelConfig.defaultConfig;
  List<_App>? _apps;
  String _query = '';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _storage.getSplitTunnelConfig();
    if (mounted) setState(() => _cfg = cfg);
    if (!Platform.isAndroid) return;
    try {
      final raw = await _channel.invokeMethod<List>('listInstalledApps') ?? const [];
      final apps = [
        for (final e in raw)
          () {
            final m = Map<String, String>.from(e as Map);
            final b64 = m['iconBase64'] ?? '';
            return _App(m['packageName']!, m['label'] ?? m['packageName']!,
                b64.isEmpty ? null : base64Decode(b64));
          }(),
      ];
      if (mounted) setState(() => _apps = apps);
    } on PlatformException {
      if (mounted) setState(() => _apps = const []);
    }
  }

  Future<void> _save(SplitTunnelConfig cfg) async {
    await _storage.setSplitTunnelConfig(cfg);
    setState(() {
      _cfg = cfg;
      _dirty = true;
    });
  }

  void _setMode(int i) => _save(_cfg.copyWith(mode: SplitTunnelMode.values[[0, 2, 1][i]]));

  void _toggle(String pkg, bool on) {
    final apps = List<String>.from(_cfg.apps);
    on ? apps.add(pkg) : apps.remove(pkg);
    _save(_cfg.copyWith(apps: apps));
  }

  int get _modeIndex => switch (_cfg.mode) {
        SplitTunnelMode.off => 0,
        SplitTunnelMode.blocklist => 1,
        SplitTunnelMode.allowlist => 2,
      };

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    if (!Platform.isAndroid) return _iosFallback(context);

    final apps = _apps;
    final installed = apps?.length ?? 0;
    final n = apps == null ? _cfg.apps.length : apps.where((a) => _cfg.apps.contains(a.pkg)).length;
    final q = _query.toLowerCase();
    final shown = apps
        ?.where((a) => q.isEmpty || a.label.toLowerCase().contains(q) || a.pkg.contains(q))
        .toList();
    final off = _cfg.mode == SplitTunnelMode.off;
    final bold = TextStyle(color: c.text, fontWeight: FontWeight.w800);
    final app = AppScope.of(context);

    return Stack(children: [
      SafeArea(
        bottom: false,
        child: CustomScrollView(slivers: [
          const SliverToBoxAdapter(child: TopBar()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            sliver: SliverList.list(children: [
              const Headline(lines: ['Кому', 'без маски'], size: 36, hot: true),
              const SizedBox(height: 10),
              Text.rich(
                switch (_cfg.mode) {
                  SplitTunnelMode.off => const TextSpan(
                      text: 'Сейчас прячем всё. Выбери «Кроме этих», чтобы пустить некоторые приложения напрямую.'),
                  SplitTunnelMode.blocklist => TextSpan(children: [
                      const TextSpan(text: 'Эти приложения пойдут напрямую — '),
                      TextSpan(text: '$n из $installed', style: bold),
                      const TextSpan(text: '. Остальные спрячем.'),
                    ]),
                  SplitTunnelMode.allowlist => TextSpan(children: [
                      const TextSpan(text: 'Через VPN пойдут только эти — '),
                      TextSpan(text: '$n из $installed', style: bold),
                      const TextSpan(text: '. Остальные напрямую.'),
                    ]),
                },
                style: bodyStyle(c, size: 14),
              ),
              const SizedBox(height: 16),
              ChromeSegmented(
                options: const ['Всё через VPN', 'Кроме этих', 'Только эти'],
                index: _modeIndex,
                onChanged: _setMode,
              ),
              const SizedBox(height: 14),
              _SearchField(onChanged: (v) => setState(() => _query = v.trim())),
              const SizedBox(height: 14),
            ]),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, navBarHeight(context) + 24),
            sliver: SliverToBoxAdapter(
              child: AnimatedOpacity(
                opacity: off ? 0.4 : 1,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: off,
                  child: ChromeCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: shown == null
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : shown.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('Ничего не нашлось', style: bodyStyle(c), textAlign: TextAlign.center),
                              )
                            : Column(children: [
                                for (var i = 0; i < shown.length; i++) ...[
                                  if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
                                  _AppRow(
                                    app: shown[i],
                                    on: _cfg.apps.contains(shown[i].pkg),
                                    onChanged: (v) => _toggle(shown[i].pkg, v),
                                  ),
                                ],
                              ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      // Split rules are applied when the tunnel is (re)built.
      if (_dirty && app.status is VpnStatusConnected)
        Positioned(
          left: 16,
          right: 16,
          bottom: navBarHeight(context) + 12,
          child: Material(
            color: c.dark ? const Color(0xFFF4F1FA) : const Color(0xFF1E1B26),
            borderRadius: BorderRadius.circular(16),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(children: [
                Expanded(
                  child: Text('Изменения вступят в силу после переподключения',
                      style: TextStyle(
                        fontFamily: ChromeFonts.body,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: c.dark ? const Color(0xFF1E1B26) : const Color(0xFFF4F1FA),
                      )),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _dirty = false);
                    app.connect(); // restarts the running session with the new rules
                  },
                  child: Text('Применить',
                      style: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w900, color: c.accent)),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _iosFallback(BuildContext context) {
    final c = Chrome.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 120), children: [
        const TopBar(),
        const Headline(lines: ['Кому', 'без маски'], size: 36, hot: true),
        const SizedBox(height: 12),
        Text('На iPhone туннель делится по адресам, а не по приложениям.', style: bodyStyle(c)),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Настроить маршруты',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SplitTunnelingScreen()),
          ),
        ),
      ]),
    );
  }
}

class _AppRow extends StatelessWidget {
  final _App app;
  final bool on;
  final ValueChanged<bool> onChanged;
  const _AppRow({required this.app, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final joke = _jokes[app.pkg];
    return InkWell(
      onTap: () => onChanged(!on),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 42,
              height: 42,
              child: app.icon != null
                  ? Image.memory(app.icon!, fit: BoxFit.cover, gaplessPlayback: true)
                  : Container(
                      color: c.accent,
                      alignment: Alignment.center,
                      child: Text(app.label.isEmpty ? '?' : app.label[0].toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: c.onAccent)),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w800, fontSize: 15, color: c.text)),
              if (joke != null) Text(joke, style: bodyStyle(c, size: 12.5, height: 1.3)),
            ]),
          ),
          const SizedBox(width: 8),
          ChromeSwitch(value: on, onChanged: onChanged),
        ]),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return ChromeCard(
      radius: 999,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 47,
        child: Row(children: [
          Icon(Icons.search_rounded, size: 20, color: c.sub),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w600, fontSize: 15, color: c.text),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Найти приложение',
                hintStyle: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w600, fontSize: 15, color: c.sub),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
