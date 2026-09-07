import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/storage/token_storage.dart';
import 'package:sbc_contacts/main.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/sbc_logo.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('EmptyState renders title and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: Icons.search, title: 'Aucun résultat', message: 'Réessaie'),
        ),
      ),
    );
    expect(find.text('Aucun résultat'), findsOneWidget);
    expect(find.text('Réessaie'), findsOneWidget);
  });

  testWidgets('app boots to the login screen when signed out', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        ],
        child: const SbcContactsApp(),
      ),
    );
    // Let the async session-restore resolve and the router settle to /login.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Se connecter avec SBC'), findsOneWidget);
    expect(find.byType(SbcLogo), findsOneWidget);
  });
}
