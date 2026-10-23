import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Cosmic-Gen AI 3-Tier Subscription & Gumroad Payment Dialog
/// Supports Starter ($4.99), Pro ($9.99), and VIP ($19.99) with seamless
/// browser checkout, real-time activation webhook polling, and license key verification.
class SubscriptionPlanDialog extends StatefulWidget {
  final bool isSubscribed;
  final String currentPlan;
  final ValueChanged<bool>? onPlanChanged;

  const SubscriptionPlanDialog({
    super.key,
    required this.isSubscribed,
    required this.currentPlan,
    this.onPlanChanged,
  });

  static Future<bool?> show(
    BuildContext context, {
    required bool isSubscribed,
    String currentPlan = 'Free Tier',
    ValueChanged<bool>? onPlanChanged,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SubscriptionPlanDialog(
        isSubscribed: isSubscribed,
        currentPlan: currentPlan,
        onPlanChanged: onPlanChanged,
      ),
    );
  }

  @override
  State<SubscriptionPlanDialog> createState() => _SubscriptionPlanDialogState();
}

class _SubscriptionPlanDialogState extends State<SubscriptionPlanDialog> {
  late bool _isSubscribed;
  late String _currentPlan;
  bool _isLoading = false;
  bool _isAwaitingWebhook = false;
  String? _pendingCheckoutTier;
  Timer? _pollingTimer;

  final TextEditingController _licenseKeyController = TextEditingController();
  bool _isVerifyingLicense = false;
  String? _licenseError;
  String? _licenseSuccess;

  // Gumroad Product Permalinks (configured for Cosmic-Gen store)
  static const String starterPermalink = 'starter';
  static const String proPermalink = 'pro';
  static const String vipPermalink = 'vip';

  @override
  void initState() {
    super.initState();
    _isSubscribed = widget.isSubscribed;
    _currentPlan = widget.currentPlan;
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _licenseKeyController.dispose();
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
      debugPrint('[SubscriptionDialog] Failed to open URL ($url): $e');
    }
  }

  Future<void> _startCheckout(String tier, String permalink) async {
    final user = AuthService.instance.currentUser;
    final email = user?.email ?? '';
    final userId = user?.id ?? '';

    // Build Gumroad checkout URL prefilled with email and user_id for webhook attribution
    final uri = Uri(
      scheme: 'https',
      host: 'gumroad.com',
      path: '/l/$permalink',
      queryParameters: {
        if (email.isNotEmpty) 'email': email,
        if (userId.isNotEmpty) 'user_id': userId,
      },
    );

    setState(() {
      _isAwaitingWebhook = true;
      _pendingCheckoutTier = tier;
      _licenseError = null;
      _licenseSuccess = null;
    });

    await _openBrowserUrl(uri.toString());

    // Start background auto-poller (checks for webhook delivery every 3 seconds for 2.5 minutes)
    _pollingTimer?.cancel();
    int ticks = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      ticks++;
      if (ticks > 50) {
        timer.cancel();
        if (mounted) setState(() => _isAwaitingWebhook = false);
        return;
      }

      final updatedUser = await AuthService.instance.getCurrentUser(forceRefresh: true);
      if (updatedUser != null && updatedUser.isSubscribed) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isSubscribed = true;
            _currentPlan = updatedUser.subscriptionPlan;
            _isAwaitingWebhook = false;
          });
          await DatabaseService.instance.setSetting('user_subscription_status', updatedUser.subscriptionTier);
          widget.onPlanChanged?.call(true);
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Payment confirmed! Your ${_currentPlan.toUpperCase()} membership is active!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    });
  }

  Future<void> _verifyLicenseKey() async {
    final key = _licenseKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _licenseError = 'Please enter your Gumroad license key.');
      return;
    }

    setState(() {
      _isVerifyingLicense = true;
      _licenseError = null;
      _licenseSuccess = null;
    });

    try {
      final client = ApiClient();
      final response = await client.post(
        '/payments/verify-license',
        jsonBody: {'licenseKey': key},
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        final planData = data['data']?['plan'] as Map<String, dynamic>?;
        final planName = planData?['name']?.toString() ?? 'Pro';
        final tier = data['data']?['subscriptionTier']?.toString() ?? 'pro';

        await AuthService.instance.getCurrentUser(forceRefresh: true);
        await DatabaseService.instance.setSetting('user_subscription_status', tier);

        if (mounted) {
          setState(() {
            _isSubscribed = true;
            _currentPlan = planName;
            _isVerifyingLicense = false;
            _licenseSuccess = 'License verified! You are now on the $planName plan.';
          });

          widget.onPlanChanged?.call(true);
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) Navigator.of(context).pop(true);
          });
        }
      } else {
        final msg = data['message']?.toString() ?? 'Invalid license key or already claimed.';
        if (mounted) {
          setState(() {
            _isVerifyingLicense = false;
            _licenseError = msg;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifyingLicense = false;
          _licenseError = 'Verification failed: ${e.toString().replaceAll("Exception: ", "")}';
        });
      }
    }
  }

  Future<void> _handleLocalQuickToggle(String tier) async {
    setState(() => _isLoading = true);
    try {
      await DatabaseService.instance.setSetting('user_subscription_status', tier);
      if (mounted) {
        setState(() {
          _isSubscribed = tier != 'free';
          _currentPlan = tier.toUpperCase();
          _isLoading = false;
        });
        widget.onPlanChanged?.call(_isSubscribed);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final bg = dark ? LuminaColors.darkCard : LuminaColors.lightCard;
    final border = dark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    final user = AuthService.instance.currentUser;

    final normPlan = _currentPlan.toLowerCase();
    final isCurrentStarter = _isSubscribed && normPlan.contains('starter');
    final isCurrentPro = _isSubscribed && normPlan.contains('pro');
    final isCurrentVip = _isSubscribed && normPlan.contains('vip');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        width: 880,
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 820),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.6 : 0.2),
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LuminaColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cosmic-Gen AI Membership',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user != null
                              ? 'Signed in as ${user.email}. Choose your tier to unlock full generation & DeepFace.'
                              : 'Unlock unlimited inference, high-resolution models, and DeepFace webcam streaming.',
                          style: TextStyle(fontSize: 12.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, size: 20, color: muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Real-time awaiting webhook notification banner
            if (_isAwaitingWebhook)
              Container(
                margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: LuminaColors.primaryStart.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LuminaColors.primaryEnd.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: LuminaColors.primaryEnd),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Gumroad checkout opened in your browser for ${_pendingCheckoutTier?.toUpperCase()}! Complete payment to auto-unlock.',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isAwaitingWebhook = false),
                      child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),

            // Plan Cards Comparison
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Starter Plan ($4.99)
                        Expanded(
                          child: _buildPlanCard(
                            title: 'Starter',
                            price: '\$4.99',
                            period: '/ month',
                            subtitle: 'Essential local generation & webcam swap',
                            isCurrent: isCurrentStarter,
                            accentColor: const Color(0xFF3B82F6),
                            dark: dark,
                            border: border,
                            muted: muted,
                            features: const [
                              'Unlimited local image generation',
                              'Standard DeepFace webcam swap (640×480)',
                              '50 Cloud GPU compute credits / mo',
                              '100% offline data privacy',
                              'Standard queue priority',
                            ],
                            buttonLabel: isCurrentStarter ? 'Active Plan' : 'Subscribe (\$4.99)',
                            onSubscribe: () => _startCheckout('starter', starterPermalink),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Pro Plan ($9.99) - Highlighted
                        Expanded(
                          child: _buildPlanCard(
                            title: 'Pro Member',
                            badge: 'MOST POPULAR',
                            price: '\$9.99',
                            period: '/ month',
                            subtitle: 'HD quality, upscaling & fast video',
                            isCurrent: isCurrentPro,
                            isHighlight: true,
                            accentColor: const Color(0xFF10B981),
                            dark: dark,
                            border: border,
                            muted: muted,
                            features: const [
                              'Unlimited high-speed local generations',
                              '1080p HD Live DeepFace Webcam stream',
                              '4K Super-Resolution & Real-ESRGAN',
                              '250 Cloud GPU compute credits / mo',
                              'Turbo video (Wan 2.1 & MiniMax)',
                              'Special PRO Member badge in UI',
                            ],
                            buttonLabel: isCurrentPro ? 'Active Plan' : 'Subscribe (\$9.99)',
                            onSubscribe: () => _startCheckout('pro', proPermalink),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // VIP Plan ($19.99) - Ultimate
                        Expanded(
                          child: _buildPlanCard(
                            title: 'VIP Elite',
                            badge: 'EXCLUSIVE VIP',
                            price: '\$19.99',
                            period: '/ month',
                            subtitle: 'Dedicated GPU compute & full rights',
                            isCurrent: isCurrentVip,
                            isVipHighlight: true,
                            accentColor: const Color(0xFF8B5CF6),
                            dark: dark,
                            border: border,
                            muted: muted,
                            features: const [
                              'All Pro features & pipelines included',
                              'Ultra HD 4K Live DeepFace Webcam stream',
                              'Priority Dedicated Cloud GPU instances',
                              '1,000 Cloud GPU compute credits / mo',
                              'Commercial licensing & royalty-free',
                              'Radiant VIP Member Badge in UI',
                            ],
                            buttonLabel: isCurrentVip ? 'Active Plan' : 'Subscribe (\$19.99)',
                            onSubscribe: () => _startCheckout('vip', vipPermalink),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // License Key Fallback Entry Form
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.key_rounded, size: 16, color: muted),
                              const SizedBox(width: 8),
                              const Text(
                                'Have a Gumroad License Key?',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(Enter key to activate instantly)',
                                style: TextStyle(fontSize: 11.5, color: muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: _licenseKeyController,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'e.g. 12345678-ABCD-EFGH-IJKL-9876543210AB',
                                      hintStyle: TextStyle(fontSize: 12, color: muted),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: border),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: border),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _isVerifyingLicense ? null : _verifyLicenseKey,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LuminaColors.primaryEnd,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: _isVerifyingLicense
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Activate License', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          if (_licenseError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _licenseError!,
                              style: const TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.w600),
                            ),
                          ],
                          if (_licenseSuccess != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _licenseSuccess!,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer Note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Secure checkout powered by Gumroad. Cancel subscription anytime with 1 click.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    String? badge,
    required String price,
    required String period,
    required String subtitle,
    required bool isCurrent,
    bool isHighlight = false,
    bool isVipHighlight = false,
    required Color accentColor,
    required bool dark,
    required Color border,
    required Color muted,
    required List<String> features,
    required String buttonLabel,
    required VoidCallback onSubscribe,
  }) {
    Color cardBorder = border;
    List<BoxShadow>? shadows;
    LinearGradient? bgGradient;

    if (isVipHighlight) {
      cardBorder = const Color(0xFFD946EF);
      shadows = [
        BoxShadow(
          color: const Color(0xFFD946EF).withValues(alpha: 0.25),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ];
    } else if (isHighlight) {
      cardBorder = const Color(0xFF10B981);
      shadows = [
        BoxShadow(
          color: const Color(0xFF10B981).withValues(alpha: 0.2),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
    } else if (isCurrent) {
      cardBorder = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cardBorder,
          width: (isHighlight || isVipHighlight) ? 1.8 : 1,
        ),
        color: isVipHighlight
            ? (dark ? const Color(0xFF1C1329) : const Color(0xFFF9F5FF))
            : isHighlight
                ? (dark ? const Color(0xFF13231E) : const Color(0xFFF2FBF7))
                : (dark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02)),
        boxShadow: shadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: isVipHighlight
                        ? const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF59E0B)])
                        : const LinearGradient(colors: [Color(0xFF059669), Color(0xFF10B981)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              if (isCurrent && badge == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.green,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isVipHighlight
                      ? const Color(0xFFD946EF)
                      : isHighlight
                          ? const Color(0xFF10B981)
                          : null,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                period,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: isVipHighlight
                        ? const Color(0xFFD946EF)
                        : isHighlight
                            ? const Color(0xFF10B981)
                            : accentColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      f,
                      style: TextStyle(fontSize: 11.5, color: dark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isCurrent ? null : onSubscribe,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: isCurrent
                    ? Colors.grey.shade700
                    : isVipHighlight
                        ? const Color(0xFF8B5CF6)
                        : isHighlight
                            ? const Color(0xFF10B981)
                            : accentColor,
                foregroundColor: Colors.white,
                elevation: isCurrent ? 0 : 2,
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
