import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Verifies the authenticity and integrity of OTA update artifacts.
///
/// The update channel intentionally accepts self-signed TLS certificates so it
/// works against IP-mode deployments, which means the transport provides no
/// integrity guarantee. Instead, trust is anchored in the shared `server_key`
/// (the same secret used to derive the tunnel keys, delivered to the client as
/// `server_key` in the VPN config):
///
///   * The server signs the update manifest with HMAC-SHA256 keyed by
///     `SHA-256(server_key || "update-signing")` and returns it in the
///     `X-Update-Signature` header.
///   * The signed manifest embeds `apk_sha256`, the hash of the APK binary.
///
/// A client that holds the correct `server_key` can therefore detect any
/// tampering of the manifest or the downloaded APK, defeating an on-path
/// attacker who would otherwise be able to push a malicious APK (RCE).
///
/// Mirrors `signUpdate` / `updateSigningKey` in `pkg/api/update.go`.
class UpdateVerifier {
  /// Derives the manifest-signing key from [serverKey].
  static List<int> _signingKey(String serverKey) {
    final input = <int>[
      ...utf8.encode(serverKey),
      ...utf8.encode('update-signing'),
    ];
    return sha256.convert(input).bytes;
  }

  /// Computes the expected hex-encoded HMAC-SHA256 over [body].
  static String expectedSignature(String serverKey, List<int> body) {
    final mac = Hmac(sha256, _signingKey(serverKey));
    return mac.convert(body).toString();
  }

  /// Returns true iff [signatureHex] matches the HMAC of [body] under
  /// [serverKey]. Comparison is constant-time. A missing/empty signature or
  /// server key fails closed (returns false).
  static bool verifyManifest({
    required String serverKey,
    required List<int> body,
    required String? signatureHex,
  }) {
    if (serverKey.isEmpty) return false;
    if (signatureHex == null || signatureHex.isEmpty) return false;
    return _constantTimeEquals(
      expectedSignature(serverKey, body),
      signatureHex.trim().toLowerCase(),
    );
  }

  /// Returns true iff [data] hashes to [expectedHex] (hex SHA-256, case
  /// insensitive). An empty expected hash fails closed.
  static bool verifyApk(Uint8List data, String expectedHex) {
    if (expectedHex.isEmpty) return false;
    final actual = sha256.convert(data).toString();
    return _constantTimeEquals(actual, expectedHex.trim().toLowerCase());
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
