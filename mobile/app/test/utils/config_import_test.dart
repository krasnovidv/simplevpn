import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/utils/config_import.dart';

void main() {
  const goodMap = {
    'server': '193.23.3.93:443',
    'server_key': 'abcd1234',
    'username': 'alice',
    'password': 's3cret',
    'sni': 'example.com',
  };
  final goodJson = jsonEncode(goodMap);

  String joinLink(String json) => buildJoinLink(json, '193.23.3.93');
  String deepLink(String json) {
    final b64 = Uri.parse(joinLink(json)).fragment;
    return 'simplevpn://connect/$b64';
  }

  group('parseImportedConfig accepts', () {
    test('raw JSON', () {
      final c = parseImportedConfig(goodJson);
      expect(c.server, '193.23.3.93:443');
      expect(c.username, 'alice');
      expect(c.sni, 'example.com');
    });

    test('JSON with surrounding whitespace', () {
      final c = parseImportedConfig('  $goodJson \n');
      expect(c.password, 's3cret');
    });

    test('join http link', () {
      final c = parseImportedConfig(joinLink(goodJson));
      expect(c.server, '193.23.3.93:443');
      expect(c.serverKey, 'abcd1234');
    });

    test('simplevpn deep link', () {
      final c = parseImportedConfig(deepLink(goodJson));
      expect(c.username, 'alice');
    });
  });

  group('parseImportedConfig rejects with friendly message', () {
    test('empty input', () {
      expect(() => parseImportedConfig('   '),
          throwsA(isA<ConfigImportException>()));
    });

    test('missing server field', () {
      final m = Map<String, dynamic>.from(goodMap)..remove('server');
      expect(
        () => parseImportedConfig(jsonEncode(m)),
        throwsA(predicate((e) =>
            e is ConfigImportException && e.message.contains('сервер'))),
      );
    });

    test('missing password', () {
      final m = Map<String, dynamic>.from(goodMap)..remove('password');
      expect(
        () => parseImportedConfig(jsonEncode(m)),
        throwsA(predicate((e) =>
            e is ConfigImportException && e.message.contains('пароль'))),
      );
    });

    test('bad server (no port)', () {
      final m = Map<String, dynamic>.from(goodMap)..['server'] = '193.23.3.93';
      expect(
        () => parseImportedConfig(jsonEncode(m)),
        throwsA(isA<ConfigImportException>()),
      );
    });

    test('not JSON / unknown format', () {
      expect(() => parseImportedConfig('hello world'),
          throwsA(isA<ConfigImportException>()));
    });

    test('garbage JSON object missing everything', () {
      expect(() => parseImportedConfig('{"foo":"bar"}'),
          throwsA(isA<ConfigImportException>()));
    });
  });

  test('buildJoinLink round-trips through parseImportedConfig', () {
    final link = buildJoinLink(goodJson, '10.0.0.1');
    expect(link, startsWith('http://10.0.0.1:8080/join#'));
    final c = parseImportedConfig(link);
    expect(c.server, '193.23.3.93:443');
  });
}
