import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../services/api_service.dart';
import '../services/info_service.dart';
import '../widgets/track_tile.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../utils/snackbar_helper.dart';
import '../main.dart';
import 'album_screen.dart';
import 'main_screen.dart';

class ArtistScreen extends StatefulWidget {
  final String artistId;
  const ArtistScreen({super.key, required this.artistId});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Artist? _artist;
  String? _bio;
  List<Track> _topTracks = [];
  List<Album> _albums = [];
  List<Album> _singles = [];
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
      final artist = await ApiService.getArtistDetails(widget.artistId);
      
      String? bio;
      List<String> validTopTracks = [];

      try {
        if (artist.name.isNotEmpty) {
          bio = await InfoService.getArtistBio(artist.name);
          validTopTracks = await InfoService.getTopTracks(artist.name);
        }
      } catch (e) {
        print("Error fetching External Info data: $e");
      }

      // Fetch tracks from internal API
      var tracks = await ApiService.getArtistTopTracks(widget.artistId);
      
      // Deduplicate tracks
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
      
      // Sort tracks by External popularity if available
      if (validTopTracks.isNotEmpty) {
        print("Sorting ${tracks.length} tracks using ${validTopTracks.length} External top tracks");
        
        final rankMap = <String, int>{};
        for (int i = 0; i < validTopTracks.length; i++) {
          rankMap[validTopTracks[i].toLowerCase().trim()] = i;
        }

        tracks.sort((a, b) {
          final titleA = a.title.toLowerCase().trim();
          final titleB = b.title.toLowerCase().trim();
          
          final rankA = rankMap.containsKey(titleA) ? rankMap[titleA]! : 9999;
          final rankB = rankMap.containsKey(titleB) ? rankMap[titleB]! : 9999;
          
          if (rankA != rankB) {
            return rankA.compareTo(rankB);
          }
           return (b.popularity ?? 0).compareTo(a.popularity ?? 0);
        });
      } else {
        print("Sorting by internal popularity...");
        tracks.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
      }

      if (tracks.length > 10) {
        tracks = tracks.sublist(0, 10);
      }

      final allAlbums = await ApiService.getArtistAlbums(widget.artistId);

      // Deduplicate albums
      final seenAlbumTitles = <String>{};
      final uniqueAllAlbums = <Album>[];
      for (var album in allAlbums) {
        final cleanTitle = album.title.trim().toLowerCase();
        if (!seenAlbumTitles.contains(cleanTitle)) {
          seenAlbumTitles.add(cleanTitle);
          uniqueAllAlbums.add(album);
        }
      }
      
      if (!mounted) return;

      setState(() {
        _artist = artist;
        _bio = bio;
        _topTracks = tracks;
        _albums = uniqueAllAlbums.where((a) => a.type?.toUpperCase() == 'ALBUM').toList();
        _singles = uniqueAllAlbums.where((a) => a.type?.toUpperCase() != 'ALBUM').toList();
        _isLoading = false;
      });
      print("ArtistScreen: Found ${tracks.length} tracks (Sorted), ${_albums.length} albums, ${_singles.length} singles");
    } catch (e) {
      print("Error fetching artist data: $e");
      if (mounted) {
        showSnackBar(context, "Error: $e");
      }
      setState(() => _isLoading = false);
    }
  }

  void _showBioDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: 600, // Limit width on desktop
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "About ${_artist?.name ?? 'Artist'}",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _bio ?? "",
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

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
                          showIndex: true,
                          index: index,
                          showCover: true,
                          onTap: () {
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(_topTracks, initialIndex: index);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                  if (_albums.isNotEmpty) ...[
                    const Text("Albums", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(2, 8),
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
                                style: TextStyle(fontWeight: FontWeight.w500, color: textColor),
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
                    const SizedBox(height: 32),
                  ],
                  if (_singles.isNotEmpty) ...[
                    const Text("Singles & EPs", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(2, 8),
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _singles.length,
                      itemBuilder: (context, index) {
                        final album = _singles[index];
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
                                style: TextStyle(fontWeight: FontWeight.w500, color: textColor),
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
                    const SizedBox(height: 32),
                  ],
                  
                  // Biography Section - Moved to bottom
                  if (_bio != null && _bio!.isNotEmpty) ...[
                    Text(
                      "About",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _showBioDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                         padding: const EdgeInsets.symmetric(vertical: 8),
                         child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _bio!.trim(),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[300] : Colors.grey[800],
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Read full bio",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

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
