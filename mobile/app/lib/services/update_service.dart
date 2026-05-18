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

const _dismissedVersionKey = 'dismissed_update_version_code';

class UpdateService {
  static const _tag = 'UpdateService';

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _serverHost;

  Future<String?> _getServerHost() async {
    if (_serverHost != null) return _serverHost;
    final cfgStr = await _secureStorage.read(key: 'vpn_config');
    if (cfgStr == null || cfgStr.isEmpty) {
      debugPrint('[$_tag] No VPN config found in secure storage');
      return null;
    }
    try {
      final map = jsonDecode(cfgStr) as Map<String, dynamic>;
      final server = map['server'] as String? ?? '';
      final host = server.split(':').first;
      if (host.isEmpty) {
        debugPrint('[$_tag] Empty host in VPN config server=$server');
        return null;
      }
      _serverHost = host;
      debugPrint('[$_tag] Resolved server host=$host from config');
      return host;
    } catch (e) {
      debugPrint('[$_tag] Failed to parse VPN config: $e');
      return null;
    }
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

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(json);
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
