import 'user_permissions.dart';

class ViewObject {
  final int id;
  final String title;
  final int objectTypeId;
  final int classId;
  final int versionId;
  final String objectTypeName;
  final String classTypeName;
  final String displayId;
  final DateTime? createdUtc;
  final DateTime? lastModifiedUtc;
  final UserPermission? userPermission;
  final List<UserPermissionEntry> permissionEntries; // NEW
  final bool isSingleFile;
  final bool isCheckedOut;
  final int? checkoutUserId;
  final String? checkoutUsername;

  ViewObject({
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
    this.userPermission,
    this.permissionEntries = const [], // NEW
    required this.isSingleFile,
    this.isCheckedOut = false,
    this.checkoutUserId,
    this.checkoutUsername
  });

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory ViewObject.fromJson(Map<String, dynamic> json, {int? forUserId}) {
    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    final resolvedId = asInt(json['id']) != 0
        ? asInt(json['id'])
        : asInt(json['displayID']) != 0
            ? asInt(json['displayID'])
            : asInt(json['displayId']);

    final resolvedObjectTypeId = asInt(json['objectTypeId']) != 0
        ? asInt(json['objectTypeId'])
        : asInt(json['objectID']) != 0
            ? asInt(json['objectID'])
            : asInt(json['objectTypeID']);

    final resolvedClassId = asInt(json['classId']) != 0
        ? asInt(json['classId'])
        : asInt(json['classID']) != 0
            ? asInt(json['classID'])
            : asInt(json['classTypeId']);

    // ── NEW PERMISSIONS PARSING ──
    final rawPerm = json['userPermission'];
    UserPermission? resolvedPermission;
    List<UserPermissionEntry> entries = const [];

    if (rawPerm is Map<String, dynamic>) {
      // Old format fallback
      resolvedPermission = UserPermission.fromJson(rawPerm);
    } else if (rawPerm is List) {
      // New array format
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

    return ViewObject(
      id: resolvedId,
      title: (json['title'] as String?) ?? '',
      objectTypeId: resolvedObjectTypeId,
      classId: resolvedClassId,
      versionId: asInt(json['versionId']),
      objectTypeName: (json['objectTypeName'] as String?) ?? '',
      classTypeName: (json['classTypeName'] as String?) ?? '',
      displayId: (json['displayID']?.toString()) ?? (json['displayId']?.toString()) ?? '',
      createdUtc: _dt(json['createdUtc']),
      lastModifiedUtc: _dt(json['lastModifiedUtc']),
      userPermission: resolvedPermission,
      permissionEntries: entries,
      isSingleFile: (json['isSingleFile'] as bool?) ?? true,
      isCheckedOut: (json['isCheckedOut'] as bool?) ?? false,
      checkoutUserId: asInt(json['checkoutUserId']),
      checkoutUsername: (json['checkoutUsername'] as String?) ?? '',
    );
  }
}