import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/clay_design_system.dart';
import '../data/auth_repository.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authRepo = ref.read(authRepositoryProvider);
      dev.log('[REGISTER_UI] Registering user...', name: 'AuthTrace');

      await authRepo.registerAndLogin(
        _passwordController.text.trim(),
        displayName: _nameController.text.trim(),
      );

      ref.invalidate(authStateProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created! Welcome to Easy Chat.'),
            backgroundColor: ClayColors.accent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/nearby');
      }
    } catch (e, stack) {
      if (mounted) {
        dev.log('[REGISTER_UI][ERROR] Exception during register: $e\n$stack', name: 'AuthTrace');
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
                    'Create Profile',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: ClayColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Set up your handle to chat with nearby peers',
                    style: TextStyle(
                      fontSize: 14,
                      color: ClayColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  ClayCard(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('register_name_field'),
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            hintText: 'e.g. Alex',
                            prefixIcon: Icon(Icons.badge_outlined, color: ClayColors.textSecondary),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 2) {
                              return 'Please enter a name (at least 2 characters)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            hintText: 'Choose a password (min 6 characters)',
                            prefixIcon: Icon(Icons.lock_outline_rounded, color: ClayColors.textSecondary),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: Icon(Icons.lock_outline_rounded, color: ClayColors.textSecondary),
                          ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 28),
                        ClayButton(
                          label: _isLoading ? 'Creating...' : 'Create Account',
                          icon: Icons.arrow_forward_rounded,
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _submitRegister,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextButton(
                    onPressed: () => context.go('/login'),
                    style: TextButton.styleFrom(
                      foregroundColor: ClayColors.textSecondary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    child: const Text("Already have a profile? Sign In"),
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
