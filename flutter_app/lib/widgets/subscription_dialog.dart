import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Friendly subscription modal dialog allowing users to see their
/// current local edition (Free Tier vs Pro Member) and upgrade.
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isSubscribed = widget.isSubscribed;
  }

  Future<void> _toggleSubscription(bool subscribe) async {
    setState(() => _isLoading = true);
    try {
      await DatabaseService.instance.setSetting(
        'user_subscription_status',
        subscribe ? 'pro' : 'free',
      );
      if (mounted) {
        setState(() {
          _isSubscribed = subscribe;
          _isLoading = false;
        });
        widget.onPlanChanged?.call(subscribe);
        Navigator.of(context).pop(subscribe);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              subscribe
                  ? '🎉 Welcome to Cosmic-Gen Pro! Unlimited local generation active.'
                  : 'Switched to Free Tier.',
            ),
            backgroundColor: subscribe ? const Color(0xFF10B981) : Colors.grey.shade800,
          ),
        );
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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxWidth: 680),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.5 : 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LuminaColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
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
                          'Local Engine Membership',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Local generation is completely free & private. Upgrade for Pro acceleration.',
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

            // Plan Cards Comparison
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Free Plan Card
                  Expanded(
                    child: _buildPlanCard(
                      title: 'Free Tier',
                      price: 'Free Forever',
                      subtitle: 'Perfect for casual & local experimenting',
                      isCurrent: !_isSubscribed,
                      dark: dark,
                      border: border,
                      muted: muted,
                      features: const [
                        'Standard local GPU & CPU inference',
                        '640×480 Live Face Swap with DeepFace',
                        'Text-to-Image & Image-to-Video models',
                        'Full privacy: 100% on-device data',
                        'Pay-as-you-go Cloud GPU when needed',
                      ],
                      buttonLabel: !_isSubscribed ? 'Current Plan' : 'Downgrade to Free',
                      isActionPrimary: false,
                      onPressed: _isSubscribed ? () => _toggleSubscription(false) : null,
                    ),
                  ),
                  const SizedBox(width: 18),
                  // Pro Plan Card
                  Expanded(
                    child: _buildPlanCard(
                      title: 'Pro Member',
                      badge: 'RECOMMENDED',
                      price: '\$9.99 / month',
                      subtitle: 'For creators, streamers & power users',
                      isCurrent: _isSubscribed,
                      isHighlight: true,
                      dark: dark,
                      border: border,
                      muted: muted,
                      features: const [
                        'Unlimited high-speed local generations',
                        'HD Live DeepFace Webcam streaming',
                        '4K Super-Resolution & Real-ESRGAN',
                        '500 monthly Cloud GPU compute credits',
                        'Priority model downloads & pipeline caches',
                        'Commercial licensing & royalty-free output',
                      ],
                      buttonLabel: _isSubscribed ? 'Active (Pro Member)' : 'Upgrade to Pro',
                      isActionPrimary: true,
                      onPressed: !_isSubscribed ? () => _toggleSubscription(true) : null,
                    ),
                  ),
                ],
              ),
            ),

            // Footer Note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No credit card required for standard local processing. All offline pipelines remain fully unlocked.',
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
    required String subtitle,
    required bool isCurrent,
    bool isHighlight = false,
    required bool dark,
    required Color border,
    required Color muted,
    required List<String> features,
    required String buttonLabel,
    required bool isActionPrimary,
    VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlight
              ? LuminaColors.primaryEnd.withValues(alpha: 0.7)
              : (isCurrent ? Colors.green.withValues(alpha: 0.4) : border),
          width: isHighlight ? 1.8 : 1,
        ),
        color: isHighlight
            ? (dark ? const Color(0xFF161C26) : const Color(0xFFF3F7FF))
            : (dark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02)),
        boxShadow: isHighlight
            ? [
                BoxShadow(
                  color: LuminaColors.primaryGlow.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LuminaColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              if (isCurrent && badge == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            price,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isHighlight ? LuminaColors.primaryEnd : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: isHighlight ? LuminaColors.primaryEnd : Colors.green.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f,
                      style: TextStyle(fontSize: 12.5, color: dark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: isActionPrimary
                ? ElevatedButton(
                    onPressed: onPressed,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: isCurrent ? Colors.green : LuminaColors.primaryEnd,
                      foregroundColor: Colors.white,
                      elevation: isCurrent ? 0 : 3,
                      shadowColor: LuminaColors.primaryGlow.withValues(alpha: 0.4),
                    ),
                    child: Text(
                      buttonLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  )
                : OutlinedButton(
                    onPressed: onPressed,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: border),
                    ),
                    child: Text(
                      buttonLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: isCurrent ? muted : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
