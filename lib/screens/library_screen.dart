import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/track_tile.dart';
import '../models/track.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/playlist_cover_grid.dart';
import '../services/hive_service.dart';
import 'playlist_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Your Library"),
          bottom: const TabBar(
            indicatorColor: Color(0xFF1DB954),
            tabs: [
              Tab(text: "Liked"),
              Tab(text: "Downloads"),
              Tab(text: "Playlists"),
            ],
          ),
        ),
        body: Consumer<LibraryProvider>(
          builder: (context, library, child) {
            return TabBarView(
              children: [
                // Liked Songs
                library.likedSongs.isEmpty
                    ? const Center(child: Text("No liked songs yet"))
                    : ListView.builder(
                        itemCount: library.likedSongs.length,
                        itemBuilder: (context, index) {
                          final track = library.likedSongs[index];
                          return TrackTile(
                            track: track,
                            enablePlaylistActions: true,
                            onTap: () {
                              Provider.of<PlayerProvider>(context, listen: false)
                                  .playPlaylist(library.likedSongs, initialIndex: index);
                            },
                          );
                        },
                      ),
                
                // Downloads
                library.downloadedSongs.isEmpty
                    ? const Center(child: Text("No downloads yet"))
                    : ListView.builder(
                        itemCount: library.downloadedSongs.length,
                        itemBuilder: (context, index) {
                          final track = library.downloadedSongs[index];
                          return TrackTile(
                            track: track,
                            isDownloaded: true,
                            showMenu: true,
                            onTap: () {
                              Provider.of<PlayerProvider>(context, listen: false)
                                  .playPlaylist(library.downloadedSongs, initialIndex: index);
                            },
                            trailing: IconButton(
                              tooltip: 'Delete download',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete download?'),
                                    content: Text('Delete "${track.title}" from downloads? This will also delete the file.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                
                                // Delete physical file if it exists
                                if (track.localPath != null) {
                                  try {
                                    final file = File(track.localPath!);
                                    if (await file.exists()) {
                                      await file.delete();
                                    }
                                  } catch (e) {
                                    print("Error deleting file: $e");
                                  }
                                }
                                
                                // Remove from Hive
                                await HiveService.removeDownload(track.id);
                                library.refreshDownloads();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Download deleted')),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),

                // Playlists
                _PlaylistsTab(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrackList(BuildContext context, List<dynamic> tracks, {bool isDownloaded = false}) {
    if (ResponsiveLayout.isTv(context)) {
      return GridView.builder(
        padding: const EdgeInsets.all(32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 5,
          crossAxisSpacing: 32,
          mainAxisSpacing: 16,
        ),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return TrackTile(
            track: track,
            isDownloaded: isDownloaded,
            onTap: () {
              Provider.of<PlayerProvider>(context, listen: false)
                  .playPlaylist(List<Track>.from(tracks), initialIndex: index);
            },
          );
        },
      );
    }

    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return TrackTile(
          track: track,
          isDownloaded: isDownloaded,
          onTap: () {
            Provider.of<PlayerProvider>(context, listen: false)
                .playPlaylist(List<Track>.from(tracks), initialIndex: index);
          },
        );
      },
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Your Playlists',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final name = await _promptForPlaylistName(context);
                      if (name == null) return;
                      try {
                        await Provider.of<LibraryProvider>(context, listen: false).createPlaylist(name);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: library.playlists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.queue_music, size: 64, color: Colors.grey[700]),
                          const SizedBox(height: 16),
                          const Text(
                            'No playlists yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Create a playlist and add tracks to it.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: library.playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = library.playlists[index];
                        return ListTile(
                          leading: PlaylistCoverGrid(playlist: playlist, size: 56),
                          title: Text(playlist.name),
                          subtitle: Text('${playlist.tracks.length} tracks'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlaylistScreen(playlistId: playlist.id),
                              ),
                            );
                          },
                          trailing: IconButton(
                            tooltip: 'Delete playlist',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete playlist?'),
                                  content: Text('Delete "${playlist.name}"? This cannot be undone.'),
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
                              if (confirmed != true) return;
                              await Provider.of<LibraryProvider>(context, listen: false)
                                  .deletePlaylist(playlist.id);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptForPlaylistName(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New playlist'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final name = result?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }
}
