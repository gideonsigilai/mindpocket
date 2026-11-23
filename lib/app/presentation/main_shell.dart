import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../app_theme.dart';
import 'screens/catalog_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'app_destination.dart';


class MainShell extends StatefulWidget {
  const MainShell({required this.controller, super.key});

  final AppController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppDestination _destination = AppDestination.home;

  void _select(AppDestination destination) {
    if (_destination == destination) return;
    setState(() => _destination = destination);
    if (destination == AppDestination.catalog &&
        widget.controller.catalogModels.isEmpty &&
        !widget.controller.isLoadingCatalog) {
      unawaited(widget.controller.searchModels());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              children: [
                Expanded(child: _workspace()),
                _BottomNavigation(
                  selected: _destination,
                  onSelected: _select,
                ),
              ],
            );
          }
          return Row(
            children: [
              _SideNavigation(
                controller: widget.controller,
                selected: _destination,
                onSelected: _select,
              ),
              Expanded(child: _workspace()),
            ],
          );
        },
      ),
    ),
  );

  Widget _workspace() => Column(
    children: [
      _TopBar(
        controller: widget.controller,
        destination: _destination,
      ),
      Expanded(
        child: switch (_destination) {
          AppDestination.home => DashboardScreen(
            controller: widget.controller,
            onNavigate: _select,
          ),
          AppDestination.catalog => CatalogScreen(
            controller: widget.controller,
          ),
          AppDestination.library => LibraryScreen(
            controller: widget.controller,
            onNavigate: _select,
          ),
          AppDestination.chat => ChatScreen(
            controller: widget.controller,
            onNavigate: _select,
          ),
          AppDestination.settings => SettingsScreen(
            controller: widget.controller,
          ),
        },
      ),
    ],
  );
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.controller,
    required this.selected,
    required this.onSelected,
  });

  final AppController controller;
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    width: 238,
    padding: const EdgeInsets.fromLTRB(16, 22, 14, 18),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(right: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.blur_on_rounded, color: AppColors.canvas),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOOM',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Local AI studio',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text(
          'WORKSPACE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.muted,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (final destination in AppDestination.values)
          _NavigationButton(
            destination: destination,
            selected: selected == destination,
            onPressed: () => onSelected(destination),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    controller.localModelPath == null
                        ? Icons.radio_button_unchecked_rounded
                        : Icons.check_circle_rounded,
                    size: 16,
                    color: controller.localModelPath == null
                        ? AppColors.muted
                        : AppColors.teal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.localModelPath == null
                          ? 'No model loaded'
                          : 'Local model ready',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                controller.settings.internetEnabled
                    ? 'Internet access is on'
                    : 'Offline mode is on',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: selected ? AppColors.raised : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                destination.icon,
                size: 19,
                color: selected ? AppColors.blue : AppColors.muted,
              ),
              const SizedBox(width: 12),
              Text(
                destination.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? AppColors.text : AppColors.muted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.destination});

  final AppController controller;
  final AppDestination destination;

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: const BoxDecoration(
      color: AppColors.canvas,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Icon(destination.icon, size: 18, color: AppColors.blue),
        const SizedBox(width: 10),
        Text(
          destination.label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        StatusPill(
          label: controller.settings.internetEnabled ? 'Online access' : 'Offline',
          icon: controller.settings.internetEnabled
              ? Icons.public_rounded
              : Icons.cloud_off_rounded,
          color: controller.settings.internetEnabled
              ? AppColors.teal
              : AppColors.amber,
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: controller.settings.internetEnabled
              ? 'Turn off internet access'
              : 'Allow internet access',
          child: Semantics(
            label: 'Internet access',
            child: Switch.adaptive(
              value: controller.settings.internetEnabled,
              onChanged: controller.setInternetEnabled,
            ),
          ),
        ),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.icon,
    required this.color,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    ),
  );
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.selected, required this.onSelected});

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: AppDestination.values.indexOf(selected),
    onDestinationSelected: (index) => onSelected(AppDestination.values[index]),
    destinations: [
      for (final destination in AppDestination.values)
        NavigationDestination(
          icon: Icon(destination.icon),
          label: destination.label,
        ),
    ],
  );
}
