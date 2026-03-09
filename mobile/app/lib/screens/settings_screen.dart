import 'package:flutter/material.dart';
import '../services/config_storage.dart';
import '../models/vpn_config.dart';
import 'qr_scanner_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = ConfigStorage();
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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _storage.loadConfig();
    _autoReconnect = await _storage.getAutoReconnect();
    _killSwitch = await _storage.getKillSwitch();

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

    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR Config',
            onPressed: _scanQr,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server config section
          Text('Server Configuration',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          TextField(
            controller: _serverCtrl,
            decoration: const InputDecoration(
              labelText: 'Server (host:port)',
              hintText: 'vpn.example.com:443',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _serverKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Server Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _sniCtrl,
            decoration: const InputDecoration(
              labelText: 'SNI Domain (optional)',
              hintText: 'vpn.example.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            title: const Text('Skip TLS Verification'),
            subtitle: const Text('For self-signed certificates (test servers)'),
            value: _skipVerify,
            onChanged: (v) => setState(() => _skipVerify = v),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 16),

          // Transport settings
          Text('Transport', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _transport,
            decoration: const InputDecoration(
              labelText: 'Transport Protocol',
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
              labelText: 'TLS Fingerprint',
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

          FilledButton(
            onPressed: _save,
            child: const Text('Save Configuration'),
          ),

          const Divider(height: 40),

          // Connection settings
          Text('Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          SwitchListTile(
            title: const Text('Auto-Reconnect'),
            subtitle:
                const Text('Automatically reconnect on network changes'),
            value: _autoReconnect,
            onChanged: (v) async {
              await _storage.setAutoReconnect(v);
              setState(() => _autoReconnect = v);
            },
          ),

          SwitchListTile(
            title: const Text('Kill Switch'),
            subtitle:
                const Text('Block all traffic when VPN disconnects'),
            value: _killSwitch,
            onChanged: (v) async {
              await _storage.setKillSwitch(v);
              setState(() => _killSwitch = v);
            },
          ),
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved')),
      );
    }
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
    super.dispose();
  }
}
