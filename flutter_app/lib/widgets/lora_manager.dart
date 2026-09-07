import 'package:flutter/material.dart';

import '../models/lora.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// LoRA style packs: list active, add by path/HF id, scale weight, unload.
/// Styled to the Lumina dialog language (see settings_dialog.dart).
class LoraManagerDialog extends StatefulWidget {
  final ApiService api;

  const LoraManagerDialog({super.key, required this.api});

  static Future<void> show(BuildContext context, ApiService api) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor:
            isDark ? const Color(0xFF14181F) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: LoraManagerDialog(api: api),
        ),
      ),
    );
  }

  @override
  State<LoraManagerDialog> createState() => _LoraManagerDialogState();
}

class _LoraManagerDialogState extends State<LoraManagerDialog> {
  Map<String, LoraInfo> _active = {};
  bool _loading = true;
  String? _error;
  bool _adding = false;

  final _pathController = TextEditingController();
  final _nameController = TextEditingController();
  double _weight = 0.8;
  final Map<String, double> _pendingScales = {};

  // LoRAs known to live on the engine (getActiveLoras only reports
  // *loaded* ones, and returns {} when offline, so suggest + probe).
  static const _known = [
    {'id': 'LyliaEngine/add-detail-xl', 'hint': 'Detail booster (SDXL)'},
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final online = await widget.api.checkHealth();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _loading = false;
        _active = {};
        _error = 'Engine offline — start your tunnel, then Refresh.';
      });
      return;
    }
    try {
      final loras = await widget.api.getActiveLoras();
      if (!mounted) return;
      setState(() {
        _active = loras;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not reach engine: $e';
      });
    }
  }

  Future<void> _load() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    final ok = await widget.api.loadLora(LoraConfig(
      pathOrId: path,
      adapterName: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      weight: _weight,
    ));
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok) {
      _pathController.clear();
      _nameController.clear();
      await _refresh();
    } else {
      setState(() => _error = 'Load failed. Check the path or HF id.');
    }
  }

  Future<void> _loadKnown(String id) async {
    _pathController.text = id;
    _nameController.clear();
    await _load();
  }

  Future<void> _unloadAll() async {
    final ok = await widget.api.unloadLoras();
    if (!mounted) return;
    if (ok) {
      await _refresh();
    } else {
      setState(() => _error = 'Unload failed.');
    }
  }

  InputDecoration _field(String hint, bool isDark) => InputDecoration(
        isDense: true,
        hintText: hint,
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1A1F28)
            : Colors.black.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LoRA style packs (${_active.length})',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _refresh,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
          Text(
            'SDXL LoRAs only apply while an SDXL model is loaded.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _active.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No LoRAs loaded. Pick one below.',
                          style:
                              TextStyle(fontSize: 13, color: muted),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final e in _active.entries)
                            _loraRow(e.key, e.value, isDark, muted),
                        ],
                      ),
          ),
          const SizedBox(height: 12),
          const Text('On this engine',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          for (final k in _known)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? LuminaColors.darkCard
                    : LuminaColors.lightCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? LuminaColors.darkBorder
                      : LuminaColors.lightBorder,
                ),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.style_outlined,
                    size: 20, color: muted),
                title: Text(k['id']!,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(k['hint']!,
                    style: TextStyle(fontSize: 11, color: muted)),
                trailing: _active.keys.any((n) =>
                        n.toLowerCase().contains('add-detail'))
                    ? const Icon(Icons.check_circle,
                        color: Colors.green, size: 20)
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed:
                            _adding ? null : () => _loadKnown(k['id']!),
                        child: const Text('Load',
                            style: TextStyle(fontSize: 12)),
                      ),
              ),
            ),
          const SizedBox(height: 12),
          const Text('Add LoRA',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _pathController,
            style: const TextStyle(fontSize: 13),
            decoration:
                _field('Path on engine or HF id', isDark),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: _field('Name (optional)', isDark),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Text(_weight.toStringAsFixed(2),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          Row(
            children: [
              Text('Weight',
                  style: TextStyle(fontSize: 13, color: muted)),
              Expanded(
                child: Slider(
                  min: 0.0,
                  max: 2.0,
                  divisions: 40,
                  value: _weight,
                  label: _weight.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _weight = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onPressed: _adding ? null : _load,
                  icon: _adding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Load LoRA'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _active.isEmpty ? null : _unloadAll,
                child:
                    const Text('Unload all', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loraRow(String name, LoraInfo info, bool isDark, Color muted) {
    final scale = _pendingScales[name] ?? info.weight;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? LuminaColors.darkCard : LuminaColors.lightCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? LuminaColors.darkBorder
              : LuminaColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Text(info.path,
              style: TextStyle(fontSize: 11, color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Row(
            children: [
              Text('Scale',
                  style: TextStyle(fontSize: 12, color: muted)),
              Expanded(
                child: Slider(
                  min: 0.0,
                  max: 2.0,
                  divisions: 40,
                  value: scale,
                  label: scale.toStringAsFixed(2),
                  onChanged: (v) =>
                      setState(() => _pendingScales[name] = v),
                  onChangeEnd: (v) =>
                      widget.api.setLoraScale(name, v),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(scale.toStringAsFixed(2),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
