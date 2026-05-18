import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

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

  String? _serverHost;

  Future<String?> _getServerHost() async {
    if (_serverHost != null) return _serverHost;
    final prefs = await SharedPreferences.getInstance();
    final cfgStr = prefs.getString('vpn_config');
    if (cfgStr == null || cfgStr.isEmpty) {
      dev.log('[$_tag] No VPN config found in SharedPreferences', level: 800);
      return null;
    }
    try {
      final map = jsonDecode(cfgStr) as Map<String, dynamic>;
      final server = map['server'] as String? ?? '';
      final host = server.split(':').first;
      if (host.isEmpty) {
        dev.log('[$_tag] Empty host in VPN config server=$server', level: 900);
        return null;
      }
      _serverHost = host;
      dev.log('[$_tag] Resolved server host=$host from config', level: 500);
      return host;
    } catch (e) {
      dev.log('[$_tag] Failed to parse VPN config: $e', level: 900);
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
    dev.log('[$_tag] Checking for update at $url', level: 500);

    final client = _buildClient();
    try {
      final resp = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      dev.log('[$_tag] Update check response: status=${resp.statusCode}', level: 500);

      if (resp.statusCode != 200) {
        dev.log('[$_tag] Update check failed: ${resp.statusCode} ${resp.body}', level: 800);
        return null;
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(json);
      dev.log('[$_tag] Remote version: ${info.version} (code=${info.versionCode})', level: 500);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      dev.log('[$_tag] Current version: ${packageInfo.version} (code=$currentCode)', level: 500);

      if (info.versionCode <= currentCode) {
        dev.log('[$_tag] No update needed (remote=${info.versionCode} <= current=$currentCode)', level: 500);
        return null;
      }

      if (await isVersionDismissed(info.versionCode)) {
        dev.log('[$_tag] Version ${info.versionCode} was dismissed by user', level: 500);
        return null;
      }

      dev.log('[$_tag] Update available: ${info.version} (code=${info.versionCode})', level: 500);
      return info;
    } catch (e) {
      dev.log('[$_tag] Update check error: $e', level: 900);
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
    dev.log('[$_tag] Downloading APK from $downloadUrl', level: 500);

    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final request = await ioClient.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        dev.log('[$_tag] Download failed: status=${response.statusCode}', level: 900);
        return null;
      }

      final contentLength = response.contentLength;
      dev.log('[$_tag] Download started, contentLength=$contentLength', level: 500);

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

      dev.log('[$_tag] Download complete: ${file.path} ($received bytes)', level: 500);
      return file.path;
    } catch (e) {
      dev.log('[$_tag] Download error: $e', level: 900);
      return null;
    } finally {
      ioClient.close();
    }
  }

  Future<bool> installApk(String apkPath) async {
    dev.log('[$_tag] Triggering APK install: $apkPath', level: 500);
    try {
      const channel = MethodChannel('com.simplevpn/vpn');
      final result = await channel.invokeMethod('installApk', {'path': apkPath});
      dev.log('[$_tag] installApk result: $result', level: 500);
      return result == true;
    } catch (e) {
      dev.log('[$_tag] installApk error: $e', level: 900);
      return false;
    }
  }

  Future<void> dismissVersion(int versionCode) async {
    dev.log('[$_tag] Dismissing version code=$versionCode', level: 500);
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
