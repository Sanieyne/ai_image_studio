import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/project_item.dart';
import '../theme/app_theme.dart';
import 'settings_dialog.dart';

/// Studio sidebar backed by SQLite projects: full 284px panel or a
/// 72px collapsed icon rail. Data + mutations live in the parent.
class AppSidebar extends StatefulWidget {
  final bool collapsed;
  final List<ProjectItem> projects;
  final String? activeProjectId;
  final VoidCallback? onNewProject;
  final ValueChanged<String>? onSelectProject;
  final void Function(String id, String title)? onRenameTitle;
  final ValueChanged<ProjectItem>? onTogglePin;
  final ValueChanged<ProjectItem>? onDeleteProject;
  final VoidCallback? onExpand;

  const AppSidebar({
    super.key,
    this.collapsed = false,
    this.projects = const [],
    this.activeProjectId,
    this.onNewProject,
    this.onSelectProject,
    this.onRenameTitle,
    this.onTogglePin,
    this.onDeleteProject,
    this.onExpand,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

/// Context-menu actions for a sidebar project item.
enum ProjectAction { share, rename, pin, archive, delete, moveToProject }

class _AppSidebarState extends State<AppSidebar> {
  final _search = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ProjectItem> get _pinned =>
      widget.projects.where((p) => p.isPinned).toList();
  List<ProjectItem> get _recent =>
      widget.projects.where((p) => !p.isPinned).toList();

  List<ProjectItem> _visible(List<ProjectItem> src) => _filter.isEmpty
      ? src
      : src
          .where((p) => p.title.toLowerCase().contains(_filter))
          .toList();
  void _onProjectAction(ProjectAction action, ProjectItem p) {
    switch (action) {
      case ProjectAction.rename:
        // Inline renaming is handled directly inside SidebarProjectTile.
        break;
      case ProjectAction.pin:
        widget.onTogglePin?.call(p);
      case ProjectAction.delete:
        widget.onDeleteProject?.call(p);
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${_actionLabel(action)} is coming soon.')),
        );
    }
  }

  String _actionLabel(ProjectAction action) {
    switch (action) {
      case ProjectAction.share:
        return 'Share';
      case ProjectAction.rename:
        return 'Rename';
      case ProjectAction.pin:
        return 'Pin';
      case ProjectAction.archive:
        return 'Archive';
      case ProjectAction.delete:
        return 'Delete';
      case ProjectAction.moveToProject:
        return 'Move to project';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final border = dark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    final card = dark ? LuminaColors.darkSurface : Colors.white;
    final collapsed = widget.collapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: collapsed ? 72 : 284,
      clipBehavior: Clip.hardEdge,
      margin: const EdgeInsets.fromLTRB(14, 8, 0, 14),
      decoration: BoxDecoration(
        color: card.withValues(alpha: dark ? 0.72 : 0.66),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: collapsed
          ? _rail(muted, card)
          : _fullPanel(dark, border, muted, card),
    );
  }

  // ── collapsed 72px icon rail ──────────────────────────────
  Widget _rail(Color muted, Color card) {
    final items = widget.projects;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          Tooltip(
            message: 'New Project',
            child: Material(
              color: Colors.transparent,
              child: Ink(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LuminaColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: LuminaColors.primaryGlow
                          .withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: widget.onNewProject,
                  borderRadius: BorderRadius.circular(8),
                  child: const Center(
                    child: Text('+',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.0)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          IconButton(
            onPressed: widget.onExpand,
            icon: Icon(Icons.search, size: 19, color: muted),
            tooltip: 'Search',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final p in items)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                      child: IconButton(
                        onPressed: () =>
                            widget.onSelectProject?.call(p.id),
                        icon: _thumbIcon(p, 19, muted),
                        tooltip: p.title,
                        style: IconButton.styleFrom(
                          backgroundColor: p.id ==
                                  widget.activeProjectId
                              ? LuminaColors.primaryGlow
                                  .withValues(alpha: 0.18)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Tooltip(
            message: 'Alex Dan — PRO',
            child: InkWell(
              onTap: widget.onExpand,
              borderRadius: BorderRadius.circular(16),
              child: _avatar(card, 30),
            ),
          ),
        ],
      ),
    );
  }

  /// Deterministic project glyph: folder for pinned, image otherwise.
  Widget _thumbIcon(ProjectItem p, double size, Color muted) {
    return Icon(
      p.isPinned ? Icons.folder_special_outlined : Icons.image_outlined,
      size: size,
      color: muted,
    );
  }

  // ── expanded 284px panel ──────────────────────────────────
  Widget _fullPanel(bool dark, Color border, Color muted, Color card) {
    final pinned = _visible(_pinned);
    final recent = _visible(_recent);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(LuminaColors.cardRadius),
              gradient: LuminaColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color:
                      LuminaColors.primaryGlow.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FilledButton(
              onPressed: widget.onNewProject,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                      LuminaColors.cardRadius),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('+ New Project',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (v) =>
                setState(() => _filter = v.trim().toLowerCase()),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Search Images & Videos',
              hintStyle: TextStyle(fontSize: 13, color: muted),
              prefixIcon:
                  Icon(Icons.search, size: 17, color: muted),
              filled: true,
              fillColor: dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.7),
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(LuminaColors.pillRadius),
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(LuminaColors.pillRadius),
                borderSide: BorderSide(color: border),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pinned.isNotEmpty) ...[
                    _SectionHeader('Pinned Projects', muted),
                    ...pinned.map((p) => SidebarProjectTile(
                          icon: Icons.folder_special_outlined,
                          title: p.title,
                          isPinned: p.isPinned,
                          isSelected: p.id == widget.activeProjectId,
                          onTap: () =>
                              widget.onSelectProject?.call(p.id),
                          onRename: (newTitle) {
                            widget.onRenameTitle?.call(p.id, newTitle);
                          },
                          onActionSelected: (a) => _onProjectAction(a, p),
                        )),
                    const SizedBox(height: 10),
                  ],
                  _SectionHeader('Recent Creations', muted),
                  if (recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Text(
                        'No recent creations yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted.withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    ...recent.map((p) => SidebarProjectTile(
                          icon: Icons.movie_creation_outlined,
                          title: p.title,
                          isPinned: p.isPinned,
                          isSelected: p.id == widget.activeProjectId,
                          onTap: () =>
                              widget.onSelectProject?.call(p.id),
                          onRename: (newTitle) {
                            widget.onRenameTitle?.call(p.id, newTitle);
                          },
                          onActionSelected: (a) => _onProjectAction(a, p),
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildProfile(context, dark),
        ],
      ),
    );
  }

  Widget _buildProfile(BuildContext context, bool isDark) {
    final avatarWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        const CircleAvatar(
          radius: 15,
          backgroundColor: Color(0xFFD32F2F),
          child: Text(
            'AD',
            style: TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        Positioned(
          bottom: -1,
          right: -1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF34A853),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0xFF14181F) : const Color(0xFFF3F1EC),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );

    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      // Spawns the menu upward directly above the avatar card
      offset: const Offset(0, -190),
      elevation: 12,
      color: isDark ? const Color(0xFF1E232D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      onSelected: (value) {
        if (value == 'account') {
          _openSettingsDialog(context, initialTab: 0);
        } else if (value == 'models') {
          _openSettingsDialog(context, initialTab: 1);
        } else if (value == 'preferences') {
          _openSettingsDialog(context, initialTab: 2);
        }
      },
      itemBuilder: (ctx) => [
        _buildProfileMenuItem(
          value: 'account',
          icon: Icons.person_outline_rounded,
          title: 'Account Settings',
          isDark: isDark,
        ),
        _buildProfileMenuItem(
          value: 'models',
          icon: Icons.tune_rounded,
          title: 'Models & Paths',
          isDark: isDark,
        ),
        _buildProfileMenuItem(
          value: 'preferences',
          icon: Icons.settings_outlined,
          title: 'Preferences',
          isDark: isDark,
        ),
        const PopupMenuDivider(height: 10),
        _buildProfileMenuItem(
          value: 'logout',
          icon: Icons.logout_rounded,
          title: 'Sign Out',
          isDark: isDark,
          isDestructive: true,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1F29) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            avatarWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Alex Dan',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark ? Colors.white : const Color(0xFF14181F),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'alex.dan@example.com',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.more_vert,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildProfileMenuItem({
    required String value,
    required IconData icon,
    required String title,
    required bool isDark,
    bool isDestructive = false,
  }) {
    final textColor = isDestructive
        ? const Color(0xFFFF5252)
        : (isDark ? Colors.white : const Color(0xFF14181F));
    final iconColor = isDestructive
        ? const Color(0xFFFF5252)
        : (isDark ? Colors.white60 : Colors.black54);

    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 17, color: iconColor),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 13, color: textColor)),
        ],
      ),
    );
  }

  void _openSettingsDialog(BuildContext context, {int initialTab = 0}) {
    showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(initialTab: initialTab),
    );
  }

  Widget _avatar(Color card, double size) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LuminaColors.primaryGradient,
          ),
          child: Center(
            child: Text('AD',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.35)),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF34D17B),
              border: Border.all(color: card, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final Color muted;
  const _SectionHeader(this.text, this.muted);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: muted)),
    );
  }
}

class SidebarProjectTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isPinned;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<String>? onRename;
  final Function(ProjectAction action)? onActionSelected;

  const SidebarProjectTile({
    super.key,
    required this.icon,
    required this.title,
    this.isPinned = false,
    this.isSelected = false,
    this.onTap,
    this.onRename,
    this.onActionSelected,
  });

  @override
  State<SidebarProjectTile> createState() => _SidebarProjectTileState();
}

class _SidebarProjectTileState extends State<SidebarProjectTile> {
  bool _isHovered = false;
  bool _isMenuOpen = false;
  bool _isEditing = false;
  bool _isSubmitting = false;

  late TextEditingController _editController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.title);
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEditing();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant SidebarProjectTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.title != widget.title) {
      _editController.text = widget.title;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _editController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      if (!_isSubmitting) {
        _cancelEditing();
      }
    }
  }

  void _startEditing() {
    _isSubmitting = false;
    setState(() {
      _isEditing = true;
      _isMenuOpen = false;
      _editController.text = widget.title;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _commitRename() {
    if (!_isEditing) return;
    _isSubmitting = true;

    final trimmed = _editController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.title) {
      widget.onRename?.call(trimmed);
    } else {
      _editController.text = widget.title;
    }

    setState(() {
      _isEditing = false;
      _isSubmitting = false;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editController.text = widget.title;
      _isEditing = false;
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: 38,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _isEditing
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04))
              : widget.isSelected
                  ? (isDark
                      ? LuminaColors.primaryGlow.withValues(alpha: 0.16)
                      : const Color(0xFFD32F2F).withValues(alpha: 0.10))
                  : (_isHovered || _isMenuOpen)
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05))
                      : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: _isEditing
              ? Border.all(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.5),
                  width: 1,
                )
              : widget.isSelected
                  ? Border.all(
                      color: const Color(0xFFD32F2F).withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
        ),
        child: _isEditing
            ? _buildInlineEditingRow(isDark)
            : _buildDisplayRow(isDark),
      ),
    );
  }

  // --- Inline Editing Mode ---
  Widget _buildInlineEditingRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 6),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: const Color(0xFFD32F2F)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _editController,
              focusNode: _focusNode,
              onSubmitted: (_) => _commitRename(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF14181F),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          // Tick / Checkmark button
          Listener(
            onPointerDown: (_) => _isSubmitting = true,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _commitRename,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.check,
                  size: 16,
                  color: Color(0xFFD32F2F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Normal Display Mode ---
  Widget _buildDisplayRow(bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            if (widget.isSelected)
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Icon(
              widget.icon,
              size: 18,
              color: widget.isSelected
                  ? const Color(0xFFD32F2F)
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isSelected
                      ? (isDark ? Colors.white : const Color(0xFFD32F2F))
                      : (isDark ? Colors.white : const Color(0xFF14181F)),
                ),
              ),
            ),
            if (widget.isPinned && !_isHovered && !_isMenuOpen)
              const Icon(Icons.star, size: 14, color: Color(0xFFF5B942)),
            if (_isHovered || _isMenuOpen)
              PopupMenuButton<ProjectAction>(
                tooltip: '',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 190),
                elevation: 10,
                offset: const Offset(20, 0),
                color: const Color(0xFF21252D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                onOpened: () => setState(() => _isMenuOpen = true),
                onCanceled: () => setState(() => _isMenuOpen = false),
                onSelected: (action) {
                  setState(() => _isMenuOpen = false);
                  if (action == ProjectAction.rename) {
                    _startEditing(); // Triggers inline mode directly
                  } else {
                    widget.onActionSelected?.call(action);
                  }
                },
                itemBuilder: (context) => [
                  _buildMenuItem(
                    ProjectAction.share,
                    Icons.ios_share_rounded,
                    'Share',
                  ),
                  _buildMenuItem(
                    ProjectAction.rename,
                    Icons.edit_outlined,
                    'Rename',
                  ),
                  _buildMenuItem(
                    ProjectAction.pin,
                    widget.isPinned
                        ? Icons.star_border
                        : Icons.push_pin_outlined,
                    widget.isPinned ? 'Unpin chat' : 'Pin chat',
                  ),
                  _buildMenuItem(
                    ProjectAction.archive,
                    Icons.archive_outlined,
                    'Archive',
                  ),
                  _buildMenuItem(
                    ProjectAction.delete,
                    Icons.delete_outline,
                    'Delete',
                    isDestructive: true,
                  ),
                  _buildMenuItem(
                    ProjectAction.moveToProject,
                    Icons.folder_outlined,
                    'Move to project',
                  ),
                ],
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Icon(Icons.more_horiz,
                        size: 18, color: Colors.white70),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<ProjectAction> _buildMenuItem(
    ProjectAction value,
    IconData icon,
    String title, {
    bool isDestructive = false,
  }) {
    final color = isDestructive ? const Color(0xFFFF5252) : Colors.white;
    return PopupMenuItem<ProjectAction>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
