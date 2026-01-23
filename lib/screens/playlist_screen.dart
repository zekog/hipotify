import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../widgets/track_tile.dart';
import '../widgets/playlist_cover_grid.dart';
import '../main.dart';
import 'main_screen.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final ValueNotifier<int> _menuRefreshNotifier = ValueNotifier<int>(0);

  @override
  void dispose() {
    _menuRefreshNotifier.dispose();
    super.dispose();
  }

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

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    } else {
      return '${minutes}min';
    }
  }

  void _navigateToMainScreen(int index) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => MainScreen(initialIndex: index),
      ),
      (route) => false,
    );
  }

  Future<void> _renamePlaylist(BuildContext context, LibraryProvider library, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Playlist name'),
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
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    
    final newName = result?.trim();
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        final playlist = library.getPlaylistById(widget.playlistId);
        if (playlist != null) {
          final updated = playlist.copyWith(name: newName);
          await library.updatePlaylist(updated);
          if (context.mounted) {
            _showSnackBar(context, 'Playlist renamed to "$newName"');
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to rename: $e'),
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 80,
                left: 8,
                right: 8,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickCustomCover(BuildContext context, LibraryProvider library) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      final playlist = library.getPlaylistById(widget.playlistId);
      if (playlist == null) return;

      // Delete old cover if exists - delete all old versions
      if (playlist.customCoverPath != null) {
        try {
          final oldCoverFile = File(playlist.customCoverPath!);
          if (await oldCoverFile.exists()) {
            await oldCoverFile.delete();
          }
        } catch (e) {
          print("Error deleting old cover: $e");
        }
      }

      // Also delete any old cover files with the same playlist ID pattern
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final playlistDir = Directory('${appDir.path}/playlist_covers');
        if (await playlistDir.exists()) {
          final files = playlistDir.listSync();
          for (var file in files) {
            if (file is File && file.path.startsWith('${playlistDir.path}/${playlist.id}')) {
              try {
                await file.delete();
              } catch (e) {
                print("Error deleting old cover file: $e");
              }
            }
          }
        }
      } catch (e) {
        print("Error cleaning old cover files: $e");
      }

      // Save image to app directory with playlist ID and timestamp as filename
      final appDir = await getApplicationDocumentsDirectory();
      final playlistDir = Directory('${appDir.path}/playlist_covers');
      if (!await playlistDir.exists()) {
        await playlistDir.create(recursive: true);
      }

      // Use timestamp to create unique filename and avoid cache issues
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savedImage = File('${playlistDir.path}/${playlist.id}_$timestamp.jpg');
      await File(image.path).copy(savedImage.path);

      // Update playlist with custom cover path
      final updated = playlist.copyWith(customCoverPath: savedImage.path);
      await library.updatePlaylist(updated);

      if (context.mounted) {
        // Force menu rebuild and UI refresh
        setState(() {
          _menuRefreshNotifier.value++;
        });
        _showSnackBar(context, 'Custom cover image set');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, 'Failed to set cover: $e');
      }
    }
  }

  Future<void> _removeCustomCover(BuildContext context, LibraryProvider library) async {
    try {
      final playlist = library.getPlaylistById(widget.playlistId);
      if (playlist == null || playlist.customCoverPath == null) return;

      // Delete the image file
      final coverFile = File(playlist.customCoverPath!);
      if (await coverFile.exists()) {
        await coverFile.delete();
      }

      // Also delete any old cover files with the same playlist ID pattern
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final playlistDir = Directory('${appDir.path}/playlist_covers');
        if (await playlistDir.exists()) {
          final files = playlistDir.listSync();
          for (var file in files) {
            if (file is File && file.path.startsWith('${playlistDir.path}/${playlist.id}')) {
              try {
                await file.delete();
              } catch (e) {
                print("Error deleting cover file: $e");
              }
            }
          }
        }
      } catch (e) {
        print("Error cleaning cover files: $e");
      }

      // Update playlist to remove custom cover
      final updated = playlist.copyWith(customCoverPath: null);
      await library.updatePlaylist(updated);

      if (context.mounted) {
        // Force menu rebuild and UI refresh
        setState(() {
          _menuRefreshNotifier.value++;
        });
        _showSnackBar(context, 'Custom cover removed');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, 'Failed to remove cover: $e');
      }
    }
  }

  Widget _buildDefaultCover(Playlist playlist) {
    if (playlist.tracks.isNotEmpty && playlist.tracks.first.coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: playlist.tracks.first.coverUrl,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => Container(
          color: const Color(0xFF121212),
          child: Center(
            child: PlaylistCoverGrid(
              playlist: playlist,
              size: 200,
            ),
          ),
        ),
      );
    } else {
      return Container(
        color: const Color(0xFF121212),
        child: Center(
          child: PlaylistCoverGrid(
            playlist: playlist,
            size: 200,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        final playlist = library.getPlaylistById(widget.playlistId);
        if (playlist == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Playlist')),
            body: const Center(child: Text('Playlist not found')),
          );
        }

        final totalDuration = playlist.tracks.fold<int>(
          0,
          (sum, track) => sum + track.duration,
        );
        final trackCount = playlist.tracks.length;
        final durationText = totalDuration > 0 
            ? _formatDuration(totalDuration)
            : '';

        return Scaffold(
          bottomNavigationBar: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: BottomNavigationBar(
                currentIndex: 2, // Library is selected
                onTap: (index) {
                  if (index == 2) {
                    // Library - just pop back
                    Navigator.of(context).pop();
                  } else {
                    // Other screens - navigate to MainScreen
                    _navigateToMainScreen(index);
                  }
                },
                backgroundColor: Colors.black.withOpacity(0.5),
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: Theme.of(context).primaryColor,
                unselectedItemColor: Colors.white.withOpacity(0.5),
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                  BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                  BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
                  BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Download'),
                  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
                ],
              ),
            ),
          ),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                actions: [
                  ValueListenableBuilder<int>(
                    valueListenable: _menuRefreshNotifier,
                    builder: (context, _, __) {
                      return Consumer<LibraryProvider>(
                        builder: (context, lib, _) {
                          final currentPlaylist = lib.getPlaylistById(widget.playlistId);
                          if (currentPlaylist == null) {
                            return const SizedBox.shrink();
                          }
                          
                          return PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                              switch (value) {
                                case 'rename':
                                  _renamePlaylist(context, lib, currentPlaylist.name);
                                  break;
                                case 'set_cover':
                                  _pickCustomCover(context, lib);
                                  break;
                                case 'remove_cover':
                                  _removeCustomCover(context, lib);
                                  break;
                                case 'delete':
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Delete playlist?'),
                                      content: Text('Delete "${currentPlaylist.name}"? This cannot be undone.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.of(context).pop(true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await lib.deletePlaylist(currentPlaylist.id);
                                    if (context.mounted) Navigator.of(context).pop();
                                  }
                                  break;
                              }
                            },
                            itemBuilder: (context) {
                              return [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: const Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 20),
                                      SizedBox(width: 12),
                                      Text('Rename playlist'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'set_cover',
                                  child: const Row(
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined, size: 20),
                                      SizedBox(width: 12),
                                      Text('Set custom cover'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'remove_cover',
                                  child: const Row(
                                    children: [
                                      Icon(Icons.remove_circle_outline, size: 20),
                                      SizedBox(width: 12),
                                      Text('Remove custom cover'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: const Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      SizedBox(width: 12),
                                      Text('Delete playlist', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ];
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                  title: Text(
                    playlist.name,
                    style: const TextStyle(shadows: [Shadow(blurRadius: 10, color: Colors.black)]),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background cover image (use custom cover if available, otherwise first track's cover or grid)
                      playlist.customCoverPath != null && File(playlist.customCoverPath!).existsSync()
                          ? Image.file(
                              File(playlist.customCoverPath!),
                              key: ValueKey(playlist.customCoverPath), // Force rebuild when path changes
                              fit: BoxFit.cover,
                              cacheWidth: null, // Disable cache to always show fresh image
                              cacheHeight: null,
                              errorBuilder: (context, error, stackTrace) {
                                // Fallback if custom cover file doesn't exist
                                return _buildDefaultCover(playlist);
                              },
                            )
                          : _buildDefaultCover(playlist),
                      // Gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (trackCount > 0)
                        Text(
                          trackCount == 1 
                              ? 'Playlist • 1 song${durationText.isNotEmpty ? ' • $durationText' : ''}'
                              : 'Playlist • $trackCount songs${durationText.isNotEmpty ? ' • $durationText' : ''}',
                          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)),
                        )
                      else
                        Text(
                          'Playlist',
                          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)),
                        ),
                      const SizedBox(height: 16),
                      if (trackCount > 0) ...[
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Provider.of<PlayerProvider>(context, listen: false)
                                      .playPlaylist(playlist.tracks, initialIndex: 0);
                                },
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('PLAY'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  final shuffled = List<Track>.from(playlist.tracks)..shuffle();
                                  Provider.of<PlayerProvider>(context, listen: false)
                                      .playPlaylist(shuffled, initialIndex: 0);
                                },
                                icon: const Icon(Icons.shuffle),
                                label: const Text('SHUFFLE'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ] else
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32.0),
                          child: Center(
                            child: Text(
                              'No tracks in this playlist yet',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      if (playlist.tracks.isNotEmpty)
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: playlist.tracks.length,
                          onReorder: (oldIndex, newIndex) async {
                            await library.reorderPlaylistTracks(
                              playlist.id,
                              oldIndex,
                              newIndex,
                            );
                          },
                          itemBuilder: (context, index) {
                            final track = playlist.tracks[index];
                            return Container(
                              key: ValueKey('${playlist.id}_${track.id}_$index'),
                              child: TrackTile(
                                track: track,
                                showMenu: true,
                                onTap: () {
                                  Provider.of<PlayerProvider>(context, listen: false)
                                      .playPlaylist(playlist.tracks, initialIndex: index);
                                },
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Remove from playlist',
                                      icon: const Icon(Icons.remove_circle_outline),
                                      onPressed: () async {
                                        await library.removeTrackFromPlaylist(playlist.id, track.id);
                                        if (!context.mounted) return;
                                        _showSnackBar(context, 'Removed from "${playlist.name}"');
                                      },
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8.0),
                                      child: Icon(
                                        Icons.drag_handle,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

  