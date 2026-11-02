import 'dart:async';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_form_widgets.dart';

/// Password recovery screen.
/// Step 1: Requests an OTP code to user's registered email.
/// Step 2: Validates the 6-digit OTP code and updates the user's password.
class ForgotPasswordScreen extends StatefulWidget {
  final VoidCallback onShowLogin;
  final void Function(String message)? onPasswordResetSuccess;

  const ForgotPasswordScreen({
    super.key,
    required this.onShowLogin,
    this.onPasswordResetSuccess,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _success;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    _resendCooldown = seconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
  }

  Future<void> _requestOtp() async {
    setState(() {
      _error = null;
      _success = null;
    });
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      final msg = await AuthService.instance.requestPasswordReset(email);
      if (mounted) {
        setState(() {
          _codeSent = true;
          _success = msg;
        });
        _startCooldown(60);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitReset() async {
    setState(() {
      _error = null;
      _success = null;
    });
    if (!_resetFormKey.currentState!.validate()) return;

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      final code = _otpController.text.trim();
      final newPass = _newPasswordController.text;

      final msg = await AuthService.instance.resetPassword(
        email: email,
        code: code,
        newPassword: newPass,
      );

      if (mounted) {
        if (widget.onPasswordResetSuccess != null) {
          widget.onPasswordResetSuccess!(msg);
        } else {
          widget.onShowLogin();
        }
      }
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
      title: _codeSent ? 'Enter reset code' : 'Reset password',
      subtitle: _codeSent
          ? 'Enter the 6-digit code sent to ${_emailController.text.trim()}'
          : 'Enter your email to receive a password reset code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_success != null) ...[
            LuminaAuthSuccessBanner(message: _success!),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            LuminaAuthErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],
          if (!_codeSent) _buildEmailStep() else _buildResetStep(),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              const Text(
                'Remember your password? ',
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
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuminaAuthTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: AuthValidators.email,
            onSubmitted: (_) => _requestOtp(),
          ),
          const SizedBox(height: 20),
          LuminaAuthButton(
            label: 'Send Reset Code',
            loading: _loading,
            onPressed: _requestOtp,
          ),
        ],
      ),
    );
  }

  Widget _buildResetStep() {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuminaAuthTextField(
            controller: _otpController,
            label: '6-Digit Verification Code',
            hint: 'e.g. 123456',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            validator: AuthValidators.otpCode,
          ),
          const SizedBox(height: 14),
          LuminaAuthTextField(
            controller: _newPasswordController,
            label: 'New Password',
            hint: '8+ chars, upper + lower + number',
            icon: Icons.lock_outline_rounded,
            obscureText: true,
            validator: AuthValidators.registerPassword,
          ),
          const SizedBox(height: 14),
          LuminaAuthTextField(
            controller: _confirmPasswordController,
            label: 'Confirm New Password',
            hint: 'Re-enter your new password',
            icon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.done,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your password';
              if (v != _newPasswordController.text) return 'Passwords do not match';
              return null;
            },
            onSubmitted: (_) => _submitReset(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _loading
                    ? null
                    : () {
                        setState(() {
                          _codeSent = false;
                          _error = null;
                          _success = null;
                        });
                      },
                child: const Text(
                  'Change email',
                  style: TextStyle(
                    color: LuminaColors.darkMuted,
                    fontSize: 12.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: (_loading || _resendCooldown > 0) ? null : _requestOtp,
                child: Text(
                  _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend code',
                  style: TextStyle(
                    color: _resendCooldown > 0
                        ? LuminaColors.darkMuted
                        : LuminaColors.primaryEnd,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LuminaAuthButton(
            label: 'Reset Password',
            loading: _loading,
            onPressed: _submitReset,
          ),
        ],
      ),
    );
  }
}
