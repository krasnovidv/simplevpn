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

  /// Additional "host:port" addresses tried, in order, when [server] does not
  /// answer. A move between hosting providers changes only the address — the
  /// server key and accounts stay the same — so knowing several addresses lets
  /// the app survive the move without the user re-importing anything.
  /// The address that actually connects is promoted to [server] afterwards.
  final List<String> endpoints;

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
    this.endpoints = const [],
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
      endpoints: parseEndpoints(map['endpoints']),
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
        if (endpoints.isNotEmpty) 'endpoints': endpoints,
      });

  /// Coerces an untrusted `endpoints` value into a clean ordered list. Anything
  /// that is not a non-empty string is dropped rather than failing the whole
  /// import — a malformed fallback list must never cost the user a working
  /// primary address.
  static List<String> parseEndpoints(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      if (e is! String) continue;
      final v = e.trim();
      if (v.isEmpty || out.contains(v)) continue;
      out.add(v);
    }
    return out;
  }

  /// Makes [address] the primary, demoting the previous primary into the
  /// fallback list so the app can find its way back if the move is reverted.
  /// Returns `this` unchanged when [address] is already primary or empty.
  VpnConfig promoteEndpoint(String address) {
    final addr = address.trim();
    if (addr.isEmpty || addr == server) return this;
    final rest = <String>[
      if (server.trim().isNotEmpty) server.trim(),
      ...endpoints.where((e) => e != addr && e != server),
    ];
    return copyWith(server: addr, endpoints: rest);
  }

  VpnConfig copyWith({
    String? server,
    String? serverKey,
    String? username,
    String? password,
    String? sni,
    bool? skipVerify,
    String? transport,
    String? fingerprint,
    List<String>? endpoints,
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
        endpoints: endpoints ?? this.endpoints,
      );
}
