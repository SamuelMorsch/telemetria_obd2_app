import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const TelemetriaApp());
}

class TelemetriaApp extends StatelessWidget {
  const TelemetriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telemetria OBD-II',
      debugShowCheckedModeBanner: false, // Tira a faixa de "Debug"
      theme: ThemeData(
        brightness: Brightness.dark, // Ativa o Dark Mode base
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Fundo azul bem escuro (Slate 900)
        primaryColor: const Color(0xFF38BDF8), // Azul ciano moderno
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0, // Tira a sombra dura
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF38BDF8)),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}