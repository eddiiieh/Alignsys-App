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
      SnackBar(
        content: const Text(
          'No object types available. Please wait for data to load.',
        ),
        backgroundColor: context.colors.warningText,
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
    builder: (sheetContext) {
      final c = sheetContext.colors;
      return Container(
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                color: c.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.brandTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_link_rounded,
                    color: c.brand,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create & Link',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        'Linking to "${target.title}"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: c.textSecondary),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: c.divider),
                itemBuilder: (itemContext, index) {
                  final entry = entries[index];

                  if (entry.isScan) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.brandTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.document_scanner_rounded,
                          size: 20,
                          color: c.brand,
                        ),
                      ),
                      title: Text(
                        'Scan Document',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Take a photo, upload as PDF, and link it',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: c.textTertiary,
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

                  if (entry.isTemplate) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.brandTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.dashboard_customize_rounded,
                          size: 20,
                          color: c.brand,
                        ),
                      ),
                      title: Text(
                        'Templates',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Start from a vault template — no upload needed',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: c.textTertiary,
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

                  final ot = entry.objectType!;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.brandTint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        ot.isDocument
                            ? Icons.description_rounded
                            : svc.iconForObjectTypeId(ot.id),
                        size: 20,
                        color: c.brand,
                      ),
                    ),
                    title: Text(
                      ot.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: c.textTertiary,
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final result =
                          await Navigator.push<LinkedCreationResult>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DynamicFormScreen(
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
      );
    },
  );
}

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
        allClasses.where((cls) => templatesByClass.containsKey(cls.id)).toList();

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
      iconColor: context.colors.dangerText,
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
    (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
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
    builder: (sheetContext) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final c = ctx.colors;
        return Container(
          decoration: BoxDecoration(
            color: c.surfaceElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.brandTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.dashboard_customize_rounded,
                      color: c.brand,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select Template',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.search_rounded,
                      color: showSearch ? c.brand : c.textSecondary,
                    ),
                    onPressed: () {
                      setSheet(() {
                        showSearch = !showSearch;
                        if (!showSearch) {
                          searchController.clear();
                          filtered = List.from(allClasses);
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            searchFocusNode.requestFocus();
                          });
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: c.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: showSearch
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          style: TextStyle(color: c.textPrimary),
                          cursorColor: c.brand,
                          decoration: InputDecoration(
                            hintText: 'Search templates...',
                            hintStyle: TextStyle(
                              color: c.textTertiary,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: c.textTertiary,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: c.surfaceSunken,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: c.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: c.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: c.brand, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                          onChanged: (q) {
                            setSheet(() {
                              filtered = q.trim().isEmpty
                                  ? List.from(allClasses)
                                  : allClasses
                                      .where((cls) => cls.displayName
                                          .toLowerCase()
                                          .contains(q.toLowerCase()))
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
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 36,
                              color: c.textTertiary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No matches found',
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: c.divider),
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
                                color: c.brandTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.dashboard_customize_rounded,
                                size: 20,
                                color: c.brand,
                              ),
                            ),
                            title: Text(
                              cls.displayName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: c.textTertiary,
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
        );
      },
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
    builder: (sheetContext) {
      final c = sheetContext.colors;
      return Container(
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                color: c.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.brandTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.description_rounded,
                    color: c.brand,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose Template',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        cls.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: c.textSecondary),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: templates.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: c.divider),
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
                        color: c.brandTint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.description_rounded,
                        size: 20,
                        color: c.brand,
                      ),
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: c.textTertiary,
                    ),
                    onTap: () => Navigator.pop(sheetContext, t),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
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
      builder: (_) => TemplateFormScreen(
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

Future<void> _refreshAfterLink(
  MFilesService svc,
  ViewObject target,
  LinkedCreationResult result,
) async {
  final refreshes = <Future<void>>[
    svc.refreshRelationshipsAfterLink(
      objectId: target.id,
      objectTypeId: target.objectTypeId,
      versionId: target.versionId,
    ),
  ];
  if (result.objectId != null) {
    refreshes.add(
      svc.refreshRelationshipsAfterLink(
        objectId: result.objectId!,
        objectTypeId: result.objectTypeId,
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
        SnackBar(
          content: Text('Scan failed: $e'),
          backgroundColor: context.colors.dangerText,
        ),
      );
    }
    return;
  }

  onScanStatusChange(null);
  if (pdfFile == null || !context.mounted) return;

  final result = await Navigator.of(context).push<LinkedCreationResult>(
    MaterialPageRoute(
      builder: (_) => DynamicFormScreen(
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