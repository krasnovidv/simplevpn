import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/utils/vpn_error.dart';

void main() {
  test('auth kind maps to credentials message', () {
    expect(friendlyVpnError('auth', null), 'НЕВЕРНЫЙ ЛОГИН ИЛИ ПАРОЛЬ');
    expect(friendlyVpnError('transient', 'invalid password'),
        'НЕВЕРНЫЙ ЛОГИН ИЛИ ПАРОЛЬ');
  });

  test('network errors map to no-network', () {
    expect(friendlyVpnError('transient', 'Failed host lookup: api'),
        'НЕТ ПОДКЛЮЧЕНИЯ К СЕТИ');
    expect(friendlyVpnError('transient', 'Network is unreachable'),
        'НЕТ ПОДКЛЮЧЕНИЯ К СЕТИ');
  });

  test('timeout/refused map to server-unreachable', () {
    expect(friendlyVpnError('transient', 'dial tcp: i/o timeout'),
        'СЕРВЕР НЕДОСТУПЕН');
    expect(friendlyVpnError('transient', 'connection refused'),
        'СЕРВЕР НЕДОСТУПЕН');
  });

  test('unknown falls back to generic', () {
    expect(friendlyVpnError('fatal', 'some weird thing'), 'ОШИБКА СОЕДИНЕНИЯ');
    expect(friendlyVpnError('transient', null), 'ОШИБКА СОЕДИНЕНИЯ');
  });

  test('network failure during auth is not a credentials error', () {
    expect(friendlyVpnError('transient', 'auth response: read tcp: i/o timeout'),
        'СЕРВЕР НЕДОСТУПЕН');
  });

  test('stalled tunnel and kill switch have their own messages', () {
    expect(friendlyVpnError('transient', 'tunnel stalled: no data from server'),
        'СЕРВЕР ПЕРЕСТАЛ ОТВЕЧАТЬ');
    expect(friendlyVpnError('transient', 'blocked (kill switch)'),
        'ТРАФИК ЗАБЛОКИРОВАН (KILL SWITCH)');
  });
}
