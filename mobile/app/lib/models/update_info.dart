class UpdateInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String changelog;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.changelog,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String? ?? '',
        versionCode: json['versionCode'] as int? ?? 0,
        downloadUrl: json['downloadUrl'] as String? ?? '',
        changelog: json['changelog'] as String? ?? '',
      );
}
