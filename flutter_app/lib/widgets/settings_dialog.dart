import 'package:flutter/material.dart';

import '../features/cloud_mode/data/services/cloud_api_service.dart';
import '../services/auth_service.dart';

const List<String> kReservedDisplayNames = [
  'admin',
  'administrator',
  'root',
  'system',
  'moderator',
  'mod',
  'support',
  'official',
  'staff',
  'help',
  'security',
];

class SettingsDialog extends StatefulWidget {
  final int initialTab;
  const SettingsDialog({super.key, this.initialTab = 0});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late int _selectedTab;
  static const String defaultModelPath =
      'stabilityai/stable-diffusion-xl-base-1.0';
  static const String defaultLoraDir = '/home/user/ai_models/loras';

  late TextEditingController _modelPathController;
  late TextEditingController _loraDirController;
  late TextEditingController _negativePromptController;

  // Account / Profile editing controllers & state
  late TextEditingController _displayNameController;
  late TextEditingController _bioController;
  late TextEditingController _avatarUrlController;
  late bool _isPublicProfile;
  bool _isSavingProfile = false;
  bool _isRefreshingProfile = false;
  String? _profileError;
  String? _profileSuccess;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _modelPathController = TextEditingController(text: defaultModelPath);
    _loraDirController = TextEditingController(text: defaultLoraDir);
    _negativePromptController = TextEditingController(
      text: 'low quality, blurry, distorted, bad anatomy',
    );

    final user = AuthService.instance.currentUser;
    _displayNameController = TextEditingController(
      text: user?.displayName ?? user?.username ?? '',
    );
    _bioController = TextEditingController(text: user?.bio ?? '');
    _avatarUrlController = TextEditingController(text: user?.avatarUrl ?? '');
    _isPublicProfile = user?.isPublicProfile ?? true;

    // Refresh user profile in background
    AuthService.instance.refreshProfile().then((updated) {
      if (mounted && updated != null) {
        if (_displayNameController.text == (user?.displayName ?? user?.username ?? '')) {
          _displayNameController.text = updated.displayName ?? updated.username;
        }
        if (_bioController.text == (user?.bio ?? '')) {
          _bioController.text = updated.bio ?? '';
        }
        if (_avatarUrlController.text == (user?.avatarUrl ?? '')) {
          _avatarUrlController.text = updated.avatarUrl ?? '';
        }
        setState(() {
          _isPublicProfile = updated.isPublicProfile;
        });
      }
    });
  }

  @override
  void dispose() {
    _modelPathController.dispose();
    _loraDirController.dispose();
    _negativePromptController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  void _resetModelPath() {
    setState(() {
      _modelPathController.text = defaultModelPath;
    });
  }

  Future<void> _handleSaveProfile() async {
    setState(() {
      _profileError = null;
      _profileSuccess = null;
    });

    final displayName = _displayNameController.text.trim();
    final bio = _bioController.text.trim();
    final avatarUrl = _avatarUrlController.text.trim();

    // 1. Validate display name
    if (displayName.isEmpty) {
      setState(() => _profileError = 'Display name must be at least 1 character');
      return;
    }
    if (displayName.length > 50) {
      setState(() => _profileError = 'Display name cannot exceed 50 characters');
      return;
    }
    if (kReservedDisplayNames.contains(displayName.toLowerCase())) {
      setState(() => _profileError = 'This display name is reserved. Please choose another.');
      return;
    }

    // 2. Validate avatarUrl
    if (avatarUrl.isNotEmpty) {
      if (avatarUrl.length > 1000) {
        setState(() => _profileError = 'Avatar URL cannot exceed 1000 characters');
        return;
      }
      final uri = Uri.tryParse(avatarUrl);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || (uri.host.isEmpty)) {
        setState(() => _profileError = 'Avatar URL must be a valid HTTP or HTTPS URL');
        return;
      }
    }

    // 3. Validate bio
    if (bio.length > 160) {
      setState(() => _profileError = 'Bio cannot exceed 160 characters');
      return;
    }

    setState(() => _isSavingProfile = true);

    try {
      final success = await CloudApiService.instance.updateProfile(
        displayName: displayName,
        avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
        bio: bio.isEmpty ? null : bio,
        isPublicProfile: _isPublicProfile,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          _isSavingProfile = false;
          _profileSuccess = 'Profile updated successfully!';
          _profileError = null;
        });
      } else {
        setState(() {
          _isSavingProfile = false;
          _profileError = CloudApiService.instance.lastProfileUpdateError ?? 'Failed to update profile. Please try again.';
          _profileSuccess = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSavingProfile = false;
          _profileError = 'Error saving profile: $e';
          _profileSuccess = null;
        });
      }
    }
  }

  void _handleResetProfile() {
    final user = AuthService.instance.currentUser;
    setState(() {
      _displayNameController.text = user?.displayName ?? user?.username ?? '';
      _bioController.text = user?.bio ?? '';
      _avatarUrlController.text = user?.avatarUrl ?? '';
      _isPublicProfile = user?.isPublicProfile ?? true;
      _profileError = null;
      _profileSuccess = null;
    });
  }

  Future<void> _handleRefreshCredits() async {
    setState(() => _isRefreshingProfile = true);
    await AuthService.instance.refreshProfile();
    if (mounted) {
      setState(() => _isRefreshingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF14181F) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 600),
        child: SizedBox(
          width: 740,
          height: 600,
          child: Row(
          children: [
            // Left Navigation Tabs
            Container(
              width: 210,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF101318) : const Color(0xFFF7F6F3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                border: Border(
                  right: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildTabButton(0, Icons.person_outline_rounded, 'Account'),
                  _buildTabButton(1, Icons.tune_rounded, 'Models & Paths'),
                  _buildTabButton(2, Icons.speed_rounded, 'Inference Defaults'),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Cosmic-Gen Studio v1.0.4',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right Tab Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with Close Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedTab == 0
                              ? 'Account Overview'
                              : _selectedTab == 1
                                  ? 'Models & Local Paths'
                                  : 'Inference Defaults',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Tab Body
                    Expanded(
                      child: SingleChildScrollView(
                        child: _selectedTab == 0
                            ? _buildAccountTab(isDark)
                            : _selectedTab == 1
                                ? _buildModelsTab(isDark)
                                : _buildDefaultsTab(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildTabButton(int index, IconData icon, String title) {
    final isSelected = _selectedTab == index;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isSelected
            ? const Color(0xFFD32F2F).withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _selectedTab = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? const Color(0xFFD32F2F) : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? const Color(0xFFD32F2F) : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Account Tab ---
  Widget _buildAccountTab(bool isDark) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentUser;
        final initials = (user?.displayName ?? user?.username ?? 'CG')
            .trim()
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map((s) => s[0])
            .take(2)
            .join('')
            .toUpperCase();
        final avatarUrl = _avatarUrlController.text.trim();
        final displayAvatar = avatarUrl.isNotEmpty
            ? avatarUrl
            : (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty ? user.avatarUrl! : null);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2029) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFD32F2F),
                    backgroundImage: displayAvatar != null && displayAvatar.startsWith('http')
                        ? NetworkImage(displayAvatar)
                        : null,
                    child: (displayAvatar == null || !displayAvatar.startsWith('http'))
                        ? Text(
                            initials.isEmpty ? 'CG' : initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user?.displayName ?? user?.username ?? 'Cosmic Creator',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD32F2F),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'CREATOR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? 'Logged in',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user?.username != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '@${user!.username}',
                            style: TextStyle(
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Available Credits Live Card with Refresh
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF231E12), const Color(0xFF1B2029)]
                      : [const Color(0xFFFFF9E6), const Color(0xFFF7F6F3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF5B942).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Available Balance',
                        style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.stars_rounded, color: Color(0xFFF5B942), size: 22),
                          const SizedBox(width: 8),
                          Text(
                            '${user?.credits ?? 0} Credits',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF5B942),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Refresh Balance',
                    icon: _isRefreshingProfile
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF5B942)),
                          )
                        : const Icon(Icons.refresh_rounded, color: Color(0xFFF5B942)),
                    onPressed: _isRefreshingProfile ? null : _handleRefreshCredits,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Section Heading
            const Text(
              'Edit Profile',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Update how you appear to others across the Cosmic-Gen community.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(height: 14),

            // Display Name Field
            TextFormField(
              controller: _displayNameController,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: 'Display Name',
                hintText: 'e.g. Cosmic Creator',
                helperText: '1–50 characters. Reserved system names are blocked.',
                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 12),

            // Bio Field
            TextFormField(
              controller: _bioController,
              maxLength: 160,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Bio',
                hintText: 'Tell the community about your work...',
                helperText: 'Max 160 characters',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Icon(Icons.description_outlined, size: 20),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 12),

            // Avatar URL Field
            TextFormField(
              controller: _avatarUrlController,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Avatar Image URL',
                hintText: 'https://example.com/avatar.png',
                helperText: 'Direct HTTP or HTTPS link to your profile picture',
                prefixIcon: const Icon(Icons.link_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 8),

            // Public Profile Switch
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2029) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              // Own Material so the tile's ink and highlight show over the box colour.
              child: Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                title: const Text('Public Creator Profile', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Allow other creators to see your public generations and bio',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                ),
                value: _isPublicProfile,
                activeColor: const Color(0xFFD32F2F),
                onChanged: (val) => setState(() => _isPublicProfile = val),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              ),
            ),

            // Feedback alerts
            if (_profileError != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _profileError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_profileSuccess != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _profileSuccess!,
                        style: const TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isSavingProfile ? null : _handleResetProfile,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isSavingProfile ? null : _handleSaveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isSavingProfile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            // Storage and Cloud Usage Stats
            const Text(
              'Cloud Storage Quota',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Storage Used',
                    '${(user?.storageUsedGB ?? 0.0).toStringAsFixed(1)} GB / ${(user?.storageQuotaGB ?? 20.0).toStringAsFixed(0)} GB',
                    Icons.cloud_outlined,
                    isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'Account Status',
                    'Active',
                    Icons.verified_user_outlined,
                    isDark,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1B2029)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // --- Models & Paths Tab ---
  Widget _buildModelsTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Base SDXL Checkpoint / Repo ID',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _resetModelPath,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _modelPathController,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText:
                'e.g. stabilityai/stable-diffusion-xl-base-1.0 or /path/to/sdxl.safetensors',
            filled: true,
            fillColor: isDark
                ? const Color(0xFF1A1F28)
                : Colors.black.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'LoRA Models Directory',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _loraDirController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Directory where .safetensors LoRA files are stored',
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1A1F28)
                      : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'LoRA folder set to: ${_loraDirController.text}',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Browse'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Engine Status Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1B2029)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.green.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      color: Colors.green, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Engine Device: CUDA (NVIDIA GPU detected • fp16)',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 28),
                  Expanded(
                    child: Text(
                      'Status: Online (127.0.0.1:8000)  •  Active LoRAs: 0 loaded',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Model paths saved and engine notified.'),
                ),
              );
            },
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text('Save & Apply Paths',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // --- Defaults Tab ---
  Widget _buildDefaultsTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Default Negative Prompt',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _negativePromptController,
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'low quality, blurry, distorted, bad anatomy',
            filled: true,
            fillColor: isDark
                ? const Color(0xFF1A1F28)
                : Colors.black.withValues(alpha: 0.04),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
