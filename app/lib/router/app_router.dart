import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:sbc_contacts/features/auth/presentation/login_screen.dart';
import 'package:sbc_contacts/features/directory/presentation/profile_screen.dart';
import 'package:sbc_contacts/features/home/home_shell.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/presentation/criteria_edit_screen.dart';

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Resolves a criteria id from the loaded list for editing.
class _CriteriaEditRoute extends ConsumerWidget {
  const _CriteriaEditRoute({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(criteriaControllerProvider).value ?? [];
    final match = list.where((c) => c.id == id).toList();
    if (match.isEmpty) return const _SplashScreen();
    return CriteriaEditScreen(existing: match.first);
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(authControllerProvider, (_, __) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading) return loc == '/splash' ? null : '/splash';
      final loggedIn = auth.value != null;
      if (!loggedIn) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeShell()),
      GoRoute(
        path: '/profile/:sbcId',
        builder: (_, s) => ProfileScreen(sbcId: s.pathParameters['sbcId']!),
      ),
      GoRoute(path: '/criteria/new', builder: (_, __) => const CriteriaEditScreen()),
      GoRoute(
        path: '/criteria/:id',
        builder: (_, s) => _CriteriaEditRoute(id: s.pathParameters['id']!),
      ),
    ],
  );
});
