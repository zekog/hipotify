import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/youtube_music_service.dart';
import '../services/spotify_service.dart';
import '../services/api_service.dart';
import '../services/hive_service.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../models/convertible_track.dart';
import '../models/album.dart';
import '../providers/library_provider.dart';
import '../utils/snackbar_helper.dart';

class PlaylistConverterScreen extends StatefulWidget {
  const PlaylistConverterScreen({super.key});

  @override
  State<PlaylistConverterScreen> createState() => _PlaylistConverterScreenState();
}

class _PlaylistConverterScreenState extends State<PlaylistConverterScreen> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  
  TrackSource _selectedSource = TrackSource.youtube;
  String? _playlistTitle;
  List<ConversionResult> _results = [];
  bool _isLoading = false;
  bool _isConverting = false;
  int _convertedCount = 0;
  int _totalCount = 0;
  
  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }
  
  Future<void> _fetchPlaylist() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      showSnackBar(context, 'Please enter a playlist URL');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _playlistTitle = null;
      _results = [];
    });

    try {
      if (_selectedSource == TrackSource.spotify) {
        await _fetchSpotifyPlaylist(url);
      } else {
        await _fetchYouTubePlaylist(url);
      }
    } catch (e) {
      if (mounted) showSnackBar(context, 'Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchYouTubePlaylist(String url) async {
    final playlistId = YouTubeMusicService.extractPlaylistId(url);
    if (playlistId == null) {
      if (mounted) showSnackBar(context, 'Invalid YouTube playlist URL');
      setState(() => _isLoading = false);
      return;
    }
    
    final playlist = await YouTubeMusicService.fetchPlaylist(playlistId);
    if (playlist == null) {
      if (mounted) showSnackBar(context, 'Could not fetch playlist. Make sure it\'s public.');
      setState(() => _isLoading = false);
      return;
    }
    
    if (mounted) {
      setState(() {
        _playlistTitle = playlist.title;
        _nameController.text = playlist.title;
        _results = playlist.tracks
            .map((t) => ConversionResult(sourceTrack: ConvertibleTrack.fromYouTube(t)))
            .toList();
        _isLoading = false;
      });
      showSnackBar(context, 'Found ${playlist.tracks.length} tracks');
    }
  }

  Future<void> _fetchSpotifyPlaylist(String url) async {
    final playlistId = SpotifyService.extractPlaylistId(url);
    if (playlistId == null) {
      if (mounted) showSnackBar(context, 'Invalid Spotify playlist URL');
      setState(() => _isLoading = false);
      return;
    }
    
    final playlist = await SpotifyService.fetchPlaylist(playlistId);
    if (playlist == null) {
      if (mounted) showSnackBar(context, 'Could not fetch playlist. Public playlists only.');
      setState(() => _isLoading = false);
      return;
    }
    
    if (mounted) {
      setState(() {
        _playlistTitle = playlist.title;
        _nameController.text = playlist.title;
        _results = playlist.tracks
            .map((t) => ConversionResult(sourceTrack: ConvertibleTrack.fromSpotify(t)))
            .toList();
        _isLoading = false;
      });
      showSnackBar(context, 'Found ${playlist.tracks.length} tracks');
    }
  }
  
  Future<void> _convertTracks() async {
    if (_results.isEmpty) return;
    
    setState(() {
      _isConverting = true;
      _convertedCount = 0;
      _totalCount = _results.length;
    });
    
    for (int i = 0; i < _results.length; i++) {
      if (!mounted || !_isConverting) break;
      
      final result = _results[i];
      if (result.tidalTrack != null) {
        setState(() => _convertedCount = i + 1);
        continue;
      }
      
      try {
        Track? bestMatch = await _findBestMatch(result.sourceTrack);
        
        setState(() {
          _results[i] = ConversionResult(
            sourceTrack: result.sourceTrack,
            tidalTrack: bestMatch,
            error: bestMatch == null ? 'Not found' : null,
          );
          _convertedCount = i + 1;
        });
        
        // Small delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        setState(() {
          _results[i] = ConversionResult(
            sourceTrack: result.sourceTrack,
            error: e.toString(),
          );
          _convertedCount = i + 1;
        });
      }
    }
    
    setState(() => _isConverting = false);
    
    final foundCount = _results.where((r) => r.tidalTrack != null).length;
    if (mounted) {
      showSnackBar(context, 'Conversion complete: $foundCount/${_results.length} tracks found');
    }
  }
  
  /// Tries multiple search queries to find the best matching track
  Future<Track?> _findBestMatch(ConvertibleTrack sourceTrack) async {
    // 1. ISRC Match (Highest Accuracy)
    if (sourceTrack.isrc != null) {
      try {
        final isrcResults = await ApiService.search(sourceTrack.isrc!, limit: 1, searchType: 'track');
        if (isrcResults.isNotEmpty && isrcResults.first is Track) {
          return isrcResults.first as Track;
        }
      } catch (e) {
        print("ISRC search failed: $e");
      }
    }

    // 2. Album Match (High Accuracy for common titles)
    if (sourceTrack.album != null && sourceTrack.artist != null) {
      Track? albumTrack = await _findTrackInAlbum(sourceTrack);
      if (albumTrack != null) return albumTrack;
    }

    // 3. Strict Match (Title + Artist + Duration Check)
    final queries = sourceTrack.searchQueries;
    for (final query in queries) {
      try {
        final searchResults = await ApiService.search(query, limit: 10, searchType: 'track');
        
        // Tier 3a: Strict Filtering
        for (final item in searchResults) {
          if (item is Track) {
             if (_isStrictMatch(sourceTrack, item)) {
               return item;
             }
          }
        }
        
        // Tier 3b: Relaxed Filtering (Legacy logic but with duration check if possible)
        for (final item in searchResults) {
          if (item is Track) {
            // Skip remixes/covers if not requested
            if (!sourceTrack.isRemix && _isRemix(item.title)) continue;
            if (!sourceTrack.isCover && _isCover(item.title)) continue;

            if (_isGoodMatch(sourceTrack, item)) {
              return item;
            }
          }
        }
      } catch (e) {
        print("Search failed for query '$query': $e");
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    return null;
  }

  Future<Track?> _findTrackInAlbum(ConvertibleTrack sourceTrack) async {
    try {
      // Search for the album
      final query = '${sourceTrack.album} ${sourceTrack.artist}';
      final results = await ApiService.search(query, limit: 5, searchType: 'album');
      
      for (final item in results) {
        if (item is Album) {
          // Check if album artist matches reasonably
          if (!_isFuzzyMatch(sourceTrack.artist!, item.artistName)) continue;

          // Fetch tracks for this album
          try {
            final tracks = await ApiService.getAlbumTracks(item.id);
            for (final track in tracks) {
              if (_isTitleMatch(sourceTrack.title, track.title)) {
                // Found it in the album!
                return track;
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
       print("Album match failed: $e");
    }
    return null;
  }

  bool _isStrictMatch(ConvertibleTrack source, Track tidal) {
    // 1. Artist Match
    if (source.artist != null && !_isFuzzyMatch(source.artist!, tidal.artistName)) {
      return false;
    }
    
    // 2. Duration Match (±5 seconds)
    if (source.duration != null) {
      final diff = (source.duration!.inSeconds - tidal.duration).abs();
      if (diff > 5) return false;
    }

    // 3. Remix/Cover Check
    if (!source.isRemix && _isRemix(tidal.title)) return false;
    if (!source.isCover && _isCover(tidal.title)) return false;

    // 4. Title Fuzzy Match
    return _isTitleMatch(source.title, tidal.title);
  }

  bool _isFuzzyMatch(String s1, String s2) {
    final k1 = _extractKeywords(s1.toLowerCase());
    final k2 = _extractKeywords(s2.toLowerCase());
    return k1.any((w) => k2.contains(w));
  }
  
  bool _isTitleMatch(String s1, String s2) {
     final clean1 = s1.toLowerCase().replaceAll(RegExp(r'\W'), '');
     final clean2 = s2.toLowerCase().replaceAll(RegExp(r'\W'), '');
     return clean1 == clean2 || clean1.contains(clean2) || clean2.contains(clean1);
  }
  
  /// Checks if a track title indicates it's a remix
  bool _isRemix(String title) {
    final lower = title.toLowerCase();
    return lower.contains('remix') ||
           lower.contains('bootleg') ||
           lower.contains('edit)') ||
           lower.contains('edit]') ||
           lower.contains('vip mix') ||
           lower.contains('club mix');
  }
  
  /// Checks if a track title indicates it's a cover
  bool _isCover(String title) {
    final lower = title.toLowerCase();
    return lower.contains('cover') ||
           lower.contains('acoustic version') ||
           lower.contains('unplugged');
  }
  
  /// Checks if the Tidal track is a good match for the source track
  bool _isGoodMatch(ConvertibleTrack sourceTrack, Track tidalTrack) {
    final sourceTitle = sourceTrack.title.toLowerCase();
    final tidalTitle = tidalTrack.title.toLowerCase();
    
    // Title should have significant overlap
    final sourceWords = _extractKeywords(sourceTitle);
    final tidalWords = _extractKeywords(tidalTitle);
    
    // At least 50% of the shorter title's words should match
    final minWords = sourceWords.length < tidalWords.length ? sourceWords : tidalWords;
    final maxWords = sourceWords.length >= tidalWords.length ? sourceWords : tidalWords;
    
    int matchCount = 0;
    for (final word in minWords) {
      if (maxWords.contains(word)) matchCount++;
    }
    
    if (minWords.isNotEmpty && matchCount / minWords.length < 0.5) {
      return false;
    }
    
    // If we have artist info, check for artist match
    if (sourceTrack.artist != null) {
      final sourceArtist = sourceTrack.artist!.toLowerCase();
      final sourceArtistWords = _extractKeywords(sourceArtist);
    final tidalArtist = tidalTrack.artistName.toLowerCase();
      final tidalArtistWords = _extractKeywords(tidalArtist);
      
      bool hasArtistMatch = sourceArtistWords.any((w) => tidalArtistWords.contains(w));
      if (!hasArtistMatch && sourceArtistWords.isNotEmpty) {
        // Artist mismatch - be more lenient if title is exact match
        // But if duration is known and wildly different, REJECT
         if (sourceTrack.duration != null) {
          final diff = (sourceTrack.duration!.inSeconds - tidalTrack.duration).abs();
          if (diff > 10) return false;
        }

        if (sourceTitle != tidalTitle) {
          return false;
        }
      }
    }
    
    return true;
  }
  
  /// Extracts significant keywords from a string
  List<String> _extractKeywords(String text) {
    final stopWords = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'from', 'is', 'it', 'as'};
    // Use unicode-aware matching to preserve non-ASCII characters (e.g., Polish chars)
    // Keep letters, numbers, and basic punctuation that might be relevant? 
    // Actually, just keep anything that is NOT a separator (space, dash, underscore)
    // and then remove pure punctuation.
    return text
        .split(RegExp(r'[\s\-_]+'))
        .map((w) => w.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').toLowerCase())
        .where((w) => w.length > 1 && !stopWords.contains(w))
        .toList();
  }

  
  Future<void> _savePlaylist() async {
    final tracks = _results
        .where((r) => r.tidalTrack != null)
        .map((r) => r.tidalTrack!)
        .toList();
    
    if (tracks.isEmpty) {
      showSnackBar(context, 'No tracks to save');
      return;
    }
    
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showSnackBar(context, 'Please enter a playlist name');
      return;
    }
    
    final playlist = Playlist(
      id: 'import_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      tracks: tracks,
    );
    
    await HiveService.savePlaylist(playlist);
    // LibraryProvider will auto-refresh on next build
    
    if (mounted) {
      showSnackBar(context, 'Playlist saved with ${tracks.length} tracks!');
      Navigator.pop(context);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist Converter'),
        actions: [
          if (_results.isNotEmpty && !_isConverting)
            TextButton.icon(
              onPressed: _savePlaylist,
              icon: const Icon(Icons.save),
              label: const Text('SAVE'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Disclaimer
          Container(
            width: double.infinity,
            color: Colors.amber.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Conversion is in beta. Matches may not be 100% accurate or complete.',
                    style: TextStyle(
                      color: Colors.amber[200],
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Source Selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<TrackSource>(
              segments: const [
                ButtonSegment(
                  value: TrackSource.youtube,
                  label: Text('YouTube Music'),
                  icon: Icon(Icons.play_circle_fill, color: Colors.red),
                ),
                ButtonSegment(
                  value: TrackSource.spotify,
                  label: Text('Spotify'),
                  icon: Icon(Icons.music_note, color: Colors.green),
                ),
              ],
              selected: {_selectedSource},
              onSelectionChanged: (Set<TrackSource> newSelection) {
                setState(() {
                  _selectedSource = newSelection.first;
                  _urlController.clear();
                  _nameController.clear();
                  _results = [];
                  _playlistTitle = null;
                });
              },
            ),
          ),
          
          // URL Input Section
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: _selectedSource == TrackSource.spotify 
                        ? 'Paste Spotify playlist URL...'
                        : 'Paste YouTube Music playlist URL...',
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _urlController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _fetchPlaylist(),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _fetchPlaylist,
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_isLoading ? 'Loading...' : 'Fetch Playlist'),
                ),
              ],
            ),
          ),
          
          // Playlist Name Input (after fetch)
          if (_playlistTitle != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Playlist Name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Convert Button and Progress
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isConverting ? null : _convertTracks,
                      icon: _isConverting
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(_isConverting 
                          ? 'Converting $_convertedCount/$_totalCount...' 
                          : 'Convert to Tidal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  if (_isConverting)
                    IconButton(
                      onPressed: () => setState(() => _isConverting = false),
                      icon: const Icon(Icons.stop),
                      tooltip: 'Stop',
                    ),
                ],
              ),
            ),
            
            // Progress indicator
            if (_isConverting)
              Padding(
                padding: const EdgeInsets.all(16),
                child: LinearProgressIndicator(
                  value: _totalCount > 0 ? _convertedCount / _totalCount : 0,
                ),
              ),
            
            // Results summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _StatChip(
                    label: 'Total',
                    count: _results.length,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Found',
                    count: _results.where((r) => r.tidalTrack != null).length,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Missing',
                    count: _results.where((r) => r.error != null).length,
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          ],
          
          // Track List
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.playlist_add, size: 64, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        Text(
                          'Paste a playlist URL to start',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        if (_selectedSource == TrackSource.youtube)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Supports: music.youtube.com & youtube.com',
                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            ),
                          ),
                        if (_selectedSource == TrackSource.spotify)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Supports: open.spotify.com/playlist/...',
                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return _ConversionResultTile(result: result);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ConversionResult {
  final ConvertibleTrack sourceTrack;
  final Track? tidalTrack;
  final String? error;
  
  ConversionResult({
    required this.sourceTrack,
    this.tidalTrack,
    this.error,
  });
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  
  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ConversionResultTile extends StatelessWidget {
  final ConversionResult result;
  
  const _ConversionResultTile({required this.result});
  
  @override
  Widget build(BuildContext context) {
    final isFound = result.tidalTrack != null;
    final isPending = result.tidalTrack == null && result.error == null;
    
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isPending 
              ? Colors.grey[800]
              : isFound 
                  ? Colors.green.withOpacity(0.2) 
                  : Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isPending ? Icons.hourglass_empty : (isFound ? Icons.check : Icons.close),
          color: isPending ? Colors.grey : (isFound ? Colors.green : Colors.red),
        ),
      ),
      title: Text(
        isFound ? result.tidalTrack!.title : result.sourceTrack.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isFound 
            ? result.tidalTrack!.artistName 
            : (result.sourceTrack.artist ?? result.error ?? 'Waiting...'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: result.error != null ? Colors.red[300] : null,
        ),
      ),
      trailing: isPending
          ? null
          : isFound
              ? const Icon(Icons.music_note, color: Colors.green)
              : IconButton(
                  icon: const Icon(Icons.create),
                  tooltip: 'Edit / Manual Match', // Future feature
                  onPressed: () {
                    // Placeholder for future manual matching
                  },
                ),
    );
  }
}
