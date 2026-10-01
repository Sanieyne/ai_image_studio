import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_form_widgets.dart';

/// Sign-in screen. On success [AuthService] flips to authenticated and the
/// app's login gate swaps to [HomeScreen] — no navigation code needed here.
class LoginScreen extends StatefulWidget {
  final VoidCallback onShowRegister;

  const LoginScreen({super.key, required this.onShowRegister});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.login(
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
      title: 'Welcome back',
      subtitle: 'Sign in to continue to your studio',
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
              hint: 'Your password',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              textInputAction: TextInputAction.done,
              validator: AuthValidators.loginPassword,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            LuminaAuthButton(
              label: 'Sign In',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(
                    color: LuminaColors.darkMuted,
                    fontSize: 13,
                  ),
                ),
                GestureDetector(
                  onTap: _loading ? null : widget.onShowRegister,
                  child: const Text(
                    'Create one',
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
