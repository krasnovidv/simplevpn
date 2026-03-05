import 'package:flutter/material.dart';
import '../services/vpn_service.dart';
import '../services/config_storage.dart';
import '../models/vpn_config.dart';
import 'settings_screen.dart';
import 'log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _vpnService = VpnService();
  final _storage = ConfigStorage();
  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _config;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _vpnService.addListener((status) {
      setState(() => _status = status);
    });
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _storage.loadConfig();
    setState(() => _config = config);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SimpleVPN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Connection Log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadConfig();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status icon
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor.withValues(alpha: 0.15),
                  border: Border.all(color: _statusColor, width: 3),
                ),
                child: Icon(_statusIcon, size: 64, color: _statusColor),
              ),

              const SizedBox(height: 24),

              // Status text
              Text(
                _statusText,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),

              const SizedBox(height: 8),

              // Server info
              if (_config != null)
                Text(
                  _config!.server,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),

              if (_config == null)
                Text(
                  'No server configured',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                      ),
                ),

              const SizedBox(height: 48),

              // Connect/Disconnect button
              SizedBox(
                width: 220,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _config != null ? _toggleConnection : null,
                  icon: Icon(_status == VpnStatus.connected
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(
                    _status == VpnStatus.connected
                        ? 'Disconnect'
                        : _status == VpnStatus.connecting
                            ? 'Connecting...'
                            : 'Connect',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _status == VpnStatus.connected
                        ? colorScheme.error
                        : null,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Configure button (when no config)
              if (_config == null)
                TextButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    );
                    _loadConfig();
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Configure Server'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _statusIcon => switch (_status) {
        VpnStatus.connected => Icons.shield_rounded,
        VpnStatus.connecting => Icons.hourglass_top_rounded,
        VpnStatus.error => Icons.error_outline_rounded,
        VpnStatus.disconnected => Icons.shield_outlined,
      };

  Color get _statusColor => switch (_status) {
        VpnStatus.connected => Colors.green,
        VpnStatus.connecting => Colors.orange,
        VpnStatus.error => Colors.red,
        VpnStatus.disconnected => Colors.grey,
      };

  String get _statusText => switch (_status) {
        VpnStatus.connected => 'Protected',
        VpnStatus.connecting => 'Connecting...',
        VpnStatus.error => 'Error',
        VpnStatus.disconnected => 'Not Connected',
      };

  void _toggleConnection() {
    if (_status == VpnStatus.connected) {
      _vpnService.disconnect();
    } else if (_config != null) {
      _vpnService.connect(_config!.toJson());
    }
  }
}
