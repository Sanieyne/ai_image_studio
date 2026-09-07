import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Shows [Image.memory] when bytes exist, a placeholder when empty,
/// and a loading overlay while [isLoading] is true.
class ImagePreview extends StatelessWidget {
  final Uint8List? imageBytes;
  final bool isLoading;

  const ImagePreview({super.key, this.imageBytes, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageBytes != null)
              Image.memory(imageBytes!, fit: BoxFit.contain)
            else
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 64),
                    SizedBox(height: 8),
                    Text('Your image will appear here'),
                  ],
                ),
              ),
            if (isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Generating...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
