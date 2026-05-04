import 'package:flutter/material.dart';
import '../services/config_storage.dart';
import '../services/admin_api_service.dart';
import '../models/vpn_config.dart';
import '../utils/validators.dart';
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
  String _transport = '';
  String _fingerprint = '';
  bool _autoReconnect = false;
  bool _killSwitch = false;
  int _reconnectMaxAttempts = 5;
  int _reconnectMaxBackoff = 60;
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
    _autoReconnect = await _storage.getAutoReconnect();
    _killSwitch = await _storage.getKillSwitch();
    _reconnectMaxAttempts = await _storage.getReconnectMaxAttempts();
    _reconnectMaxBackoff = await _storage.getReconnectMaxBackoff();
    final adminSettings = await _adminApi.loadSettings();

    if (config != null) {
      _serverCtrl.text = config.server;
      _serverKeyCtrl.text = config.serverKey;
      _usernameCtrl.text = config.username;
      _passwordCtrl.text = config.password;
      _sniCtrl.text = config.sni;
      _skipVerify = config.skipVerify;
      _transport = config.transport;
      _fingerprint = config.fingerprint;
    }

    _adminUrlCtrl.text = adminSettings.url;
    _adminTokenCtrl.text = adminSettings.token;
    _adminSkipVerify = adminSettings.skipVerify;

    setState(() => _loaded = true);
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
      appBar: AppBar(
        title: const Text('Настройки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Сканировать QR',
            onPressed: _scanQr,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server config section
          Text('Конфигурация сервера',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

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
          const SizedBox(height: 12),

          SwitchListTile(
            title: const Text('Пропустить проверку TLS'),
            subtitle: const Text('Для самоподписанных сертификатов'),
            value: _skipVerify,
            onChanged: (v) => setState(() => _skipVerify = v),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 16),

          // Transport settings
          Text('Транспорт', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _transport,
            decoration: const InputDecoration(
              labelText: 'Транспортный протокол',
              border: OutlineInputBorder(),
            ),
            items: VpnConfig.transportOptions
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(VpnConfig.transportLabels[v] ?? v),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _transport = v ?? ''),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _fingerprint,
            decoration: const InputDecoration(
              labelText: 'TLS отпечаток',
              border: OutlineInputBorder(),
            ),
            items: VpnConfig.fingerprintOptions
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(VpnConfig.fingerprintLabels[v] ?? v),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _fingerprint = v ?? ''),
          ),

          const SizedBox(height: 16),

          const Divider(height: 40),

          // Connection settings
          Text('Подключение', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          SwitchListTile(
            title: const Text('Автопереподключение'),
            subtitle:
                const Text('Автоматически переподключаться при смене сети'),
            value: _autoReconnect,
            onChanged: (v) async {
              await _storage.setAutoReconnect(v);
              setState(() => _autoReconnect = v);
            },
          ),

          SwitchListTile(
            title: const Text('Kill Switch'),
            subtitle:
                const Text('Блокировать трафик при отключении VPN'),
            value: _killSwitch,
            onChanged: (v) async {
              await _storage.setKillSwitch(v);
              setState(() => _killSwitch = v);
            },
          ),

          if (_autoReconnect) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Макс. попыток'),
              subtitle: Text(
                _reconnectMaxAttempts == 0
                    ? 'Без ограничений'
                    : '$_reconnectMaxAttempts попыток',
              ),
              trailing: SizedBox(
                width: 160,
                child: Slider(
                  value: _reconnectMaxAttempts.toDouble(),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (v) async {
                    final val = v.round();
                    await _storage.setReconnectMaxAttempts(val);
                    setState(() => _reconnectMaxAttempts = val);
                  },
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Макс. задержка'),
              subtitle: Text('${_reconnectMaxBackoff}с между попытками'),
              trailing: SizedBox(
                width: 160,
                child: Slider(
                  value: _reconnectMaxBackoff.toDouble(),
                  min: 10,
                  max: 300,
                  divisions: 29,
                  onChanged: (v) async {
                    final val = (v / 10).round() * 10;
                    await _storage.setReconnectMaxBackoff(val);
                    setState(() => _reconnectMaxBackoff = val);
                  },
                ),
              ),
            ),
          ],

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Раздельное туннелирование'),
            subtitle: const Text('Выбрать приложения или маршруты'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SplitTunnelingScreen()),
            ),
          ),

          const Divider(height: 40),

          // Admin API section
          Text('Admin API', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Подключение к API управления сервером.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 12),

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

          const SizedBox(height: 24),

          FilledButton(
            onPressed: _saveAll,
            child: const Text('Сохранить всё'),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final config = VpnConfig(
      server: _serverCtrl.text,
      serverKey: _serverKeyCtrl.text,
      username: _usernameCtrl.text,
      password: _passwordCtrl.text,
      sni: _sniCtrl.text,
      skipVerify: _skipVerify,
      transport: _transport,
      fingerprint: _fingerprint,
    );
    await _storage.saveConfig(config);
  }

  Future<void> _saveAll() async {
    await Future.wait([_save(), _saveAdmin()]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки сохранены')),
      );
    }
  }

  Future<void> _saveAdmin() async {
    await _adminApi.saveSettings(
      url: _adminUrlCtrl.text.trim(),
      token: _adminTokenCtrl.text,
      skipVerify: _adminSkipVerify,
    );
  }

  Future<void> _scanQr() async {
    final config = await Navigator.of(context).push<VpnConfig>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (config != null) {
      _serverCtrl.text = config.server;
      _serverKeyCtrl.text = config.serverKey;
      _usernameCtrl.text = config.username;
      _passwordCtrl.text = config.password;
      _sniCtrl.text = config.sni;
      _skipVerify = config.skipVerify;
      _transport = config.transport;
      _fingerprint = config.fingerprint;
      await _save();
    }
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
