import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/clay_design_system.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authRepo = ref.read(authRepositoryProvider);
      dev.log('[LoginScreen] User clicked Log In. Submitting credentials...', name: 'AuthUI');

      await authRepo.login(_passwordController.text.trim());

      ref.invalidate(authStateProvider);

      if (mounted) {
        dev.log('[LoginScreen] Login succeeded. Navigating to /nearby', name: 'AuthUI');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome back!'),
            backgroundColor: ClayColors.accent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/nearby');
      }
    } catch (e) {
      if (mounted) {
        dev.log('[LoginScreen] Login error: $e', name: 'AuthUI');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: ClayColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo container
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: ClayColors.card,
                      shape: BoxShape.circle,
                      boxShadow: ClayShadows.cardElevated,
                      border: Border.all(color: ClayColors.borderSoft, width: 1.2),
                    ),
                    child: const Center(
                      child: EasyChatLogoMark(size: 48),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Easy Chat',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: ClayColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in to start discovering nearby peers',
                    style: TextStyle(
                      fontSize: 14,
                      color: ClayColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Clay Card for form inputs
                  ClayCard(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('login_password_field'),
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter your session password',
                            prefixIcon: Icon(Icons.lock_outline_rounded, color: ClayColors.textSecondary),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        ClayButton(
                          key: const Key('login_submit_button'),
                          label: _isLoading ? 'Signing in...' : 'Sign In',
                          icon: Icons.login_rounded,
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _submitLogin,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextButton(
                    onPressed: () => context.go('/register'),
                    style: TextButton.styleFrom(
                      foregroundColor: ClayColors.textSecondary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    child: const Text("New to Easy Chat? Create Profile"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
