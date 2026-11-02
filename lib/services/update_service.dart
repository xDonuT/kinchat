import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.downloadUrl,
    required this.releaseUrl,
    required this.notes,
  });

  final String version;
  final String downloadUrl;
  final String releaseUrl;
  final String notes;
}

class UpdateService {
  static const String _repo = 'xDonuT/kinchat';

  static Future<AppUpdate?> check() async {
    final info = await PackageInfo.fromPlatform();
    final current = _AppVersion.parse(info.version);
    if (current == null) return null;

    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
          .timeout(const Duration(seconds: 12));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'kinchat-updater');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub returned ${response.statusCode}');
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('Bad release payload');
      final data = Map<String, dynamic>.from(decoded);

      final tag = data['tag_name'];
      if (tag is! String) throw const FormatException('Missing release tag');
      final latest = _AppVersion.parse(tag);
      if (latest == null || latest.compareTo(current) <= 0) return null;

      final releaseUrl =
          data['html_url'] as String? ??
          'https://github.com/$_repo/releases/latest';
      String? downloadUrl;
      final assets = data['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = asset['name'];
          final url = asset['browser_download_url'];
          if (name is String && name.toLowerCase().endsWith('.apk') && url is String) {
            downloadUrl = url;
            break;
          }
        }
      }

      return AppUpdate(
        version: latest.toString(),
        downloadUrl: downloadUrl ?? releaseUrl,
        releaseUrl: releaseUrl,
        notes: data['body'] as String? ?? '',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _AppVersion implements Comparable<_AppVersion> {
  const _AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static _AppVersion? parse(String raw) {
    final match = RegExp(
      r'^[vV]?(\d+)\.(\d+)\.(\d+)',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    return _AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(_AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}
