import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/split_tunnel_config.dart';
import '../services/config_storage.dart';

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('com.simplevpn/vpn');
  final _storage = ConfigStorage();

  SplitTunnelConfig _config = SplitTunnelConfig.defaultConfig;
  bool _loaded = false;

  // Android
  List<Map<String, String>> _installedApps = [];
  bool _appsLoading = false;
  String _appSearch = '';

  // iOS route input
  final _routeCtrl = TextEditingController();
  String? _routeError;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final config = await _storage.getSplitTunnelConfig();
    setState(() {
      _config = config;
      _loaded = true;
    });
    if (Platform.isAndroid && _installedApps.isEmpty) _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _appsLoading = true);
    try {
      final raw = await _channel.invokeMethod<List>('listInstalledApps');
      final apps = (raw ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
      setState(() => _installedApps = apps);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки приложений: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _appsLoading = false);
    }
  }

  Future<void> _setMode(SplitTunnelMode? mode) async {
    if (mode == null) return;
    final updated = _config.copyWith(mode: mode);
    await _storage.setSplitTunnelConfig(updated);
    setState(() => _config = updated);
    _showReconnectSnack();
  }

  Future<void> _toggleApp(String pkg) async {
    final apps = List<String>.from(_config.apps);
    if (apps.contains(pkg)) {
      apps.remove(pkg);
    } else {
      apps.add(pkg);
    }
    final updated = _config.copyWith(apps: apps);
    await _storage.setSplitTunnelConfig(updated);
    setState(() => _config = updated);
    _showReconnectSnack();
  }

  Future<void> _addRoute() async {
    final cidr = _routeCtrl.text.trim();
    final err = SplitTunnelConfig.validateCidr(cidr);
    if (err != null) {
      setState(() => _routeError = err);
      return;
    }
    if (_config.routes.contains(cidr)) {
      setState(() => _routeError = 'Уже в списке');
      return;
    }
    final routes = [..._config.routes, cidr];
    final updated = _config.copyWith(routes: routes);
    await _storage.setSplitTunnelConfig(updated);
    setState(() {
      _config = updated;
      _routeError = null;
    });
    _routeCtrl.clear();
    _showReconnectSnack();
  }

  Future<void> _removeRoute(String cidr) async {
    final routes = List<String>.from(_config.routes)..remove(cidr);
    final updated = _config.copyWith(routes: routes);
    await _storage.setSplitTunnelConfig(updated);
    setState(() => _config = updated);
    _showReconnectSnack();
  }

  void _showReconnectSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Для применения изменений переподключитесь')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Раздельное туннелирование'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Приложения', icon: Icon(Icons.apps)),
            Tab(text: 'Маршруты', icon: Icon(Icons.route)),
          ],
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildModeSelector(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAppsTab(),
                      _buildRoutesTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: DropdownButtonFormField<SplitTunnelMode>(
        value: _config.mode,
        decoration: const InputDecoration(
          labelText: 'Режим',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: SplitTunnelMode.off, child: Text('Выкл — полный туннель')),
          DropdownMenuItem(value: SplitTunnelMode.allowlist, child: Text('Разрешённые — только выбранные')),
          DropdownMenuItem(value: SplitTunnelMode.blocklist, child: Text('Заблокированные — кроме выбранных')),
        ],
        onChanged: _setMode,
      ),
    );
  }

  Widget _buildAppsTab() {
    if (!Platform.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Раздельное туннелирование по приложениям доступно только на Android.\nИспользуйте вкладку «Маршруты» на iOS.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_appsLoading) return const Center(child: CircularProgressIndicator());

    final filtered = _appSearch.isEmpty
        ? _installedApps
        : _installedApps.where((a) {
            final q = _appSearch.toLowerCase();
            return (a['label'] ?? '').toLowerCase().contains(q) ||
                (a['packageName'] ?? '').toLowerCase().contains(q);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Поиск приложений',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _appSearch = v),
          ),
        ),
        if (_config.mode == SplitTunnelMode.off)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Включите режим для выбора приложений.'),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final app = filtered[i];
              final pkg = app['packageName'] ?? '';
              final label = app['label'] ?? pkg;
              final selected = _config.apps.contains(pkg);
              return CheckboxListTile(
                title: Text(label),
                subtitle: Text(pkg, style: const TextStyle(fontSize: 11)),
                value: selected,
                onChanged: _config.mode == SplitTunnelMode.off
                    ? null
                    : (_) => _toggleApp(pkg),
                secondary: app['iconBase64']?.isNotEmpty == true
                    ? Image.memory(
                        Uri.parse('data:image/png;base64,${app['iconBase64']}')
                            .data!
                            .contentAsBytes(),
                        width: 32,
                        height: 32,
                        errorBuilder: (_, __, ___) => const Icon(Icons.android),
                      )
                    : const Icon(Icons.android),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRoutesTab() {
    if (Platform.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Маршрутизация по CIDR настраивается на iOS.\nИспользуйте вкладку «Приложения» на Android.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _routeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Добавить CIDR (напр. 192.168.1.0/24)',
                    border: const OutlineInputBorder(),
                    errorText: _routeError,
                  ),
                  onChanged: (_) => setState(() => _routeError = null),
                  onSubmitted: (_) => _addRoute(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: _config.mode == SplitTunnelMode.off ? null : _addRoute,
                tooltip: 'Добавить маршрут',
              ),
            ],
          ),
        ),
        if (_config.mode == SplitTunnelMode.off)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Включите режим для настройки маршрутов.'),
          ),
        Expanded(
          child: _config.routes.isEmpty
              ? const Center(child: Text('Маршруты не добавлены.'))
              : ListView.builder(
                  itemCount: _config.routes.length,
                  itemBuilder: (_, i) {
                    final cidr = _config.routes[i];
                    return ListTile(
                      title: Text(cidr),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _config.mode == SplitTunnelMode.off
                            ? null
                            : () => _removeRoute(cidr),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _routeCtrl.dispose();
    super.dispose();
  }
}
