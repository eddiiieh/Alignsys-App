import 'package:flutter/material.dart';

/// Returns an icon representative of a given M-Files object type name.
/// Mirrors the mapping used for the "Create" sheet in home_screen.dart.
IconData iconForObjectTypeName(String name) {
  final n = name.toLowerCase().trim();
  if (n == 'cars' || n.contains('vehicle')) return Icons.directions_car_rounded;
  if (n == 'container files') return Icons.folder_zip_rounded;
  if (n == 'document collections') return Icons.library_books_rounded;
  if (n == 'news') return Icons.newspaper_rounded;
  if (n == 'students') return Icons.school_rounded;
  if (n == 'annotations') return Icons.rate_review_rounded;
  if (n == 'archive boxes') return Icons.archive_rounded;
  if (n == 'calendar events') return Icons.event_rounded;
  if (n == 'customers') return Icons.people_alt_rounded;
  if (n == 'departments') return Icons.account_tree_rounded;
  if (n == 'filing slots') return Icons.inbox_rounded;
  if (n == 'finances') return Icons.account_balance_rounded;
  if (n == 'insurers') return Icons.health_and_safety_rounded;
  if (n == 'job vacancies') return Icons.work_history_rounded;
  if (n == 'library books') return Icons.menu_book_rounded;
  if (n == 'librarys' || n == 'libraries') return Icons.local_library_rounded;
  if (n == 'prescription sales') return Icons.medication_rounded;
  if (n == 'processes') return Icons.account_tree_rounded;
  if (n == 'requisitions') return Icons.request_page_rounded;
  if (n == 'shares') return Icons.share_rounded;
  if (n == 'test') return Icons.science_rounded;
  if (n == 'loans') return Icons.local_atm_rounded;
  if (n == 'members') return Icons.person_2_rounded;
  if (n == 'valuers') return Icons.currency_exchange_rounded;
  if (n.contains('contact') || n.contains('person') || n.contains('client')) return Icons.person_rounded;
  if (n.contains('project')) return Icons.work_rounded;
  if (n.contains('invoice')) return Icons.receipt_long_rounded;
  if (n.contains('payment') || n.contains('transaction')) return Icons.payments_rounded;
  if (n.contains('contract') || n.contains('agreement')) return Icons.handshake_rounded;
  if (n.contains('report') || n.contains('analytics')) return Icons.analytics_rounded;
  if (n.contains('meeting') || n.contains('minute')) return Icons.groups_rounded;
  if (n.contains('task') || n.contains('assignment')) return Icons.task_alt_rounded;
  if (n.contains('email') || n.contains('message') || n.contains('mail')) return Icons.email_rounded;
  if (n.contains('asset') || n.contains('equipment')) return Icons.inventory_2_rounded;
  if (n.contains('employee') || n.contains('staff') || n.contains('user')) return Icons.badge_rounded;
  if (n.contains('supplier') || n.contains('vendor')) return Icons.local_shipping_rounded;
  if (n.contains('company') || n.contains('organisation') || n.contains('organization')) return Icons.business_rounded;
  if (n.contains('case') || n.contains('ticket') || n.contains('issue')) return Icons.support_agent_rounded;
  if (n.contains('product') || n.contains('item') || n.contains('sku')) return Icons.inventory_rounded;
  if (n.contains('property') || n.contains('real estate') || n.contains('land')) return Icons.home_work_rounded;
  return Icons.category_rounded;
}