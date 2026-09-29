import 'package:flutter/material.dart';
import '../features/cloud_mode/data/models/saved_generation.dart';
import '../features/cloud_mode/data/services/cloud_api_service.dart';
import '../theme/app_theme.dart';

/// Lightweight modal sheet/dialog to set up creator profile before publishing.
/// Allows updating displayName, bio, and toggling isPublicProfile.
class PublicProfileSetupDialog extends StatefulWidget {
  final CloudUserProfile user;
  final bool isDark;

  const PublicProfileSetupDialog({
    super.key,
    required this.user,
    required this.isDark,
  });

  static Future<bool?> show(
    BuildContext context, {
    required CloudUserProfile user,
    required bool isDark,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PublicProfileSetupDialog(
        user: user,
        isDark: isDark,
      ),
    );
  }

  @override
  State<PublicProfileSetupDialog> createState() => _PublicProfileSetupDialogState();
}

class _PublicProfileSetupDialogState extends State<PublicProfileSetupDialog> {
  late TextEditingController _displayNameController;
  late TextEditingController _bioController;
  late bool _isPublicProfile;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.user.displayName ?? widget.user.username,
    );
    _bioController = TextEditingController(text: widget.user.bio ?? '');
    _isPublicProfile = widget.user.isPublicProfile;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _displayNameController.text.trim();
    final bio = _bioController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Display name cannot be empty');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final success = await CloudApiService.instance.updateProfile(
        displayName: name,
        bio: bio,
        isPublicProfile: _isPublicProfile,
      );

      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = 'Failed to update profile. Please try again.';
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error saving profile: $e';
          _saving = false;
        });
      }
    }
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
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LuminaColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set up your public creator profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose how you appear to others on the Community Gallery',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Display Name Field
              Text(
                'Public Display Name',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _displayNameController,
                maxLength: 50,
                style: TextStyle(fontSize: 13, color: text),
                decoration: InputDecoration(
                  hintText: 'e.g. NeoCreator',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline, size: 18, color: muted),
                  filled: true,
                  fillColor: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: LuminaColors.primaryEnd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),

              // Bio Field
              Text(
                'Creator Bio (Optional)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _bioController,
                maxLength: 160,
                maxLines: 2,
                style: TextStyle(fontSize: 13, color: text),
                decoration: InputDecoration(
                  hintText: 'Tell the community about your art or prompt style...',
                  filled: true,
                  fillColor: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: LuminaColors.primaryEnd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),

              // Public Profile Visibility Toggle
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isPublicProfile ? Icons.public_rounded : Icons.public_off_rounded,
                      size: 20,
                      color: _isPublicProfile ? Colors.green : Colors.amber,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Public Profile Visibility',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: text,
                            ),
                          ),
                          Text(
                            _isPublicProfile
                                ? 'Your profile page will be accessible at /user/${widget.user.username}'
                                : 'Disabled: visitors will not be able to view your creator page',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isPublicProfile,
                      activeColor: LuminaColors.primaryEnd,
                      onChanged: (val) => setState(() => _isPublicProfile = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Actions: Save & Publish vs Skip
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(true),
                    child: Text(
                      'Publish as @${widget.user.username} for now',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LuminaColors.primaryEnd,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Save & Continue',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
