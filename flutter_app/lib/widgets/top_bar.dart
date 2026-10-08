import 'package:flutter/material.dart';

import '../services/engine_process_manager.dart';

import '../features/cloud_mode/data/models/cloud_model.dart';
import '../theme/app_theme.dart';

/// Floating glass top bar: logo + workspace pill + Local/Cloud switcher on the left;
/// credits pill, buy button, theme toggle and engine/cloud status on the right.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final String appTitle;
  final String workspaceLabel;
  final int credits;
  final bool engineOnline;
  final bool cloudOnline;
  final bool isDark;
  final VoidCallback onThemeToggle;
  final VoidCallback? onBuyCredits;
  final bool sidebarCollapsed;
  final VoidCallback? onMenuToggle;
  final StudioExecutionMode executionMode;
  final ValueChanged<StudioExecutionMode>? onExecutionModeChanged;

  const TopBar({
    super.key,
    this.appTitle = 'COSMIC-GEN AI',
    this.workspaceLabel = 'Creative Studio',
    this.credits = 2450,
    required this.engineOnline,
    this.cloudOnline = false,
    this.deviceName,
    required this.isDark,
    required this.onThemeToggle,
    this.onBuyCredits,
    this.sidebarCollapsed = false,
    this.onMenuToggle,
    this.executionMode = StudioExecutionMode.local,
    this.onExecutionModeChanged,
  });

  final String? deviceName;

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
              // Sidebar collapse toggle (only relevant in local studio mode).
              if (executionMode == StudioExecutionMode.local) ...[
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
              ],
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

              // Local vs Cloud Mode Switcher
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
                  border: Border.all(color: border),
                  color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModePill(
                      icon: Icons.memory_rounded,
                      label: 'Local Engine',
                      selected: executionMode == StudioExecutionMode.local,
                      muted: muted,
                      onTap: () => onExecutionModeChanged?.call(StudioExecutionMode.local),
                    ),
                    _ModePill(
                      icon: Icons.cloud_outlined,
                      label: 'Cloud GPU',
                      selected: executionMode == StudioExecutionMode.cloud,
                      muted: muted,
                      onTap: () => onExecutionModeChanged?.call(StudioExecutionMode.cloud),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),
              if (executionMode == StudioExecutionMode.local)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted),
                    ),
                  ),
                ),
              const Spacer(),
              // Engine or Cloud status chip
              if (executionMode == StudioExecutionMode.local)
                _StatusChip(online: engineOnline, deviceName: deviceName)
              else
                _CloudStatusChip(online: cloudOnline),
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

class _ModePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color muted;
  final VoidCallback onTap;

  const _ModePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
          gradient: selected ? LuminaColors.primaryGradient : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: LuminaColors.primaryGlow.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : muted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.white : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool online;
  final String? deviceName;
  const _StatusChip({required this.online, this.deviceName});

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    return ValueListenableBuilder<EngineStatus>(
      valueListenable: EngineProcessManager.instance.status,
      builder: (context, engine, _) {
        final starting = !online && engine.phase == EngineRunPhase.starting;
        final failed = !online && engine.phase == EngineRunPhase.failed;
        final label = online
            ? (deviceName != null && deviceName!.isNotEmpty ? deviceName! : 'Online')
            : (starting || failed ? engine.label : 'Offline');
        final color = online ? Colors.green : (starting ? Colors.amber : Colors.red);
        final chip = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (starting)
              SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: color))
            else
              Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                label,
                key: const ValueKey('engine_status_label'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: muted),
              ),
            ),
          ],
        );
        if (online) return chip;
        // Not answering: details and the engine log are one click away.
        return PopupMenuButton<String>(
          key: const ValueKey('engine_status_menu'),
          tooltip: failed ? engine.label : 'Local engine status',
          onSelected: (value) async {
            if (value == 'log') {
              final opened = await EngineProcessManager.instance.openLog();
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No engine log yet: the engine has not been started on this computer.')),
                );
              }
            } else if (value == 'restart') {
              EngineProcessManager.instance.stopEngine();
              await EngineProcessManager.instance.ensureEngineRunning();
            }
          },
          itemBuilder: (_) => [
            if (failed)
              PopupMenuItem<String>(enabled: false, child: Text(engine.label, style: const TextStyle(fontSize: 12))),
            const PopupMenuItem<String>(value: 'log', child: Text('Open engine log')),
            const PopupMenuItem<String>(value: 'restart', child: Text('Restart engine')),
          ],
          child: chip,
        );
      },
    );
  }
}

class _CloudStatusChip extends StatelessWidget {
  final bool online;
  const _CloudStatusChip({required this.online});

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    // Reachability of the cloud backend only; it says nothing about a rented GPU.
    final label = online ? 'Cloud: Connected' : 'Cloud: Offline';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_done_rounded,
            size: 14, color: online ? Colors.cyanAccent.shade700 : Colors.amber),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: online ? Colors.cyanAccent.shade700 : muted)),
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
