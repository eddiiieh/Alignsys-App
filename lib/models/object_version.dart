class ObjectVersionFile {
  final int fileId;
  final String fileTitle;
  final int fileVersion;
  final String extension;
  final String? reportGuid;

  const ObjectVersionFile({
    required this.fileId,
    required this.fileTitle,
    required this.fileVersion,
    required this.extension,
    this.reportGuid,
  });

  factory ObjectVersionFile.fromJson(Map<String, dynamic> m) {
    return ObjectVersionFile(
      fileId: (m['fileID'] as num?)?.toInt() ?? 0,
      fileTitle: (m['fileTitle'] as String?) ?? '',
      fileVersion: (m['fileversion'] as num?)?.toInt() ?? 0,
      extension: (m['extension'] as String?) ?? '',
      reportGuid: m['reportGuid'] as String?,
    );
  }
}

class ObjectVersion {
  final int versionId;
  final String title;
  final String lastModifiedBy;
  final String lastModifiedUtc;
  final String extension;
  final int classId;
  final String className;
  final String displayId;
  final bool isSingleFile;
  final List<ObjectVersionFile> files;

  const ObjectVersion({
    required this.versionId,
    required this.title,
    required this.lastModifiedBy,
    required this.lastModifiedUtc,
    required this.extension,
    required this.classId,
    required this.className,
    required this.displayId,
    required this.isSingleFile,
    required this.files,
  });

  /// Convenience: first file, or null if none attached.
  ObjectVersionFile? get firstFile => files.isNotEmpty ? files.first : null;

  factory ObjectVersion.fromJson(Map<String, dynamic> m) {
    final rawFiles = m['objectFiles'] as List? ?? [];
    return ObjectVersion(
      versionId: (m['versionid'] as num?)?.toInt() ?? 0,
      title: (m['title'] as String?) ?? '',
      lastModifiedBy: (m['lastModifiedBy'] as String?) ?? '',
      lastModifiedUtc: (m['lastModifiedUtc'] as String?) ?? '',
      extension: (m['extension'] as String?) ?? '',
      classId: (m['class'] as num?)?.toInt() ?? 0,
      className: (m['className'] as String?) ?? '',
      displayId: (m['displayID'] as String?) ?? '',
      isSingleFile: (m['isSingleFile'] as bool?) ?? true,
      files: rawFiles
          .whereType<Map<String, dynamic>>()
          .map(ObjectVersionFile.fromJson)
          .toList(),
    );
  }
}