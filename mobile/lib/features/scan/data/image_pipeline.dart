import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Where a receipt image came from (task 1.3.1).
enum ImageSourceKind { camera, gallery }

/// Picks, crops, and compresses a receipt image before upload (tasks 1.3.1–1.3.2).
///
/// Compression is not just about bandwidth: OCR cost scales with what we send, and
/// `MyBill.md` §15 caps the client at ~2MB / quality 85. The backend's 10MB limit is an
/// abuse guard, not a target — a raw 12MP phone photo would sail past both.
class ImagePipeline {
  ImagePipeline({ImagePicker? picker, ImageCropper? cropper})
    : _picker = picker ?? ImagePicker(),
      _cropper = cropper ?? ImageCropper();

  final ImagePicker _picker;
  final ImageCropper _cropper;

  /// Target ceiling for the uploaded file (MyBill.md §15).
  static const int maxUploadBytes = 2 * 1024 * 1024;

  /// Starting JPEG quality. Dropped stepwise if the result still exceeds the ceiling.
  static const int initialQuality = 85;

  /// Longest edge kept for the upload. Receipts are text on paper — resolution past this
  /// buys the OCR nothing and costs upload time on a phone connection.
  static const int maxDimension = 2000;

  /// Full capture flow: pick → crop/rotate → compress.
  ///
  /// Returns null when the user backs out of either the picker or the cropper — a
  /// cancellation, not an error, so callers show nothing.
  Future<File?> capture(ImageSourceKind source) async {
    final picked = await _pick(source);
    if (picked == null) return null;

    final cropped = await _crop(picked.path);
    if (cropped == null) return null;

    return compress(File(cropped.path));
  }

  Future<XFile?> _pick(ImageSourceKind source) => _picker.pickImage(
    source: source == ImageSourceKind.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    // Let the cropper and compressor do the resizing; downscaling here first would
    // throw away detail the crop step might have kept.
    imageQuality: 100,
  );

  /// Crop/rotate step (task 1.3.2). Free-form: receipts are tall and thin, and locking
  /// an aspect ratio would force the user to include background or clip the total.
  Future<CroppedFile?> _crop(String path) => _cropper.cropImage(
    sourcePath: path,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 100,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Crop receipt',
        lockAspectRatio: false,
        hideBottomControls: false,
      ),
      IOSUiSettings(title: 'Crop receipt', aspectRatioLockEnabled: false),
    ],
  );

  /// Compresses to JPEG under [maxUploadBytes], stepping quality down until it fits.
  ///
  /// A single pass at a fixed quality can't guarantee the ceiling — a dense, detailed
  /// photo may still exceed it at 85 — so this retries at progressively lower quality
  /// and gives up gracefully rather than looping forever.
  Future<File> compress(File source) async {
    final directory = await getTemporaryDirectory();
    var quality = initialQuality;

    File? best;
    for (var attempt = 0; attempt < 4; attempt++) {
      final target =
          '${directory.path}/receipt_${DateTime.now().microsecondsSinceEpoch}_$attempt.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        target,
        quality: quality,
        minWidth: maxDimension,
        minHeight: maxDimension,
        format: CompressFormat.jpeg,
        // Phone cameras record orientation in EXIF; strip it into the pixels so the
        // backend and OCR never have to interpret the tag.
        keepExif: false,
        autoCorrectionAngle: true,
      );

      if (result == null) break;
      best = File(result.path);
      if (await best.length() <= maxUploadBytes) return best;
      quality -= 15;
    }

    // Still over the ceiling (or compression failed outright): hand back the best effort
    // rather than blocking the upload. The backend's 10MB cap is the real backstop, and
    // a slightly-too-large receipt is better than a dead end.
    return best ?? source;
  }
}

final imagePipelineProvider = Provider<ImagePipeline>((ref) => ImagePipeline());
