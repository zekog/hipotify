import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/track_tile.dart';
import '../models/track.dart';
import '../widgets/responsive_layout.dart';

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
                            onTap: () {
                              Provider.of<PlayerProvider>(context, listen: false)
                                  .playPlaylist(library.downloadedSongs, initialIndex: index);
                            },
                          );
                        },
                      ),

                // Playlists
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.playlist_add, size: 64, color: Colors.grey[700]),
                      const SizedBox(height: 16),
                      const Text(
                        "Playlists coming soon",
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Create and manage your custom playlists here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
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
