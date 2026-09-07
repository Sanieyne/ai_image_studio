import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Floating glass top bar: logo + workspace pill on the left;
/// credits pill, buy button, theme toggle and engine status on the right.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final String appTitle;
  final String workspaceLabel;
  final int credits;
  final bool engineOnline;
  final bool isDark;
  final VoidCallback onThemeToggle;
  final VoidCallback? onBuyCredits;
  final bool sidebarCollapsed;
  final VoidCallback? onMenuToggle;

  const TopBar({
    super.key,
    this.appTitle = 'LUMINA AI',
    this.workspaceLabel = 'Creative Studio',
    this.credits = 2450,
    required this.engineOnline,
    required this.isDark,
    required this.onThemeToggle,
    this.onBuyCredits,
    this.sidebarCollapsed = false,
    this.onMenuToggle,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final border = dark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: (dark ? LuminaColors.darkSurface : Colors.white)
                .withValues(alpha: dark ? 0.72 : 0.66),
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
          child: Row(
            children: [
              // Sidebar collapse toggle.
              IconButton(
                onPressed: onMenuToggle,
                icon: Icon(
                  sidebarCollapsed ? Icons.menu : Icons.menu_open,
                  size: 20,
                ),
                tooltip: sidebarCollapsed
                    ? 'Expand sidebar'
                    : 'Collapse sidebar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 6),
              // Logo badge + title.
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF232A35), Color(0xFF0E1116)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFF78C8FF).withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5AB4FF).withValues(alpha: 0.35),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('✦',
                      style: TextStyle(fontSize: 17, color: Color(0xFFDFF3FF))),
                ),
              ),
              const SizedBox(width: 10),
              Text(appTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                      fontSize: 14)),
              const SizedBox(width: 10),
              Container(width: 1, height: 22, color: border),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(LuminaColors.pillRadius),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    workspaceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: muted),
                  ),
                ),
              ),
              const Spacer(),
              // Engine status (compact dot + label).
              _StatusChip(online: engineOnline),
              const SizedBox(width: 10),
              // Credits pill.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(LuminaColors.pillRadius),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('✦',
                        style: TextStyle(
                            color: LuminaColors.amber, fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      '${_fmt(credits)} Credits',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Buy credits (secondary outline).
              OutlinedButton(
                onPressed: onBuyCredits,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: LuminaColors.infoBlue),
                  shape: const StadiumBorder(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text('+ Buy Credits',
                    style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              // Theme toggle.
              Tooltip(
                message: isDark ? 'Switch to light' : 'Switch to dark',
                child: InkWell(
                  onTap: onThemeToggle,
                  borderRadius:
                      BorderRadius.circular(LuminaColors.pillRadius),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(LuminaColors.pillRadius),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToggleOpt(
                            label: '☀ Light',
                            active: !isDark,
                            muted: muted),
                        _ToggleOpt(
                            label: '🌙 Dark',
                            active: isDark,
                            muted: muted),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

class _StatusChip extends StatelessWidget {
  final bool online;
  const _StatusChip({required this.online});

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle,
            size: 10, color: online ? Colors.green : Colors.red),
        const SizedBox(width: 6),
        Text(online ? 'Online' : 'Offline',
            style: TextStyle(fontSize: 12.5, color: muted)),
      ],
    );
  }
}

class _ToggleOpt extends StatelessWidget {
  final String label;
  final bool active;
  final Color muted;
  const _ToggleOpt(
      {required this.label, required this.active, required this.muted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
        gradient: active ? LuminaColors.primaryGradient : null,
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : muted)),
    );
  }
}
