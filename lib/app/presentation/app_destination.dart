import 'package:material_ui/material_ui.dart';

enum AppDestination { home, catalog, library, chat, settings }

extension AppDestinationPresentation on AppDestination {
  String get label => switch (this) {
    AppDestination.home => 'Overview',
    AppDestination.catalog => 'Model catalog',
    AppDestination.library => 'My models',
    AppDestination.chat => 'Chat',
    AppDestination.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    AppDestination.home => Icons.space_dashboard_outlined,
    AppDestination.catalog => Icons.explore_outlined,
    AppDestination.library => Icons.storage_outlined,
    AppDestination.chat => Icons.forum_outlined,
    AppDestination.settings => Icons.tune_rounded,
  };
}
