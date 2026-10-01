/// Defines properties whose visibility on create/edit forms depends on
/// another property's boolean value, mirroring hardcoded show/hide rules
/// baked into the web app's frontend (no backend/API involvement, see
/// investigation notes in mfiles_service.dart's ClassProps handling).
///
/// Currently sourced from one confirmed pattern in this vault: selecting
/// "Yes" on propId 1119 ("Forward for Review/Approval?") reveals props
/// 1120, 1121, 1122, 1173, 1177, 1178 on document create forms. If more
/// such pairs are discovered elsewhere in the vault, add them here so both
/// DynamicFormScreen and TemplateFormScreen stay in sync automatically.
class ConditionalPropertyRule {
  final int dependsOnPropId;
  final bool showWhenTrue;

  const ConditionalPropertyRule({
    required this.dependsOnPropId,
    required this.showWhenTrue,
  });
}

const Map<int, ConditionalPropertyRule> conditionalProperties = {
  1120: ConditionalPropertyRule(dependsOnPropId: 1119, showWhenTrue: true),
  1121: ConditionalPropertyRule(dependsOnPropId: 1119, showWhenTrue: true),
  1122: ConditionalPropertyRule(dependsOnPropId: 1119, showWhenTrue: true),
  1173: ConditionalPropertyRule(dependsOnPropId: 1119, showWhenTrue: true),
  1177: ConditionalPropertyRule(dependsOnPropId: 1119, showWhenTrue: true),
  1178: ConditionalPropertyRule(dependsOnPropId: 1119, showWhenTrue: true),
};

/// True if [propId] has no conditional rule (always visible), or if it does
/// and the controlling property's current boolean value in [formValues]
/// matches the rule's showWhenTrue condition.
///
/// [formValues] should map propId -> current value, using whatever value
/// map the calling screen already maintains (works for both
/// Map<int, dynamic> and a plain lookup function wrapping it).
bool isConditionallyVisible(int propId, dynamic Function(int) getValue) {
  final rule = conditionalProperties[propId];
  if (rule == null) return true;
  final controllerValue = getValue(rule.dependsOnPropId);
  return controllerValue == rule.showWhenTrue;
}