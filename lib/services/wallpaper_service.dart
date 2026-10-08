import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// A chat background the user chose themselves.
///
/// The image is stored only on the device that picked it: it is never
/// uploaded, so it costs nothing in the cloud and nobody else can see it.
class WallpaperService {
  WallpaperService._();

  /// The stored image's path, or null when the user has no background yet.
  static Future<String?> loadPath() async {
    final file = await _file();
    return await file.exists() ? file.path : null;
  }

  static Future<String> saveBytes(Uint8List bytes) async {
    final file = await _file();
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<void> remove() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/wallpaper.image');
  }
}