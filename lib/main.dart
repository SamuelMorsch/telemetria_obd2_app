import 'package:flutter/material.dart';

import 'app_services.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TelemetriaApp());
}

class TelemetriaApp extends StatelessWidget {
  const TelemetriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telemetria Automotiva',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true, brightness: Brightness.dark),
      home: const AppRoot(),
    );
  }
}

/// Decide entre a tela de login e a principal, conforme haja ou não uma conta conectada.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final Future<void> _init = AppServices.instance.init();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Erro ao iniciar o app: ${snapshot.error}')));
        }
        return ListenableBuilder(
          listenable: AppServices.instance,
          builder: (BuildContext context, Widget? child) =>
              AppServices.instance.isLoggedIn ? const MainScreen() : const LoginScreen(),
        );
      },
    );
  }
}
