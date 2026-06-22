import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplevpn/services/update_verifier.dart';

void main() {
  group('UpdateVerifier.verifyManifest', () {
    // Known-answer vector shared with the Go server. The identical vector is
    // asserted in pkg/api/update_sign_test.go (TestSignUpdateKnownAnswer). If
    // this fails, the client and server signing schemes have diverged.
    const serverKey = 'test-server-key';
    const body = '{"apk_sha256":"abc123","version":"1.0.0","versionCode":7}';
    const sig =
        'f7d9d4b65e95ee7ca0e271cf3baa0ac92dffc1d68602b784800dacc7b744f9d8';

    test('matches the Go known-answer vector', () {
      expect(
        UpdateVerifier.expectedSignature(serverKey, utf8.encode(body)),
        sig,
      );
    });

    test('accepts a valid signature', () {
      expect(
        UpdateVerifier.verifyManifest(
          serverKey: serverKey,
          body: utf8.encode(body),
          signatureHex: sig,
        ),
        isTrue,
      );
    });

    test('accepts case-insensitive / padded signature', () {
      expect(
        UpdateVerifier.verifyManifest(
          serverKey: serverKey,
          body: utf8.encode(body),
          signatureHex: '  ${sig.toUpperCase()}  ',
        ),
        isTrue,
      );
    });

    test('rejects a tampered body', () {
      expect(
        UpdateVerifier.verifyManifest(
          serverKey: serverKey,
          body: utf8.encode('{"version":"6.6.6"}'),
          signatureHex: sig,
        ),
        isFalse,
      );
    });

    test('rejects a wrong server key', () {
      expect(
        UpdateVerifier.verifyManifest(
          serverKey: 'attacker-key',
          body: utf8.encode(body),
          signatureHex: sig,
        ),
        isFalse,
      );
    });

    test('fails closed on missing signature', () {
      expect(
        UpdateVerifier.verifyManifest(
          serverKey: serverKey,
          body: utf8.encode(body),
          signatureHex: null,
        ),
        isFalse,
      );
    });

    test('fails closed on empty server key', () {
      expect(
        UpdateVerifier.verifyManifest(
          serverKey: '',
          body: utf8.encode(body),
          signatureHex: sig,
        ),
        isFalse,
      );
    });
  });

  group('UpdateVerifier.verifyApk', () {
    test('accepts matching hash', () {
      final data = Uint8List.fromList(utf8.encode('hello world'));
      // sha256("hello world")
      const hash =
          'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
      expect(UpdateVerifier.verifyApk(data, hash), isTrue);
    });

    test('rejects mismatched hash', () {
      final data = Uint8List.fromList(utf8.encode('malicious payload'));
      const hash =
          'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
      expect(UpdateVerifier.verifyApk(data, hash), isFalse);
    });

    test('fails closed on empty expected hash', () {
      final data = Uint8List.fromList(utf8.encode('anything'));
      expect(UpdateVerifier.verifyApk(data, ''), isFalse);
    });
  });
}
