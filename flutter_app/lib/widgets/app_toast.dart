import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppToastType {
  error,
  success,
  info,
}

class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(seconds: 10),
  }) {
    dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastWidget(
        title: title,
        message: message,
        type: type,
        onDismiss: () => dismiss(),
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      dismiss();
    });
  }

  static void showError(
    BuildContext context, {
    required String message,
    String? title = 'Error',
  }) {
    show(
      context,
      message: message,
      title: title,
      type: AppToastType.error,
    );
  }

  static void showSuccess(
    BuildContext context, {
    required String message,
    String? title = 'Success',
  }) {
    show(
      context,
      message: message,
      title: title,
      type: AppToastType.success,
    );
  }

  static void showInfo(
    BuildContext context, {
    required String message,
    String? title = 'Information',
  }) {
    show(
      context,
      message: message,
      title: title,
      type: AppToastType.info,
    );
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (_currentEntry != null) {
      _currentEntry?.remove();
      _currentEntry = null;
    }
  }
}

class _ToastWidget extends StatefulWidget {
  final String? title;
  final String message;
  final AppToastType type;
  final VoidCallback onDismiss;

  const _ToastWidget({
    this.title,
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.35, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    await _animController.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accentColor;
    final IconData iconData;
    final String defaultTitle;

    switch (widget.type) {
      case AppToastType.error:
        accentColor = const Color(0xFFFF5252);
        iconData = Icons.error_outline_rounded;
        defaultTitle = 'Error';
        break;
      case AppToastType.success:
        accentColor = const Color(0xFF34D17B);
        iconData = Icons.check_circle_outline_rounded;
        defaultTitle = 'Success';
        break;
      case AppToastType.info:
        accentColor = LuminaColors.infoBlue;
        iconData = Icons.info_outline_rounded;
        defaultTitle = 'Information';
        break;
    }

    final effectiveTitle = widget.title ?? defaultTitle;
    final isLongMessage = widget.message.length > 70 || widget.message.contains('\n');

    return Positioned(
      top: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 280,
                maxWidth: 380,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2029) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: accentColor,
                        width: 4.5,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          iconData,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              effectiveTitle,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.message,
                              maxLines: _expanded ? null : 2,
                              overflow: _expanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF4A5568),
                              ),
                            ),
                            if (isLongMessage) ...[
                              const SizedBox(height: 2),
                              InkWell(
                                onTap: () =>
                                    setState(() => _expanded = !_expanded),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 2, horizontal: 4),
                                  child: Text(
                                    _expanded ? 'See less' : 'See more',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        color: isDark ? Colors.white54 : Colors.black45,
                        splashRadius: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        tooltip: 'Dismiss',
                        onPressed: _handleClose,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
