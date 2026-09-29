import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/cloud_mode/data/models/saved_generation.dart';
import '../features/cloud_mode/data/services/cloud_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/moderation_outcome_dialog.dart';

/// My Library Screen: Browses the user's remote saved cloud generations,
/// supports publishing, unpublishing, deleting, and quota inspection.
class MyLibraryScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback? onClose;

  const MyLibraryScreen({super.key, required this.isDark, this.onClose});

  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen> {
  final _cloudApi = CloudApiService.instance;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _activeFilter = 'All'; // All, Image, Video, Audio

  List<SavedGeneration> _items = [];
  int _page = 1;
  int _totalCount = 0;
  bool _hasMore = false;
  CloudUserProfile? _userProfile;

  static const List<String> _mediaFilters = ['All', 'Image', 'Video', 'Audio'];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _cloudApi.initAuth();
      final user = await _cloudApi.fetchCurrentUser();

      final res = await _cloudApi.fetchMyGenerations(
        page: 1,
        limit: 24,
        mediaType: _activeFilter != 'All' ? _activeFilter.toLowerCase() : null,
      );

      if (!mounted) return;
      setState(() {
        _userProfile = user;
        _items = res.items;
        _page = res.page;
        _totalCount = res.total;
        _hasMore = res.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load library: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final res = await _cloudApi.fetchMyGenerations(
        page: _page + 1,
        limit: 24,
        mediaType: _activeFilter != 'All' ? _activeFilter.toLowerCase() : null,
      );

      if (!mounted) return;
      setState(() {
        _items.addAll(res.items);
        _page = res.page;
        _hasMore = res.hasMore;
        _totalCount = res.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _handleFilterChange(String filter) async {
    if (_activeFilter == filter) return;
    setState(() => _activeFilter = filter);
    await _loadInitialData();
  }

  Future<void> _handlePublish(SavedGeneration item) async {
    final updated = await ModerationOutcomeDialog.showPublishFlow(
      context,
      generation: item,
      isDark: widget.isDark,
    );

    if (updated != null && mounted) {
      setState(() {
        final idx = _items.indexWhere((g) => g.id == updated.id);
        if (idx != -1) _items[idx] = updated;
      });
    }
  }

  Future<void> _handleUnpublish(SavedGeneration item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? LuminaColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unpublish from Gallery?'),
        content: const Text(
          'This will remove your creation from the public Community Gallery. It will still remain in your private library.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.isDark ? LuminaColors.darkSurface : Colors.grey.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpublish'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _cloudApi.unpublishGeneration(item.id);
    if (success && mounted) {
      setState(() {
        final idx = _items.indexWhere((g) => g.id == item.id);
        if (idx != -1) {
          _items[idx] = SavedGeneration(
            id: item.id,
            userId: item.userId,
            mediaType: item.mediaType,
            storageKey: item.storageKey,
            prompt: item.prompt,
            negativePrompt: item.negativePrompt,
            modelId: item.modelId,
            settings: item.settings,
            fileSizeBytes: item.fileSizeBytes,
            isPublic: false,
            moderationStatus: item.moderationStatus,
            likesCount: item.likesCount,
            viewsCount: item.viewsCount,
            reportsCount: item.reportsCount,
            createdAt: item.createdAt,
            publishedAt: item.publishedAt,
            url: item.url,
          );
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unpublished from Community Gallery'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDelete(SavedGeneration item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? LuminaColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Saved Generation?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action is destructive and cannot be undone.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'The media file will be permanently removed from cloud storage and your storage quota will be freed up.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Prompt: "${item.prompt}"',
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Permanently Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _cloudApi.deleteGeneration(item.id);
    if (success && mounted) {
      setState(() {
        _items.removeWhere((g) => g.id == item.id);
        _totalCount = (_totalCount > 0) ? _totalCount - 1 : 0;
      });

      // Refresh user profile for updated storage count
      final updatedUser = await _cloudApi.fetchCurrentUser();
      if (mounted && updatedUser != null) {
        setState(() => _userProfile = updatedUser);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generation deleted and storage freed.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyWebLink(SavedGeneration item) {
    Clipboard.setData(ClipboardData(text: item.webGalleryUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Web Gallery URL copied: ${item.webGalleryUrl}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? LuminaColors.darkBg : LuminaColors.lightBg;
    final cardBg = isDark ? LuminaColors.darkCard : Colors.white;
    final border = isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    final text = isDark ? LuminaColors.darkText : LuminaColors.lightText;

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: cardBg.withValues(alpha: isDark ? 0.75 : 0.85),
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LuminaColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.collections_bookmark_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Library',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: text,
                      ),
                    ),
                    Text(
                      'Your saved cloud creations & gallery publications',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
                const Spacer(),

                // Storage Quota Meter
                if (_userProfile != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_done_rounded, size: 16, color: LuminaColors.primaryEnd),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Storage: ${_userProfile!.storageUsedGB.toStringAsFixed(2)} GB / ${_userProfile!.storageQuotaGB.toStringAsFixed(0)} GB',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: text),
                            ),
                            const SizedBox(height: 3),
                            SizedBox(
                              width: 110,
                              child: LinearProgressIndicator(
                                value: (_userProfile!.storageUsedGB / _userProfile!.storageQuotaGB).clamp(0.0, 1.0),
                                minHeight: 3,
                                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  (_userProfile!.storageUsedGB / _userProfile!.storageQuotaGB) > 0.9
                                      ? Colors.redAccent
                                      : LuminaColors.primaryEnd,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Refresh Button
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh Library',
                  onPressed: _loadInitialData,
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close Library',
                    onPressed: widget.onClose,
                  ),
                ],
              ],
            ),
          ),

          // Filters Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                // Filter Pills
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _mediaFilters.map((filter) {
                      final isSelected = _activeFilter == filter;
                      return InkWell(
                        onTap: () => _handleFilterChange(filter),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark ? const Color(0xFF2E3642) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            filter,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? (isDark ? Colors.white : const Color(0xFF14181F))
                                  : muted,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Spacer(),
                Text(
                  '$_totalCount items',
                  style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          // Main Content View
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(LuminaColors.primaryEnd),
                    ),
                  )
                : _error != null
                    ? _buildErrorView()
                    : _items.isEmpty
                        ? _buildEmptyState(text, muted)
                        : _buildLibraryGrid(cardBg, border, muted, text, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color text, Color muted) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LuminaColors.primaryStart.withValues(alpha: 0.12),
                border: Border.all(color: LuminaColors.primaryStart.withValues(alpha: 0.25)),
              ),
              child: const Icon(
                Icons.bookmark_border_rounded,
                size: 44,
                color: LuminaColors.primaryEnd,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No saved generations yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: text),
            ),
            const SizedBox(height: 8),
            Text(
              'When generating in Cloud GPU mode, tap the "Save" action on any creation to add it to your library and publish to the Community Gallery.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              style: ElevatedButton.styleFrom(
                backgroundColor: LuminaColors.primaryEnd,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh Library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _loadInitialData,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryGrid(
    Color cardBg,
    Color border,
    Color muted,
    Color text,
    bool isDark,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 280).floor().clamp(1, 5);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.76,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _buildLibraryCard(item, cardBg, border, muted, text, isDark);
              },
            ),

            if (_hasMore) ...[
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? LuminaColors.darkCard : Colors.white,
                    foregroundColor: text,
                    side: BorderSide(color: border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: _loadingMore
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded, size: 18),
                  label: Text(_loadingMore ? 'Loading...' : 'Load More Generations'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLibraryCard(
    SavedGeneration item,
    Color cardBg,
    Color border,
    Color muted,
    Color text,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Media Thumbnail with Status Badges
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.mediaType == 'image')
                  Image.network(
                    item.publicUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: isDark ? Colors.black38 : Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.broken_image_rounded, size: 36, color: Colors.grey),
                      ),
                    ),
                  )
                else if (item.mediaType == 'video')
                  Container(
                    color: Colors.black87,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.movie_creation_outlined, size: 40, color: Colors.white24),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38),
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    color: isDark ? const Color(0xFF1A2130) : const Color(0xFFECEFF5),
                    child: const Center(
                      child: Icon(Icons.audiotrack_rounded, size: 36, color: LuminaColors.primaryEnd),
                    ),
                  ),

                // Top Badge: Public Status
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.isPublic
                          ? Colors.green.withValues(alpha: 0.9)
                          : item.moderationStatus == 'pending_review'
                              ? Colors.amber.withValues(alpha: 0.9)
                              : item.moderationStatus == 'rejected'
                                  ? Colors.redAccent.withValues(alpha: 0.9)
                                  : Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isPublic
                              ? Icons.public_rounded
                              : item.moderationStatus == 'pending_review'
                                  ? Icons.hourglass_empty_rounded
                                  : item.moderationStatus == 'rejected'
                                      ? Icons.block_rounded
                                      : Icons.lock_outline_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.isPublic
                              ? 'Public'
                              : item.moderationStatus == 'pending_review'
                                  ? 'In Review'
                                  : item.moderationStatus == 'rejected'
                                      ? 'Rejected'
                                      : 'Private',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top Right Badge: Media Type
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.mediaType.toUpperCase(),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Metadata & Prompt
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.modelId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: LuminaColors.primaryEnd,
                          ),
                        ),
                      ),
                      Text(
                        '${item.createdAt.month}/${item.createdAt.day}/${item.createdAt.year}',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Text(
                      item.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: text, height: 1.25),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Actions: Publish / Unpublish / Delete
                  Row(
                    children: [
                      if (item.isPublic) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _copyWebLink(item),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              side: BorderSide(color: border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.link, size: 13),
                            label: const Text('Link', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _handleUnpublish(item),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              side: BorderSide(color: border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Text('Unpublish', style: TextStyle(fontSize: 10.5)),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: item.moderationStatus == 'rejected' ? null : () => _handlePublish(item),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: LuminaColors.primaryEnd,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.public, size: 13),
                            label: Text(
                              item.moderationStatus == 'pending_review' ? 'Pending' : 'Publish',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => _handleDelete(item),
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        tooltip: 'Delete Generation',
                        color: Colors.redAccent.withValues(alpha: 0.8),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
