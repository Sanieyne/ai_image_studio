import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_form_widgets.dart';

/// Registration screen. Field rules mirror the backend `registerSchema`;
/// server validation errors are shown inline via the error banner.
class RegisterScreen extends StatefulWidget {
  final VoidCallback onShowLogin;

  const RegisterScreen({super.key, required this.onShowLogin});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.register(
        _usernameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
      );
      // Auth gate reacts to the status change; nothing to navigate.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LuminaAuthScaffold(
      title: 'Create your account',
      subtitle: 'Usernames are alphanumeric, 3–30 characters',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              LuminaAuthErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            LuminaAuthTextField(
              controller: _usernameController,
              label: 'Username',
              hint: 'e.g. pixelartist7',
              icon: Icons.person_outline_rounded,
              validator: AuthValidators.username,
            ),
            const SizedBox(height: 14),
            LuminaAuthTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'you@example.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 14),
            LuminaAuthTextField(
              controller: _passwordController,
              label: 'Password',
              hint: '8+ chars, upper + lower + number',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              textInputAction: TextInputAction.done,
              validator: AuthValidators.registerPassword,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            LuminaAuthButton(
              label: 'Create Account',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                const Text(
                  'Already have an account? ',
                  style: TextStyle(
                    color: LuminaColors.darkMuted,
                    fontSize: 13,
                  ),
                ),
                GestureDetector(
                  onTap: _loading ? null : widget.onShowLogin,
                  child: const Text(
                    'Sign in',
                    style: TextStyle(
                      color: LuminaColors.primaryEnd,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
