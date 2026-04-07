import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_pdf_annotations',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2196F3),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
