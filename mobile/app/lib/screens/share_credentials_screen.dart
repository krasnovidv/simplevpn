import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/vpn_config.dart';
import '../services/config_storage.dart';
import '../services/deep_link_service.dart';
import '../services/event_log.dart';

class ShareCredentialsScreen extends StatefulWidget {
  final String username;
  final String? prefilledPassword;

  const ShareCredentialsScreen({
    super.key,
    required this.username,
    this.prefilledPassword,
  });

  @override
  State<ShareCredentialsScreen> createState() => _ShareCredentialsScreenState();
}

class _ShareCredentialsScreenState extends State<ShareCredentialsScreen> {
  final _log = EventLog();
  final _passwordCtrl = TextEditingController();
  final _qrKey = GlobalKey();
  VpnConfig? _serverConfig;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledPassword != null) {
      _passwordCtrl.text = widget.prefilledPassword!;
    }
    _passwordCtrl.addListener(() => setState(() {}));
    _loadServerConfig();
  }

  Future<void> _loadServerConfig() async {
    final config = await ConfigStorage().loadConfig();
    if (mounted) {
      setState(() {
        _serverConfig = config;
        _loading = false;
      });
      _log.debug('ShareCredentials: loaded server config, server=${config?.server}');
    }
  }

  VpnConfig? get _userConfig {
    if (_serverConfig == null || _passwordCtrl.text.isEmpty) return null;
    return _serverConfig!.copyWith(
      username: widget.username,
      password: _passwordCtrl.text,
    );
  }

  String? get _shareLink {
    final config = _userConfig;
    if (config == null) return null;
    final json = config.toJson();
    final encoded = encodeConfigToBase64Url(json);
    final host = _serverConfig!.server.split(':').first;
    return 'http://$host:8080/join#$encoded';
  }

  String get _shareText {
    final link = _shareLink ?? '';
    return 'RKNPNH VPN — конфиг для ${widget.username}\n\n'
        'Открой ссылку на телефоне:\n$link';
  }

  Future<void> _copyLink() async {
    final link = _shareLink;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    _log.debug('ShareCredentials: link copied to clipboard');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована')),
      );
    }
  }

  Future<void> _shareLink_() async {
    final link = _shareLink;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    _log.debug('ShareCredentials: sharing link (copied to clipboard first)');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ссылка скопирована в буфер'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    Share.share(_shareText);
  }

  Future<void> _shareQrImage() async {
    final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    _log.debug('ShareCredentials: capturing QR image');
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/simplevpn_qr.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    _log.debug('ShareCredentials: QR image saved to ${file.path}');

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'RKNPNH VPN — конфиг для ${widget.username}',
    );
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Поделиться доступом')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_serverConfig == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Поделиться доступом')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Конфигурация сервера не найдена.\nСначала настройте сервер.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final hasConfig = _shareLink != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Поделиться доступом')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                    'Содержит пароль пользователя. '
                    'Передавайте только по защищённому каналу.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Text('Сервер', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _infoRow('Адрес', _serverConfig!.server),
          if (_serverConfig!.sni.isNotEmpty)
            _infoRow('SNI', _serverConfig!.sni),

          const SizedBox(height: 16),

          Text('Пользователь', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _infoRow('Логин', widget.username),

          if (widget.prefilledPassword == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                helperText: 'Введите пароль, установленный для этого пользователя',
                border: OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 24),

          if (hasConfig) ...[
            Center(
              child: RepaintBoundary(
                key: _qrKey,
                child: QrImageView(
                  data: _shareLink!,
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(8),
                  errorStateBuilder: (ctx, err) => const SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(
                      child: Text(
                        'QR слишком большой — уменьшите поля',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareQrImage,
                    icon: const Icon(Icons.image),
                    label: const Text('QR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.copy),
                    label: const Text('Копировать'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _shareLink_,
              icon: const Icon(Icons.share),
              label: const Text('Отправить ссылку'),
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
                    'Введите пароль\nдля генерации QR и ссылки',
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
