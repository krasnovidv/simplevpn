/// Maps a VPN error (kind + raw technical message) to a short, human-readable
/// Russian phrase suitable for the status line (sentence case). The raw message stays in the
/// logs; users see a cause, not a stack-trace fragment.
String friendlyVpnError(String kind, String? message) {
  final m = (message ?? '').toLowerCase();

  if (m.contains('kill switch')) return 'Рубильник держит трафик: VPN упал, наружу ничего не уходит';

  // Only an explicit rejection means bad credentials; "auth response: i/o
  // timeout" is the network failing mid-handshake.
  if (kind == 'auth' ||
      m.contains('auth rejected') ||
      m.contains('credential') ||
      m.contains('unauthorized') ||
      m.contains('invalid password') ||
      m.contains('invalid user')) {
    return 'Неверный логин или пароль';
  }

  if (m.contains('no route') ||
      m.contains('network is unreachable') ||
      m.contains('no address associated') ||
      m.contains('failed host lookup') ||
      m.contains('offline') ||
      m.contains('no internet')) {
    return 'Нет подключения к сети';
  }

  if (m.contains('stalled')) return 'Сервер перестал отвечать';

  if (m.contains('x509') || m.contains('certificate')) {
    return 'Ошибка сертификата сервера';
  }

  if (m.contains('timeout') ||
      m.contains('timed out') ||
      m.contains('refused') ||
      m.contains('unreachable') ||
      m.contains('connection reset') ||
      m.contains('dial')) {
    return 'Сервер недоступен';
  }

  return 'Ошибка соединения';
}
