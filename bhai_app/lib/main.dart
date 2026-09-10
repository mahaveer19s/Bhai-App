import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'core/security/security_service.dart';
import 'core/services/notification_service.dart';
import 'core/storage/local_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await Hive.initFlutter();
  await LocalStorage().init();
  await SecurityService().init();
  await NotificationService().initialize();
  
  runApp(
    const ProviderScope(
      child: BhaiApp(),
    ),
  );
}

class BhaiApp extends ConsumerWidget {
  const BhaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read theme state from settings box if present
    final settingsBox = Hive.box('settings');
    final isDarkMode = settingsBox.get('dark_mode', defaultValue: true) as bool;

    return MaterialApp.router(
      title: 'BHAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
