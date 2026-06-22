/// Maps a VPN error (kind + raw technical message) to a short, human-readable
/// Russian phrase suitable for the status line. The raw message stays in the
/// logs; users see a cause, not a stack-trace fragment.
String friendlyVpnError(String kind, String? message) {
  final m = (message ?? '').toLowerCase();

  if (kind == 'auth' ||
      m.contains('auth') ||
      m.contains('credential') ||
      m.contains('unauthorized') ||
      m.contains('invalid password') ||
      m.contains('invalid user')) {
    return 'НЕВЕРНЫЙ ЛОГИН ИЛИ ПАРОЛЬ';
  }

  if (m.contains('no route') ||
      m.contains('network is unreachable') ||
      m.contains('no address associated') ||
      m.contains('failed host lookup') ||
      m.contains('offline') ||
      m.contains('no internet')) {
    return 'НЕТ ПОДКЛЮЧЕНИЯ К СЕТИ';
  }

  if (m.contains('timeout') ||
      m.contains('timed out') ||
      m.contains('refused') ||
      m.contains('unreachable') ||
      m.contains('connection reset') ||
      m.contains('dial')) {
    return 'СЕРВЕР НЕДОСТУПЕН';
  }

  return 'ОШИБКА СОЕДИНЕНИЯ';
}
