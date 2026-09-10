import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mfiles_app/models/vault_object_type.dart';
import 'package:mfiles_app/models/view_object.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/theme/app_colors.dart';
import 'package:mfiles_app/utils/scan_document_flow.dart';

class _LinkEntry {
  final bool isScan;
  final VaultObjectType? objectType;

  const _LinkEntry.scan() : isScan = true, objectType = null;
  const _LinkEntry.objectType(VaultObjectType type) : isScan = false, objectType = type;
}

/// Shows the "Create & Link" type picker for [target], then pushes
/// DynamicFormScreen(linkTarget: target) for whatever type the user picks.
///
/// Templates are intentionally left out, Templates/ObjectCreation has no
/// linking support on the backend yet (see the note left in home_screen.dart).
///
/// [onLinked] fires once a link completes successfully, so the caller can
/// clear selection and refresh its list.
///
/// [onScanStatusChange] is called with a progress message while a scan is
/// in flight, and null when it finishes, each screen wires this to whatever
/// loading indicator it already uses rather than this widget owning its own.
Future<void> showLinkCreateSheet(
  BuildContext context, {
  required ViewObject target,
  required VoidCallback onLinked,
  required void Function(String? message) onScanStatusChange,
}) async {
  final svc = context.read<MFilesService>();

  if (svc.objectTypes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No object types available. Please wait for data to load.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  final sortedTypes = [
    ...svc.objectTypes.where((t) => t.isDocument),
    ...([...svc.objectTypes.where((t) => !t.isDocument)]..sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    )),
  ];

  final entries = <_LinkEntry>[
    const _LinkEntry.scan(),
    ...sortedTypes.map((t) => _LinkEntry.objectType(t)),
  ];

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.add_link_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Create & Link', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      'Linking to "${target.title}"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: entries.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (itemContext, index) {
                final entry = entries[index];

                if (entry.isScan) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.document_scanner_rounded, size: 20, color: AppColors.primary),
                    ),
                    title: const Text('Scan Document', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('Take a photo, upload as PDF, and link it', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _scanAndLink(context, svc, target, onLinked, onScanStatusChange);
                    },
                  );
                }

                final ot = entry.objectType!;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                    child: Icon(
                      ot.isDocument ? Icons.description_rounded : svc.iconForObjectTypeId(ot.id),
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(ot.displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final linked = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DynamicFormScreen(objectType: ot, linkTarget: target),
                      ),
                    );
                    if (linked == true) onLinked();
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _scanAndLink(
  BuildContext context,
  MFilesService svc,
  ViewObject target,
  VoidCallback onLinked,
  void Function(String? message) onScanStatusChange,
) async {
  final docType = svc.objectTypes.firstWhere(
    (t) => t.isDocument,
    orElse: () => svc.objectTypes.first,
  );

  File? pdfFile;
  try {
    pdfFile = await ScanDocumentFlow.captureAndConvert(
      context,
      onStatusChange: onScanStatusChange,
    );
  } catch (e) {
    onScanStatusChange(null);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e'), backgroundColor: Colors.red),
      );
    }
    return;
  }

  onScanStatusChange(null);
  if (pdfFile == null || !context.mounted) return;

  final linked = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => DynamicFormScreen(objectType: docType, scannedFile: pdfFile, linkTarget: target),
    ),
  );

  if (linked == true) onLinked();
}