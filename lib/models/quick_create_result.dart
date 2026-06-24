/// Result returned when a [DynamicFormScreen] is pushed in "quick create"
/// mode (i.e. launched from the "+" button next to a lookup field) and the
/// user successfully creates a new object.
///
/// [objectId] may be null if creation succeeded but the server response
/// didn't contain a parseable object ID — in that case the caller should
/// tell the user to select the new item manually from the search list.
class QuickCreateResult {
  final int? objectId;
  final String displayValue;

  const QuickCreateResult({
    required this.objectId,
    required this.displayValue,
  });
}