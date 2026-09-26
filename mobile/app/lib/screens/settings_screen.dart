import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/config_storage.dart';
import '../services/admin_api_service.dart';
import '../models/vpn_config.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/footer_common.dart';
import 'log_screen.dart';
import 'qr_scanner_screen.dart';
import 'split_tunneling_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = ConfigStorage();
  final _adminApi = AdminApiService();
  final _serverCtrl = TextEditingController();
  final _serverKeyCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _sniCtrl = TextEditingController();
  bool _skipVerify = false;
  // The stored config, so saving the manual fields keeps what the form does
  // not show (fallback endpoints, transport, TLS fingerprint).
  VpnConfig? _config;
  bool _autoConnectOnLaunch = false;
  bool _killSwitch = false;
  FooterKind _footerWidget = footerDefault;
  String _version = '';
  bool _loaded = false;
  String? _serverError;

  // Admin settings
  final _adminUrlCtrl = TextEditingController();
  final _adminTokenCtrl = TextEditingController();
  bool _adminSkipVerify = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _storage.loadConfig();
    _autoConnectOnLaunch = await _storage.getAutoConnectOnLaunch();
    _killSwitch = await _storage.getKillSwitch();
    _footerWidget = footerKindFromId(await _storage.getFooterWidget());
    final adminSettings = await _adminApi.loadSettings();
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version} (${info.buildNumber})';
    } catch (_) {}

    if (config != null) _fillForm(config);

    _adminUrlCtrl.text = adminSettings.url;
    _adminTokenCtrl.text = adminSettings.token;
    _adminSkipVerify = adminSettings.skipVerify;

    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Сервер'),
          _serverSummary(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_config == null ? 'Настроить по QR-коду' : 'Заменить по QR-коду'),
            onPressed: _scanQr,
          ),

          const Divider(height: 40),

          _sectionTitle('Подключение'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Подключаться при запуске'),
            subtitle: const Text('Включать VPN сразу при открытии приложения'),
            value: _autoConnectOnLaunch,
            onChanged: (v) async {
              await _storage.setAutoConnectOnLaunch(v);
              setState(() => _autoConnectOnLaunch = v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Kill Switch'),
            subtitle: const Text(
                'Если связь с сервером пропала — не пускать трафик мимо VPN, пока не переподключимся'),
            value: _killSwitch,
            onChanged: (v) async {
              await _storage.setKillSwitch(v);
              setState(() => _killSwitch = v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Раздельное туннелирование'),
            subtitle: const Text('Какие приложения пускать через VPN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SplitTunnelingScreen()),
            ),
          ),

          const Divider(height: 40),

          _sectionTitle('Виджет статуса'),
          Text('что показывать под кнопкой',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          for (final o in footerOptions) _footerOptionRow(o),

          const Divider(height: 40),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Журнал подключений'),
            subtitle: const Text('Технические подробности ошибок'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
          _manualConfigSection(),
          _adminSection(),

          if (_version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'версия $_version',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.dim,
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _serverSummary() {
    final c = _config;
    if (c == null) {
      return const Text(
        'Сервер не настроен. Отсканируйте QR-код, который вам прислали, '
        'или откройте ссылку-приглашение.',
        style: TextStyle(color: AppColors.dim),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.dns_outlined),
      title: Text(c.username),
      subtitle: Text(c.server),
    );
  }

  Widget _manualConfigSection() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      leading: const Icon(Icons.tune),
      title: const Text('Ручная настройка'),
      subtitle: const Text('Если нет QR-кода'),
      children: [
        TextField(
          controller: _serverCtrl,
          decoration: InputDecoration(
            labelText: 'Сервер (ip:порт)',
            hintText: '192.168.1.1:443',
            border: const OutlineInputBorder(),
            errorText: _serverError,
          ),
          onChanged: (v) {
            setState(() {
              _serverError = v.isEmpty ? null : validateServerAddress(v);
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _serverKeyCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Ключ сервера',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameCtrl,
          decoration: const InputDecoration(
            labelText: 'Имя пользователя',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Пароль',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sniCtrl,
          decoration: const InputDecoration(
            labelText: 'SNI домен (необязательно)',
            hintText: 'vpn.example.com',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          title: const Text('Пропустить проверку TLS'),
          subtitle: const Text('Для самоподписанных сертификатов'),
          value: _skipVerify,
          onChanged: (v) => setState(() => _skipVerify = v),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saveManual,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _adminSection() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      leading: const Icon(Icons.admin_panel_settings_outlined),
      title: const Text('Администрирование'),
      subtitle: const Text('Для владельца сервера'),
      children: [
        TextField(
          controller: _adminUrlCtrl,
          decoration: const InputDecoration(
            labelText: 'URL администратора',
            hintText: 'https://1.2.3.4:8443',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _adminTokenCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Bearer-токен',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          title: const Text('Пропустить проверку TLS'),
          subtitle: const Text('Для самоподписанных сертификатов'),
          value: _adminSkipVerify,
          onChanged: (v) => setState(() => _adminSkipVerify = v),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saveAdmin,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _footerOptionRow(FooterOption o) {
    final active = _footerWidget == o.kind;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await _storage.setFooterWidget(footerKindToId(o.kind));
          setState(() => _footerWidget = o.kind);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? AppColors.magenta.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: active ? AppColors.magenta : AppColors.dim2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Center(
                  child: o.dice
                      ? const Text('🎲', style: TextStyle(fontSize: 16))
                      : Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: active ? AppColors.magenta : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                                color: active ? AppColors.magenta : AppColors.dim,
                                width: 1.5),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          o.name,
                          style: TextStyle(
                            fontFamily: AppFonts.body,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color:
                                active ? AppColors.white : const Color(0xFFb8a8d8),
                          ),
                        ),
                        if (o.kind == FooterKind.random && active)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '→ ${footerOptionName(_resolvedRandomPreview)}',
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 9,
                                color: AppColors.cyan,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(o.desc,
                        style: const TextStyle(
                            fontFamily: AppFonts.body,
                            fontSize: 11,
                            color: AppColors.dim)),
                  ],
                ),
              ),
              if (active)
                const Icon(Icons.check, size: 16, color: AppColors.magenta),
            ],
          ),
        ),
      ),
    );
  }

  // The home screen decides the actual rolled footer at connect time; here we
  // just show one pool member as a hint of what "random" can yield.
  FooterKind get _resolvedRandomPreview => footerRandomPool.first;

  void _fillForm(VpnConfig config) {
    _config = config;
    _serverCtrl.text = config.server;
    _serverKeyCtrl.text = config.serverKey;
    _usernameCtrl.text = config.username;
    _passwordCtrl.text = config.password;
    _sniCtrl.text = config.sni;
    _skipVerify = config.skipVerify;
  }

  Future<void> _saveManual() async {
    final server = _serverCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final sni = _sniCtrl.text.trim();
    final fields = {
      'сервер': server,
      'ключ сервера': _serverKeyCtrl.text,
      'имя пользователя': username,
      'пароль': _passwordCtrl.text,
    };
    final missing = [
      for (final e in fields.entries)
        if (e.value.isEmpty) e.key,
    ];
    final error = missing.isNotEmpty
        ? 'Заполните: ${missing.join(', ')}'
        : validateServerAddress(server);
    if (error != null) {
      _snack(error);
      return;
    }
    final base = _config;
    final config = base == null
        ? VpnConfig(
            server: server,
            serverKey: _serverKeyCtrl.text,
            username: username,
            password: _passwordCtrl.text,
            sni: sni,
            skipVerify: _skipVerify,
          )
        : base.copyWith(
            server: server,
            serverKey: _serverKeyCtrl.text,
            username: username,
            password: _passwordCtrl.text,
            sni: sni,
            skipVerify: _skipVerify,
          );
    await _storage.saveConfig(config);
    setState(() => _config = config);
    _snack('Сохранено. Переподключитесь, чтобы применить.');
  }

  Future<void> _saveAdmin() async {
    await _adminApi.saveSettings(
      url: _adminUrlCtrl.text.trim(),
      token: _adminTokenCtrl.text,
      skipVerify: _adminSkipVerify,
    );
    _snack('Сохранено');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _scanQr() async {
    final config = await Navigator.of(context).push<VpnConfig>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (config == null) return;
    await _storage.saveConfig(config);
    setState(() => _fillForm(config));
    _snack('Сервер настроен');
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _serverKeyCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _sniCtrl.dispose();
    _adminUrlCtrl.dispose();
    _adminTokenCtrl.dispose();
    super.dispose();
  }
}
