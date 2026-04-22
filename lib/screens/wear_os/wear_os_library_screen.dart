import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/player_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/hive_service.dart';
import '../../models/track.dart';
import '../../models/playlist.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/rotary_scroll_wrapper.dart';
import '../../services/download_service.dart';
import 'wear_os_player_screen.dart';

/// Wear OS optimized library screen
class WearOsLibraryScreen extends StatefulWidget {
  const WearOsLibraryScreen({super.key});

  @override
  State<WearOsLibraryScreen> createState() => _WearOsLibraryScreenState();
}

class _WearOsLibraryScreenState extends State<WearOsLibraryScreen> {
  int _selectedTab = 0;
  final List<String> _tabs = ['Liked', 'Playlists', 'Downloads', 'Recent'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24), // Dla zaokrąglenia na górze ekranu
            
            // Tab selector
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(
                  horizontal: WearOsConstants.smallPadding),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedTab == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTab = index),
                    child: AnimatedContainer(
                      duration: WearOsConstants.quickAnimation,
                      margin: const EdgeInsets.only(right: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).primaryColor.withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _tabs[index],
                        style: TextStyle(
                          fontSize: WearOsConstants.captionSize,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: WearOsConstants.smallPadding),

            // Content
            Expanded(
              child: _buildTabContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildLikedSongsTab();
      case 1:
        return _buildPlaylistsTab();
      case 2:
        return _buildDownloadsTab();
      case 3:
        return _buildRecentTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLikedSongsTab() {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        final likedSongs = library.likedSongs;

        if (likedSongs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.favorite_border,
            message: 'No liked songs',
            subMessage: 'Tap ♥ to add songs',
          );
        }

        return RotaryScrollWrapper(
          controller: ScrollController(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                WearOsConstants.smallPadding, 0, WearOsConstants.smallPadding, 40),
            itemCount: likedSongs.length,
            itemBuilder: (context, index) {
              final track = likedSongs[index];
              return _LibraryTrackTile(
                track: track,
                onTap: () {
                  context.read<PlayerProvider>().playTrack(track);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
                  );
                },
                onMore: () => _showTrackOptions(context, track, library),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPlaylistsTab() {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        final playlists = library.playlists;

        if (playlists.isEmpty) {
          return _buildEmptyState(
            icon: Icons.playlist_play,
            message: 'No playlists',
            subMessage: 'Create your first playlist',
          );
        }

        return RotaryScrollWrapper(
          controller: ScrollController(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                WearOsConstants.smallPadding, 0, WearOsConstants.smallPadding, 40),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _PlaylistTile(
                playlist: playlist,
                onTap: () => _showPlaylistDetails(context, playlist),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDownloadsTab() {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        final downloads = library.downloadedSongs;

        if (downloads.isEmpty) {
          return _buildEmptyState(
            icon: Icons.download_outlined,
            message: 'No downloads',
            subMessage: 'Download songs for offline',
          );
        }

        return RotaryScrollWrapper(
          controller: ScrollController(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                WearOsConstants.smallPadding, 0, WearOsConstants.smallPadding, 40),
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final track = downloads[index];
              return _LibraryTrackTile(
                track: track,
                onTap: () {
                  context.read<PlayerProvider>().playTrack(track);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
                  );
                },
                onMore: () => _showTrackOptions(context, track, library),
                showDownloadedIndicator: true,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRecentTab() {
    final recentTracks = HiveService.getRecentlyPlayed();

    if (recentTracks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history,
        message: 'No recent songs',
        subMessage: 'Start listening',
      );
    }

    return RotaryScrollWrapper(
      controller: ScrollController(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
                WearOsConstants.smallPadding, 0, WearOsConstants.smallPadding, 40),
        itemCount: recentTracks.length,
        itemBuilder: (context, index) {
          final track = recentTracks[index];
          return _LibraryTrackTile(
            track: track,
            onTap: () {
              context.read<PlayerProvider>().playTrack(track);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
              );
            },
            onMore: () => _showTrackOptions(
                context, track, context.read<LibraryProvider>()),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String subMessage,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: WearOsConstants.titleSize,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subMessage,
            style: TextStyle(
              fontSize: WearOsConstants.captionSize,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showTrackOptions(
      BuildContext context, Track track, LibraryProvider library) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WearOsTrackOptionsScreen(
          track: track,
          library: library,
        ),
      ),
    );
  }

  void _showPlaylistDetails(BuildContext context, Playlist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WearOsPlaylistDetailScreen(playlist: playlist),
      ),
    );
  }
}

/// Library track tile
class _LibraryTrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final bool showDownloadedIndicator;

  const _LibraryTrackTile({
    required this.track,
    required this.onTap,
    required this.onMore,
    this.showDownloadedIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: track.coverUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: Colors.grey[800],
            child: const Icon(Icons.music_note, size: 20),
          ),
        ),
      ),
      title: Text(
        track.title,
        style: const TextStyle(fontSize: WearOsConstants.bodySize),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (showDownloadedIndicator)
            Icon(Icons.download_done, size: 12, color: Colors.green[400]),
          if (showDownloadedIndicator) const SizedBox(width: 4),
          Expanded(
            child: Text(
              track.artistName,
              style: TextStyle(
                fontSize: WearOsConstants.captionSize,
                color: Colors.white.withOpacity(0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: GestureDetector(
        onTap: onMore,
        child: Container(
          padding: const EdgeInsets.all(4),
          color: Colors.transparent, // Zwiększenie strefy kliknięcia
          child: const Icon(Icons.more_vert, size: 20),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Playlist tile
class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _PlaylistTile({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.5),
              Theme.of(context).primaryColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.queue_music, size: 24),
      ),
      title: Text(
        playlist.name,
        style: const TextStyle(
            fontSize: WearOsConstants.bodySize, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.tracks.length} tracks',
        style: TextStyle(
          fontSize: WearOsConstants.captionSize,
          color: Colors.white.withOpacity(0.6),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

/// Playlist detail screen for Wear OS
class WearOsPlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const WearOsPlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          playlist.name,
          style: const TextStyle(fontSize: WearOsConstants.titleSize),
        ),
        centerTitle: true,
        toolbarHeight: 48,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              if (playlist.tracks.isNotEmpty) {
                context.read<PlayerProvider>().playPlaylist(playlist.tracks);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: playlist.tracks.isEmpty
          ? Center(
              child: Text(
                'No tracks in this playlist',
                style: TextStyle(
                  fontSize: WearOsConstants.bodySize,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  WearOsConstants.smallPadding, 0, WearOsConstants.smallPadding, 40),
              itemCount: playlist.tracks.length,
              itemBuilder: (context, index) {
                final track = playlist.tracks[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(
                    track.title,
                    style: const TextStyle(fontSize: WearOsConstants.bodySize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.artistName,
                    style: TextStyle(
                      fontSize: WearOsConstants.captionSize,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  onTap: () {
                    context.read<PlayerProvider>().playPlaylist(
                          playlist.tracks,
                          initialIndex: index,
                        );
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _WearOsTrackOptionsScreen extends StatelessWidget {
  final Track track;
  final LibraryProvider library;

  const _WearOsTrackOptionsScreen({
    required this.track,
    required this.library,
  });

  @override
  Widget build(BuildContext context) {
    final isLiked = library.isLiked(track.id);
    final isDownloaded = library.downloadedSongs.any((t) => t.id == track.id);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            vertical: 30, // Miejsce na zegar / ramkę
            horizontal: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Track preview
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
                leading: const Icon(Icons.play_arrow, color: Colors.white),
                title: const Text('Play Now'),
                onTap: () {
                  context.read<PlayerProvider>().playTrack(track);
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
                  );
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
              if (!isDownloaded)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download, color: Colors.white),
                  title: const Text('Download'),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download started')),
                    );
                    DownloadService.downloadTrack(track);
                  },
                ),
                
              const SizedBox(height: 40), // Pad od dołu
            ],
          ),
        ),
      ),
    );
  }
}
