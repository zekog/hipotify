import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/hive_service.dart';
import '../providers/player_provider.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import '../widgets/focusable_card.dart';
import '../widgets/responsive_layout.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final recentTracks = HiveService.getRecentlyPlayed();
    final recentAlbums = HiveService.getRecentAlbums();
    final recentArtists = HiveService.getRecentArtists();
    final isTv = ResponsiveLayout.isTv(context);

    // Adjust sizes for TV
    final double sectionSpacing = isTv ? 48.0 : 24.0;
    final double listHeight = isTv ? 280.0 : 240.0;
    final double cardWidth = isTv ? 180.0 : 140.0;
    final double artistCardWidth = isTv ? 160.0 : 120.0;
    final double artistImageSize = isTv ? 140.0 : 100.0;
    final double titleFontSize = isTv ? 24.0 : 20.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Good Evening",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false, // Hide back button on TV if present
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          // Small delay to show the indicator
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: isTv ? 32.0 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (recentTracks.isNotEmpty) ...[
                _buildSectionTitle("Recently Played", fontSize: titleFontSize),
                const SizedBox(height: 12),
                SizedBox(
                  height: listHeight,
                  child: ListView.builder(
                    key: const ValueKey('recent_tracks'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    scrollDirection: Axis.horizontal,
                    itemCount: recentTracks.length,
                    itemBuilder: (context, index) {
                      final track = recentTracks[index];
                      return _buildTrackCard(context, track, width: cardWidth);
                    },
                  ),
                ),
                SizedBox(height: sectionSpacing),
              ],
              if (recentAlbums.isNotEmpty) ...[
                _buildSectionTitle("Recently Played Albums", fontSize: titleFontSize),
                const SizedBox(height: 12),
                SizedBox(
                  height: listHeight,
                  child: ListView.builder(
                    key: const ValueKey('recent_albums'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    scrollDirection: Axis.horizontal,
                    itemCount: recentAlbums.length,
                    itemBuilder: (context, index) {
                      final album = recentAlbums[index];
                      return _buildAlbumCard(context, album, width: cardWidth);
                    },
                  ),
                ),
                SizedBox(height: sectionSpacing),
              ],
              if (recentArtists.isNotEmpty) ...[
                _buildSectionTitle("Recently Played Artists", fontSize: titleFontSize),
                const SizedBox(height: 12),
                SizedBox(
                  height: listHeight,
                  child: ListView.builder(
                    key: const ValueKey('recent_artists'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    scrollDirection: Axis.horizontal,
                    itemCount: recentArtists.length,
                    itemBuilder: (context, index) {
                      final artist = recentArtists[index];
                      return _buildArtistCard(context, artist, width: artistCardWidth, imageSize: artistImageSize);
                    },
                  ),
                ),
                SizedBox(height: sectionSpacing),
              ],
              if (recentTracks.isEmpty && recentAlbums.isEmpty && recentArtists.isEmpty)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 100),
                      Icon(Icons.music_note, size: 80, color: Colors.grey.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      const Text(
                        "Start listening by searching for a song",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {double fontSize = 20.0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildTrackCard(BuildContext context, Track track, {double width = 140.0}) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: FocusableCard(
        onTap: () {
          context.read<PlayerProvider>().playTrack(track);
        },
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: track.coverUrl,
                  width: width,
                  height: width,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.music_note, color: Colors.white24),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.error, color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      track.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumCard(BuildContext context, Album album, {double width = 140.0}) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: FocusableCard(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => AlbumScreen(albumId: album.id)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: album.coverUrl,
                  width: width,
                  height: width,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.album, color: Colors.white24),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.error, color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      album.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtistCard(BuildContext context, Artist artist, {double width = 120.0, double imageSize = 100.0}) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: FocusableCard(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => ArtistScreen(artistId: artist.id)),
          );
        },
        borderRadius: BorderRadius.circular(100), // Circular focus for artists
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Container(
                width: imageSize,
                height: imageSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[900],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: artist.pictureUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: artist.pictureUrl,
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Icon(Icons.person, size: 50, color: Colors.white24),
                          errorWidget: (context, url, error) => const Icon(Icons.person, size: 50, color: Colors.white24),
                        )
                      : const Icon(Icons.person, size: 50, color: Colors.white24),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
