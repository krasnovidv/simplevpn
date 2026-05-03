import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/services/vpn_service.dart';

void main() {
  group('vpnStatusFromResult — String inputs (legacy/Android polling)', () {
    test('"connected" → VpnStatusConnected', () {
      expect(vpnStatusFromResult('connected'), isA<VpnStatusConnected>());
    });

    test('"connecting" → VpnStatusConnecting', () {
      expect(vpnStatusFromResult('connecting'), isA<VpnStatusConnecting>());
    });

    test('"disconnected" → VpnStatusDisconnected', () {
      expect(vpnStatusFromResult('disconnected'), isA<VpnStatusDisconnected>());
    });

    test('"unknown" → VpnStatusDisconnected', () {
      expect(vpnStatusFromResult('unknown'), isA<VpnStatusDisconnected>());
    });

    test('"connecting (retry 3/5)" → VpnStatusReconnecting(attempt:3, max:5)', () {
      final s = vpnStatusFromResult('connecting (retry 3/5)');
      expect(s, isA<VpnStatusReconnecting>());
      final r = s as VpnStatusReconnecting;
      expect(r.attempt, 3);
      expect(r.max, 5);
    });

    test('"connecting (retry 1/10)" → VpnStatusReconnecting(attempt:1, max:10)', () {
      final s = vpnStatusFromResult('connecting (retry 1/10)');
      final r = s as VpnStatusReconnecting;
      expect(r.attempt, 1);
      expect(r.max, 10);
    });

    test('"error: auth rejected" → VpnStatusError(errorKind:auth)', () {
      final s = vpnStatusFromResult('error: auth rejected');
      expect(s, isA<VpnStatusError>());
      final e = s as VpnStatusError;
      expect(e.errorKind, 'auth');
      expect(e.message, 'auth rejected');
    });

    test('"error: connection fatal" → VpnStatusError(errorKind:fatal)', () {
      final s = vpnStatusFromResult('error: connection fatal');
      final e = s as VpnStatusError;
      expect(e.errorKind, 'fatal');
    });

    test('"error: timeout" → VpnStatusError(errorKind:transient)', () {
      final s = vpnStatusFromResult('error: timeout');
      final e = s as VpnStatusError;
      expect(e.errorKind, 'transient');
      expect(e.message, 'timeout');
    });
  });

  group('vpnStatusFromResult — Map inputs (structured protocol)', () {
    test('state:connected → VpnStatusConnected', () {
      expect(vpnStatusFromResult({'state': 'connected'}), isA<VpnStatusConnected>());
    });

    test('state:connecting → VpnStatusConnecting', () {
      expect(vpnStatusFromResult({'state': 'connecting'}), isA<VpnStatusConnecting>());
    });

    test('state:disconnected → VpnStatusDisconnected', () {
      expect(vpnStatusFromResult({'state': 'disconnected'}), isA<VpnStatusDisconnected>());
    });

    test('state:reconnecting carries attempt and max', () {
      final s = vpnStatusFromResult({'state': 'reconnecting', 'attempt': 2, 'max': 5});
      expect(s, isA<VpnStatusReconnecting>());
      final r = s as VpnStatusReconnecting;
      expect(r.attempt, 2);
      expect(r.max, 5);
    });

    test('state:error carries errorKind and message', () {
      final s = vpnStatusFromResult({
        'state': 'error',
        'errorKind': 'auth',
        'errorMessage': 'auth rejected',
      });
      expect(s, isA<VpnStatusError>());
      final e = s as VpnStatusError;
      expect(e.errorKind, 'auth');
      expect(e.message, 'auth rejected');
    });

    test('state:error defaults errorKind to transient', () {
      final s = vpnStatusFromResult({'state': 'error'});
      final e = s as VpnStatusError;
      expect(e.errorKind, 'transient');
      expect(e.message, isNull);
    });

    test('unknown state → VpnStatusDisconnected', () {
      expect(vpnStatusFromResult({'state': 'bogus'}), isA<VpnStatusDisconnected>());
    });

    test('null input → VpnStatusDisconnected', () {
      expect(vpnStatusFromResult(null), isA<VpnStatusDisconnected>());
    });
  });

  group('VpnStatus value equality', () {
    test('VpnStatusConnected instances are equal', () {
      expect(const VpnStatusConnected(), equals(const VpnStatusConnected()));
    });

    test('VpnStatusReconnecting equality uses attempt and max', () {
      const a = VpnStatusReconnecting(attempt: 1, max: 5);
      const b = VpnStatusReconnecting(attempt: 1, max: 5);
      const c = VpnStatusReconnecting(attempt: 2, max: 5);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('VpnStatusError equality uses message and errorKind', () {
      const a = VpnStatusError(message: 'timeout', errorKind: 'transient');
      const b = VpnStatusError(message: 'timeout', errorKind: 'transient');
      const c = VpnStatusError(message: 'other', errorKind: 'transient');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('different status types are not equal', () {
      expect(
        const VpnStatusConnected(),
        isNot(equals(const VpnStatusDisconnected())),
      );
    });
  });
}
