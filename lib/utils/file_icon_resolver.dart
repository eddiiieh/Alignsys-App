import 'package:flutter/material.dart';

class FileIconResolver {
  static const IconData nonDocumentIcon = Icons.folder_outlined;
  static const IconData unknownIcon = Icons.description_outlined;

  static String normalizeExt(String? extOrName) {
    if (extOrName == null) return '';
    var s = extOrName.trim().toLowerCase();
    if (s.isEmpty) return '';

    final dot = s.lastIndexOf('.');
    if (dot != -1 && dot < s.length - 1) s = s.substring(dot + 1);
    if (s.startsWith('.')) s = s.substring(1);
    return s;
  }

  static IconData iconForExtension(String? extOrName) {
    final ext = normalizeExt(extOrName);

    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_outlined;

      case 'doc':
      case 'docx':
      case 'rtf':
      case 'odt': return Icons.article_outlined;

      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'ods': return Icons.grid_on_outlined;

      case 'ppt':
      case 'pptx':
      case 'odp': return Icons.slideshow_outlined;

      case 'txt':
      case 'md':
      case 'log': return Icons.notes_outlined;

      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg': return Icons.image_outlined;

      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz': return Icons.archive_outlined;

      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
      case 'flac': return Icons.audiotrack_outlined;

      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'avi':
      case 'webm': return Icons.movie_outlined;

      default: return Icons.description_outlined;
    }
  }
}
