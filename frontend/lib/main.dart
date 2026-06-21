import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';

void main() {
  runApp(const ConvoySyncApp());
}

class ConvoySyncApp extends StatelessWidget {
  const ConvoySyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConvoySync',
      debugShowCheckedModeBanner: false,
      theme: ConvoyTheme.darkTheme,
      home: const AuthScreen(),
    );
  }
}
