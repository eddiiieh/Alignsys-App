class Vault {
  final String name;
  final String guid;
  final String vaultId;

  Vault({
    required this.name,
    required this.guid, 
    required this.vaultId,
    });

  factory Vault.fromJson(Map<String, dynamic> json) {
    return Vault(
      name: json['name'] ?? '',
      guid: json['guid'] ?? '',
      vaultId: json['vaultId'] ?? '',
    );
  }
}
