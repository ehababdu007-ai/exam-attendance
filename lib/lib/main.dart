import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/settings_provider.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  final storageService = StorageService();
  await storageService.init();

  final settingsProvider = SettingsProvider();
  await settingsProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProxyProvider<SettingsProvider, AttendanceProvider>(
          create: (_) {
            final provider = AttendanceProvider(storageService: storageService);
            provider.updateWebAppUrl(settingsProvider.webAppUrl);
            provider.loadInitialData();
            return provider;
          },
          update: (_, settings, previous) {
            final provider = previous ?? AttendanceProvider(storageService: storageService);
            provider.updateWebAppUrl(settings.webAppUrl);
            return provider;
          },
        ),
      ],
      child: const ExamAttendanceApp(),
    ),
  );
}

class ExamAttendanceApp extends StatelessWidget {
  const ExamAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حضور الامتحانات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        fontFamily: 'Cairo',
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
