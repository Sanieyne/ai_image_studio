import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Clean modal dialog allowing users to top up Cloud GPU compute credits
/// via Gumroad ($1.00 USD = 100 credits, $5 minimum).
class CreditTopUpDialog extends StatefulWidget {
  final bool isDark;

  const CreditTopUpDialog({super.key, required this.isDark});

  static Future<void> show(BuildContext context, {required bool isDark}) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => CreditTopUpDialog(isDark: isDark),
    );
  }

  @override
  State<CreditTopUpDialog> createState() => _CreditTopUpDialogState();
}

class _CreditTopUpDialogState extends State<CreditTopUpDialog> {
  Timer? _pollingTimer;
  bool _isAwaitingPayment = false;
  int _lastKnownCredits = 0;

  @override
  void initState() {
    super.initState();
    _lastKnownCredits = AuthService.instance.currentUser?.credits ?? 0;
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _openBrowserUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('[CreditTopUp] Failed to open URL: $e');
    }
  }

  void _launchCheckout(int amountUsd) async {
    final user = AuthService.instance.currentUser;
    final email = user?.email ?? '';
    final userId = user?.id ?? '';

    // Pass email and user_id to Gumroad URL query so backend webhooks map automatically
    final uri = Uri.parse('https://cosmicgen.gumroad.com/l/cosmicgen-credits').replace(
      queryParameters: {
        'wanted': 'true',
        if (amountUsd > 0) 'price': amountUsd.toString(),
        if (email.isNotEmpty) 'email': email,
        if (userId.isNotEmpty) 'user_id': userId,
      },
    );

    setState(() => _isAwaitingPayment = true);
    await _openBrowserUrl(uri.toString());

    // Start background auto-poll (checks every 3 seconds for webhook credit deposit)
    _pollingTimer?.cancel();
    int ticks = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      ticks++;
      if (ticks > 50) {
        timer.cancel();
        if (mounted) setState(() => _isAwaitingPayment = false);
        return;
      }

      final updatedUser = await AuthService.instance.getCurrentUser(forceRefresh: true);
      if (updatedUser != null && updatedUser.credits > _lastKnownCredits) {
        timer.cancel();
        if (mounted) {
          final added = updatedUser.credits - _lastKnownCredits;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Credit top-up confirmed! Added +$added Cloud Credits.'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final user = AuthService.instance.currentUser;
    final currentCredits = user?.credits ?? 0;

    return Dialog(
      backgroundColor: dark ? const Color(0xFF131722) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Top Up Cloud Credits',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: dark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Current Balance: $currentCredits Credits (\$1.00 USD = 100 Credits)',
                          style: TextStyle(
                            fontSize: 12,
                            color: dark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: dark ? Colors.white54 : Colors.black45),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Select a credit top-up pack or choose custom on Gumroad:',
                style: TextStyle(
                  fontSize: 13,
                  color: dark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 14),

              // Packages
              _buildPackOption(
                credits: 500,
                priceUsd: 5,
                label: 'Starter Pack',
                dark: dark,
                onTap: () => _launchCheckout(5),
              ),
              const SizedBox(height: 10),
              _buildPackOption(
                credits: 1000,
                priceUsd: 10,
                label: 'Standard Pack',
                isPopular: true,
                dark: dark,
                onTap: () => _launchCheckout(10),
              ),
              const SizedBox(height: 10),
              _buildPackOption(
                credits: 2500,
                priceUsd: 25,
                label: 'Pro Pack',
                dark: dark,
                onTap: () => _launchCheckout(25),
              ),
              const SizedBox(height: 10),
              _buildPackOption(
                credits: 5000,
                priceUsd: 50,
                label: 'Studio Pack',
                dark: dark,
                onTap: () => _launchCheckout(50),
              ),
              const SizedBox(height: 16),

              // Custom amount link
              OutlinedButton.icon(
                onPressed: () => _launchCheckout(0),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Enter Custom Amount (\$5+ on Gumroad)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
              ),

              if (_isAwaitingPayment) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Checkout opened in browser. Waiting for payment confirmation...',
                          style: TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackOption({
    required int credits,
    required int priceUsd,
    required String label,
    bool isPopular = false,
    required bool dark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: dark
              ? (isPopular ? const Color(0xFF1E293B) : const Color(0xFF1A1F2E))
              : (isPopular ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPopular
                ? const Color(0xFFF59E0B)
                : (dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isPopular ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (isPopular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'POPULAR',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '+$credits Credits',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: isPopular ? const Color(0xFFF59E0B) : LuminaColors.primaryEnd,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                '\$$priceUsd USD',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
