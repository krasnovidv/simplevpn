import 'dart:convert';

class VpnConfig {
  final String server;
  final String serverKey;
  final String username;
  final String password;
  final String sni;
  final bool skipVerify;
  final String transport; // "ws" or "tls", empty = platform default
  final String fingerprint; // "chrome", "firefox", "safari", "none", empty = platform default

  static const transportOptions = ['', 'ws', 'tls'];
  static const fingerprintOptions = ['', 'chrome', 'firefox', 'safari', 'none'];

  static const transportLabels = {
    '': 'Auto (default)',
    'ws': 'WebSocket',
    'tls': 'Raw TLS',
  };

  static const fingerprintLabels = {
    '': 'Auto (default)',
    'chrome': 'Chrome',
    'firefox': 'Firefox',
    'safari': 'Safari',
    'none': 'None (Go TLS)',
  };

  VpnConfig({
    required this.server,
    required this.serverKey,
    required this.username,
    required this.password,
    required this.sni,
    this.skipVerify = false,
    this.transport = '',
    this.fingerprint = '',
  });

  factory VpnConfig.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return VpnConfig(
      server: map['server'] as String,
      serverKey: map['server_key'] as String,
      username: map['username'] as String,
      password: map['password'] as String,
      sni: (map['sni'] as String?) ?? '',
      skipVerify: (map['skip_verify'] as bool?) ?? false,
      transport: (map['transport'] as String?) ?? '',
      fingerprint: (map['fingerprint'] as String?) ?? '',
    );
  }

  String toJson() => jsonEncode({
        'server': server,
        'server_key': serverKey,
        'username': username,
        'password': password,
        'sni': sni,
        if (skipVerify) 'skip_verify': true,
        if (transport.isNotEmpty) 'transport': transport,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
      });

  VpnConfig copyWith({
    String? server,
    String? serverKey,
    String? username,
    String? password,
    String? sni,
    bool? skipVerify,
    String? transport,
    String? fingerprint,
  }) =>
      VpnConfig(
        server: server ?? this.server,
        serverKey: serverKey ?? this.serverKey,
        username: username ?? this.username,
        password: password ?? this.password,
        sni: sni ?? this.sni,
        skipVerify: skipVerify ?? this.skipVerify,
        transport: transport ?? this.transport,
        fingerprint: fingerprint ?? this.fingerprint,
      );
}
