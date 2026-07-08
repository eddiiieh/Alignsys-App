import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

class ScanDocumentFlow {
  ScanDocumentFlow._();

  /// Full pipeline: camera → crop → PDF.
  /// Returns null if the user cancels at any step.
  static Future<File?> captureAndConvert(BuildContext context) async {
    // ── Step 1: Camera ────────────────────────────────────────────────────
    final picker = ImagePicker();
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (shot == null) return null;

    // ── Step 2: Crop ──────────────────────────────────────────────────────
    final cropped = await ImageCropper().cropImage(
      sourcePath: shot.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Document',
          toolbarColor: const Color(0xFF2563EB),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF2563EB),
          lockAspectRatio: false,
          hideBottomControls: false,
          initAspectRatio: CropAspectRatioPreset.original,
        ),
        IOSUiSettings(
          title: 'Crop Document',
          doneButtonTitle: 'Use Photo',
          cancelButtonTitle: 'Retake',
          resetAspectRatioEnabled: true,
          aspectRatioLockEnabled: false,
        ),
      ],
    );
    if (cropped == null) return null;

    // ── Step 3: Image → single-page PDF ───────────────────────────────────
    // Multi-page fast-follow: replace File with List<File> here, loop
    // doc.addPage() for each, and update the caller signature accordingly.
    return _imageToPdf(File(cropped.path));
  }

  static Future<File> _imageToPdf(File imageFile) async {
    final imageBytes = await imageFile.readAsBytes();
    final pwImage = pw.MemoryImage(imageBytes);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Center(
          child: pw.Image(pwImage, fit: pw.BoxFit.contain),
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final pdfFile = File(
      '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await pdfFile.writeAsBytes(await doc.save());

    debugPrint(
      '📄 ScanDocumentFlow: PDF created at ${pdfFile.path} '
      '(${await pdfFile.length()} bytes)',
    );
    return pdfFile;
  }
}