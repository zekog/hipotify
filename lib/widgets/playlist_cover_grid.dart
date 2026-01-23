import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/playlist.dart';

class PlaylistCoverGrid extends StatelessWidget {
  final Playlist playlist;
  final double size;

  const PlaylistCoverGrid({
    super.key,
    required this.playlist,
    this.size = 56.0,
  });

  @override
  Widget build(BuildContext context) {
    // If custom cover exists, use it
    if (playlist.customCoverPath != null && File(playlist.customCoverPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(playlist.customCoverPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to default if custom cover fails to load
            return _buildDefaultCover();
          },
        ),
      );
    }

    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() {
    if (playlist.tracks.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.queue_music, color: Colors.white54),
      );
    }

    // Take only first 4 covers (2x2 grid)
    final covers = playlist.tracks.take(4).map((t) => t.coverUrl).toList();

    if (covers.length == 1) {
      // Single cover
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: covers[0],
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: size,
            height: size,
            color: Colors.grey[800],
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, url, error) => Container(
            width: size,
            height: size,
            color: Colors.grey[800],
            child: const Icon(Icons.music_note, color: Colors.white54),
          ),
        ),
      );
    }

    // Grid layout - 2x2 (4 covers max)
    final crossAxisCount = 2;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Colors.grey[900],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: covers.length,
          itemBuilder: (context, index) {
            return CachedNetworkImage(
              imageUrl: covers[index],
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[800],
                child: const Center(child: CircularProgressIndicator(strokeWidth: 1)),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[800],
                child: const Icon(Icons.music_note, size: 12, color: Colors.white54),
              ),
            );
          },
        ),
      ),
    );
  }
}
