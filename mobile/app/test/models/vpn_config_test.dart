import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/models/vpn_config.dart';

void main() {
  group('VpnConfig', () {
    test('fromJson parses all fields', () {
      final json = jsonEncode({
        'server': '1.2.3.4:443',
        'psk': 'secret123',
        'sni': 'example.com',
        'skip_verify': true,
      });

      final config = VpnConfig.fromJson(json);

      expect(config.server, '1.2.3.4:443');
      expect(config.psk, 'secret123');
      expect(config.sni, 'example.com');
      expect(config.skipVerify, true);
    });

    test('fromJson defaults sni to empty string', () {
      final json = jsonEncode({'server': 'host:443', 'psk': 'key'});
      final config = VpnConfig.fromJson(json);

      expect(config.sni, '');
    });

    test('fromJson defaults skipVerify to false', () {
      final json = jsonEncode({'server': 'host:443', 'psk': 'key'});
      final config = VpnConfig.fromJson(json);

      expect(config.skipVerify, false);
    });

    test('toJson serializes correctly', () {
      final config = VpnConfig(
        server: 'host:443',
        psk: 'key',
        sni: 'example.com',
      );
      final map = jsonDecode(config.toJson()) as Map<String, dynamic>;

      expect(map['server'], 'host:443');
      expect(map['psk'], 'key');
      expect(map['sni'], 'example.com');
      expect(map.containsKey('skip_verify'), false);
    });

    test('toJson includes skip_verify when true', () {
      final config = VpnConfig(
        server: 'host:443',
        psk: 'key',
        sni: '',
        skipVerify: true,
      );
      final map = jsonDecode(config.toJson()) as Map<String, dynamic>;

      expect(map['skip_verify'], true);
    });

    test('copyWith creates modified copy', () {
      final original = VpnConfig(server: 'a:1', psk: 'b', sni: 'c');
      final modified = original.copyWith(server: 'x:2', skipVerify: true);

      expect(modified.server, 'x:2');
      expect(modified.psk, 'b');
      expect(modified.sni, 'c');
      expect(modified.skipVerify, true);
      expect(original.skipVerify, false);
    });

    test('fromJson roundtrip', () {
      final config = VpnConfig(
        server: '10.0.0.1:443',
        psk: 'mysecret',
        sni: 'vpn.test.com',
        skipVerify: true,
      );
      final restored = VpnConfig.fromJson(config.toJson());

      expect(restored.server, config.server);
      expect(restored.psk, config.psk);
      expect(restored.sni, config.sni);
      expect(restored.skipVerify, config.skipVerify);
    });
  });
}
