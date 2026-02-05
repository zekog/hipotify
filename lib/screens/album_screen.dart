import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../widgets/track_tile.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../utils/snackbar_helper.dart';
import '../main.dart';
import 'main_screen.dart';

class AlbumScreen extends StatefulWidget {
  final String albumId;
  final Album? initialAlbum;
  final List<Track>? initialTracks;
  
  const AlbumScreen({
    super.key, 
    required this.albumId, 
    this.initialAlbum,
    this.initialTracks,
  });

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  Album? _album;
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  void _navigateToMainScreen(int index) {
    BottomNavBarState.navigateToMainScreen(context, index);
  }

  Future<void> _fetchData() async {
    try {
      Album? album = widget.initialAlbum;
      List<Track> tracks = widget.initialTracks ?? [];

      if (album == null || tracks.isEmpty) {
        final uri = Uri.parse('${ApiService.baseUrl}/album?id=${widget.albumId}');
        final response = await ApiService.getWithRetry(uri);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          album ??= ApiService.findAlbumInResponse(data, widget.albumId);
          tracks = ApiService.scanForTracks(data);
        }
      }

      // Synthesis fallback if we have tracks but no album metadata
      if (album == null && tracks.isNotEmpty) {
        final firstTrack = tracks[0];
        album = Album(
          id: widget.albumId,
          title: firstTrack.albumTitle,
          artistName: firstTrack.artistName,
          artistId: firstTrack.artistId,
          coverUuid: firstTrack.albumCoverUuid,
        );
      }

      if (album == null && tracks.isEmpty) {
        throw Exception("Could not fetch album details or tracks");
      }

      setState(() {
        _album = album;
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching album data: $e");
      if (mounted) {
        showSnackBar(context, "Error: $e");
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_album == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text("Album not found (ID: ${widget.albumId})", style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchData, child: const Text("RETRY")),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      // Bottom navigation bar is now global in MaterialApp builder
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_album!.title, style: const TextStyle(shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _album!.coverUrl,
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
                  Text(
                    "Album • ${_album!.artistName}",
                    style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(_tracks, initialIndex: 0);
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text("PLAY"),
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
                            final shuffled = List<Track>.from(_tracks)..shuffle();
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(shuffled, initialIndex: 0);
                          },
                          icon: const Icon(Icons.shuffle),
                          label: const Text("SHUFFLE"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _tracks.length,
                    itemBuilder: (context, index) {
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
                  ),
                  // Add bottom padding to prevent overlap with bottom navigation bar
                  SizedBox(height: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
