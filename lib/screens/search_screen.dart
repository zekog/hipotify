import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../providers/player_provider.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
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
    if (item is Track) return 'track_${item.id}';
    if (item is Artist) return 'artist_${item.id}';
    if (item is Album) return 'album_${item.id}';
    return '';
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
              : ListView.builder(
                  controller: _scrollController,
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

                    if (item is Track) {
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
                      );
                    }

                    return const SizedBox.shrink();
                  },
                ),
    );
  }
}
