class GroupFilter {
  final String propId;
  final String propDatatype;

  const GroupFilter({required this.propId, required this.propDatatype});

  Map<String, dynamic> toJson() => {
        "propId": propId,
        "propDatatype": propDatatype,
      };
}
