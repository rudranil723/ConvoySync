import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/theme.dart';
import 'package:frontend/providers/lobby_provider.dart';
import 'lobby_screen.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignIn() {
    // Select a default lobby in provider upon sign-in to show Riverpod state linkage
    ref.read(lobbyProvider.notifier).selectConvoy(
      'mock-convoy-uuid',
      'J6LU80',
      'leader',
    );
    
    // Navigate to Dashboard / Lobby Screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LobbyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ConvoyTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              // Brand Logo with vivid orange chevron icon
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ConvoyTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.double_arrow_rounded, // Chevron graphic representation
                        color: ConvoyTheme.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'ConvoySync',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: ConvoyTheme.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: ConvoyTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to coordinate your convoy',
                style: TextStyle(
                  fontSize: 14,
                  color: ConvoyTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // Input Fields
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'Enter your email',
                  prefixIcon: Icon(Icons.email_outlined, color: ConvoyTheme.textSecondary),
                ),
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: ConvoyTheme.textPrimary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter your password',
                  prefixIcon: Icon(Icons.lock_outline, color: ConvoyTheme.textSecondary),
                ),
                obscureText: true,
                style: const TextStyle(color: ConvoyTheme.textPrimary),
              ),
              const SizedBox(height: 24),
              // Sign In Button
              ElevatedButton(
                onPressed: _handleSignIn,
                child: const Text('Sign in'),
              ),
              const SizedBox(height: 32),
              // Footer link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: ConvoyTheme.textSecondary),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Navigate to Register (or placeholder visual event)
                    },
                    child: const Text(
                      'Register',
                      style: TextStyle(
                        color: ConvoyTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
