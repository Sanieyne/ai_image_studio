import 'package:flutter/material.dart';

/// Sliders for steps / CFG + dimension dropdowns.
class GenerationSettings extends StatelessWidget {
  final int steps;
  final double cfgScale;
  final int width;
  final int height;
  final ValueChanged<int> onStepsChanged;
  final ValueChanged<double> onCfgChanged;
  final ValueChanged<int> onWidthChanged;
  final ValueChanged<int> onHeightChanged;

  static const dimensions = [512, 768, 1024];

  const GenerationSettings({
    super.key,
    required this.steps,
    required this.cfgScale,
    required this.width,
    required this.height,
    required this.onStepsChanged,
    required this.onCfgChanged,
    required this.onWidthChanged,
    required this.onHeightChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Steps'),
            Expanded(
              child: Slider(
                min: 1,
                max: 50,
                divisions: 49,
                value: steps.toDouble(),
                label: '$steps',
                onChanged: (v) => onStepsChanged(v.round()),
              ),
            ),
            SizedBox(width: 40, child: Text('$steps', textAlign: TextAlign.end)),
          ],
        ),
        Row(
          children: [
            const Text('CFG'),
            Expanded(
              child: Slider(
                min: 1.0,
                max: 15.0,
                divisions: 140,
                value: cfgScale,
                label: cfgScale.toStringAsFixed(1),
                onChanged: onCfgChanged,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(cfgScale.toStringAsFixed(1), textAlign: TextAlign.end),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: width,
                decoration: const InputDecoration(
                  labelText: 'Width',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final d in dimensions)
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) {
                  if (v != null) onWidthChanged(v);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: height,
                decoration: const InputDecoration(
                  labelText: 'Height',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final d in dimensions)
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) {
                  if (v != null) onHeightChanged(v);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
