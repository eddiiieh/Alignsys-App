class UserPermission {
  final bool readPermission;
  final bool editPermission;
  final bool attachObjectsPermission;
  final bool deletePermission;
  final bool isClassDeleted;

  const UserPermission({
    required this.readPermission,
    required this.editPermission,
    required this.attachObjectsPermission,
    required this.deletePermission,
    required this.isClassDeleted,
  });

  factory UserPermission.fromJson(Map<String, dynamic>? json) {
    bool b(dynamic v) => v == true || v?.toString().toLowerCase() == 'true';

    final m = json ?? const <String, dynamic>{};
    return UserPermission(
      readPermission: b(m['readPermission']),
      editPermission: b(m['editPermission']),
      attachObjectsPermission: b(m['attachObjectsPermission']),
      deletePermission: b(m['deletePermission']),
      isClassDeleted: b(m['isClassDeleted']),
    );
  }
}
