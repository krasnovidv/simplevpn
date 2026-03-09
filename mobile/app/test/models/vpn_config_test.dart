import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/models/vpn_config.dart';

void main() {
  group('VpnConfig', () {
    test('fromJson parses all fields', () {
      final json = jsonEncode({
        'server': '1.2.3.4:443',
        'server_key': 'secret123',
        'username': 'alice',
        'password': 'pass456',
        'sni': 'example.com',
        'skip_verify': true,
        'transport': 'ws',
        'fingerprint': 'chrome',
      });

      final config = VpnConfig.fromJson(json);

      expect(config.server, '1.2.3.4:443');
      expect(config.serverKey, 'secret123');
      expect(config.username, 'alice');
      expect(config.password, 'pass456');
      expect(config.sni, 'example.com');
      expect(config.skipVerify, true);
      expect(config.transport, 'ws');
      expect(config.fingerprint, 'chrome');
    });

    test('fromJson defaults sni to empty string', () {
      final json = jsonEncode({
        'server': 'host:443',
        'server_key': 'key',
        'username': 'u',
        'password': 'p',
      });
      final config = VpnConfig.fromJson(json);

      expect(config.sni, '');
    });

    test('fromJson defaults transport and fingerprint to empty', () {
      final json = jsonEncode({
        'server': 'host:443',
        'server_key': 'key',
        'username': 'u',
        'password': 'p',
      });
      final config = VpnConfig.fromJson(json);

      expect(config.transport, '');
      expect(config.fingerprint, '');
    });

    test('fromJson defaults skipVerify to false', () {
      final json = jsonEncode({
        'server': 'host:443',
        'server_key': 'key',
        'username': 'u',
        'password': 'p',
      });
      final config = VpnConfig.fromJson(json);

      expect(config.skipVerify, false);
    });

    test('toJson serializes correctly', () {
      final config = VpnConfig(
        server: 'host:443',
        serverKey: 'key',
        username: 'alice',
        password: 'pass',
        sni: 'example.com',
      );
      final map = jsonDecode(config.toJson()) as Map<String, dynamic>;

      expect(map['server'], 'host:443');
      expect(map['server_key'], 'key');
      expect(map['username'], 'alice');
      expect(map['password'], 'pass');
      expect(map['sni'], 'example.com');
      expect(map.containsKey('skip_verify'), false);
    });

    test('toJson omits transport and fingerprint when empty', () {
      final config = VpnConfig(
        server: 'host:443',
        serverKey: 'key',
        username: 'alice',
        password: 'pass',
        sni: '',
      );
      final map = jsonDecode(config.toJson()) as Map<String, dynamic>;

      expect(map.containsKey('transport'), false);
      expect(map.containsKey('fingerprint'), false);
    });

    test('toJson includes transport and fingerprint when set', () {
      final config = VpnConfig(
        server: 'host:443',
        serverKey: 'key',
        username: 'alice',
        password: 'pass',
        sni: '',
        transport: 'tls',
        fingerprint: 'firefox',
      );
      final map = jsonDecode(config.toJson()) as Map<String, dynamic>;

      expect(map['transport'], 'tls');
      expect(map['fingerprint'], 'firefox');
    });

    test('toJson includes skip_verify when true', () {
      final config = VpnConfig(
        server: 'host:443',
        serverKey: 'key',
        username: 'alice',
        password: 'pass',
        sni: '',
        skipVerify: true,
      );
      final map = jsonDecode(config.toJson()) as Map<String, dynamic>;

      expect(map['skip_verify'], true);
    });

    test('copyWith creates modified copy', () {
      final original = VpnConfig(
        server: 'a:1',
        serverKey: 'b',
        username: 'u',
        password: 'p',
        sni: 'c',
      );
      final modified = original.copyWith(server: 'x:2', skipVerify: true);

      expect(modified.server, 'x:2');
      expect(modified.serverKey, 'b');
      expect(modified.username, 'u');
      expect(modified.password, 'p');
      expect(modified.sni, 'c');
      expect(modified.skipVerify, true);
      expect(original.skipVerify, false);
    });

    test('fromJson roundtrip', () {
      final config = VpnConfig(
        server: '10.0.0.1:443',
        serverKey: 'mysecret',
        username: 'alice',
        password: 'strongpass',
        sni: 'vpn.test.com',
        skipVerify: true,
        transport: 'ws',
        fingerprint: 'safari',
      );
      final restored = VpnConfig.fromJson(config.toJson());

      expect(restored.server, config.server);
      expect(restored.serverKey, config.serverKey);
      expect(restored.username, config.username);
      expect(restored.password, config.password);
      expect(restored.sni, config.sni);
      expect(restored.skipVerify, config.skipVerify);
      expect(restored.transport, config.transport);
      expect(restored.fingerprint, config.fingerprint);
    });

    test('copyWith updates transport and fingerprint', () {
      final original = VpnConfig(
        server: 'a:1',
        serverKey: 'b',
        username: 'u',
        password: 'p',
        sni: 'c',
        transport: 'ws',
        fingerprint: 'chrome',
      );
      final modified = original.copyWith(transport: 'tls', fingerprint: 'none');

      expect(modified.transport, 'tls');
      expect(modified.fingerprint, 'none');
      expect(original.transport, 'ws');
      expect(original.fingerprint, 'chrome');
    });
  });
}
