import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/tidal_playlist.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../widgets/track_tile.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../utils/snackbar_helper.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  TidalPlaylist? _playlist;
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final playlist = await ApiService.getPlaylistDetails(widget.playlistId);
      final tracks = await ApiService.getPlaylistTracks(widget.playlistId);
      setState(() {
        _playlist = playlist;
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching playlist data: $e");
      if (mounted) {
        showSnackBar(context, "Error: $e");
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text("Playlist not found (ID: ${widget.playlistId})", style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchData, child: const Text("RETRY")),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_playlist!.title, style: const TextStyle(shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _playlist!.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                  ),
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
                  if (_playlist!.description != null && _playlist!.description!.isNotEmpty) ...[
                    Text(
                      _playlist!.description!,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    "${_playlist!.numberOfTracks} tracks • By ${_playlist!.creatorName ?? 'Tidal'}",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          if (_tracks.isNotEmpty) {
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(_tracks, initialIndex: 0);
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("PLAY"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: () {
                          if (_tracks.isNotEmpty) {
                            final shuffled = List<Track>.from(_tracks)..shuffle();
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(shuffled, initialIndex: 0);
                          }
                        },
                        icon: const Icon(Icons.shuffle),
                      ),
                      const SizedBox(width: 16),
                      Consumer<LibraryProvider>(
                        builder: (context, library, _) {
                          final isSaved = library.isPlaylistSaved(_playlist!.id);
                          return IconButton(
                            onPressed: () async {
                              await library.toggleSavePlaylist(_playlist!);
                              if (context.mounted) {
                                showSnackBar(
                                  context,
                                  library.isPlaylistSaved(_playlist!.id)
                                      ? 'Saved to library!'
                                      : 'Removed from library',
                                );
                              }
                            },
                            icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                            color: isSaved ? Theme.of(context).primaryColor : Colors.white,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = _tracks[index];
                return TrackTile(
                  track: track,
                  showMenu: true,
                  onTap: () {
                    Provider.of<PlayerProvider>(context, listen: false)
                        .playPlaylist(_tracks, initialIndex: index);
                  },
                );
              },
              childCount: _tracks.length,
            ),
          ),
          // Add bottom padding
          SliverToBoxAdapter(
            child: SizedBox(height: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom + 100),
          ),
        ],
      ),
    );
  }
}