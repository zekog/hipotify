import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'hive_service.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/lyrics.dart';
import '../models/tidal_playlist.dart';

class ApiService {
  
  static String get _baseUrl {
    final url = HiveService.apiUrl;
    if (url == null || url.isEmpty) {
      throw Exception("API URL not set");
    }
    // Remove trailing slash if present
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static Map<String, String> get _headers => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    'X-Client': 'BiniLossless/v3.4',
  };

  static Future<List<dynamic>> search(String query, {int offset = 0, int limit = 50}) async {
    try {
      final List<dynamic> allItems = [];
      final Set<String> seenIds = {};

      Future<void> performSearch(String searchTerms, String typeParam, [String? inferredType]) async {
        final encoded = Uri.encodeComponent(searchTerms);
        final uri = Uri.parse('$_baseUrl/search/?$typeParam=$encoded&offset=$offset&index=$offset&limit=$limit');
        print("API Search ($typeParam) for '$searchTerms': $uri");
        final response = await http.get(uri, headers: _headers);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final resultData = data['data'] ?? data;
          
          void scan(dynamic value, [String? currentInferredType]) {
            if (value == null) return;
            if (value is List) {
              for (var item in value) scan(item, currentInferredType);
              return;
            }
            if (value is Map) {
              final item = value['item'] ?? value;
              String? type = item['type']?.toString().toLowerCase() ?? currentInferredType;
              final id = item['id']?.toString() ?? item['uuid']?.toString();

              if (id != null) {
                if (type == null || type == 'main' || type == 'contributor') {
                  if (item['duration'] != null) type = 'track';
                  else if (item['artistRoles'] != null || item['artistTypes'] != null || item['picture'] != null) type = 'artist';
                  else if (item['uuid'] != null || item['creator'] != null) type = 'playlist';
                  else if (item['cover'] != null || item['releaseDate'] != null || item['numberOfTracks'] != null) type = 'album';
                  else if (item['title'] != null && item['artist'] != null) type = 'track';
                }

                // Refine type based on specific fields
                if (item['uuid'] != null || item['creator'] != null) {
                  type = 'playlist';
                } else if (item['numberOfTracks'] != null && type != 'playlist') {
                  type = 'album';
                } else if (item['duration'] != null && type != 'album' && type != 'playlist') {
                  type = 'track';
                }

                if (type == 'track' || type == 'song' || type == 'artist' || type == 'album' || type == 'playlist') {
                  final uniqueId = '${type}_$id';
                  if (!seenIds.contains(uniqueId)) {
                    seenIds.add(uniqueId);
                    if (type == 'artist') allItems.add(Artist.fromJson(item));
                    else if (type == 'album') allItems.add(Album.fromJson(item));
                    else if (type == 'playlist') allItems.add(TidalPlaylist.fromJson(item));
                    else allItems.add(Track.fromJson(item));
                  }
                }
              }

              value.forEach((key, val) {
                if (key == 'item') return;
                String? nextInferredType = currentInferredType;
                if (key == 'artists') nextInferredType = 'artist';
                else if (key == 'albums') nextInferredType = 'album';
                else if (key == 'tracks' || key == 'songs') nextInferredType = 'track';
                else if (key == 'playlists') nextInferredType = 'playlist';
                scan(val, nextInferredType);
              });
            }
          }
          scan(resultData, inferredType);
        }
      }

      final List<Future<void>> searchTasks = [
        performSearch(query, 's', 'track'),
        performSearch(query, 'a', 'artist'),
        performSearch(query, 'al', 'album'),
        performSearch(query, 'p', 'playlist'),
      ];

      // 0. MusicBrainz Mapping for Latin Queries
      final normalizedQuery = query.toLowerCase().trim();
      final bool queryIsLatin = RegExp(r'^[a-zA-Z0-9\s\p{P}]+$', unicode: true).hasMatch(normalizedQuery);
      if (queryIsLatin) {
        final originalName = await _getMusicBrainzOriginalName(query);
        if (originalName != null && originalName.toLowerCase() != normalizedQuery) {
          print("ApiService: MusicBrainz found original name: $originalName");
          searchTasks.add(performSearch(originalName, 's', 'track'));
          searchTasks.add(performSearch(originalName, 'a', 'artist'));
          searchTasks.add(performSearch(originalName, 'al', 'album'));
          searchTasks.add(performSearch(originalName, 'p', 'playlist'));
        }
      }

      await Future.wait(searchTasks);

      print("API Search Found ${allItems.length} items total. Injecting history and re-ranking...");

      // 1. Fetch History
      final recentTracks = HiveService.getRecentlyPlayed();
      final recentArtists = HiveService.getRecentArtists();
      final recentAlbums = HiveService.getRecentAlbums();

      final recentTrackIds = recentTracks.map((t) => t.id.toString().trim()).toSet();
      final recentArtistIds = recentArtists.map((a) => a.id.toString().trim()).toSet();
      final recentAlbumIds = recentAlbums.map((a) => a.id.toString().trim()).toSet();

      // 2. History Injection: If query matches something in history, ensure it's in allItems
      
      void injectFromHistory<T>(List<T> history, String Function(T) getTitle, String Function(T) getId, String typePrefix) {
        for (var item in history) {
          final title = getTitle(item).toLowerCase();
          final id = getId(item).toString().trim();
          final uniqueId = '${typePrefix}_$id';
          
          if (title.contains(normalizedQuery) && !seenIds.contains(uniqueId)) {
            print("DEBUG: [INJECTION] Injecting $uniqueId ('${getTitle(item)}') from history");
            allItems.add(item);
            seenIds.add(uniqueId);
          }
        }
      }

      injectFromHistory<Track>(recentTracks, (t) => t.title, (t) => t.id, 'track');
      injectFromHistory<Artist>(recentArtists, (a) => a.name, (a) => a.id, 'artist');
      injectFromHistory<Album>(recentAlbums, (al) => al.title, (al) => al.id, 'album');

      // 3. Scoring Algorithm
      double calculateScore(dynamic item, int originalIndex) {
        double score = 1000.0 / (originalIndex + 1); // Base score from original rank
        
        String itemId = "";
        String itemTitle = "";
        String itemArtist = "";
        String itemAlbum = "";
        if (item is Track) { 
          itemId = item.id.toString().trim(); 
          itemTitle = item.title; 
          itemArtist = item.artistName;
          itemAlbum = item.albumTitle;
        }
        else if (item is Artist) { 
          itemId = item.id.toString().trim(); 
          itemTitle = item.name; 
        }
        else if (item is Album) { 
          itemId = item.id.toString().trim(); 
          itemTitle = item.title; 
          itemArtist = item.artistName;
        }
        else if (item is TidalPlaylist) {
          itemId = item.id.toString().trim();
          itemTitle = item.title;
        }

        final lowerTitle = itemTitle.toLowerCase();
        final lowerArtist = itemArtist.toLowerCase();
        final lowerAlbum = itemAlbum.toLowerCase();

        // 1. Title Match Bonus
        if (lowerTitle == normalizedQuery) {
          score += 3000.0;
        } else if (lowerTitle.startsWith(normalizedQuery)) {
          score += 1000.0;
        } else if (lowerTitle.contains(normalizedQuery)) {
          score += 500.0;
        }

        // 2. Artist Match Bonus
        if (lowerArtist.isNotEmpty) {
          if (lowerArtist == normalizedQuery) {
            score += 2000.0;
          } else if (lowerArtist.startsWith(normalizedQuery)) {
            score += 1000.0;
          } else if (lowerArtist.contains(normalizedQuery)) {
            score += 500.0;
          }
        }

        // 3. Album Match Bonus
        if (lowerAlbum.isNotEmpty) {
          if (lowerAlbum == normalizedQuery) {
            score += 1500.0;
          } else if (lowerAlbum.startsWith(normalizedQuery)) {
            score += 800.0;
          } else if (lowerAlbum.contains(normalizedQuery)) {
            score += 400.0;
          }
        }

        // 4. Contextual Boost (e.g., track's artist matches query)
        if (item is Track || item is Album) {
          if (lowerArtist == normalizedQuery) score += 1000.0;
          if (lowerAlbum == normalizedQuery) score += 500.0;
        }

        // 5. Transliteration Match (Script Match)
        // If query is Latin and result contains Japanese/Korean characters, 
        // it's likely a transliteration match from the API.
        final bool queryIsLatin = RegExp(r'^[a-zA-Z0-9\s\p{P}]+$', unicode: true).hasMatch(normalizedQuery);
        if (queryIsLatin) {
          final bool hasNonLatin = RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]', unicode: true).hasMatch(itemTitle) || 
                                   RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]', unicode: true).hasMatch(itemArtist);
          if (hasNonLatin) {
            score += 2000.0; // Trust the API's transliteration match
          }
        }

        // 6. History Match Bonus (The "Spotify" logic)
        if (item is Track) {
          if (recentTrackIds.contains(itemId)) {
            score += 10000.0; // Massive boost for recently played
          } else if (recentArtistIds.contains(item.artistId.toString().trim())) {
            score += 3000.0;
          } else if (recentAlbumIds.contains(item.albumId.toString().trim())) {
            score += 2000.0;
          }
          score += (item.popularity ?? 0) * 10.0;
        } else if (item is Artist) {
          if (recentArtistIds.contains(itemId)) {
            score += 10000.0;
          }
          score += (item.popularity ?? 0) * 10.0;
        } else if (item is Album) {
          if (recentAlbumIds.contains(itemId)) {
            score += 10000.0;
          } else if (recentArtistIds.contains(item.artistId.toString().trim())) {
            score += 3000.0;
          }
          score += (item.popularity ?? 0) * 10.0;
        } else if (item is TidalPlaylist) {
          // No history for public playlists yet
          score += 1200.0; // Base boost for playlists
        }

        return score;
      }

      // Create a map of items to their scores
      final Map<dynamic, double> scores = {};
      for (int i = 0; i < allItems.length; i++) {
        scores[allItems[i]] = calculateScore(allItems[i], i);
      }

      // Sort by score descending
      allItems.sort((a, b) => scores[b]!.compareTo(scores[a]!));

      print("DEBUG: Top 5 Search Results after re-ranking:");
      for (int i = 0; i < min(5, allItems.length); i++) {
        final item = allItems[i];
        String name = "";
        String id = "";
        if (item is Track) { name = item.title; id = item.id; }
        else if (item is Artist) { name = item.name; id = item.id; }
        else if (item is Album) { name = item.title; id = item.id; }
        else if (item is TidalPlaylist) { name = item.title; id = item.id; }
        print("DEBUG: #$i: $name ($id) - Score: ${scores[item]}");
      }

      return allItems;
    } catch (e) {
      print("API Search Exception: $e");
    }
    return [];
  }

  static Future<Artist> getArtistDetails(String artistId) async {
    final uri = Uri.parse('$_baseUrl/artist?f=$artistId');
    final response = await http.get(uri, headers: _headers);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final artistData = _findArtistInResponse(data, artistId);
      if (artistData != null) {
        return artistData;
      }
    }

    final fallbackUri = Uri.parse('$_baseUrl/artist?id=$artistId');
    final fallbackResponse = await http.get(fallbackUri, headers: _headers);
    if (fallbackResponse.statusCode == 200) {
      final data = jsonDecode(fallbackResponse.body);
      final artistData = _findArtistInResponse(data, artistId);
      if (artistData != null) {
        return artistData;
      }
    }

    throw Exception("Failed to get artist details (Status: ${response.statusCode})");
  }

  static Artist? _findArtistInResponse(dynamic data, String artistId) {
    Artist? foundArtist;
    void scan(dynamic value) {
      if (foundArtist != null || value == null) {
        return;
      }
      if (value is List) {
        for (var item in value) {
          scan(item);
        }
        return;
      }
      if (value is Map) {
        final item = value['item'] ?? value;
        if (item['id']?.toString() == artistId && (item['type']?.toString().toLowerCase() == 'artist' || item['name'] != null)) {
          foundArtist = Artist.fromJson(item);
          return;
        }
        value.forEach((key, val) => scan(val));
      }
    }
    scan(data['data'] ?? data);
    return foundArtist;
  }

  static Future<List<Track>> getArtistTopTracks(String artistId) async {
    // Top tracks are usually in the main artist response modules
    final uri = Uri.parse('$_baseUrl/artist?f=$artistId');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _scanForTracks(data);
    }
    return [];
  }

  static Future<Album> getAlbumDetails(String albumId) async {
    final uri = Uri.parse('$_baseUrl/album?id=$albumId');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final albumData = _findAlbumInResponse(data, albumId);
      if (albumData != null) {
        return albumData;
      }
    }
    throw Exception("Failed to get album details (Status: ${response.statusCode})");
  }

  static Album? _findAlbumInResponse(dynamic data, String albumId) {
    Album? foundAlbum;
    void scan(dynamic value) {
      if (foundAlbum != null || value == null) {
        return;
      }
      if (value is List) {
        for (var item in value) {
          scan(item);
        }
        return;
      }
      if (value is Map) {
        final item = value['item'] ?? value;
        if (item['id']?.toString() == albumId && (item['type']?.toString().toLowerCase() == 'album' || item['title'] != null)) {
          foundAlbum = Album.fromJson(item);
          return;
        }
        value.forEach((key, val) => scan(val));
      }
    }
    scan(data['data'] ?? data);
    return foundAlbum;
  }

  static Future<List<Track>> getAlbumTracks(String albumId) async {
    final uri = Uri.parse('$_baseUrl/album?id=$albumId');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _scanForTracks(data);
    }
    return [];
  }

  static Future<TidalPlaylist> getPlaylistDetails(String playlistId) async {
    final uri = Uri.parse('$_baseUrl/playlist/?id=$playlistId');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final playlistData = data['playlist'] ?? data['data'] ?? data;
      return TidalPlaylist.fromJson(playlistData);
    }
    throw Exception("Failed to get playlist details (Status: ${response.statusCode})");
  }

  static Future<List<Track>> getPlaylistTracks(String playlistId) async {
    final uri = Uri.parse('$_baseUrl/playlist/?id=$playlistId');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _scanForTracks(data);
    }
    return [];
  }

  static Future<List<Album>> getArtistAlbums(String artistId) async {
    final uri = Uri.parse('$_baseUrl/artist?f=$artistId');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return _scanForAlbums(data);
    }
    return [];
  }

  static List<Track> _scanForTracks(dynamic data) {
    final List<Track> tracks = [];
    final Set<String> seenIds = {};

    void scan(dynamic value) {
      if (value == null) {
        return;
      }
      if (value is List) {
        for (var item in value) {
          scan(item);
        }
        return;
      }
      if (value is Map) {
        final item = value['item'] ?? value;
        final type = item['type']?.toString().toLowerCase();
        final id = item['id']?.toString();
        
        // A track must have an ID and either type 'track' or a duration
        // CRITICAL: Ensure it's NOT an album (albums sometimes have duration too)
        bool isAlbum = type == 'album' || item['numberOfTracks'] != null;
        bool isTrack = id != null && (type == 'track' || type == 'song' || (item['duration'] != null && !isAlbum));

        if (isTrack) {
          if (!seenIds.contains(id)) {
            seenIds.add(id);
            tracks.add(Track.fromJson(item));
          }
        }
        
        // Always scan children to find nested tracks (e.g. in an album object)
        value.forEach((key, val) {
          if (key != 'item') scan(val);
        });
      }
    }

    scan(data['data'] ?? data);
    return tracks;
  }

  static List<Album> _scanForAlbums(dynamic data) {
    final List<Album> albums = [];
    final Set<String> seenIds = {};

    void scan(dynamic value) {
      if (value == null) {
        return;
      }
      if (value is List) {
        for (var item in value) {
          scan(item);
        }
        return;
      }
      if (value is Map) {
        final item = value['item'] ?? value;
        final type = item['type']?.toString().toLowerCase();
        final id = item['id']?.toString();
        
        // An album must have an ID and either type 'album' or a cover/numberOfTracks
        // CRITICAL: Ensure it's NOT a track
        bool isTrack = type == 'track' || type == 'song' || (item['duration'] != null && item['numberOfTracks'] == null);
        bool isAlbum = id != null && (type == 'album' || item['numberOfTracks'] != null || (item['cover'] != null && !isTrack));

        if (isAlbum) {
          if (!seenIds.contains(id)) {
            seenIds.add(id);
            albums.add(Album.fromJson(item));
          }
        }
        
        // Always scan children
        value.forEach((key, val) {
          if (key != 'item') scan(val);
        });
      }
    }

    scan(data['data'] ?? data);
    return albums;
  }

  static Future<Map<String, dynamic>> getStreamMetadata(String trackId, {String? quality}) async {
    final targetQuality = quality ?? HiveService.audioQuality;
    final uri = Uri.parse('$_baseUrl/track?id=$trackId&quality=$targetQuality');
    print("API GetStream: $uri");
    
    var response = await http.get(uri, headers: _headers);

    if (response.statusCode != 200) {
      print("API GetStream failed with ${response.statusCode}");
      
      // Fallback sequence
      final qualities = ['HI_RES_LOSSLESS', 'LOSSLESS', 'HIGH', 'LOW'];
      // Remove current quality and any higher qualities
      final currentIndex = qualities.indexOf(targetQuality);
      if (currentIndex == -1) {
         // If unknown quality, just try all from top
         // But usually we should match the requested one first.
      }
      
      final fallbackQualities = currentIndex != -1 ? qualities.sublist(currentIndex + 1) : qualities;

      for (final fallbackQuality in fallbackQualities) {
        print("Falling back to $fallbackQuality quality...");
        final fallbackUri = Uri.parse('$_baseUrl/track?id=$trackId&quality=$fallbackQuality');
        print("API GetStream (Fallback): $fallbackUri");
        final fallbackResponse = await http.get(fallbackUri, headers: _headers);
        
        if (fallbackResponse.statusCode == 200) {
          final data = jsonDecode(fallbackResponse.body);
          final trackData = data['data'] ?? data;
          return _processStreamData(trackData);
        } else {
          print("API GetStream (Fallback) failed with ${fallbackResponse.statusCode}");
          response = fallbackResponse; // Keep track of the last failed response
        }
      }
      throw Exception("Failed to get stream metadata (Status: ${response.statusCode})");
    }

    final data = jsonDecode(response.body);
    final trackData = data['data'] ?? data;

    return _processStreamData(trackData);
  }

  static Map<String, dynamic> _processStreamData(Map<String, dynamic> trackData) {
    final manifestBase64 = trackData['manifest'];
    final mimeType = trackData['manifestMimeType'];
    
    if (manifestBase64 != null) {
      final url = _extractUrlFromManifest(manifestBase64, mimeType);
      if (url != null) {
        return {
          ...trackData,
          'url': url,
        };
      }
    }
    return trackData;
  }

  static String? _extractUrlFromManifest(String base64Manifest, String? mimeType) {
    print("ApiService: Extracting URL from manifest (Mime: $mimeType)");
    String decodedString;
    try {
      final decodedBytes = base64.decode(base64Manifest.trim());
      decodedString = utf8.decode(decodedBytes);
    } catch (e) {
      print("Manifest decoding error (assuming plain text): $e");
      decodedString = base64Manifest.trim();
    }

    // 1. Check for JSON with urls array
    if (decodedString.trim().startsWith('{')) {
      try {
        final manifestJson = jsonDecode(decodedString);
        final urls = manifestJson['urls'] as List?;
        if (urls != null && urls.isNotEmpty) {
          return urls[0].toString();
        }
      } catch (_) {}
    }

    // 2. Check for DASH XML
    if (decodedString.contains('<MPD') || (mimeType?.contains('xml') ?? false)) {
      final url = _parseFlacUrlFromMpd(decodedString);
      if (url != null) return url;
      
      // If we can't find a direct FLAC URL, return data URI as fallback for just_audio
      // But for downloads, this won't work.
      // Re-encode if it was plain text
      final bytes = utf8.encode(decodedString);
      return 'data:application/dash+xml;base64,${base64.encode(bytes)}';
    }
    
    return null;
  }

  static String? _parseFlacUrlFromMpd(String manifestText) {
    // Only look for <BaseURL>...</BaseURL> which indicates a single-file stream
    // For segmented streams (SegmentTemplate), we return null to use DASH data URI
    final baseUrlRegex = RegExp(r'<BaseURL[^>]*>([^<]+)<\/BaseURL>', caseSensitive: false);
    final baseMatches = baseUrlRegex.allMatches(manifestText);
    
    for (final match in baseMatches) {
      final url = match.group(1)?.trim();
      if (url != null && _isValidMediaUrl(url)) {
        print("ApiService: Found BaseURL: $url");
        return url;
      }
    }

    // For segmented DASH (no BaseURL), return null to use data URI with DashAudioSource
    print("ApiService: No BaseURL found, will use DASH data URI");
    return null;
  }

  static bool _isValidMediaUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('w3.org') || lower.contains('xmlschema') || lower.contains('xmlns')) return false;
    return lower.contains('.flac') || lower.contains('.mp4') || lower.contains('.m4a') || lower.contains('.aac') || lower.contains('token=') || lower.contains('/audio/');
  }

  static Future<String> getStreamUrl(String trackId) async {
    final metadata = await getStreamMetadata(trackId);
    return metadata['url'];
  }

  static Future<Lyrics?> getLyrics(String trackId) async {
    try {
      final uri = Uri.parse('$_baseUrl/lyrics/?id=$trackId');
      print("API GetLyrics: $uri");
      final response = await http.get(uri, headers: _headers);
      print("API GetLyrics Status: ${response.statusCode}");
      print("API GetLyrics Body: ${response.body}");
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        var lyricsData = data['lyrics'] ?? data['data'] ?? data;
        
        // Handle array response as seen in tidal-ui
        if (lyricsData is List && lyricsData.isNotEmpty) {
          lyricsData = lyricsData[0];
        }
        
        if (lyricsData is Map<String, dynamic>) {
          return Lyrics.fromJson(lyricsData, trackId);
        } else {
          print("API GetLyrics: Unexpected data format: $lyricsData");
        }
      }
    } catch (e) {
      print("Lyrics fetch error: $e");
    }
    return null;
  }

  static Future<String?> _getMusicBrainzOriginalName(String query) async {
    try {
      // MusicBrainz API requires a User-Agent
      final uri = Uri.parse('https://musicbrainz.org/ws/2/artist/?query=${Uri.encodeComponent(query)}&fmt=json');
      final response = await http.get(uri, headers: {
        'User-Agent': 'Hipotify/1.0.0 ( mailto:zek@example.com )',
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final artists = data['artists'] as List?;
        if (artists != null && artists.isNotEmpty) {
          // Find the best match (highest score) that has a different name
          final bestMatch = artists[0];
          final score = bestMatch['score'] as int? ?? 0;
          if (score > 90) {
            final name = bestMatch['name'] as String?;
            return name;
          }
        }
      }
    } catch (e) {
      print("MusicBrainz mapping error: $e");
    }
    return null;
  }
}
