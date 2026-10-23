/// Parses a JSON value that may be an int, a double, or a numeric string
/// into an int. Some server versions emitted `latestBuildNumber` as a
/// quoted string — accepting both keeps older deployments working.
int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Describes an available update returned by the AirBuild check-update endpoint.
class UpdateInfo {
  /// Creates an [UpdateInfo] from the JSON returned by
  /// `GET /api/sdk/check-update`.
  ///
  /// The server only sends the update fields when `hasUpdate` is `true`.
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      hasUpdate: json['hasUpdate'] as bool? ?? false,
      latestVersion: json['latestVersion'] as String?,
      latestBuildNumber: _asInt(json['latestBuildNumber']),
      buildId: json['buildId'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      installUrl: json['installUrl'] as String?,
      fileSizeBytes: _asInt(json['fileSizeBytes']),
      iconUrl: json['iconUrl'] as String?,
      minOsVersion: json['minOsVersion'] as String?,
      isPasswordProtected: json['isPasswordProtected'] as bool? ?? false,
      createdAt: json['createdAt'] as String?,
    );
  }

  const UpdateInfo({
    required this.hasUpdate,
    this.latestVersion,
    this.latestBuildNumber,
    this.buildId,
    this.releaseNotes,
    this.downloadUrl,
    this.installUrl,
    this.fileSizeBytes,
    this.iconUrl,
    this.minOsVersion,
    this.isPasswordProtected = false,
    this.createdAt,
  });

  /// Whether a newer build is available for this app/platform.
  final bool hasUpdate;

  /// Version string of the latest build (e.g. `1.2.0`).
  final String? latestVersion;

  /// Build number of the latest build, if provided.
  final int? latestBuildNumber;

  /// Server-side id of the latest build. Used when reporting events.
  final String? buildId;

  /// Release notes for the latest build, if any.
  final String? releaseNotes;

  /// URL the SDK uses to download the APK (Android). Redirects to a signed S3
  /// URL. Only present for Android builds.
  final String? downloadUrl;

  /// URL testers can open in a browser to install the build (iOS). For iOS the
  /// SDK cannot sideload, so it opens this URL in Safari.
  final String? installUrl;

  /// Size of the downloadable artifact in bytes, if known.
  final int? fileSizeBytes;

  /// URL of the app icon to display in the update prompt, if available.
  final String? iconUrl;

  /// Minimum OS version required to install this build, if specified.
  final String? minOsVersion;

  /// Whether the build is protected by a password (the web install flow will
  /// prompt for it). The SDK does not handle passwords itself.
  final bool isPasswordProtected;

  /// ISO timestamp of when the build was created.
  final String? createdAt;

  /// Returns a human-readable file size string (e.g. "24.3 MB").
  String get fileSizeDisplay {
    final bytes = fileSizeBytes;
    if (bytes == null || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
