class ObjectFile {
  final int fileId;
  final String fileTitle;
  final int fileVersion;
  final String extension;
  final String reportGuid;

  ObjectFile({
    required this.fileId,
    required this.fileTitle,
    required this.fileVersion,
    required this.extension,
    required this.reportGuid,
  });

  factory ObjectFile.fromJson(Map<String, dynamic> json) {
    return ObjectFile(
      fileId: (json['fileID'] as num?)?.toInt() ?? 0,
      fileTitle: (json['fileTitle'] as String?) ?? '',
      fileVersion: (json['fileversion'] as num?)?.toInt() ?? 0,
      extension: (json['extension'] as String?) ?? '',
      reportGuid: (json['reportGuid'] as String?) ?? '',
    );
  }
}
