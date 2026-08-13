import 'package:flutter/material.dart';

class FileIconResolver {
  static const IconData nonDocumentIcon = Icons.folder_outlined;
  static const IconData unknownIcon = Icons.description_outlined;

  // Curated pool for non-document object types (Cars, Customers, Invoices,
  // and anything a future vault introduces). Deliberately disjoint from the
  // icons used in iconForExtension so no object type ever visually matches
  // a file-type badge. Deterministic by objectTypeId — same type always
  // renders the same icon.
  static const List<IconData> _objectTypePool = [
    Icons.badge_outlined,
    Icons.business_outlined,
    Icons.directions_car_outlined,
    Icons.school_outlined,
    Icons.event_outlined,
    Icons.receipt_long_outlined,
    Icons.handshake_outlined,
    Icons.groups_outlined,
    Icons.inventory_2_outlined,
    Icons.local_shipping_outlined,
    Icons.support_agent_outlined,
    Icons.home_work_outlined,
    Icons.account_balance_outlined,
    Icons.medication_outlined,
    Icons.local_atm_outlined,
    Icons.newspaper_outlined,
    Icons.library_books_outlined,
    Icons.folder_zip_outlined,
    Icons.rate_review_outlined,
    Icons.inbox_outlined,
    Icons.health_and_safety_outlined,
    Icons.work_history_outlined,
    Icons.menu_book_outlined,
    Icons.local_library_outlined,
    Icons.science_outlined,
    Icons.person_2_outlined,
    Icons.currency_exchange_outlined,
    Icons.account_tree_outlined,
    Icons.request_page_outlined,
    Icons.share_outlined,
    Icons.payments_outlined,
    Icons.task_alt_outlined,
    Icons.email_outlined,
    Icons.analytics_outlined,
    Icons.category_outlined,
    Icons.storage_outlined,
    Icons.warehouse_outlined,
    Icons.map_outlined,
    Icons.gavel_outlined,
    Icons.security_outlined,
    Icons.psychology_outlined,
  ];

  static IconData iconForObjectType(int objectTypeId) {
    final index = objectTypeId.hashCode.abs() % _objectTypePool.length;
    return _objectTypePool[index];
  }

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
