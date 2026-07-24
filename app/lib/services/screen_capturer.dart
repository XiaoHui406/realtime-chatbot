import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import '../pages/gallery_picker_page.dart';

class ScreenCapturer {
  static const _maxImages = 5;

  static Future<List<String>?> pick(BuildContext context) async {
    final assets = await Navigator.of(context).push<List<AssetEntity>>(
      MaterialPageRoute(builder: (_) => const GalleryPickerPage()),
    );
    if (assets == null || assets.isEmpty) return null;

    final picked = assets.length > _maxImages
        ? assets.sublist(0, _maxImages)
        : assets;

    final images = <String>[];
    for (final asset in picked) {
      final base64 = await _compressAsset(asset);
      if (base64 != null) {
        images.add(base64);
      }
    }
    return images.isEmpty ? null : images;
  }

  static Future<String?> _compressAsset(AssetEntity asset) async {
    final file = await asset.originFile;
    if (file == null) return null;

    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return base64Encode(bytes);

      const maxSize = 1280;
      final out = decoded.width > maxSize || decoded.height > maxSize
          ? img.copyResize(
              decoded,
              width: (decoded.width *
                      math.min(
                          maxSize / decoded.width, maxSize / decoded.height))
                  .round(),
              height: (decoded.height *
                      math.min(
                          maxSize / decoded.width, maxSize / decoded.height))
                  .round(),
            )
          : decoded;

      return base64Encode(img.encodeJpg(out, quality: 75));
    } catch (_) {
      return null;
    }
  }
}
