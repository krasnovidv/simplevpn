import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_prefs.dart';
import '../theme/chrome.dart';
import '../widgets/chrome/chrome_ui.dart';
import 'access_screen.dart';
import 'admin_screen.dart';
import 'app_scope.dart';
import 'log_screen.dart';
import 'main_tab.dart' show navBarHeight;

/// «Настройки». Only real features: what the design mocked (a protocol
/// picker, a custom DNS) is shown as the plain facts of this app instead.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _autoConnect = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final auto = await app.storage.getAutoConnectOnLaunch();
    var version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _autoConnect = auto;
        _version = version;
      });
    }
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final app = AppScope.of(context);
    final prefs = AppPrefs.instance;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(bottom: navBarHeight(context) + 16),
        children: [
          const TopBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(2, 0, 2, 18),
                child: Headline(lines: ['Настройки'], size: 30, hot: true),
              ),
              SettingsGroup(label: 'Защита', children: [
                SettingsRow(
                  title: 'Рубильник',
                  subtitle: 'Упал VPN — режем интернет, чтобы ничего не утекло',
                  value: app.killSwitch,
                  onChanged: (v) async {
                    await app.storage.setKillSwitch(v);
                    await app.reloadConfig();
                  },
                ),
                SettingsRow(
                  title: 'Автоподключение',
                  subtitle: 'Открыл приложение — и ты уже невидимка',
                  value: _autoConnect,
                  onChanged: (v) async {
                    await app.storage.setAutoConnectOnLaunch(v);
                    setState(() => _autoConnect = v);
                  },
                ),
                SettingsRow(
                  title: 'Постоянный VPN',
                  subtitle: 'Включи в настройках Android — и он сам поднимет нас после перезагрузки',
                  onTap: app.vpn.openVpnSettings,
                ),
              ]),
              const SettingsGroup(label: 'Соединение', children: [
                SettingsRow(
                  title: 'Режим «Я не VPN»',
                  subtitle: 'Притворяемся скучным HTTPS-трафиком',
                  trailingText: 'всегда',
                ),
                SettingsRow(title: 'Протокол', trailingText: 'WebSocket · TLS 1.3'),
                SettingsRow(title: 'DNS', trailingText: '1.1.1.1, в туннеле'),
              ]),
              SettingsGroup(label: 'Внешний вид', children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: prefs.themeMode,
                  builder: (context, mode, _) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: ChromeSegmented(
                      framed: false,
                      options: const ['Светлая', 'Тёмная', 'Как в системе'],
                      index: switch (mode) {
                        ThemeMode.light => 0,
                        ThemeMode.dark => 1,
                        ThemeMode.system => 2,
                      },
                      onChanged: (i) => prefs.setThemeMode([ThemeMode.light, ThemeMode.dark, ThemeMode.system][i]),
                    ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: prefs.maxAnimations,
                  builder: (context, v, _) => SettingsRow(
                    title: 'Анимации на максимум',
                    subtitle: 'Батарейке будет грустно. Нам — весело',
                    value: v,
                    onChanged: prefs.setMaxAnimations,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: prefs.statusInShade,
                  builder: (context, v, _) => SettingsRow(
                    title: 'Статус в шторке',
                    subtitle: 'Таймер и трафик в уведомлении',
                    value: v,
                    onChanged: prefs.setStatusInShade,
                  ),
                ),
              ]),
              SettingsGroup(label: 'Доступ', children: [
                SettingsRow(
                  title: 'Мой доступ',
                  subtitle: 'QR-код, ручная настройка',
                  trailingText: app.config?.username ?? 'не настроен',
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccessScreen()));
                    await app.reloadConfig();
                    await app.refreshAdmin();
                  },
                ),
                SettingsRow(
                  title: 'Журнал подключений',
                  subtitle: 'Технические подробности, если что-то пошло не так',
                  onTap: () => _push(const LogScreen()),
                ),
                if (app.adminConfigured)
                  SettingsRow(
                    title: 'Администрирование',
                    subtitle: 'Пользователи и приглашения',
                    onTap: () => _push(const AdminScreen()),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
                child: Text(
                  'RKNPNH${_version.isEmpty ? '' : ' $_version'} · сделано без одобрения',
                  textAlign: TextAlign.center,
                  style: bodyStyle(c, size: 12, weight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
