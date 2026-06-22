import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../models/update_info.dart';
import 'update_verifier.dart';

const _dismissedVersionKey = 'dismissed_update_version_code';
const _pendingUpdateCodeKey = 'pending_update_version_code';
const _pendingUpdateVersionKey = 'pending_update_version';
const _pendingUpdateChangelogKey = 'pending_update_changelog';

class UpdateService {
  static const _tag = 'UpdateService';

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _serverHost;
  String? _serverKey;

  /// Loads and caches the server host and the shared server key from the stored
  /// VPN config. The server key authenticates update manifests (see
  /// [UpdateVerifier]).
  Future<void> _loadConfig() async {
    if (_serverHost != null) return;
    final cfgStr = await _secureStorage.read(key: 'vpn_config');
    if (cfgStr == null || cfgStr.isEmpty) {
      debugPrint('[$_tag] No VPN config found in secure storage');
      return;
    }
    try {
      final map = jsonDecode(cfgStr) as Map<String, dynamic>;
      final server = map['server'] as String? ?? '';
      final host = server.split(':').first;
      if (host.isEmpty) {
        debugPrint('[$_tag] Empty host in VPN config server=$server');
        return;
      }
      _serverHost = host;
      _serverKey = map['server_key'] as String? ?? '';
      debugPrint('[$_tag] Resolved server host=$host from config');
    } catch (e) {
      debugPrint('[$_tag] Failed to parse VPN config: $e');
    }
  }

  Future<String?> _getServerHost() async {
    await _loadConfig();
    return _serverHost;
  }

  http.Client _buildClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    ioClient.connectionTimeout = const Duration(seconds: 10);
    return IOClient(ioClient);
  }

  Future<UpdateInfo?> checkForUpdate() async {
    final host = await _getServerHost();
    if (host == null) return null;

    final url = 'https://$host:8443/api/update';
    debugPrint('[$_tag] Checking for update at $url');

    final client = _buildClient();
    try {
      final resp = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      debugPrint('[$_tag] Update check response: status=${resp.statusCode}');

      if (resp.statusCode != 200) {
        debugPrint('[$_tag] Update check failed: ${resp.statusCode} ${resp.body}');
        return null;
      }

      // Verify the manifest signature before trusting any field in it. The
      // channel does not validate TLS certs, so this HMAC (keyed by the shared
      // server key) is the only thing preventing a forged update. Fail closed.
      final signature = resp.headers['x-update-signature'];
      if (!UpdateVerifier.verifyManifest(
        serverKey: _serverKey ?? '',
        body: resp.bodyBytes,
        signatureHex: signature,
      )) {
        debugPrint('[$_tag] REJECTED update: manifest signature invalid or missing');
        return null;
      }

      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(json);

      if (info.apkSha256.isEmpty) {
        debugPrint('[$_tag] REJECTED update: manifest has no apk_sha256');
        return null;
      }
      debugPrint('[$_tag] Remote version: ${info.version} (code=${info.versionCode})');

      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      debugPrint('[$_tag] Current version: ${packageInfo.version} (code=$currentCode)');

      if (info.versionCode <= currentCode) {
        debugPrint('[$_tag] No update needed (remote=${info.versionCode} <= current=$currentCode)');
        return null;
      }

      if (await isVersionDismissed(info.versionCode)) {
        debugPrint('[$_tag] Version ${info.versionCode} was dismissed by user');
        return null;
      }

      debugPrint('[$_tag] Update available: ${info.version} (code=${info.versionCode})');
      return info;
    } catch (e) {
      debugPrint('[$_tag] Update check error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> downloadApk(
    UpdateInfo info,
    void Function(double progress) onProgress,
  ) async {
    final host = await _getServerHost();
    if (host == null) return null;

    final downloadUrl = 'https://$host:8443${info.downloadUrl}';
    debugPrint('[$_tag] Downloading APK from $downloadUrl');

    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final request = await ioClient.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        debugPrint('[$_tag] Download failed: status=${response.statusCode}');
        return null;
      }

      final contentLength = response.contentLength;
      debugPrint('[$_tag] Download started, contentLength=$contentLength');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/simplevpn_update.apk');
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress(received / contentLength);
        }
      }
      await sink.close();

      debugPrint('[$_tag] Download complete: ${file.path} ($received bytes)');

      // Verify the downloaded binary against the hash from the signed manifest.
      // This is the second half of the trust chain: the manifest signature
      // authenticates apk_sha256, and this check binds the actual bytes to it.
      final bytes = await file.readAsBytes();
      if (!UpdateVerifier.verifyApk(bytes, info.apkSha256)) {
        debugPrint('[$_tag] REJECTED APK: sha256 mismatch (expected ${info.apkSha256})');
        try {
          await file.delete();
        } catch (_) {}
        return null;
      }
      debugPrint('[$_tag] APK integrity verified (sha256=${info.apkSha256})');
      return file.path;
    } catch (e) {
      debugPrint('[$_tag] Download error: $e');
      return null;
    } finally {
      ioClient.close();
    }
  }

  Future<bool> installApk(String apkPath) async {
    debugPrint('[$_tag] Triggering APK install: $apkPath');
    try {
      const channel = MethodChannel('com.simplevpn/vpn');
      final result = await channel.invokeMethod('installApk', {'path': apkPath});
      debugPrint('[$_tag] installApk result: $result');
      return result == true;
    } catch (e) {
      debugPrint('[$_tag] installApk error: $e');
      return false;
    }
  }

  /// Records the update we're about to install so that, after the new version
  /// relaunches, the app can show a "What's new" dialog with its changelog.
  Future<void> markPendingInstall(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingUpdateCodeKey, info.versionCode);
    await prefs.setString(_pendingUpdateVersionKey, info.version);
    await prefs.setString(_pendingUpdateChangelogKey, info.changelog);
    debugPrint('[$_tag] Recorded pending install: ${info.version} (code=${info.versionCode})');
  }

  /// If a previously-installed update has now taken effect (the running build
  /// number caught up to the pending one), returns its version + changelog once
  /// and clears the record. Returns null otherwise. Empty changelogs are
  /// skipped (nothing useful to show).
  Future<UpdateInfo?> consumeAppliedUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingCode = prefs.getInt(_pendingUpdateCodeKey) ?? 0;
    if (pendingCode == 0) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;
    if (currentCode < pendingCode) {
      // Update hasn't been applied yet (install pending / cancelled).
      return null;
    }

    final version = prefs.getString(_pendingUpdateVersionKey) ?? packageInfo.version;
    final changelog = prefs.getString(_pendingUpdateChangelogKey) ?? '';

    await prefs.remove(_pendingUpdateCodeKey);
    await prefs.remove(_pendingUpdateVersionKey);
    await prefs.remove(_pendingUpdateChangelogKey);

    if (changelog.trim().isEmpty) return null;
    debugPrint('[$_tag] Applied update detected: $version (code=$pendingCode)');
    return UpdateInfo(
      version: version,
      versionCode: pendingCode,
      downloadUrl: '',
      changelog: changelog,
    );
  }

  Future<void> dismissVersion(int versionCode) async {
    debugPrint('[$_tag] Dismissing version code=$versionCode');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedVersionKey, versionCode);
  }

  Future<bool> isVersionDismissed(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getInt(_dismissedVersionKey) ?? 0;
    return dismissed >= versionCode;
  }

  void clearHostCache() {
    _serverHost = null;
  }
}
