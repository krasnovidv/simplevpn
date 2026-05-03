import 'dart:convert';

enum SplitTunnelMode { off, allowlist, blocklist }

class SplitTunnelConfig {
  final SplitTunnelMode mode;
  final List<String> apps;    // Android package names
  final List<String> routes;  // iOS CIDR strings

  const SplitTunnelConfig({
    this.mode = SplitTunnelMode.off,
    this.apps = const [],
    this.routes = const [],
  });

  static SplitTunnelConfig get defaultConfig => const SplitTunnelConfig();

  static SplitTunnelMode _modeFromString(String? s) => switch (s) {
    'allowlist' => SplitTunnelMode.allowlist,
    'blocklist' => SplitTunnelMode.blocklist,
    _ => SplitTunnelMode.off,
  };

  static String _modeToString(SplitTunnelMode m) => switch (m) {
    SplitTunnelMode.off => 'off',
    SplitTunnelMode.allowlist => 'allowlist',
    SplitTunnelMode.blocklist => 'blocklist',
  };

  SplitTunnelConfig copyWith({
    SplitTunnelMode? mode,
    List<String>? apps,
    List<String>? routes,
  }) =>
      SplitTunnelConfig(
        mode: mode ?? this.mode,
        apps: apps ?? this.apps,
        routes: routes ?? this.routes,
      );

  // CIDR validator: accepts "a.b.c.d/n" where n is 0–32.
  static String? validateCidr(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return 'Invalid CIDR format';
    final ipParts = parts[0].split('.');
    if (ipParts.length != 4) return 'Invalid IP address';
    for (final octet in ipParts) {
      final n = int.tryParse(octet);
      if (n == null || n < 0 || n > 255) return 'Invalid IP octet: $octet';
    }
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return 'Prefix must be 0–32';
    return null;
  }

  Map<String, dynamic> toJson() => {
    'mode': _modeToString(mode),
    'apps': apps,
    'routes': routes,
  };

  factory SplitTunnelConfig.fromJson(Map<String, dynamic> map) => SplitTunnelConfig(
    mode: _modeFromString(map['mode'] as String?),
    apps: (map['apps'] as List?)?.cast<String>() ?? [],
    routes: (map['routes'] as List?)?.cast<String>() ?? [],
  );

  factory SplitTunnelConfig.fromJsonString(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return SplitTunnelConfig.fromJson(map);
    } catch (_) {
      return SplitTunnelConfig.defaultConfig;
    }
  }

  String toJsonString() => jsonEncode(toJson());
}
