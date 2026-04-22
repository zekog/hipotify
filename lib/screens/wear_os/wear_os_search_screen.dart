import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/player_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/api_service.dart';
import '../../services/hive_service.dart';
import '../../models/track.dart';
import '../../models/artist.dart';
import '../../models/album.dart';
import '../../models/tidal_playlist.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/rotary_scroll_wrapper.dart';
import '../../services/download_service.dart';
import 'wear_os_player_screen.dart';
import 'wear_os_album_screen.dart';
import 'wear_os_artist_screen.dart';

/// Wear OS optimized search screen with voice input and quick results
class WearOsSearchScreen extends StatefulWidget {
  const WearOsSearchScreen({super.key});

  @override
  State<WearOsSearchScreen> createState() => _WearOsSearchScreenState();
}

class _WearOsSearchScreenState extends State<WearOsSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<dynamic> _results = [];
  bool _isLoading = false;
  List<String> _searchHistory = [];

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  void _loadSearchHistory() {
    setState(() {
      _searchHistory = HiveService.getSearchHistory();
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    // Add to history
    await HiveService.addToSearchHistory(query);
    _loadSearchHistory();

    setState(() {
      _isLoading = true;
      _results = [];
    });

    try {
      final results = await ApiService.search(query, offset: 0, limit: 20);
      setState(() => _results = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _results = [];
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24), // Ramka
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WearOsConstants.smallPadding),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: WearOsConstants.smallPadding),
                    Icon(Icons.search,
                        color: Colors.white.withOpacity(0.6), size: 18),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        style:
                            const TextStyle(fontSize: WearOsConstants.bodySize),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(
                            fontSize: WearOsConstants.bodySize,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.only(bottom: 12),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _performSearch,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: _clearSearch,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(Icons.clear,
                              color: Colors.white.withOpacity(0.6), size: 18),
                        ),
                      ),
                    GestureDetector(
                      onTap: _showVoiceSearch,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(Icons.mic,
                            color: Theme.of(context).primaryColor, size: 20),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Results or History
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _results.isEmpty && _searchController.text.isEmpty
                      ? _buildSearchHistory()
                      : _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHistory() {
    if (_searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 40, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 8),
            Text(
              'Search for music',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: WearOsConstants.bodySize,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          WearOsConstants.smallPadding, 0, WearOsConstants.smallPadding, 40),
      itemCount: _searchHistory.length,
      itemBuilder: (context, index) {
        final query = _searchHistory[index];
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Icon(Icons.history,
              size: 20, color: Colors.white.withOpacity(0.5)),
          title: Text(
            query,
            style: const TextStyle(fontSize: WearOsConstants.bodySize),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: GestureDetector(
            onTap: () async {
              await HiveService.removeFromSearchHistory(query);
              _loadSearchHistory();
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              color: Colors.transparent,
              child: Icon(Icons.close,
                  size: 18, color: Colors.white.withOpacity(0.4)),
            ),
          ),
          onTap: () {
            _searchController.text = query;
            _performSearch(query);
          },
        );
      },
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No results',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: WearOsConstants.bodySize,
          ),
        ),
      );
    }

    return RotaryScrollWrapper(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
            WearOsConstants.smallPadding, 0, WearOsConstants.smallPadding, 40),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final item = _results[index];

        if (item is Track) {
          return _WearOsSearchResultTile(
            title: item.title,
            subtitle: item.artistName,
            imageUrl: item.coverUrl,
            icon: Icons.music_note,
            onTap: () {
              context.read<PlayerProvider>().playTrack(item);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
              );
            },
            onLongPress: () => _showTrackOptions(item),
          );
        }

        if (item is Artist) {
          return _WearOsSearchResultTile(
            title: item.name,
            subtitle: 'Artist',
            imageUrl: item.pictureUrl,
            icon: Icons.person,
            isCircular: true,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => WearOsArtistScreen(artistId: item.id)
              ));
            },
          );
        }

        if (item is Album) {
          return _WearOsSearchResultTile(
            title: item.title,
            subtitle: 'Album • ${item.artistName}',
            imageUrl: item.coverUrl,
            icon: Icons.album,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => WearOsAlbumScreen(albumId: item.id, initialAlbum: item)
              ));
            },
          );
        }

        if (item is TidalPlaylist) {
          return _WearOsSearchResultTile(
            title: item.title,
            subtitle: 'Playlist • ${item.creatorName ?? 'Tidal'}',
            imageUrl: item.imageUrl,
            icon: Icons.playlist_play,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Playlist details coming soon'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          );
        }

        return const SizedBox.shrink();
      },
     ),
    );
  }

  void _showTrackOptions(Track track) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WearOsSearchTrackOptionsScreen(
          track: track,
          library: context.read<LibraryProvider>(),
        ),
      ),
    );
  }

  void _showVoiceSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _WearOsVoiceSearchScreen()),
    );
  }
}

class _WearOsSearchResultTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final IconData icon;
  final bool isCircular;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _WearOsSearchResultTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.icon,
    this.isCircular = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(isCircular ? 20 : 4),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: Colors.grey[800],
            child: Icon(icon, size: 20, color: Colors.white.withOpacity(0.3)),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Colors.grey[800],
            child: Icon(icon, size: 20, color: Colors.white.withOpacity(0.3)),
          ),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
            fontSize: WearOsConstants.bodySize, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
            fontSize: WearOsConstants.captionSize,
            color: Colors.white.withOpacity(0.6)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _WearOsSearchTrackOptionsScreen extends StatelessWidget {
  final Track track;
  final LibraryProvider library;

  const _WearOsSearchTrackOptionsScreen({
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

class _WearOsVoiceSearchScreen extends StatelessWidget {
  const _WearOsVoiceSearchScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mic, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Listening...',
                style: TextStyle(fontSize: WearOsConstants.titleSize),
              ),
              const SizedBox(height: 8),
              Text(
                'Say a song or artist',
                style: TextStyle(
                  fontSize: WearOsConstants.bodySize,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
