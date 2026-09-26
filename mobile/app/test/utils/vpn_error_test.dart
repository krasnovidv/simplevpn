import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/utils/vpn_error.dart';

void main() {
  test('auth kind maps to credentials message', () {
    expect(friendlyVpnError('auth', null), 'Неверный логин или пароль');
    expect(friendlyVpnError('transient', 'invalid password'),
        'Неверный логин или пароль');
  });

  test('network errors map to no-network', () {
    expect(friendlyVpnError('transient', 'Failed host lookup: api'),
        'Нет подключения к сети');
    expect(friendlyVpnError('transient', 'Network is unreachable'),
        'Нет подключения к сети');
  });

  test('timeout/refused map to server-unreachable', () {
    expect(friendlyVpnError('transient', 'dial tcp: i/o timeout'),
        'Сервер недоступен');
    expect(friendlyVpnError('transient', 'connection refused'),
        'Сервер недоступен');
  });

  test('unknown falls back to generic', () {
    expect(friendlyVpnError('fatal', 'some weird thing'), 'Ошибка соединения');
    expect(friendlyVpnError('transient', null), 'Ошибка соединения');
  });

  test('network failure during auth is not a credentials error', () {
    expect(friendlyVpnError('transient', 'auth response: read tcp: i/o timeout'),
        'Сервер недоступен');
  });

  test('stalled tunnel and kill switch have their own messages', () {
    expect(friendlyVpnError('transient', 'tunnel stalled: no data from server'),
        'Сервер перестал отвечать');
    expect(friendlyVpnError('transient', 'blocked (kill switch)'),
        'Рубильник держит трафик: VPN упал, наружу ничего не уходит');
  });
}
