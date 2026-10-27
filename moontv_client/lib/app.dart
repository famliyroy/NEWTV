import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/session_manager.dart';
import 'core/theme/app_theme.dart';
import 'domain/models/media_item.dart';
import 'features/auth/login_page.dart';
import 'features/detail/detail_page.dart';
import 'features/home/app_shell.dart';
import 'features/home/discover_page.dart';
import 'features/home/home_page.dart';
import 'features/library/library_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/player/player_page.dart';
import 'features/schedule/schedule_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_page.dart';
import 'providers.dart';

final sessionProvider = ChangeNotifierProvider<SessionManager>(
  (ref) => ref.watch(appDependenciesProvider).session,
);

final settingsProvider = ChangeNotifierProvider(
  (ref) => ref.watch(appDependenciesProvider).settings,
);

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);
  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.uri.path;
      switch (session.status) {
        case SessionStatus.unconfigured:
          return location == '/onboarding' ? null : '/onboarding';
        case SessionStatus.unauthenticated:
          return location == '/login' || location == '/onboarding' ? null : '/login';
        case SessionStatus.authenticated:
          if (location == '/login' || location == '/onboarding') return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(path: '/discover', builder: (context, state) => const DiscoverPage()),
          GoRoute(path: '/schedule', builder: (context, state) => const SchedulePage()),
          GoRoute(path: '/library', builder: (context, state) => const LibraryPage()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) {
          final extra = state.extra;
          final query = extra is String
              ? extra
              : state.uri.queryParameters['q'];
          return SearchPage(initialQuery: query);
        },
      ),
      GoRoute(
        path: '/detail',
        builder: (context, state) {
          final extra = state.extra;
          final sources = extra is List<MediaItem>
              ? extra
              : extra is MediaItem
                  ? [extra]
                  : const <MediaItem>[];
          if (sources.isEmpty) return const HomePage();
          return DetailPage(initialItem: sources.first, availableSources: sources);
        },
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final playback = state.extra;
          if (playback is! PlaybackContext) return const HomePage();
          return PlayerPage(playback: playback);
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class NewtvApp extends ConsumerWidget {
  const NewtvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider).settings;
    final themeMode = switch (settings.themeModeIndex) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'NEWTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      themeAnimationDuration: settings.reduceMotion
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 280),
    );
  }
}
