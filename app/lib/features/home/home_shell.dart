import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/features/auth/presentation/account_screen.dart';
import 'package:sbc_contacts/features/directory/presentation/search_screen.dart';
import 'package:sbc_contacts/features/favorites/presentation/favorites_screen.dart';
import 'package:sbc_contacts/features/notifications/application/notifications_controller.dart';
import 'package:sbc_contacts/features/notifications/presentation/notifications_screen.dart';
import 'package:sbc_contacts/features/sync/presentation/sync_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _screens = [
    SearchScreen(),
    SyncScreen(),
    FavoritesScreen(),
    NotificationsScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.search), label: 'Rechercher'),
          const NavigationDestination(icon: Icon(Icons.sync), label: 'Synchro'),
          const NavigationDestination(icon: Icon(Icons.star_border), label: 'Favoris'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_none),
            ),
            label: 'Alertes',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }
}
