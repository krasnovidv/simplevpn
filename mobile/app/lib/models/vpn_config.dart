import 'dart:convert';

class VpnConfig {
  final String server;
  final String psk;
  final String sni;

  VpnConfig({
    required this.server,
    required this.psk,
    required this.sni,
  });

  factory VpnConfig.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return VpnConfig(
      server: map['server'] as String,
      psk: map['psk'] as String,
      sni: (map['sni'] as String?) ?? '',
    );
  }

  String toJson() => jsonEncode({
        'server': server,
        'psk': psk,
        'sni': sni,
      });

  VpnConfig copyWith({String? server, String? psk, String? sni}) => VpnConfig(
        server: server ?? this.server,
        psk: psk ?? this.psk,
        sni: sni ?? this.sni,
      );
}
