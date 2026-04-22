import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/artist.dart';
import '../../models/track.dart';
import '../../models/album.dart';
import '../../services/api_service.dart';
import '../../providers/player_provider.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/rotary_scroll_wrapper.dart';
import 'wear_os_player_screen.dart';
import 'wear_os_album_screen.dart';

class WearOsArtistScreen extends StatefulWidget {
  final String artistId;
  const WearOsArtistScreen({super.key, required this.artistId});

  @override
  State<WearOsArtistScreen> createState() => _WearOsArtistScreenState();
}

class _WearOsArtistScreenState extends State<WearOsArtistScreen> {
  final ScrollController _scrollController = ScrollController();
  Artist? _artist;
  List<Track> _topTracks = [];
  List<Album> _albums = [];
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
      final artist = await ApiService.getArtistDetails(widget.artistId);
      
      var tracks = await ApiService.getArtistTopTracks(widget.artistId);
      final seenTitles = <String>{};
      final uniqueTracks = <Track>[];
      for (var track in tracks) {
        final cleanTitle = track.title.trim().toLowerCase();
        if (!seenTitles.contains(cleanTitle)) {
          seenTitles.add(cleanTitle);
          uniqueTracks.add(track);
        }
      }
      tracks = uniqueTracks;
      tracks.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
      if (tracks.length > 5) tracks = tracks.sublist(0, 5); // Zegarek, mało miejsca

      final allAlbums = await ApiService.getArtistAlbums(widget.artistId);
      final seenAlbumTitles = <String>{};
      final uniqueAllAlbums = <Album>[];
      for (var album in allAlbums) {
        final cleanTitle = album.title.trim().toLowerCase();
        if (!seenAlbumTitles.contains(cleanTitle)) {
          seenAlbumTitles.add(cleanTitle);
          uniqueAllAlbums.add(album);
        }
      }

      if (mounted) {
        setState(() {
          _artist = artist;
          _topTracks = tracks;
          _albums = uniqueAllAlbums.take(6).toList(); // Max 6 albumów dla zegarka
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isLoading = false);
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
    
    if (_artist == null) {
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
                        imageUrl: _artist!.pictureUrl,
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
                        _artist!.name,
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
            
            if (_topTracks.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text("Top Tracks", style: TextStyle(fontSize: WearOsConstants.titleSize, fontWeight: FontWeight.bold)),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = _topTracks[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: WearOsConstants.defaultPadding, vertical: 2),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: track.coverUrl,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(track.title, maxLines: 1, style: const TextStyle(fontSize: WearOsConstants.bodySize)),
                      onTap: () {
                        context.read<PlayerProvider>().playPlaylist(_topTracks, initialIndex: index);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()));
                      },
                    );
                  },
                  childCount: _topTracks.length,
                ),
              ),
            ],

            if (_albums.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text("Albums", style: TextStyle(fontSize: WearOsConstants.titleSize, fontWeight: FontWeight.bold)),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final album = _albums[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: WearOsConstants.defaultPadding, vertical: 2),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(20), // Okrągłe dla artysty/albumu jako badge
                        child: CachedNetworkImage(
                          imageUrl: album.coverUrl,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(album.title, maxLines: 1, style: const TextStyle(fontSize: WearOsConstants.bodySize)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => WearOsAlbumScreen(albumId: album.id, initialAlbum: album)
                        ));
                      },
                    );
                  },
                  childCount: _albums.length,
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 50)), // Margines na dole
          ],
        ),
      ),
    );
  }
}
