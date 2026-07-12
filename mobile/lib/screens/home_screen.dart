import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'global_dashboard_screen.dart';
import 'bandes_screen.dart';
import 'stocks_screen.dart';
import 'alertes_screen.dart';
import 'crm_screen.dart';
import 'finance_screen.dart';
import 'roadmap_screen.dart';
import 'profile_screen.dart';
import 'config_screen.dart';
import '../providers/auth_provider.dart';

class _ModuleItem {
  final Widget page;
  final NavigationDestination desktopDestination;
  final NavigationDestination mobileDestination;
  final String permission;
  final bool adminOnly;

  const _ModuleItem({
    required this.page,
    required this.desktopDestination,
    required this.mobileDestination,
    required this.permission,
    this.adminOnly = false,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<_ModuleItem> _modules = const [
    _ModuleItem(
      page: GlobalDashboardScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
      permission: 'dashboard:view',
    ),
    _ModuleItem(
      page: BandesScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.egg_outlined), selectedIcon: Icon(Icons.egg), label: 'Cycles'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.egg_outlined), selectedIcon: Icon(Icons.egg), label: 'Cycles'),
      permission: 'bandes:view',
    ),
    _ModuleItem(
      page: StocksScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stocks'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stocks'),
      permission: 'stocks:view',
    ),
    _ModuleItem(
      page: AlertesScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Todo list'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Todo'),
      permission: 'alertes:view',
    ),
    _ModuleItem(
      page: CrmScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.people_outlined), selectedIcon: Icon(Icons.people), label: 'CRM'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.people_outlined), selectedIcon: Icon(Icons.people), label: 'CRM'),
      permission: 'crm:view',
    ),
    _ModuleItem(
      page: FinanceScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Tresorerie'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Finance'),
      permission: 'dashboard:view',
    ),
    _ModuleItem(
      page: RoadmapScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: 'Roadmap'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: 'Roadmap'),
      permission: 'dashboard:view',
    ),
    _ModuleItem(
      page: ProfileScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.account_circle_outlined), selectedIcon: Icon(Icons.account_circle), label: 'Profil'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.account_circle_outlined), selectedIcon: Icon(Icons.account_circle), label: 'Profil'),
      permission: 'dashboard:view',
    ),
    _ModuleItem(
      page: ConfigScreen(),
      desktopDestination: NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Config'),
      mobileDestination: NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Config'),
      permission: 'config:view',
      adminOnly: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isWide = MediaQuery.of(context).size.width >= 1000;
    final accessibleModules = _modules.where((m) {
      if (m.adminOnly && !auth.isAdmin) return false;
      return auth.hasPermission(m.permission);
    }).toList();

    if (accessibleModules.isEmpty) {
      return const Scaffold(body: Center(child: Text('Aucun module autorisé')));
    }

    if (_currentIndex >= accessibleModules.length) {
      _currentIndex = 0;
    }

    final destinations = isWide
        ? accessibleModules.map((m) => m.desktopDestination).toList()
        : accessibleModules.map((m) => m.mobileDestination).toList();

    return Scaffold(
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) => setState(() => _currentIndex = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: destinations
                      .map(
                        (d) => NavigationRailDestination(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: Text(d.label),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: accessibleModules[_currentIndex].page),
              ],
            )
          : accessibleModules[_currentIndex].page,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: destinations,
            ),
    );
  }
}
