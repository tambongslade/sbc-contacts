import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sbc_contacts/core/theme/app_theme.dart';
import 'package:sbc_contacts/features/auth/application/sso_link_handler.dart';
import 'package:sbc_contacts/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The UI is French; DateFormat throws on a 'fr' pattern without this.
  await initializeDateFormatting('fr');
  runApp(const ProviderScope(child: SbcContactsApp()));
}

class SbcContactsApp extends ConsumerStatefulWidget {
  const SbcContactsApp({super.key});

  @override
  ConsumerState<SbcContactsApp> createState() => _SbcContactsAppState();
}

class _SbcContactsAppState extends ConsumerState<SbcContactsApp> {
  @override
  void initState() {
    super.initState();
    // Start listening for the SSO deep-link redirect.
    ref.read(ssoLinkHandlerProvider).init();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'SBC Contacts',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // SBC Contacts is a light-ground product: the brand lockup and the
      // directory cards are designed on the light surface, so the app does
      // not follow the phone's dark mode.
      themeMode: ThemeMode.light,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
