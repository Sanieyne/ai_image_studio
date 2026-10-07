import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';

/// The user's active cloud GPUs, with status, cost and a Stop button.
/// Instances keep running (and billing) after the provisioning screen is left,
/// so this list is always shown on the Cloud screen while any exist.
class ActiveInstancesPanel extends StatelessWidget {
  final List<Map<String, dynamic>> instances;
  final Set<String> stoppingIds;
  final bool isDark;

  /// Called after the user confirms the stop.
  final Future<void> Function(Map<String, dynamic> instance) onStop;
  final void Function(Map<String, dynamic> instance) onOpen;

  const ActiveInstancesPanel({
    super.key,
    required this.instances,
    required this.onStop,
    required this.onOpen,
    this.stoppingIds = const {},
    this.isDark = false,
  });

  static String idOf(Map<String, dynamic> i) => (i['_id'] ?? i['id'] ?? '').toString();

  static bool _isReady(Map<String, dynamic> i) => const ['ready', 'running'].contains(i['status']);

  static String statusText(Map<String, dynamic> i) {
    if (_isReady(i)) return 'Ready';
    final progress = i['progress'];
    final msg = progress is Map ? progress['message']?.toString() : null;
    return msg ?? 'Starting…';
  }

  static double? _billing(Map<String, dynamic> i, String key) {
    final b = i['billing'];
    return b is Map ? (b[key] as num?)?.toDouble() : null;
  }

  Future<void> _confirmAndStop(BuildContext context, Map<String, dynamic> instance) async {
    final gpu = instance['gpuType']?.toString() ?? 'GPU';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop $gpu?'),
        content: Text(_isReady(instance)
            ? 'The GPU will be shut down and destroyed. Time used so far stays charged.'
            : 'The GPU will be shut down and destroyed. It is not ready yet, so everything charged for it is refunded.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep running')),
          ElevatedButton(
            key: const ValueKey('confirm_stop_active_instance'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop GPU'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onStop(instance);
  }

  @override
  Widget build(BuildContext context) {
    final border = isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    return Container(
      key: const ValueKey('active_instances_panel'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        color: (isDark ? LuminaColors.darkSurface : Colors.white).withValues(alpha: isDark ? 0.72 : 0.85),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your active GPUs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final i in instances)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.memory_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i['gpuType']?.toString() ?? 'GPU', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${statusText(i)} · ${formatCreditsRate(_billing(i, 'creditsPerHour'), 'credits/hr')}'
                          ' · charged ${(_billing(i, 'creditsCharged') ?? 0).toStringAsFixed(2)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => onOpen(i), child: const Text('Details')),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    key: ValueKey('stop_active_${idOf(i)}'),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
                    onPressed: stoppingIds.contains(idOf(i)) ? null : () => _confirmAndStop(context, i),
                    child: Text(stoppingIds.contains(idOf(i)) ? 'Stopping…' : 'Stop'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
