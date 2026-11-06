import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../features/capture/presentation/capture_sheet.dart';
import '../../features/collections/binders/collections_binding.dart';
import '../../features/collections/presentation/collections_page.dart';
import '../../features/home/binders/home_binding.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/settings/binders/settings_binding.dart';
import '../../features/settings/presentation/settings_page.dart';

/// Root shell: Home, Collections, Settings, plus the Capture action.
///
/// Pages are kept in an [IndexedStack] so scroll positions and search state
/// survive tab switches, while each page owns its own binding.
class AppShell extends StatelessWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) => _ShellBody(initialIndex: initialIndex);
}

class _ShellBody extends StatefulWidget {
  const _ShellBody({required this.initialIndex});

  final int initialIndex;

  @override
  State<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends State<_ShellBody> {
  late int _index = widget.initialIndex;

  late final List<Widget> _pages = <Widget>[
    _BoundPage(initial: HomeBinding(), child: const HomePage()),
    _BoundPage(initial: CollectionsBinding(), child: const CollectionsPage()),
    _BoundPage(initial: SettingsBinding(), child: const SettingsPage()),
  ];

  void _select(int value) {
    if (_index == value) return;
    setState(() => _index = value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 900;
        final Widget content = IndexedStack(index: _index, children: _pages);

        if (wide) {
          return Scaffold(
            floatingActionButton: _CaptureAction(onHome: _index == 0),
            body: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder_rounded),
                      label: Text('Collections'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings_rounded),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          floatingActionButton: _CaptureAction(onHome: _index == 0),
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Collections',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Capture is only offered on Home, where the timeline is visible, so a
/// mis-tap never interrupts settings work.
class _CaptureAction extends StatelessWidget {
  const _CaptureAction({required this.onHome});

  final bool onHome;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: onHome ? 1 : 0,
      child: IgnorePointer(
        ignoring: !onHome,
        child: Padding(
          padding: EdgeInsets.only(bottom: 4.h),
          child: FloatingActionButton.extended(
            onPressed: () => CaptureSheet.show(context),
            backgroundColor: Theme.of(context).colorScheme.inverseSurface,
            foregroundColor: Theme.of(context).colorScheme.onInverseSurface,
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text('Capture'),
            shape: const StadiumBorder(),
            tooltip: 'Capture a screenshot, voice note, or written note',
          ),
        ),
      ),
    );
  }
}

/// Applies a GetX binding exactly once for a tab page.
class _BoundPage extends StatefulWidget {
  const _BoundPage({required this.initial, required this.child});

  final Bindings initial;
  final Widget child;

  @override
  State<_BoundPage> createState() => _BoundPageState();
}

class _BoundPageState extends State<_BoundPage> {
  bool _bound = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  /// Bindings are idempotent: a tab rebuilt after a theme change must not
  /// replace a live controller and drop in-flight edits.
  void _bind() {
    if (_bound) return;
    _bound = true;
    widget.initial.dependencies();
  }

  @override
  Widget build(BuildContext context) {
    _bind();
    return widget.child;
  }
}
