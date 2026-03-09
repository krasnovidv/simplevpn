import 'dart:convert';

class VpnConfig {
  final String server;
  final String serverKey;
  final String username;
  final String password;
  final String sni;
  final bool skipVerify;

  VpnConfig({
    required this.server,
    required this.serverKey,
    required this.username,
    required this.password,
    required this.sni,
    this.skipVerify = false,
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
    );
  }

  String toJson() => jsonEncode({
        'server': server,
        'server_key': serverKey,
        'username': username,
        'password': password,
        'sni': sni,
        if (skipVerify) 'skip_verify': true,
      });

  VpnConfig copyWith({
    String? server,
    String? serverKey,
    String? username,
    String? password,
    String? sni,
    bool? skipVerify,
  }) =>
      VpnConfig(
        server: server ?? this.server,
        serverKey: serverKey ?? this.serverKey,
        username: username ?? this.username,
        password: password ?? this.password,
        sni: sni ?? this.sni,
        skipVerify: skipVerify ?? this.skipVerify,
      );
}
