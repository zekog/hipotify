import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../services/api_service.dart';
import '../../services/download_service.dart';
import '../../providers/player_provider.dart';
import '../../providers/library_provider.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/rotary_scroll_wrapper.dart';
import 'wear_os_player_screen.dart';

class WearOsAlbumScreen extends StatefulWidget {
  final String albumId;
  final Album? initialAlbum;
  final List<Track>? initialTracks;
  
  const WearOsAlbumScreen({
    super.key, 
    required this.albumId, 
    this.initialAlbum,
    this.initialTracks,
  });

  @override
  State<WearOsAlbumScreen> createState() => _WearOsAlbumScreenState();
}

class _WearOsAlbumScreenState extends State<WearOsAlbumScreen> {
  final ScrollController _scrollController = ScrollController();
  Album? _album;
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
        throw Exception("Could not fetch album details");
      }

      setState(() {
        _album = album;
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
      setState(() => _isLoading = false);
    }
  }

  void _downloadAlbum() async {
    if (_album == null || _tracks.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Starting album download...')),
    );
    try {
      await DownloadService.downloadAlbumZip(_album!, _tracks);
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Download Complete')),
         );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed: $e')),
         );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_album == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text("Not Found")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: RotaryScrollWrapper(
        controller: _scrollController,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  children: [
                    ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: _album!.coverUrl,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _album!.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: WearOsConstants.titleSize,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WearOsConstants.smallPadding, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 36),
                      onPressed: () {
                        context.read<PlayerProvider>().playPlaylist(_tracks, initialIndex: 0);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.shuffle, color: Colors.white, size: 28),
                      onPressed: () {
                        final shuffled = List<Track>.from(_tracks)..shuffle();
                        context.read<PlayerProvider>().playPlaylist(shuffled, initialIndex: 0);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white, size: 28),
                      onPressed: _downloadAlbum,
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: WearOsConstants.defaultPadding, vertical: 2),
                    title: Text(track.title, maxLines: 1, style: const TextStyle(fontSize: WearOsConstants.bodySize)),
                    subtitle: Text(track.artistName, style: TextStyle(fontSize: WearOsConstants.captionSize, color: Colors.white54)),
                    onTap: () {
                      context.read<PlayerProvider>().playPlaylist(_tracks, initialIndex: index);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()));
                    },
                    trailing: GestureDetector(
                      onTap: () => _showTrackOptions(context, track),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.more_vert, size: 20),
                      ),
                    ),
                  );
                },
                childCount: _tracks.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)), // Margines na dole
          ],
        ),
      ),
    );
  }

  void _showTrackOptions(BuildContext context, Track track) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WearOsAlbumTrackOptionsScreen(
          track: track,
          library: context.read<LibraryProvider>(),
        ),
      ),
    );
  }
}

class _WearOsAlbumTrackOptionsScreen extends StatelessWidget {
  final Track track;
  final LibraryProvider library;

  const _WearOsAlbumTrackOptionsScreen({
    required this.track,
    required this.library,
  });

  @override
  Widget build(BuildContext context) {
    final isLiked = library.isLiked(track.id);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            vertical: 40,
            horizontal: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: WearOsConstants.defaultPadding),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            fontSize: WearOsConstants.titleSize,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          track.artistName,
                          style: TextStyle(
                            fontSize: WearOsConstants.captionSize,
                            color: Colors.white.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Colors.white24),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.pink : Colors.white,
                ),
                title: Text(isLiked ? 'Remove from Liked' : 'Add to Liked'),
                onTap: () {
                  library.toggleLike(track);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Add to Queue'),
                onTap: () {
                  context.read<PlayerProvider>().addToNext(track);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to queue')),
                  );
                },
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download, color: Colors.white),
                title: const Text('Download Track'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Download started')),
                  );
                  DownloadService.downloadTrack(track);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
