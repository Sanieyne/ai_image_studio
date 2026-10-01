import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Client-side validators mirroring the backend Joi schemas exactly
/// (`validation.middleware.js` `registerSchema`/`loginSchema`), so users get
/// immediate feedback instead of waiting for server 400s.
///
/// Server-side validation errors are still surfaced (see [AuthException]),
/// these only pre-check the same rules locally.
class AuthValidators {
  static final RegExp _emailPattern = RegExp(r'^\S+@\S+\.\S+$');
  static final RegExp _alphanumPattern = RegExp(r'^[a-zA-Z0-9]+$');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasDigit = RegExp(r'\d');

  static String? username(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Username is required';
    if (text.length < 3) return 'Username must be at least 3 characters';
    if (text.length > 30) return 'Username cannot exceed 30 characters';
    if (!_alphanumPattern.hasMatch(text)) {
      return 'Username must only contain alphanumeric characters';
    }
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(text)) {
      return 'Please provide a valid email address';
    }
    return null;
  }

  /// Registration password rule: min 8 chars + upper + lower + digit.
  static String? registerPassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Password is required';
    if (text.length < 8) return 'Password must be at least 8 characters long';
    if (!_hasLowercase.hasMatch(text) ||
        !_hasUppercase.hasMatch(text) ||
        !_hasDigit.hasMatch(text)) {
      return 'Password must contain at least one uppercase letter, '
          'one lowercase letter, and one number';
    }
    return null;
  }

  /// Login password rule: backend only requires presence.
  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }
}

/// Lumina-styled text field for the auth screens.
class LuminaAuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?) validator;
  final void Function(String)? onSubmitted;

  const LuminaAuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validator,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  State<LuminaAuthTextField> createState() => _LuminaAuthTextFieldState();
}

class _LuminaAuthTextFieldState extends State<LuminaAuthTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final effectiveObscure = widget.obscureText && _obscured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: LuminaColors.darkMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          obscureText: effectiveObscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autocorrect: false,
          enableSuggestions: !widget.obscureText,
          validator: widget.validator,
          onFieldSubmitted: widget.onSubmitted,
          style: const TextStyle(color: LuminaColors.darkText, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(
              color: LuminaColors.darkMuted,
              fontSize: 13.5,
            ),
            prefixIcon: Icon(
              widget.icon,
              size: 19,
              color: LuminaColors.darkMuted,
            ),
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                      color: LuminaColors.darkMuted,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
            filled: true,
            fillColor: LuminaColors.darkSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: LuminaColors.darkBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: LuminaColors.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: LuminaColors.primaryEnd,
                width: 1.4,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: LuminaColors.primaryEnd),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: LuminaColors.primaryEnd,
                width: 1.4,
              ),
            ),
            errorStyle: const TextStyle(
              color: LuminaColors.primaryEnd,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Lumina primary action button (red gradient) with loading state.
class LuminaAuthButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const LuminaAuthButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LuminaColors.primaryGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: loading ? null : onPressed,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline server/network error banner for auth screens.
class LuminaAuthErrorBanner extends StatelessWidget {
  final String message;

  const LuminaAuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LuminaColors.primaryStart.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LuminaColors.primaryEnd.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: LuminaColors.primaryEnd,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: LuminaColors.darkText,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared auth screen scaffold: obsidian background + centered card.
class LuminaAuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const LuminaAuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminaColors.darkBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LuminaColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: LuminaColors.primaryGlow.withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Lumina AI',
                  style: TextStyle(
                    color: LuminaColors.darkText,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Creative Studio',
                  style: TextStyle(
                    color: LuminaColors.darkMuted,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: LuminaColors.darkCard,
                    borderRadius: BorderRadius.circular(
                      LuminaColors.cardRadius,
                    ),
                    border: Border.all(color: LuminaColors.darkBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: LuminaColors.darkText,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: LuminaColors.darkMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      child,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
