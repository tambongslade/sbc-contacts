import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/auth/presentation/account_screen.dart';
import 'package:sbc_contacts/features/contacts/contacts_permission_gate.dart';
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

  @override
  void initState() {
    super.initState();
    // Ask for contacts access once the shell is on screen, so the member sees
    // the app behind the explanation rather than a bare system dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ContactsPermissionGate.ensure(context, ref);
    });
  }

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
      // The bar floats over the content rather than sitting in a docked strip,
      // so the list visibly continues underneath it.
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _FloatingNavBar(
        index: _index,
        unread: unread,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// The navigation bar as a floating pill: a white, heavily rounded slab lifted
/// off the ground by one soft shadow, with the selected destination marked by a
/// filled disc behind its icon.
///
/// Colour alone never carries the selection — the disc, the icon weight and the
/// label weight all change together, so the current tab survives a greyscale or
/// colour-blind reading.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.unread,
    required this.onSelect,
  });

  final int index;
  final int unread;
  final ValueChanged<int> onSelect;

  static const List<({IconData icon, String label})> _items = [
    (icon: Icons.search_rounded, label: 'Recherche'),
    (icon: Icons.sync_rounded, label: 'Synchro'),
    (icon: Icons.star_rounded, label: 'Favoris'),
    (icon: Icons.notifications_rounded, label: 'Alertes'),
    (icon: Icons.person_rounded, label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavItem(
                      icon: _items[i].icon,
                      label: _items[i].label,
                      selected: i == index,
                      // Alerts is the only destination with pending state, and
                      // it is shown as a dot rather than a number: the exact
                      // count is on the screen itself.
                      dot: i == 3 && unread > 0,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.dot,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const active = SbcColors.secondaryDark;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        containedInkWell: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 44,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? SbcColors.secondary.withValues(alpha: 0.20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    icon,
                    size: 23,
                    color: selected ? active : muted,
                  ),
                ),
                if (dot)
                  Positioned(
                    right: 6,
                    top: 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: SbcColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? theme.colorScheme.onSurface : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
