import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/download_service.dart';
import '../main.dart';

class TrackTile extends StatefulWidget {
  final Track track;
  final VoidCallback onTap;
  final bool isDownloaded;
  final bool enablePlaylistActions;
  final bool showMenu;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.isDownloaded = false,
    this.enablePlaylistActions = false,
    this.showMenu = false,
    this.trailing,
  });

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _isFocused = false;

  EdgeInsets _getSnackBarMargin(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final isPlayerVisible = MiniPlayerVisibilityObserver.isPlayerVisible.value;
    final isMiniPlayerVisible = player.currentTrack != null && 
                                !isPlayerVisible && 
                                !player.isMiniPlayerHidden;
    
    if (isMiniPlayerVisible) {
      return EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 80,
        left: 8,
        right: 8,
      );
    } else {
      return EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
        left: 8,
        right: 8,
      );
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        margin: _getSnackBarMargin(context),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAddToPlaylistSheet() async {
    final library = Provider.of<LibraryProvider>(context, listen: false);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Consumer<LibraryProvider>(
            builder: (context, lib, _) {
              return ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('Add to playlist'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('New playlist'),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final name = await _promptForPlaylistName();
                      if (name == null) return;

                      try {
                        final playlist = await library.createPlaylist(name);
                        await library.addTrackToPlaylist(playlist.id, widget.track);
                        if (mounted) {
                          _showSnackBar(this.context, 'Added to "${playlist.name}"');
                        }
                      } catch (e) {
                        if (mounted) {
                          _showSnackBar(this.context, 'Failed: $e');
                        }
                      }
                    },
                  ),
                  if (lib.playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No playlists yet'),
                    )
                  else
                    ...lib.playlists.map(
                      (p) {
                        final isInPlaylist = library.isTrackInPlaylist(p.id, widget.track.id);
                        return ListTile(
                          leading: Icon(isInPlaylist ? Icons.check_circle : Icons.queue_music),
                          title: Text(p.name),
                          subtitle: Text('${p.tracks.length} tracks'),
                          onTap: () async {
                            Navigator.of(context).pop();
                            try {
                              final wasAdded = await library.toggleTrackInPlaylist(p.id, widget.track);
                              if (mounted) {
                                _showSnackBar(
                                  this.context,
                                  wasAdded
                                      ? 'Added to "${p.name}"'
                                      : 'Removed from "${p.name}"',
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                _showSnackBar(this.context, 'Failed: $e');
                              }
                            }
                          },
                        );
                      },
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<String?> _promptForPlaylistName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Playlist name',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    return result?.trim().isEmpty ?? true ? null : result!.trim();
  }


  @override
  Widget build(BuildContext context) {
    Widget? trailingWidget = widget.trailing;
    
    if (trailingWidget == null) {
      if (widget.showMenu) {
        trailingWidget = PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            final library = Provider.of<LibraryProvider>(context, listen: false);
            
            if (value == 'favorite') {
              await library.toggleLike(widget.track);
              if (mounted) {
                _showSnackBar(
                  context,
                  library.isLiked(widget.track.id)
                      ? 'Added to favorites!'
                      : 'Removed from favorites',
                );
              }
            } else if (value == 'playlist') {
              _showAddToPlaylistSheet();
            } else if (value == 'download') {
              try {
                await DownloadService.downloadTrack(
                  widget.track,
                  onProgress: (received, total) {},
                );
                if (mounted) {
                  library.refreshDownloads();
                  _showSnackBar(context, 'Download started');
                }
              } catch (e) {
                if (mounted) {
                  _showSnackBar(context, 'Download failed: $e');
                }
              }
            }
          },
          itemBuilder: (context) {
            final library = Provider.of<LibraryProvider>(context, listen: false);
            final isLiked = library.isLiked(widget.track.id);
            
            return [
              PopupMenuItem(
                value: 'favorite',
                child: Row(
                  children: [
                    Icon(isLiked ? Icons.favorite : Icons.favorite_border),
                    const SizedBox(width: 8),
                    Text(isLiked ? 'Remove from favorites' : 'Add to favorites'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'playlist',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add),
                    SizedBox(width: 8),
                    Text('Add to playlist'),
                  ],
                ),
              ),
              if (!widget.isDownloaded)
                const PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download),
                      SizedBox(width: 8),
                      Text('Download'),
                    ],
                  ),
                ),
            ];
          },
        );
      } else if (widget.enablePlaylistActions) {
        trailingWidget = IconButton(
          tooltip: 'Add to playlist',
          icon: const Icon(Icons.playlist_add),
          onPressed: () {
            _showAddToPlaylistSheet();
          },
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: _isFocused ? Colors.white.withOpacity(0.1) : Colors.transparent,
        border: _isFocused ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
      ),
      child: Row(
        children: [
          // Main content with InkWell (excluding trailing)
          Expanded(
            child: InkWell(
              onFocusChange: (value) => setState(() => _isFocused = value),
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    // Leading (cover image)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ClipRRect(
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
                    ),
                    // Title and subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                          Row(
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Trailing (button) - outside InkWell to prevent onTap
          if (trailingWidget != null) trailingWidget,
        ],
      ),
    );
  }
}
