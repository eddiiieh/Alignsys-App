// widgets/link_create_sheet.dart
// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mfiles_app/models/object_class.dart';
import 'package:mfiles_app/models/vault_object_type.dart';
import 'package:mfiles_app/models/view_object.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:mfiles_app/screens/template_form_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/theme/app_colors.dart';
import 'package:mfiles_app/utils/app_dialogs.dart';
import 'package:mfiles_app/utils/scan_document_flow.dart';
// ─────────────────────────────────────────────────────────────────────────────
// Entry rows on the sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LinkEntry {
  final bool isScan;
  final bool isTemplate;
  final VaultObjectType? objectType;

  const _LinkEntry.scan()
      : isScan = true,
        isTemplate = false,
        objectType = null;

  const _LinkEntry.template()
      : isScan = false,
        isTemplate = true,
        objectType = null;

  const _LinkEntry.objectType(VaultObjectType type)
      : isScan = false,
        isTemplate = false,
        objectType = type;
}

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
        content: Text(
          'No object types available. Please wait for data to load.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  final sortedTypes = [
    ...svc.objectTypes.where((t) => t.isDocument),
    ...([...svc.objectTypes.where((t) => !t.isDocument)]..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    )),
  ];

  final entries = <_LinkEntry>[
    const _LinkEntry.scan(),
    const _LinkEntry.template(),
    ...sortedTypes.map((t) => _LinkEntry.objectType(t)),
  ];

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => Container(
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
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_link_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Create & Link',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Linking to "${target.title}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
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
                  separatorBuilder:
                      (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (itemContext, index) {
                    final entry = entries[index];

                    // ── Scan Document ─────────────────────────────────
                    if (entry.isScan) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.document_scanner_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                        title: const Text(
                          'Scan Document',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Take a photo, upload as PDF, and link it',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _scanAndLink(
                            context,
                            svc,
                            target,
                            onLinked,
                            onScanStatusChange,
                          );
                        },
                      );
                    }

                    // ── Templates ─────────────────────────────────────
                    if (entry.isTemplate) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.dashboard_customize_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                        title: const Text(
                          'Templates',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Start from a vault template — no upload needed',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _openVaultTemplatesForLink(
                            context,
                            svc,
                            target,
                            onLinked,
                          );
                        },
                      );
                    }

                    // ── Object type ───────────────────────────────────
                    final ot = entry.objectType!;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          ot.isDocument
                              ? Icons.description_rounded
                              : svc.iconForObjectTypeId(ot.id),
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(
                        ot.displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade400,
                      ),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final result =
                            await Navigator.push<LinkedCreationResult>(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => DynamicFormScreen(
                                      objectType: ot,
                                      linkTarget: target,
                                    ),
                              ),
                            );
                        if (result != null) {
                          await _refreshAfterLink(svc, target, result);
                          onLinked();
                        }
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

// ─────────────────────────────────────────────────────────────────────────────
// Link-aware template flow (mirrors HomeScreen's Create flow, adds linkTarget)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _openVaultTemplatesForLink(
  BuildContext context,
  MFilesService svc,
  ViewObject target,
  VoidCallback onLinked,
) async {
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    if (svc.objectTypes.isEmpty) await svc.fetchObjectTypes();
    await Future.wait(
      svc.objectTypes.map((ot) => svc.fetchObjectClasses(ot.id)),
    );

    final vaultGuid = svc.selectedVault?.guid ?? '';
    final allTemplates = await svc.fetchAllTemplates(vaultGuid: vaultGuid);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (allTemplates.isEmpty) {
      await showAppInfoDialog(
        context,
        title: 'No Templates Found',
        message:
            "This repository doesn't have any templates set up yet. "
            "You can still create the document from scratch, or ask your "
            "vault admin to add one.",
        icon: Icons.dashboard_customize_rounded,
      );
      return;
    }

    final Map<int, List<Map<String, dynamic>>> templatesByClass = {};
    for (final t in allTemplates) {
      final classId =
          (t['classId'] ?? t['classID'] ?? t['ClassID'] ?? t['ClassId'])
              as int?;
      if (classId == null) continue;
      templatesByClass.putIfAbsent(classId, () => []).add(t);
    }

    final allClasses = _collectAllClasses(svc);
    final classesWithTemplates =
        allClasses
            .where((cls) => templatesByClass.containsKey(cls.id))
            .toList();

    if (classesWithTemplates.isEmpty) {
      await showAppInfoDialog(
        context,
        title: 'No Templates Found',
        message:
            "This repository doesn't have any templates set up yet. "
            "You can still create the document from scratch, or ask your "
            "vault admin to add one.",
        icon: Icons.dashboard_customize_rounded,
      );
      return;
    }

    await _openTemplateClassSheet(
      context,
      classesWithTemplates,
      templatesByClass: templatesByClass,
      target: target,
      onLinked: onLinked,
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await showAppInfoDialog(
      context,
      title: "Couldn't Load Templates",
      message:
          'Something went wrong fetching templates for this repository. '
          'Please try again.',
      icon: Icons.error_outline_rounded,
      iconColor: Colors.red.shade600,
    );
  }
}

List<ObjectClass> _collectAllClasses(MFilesService service) {
  final seen = <int>{};
  final result = <ObjectClass>[];
  for (final ot in service.objectTypes) {
    for (final group in service.getClassGroupsForType(ot.id)) {
      for (final cls in group.members) {
        if (seen.add(cls.id)) result.add(cls);
      }
    }
  }
  if (result.isEmpty) {
    for (final cls in service.objectClasses) {
      if (seen.add(cls.id)) result.add(cls);
    }
  }
  result.sort(
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
  return result;
}

Future<void> _openTemplateClassSheet(
  BuildContext context,
  List<ObjectClass> allClasses, {
  required Map<int, List<Map<String, dynamic>>> templatesByClass,
  required ViewObject target,
  required VoidCallback onLinked,
}) async {
  if (!context.mounted) return;

  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();
  List<ObjectClass> filtered = List.from(allClasses);
  bool showSearch = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => StatefulBuilder(
          builder:
              (ctx, setSheet) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 14,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.dashboard_customize_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Select Template',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.search_rounded,
                            color:
                                showSearch
                                    ? AppColors.primary
                                    : Colors.grey.shade700,
                          ),
                          onPressed: () {
                            setSheet(() {
                              showSearch = !showSearch;
                              if (!showSearch) {
                                searchController.clear();
                                filtered = List.from(allClasses);
                              } else {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  searchFocusNode.requestFocus();
                                });
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child:
                          showSearch
                              ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TextField(
                                  controller: searchController,
                                  focusNode: searchFocusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Search templates...',
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 14,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search,
                                      color: Colors.grey.shade400,
                                      size: 20,
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surfaceLight,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    isDense: true,
                                  ),
                                  onChanged: (q) {
                                    setSheet(() {
                                      filtered =
                                          q.trim().isEmpty
                                              ? List.from(allClasses)
                                              : allClasses
                                                  .where(
                                                    (c) => c.displayName
                                                        .toLowerCase()
                                                        .contains(
                                                          q.toLowerCase(),
                                                        ),
                                                  )
                                                  .toList();
                                    });
                                  },
                                ),
                              )
                              : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${filtered.length} template${filtered.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child:
                          filtered.isEmpty
                              ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 36,
                                      color: Colors.grey.shade300,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No matches found',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                separatorBuilder:
                                    (_, __) => Divider(
                                      height: 1,
                                      color: Colors.grey.shade100,
                                    ),
                                itemBuilder: (_, index) {
                                  final cls = filtered[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(
                                          0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.dashboard_customize_rounded,
                                        size: 20,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    title: Text(
                                      cls.displayName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    trailing: Icon(
                                      Icons.chevron_right_rounded,
                                      color: Colors.grey.shade400,
                                    ),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      final templates =
                                          templatesByClass[cls.id] ?? [];
                                      _openTemplateDocumentSheetForLink(
                                        context,
                                        cls,
                                        templates,
                                        target: target,
                                        onLinked: onLinked,
                                      );
                                    },
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
        ),
  );
}

Future<void> _openTemplateDocumentSheetForLink(
  BuildContext context,
  ObjectClass cls,
  List<Map<String, dynamic>> templates, {
  required ViewObject target,
  required VoidCallback onLinked,
}) async {
  if (!context.mounted) return;

  if (templates.isEmpty) {
    await showAppInfoDialog(
      context,
      title: 'No Templates for This Class',
      message:
          "${cls.displayName} doesn't have any templates yet. "
          'Try a different class or create the document from scratch.',
      icon: Icons.dashboard_customize_rounded,
    );
    return;
  }

  final objectTypeId = cls.objectTypeId;

  if (templates.length == 1) {
    final t = templates.first;
    await _pushTemplateForm(
      context,
      cls: cls,
      template: t,
      objectTypeId: objectTypeId,
      target: target,
      onLinked: onLinked,
    );
    return;
  }

  final picked = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => Container(
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
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Choose Template',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          cls.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
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
                  itemCount: templates.length,
                  separatorBuilder:
                      (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (_, index) {
                    final t = templates[index];
                    final title = t['title'] as String? ?? 'Untitled';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.description_rounded,
                          size: 20,
                          color: Color.fromRGBO(25, 76, 129, 1),
                        ),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade400,
                      ),
                      onTap: () => Navigator.pop(sheetContext, t),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
  );

  if (picked == null || !context.mounted) return;

  await _pushTemplateForm(
    context,
    cls: cls,
    template: picked,
    objectTypeId: objectTypeId,
    target: target,
    onLinked: onLinked,
  );
}

Future<void> _pushTemplateForm(
  BuildContext context, {
  required ObjectClass cls,
  required Map<String, dynamic> template,
  required int objectTypeId,
  required ViewObject target,
  required VoidCallback onLinked,
}) async {
  final result = await Navigator.push<LinkedCreationResult>(
    context,
    MaterialPageRoute(
      builder:
          (_) => TemplateFormScreen(
            classId: cls.id,
            className: cls.displayName,
            templateObjectId: template['id'] as int,
            templateTitle: template['title'] as String? ?? 'Template',
            objectTypeId: objectTypeId, 
            linkTarget: target,
          ),
    ),
  );

  if (result != null) {
    final svc = context.read<MFilesService>();
    await _refreshAfterLink(svc, target, result);
    onLinked();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _refreshAfterLink(
  MFilesService svc,
  ViewObject target,
  LinkedCreationResult result,
) async {
  final refreshes = <Future<void>>[
    svc.refreshRelationshipsAfterLink(
      objectId: target.id,
      objectTypeId: target.objectTypeId,
      classId: target.classId,
      versionId: target.versionId,
    ),
  ];
  if (result.objectId != null) {
    refreshes.add(
      svc.refreshRelationshipsAfterLink(
        objectId: result.objectId!,
        objectTypeId: result.objectTypeId,
        classId: result.classId,
        versionId: 1,
      ),
    );
  }
  await Future.wait(refreshes);
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

  final result = await Navigator.of(context).push<LinkedCreationResult>(
    MaterialPageRoute(
      builder:
          (_) => DynamicFormScreen(
            objectType: docType,
            scannedFile: pdfFile,
            linkTarget: target,
          ),
    ),
  );

  if (result != null) {
    await _refreshAfterLink(svc, target, result);
    onLinked();
  }
}