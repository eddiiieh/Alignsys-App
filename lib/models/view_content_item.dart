import 'user_permissions.dart';

class ViewContentItem {
  final String type;
  final int id;
  final String title;
  final int objectTypeId;
  final int classId;
  final int versionId;
  final String? objectTypeName;
  final String? classTypeName;
  final String? displayId;
  final DateTime? createdUtc;
  final DateTime? lastModifiedUtc;
  final int viewId;
  final String? propId;
  final String? propDatatype;
  final bool isSingleFile;
  final bool isCheckedOut;
  final int? checkoutUserId;
  final String? checkoutUsername;
  final UserPermission? userPermission; // NEW
  final List<UserPermissionEntry> permissionEntries; // NEW

  ViewContentItem({
    required this.type,
    required this.id,
    required this.title,
    required this.objectTypeId,
    required this.classId,
    required this.versionId,
    required this.objectTypeName,
    required this.classTypeName,
    required this.displayId,
    required this.createdUtc,
    required this.lastModifiedUtc,
    required this.viewId,
    required this.propId,
    required this.propDatatype,
    required this.isSingleFile,
    required this.isCheckedOut,
    required this.checkoutUserId,
    required this.checkoutUsername,
    this.userPermission, // NEW
    this.permissionEntries = const [], // NEW
  });

  bool get isObject => type == 'MFFolderContentItemTypeObjectVersion' && id > 0;
  bool get isGroupFolder => type == 'MFFolderContentItemTypePropertyFolder';
  bool get isViewFolder => type == 'MFFolderContentItemTypeViewFolder' && id > 0;
  bool get isMultiFile => objectTypeId == 0 && !isSingleFile;

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory ViewContentItem.fromJson(Map<String, dynamic> m, {int? forUserId}) {
    final rawPropId = m['propId'] ?? m['propID'] ?? m['propertyId'] ?? m['propertyID'];

    // ── NEW PERMISSIONS PARSING ──
    final rawPerm = m['userPermission'];
    UserPermission? resolvedPermission;
    List<UserPermissionEntry> entries = const [];

    if (rawPerm is Map<String, dynamic>) {
      resolvedPermission = UserPermission.fromJson(rawPerm);
    } else if (rawPerm is List) {
      entries = rawPerm
          .whereType<Map<String, dynamic>>()
          .map(UserPermissionEntry.fromJson)
          .toList();
      
      if (forUserId != null) {
        for (final e in entries) {
          if (e.userId == forUserId) {
            resolvedPermission = e.permission;
            break;
          }
        }
      }
    }

    return ViewContentItem(
      type: (m['type'] as String?) ?? '',
      id: (m['id'] as num?)?.toInt() ?? -1,
      title: (m['title'] as String?) ?? '',
      objectTypeId: (m['objectTypeId'] as num?)?.toInt() ?? -1,
      classId: (m['classId'] as num?)?.toInt() ?? -1,
      versionId: (m['versionId'] as num?)?.toInt() ?? 0,
      objectTypeName: m['objectTypeName'] as String?,
      classTypeName: m['classTypeName'] as String?,
      displayId: (m['displayID'] as String?) ?? (m['displayId'] as String?),
      createdUtc: _dt(m['createdUtc']),
      lastModifiedUtc: _dt(m['lastModifiedUtc']),
      viewId: (m['viewId'] as num?)?.toInt() ?? -1,
      propId: rawPropId?.toString(),
      propDatatype: m['propDatatype']?.toString(),
      isSingleFile: (m['isSingleFile'] as bool?) ?? true,
      isCheckedOut: (m['isCheckedOut'] as bool?) ?? false,
      checkoutUserId: ((m['checkoutUserId'] ?? m['checkoutuserid']) as num?)?.toInt(),
      checkoutUsername: (m['checkoutUsername'] ?? m['checkoutusername']) as String?,
      userPermission: resolvedPermission, // NEW
      permissionEntries: entries,         // NEW
    );
  }
}