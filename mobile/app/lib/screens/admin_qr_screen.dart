import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/vpn_config.dart';
import '../services/config_storage.dart';

class AdminQrScreen extends StatefulWidget {
  const AdminQrScreen({super.key});

  @override
  State<AdminQrScreen> createState() => _AdminQrScreenState();
}

class _AdminQrScreenState extends State<AdminQrScreen> {
  final _serverCtrl = TextEditingController();
  final _serverKeyCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _sniCtrl = TextEditingController();
  String _transport = '';

  @override
  void initState() {
    super.initState();
    _prefillFromConfig();
    _serverCtrl.addListener(_rebuild);
    _serverKeyCtrl.addListener(_rebuild);
    _usernameCtrl.addListener(_rebuild);
    _passwordCtrl.addListener(_rebuild);
    _sniCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  Future<void> _prefillFromConfig() async {
    final storage = ConfigStorage();
    final config = await storage.loadConfig();
    if (config != null && mounted) {
      setState(() {
        _serverCtrl.text = config.server;
        _serverKeyCtrl.text = config.serverKey;
        _sniCtrl.text = config.sni;
        _transport = config.transport;
        // username left blank — admin fills in the target user's name
      });
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

  String? get _qrData {
    if (_serverCtrl.text.isEmpty ||
        _serverKeyCtrl.text.isEmpty ||
        _usernameCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty) {
      return null;
    }

    final map = <String, dynamic>{
      'server': _serverCtrl.text.trim(),
      'server_key': _serverKeyCtrl.text,
      'username': _usernameCtrl.text.trim(),
      'password': _passwordCtrl.text,
    };
    if (_sniCtrl.text.isNotEmpty) map['sni'] = _sniCtrl.text.trim();
    if (_transport.isNotEmpty) map['transport'] = _transport;

    return jsonEncode(map);
  }

  Future<void> _copyToClipboard() async {
    final data = _qrData;
    if (data == null) return;
    await Clipboard.setData(ClipboardData(text: data));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config JSON copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrData = _qrData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Client QR'),
        actions: [
          if (qrData != null)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy JSON',
              onPressed: _copyToClipboard,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Warning banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This QR code contains the user\'s password. '
                    'Share only over a secure channel.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Text('Client Configuration',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          TextField(
            controller: _serverCtrl,
            decoration: const InputDecoration(
              labelText: 'Server (ip:port)',
              hintText: '1.2.3.4:443',
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
            controller: _sniCtrl,
            decoration: const InputDecoration(
              labelText: 'SNI Domain (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _transport,
            decoration: const InputDecoration(
              labelText: 'Transport',
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

          const SizedBox(height: 20),

          Text('User Credentials',
              style: Theme.of(context).textTheme.titleMedium),
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
              helperText: 'Enter the password you set for this user',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 24),

          // Live QR preview
          if (qrData != null) ...[
            Center(
              child: Column(
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(8),
                    errorStateBuilder: (ctx, err) => const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(
                        child: Text(
                          'QR too large — reduce field lengths',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Config JSON'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'Fill all required fields\nto generate QR',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
