import 'package:flutter/material.dart';

/// Full-screen, zoomable view of a chat photo.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  final String imageUrl;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Hero(
            tag: heroTag,
            child: Image.network(
              imageUrl,
              semanticLabel: 'Photo',
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                final total = progress.expectedTotalBytes;
                return CircularProgressIndicator(
                  value: total == null
                      ? null
                      : progress.cumulativeBytesLoaded / total,
                );
              },
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
