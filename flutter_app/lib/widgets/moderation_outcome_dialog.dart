import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/cloud_mode/data/models/saved_generation.dart';
import '../features/cloud_mode/data/services/cloud_api_service.dart';
import '../theme/app_theme.dart';
import 'public_profile_setup_dialog.dart';

/// Interactive Publish Flow Orchestrator & Moderation Outcome Dialog.
/// Handles checking profile setup, checking content with moderation service,
/// and displaying Approved (200), Pending Review (202), or Rejected (400) states.
class ModerationOutcomeDialog extends StatefulWidget {
  final SavedGeneration generation;
  final bool isDark;
  final String? testModerationVerdict;

  const ModerationOutcomeDialog({
    super.key,
    required this.generation,
    required this.isDark,
    this.testModerationVerdict,
  });

  /// Launch the full publish flow with profile pre-check and moderation state handling
  static Future<SavedGeneration?> showPublishFlow(
    BuildContext context, {
    required SavedGeneration generation,
    required bool isDark,
    String? testModerationVerdict,
  }) async {
    final cloudApi = CloudApiService.instance;
    await cloudApi.initAuth();

    // 1. Profile pre-check: verify user has customized profile and isPublicProfile enabled
    final user = await cloudApi.fetchCurrentUser();
    if (user != null) {
      if (!user.isPublicProfile) {
        if (!context.mounted) return null;
        final shouldEnable = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? LuminaColors.darkCard : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.visibility_off_rounded, color: Colors.amber),
                SizedBox(width: 8),
                Text('Enable Public Profile?'),
              ],
            ),
            content: const Text(
              'Your profile is currently set to private. To publish creations to the Community Gallery, your creator profile must be publicly viewable.',
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LuminaColors.primaryEnd,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Enable & Continue'),
              ),
            ],
          ),
        );

        if (shouldEnable != true) return null;
        await cloudApi.updateProfile(isPublicProfile: true);
      } else if (!user.hasCustomProfile) {
        if (!context.mounted) return null;
        final proceed = await PublicProfileSetupDialog.show(
          context,
          user: user,
          isDark: isDark,
        );
        if (proceed != true) return null;
      }
    }

    if (!context.mounted) return null;

    return showDialog<SavedGeneration?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ModerationOutcomeDialog(
        generation: generation,
        isDark: isDark,
        testModerationVerdict: testModerationVerdict,
      ),
    );
  }

  @override
  State<ModerationOutcomeDialog> createState() => _ModerationOutcomeDialogState();
}

class _ModerationOutcomeDialogState extends State<ModerationOutcomeDialog> {
  bool _isLoading = true;
  PublishResult? _result;
  bool _copiedLink = false;

  @override
  void initState() {
    super.initState();
    _startPublish();
  }

  Future<void> _startPublish() async {
    setState(() {
      _isLoading = true;
      _result = null;
    });

    final res = await CloudApiService.instance.publishGeneration(
      widget.generation.id,
      testModerationVerdict: widget.testModerationVerdict,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _result = res;
      });
    }
  }

  void _copyWebLink(String url) {
    Clipboard.setData(ClipboardData(text: url));
    setState(() => _copiedLink = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedLink = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? LuminaColors.darkCard : Colors.white;
    final border = isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    final text = isDark ? LuminaColors.darkText : LuminaColors.lightText;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? _buildLoadingState(text, muted)
              : _buildOutcomeContent(context, text, muted, border, isDark),
        ),
      ),
    );
  }

  Widget _buildLoadingState(Color text, Color muted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        const SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(LuminaColors.primaryEnd),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Checking content...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Automated safety and community guidelines screening in progress',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildOutcomeContent(
    BuildContext context,
    Color text,
    Color muted,
    Color border,
    bool isDark,
  ) {
    final res = _result!;
    final gen = res.generation ?? widget.generation;
    final webUrl = gen.webGalleryUrl;

    if (res.isApproved) {
      // 200 APPROVED
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.15),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Published to Community Gallery 🎉',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your creation has been verified and is now live for creators around the world to browse, like, and remix.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
          ),
          const SizedBox(height: 18),

          // Web gallery link box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, size: 16, color: LuminaColors.primaryEnd),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    webUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: text, fontFamily: 'monospace'),
                  ),
                ),
                TextButton(
                  onPressed: () => _copyWebLink(webUrl),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _copiedLink ? 'Copied ✓' : 'Copy',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _copiedLink ? Colors.green : LuminaColors.primaryEnd,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(gen),
                child: const Text('Done'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(gen);
                  // Copy link as quick action
                  Clipboard.setData(ClipboardData(text: webUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gallery URL copied: $webUrl'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: LuminaColors.primaryEnd,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: const Text(
                  'View on Gallery',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (res.isPendingReview) {
      // 202 PENDING REVIEW
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.amber.withValues(alpha: 0.15),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: Colors.amber,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Under Review',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your post is under review and will appear in the gallery once approved. This usually takes a few minutes — we'll notify you.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No action required. Your creation remains safely stored in your private library.',
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(gen),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? LuminaColors.darkSurface : Colors.grey.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Understood'),
            ),
          ),
        ],
      );
    }

    // 400 REJECTED / OTHER ERROR
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.redAccent.withValues(alpha: 0.15),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
          ),
          child: const Icon(
            Icons.block_flipped,
            color: Colors.redAccent,
            size: 40,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          res.isRejected ? 'Cannot Be Published' : 'Publishing Error',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          res.message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
          ),
          child: Text(
            res.isRejected
                ? 'Community guidelines prohibit adult, violent, or sensitive imagery from public exhibition.'
                : 'Please check your connection and try again.',
            style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(null),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? LuminaColors.darkSurface : Colors.grey.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }
}
