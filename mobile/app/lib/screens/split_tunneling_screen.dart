import 'package:flutter/material.dart';

import '../models/split_tunnel_config.dart';
import '../services/config_storage.dart';
import '../theme/chrome.dart';
import '../widgets/chrome/chrome_ui.dart';

/// iOS split tunneling: the tunnel is split by destination routes (CIDR),
/// since iOS has no per-app VPN for this kind of profile.
class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  final _storage = ConfigStorage();
  final _route = TextEditingController();
  SplitTunnelConfig _cfg = SplitTunnelConfig.defaultConfig;
  String? _error;

  @override
  void initState() {
    super.initState();
    _storage.getSplitTunnelConfig().then((c) {
      if (mounted) setState(() => _cfg = c);
    });
  }

  @override
  void dispose() {
    _route.dispose();
    super.dispose();
  }

  Future<void> _save(SplitTunnelConfig cfg) async {
    await _storage.setSplitTunnelConfig(cfg);
    setState(() => _cfg = cfg);
  }

  Future<void> _add() async {
    final cidr = _route.text.trim();
    final err = SplitTunnelConfig.validateCidr(cidr) ?? (_cfg.routes.contains(cidr) ? 'Уже в списке' : null);
    setState(() => _error = err);
    if (err != null) return;
    _route.clear();
    await _save(_cfg.copyWith(routes: [..._cfg.routes, cidr]));
  }

  @override
  Widget build(BuildContext context) {
    final c = Chrome.of(context);
    final modeIndex = switch (_cfg.mode) {
      SplitTunnelMode.off => 0,
      SplitTunnelMode.blocklist => 1,
      SplitTunnelMode.allowlist => 2,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('МАРШРУТЫ')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        ChromeSegmented(
          options: const ['Всё через VPN', 'Кроме этих', 'Только эти'],
          index: modeIndex,
          onChanged: (i) => _save(_cfg.copyWith(mode: SplitTunnelMode.values[[0, 2, 1][i]])),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _route,
          onSubmitted: (_) => _add(),
          decoration: InputDecoration(
            labelText: 'Сеть (CIDR)',
            hintText: '192.168.0.0/16',
            errorText: _error,
            suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: _add),
          ),
        ),
        const SizedBox(height: 16),
        if (_cfg.routes.isEmpty)
          Text('Маршрутов пока нет', style: bodyStyle(c))
        else
          ChromeCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final r in _cfg.routes)
                ListTile(
                  title: Text(r, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                  trailing: IconButton(
                    icon: Icon(Icons.close_rounded, color: c.sub),
                    onPressed: () => _save(_cfg.copyWith(routes: [..._cfg.routes]..remove(r))),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 12),
        Text('Изменения вступят в силу после переподключения.', style: bodyStyle(c, size: 13)),
      ]),
    );
  }
}
