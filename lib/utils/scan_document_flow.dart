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
    try {
      debugPrint("STEP 1 - Opening camera");

      // ── Step 1: Camera ────────────────────────────────────────────────────
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (shot == null) {
        debugPrint("Camera cancelled");
        return null;
      }

      debugPrint("STEP 2 - Camera complete: ${shot.path}");

      // ── Step 2: Crop ──────────────────────────────────────────────────────
      debugPrint("STEP 3 - Opening cropper");

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

      if (cropped == null) {
        debugPrint("Crop cancelled");
        return null;
      }

      debugPrint("STEP 4 - Crop complete: ${cropped.path}");

      // ── Step 3: Image → single-page PDF ───────────────────────────────────
      debugPrint("STEP 5 - Creating PDF");

      final pdf = await _imageToPdf(File(cropped.path));

      debugPrint("STEP 6 - PDF created: ${pdf.path}");

      return pdf;
    } catch (e, stackTrace) {
      debugPrint("❌ ScanDocumentFlow.captureAndConvert failed");
      debugPrint("$e");
      debugPrintStack(stackTrace: stackTrace);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Document scan failed:\n$e"),
            backgroundColor: Colors.red,
          ),
        );
      }

      return null;
    }
  }

  static Future<File> _imageToPdf(File imageFile) async {
    final imageBytes = await imageFile.readAsBytes();
    final pwImage = pw.MemoryImage(imageBytes);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build:
            (context) =>
                pw.Center(child: pw.Image(pwImage, fit: pw.BoxFit.contain)),
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
