import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../services/api_service.dart';
import '../widgets/track_tile.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import 'album_screen.dart';

class ArtistScreen extends StatefulWidget {
  final String artistId;
  const ArtistScreen({super.key, required this.artistId});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Artist? _artist;
  List<Track> _topTracks = [];
  List<Album> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final artist = await ApiService.getArtistDetails(widget.artistId);
      // Top tracks and albums are now fetched using more robust scanning
      final tracks = await ApiService.getArtistTopTracks(widget.artistId);
      final albums = await ApiService.getArtistAlbums(widget.artistId);
      
      setState(() {
        _artist = artist;
        _topTracks = tracks;
        _albums = albums;
        _isLoading = false;
      });
      print("ArtistScreen: Found ${tracks.length} tracks and ${albums.length} albums for ${_artist?.name}");
    } catch (e) {
      print("Error fetching artist data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_artist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text("Artist not found (ID: ${widget.artistId})", style: const TextStyle(fontSize: 18)),
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
              title: Text(_artist!.name, style: const TextStyle(shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _artist!.pictureUrl,
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
                  if (_albums.isNotEmpty) ...[
                    const Text("Albums", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _albums.length,
                      itemBuilder: (context, index) {
                        final album = _albums[index];
                        return GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => AlbumScreen(albumId: album.id)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: album.coverUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: Colors.grey[900]),
                                    errorWidget: (context, url, error) => Container(color: Colors.grey[800], child: const Icon(Icons.album)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                album.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                album.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_topTracks.isNotEmpty) ...[
                    const Text("Top Tracks", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _topTracks.length > 10 ? 10 : _topTracks.length,
                      itemBuilder: (context, index) {
                        final track = _topTracks[index];
                        return TrackTile(
                          track: track,
                          showMenu: true,
                          onTap: () {
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(_topTracks, initialIndex: index);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
