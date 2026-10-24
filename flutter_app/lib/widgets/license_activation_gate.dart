import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Full-screen or modal license gate that encrypts and guards access to the software.
/// Only authenticated users with a valid one-time lifetime license key ($35) can proceed.
class LicenseActivationGate extends StatefulWidget {
  final Widget child;
  final bool isDark;

  const LicenseActivationGate({
    super.key,
    required this.child,
    required this.isDark,
  });

  @override
  State<LicenseActivationGate> createState() => _LicenseActivationGateState();
}

class _LicenseActivationGateState extends State<LicenseActivationGate> {
  final _keyController = TextEditingController();
  bool _isChecking = true;
  bool _isUnlocked = false;
  bool _isVerifying = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _checkStoredLicense();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _checkStoredLicense() async {
    final user = AuthService.instance.currentUser;
    final dbStatus = await DatabaseService.instance.getSetting('user_subscription_status');
    
    if ((user != null && user.isSubscribed) || (dbStatus == 'pro' || dbStatus == 'lifetime')) {
      if (mounted) {
        setState(() {
          _isUnlocked = true;
          _isChecking = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _openBuyLicenseUrl() async {
    final user = AuthService.instance.currentUser;
    final email = user?.email ?? '';
    final userId = user?.id ?? '';
    final uri = Uri.parse('https://cosmicgen.gumroad.com/l/cosmicgen').replace(
      queryParameters: {
        'wanted': 'true',
        if (email.isNotEmpty) 'email': email,
        if (userId.isNotEmpty) 'user_id': userId,
      },
    );
    final url = uri.toString();
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('[LicenseActivationGate] Failed to open URL: $e');
    }
  }

  Future<void> _activateLicense() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Please enter your software license key.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
      _success = null;
    });

    try {
      final client = ApiClient();
      final res = await client.post(
        '/payments/verify-license',
        jsonBody: {
          'licenseKey': key,
          'productId': 'P_uhVlz366OzcZdNsU5awg==',
        },
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        await DatabaseService.instance.setSetting('user_subscription_status', 'lifetime');
        await AuthService.instance.getCurrentUser(forceRefresh: true);

        if (mounted) {
          setState(() {
            _isVerifying = false;
            _success = 'License Activated! Unlocking Cosmic-Gen AI Studio...';
          });

          await Future.delayed(const Duration(milliseconds: 900));
          if (mounted) {
            setState(() => _isUnlocked = true);
          }
        }
      } else {
        final msg = data['message']?.toString() ?? 'Invalid license key or already claimed.';
        if (mounted) {
          setState(() {
            _isVerifying = false;
            _error = msg;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _error = 'Verification failed: ${e.toString().replaceAll("Exception: ", "")}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: LuminaColors.darkBg,
        body: Center(
          child: CircularProgressIndicator(color: LuminaColors.primaryEnd),
        ),
      );
    }

    if (_isUnlocked) {
      return widget.child;
    }

    final dark = widget.isDark;
    return Scaffold(
      backgroundColor: dark ? LuminaColors.darkBg : const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF131722) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: dark ? const Color(0xFF262E40) : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
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
                          color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.key_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Software Activation',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cosmic-Gen AI Studio is encrypted commercial software. Enter your one-time purchase license key (\$35 USD) to unlock unlimited local generation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _keyController,
                    style: TextStyle(
                      color: dark ? Colors.white : Colors.black,
                      fontFamily: 'monospace',
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      labelText: 'License Key',
                      hintText: 'XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX',
                      hintStyle: TextStyle(
                        color: dark ? Colors.white24 : Colors.black26,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: dark ? const Color(0xFF1E2433) : const Color(0xFFF1F5F9),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _success!,
                              style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _activateLicense,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: LuminaColors.primaryEnd,
                        foregroundColor: Colors.white,
                        elevation: 3,
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Unlock Software',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: dark ? Colors.white12 : Colors.black12)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Don\'t have a license key?',
                          style: TextStyle(
                            fontSize: 12,
                            color: dark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: dark ? Colors.white12 : Colors.black12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openBuyLicenseUrl,
                      icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                      label: const Text('Buy Lifetime License (\$35 USD)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        foregroundColor: const Color(0xFF10B981),
                      ),
                    ),
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
