import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/hive_service.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_service.dart';
import '../utils/snackbar_helper.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';
import '../models/playlist.dart';
import '../models/tidal_playlist.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

// Public class to access SearchScreen state
class SearchScreenStateAccessor {
  static void resetToHistory(GlobalKey<State<SearchScreen>> key) {
    final state = key.currentState;
    if (state is _SearchScreenState) {
      state._resetSearchState();
    }
  }
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  
  List<dynamic> _results = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 20;
  bool _hasMore = true;
  String _lastQuery = '';
  final Set<String> _resultIds = {};
  List<String> _searchHistory = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _resetSearchState();
  }



  void _resetSearchState() {
    if (!mounted) return;
    setState(() {
      _results = [];
      _resultIds.clear();
      _offset = 0;
      _hasMore = true;
      _lastQuery = '';
      _isLoading = false;
      _isLoadingMore = false;
      _searchHistory = HiveService.getSearchHistory();
      _searchController.clear();
    });
  }

  // Public method to reset search state
  void resetToHistory() {
    _resetSearchState();
  }

  void _loadSearchHistory() {
    setState(() {
      _searchHistory = HiveService.getSearchHistory();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore && _lastQuery.isNotEmpty) {
        _loadMore();
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    print("SearchScreen: Performing search for '$query'");
    
    // Add to search history
    await HiveService.addToSearchHistory(query);
    _loadSearchHistory();
    
    setState(() {
      _isLoading = true;
      _results = [];
      _resultIds.clear();
      _offset = 0;
      _hasMore = true;
      _lastQuery = query;
    });

    try {
      final results = await ApiService.search(query, offset: _offset, limit: _limit);
      setState(() {
        for (var item in results) {
          final id = _getItemId(item);
          if (id.isNotEmpty && !_resultIds.contains(id)) {
            _results.add(item);
            _resultIds.add(id);
          }
        }
        _offset += results.length;
        if (results.isEmpty || results.length < _limit) _hasMore = false;
      });
    } catch (e) {
      showSnackBar(context, 'Search failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final results = await ApiService.search(_lastQuery, offset: _offset, limit: _limit);
      setState(() {
        int addedCount = 0;
        for (var item in results) {
          final id = _getItemId(item);
          if (id.isNotEmpty && !_resultIds.contains(id)) {
            _results.add(item);
            _resultIds.add(id);
            addedCount++;
          }
        }
        _offset += results.length;
        // If no new items were added, or results are empty/less than limit, stop loading
        if (results.isEmpty || results.length < _limit || addedCount == 0) {
          _hasMore = false;
        }
      });
    } catch (e) {
      print("Error loading more: $e");
      setState(() => _hasMore = false); // Stop on error to avoid loops
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  String _getItemId(dynamic item) {
    if (item is Artist) return 'artist_${item.id}';
    if (item is Album) return 'album_${item.id}';
    if (item is TidalPlaylist) return 'playlist_${item.id}';
    return '';
  }

  Future<String?> _promptForPlaylistName(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    final name = result?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _showAddToPlaylistMenu(BuildContext context, Track track, LibraryProvider library) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Center(
          child: Material(
            type: MaterialType.card,
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF1E1E1E),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
              child: Consumer<LibraryProvider>(
                builder: (context, lib, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Add to playlist',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.add, color: Colors.white),
                              title: const Text('New playlist', style: TextStyle(color: Colors.white)),
                              onTap: () async {
                                Navigator.of(context).pop();
                                final name = await _promptForPlaylistName(context);
                                if (name == null) return;

                                try {
                                  final playlist = await library.createPlaylist(name);
                                  await library.addTrackToPlaylist(playlist.id, track);
                                  if (context.mounted) {
                                    showSnackBar(context, 'Added to "${playlist.name}"');
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    showSnackBar(context, 'Failed: $e');
                                  }
                                }
                              },
                            ),
                            if (lib.playlists.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No playlists yet',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            else
                              ...lib.playlists.map(
                                (p) {
                                  final isInPlaylist = library.isTrackInPlaylist(p.id, track.id);
                                  return ListTile(
                                    leading: Icon(
                                      isInPlaylist ? Icons.check_circle : Icons.queue_music,
                                      color: isInPlaylist ? Theme.of(context).primaryColor : Colors.white,
                                    ),
                                    title: Text(p.name, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(
                                      '${p.tracks.length} tracks',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    onTap: () async {
                                      Navigator.of(context).pop();
                                      try {
                                        final wasAdded = await library.toggleTrackInPlaylist(p.id, track);
                                        if (context.mounted) {
                                          showSnackBar(
                                            context,
                                            wasAdded
                                                ? 'Added to "${p.name}"'
                                                : 'Removed from "${p.name}"',
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          showSnackBar(context, 'Failed: $e');
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: false,
          decoration: const InputDecoration(
            hintText: 'Search songs, artists, albums...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          onSubmitted: _performSearch,
          textInputAction: TextInputAction.search,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _performSearch(_searchController.text),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty && _lastQuery.isNotEmpty
              ? const Center(child: Text("No results found"))
              : _results.isEmpty && _lastQuery.isEmpty
                  ? _buildSearchHistory()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                        bottom: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: _results.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _results.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                    final item = _results[index];
                    
                    if (item is Artist) {
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: CachedNetworkImage(
                            imageUrl: item.pictureUrl,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.grey),
                          ),
                        ),
                        title: Text(item.name, style: const TextStyle(color: Colors.white)),
                        subtitle: const Text("Artist", style: TextStyle(color: Colors.grey)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => ArtistScreen(artistId: item.id)),
                        ),
                      );
                    }

                    if (item is Album) {
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: item.coverUrl,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const Icon(Icons.album, color: Colors.grey),
                          ),
                        ),
                        title: Text(item.title, style: const TextStyle(color: Colors.white)),
                        subtitle: Text("Album • ${item.artistName}", style: const TextStyle(color: Colors.grey)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => AlbumScreen(albumId: item.id)),
                        ),
                      );
                    }

                    if (item is TidalPlaylist) {
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: item.imageUrl,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const Icon(Icons.playlist_play, color: Colors.grey),
                          ),
                        ),
                        title: Text(item.title, style: const TextStyle(color: Colors.white)),
                        subtitle: Text("Playlist • ${item.creatorName ?? 'Tidal'} • ${item.numberOfTracks} tracks", style: const TextStyle(color: Colors.grey)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => PlaylistScreen(playlistId: item.id)),
                        ),
                        trailing: Consumer<LibraryProvider>(
                          builder: (context, library, _) {
                            final isSaved = library.isPlaylistSaved(item.id);
                            return PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white),
                              onSelected: (value) async {
                                if (value == 'save') {
                                  await library.toggleSavePlaylist(item);
                                  if (context.mounted) {
                                    showSnackBar(
                                      context,
                                      library.isPlaylistSaved(item.id)
                                          ? 'Saved to library!'
                                          : 'Removed from library',
                                    );
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'save',
                                  child: Row(
                                    children: [
                                      Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                                      const SizedBox(width: 8),
                                      Text(isSaved ? 'Remove from library' : 'Save to library'),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    }

                    if (item is Track) {
                      return Consumer<LibraryProvider>(
                        builder: (context, library, _) {
                          final isLiked = library.isLiked(item.id);
                          final isDownloaded = library.downloadedSongs.any((t) => t.id == item.id);
                          
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: item.coverUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => const Icon(Icons.music_note, color: Colors.grey),
                              ),
                            ),
                            title: Text(item.title, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(item.artistName, style: const TextStyle(color: Colors.grey)),
                            onTap: () => Provider.of<PlayerProvider>(context, listen: false).playTrack(item),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white),
                              onSelected: (value) async {
                                if (value == 'favorite') {
                                  await library.toggleLike(item);
                                  if (context.mounted) {
                                    showSnackBar(
                                      context,
                                      library.isLiked(item.id)
                                          ? 'Added to favorites!'
                                          : 'Removed from favorites',
                                    );
                                  }
                                } else if (value == 'playlist') {
                                  _showAddToPlaylistMenu(context, item, library);
                                } else if (value == 'download' && !isDownloaded) {
                                  try {
                                    await DownloadService.downloadTrack(
                                      item,
                                      onProgress: (received, total) {},
                                    );
                                    if (context.mounted) {
                                      library.refreshDownloads();
                                      showSnackBar(context, 'Download started');
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      showSnackBar(context, 'Download failed: $e');
                                    }
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'favorite',
                                  child: Row(
                                    children: [
                                      Icon(isLiked ? Icons.favorite : Icons.favorite_border),
                                      const SizedBox(width: 8),
                                      Text(isLiked ? 'Remove from favorites' : 'Add to favorites'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'playlist',
                                  child: Row(
                                    children: [
                                      Icon(Icons.playlist_add),
                                      SizedBox(width: 8),
                                      Text('Add to playlist'),
                                    ],
                                  ),
                                ),
                                if (!isDownloaded)
                                  const PopupMenuItem(
                                    value: 'download',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download),
                                        SizedBox(width: 8),
                                        Text('Download'),
                                      ],
                                    ),
                                  ),
                              ],
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

  Widget _buildSearchHistory() {
    if (_searchHistory.isEmpty) {
      return const Center(
        child: Text(
          'No search history',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchHistory.length,
      itemBuilder: (context, index) {
        final query = _searchHistory[index];
        return ListTile(
          leading: const Icon(Icons.history, color: Colors.grey),
          title: Text(query, style: const TextStyle(color: Colors.white)),
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            onPressed: () async {
              await HiveService.removeFromSearchHistory(query);
              _loadSearchHistory();
            },
          ),
          onTap: () {
            _searchController.text = query;
            _performSearch(query);
          },
        );
      },
    );
  }
}
