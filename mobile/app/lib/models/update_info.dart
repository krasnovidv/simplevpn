import 'vpn_config.dart';

class UpdateInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String changelog;

  /// Hex-encoded SHA-256 of the APK referenced by [downloadUrl].
  /// Injected and signed by the server; the client verifies the downloaded
  /// binary against it before installing. Empty if the server has no APK.
  final String apkSha256;

  /// Server addresses the deployment wants clients to know about, newest first.
  /// Carried on the signed manifest so a server move can be announced to
  /// already-installed apps without shipping an APK: the client merges these
  /// into its config and fails over to them once the old address goes dark.
  /// Trustworthy only because the manifest is HMAC-signed with the server key.
  final List<String> endpoints;

  /// Marks an update the user cannot safely postpone — currently used when the
  /// server is moving hosts and an un-updated app will simply stop connecting.
  /// The app shows it unmissably and refuses to let the user silence it.
  final bool critical;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.changelog,
    this.apkSha256 = '',
    this.endpoints = const [],
    this.critical = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String? ?? '',
        versionCode: json['versionCode'] as int? ?? 0,
        downloadUrl: json['downloadUrl'] as String? ?? '',
        changelog: json['changelog'] as String? ?? '',
        apkSha256: json['apk_sha256'] as String? ?? '',
        endpoints: VpnConfig.parseEndpoints(json['endpoints']),
        critical: json['critical'] as bool? ?? false,
      );
}
