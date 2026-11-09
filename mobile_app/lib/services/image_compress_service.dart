import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class ImageCompressService {
  ImageCompressService._();

  /// Natively compresses an [XFile] frame down to a lightweight JPEG in milliseconds.
  static Future<XFile> compressFrame(
    XFile originalFile, {
    int quality = 70,
    int minWidth = 720,
    int minHeight = 1280,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          '${tempDir.path}/compressed_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final XFile? compressedFile =
          await FlutterImageCompress.compressAndGetFile(
        originalFile.path,
        targetPath,
        quality: quality,
        minWidth: minWidth,
        minHeight: minHeight,
        format: CompressFormat.jpeg,
      );

      if (compressedFile != null) {
        return compressedFile;
      }
    } catch (e) {
      debugPrint('[COMPRESS WARNING] Native compression failed: $e');
    }

    // Fallback to original file if compression fails or returns null
    return originalFile;
  }

  /// Batch compresses multiple flash frames concurrently.
  static Future<List<XFile>> compressBatch(
    List<XFile> originalFiles, {
    int quality = 65,
  }) async {
    return Future.wait(
      originalFiles.map(
        (file) => compressFrame(file, quality: quality, minWidth: 480, minHeight: 640),
      ),
    );
  }
}