import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const _items = [
    (route: '/home', icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首页'),
    (route: '/discover', icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: '发现'),
    (route: '/schedule', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: '追番'),
    (route: '/library', icon: Icons.video_library_outlined, selectedIcon: Icons.video_library, label: '我的'),
    (route: '/settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置'),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _items.indexWhere((item) => location.startsWith(item.route));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final index = _selectedIndex(context);
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final content = SafeArea(child: child);
    return Scaffold(
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 168,
                  selectedIndex: index,
                  onDestinationSelected: (value) => context.go(_items[value].route),
                  destinations: [
                    for (final item in _items)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selectedIcon),
                        label: Text(item.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => context.go(_items[value].route),
              destinations: [
                for (final item in _items)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/search'),
        icon: const Icon(Icons.search),
        label: const Text('搜索'),
      ),
    );
  }
}
