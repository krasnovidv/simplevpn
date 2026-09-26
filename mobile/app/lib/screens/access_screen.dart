import 'package:flutter/material.dart';

import '../models/vpn_config.dart';
import '../services/admin_api_service.dart';
import '../services/config_storage.dart';
import '../theme/chrome.dart';
import '../utils/validators.dart';
import '../widgets/chrome/chrome_ui.dart';
import 'qr_scanner_screen.dart';

/// «Мой доступ»: import by QR, manual server config, Admin API.
class AccessScreen extends StatefulWidget {
  const AccessScreen({super.key});

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  final _storage = ConfigStorage();
  final _adminApi = AdminApiService();
  final _server = TextEditingController();
  final _key = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _sni = TextEditingController();
  final _adminUrl = TextEditingController();
  final _adminToken = TextEditingController();
  bool _skipVerify = false;
  bool _adminSkipVerify = false;
  // The stored config, so saving the form keeps what it does not show
  // (fallback endpoints, transport, TLS fingerprint).
  VpnConfig? _config;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _storage.loadConfig();
    final admin = await _adminApi.loadSettings();
    if (cfg != null) _fill(cfg);
    _adminUrl.text = admin.url;
    _adminToken.text = admin.token;
    _adminSkipVerify = admin.skipVerify;
    if (mounted) setState(() => _loaded = true);
  }

  void _fill(VpnConfig cfg) {
    _config = cfg;
    _server.text = cfg.server;
    _key.text = cfg.serverKey;
    _user.text = cfg.username;
    _pass.text = cfg.password;
    _sni.text = cfg.sni;
    _skipVerify = cfg.skipVerify;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _scan() async {
    final cfg = await Navigator.of(context).push<VpnConfig>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (cfg == null) return;
    await _storage.saveConfig(cfg);
    setState(() => _fill(cfg));
    _snack('Доступ настроен');
  }

  Future<void> _saveManual() async {
    final server = _server.text.trim();
    final user = _user.text.trim();
    final missing = [
      if (server.isEmpty) 'сервер',
      if (_key.text.isEmpty) 'ключ сервера',
      if (user.isEmpty) 'имя пользователя',
      if (_pass.text.isEmpty) 'пароль',
    ];
    final err = missing.isNotEmpty ? 'Заполни: ${missing.join(', ')}' : validateServerAddress(server);
    if (err != null) {
      _snack(err);
      return;
    }
    final base = _config;
    final cfg = base == null
        ? VpnConfig(
            server: server,
            serverKey: _key.text,
            username: user,
            password: _pass.text,
            sni: _sni.text.trim(),
            skipVerify: _skipVerify,
          )
        : base.copyWith(
            server: server,
            serverKey: _key.text,
            username: user,
            password: _pass.text,
            sni: _sni.text.trim(),
            skipVerify: _skipVerify,
          );
    await _storage.saveConfig(cfg);
    setState(() => _config = cfg);
    _snack('Сохранено. Переподключись, чтобы применить.');
  }

  Future<void> _saveAdmin() async {
    await _adminApi.saveSettings(
      url: _adminUrl.text.trim(),
      token: _adminToken.text,
      skipVerify: _adminSkipVerify,
    );
    _snack('Сохранено');
  }

  @override
  void dispose() {
    for (final t in [_server, _key, _user, _pass, _sni, _adminUrl, _adminToken]) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final cfg = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('МОЙ ДОСТУП')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
              ChromeCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(cfg == null ? 'Доступ не настроен' : cfg.username,
                      style: TextStyle(
                          fontFamily: ChromeFonts.body, fontWeight: FontWeight.w800, fontSize: 16, color: c.text)),
                  const SizedBox(height: 4),
                  Text(
                    cfg == null
                        ? 'Отсканируй QR-код из приглашения или открой ссылку, которую тебе прислали.'
                        : cfg.server,
                    style: bodyStyle(c, size: 13),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: cfg == null ? 'Сканировать QR' : 'Заменить по QR-коду',
                    icon: Icons.qr_code_scanner_rounded,
                    onTap: _scan,
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              _Section(title: 'Ручная настройка', subtitle: 'Если QR-кода нет', children: [
                _Field(controller: _server, label: 'Сервер (ip:порт)', hint: '1.2.3.4:443'),
                _Field(controller: _key, label: 'Ключ сервера', obscure: true),
                _Field(controller: _user, label: 'Имя пользователя'),
                _Field(controller: _pass, label: 'Пароль', obscure: true),
                _Field(controller: _sni, label: 'SNI домен (необязательно)', hint: 'vpn.example.com'),
                SettingsRow(
                  title: 'Пропустить проверку TLS',
                  subtitle: 'Для самоподписанных сертификатов',
                  value: _skipVerify,
                  onChanged: (v) => setState(() => _skipVerify = v),
                ),
                const SizedBox(height: 8),
                PrimaryButton(label: 'Сохранить', onTap: _saveManual),
              ]),
              const SizedBox(height: 24),
              _Section(title: 'Администрирование', subtitle: 'Для владельца сервера', children: [
                _Field(controller: _adminUrl, label: 'URL администратора', hint: 'https://1.2.3.4:8443'),
                _Field(controller: _adminToken, label: 'Bearer-токен', obscure: true),
                SettingsRow(
                  title: 'Пропустить проверку TLS',
                  subtitle: 'Для самоподписанных сертификатов',
                  value: _adminSkipVerify,
                  onChanged: (v) => setState(() => _adminSkipVerify = v),
                ),
                const SizedBox(height: 8),
                GhostButton(label: 'Сохранить', onTap: _saveAdmin),
              ]),
            ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  const _Section({required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 6),
        childrenPadding: const EdgeInsets.only(top: 4),
        title: Text(title.toUpperCase(),
            style: TextStyle(
                fontFamily: ChromeFonts.body, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: c.sub)),
        subtitle: Text(subtitle, style: bodyStyle(c, size: 12.5)),
        iconColor: c.sub,
        collapsedIconColor: c.sub,
        children: children,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  const _Field({required this.controller, required this.label, this.hint, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: color, width: 1.5),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(fontFamily: ChromeFonts.body, fontWeight: FontWeight.w600, fontSize: 15, color: c.text),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: c.card,
          labelStyle: bodyStyle(c, size: 14),
          hintStyle: bodyStyle(c, size: 14).copyWith(color: c.sub.withValues(alpha: 0.6)),
          enabledBorder: border(c.line),
          focusedBorder: border(c.accent),
        ),
      ),
    );
  }
}
