  import 'package:flutter/foundation.dart';

import 'user_permissions.dart';

  class ViewObject {
    final int id; // object id
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
    });

    static DateTime? _dt(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    factory ViewObject.fromJson(Map<String, dynamic> json) {
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

    // PROOF LOG (must show classId=44 for your example)
    debugPrint(
      'PARSE ViewObject → raw.classId=${json['classId']} raw.classID=${json['classID']} '
      'resolvedClassId=$resolvedClassId raw.objectTypeId=${json['objectTypeId']} resolvedObjectTypeId=$resolvedObjectTypeId '
      'raw.id=${json['id']} raw.displayID=${json['displayID']} resolvedId=$resolvedId',
    );

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
    );
  }
}
