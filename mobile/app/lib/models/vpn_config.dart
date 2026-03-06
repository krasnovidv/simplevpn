import 'dart:convert';

class VpnConfig {
  final String server;
  final String psk;
  final String sni;
  final bool skipVerify;

  VpnConfig({
    required this.server,
    required this.psk,
    required this.sni,
    this.skipVerify = false,
  });

  factory VpnConfig.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return VpnConfig(
      server: map['server'] as String,
      psk: map['psk'] as String,
      sni: (map['sni'] as String?) ?? '',
      skipVerify: (map['skip_verify'] as bool?) ?? false,
    );
  }

  String toJson() => jsonEncode({
        'server': server,
        'psk': psk,
        'sni': sni,
        if (skipVerify) 'skip_verify': true,
      });

  VpnConfig copyWith({String? server, String? psk, String? sni, bool? skipVerify}) =>
      VpnConfig(
        server: server ?? this.server,
        psk: psk ?? this.psk,
        sni: sni ?? this.sni,
        skipVerify: skipVerify ?? this.skipVerify,
      );
}
