import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';

class TrackTile extends StatefulWidget {
  final Track track;
  final VoidCallback onTap;
  final bool isDownloaded;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.isDownloaded = false,
  });

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: _isFocused ? Colors.white.withOpacity(0.1) : Colors.transparent,
        border: _isFocused ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
      ),
      child: ListTile(
        onFocusChange: (value) => setState(() => _isFocused = value),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: widget.track.coverUrl,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[800]),
            errorWidget: (context, url, error) => const Icon(Icons.music_note),
          ),
        ),
        title: Text(
          widget.track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Row(
          children: [
            if (widget.isDownloaded) ...[
              Icon(Icons.download_done, size: 14, color: Theme.of(context).primaryColor),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                widget.track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        onTap: widget.onTap,
      ),
    );
  }
}
