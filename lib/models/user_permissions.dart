class UserPermission {
  final bool readPermission;
  final bool editPermission;
  final bool attachObjectsPermission;
  final bool deletePermission;
  final bool isClassDeleted;
  final bool changePermission;

  const UserPermission({
    required this.readPermission,
    required this.editPermission,
    required this.attachObjectsPermission,
    required this.deletePermission,
    required this.isClassDeleted,
    this.changePermission = false,
  });

  static const denyAll = UserPermission(
    readPermission: false,
    editPermission: false,
    attachObjectsPermission: false,
    deletePermission: false,
    isClassDeleted: false,
  );

  factory UserPermission.fromJson(Map<String, dynamic>? json) {
    bool b(dynamic v) {
      if (v is bool) return v;
      if (v == null) return false;
      final s = v.toString().toLowerCase();
      return s == 'true' || s == '1';
    }

    final m = json ?? const <String, dynamic>{};
    return UserPermission(
      readPermission: b(m['readPermission']),
      editPermission: b(m['editPermission']),
      // Handles both old and new payload keys
      attachObjectsPermission: b(m['attachObjectsPermission'] ?? m['attach']),
      deletePermission: b(m['deletePermission']),
      isClassDeleted: b(m['isClassDeleted']),
      changePermission: b(m['change']),
    );
  }
}

/// Represents one user's permissions from the new array payload.
class UserPermissionEntry {
  final int userId;
  final String? fullName;
  final UserPermission permission;

  const UserPermissionEntry({
    required this.userId,
    required this.permission,
    this.fullName,
  });

  factory UserPermissionEntry.fromJson(Map<String, dynamic> m) {
    final rawPerm = m['userPermission'];
    final rawName = m['fullName'] as String?;
    return UserPermissionEntry(
      userId: (m['userid'] as num?)?.toInt() ?? (m['userId'] as num?)?.toInt() ?? 0,
      fullName: (rawName == null || rawName.trim().isEmpty) ? null : rawName,
      permission: UserPermission.fromJson(
        rawPerm is Map<String, dynamic> ? rawPerm : null,
      ),
    );
  }

  String get displayName {
    final n = fullName?.trim();
    return (n == null || n.isEmpty) ? 'User $userId' : n;
  }
}