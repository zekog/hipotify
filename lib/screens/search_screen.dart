import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/spotify_service.dart';
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
  final Set<String> _seenAlbumTitles = {};
  final Set<String> _seenArtistNames = {};
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
      _seenAlbumTitles.clear();
      _seenArtistNames.clear();
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
      _seenAlbumTitles.clear();
      _seenArtistNames.clear();
      _offset = 0;
      _hasMore = true;
      _lastQuery = query;
    });

    // Check if the query is a link
    if (await _handleLinkQuery(query)) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await ApiService.search(query, offset: _offset, limit: _limit);
      setState(() {
        for (var item in results) {
          final id = _getItemId(item);
          if (id.isNotEmpty && !_resultIds.contains(id)) {
            bool isDuplicate = false;
            if (item is Artist) {
               final key = item.name.trim().toLowerCase();
               if (_seenArtistNames.contains(key)) {
                 isDuplicate = true;
               } else {
                 _seenArtistNames.add(key);
               }
            } else if (item is Album) {
               final key = item.title.trim().toLowerCase();
               if (_seenAlbumTitles.contains(key)) {
                 isDuplicate = true;
               } else {
                 _seenAlbumTitles.add(key);
               }
            }

            if (!isDuplicate) {
              _results.add(item);
              _resultIds.add(id);
            }
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

  Future<bool> _handleLinkQuery(String query) async {
    final cleanQuery = query.trim();
    
    // Spotify Regex
    final spotifyRegex = RegExp(r'open\.spotify\.com/(album|artist|track|playlist)/([a-zA-Z0-9]+)');
    // Tidal Regex
    final tidalRegex = RegExp(r'tidal\.com/([a-zA-Z0-9/]*)(album|artist|track|playlist)/([a-zA-Z0-9]+)');

    String? type;
    String? id;
    bool isSpotify = false;

    final spotifyMatch = spotifyRegex.firstMatch(cleanQuery);
    if (spotifyMatch != null) {
      type = spotifyMatch.group(1);
      id = spotifyMatch.group(2);
      isSpotify = true;
    } else {
      final tidalMatch = tidalRegex.firstMatch(cleanQuery);
      if (tidalMatch != null) {
        type = tidalMatch.group(2);
        id = tidalMatch.group(3);
      }
    }

    if (type != null && id != null) {
      print("SearchScreen: Detected link - Type: $type, ID: $id, Spotify: $isSpotify");
      
      // For Spotify links, fetch metadata and search
      if (isSpotify) {
        await _handleSpotifyLink(cleanQuery, type);
        return true;
      }
      
      // For Tidal links, navigate directly
      _navigateToEntity(type, id);
      return true;
    }

    return false;
  }

  Future<void> _handleSpotifyLink(String spotifyUrl, String type) async {
    if (!mounted) return;
    
    showSnackBar(context, 'Fetching Spotify metadata...');
    
    try {
      String searchQuery = '';
      String? searchType = type;
      String? isrc;
      
      // Use advanced fetching for tracks
      if (type == 'track') {
        final idMatch = RegExp(r'track/([a-zA-Z0-9]+)').firstMatch(spotifyUrl);
        final id = idMatch?.group(1);
        if (id != null) {
           final spotifyTrack = await SpotifyService.fetchTrack(id);
           if (spotifyTrack != null) {
              if (spotifyTrack.isrc != null) {
                isrc = spotifyTrack.isrc;
                searchQuery = spotifyTrack.isrc!; 
                print("SearchScreen: Found ISRC: $isrc");
              } else {
                searchQuery = '${spotifyTrack.title} ${spotifyTrack.artist ?? ''}';
              }
           }
        }
      } 
      
      // Fallback to oEmbed if advanced fetch failed or not a track
      if (searchQuery.isEmpty) {
        final metadata = await ApiService.getSpotifyMetadata(spotifyUrl);
        if (metadata == null) {
          if (mounted) showSnackBar(context, 'Could not fetch Spotify metadata');
          return;
        }
        
        final title = metadata['title'] ?? '';
        final artist = metadata['artist'];
        
        if (type == 'track') {
          searchQuery = artist != null ? '$title $artist' : title;
        } else if (type == 'album') {
          searchQuery = artist != null ? '$title $artist' : title;
        } else if (type == 'artist') {
          searchQuery = title;
        } else if (type == 'playlist') {
          searchQuery = title;
        } else {
          searchQuery = title;
        }
      }
      
      print("SearchScreen: Spotify search - Query: '$searchQuery', Type: $type, ISRC: $isrc");
      
      // Update search field
      _searchController.text = searchQuery;
      _lastQuery = searchQuery; // Important to set this for comparison
      
      // If we have an ISRC, try that first
      if (isrc != null) {
         try {
           final isrcResults = await ApiService.search(isrc, limit: 1, searchType: 'track');
           if (isrcResults.isNotEmpty && isrcResults.first is Track) {
              final track = isrcResults.first as Track;
              if (mounted) {
                _searchController.text = '${track.title} ${track.artistName}'; // Show readable text
                setState(() {
                  _results = [track];
                  _resultIds.clear();
                  _resultIds.add(track.id);
                  _hasMore = false;
                  _isLoading = false;
                });
                showSnackBar(context, 'Found exact match via ISRC!');
                return;
              }
           } else {
             print("SearchScreen: ISRC search returned no results. Trying Odesli fallback...");
             if (mounted) showSnackBar(context, 'ISRC lookup failed. Trying Odesli...');
             
             // Odesli Fallback
             final odesliData = await ApiService.resolveTidalTrackFromOdesli(spotifyUrl);
             if (odesliData != null) {
               final tidalId = odesliData['id'] as String;
               final title = odesliData['title'] as String;
               final artist = odesliData['artist'] as String;
               final cover = odesliData['cover'] as String?;
               
                print("SearchScreen: Odesli found Tidal ID: $tidalId ('$title' by '$artist')");
                
                // Fetch in background for playback with metadata override
                final success = await _fetchAndPlayTrack(tidalId, metadataOverride: {
                  'title': title,
                  'artistName': artist,
                  'cover': cover,
                });

                if (success) {
                  // Create track object from Odesli data
                  final track = Track(
                    id: tidalId,
                    title: title,
                    artistName: artist,
                    artistId: '', 
                    albumId: '', 
                    albumTitle: 'Single', 
                    albumCoverUuid: cover ?? '', 
                    duration: 0, 
                  );

                  if (mounted) {
                      _searchController.text = '${track.title} ${track.artistName}';
                      setState(() {
                        _results = [track];
                        _resultIds.clear();
                        _resultIds.add(track.id);
                        _hasMore = false;
                        _isLoading = false;
                      });
                      showSnackBar(context, 'Found match via Odesli!');
                  }
                  return; // Exit ONLY if playback matched and started
                } else {
                  print("SearchScreen: Odesli match found but Playback failed (likely region locked). Falling back to text search.");
                  if (mounted) {
                     showSnackBar(context, 'Exact match region-locked. Searching closest match...');
                     // Fallback to text search using the high-quality metadata we got from Odesli
                     _searchController.text = '$title $artist';
                     await _performSearch('$title $artist');
                     return;
                  }
                }
             }
           }
         } catch (e) {
           print("ISRC search failed, falling back to text: $e");
         }
      }

      // Perform regular search if ISRC failed or wasn't available
      await _performSearch(searchQuery);
      
    } catch (e) {
      print("Error handling Spotify link: $e");
      if (mounted) showSnackBar(context, 'Error: $e');
    }
  }

  void _navigateToEntity(String type, String id) {
    if (!mounted) return;

    Widget? screen;
    if (type == 'album') {
      screen = AlbumScreen(albumId: id);
    } else if (type == 'artist') {
      screen = ArtistScreen(artistId: id);
    } else if (type == 'playlist') {
      screen = PlaylistScreen(playlistId: id);
    } else if (type == 'track') {
      _fetchAndPlayTrack(id);
      return;
    }

    if (screen != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => screen!),
      );
    }
  }

  Future<bool> _fetchAndPlayTrack(String trackId, {Map<String, dynamic>? metadataOverride}) async {
    try {
      final streamMetadata = await ApiService.getStreamMetadata(trackId);
      
      // Merge metadata if provided
      final finalMetadata = Map<String, dynamic>.from(streamMetadata);
      if (metadataOverride != null) {
        finalMetadata.addAll(metadataOverride);
      }

      final track = Track.fromJson(finalMetadata);
      
      if (mounted) {
        Provider.of<PlayerProvider>(context, listen: false).playTrack(track);
        showSnackBar(context, "Playing: ${track.title}");
        return true;
      }
    } catch (e) {
      print("Error fetching track for link: $e");
      // Don't show snackbar here, let caller handle fallback
    }
    return false;
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
            bool isDuplicate = false;
            if (item is Artist) {
               final key = item.name.trim().toLowerCase();
               if (_seenArtistNames.contains(key)) {
                 isDuplicate = true;
               } else {
                 _seenArtistNames.add(key);
               }
            } else if (item is Album) {
               final key = item.title.trim().toLowerCase();
               if (_seenAlbumTitles.contains(key)) {
                 isDuplicate = true;
               } else {
                 _seenAlbumTitles.add(key);
               }
            }

            if (!isDuplicate) {
              _results.add(item);
              _resultIds.add(id);
              addedCount++;
            }
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
    final textColor = Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Center(
          child: Material(
            type: MaterialType.card,
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).cardColor,
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
                             Expanded(
                              child: Text(
                                'Add to playlist',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
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
                              leading: Icon(Icons.add, color: textColor),
                              title: Text('New playlist', style: TextStyle(color: textColor)),
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
                                      color: isInPlaylist ? Theme.of(context).primaryColor : textColor,
                                    ),
                                    title: Text(p.name, style: TextStyle(color: textColor)),
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
    final textColor = Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white;
    final hintColor = Theme.of(context).brightness == Brightness.light ? Colors.grey[600] : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search songs, artists, albums...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: hintColor),
          ),
          style: TextStyle(color: textColor, fontSize: 18),
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
                        title: Text(item.name, style: TextStyle(color: textColor)),
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
                        title: Text(item.title, style: TextStyle(color: textColor)),
                        subtitle: Text("Album • ${item.artistName}", style: const TextStyle(color: Colors.grey)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => AlbumScreen(albumId: item.id, initialAlbum: item)),
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
                        title: Text(item.title, style: TextStyle(color: textColor)),
                        subtitle: Text("Playlist • ${item.creatorName ?? 'Tidal'} • ${item.numberOfTracks} tracks", style: const TextStyle(color: Colors.grey)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => PlaylistScreen(playlistId: item.id)),
                        ),
                        trailing: Consumer<LibraryProvider>(
                          builder: (context, library, _) {
                            final isSaved = library.isPlaylistSaved(item.id);
                            return PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: textColor),
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
                                      Icon(isSaved ? Icons.bookmark : Icons.bookmark_border, color: Colors.black),
                                      const SizedBox(width: 8),
                                      const Text('Toggle Library', style: TextStyle(color: Colors.black)),
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
                            title: Text(item.title, style: TextStyle(color: textColor)),
                            subtitle: Text(item.artistName, style: const TextStyle(color: Colors.grey)),
                            onTap: () => Provider.of<PlayerProvider>(context, listen: false).playTrack(item),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: textColor),
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
                                      Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: Colors.black),
                                      const SizedBox(width: 8),
                                      Text(isLiked ? 'Remove from favorites' : 'Add to favorites', style: const TextStyle(color: Colors.black)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'playlist',
                                  child: Row(
                                    children: [
                                      Icon(Icons.playlist_add, color: Colors.black),
                                      SizedBox(width: 8),
                                      Text('Add to playlist', style: TextStyle(color: Colors.black)),
                                    ],
                                  ),
                                ),
                                if (!isDownloaded)
                                  const PopupMenuItem(
                                    value: 'download',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download, color: Colors.black),
                                        SizedBox(width: 8),
                                        Text('Download', style: TextStyle(color: Colors.black)),
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
    final textColor = Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white;
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
          title: Text(query, style: TextStyle(color: textColor)),
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
