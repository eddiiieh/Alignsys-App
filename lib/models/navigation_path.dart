/// Model to track navigation path for breadcrumbs
class NavigationPath {
  final List<NavigationStep> steps;

  NavigationPath({required this.steps});

  /// Creates a path for home screen
  factory NavigationPath.home() {
    return NavigationPath(steps: [
      NavigationStep(label: 'Home', type: NavigationStepType.home),
    ]);
  }

  /// Creates a path for a view (e.g., Common Views > Documents)
  factory NavigationPath.view({
    required String viewName,
    String? parentSection,
  }) {
    final steps = <NavigationStep>[
      NavigationStep(label: 'Home', type: NavigationStepType.home),
    ];

    if (parentSection != null) {
      steps.add(NavigationStep(label: parentSection, type: NavigationStepType.section));
    }

    steps.add(NavigationStep(label: viewName, type: NavigationStepType.view));

    return NavigationPath(steps: steps);
  }

  /// Creates a path for view items (e.g., Home > Documents > By Workflow State)
  factory NavigationPath.viewItems({
    required String viewName,
    required String itemName,
    String? parentSection,
  }) {
    final steps = <NavigationStep>[
      NavigationStep(label: 'Home', type: NavigationStepType.home),
    ];

    if (parentSection != null) {
      steps.add(NavigationStep(label: parentSection, type: NavigationStepType.section));
    }

    steps.add(NavigationStep(label: viewName, type: NavigationStepType.view));
    steps.add(NavigationStep(label: itemName, type: NavigationStepType.grouping));

    return NavigationPath(steps: steps);
  }

  /// Creates a path for object details
  factory NavigationPath.objectDetails({
    required String objectTitle,
    required String viewName,
    String? parentSection,
    String? groupingName,
  }) {
    final steps = <NavigationStep>[
      NavigationStep(label: 'Home', type: NavigationStepType.home),
    ];

    if (parentSection != null) {
      steps.add(NavigationStep(label: parentSection, type: NavigationStepType.section));
    }

    steps.add(NavigationStep(label: viewName, type: NavigationStepType.view));

    if (groupingName != null) {
      steps.add(NavigationStep(label: groupingName, type: NavigationStepType.grouping));
    }

    steps.add(NavigationStep(label: objectTitle, type: NavigationStepType.object));

    return NavigationPath(steps: steps);
  }

  /// Adds a step to the path
  NavigationPath addStep(NavigationStep step) {
    return NavigationPath(steps: [...steps, step]);
  }

  /// Removes the last step
  NavigationPath popStep() {
    if (steps.length <= 1) return this;
    return NavigationPath(steps: steps.sublist(0, steps.length - 1));
  }
}

class NavigationStep {
  final String label;
  final NavigationStepType type;

  NavigationStep({
    required this.label,
    required this.type,
  });
}

enum NavigationStepType {
  home,
  section, // "Common Views", "Other Views"
  view, // "Documents", "Customers"
  grouping, // "By Workflow State", "By Class"
  object, // Individual object
}