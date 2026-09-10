import 'package:go_router/go_router.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/helpline/presentation/helpline_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/emergency/presentation/emergency_history_screen.dart';

/// V1 Router: Direct access to emergency finder without login or signup hurdles.
final GoRouter appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    // Redirects for legacy routes to ensure zero signup / login blocks
    GoRoute(
      path: '/login',
      redirect: (context, state) => '/home',
    ),
    GoRoute(
      path: '/onboarding',
      redirect: (context, state) => '/home',
    ),
    GoRoute(
      path: '/helpline',
      builder: (context, state) => const HelplineScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/emergency-history',
      builder: (context, state) => const EmergencyHistoryScreen(),
    ),
  ],
);
