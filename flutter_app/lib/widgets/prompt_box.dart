import 'package:flutter/material.dart';

/// Multi-line prompt input + negative-prompt expansion tile.
class PromptBox extends StatelessWidget {
  final TextEditingController promptController;
  final TextEditingController negativeController;

  const PromptBox({
    super.key,
    required this.promptController,
    required this.negativeController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: promptController,
          maxLines: 4,
          minLines: 3,
          decoration: const InputDecoration(
            labelText: 'Prompt',
            hintText: 'A cinematic portrait of a fox in neon rain...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          title: const Text('Negative prompt'),
          tilePadding: EdgeInsets.zero,
          children: [
            TextField(
              controller: negativeController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'blurry, low quality, watermark...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
