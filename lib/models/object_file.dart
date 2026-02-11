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
    int asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
    String asStr(dynamic v) => (v ?? '').toString();

    return ObjectFile(
      fileId: asInt(json['fileId'] ?? json['fileID'] ?? json['id']),
      fileTitle: asStr(json['fileTitle'] ?? json['title'] ?? json['name']),
      fileVersion: asInt(json['fileVersion'] ?? json['version']),
      extension: asStr(json['extension'] ?? json['ext']),
      reportGuid: asStr(json['reportGuid'] ?? json['reportGUID'] ?? ''),
    );
  }
}
