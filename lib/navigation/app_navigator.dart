import 'package:flutter/material.dart';

/// Global navigator key so non-widget classes (like MFilesService) can
/// trigger navigation — e.g. redirecting to /login when a session expires.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();