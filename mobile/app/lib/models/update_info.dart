class UpdateInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String changelog;

  /// Hex-encoded SHA-256 of the APK referenced by [downloadUrl].
  /// Injected and signed by the server; the client verifies the downloaded
  /// binary against it before installing. Empty if the server has no APK.
  final String apkSha256;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.changelog,
    this.apkSha256 = '',
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String? ?? '',
        versionCode: json['versionCode'] as int? ?? 0,
        downloadUrl: json['downloadUrl'] as String? ?? '',
        changelog: json['changelog'] as String? ?? '',
        apkSha256: json['apk_sha256'] as String? ?? '',
      );
}
