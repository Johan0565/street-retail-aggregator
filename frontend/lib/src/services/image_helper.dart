import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';

class ImageHelper {
  static final ImagePicker _picker = ImagePicker();

  /// Полная ссылка на ресурс. Принимает либо абсолютный URL, либо относительный
  /// путь вида /uploads/... — в таком случае префиксует базовым URL API.
  static String? toAbsoluteUrl(String? relativeOrAbsolute) {
    if (relativeOrAbsolute == null || relativeOrAbsolute.isEmpty) return null;
    if (relativeOrAbsolute.startsWith('http')) return relativeOrAbsolute;
    return '${ApiConfig.baseUrl}$relativeOrAbsolute';
  }

  /// Показывает BottomSheet с выбором источника и возвращает выбранные файлы.
  /// allowMultiple=true разрешён только для галереи.
  static Future<List<File>> pickImages(
    BuildContext context, {
    bool allowMultiple = false,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Из галереи'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return [];

    final List<XFile> picked = [];
    if (source == ImageSource.gallery && allowMultiple) {
      picked.addAll(await _picker.pickMultiImage());
    } else {
      final one = await _picker.pickImage(source: source);
      if (one != null) picked.add(one);
    }
    if (picked.isEmpty) return [];

    final result = <File>[];
    for (final x in picked) {
      final compressed = await _compress(File(x.path));
      if (compressed != null) result.add(compressed);
    }
    return result;
  }

  /// Сжимает картинку до ~1600px по длинной стороне и JPEG q=80.
  static Future<File?> _compress(File source) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final target =
          '${tmpDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        target,
        quality: 80,
        minWidth: 1600,
        minHeight: 1600,
        format: CompressFormat.jpeg,
      );
      if (result == null) return source;
      return File(result.path);
    } catch (_) {
      return source;
    }
  }
}
