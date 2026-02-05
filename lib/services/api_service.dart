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
  static final http.Client _client = http.Client();
  
  static String get baseUrl => _baseUrl;
  static String get _baseUrl {
    final url = HiveService.apiUrl;
    if (url == null || url.isEmpty) {
      throw Exception("API URL not set");
    }
    // Remove trailing slash if present
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static Map<String, String> get _headers => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': 'https://hifi-one.spotisaver.net',
    'Referer': 'https://hifi-one.spotisaver.net/',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'cross-site',
    'Sec-Ch-Ua': '"Not A(Brand";v="99", "Google Chrome";v="121", "Chromium";v="121"',
    'Sec-Ch-Ua-Mobile': '?0',
    'Sec-Ch-Ua-Platform': '"Windows"',
  };

  /// Generic GET request with automatic retry on 429 (Too Many Requests)
  static Future<http.Response> getWithRetry(Uri uri, {int maxRetries = 3}) async {
    int retryCount = 0;
    while (true) {
      try {
        final response = await _client.get(uri, headers: _headers);
        if ((response.statusCode == 429 || response.statusCode >= 500) && retryCount < maxRetries) {
          retryCount++;
          // Standard exponential backoff: 1s, 2s, 4s
          final delay = Duration(seconds: pow(2, retryCount - 1).toInt());
          print("ApiService: Received ${response.statusCode}. Retrying in ${delay.inSeconds}s (Attempt $retryCount/$maxRetries)");
          await Future.delayed(delay);
          continue;
        }
        return response;
      } catch (e) {
        if (retryCount >= maxRetries) rethrow;
        retryCount++;
        final delay = Duration(seconds: pow(2, retryCount - 1).toInt());
        print("ApiService: Request failed ($e). Retrying in ${delay.inSeconds}s (Attempt $retryCount/$maxRetries)");
        await Future.delayed(delay);
      }
    }
  }

  static Future<http.Response> _getWithRetry(Uri uri, {int maxRetries = 5}) => getWithRetry(uri, maxRetries: maxRetries);

  static Future<List<dynamic>> search(String query, {int offset = 0, int limit = 50, String? searchType}) async {
    try {
      final List<dynamic> allItems = [];
      final Set<String> seenIds = {};
      final normalizedQuery = query.toLowerCase().trim();

      Future<void> performSearch(String searchTerms, String typeParam, [String? inferredType]) async {
        final encoded = Uri.encodeComponent(searchTerms);
        final uri = Uri.parse('$_baseUrl/search?$typeParam=$encoded&offset=$offset&index=$offset&limit=$limit');
        print("API Search ($typeParam) for '$searchTerms': $uri");
        final response = await _getWithRetry(uri);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final resultData = data['data'] ?? data;
          
          _scanGeneric(resultData, 
            allItems: allItems, 
            seenIds: seenIds, 
            inferredType: inferredType
          );
        }
      }

      final List<Future<void>> searchTasks = [];
      
      if (searchType == null || searchType == 'track') {
        searchTasks.add(performSearch(query, 's', 'track'));
      }
      if (searchType == null || searchType == 'artist') {
        searchTasks.add(performSearch(query, 'a', 'artist'));
      }
      if (searchType == null || searchType == 'album') {
        searchTasks.add(performSearch(query, 'al', 'album'));
      }
      if (searchType == null || searchType == 'playlist') {
        searchTasks.add(performSearch(query, 'p', 'playlist'));
      }

      // 0. MusicBrainz Mapping for Latin Queries (Only for generic searches)
      if (searchType == null) {
        final queryIsLatin = RegExp(r'^[a-zA-Z0-9\s\p{P}]+$', unicode: true).hasMatch(normalizedQuery);
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
          score += 5000.0; // Higher weight for exact title
        } else if (lowerTitle.startsWith(normalizedQuery)) {
          score += 1500.0;
        } else if (lowerTitle.contains(normalizedQuery)) {
          score += 500.0;
        }

        // 2. Artist Match Bonus
        if (lowerArtist.isNotEmpty) {
          if (lowerArtist == normalizedQuery) {
            score += 4000.0; // Higher weight for exact artist match
          } else if (lowerArtist.startsWith(normalizedQuery)) {
            score += 1200.0;
          } else if (lowerArtist.contains(normalizedQuery)) {
            score += 600.0;
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
    // Try Full request first
    final uri = Uri.parse('$_baseUrl/artist?f=$artistId');
    final response = await _getWithRetry(uri);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final artistData = _findArtistInResponse(data, artistId);
      if (artistData != null) {
        return artistData;
      }
    }

    // Fallback to id= if f= fails or doesn't return full data
    final fallbackUri = Uri.parse('$_baseUrl/artist?id=$artistId');
    final fallbackResponse = await _getWithRetry(fallbackUri);
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
    final uri = Uri.parse('$_baseUrl/artist?f=$artistId');
    final response = await _getWithRetry(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      // Module search
      final modules = data['modules'] ?? data['data']?['modules'];
      if (modules is List) {
        for (var module in modules) {
           final type = module['type']?.toString().toUpperCase();
           final title = module['title']?.toString().toLowerCase();
           
           if (type == 'TRACK_LIST' || type == 'TOP_TRACKS' || (title != null && (title.contains('top') || title.contains('utwory') || title.contains('popularne')))) {
             final tracks = scanForTracks(module);
             if (tracks.isNotEmpty) {
               return tracks;
             }
           }
        }
      }
      
      final tracks = scanForTracks(data);
      if (tracks.isNotEmpty) {
        return tracks;
      }
    }

    // Fallback to id=
    final fallbackUri = Uri.parse('$_baseUrl/artist?id=$artistId');
    final fallbackResponse = await _getWithRetry(fallbackUri);
    if (fallbackResponse.statusCode == 200) {
      final data = jsonDecode(fallbackResponse.body);
      return scanForTracks(data);
    }
    return [];
  }

  static Future<Album> getAlbumDetails(String albumId) async {
    final uri = Uri.parse('$_baseUrl/album?id=$albumId');
    final response = await _getWithRetry(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final albumData = findAlbumInResponse(data, albumId);
      if (albumData != null) {
        return albumData;
      }
    }
    throw Exception("Failed to get album details (Status: ${response.statusCode})");
  }

  static Album? findAlbumInResponse(dynamic data, String albumId) {
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
        value.forEach((key, val) {
          if (key != 'item') {
            scan(val);
          }
        });
      }
    }
    scan(data['data'] ?? data);
    return foundAlbum;
  }

  static Future<List<Track>> getAlbumTracks(String albumId) async {
    final uri = Uri.parse('$_baseUrl/album?id=$albumId');
    final response = await _getWithRetry(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return scanForTracks(data);
    }
    return [];
  }

  static Future<TidalPlaylist> getPlaylistDetails(String playlistId) async {
    final uri = Uri.parse('$_baseUrl/playlist?id=$playlistId');
    final response = await _getWithRetry(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final playlistData = data['playlist'] ?? data['data'] ?? data;
      return TidalPlaylist.fromJson(playlistData);
    }
    throw Exception("Failed to get playlist details (Status: ${response.statusCode})");
  }

  static Future<List<Track>> getPlaylistTracks(String playlistId) async {
    final uri = Uri.parse('$_baseUrl/playlist?id=$playlistId');
    final response = await _getWithRetry(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return scanForTracks(data);
    }
    return [];
  }

  static Future<List<Album>> getArtistAlbums(String artistId) async {
    final uri = Uri.parse('$_baseUrl/artist?f=$artistId');
    final response = await _getWithRetry(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      // Try to find modules for albums too
      final modules = data['modules'] ?? data['data']?['modules'];
      if (modules is List) {
        for (var module in modules) {
           final type = module['type']?.toString().toUpperCase();
           final title = module['title']?.toString().toLowerCase();
           
           if (type == 'ALBUM_LIST' || (title != null && (title.contains('album') || title.contains('singl') || title.contains('wydania')))) {
             final albums = scanForAlbums(module);
             if (albums.isNotEmpty) {
               return albums;
             }
           }
        }
      }

      final albums = scanForAlbums(data);
      if (albums.isNotEmpty) {
        return albums;
      }
    }

    // Fallback to id=
    final fallbackUri = Uri.parse('$_baseUrl/artist?id=$artistId');
    final fallbackResponse = await _getWithRetry(fallbackUri);
    if (fallbackResponse.statusCode == 200) {
      final data = jsonDecode(fallbackResponse.body);
      return scanForAlbums(data);
    }
    return [];
  }

  static List<Track> scanForTracks(dynamic data) {
    if (data == null) return [];
    final List<dynamic> allItems = [];
    final Set<String> seenIds = {};
    _scanGeneric(data is Map && data.containsKey('data') ? data['data'] : data, 
      allItems: allItems, 
      seenIds: seenIds, 
      inferredType: 'track'
    );
    return allItems.whereType<Track>().toList();
  }

  static List<Album> scanForAlbums(dynamic data) {
    if (data == null) return [];
    final List<dynamic> allItems = [];
    final Set<String> seenIds = {};
    _scanGeneric(data is Map && data.containsKey('data') ? data['data'] : data, 
      allItems: allItems, 
      seenIds: seenIds, 
      inferredType: 'album'
    );
    return allItems.whereType<Album>().toList();
  }

  /// Unified scanning logic for search and detail screens
  static void _scanGeneric(dynamic value, {
    required List<dynamic> allItems, 
    required Set<String> seenIds, 
    String? inferredType
  }) {
    if (value == null) return;
    
    if (value is List) {
      for (var item in value) {
        _scanGeneric(item, allItems: allItems, seenIds: seenIds, inferredType: inferredType);
      }
      return;
    }
    
    if (value is Map) {
      final item = value['item'] ?? value;
      String? type = item['type']?.toString().toLowerCase() ?? inferredType;
      final id = item['id']?.toString() ?? item['uuid']?.toString();

      if (id != null) {
        // 1. Initial Type Inference
        if (type == null || type == 'main' || type == 'contributor' || type == 'media' || type == 'product') {
          if (item['duration'] != null) {
            type = 'track';
          } else if (item['artistRoles'] != null || item['artistTypes'] != null || item['picture'] != null) {
            type = 'artist';
          } else if (item['uuid'] != null || item['creator'] != null) {
            type = 'playlist';
          } else if (item['cover'] != null || item['releaseDate'] != null || item['numberOfTracks'] != null) {
            type = 'album';
          } else if (item['title'] != null && item['artist'] != null) {
            type = 'track';
          }
        }

        // 2. Structural Refinement
        if (item['uuid'] != null || item['creator'] != null) {
          type = 'playlist';
        } else if (item['numberOfTracks'] != null && type != 'playlist') {
          type = 'album';
        } else if (item['duration'] != null && type != 'album' && type != 'playlist') {
          type = 'track';
        }

        // 3. Normalized Mapping
        if (type == 'song') type = 'track';
        if (type == 'release') type = 'album';

        // 4. Object Creation
        if (type == 'track' || type == 'artist' || type == 'album' || type == 'playlist') {
          final uniqueId = '${type}_$id';
          if (!seenIds.contains(uniqueId)) {
            seenIds.add(uniqueId);
            try {
              if (type == 'artist') {
                allItems.add(Artist.fromJson(item));
              } else if (type == 'album') {
                allItems.add(Album.fromJson(item));
              } else if (type == 'playlist') {
                allItems.add(TidalPlaylist.fromJson(item));
              } else if (type == 'track') {
                allItems.add(Track.fromJson(item));
              }
            } catch (e) {
              print("ApiService: Error parsing $type ($id): $e");
            }
          }
        }
      }

      // 5. Recursive Scan
      value.forEach((key, val) {
        if (key == 'item' || key == 'links') {
          return;
        }
        
        // If we found an object and it IS a track/artist/etc, 
        // we should reset inference for its children.
        String? nextInferredType = (id != null) ? null : inferredType;
        
        // Key-based hints are more reliable than previous inference
        final lowerKey = key.toLowerCase();
        if (lowerKey.contains('artist')) {
          nextInferredType = 'artist';
        } else if (lowerKey.contains('album') || lowerKey == 'releases' || lowerKey == 'albums') {
          nextInferredType = 'album';
        } else if (lowerKey.contains('track') || lowerKey.contains('song') || lowerKey == 'toptracks' || lowerKey == 'items' || lowerKey == 'contents') {
          nextInferredType = 'track';
        } else if (lowerKey.contains('playlist')) {
          nextInferredType = 'playlist';
        }
        
        _scanGeneric(val, allItems: allItems, seenIds: seenIds, inferredType: nextInferredType);
      });
    }
  }

  static Future<Map<String, dynamic>> getStreamMetadata(String trackId, {String? quality}) async {
    final targetQuality = quality ?? HiveService.audioQuality;
    final qualities = ['HI_RES_LOSSLESS', 'LOSSLESS', 'HIGH', 'LOW'];
    
    // Explicitly add current target quality at the start if not HI_RES_LOSSLESS
    final List<String> tryQualities = [targetQuality];
    for (var q in qualities) {
      if (q != targetQuality) tryQualities.add(q);
    }

    http.Response? lastResponse;

    for (final q in tryQualities) {
      final uri = Uri.parse('$_baseUrl/track?id=$trackId&quality=$q');
      print("API GetStream: $uri");
      
      try {
        final response = await _getWithRetry(uri);
        lastResponse = response;
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // Ensure trackData is mutable and strictly a Map
          final trackData = Map<String, dynamic>.from(data['data'] ?? data);
          
          // CRITICAL: Ensure ID is preserved. Some endpoints might not return it in the body.
          if (trackData['id'] == null) {
             print("ApiService: ID missing in stream response, injecting $trackId");
             trackData['id'] = trackId;
          }
          
          return _processStreamData(trackData);
        }
        print("API GetStream for $q failed with ${response.statusCode}");
      } catch (e) {
        print("API GetStream for $q error: $e");
      }
    }

    throw Exception("Failed to get stream metadata (Status: ${lastResponse?.statusCode ?? 'Unknown'})");
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
      final uri = Uri.parse('$_baseUrl/lyrics?id=$trackId');
      print("API GetLyrics: $uri");
      final response = await _getWithRetry(uri);
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
      final response = await _client.get(uri, headers: {
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

  /// Fetches metadata from a Spotify link using oEmbed API.
  /// Returns a map with 'title', 'type', and optionally 'artist'.
  static Future<Map<String, String>?> getSpotifyMetadata(String spotifyUrl) async {
    try {
      final oembedUrl = 'https://open.spotify.com/oembed?url=${Uri.encodeComponent(spotifyUrl)}';
      final response = await _client.get(Uri.parse(oembedUrl), headers: {
        'User-Agent': 'Hipotify/1.0.0',
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final title = data['title'] as String?;
        final type = data['type'] as String?; // "rich" for tracks, but we infer from URL
        
        if (title != null) {
          // Title format varies:
          // Track: "Song Name - song and lyrics by Artist Name | Spotify" or "Song Name"
          // Album: "Album Name - Album by Artist Name | Spotify"
          // Artist: "Artist Name | Spotify"
          
          String cleanTitle = title;
          String? artist;
          
          // Remove " | Spotify" suffix
          if (cleanTitle.contains(' | Spotify')) {
            cleanTitle = cleanTitle.split(' | Spotify')[0];
          }
          
          // Extract artist from formats like "Song - song and lyrics by Artist"
          final lyricsMatch = RegExp(r'^(.+?)\s*[-–]\s*song and lyrics by\s+(.+)$', caseSensitive: false).firstMatch(cleanTitle);
          if (lyricsMatch != null) {
            cleanTitle = lyricsMatch.group(1)!.trim();
            artist = lyricsMatch.group(2)!.trim();
          } else {
            // Try "Album - Album by Artist" format
            final albumMatch = RegExp(r'^(.+?)\s*[-–]\s*Album by\s+(.+)$', caseSensitive: false).firstMatch(cleanTitle);
            if (albumMatch != null) {
              cleanTitle = albumMatch.group(1)!.trim();
              artist = albumMatch.group(2)!.trim();
            } else {
              // Try generic "Title by Artist" format
              final byMatch = RegExp(r'^(.+?)\s+by\s+(.+)$', caseSensitive: false).firstMatch(cleanTitle);
              if (byMatch != null) {
                cleanTitle = byMatch.group(1)!.trim();
                artist = byMatch.group(2)!.trim();
              }
            }
          }
          
          return {
            'title': cleanTitle,
            if (artist != null) 'artist': artist,
            'type': type ?? 'unknown',
          };
        }
      }
    } catch (e) {
      print("Spotify oEmbed error: $e");
    }
    return null;
  }

  /// Resolves a Spotify URL to a Tidal Track ID using Odesli (Songlink)
  /// Returns a Map with 'id', 'title', 'artist', 'cover' if found.
  static Future<Map<String, dynamic>?> resolveTidalTrackFromOdesli(String spotifyUrl) async {
    try {
      print("ApiService: Resolving Tidal ID via Odesli for $spotifyUrl");
      final uri = Uri.parse('https://api.song.link/v1-alpha.1/links?url=${Uri.encodeComponent(spotifyUrl)}');
      final response = await _client.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // 1. Find the Tidal entity info
        Map<String, dynamic>? tidalEntity;
        
        final entities = data['entitiesByUniqueId'] as Map<String, dynamic>?;
        if (entities != null) {
          for (final key in entities.keys) {
            if (key.startsWith('TIDAL_SONG::')) {
              tidalEntity = entities[key];
              break;
            }
          }
        }

        String? id;
        String? title;
        String? artist;
        String? cover;

        if (tidalEntity != null) {
          id = tidalEntity['id']?.toString();
          title = tidalEntity['title']?.toString();
          artist = tidalEntity['artistName']?.toString();
          cover = tidalEntity['thumbnailUrl']?.toString();
        }

        // 2. If ID still missing, try linksByPlatform
        if (id == null) {
          final links = data['linksByPlatform'] as Map<String, dynamic>?;
          if (links != null && links.containsKey('tidal')) {
             final tidalLink = links['tidal'];
             final uniqueId = tidalLink['entityUniqueId'] as String?;
             
             if (uniqueId != null && uniqueId.startsWith('TIDAL_SONG::')) {
               id = uniqueId.split('::').last;
             } else {
               final url = tidalLink['url'] as String?;
               if (url != null) {
                  final idMatch = RegExp(r'tidal\.com/track/([0-9]+)').firstMatch(url);
                  if (idMatch != null) id = idMatch.group(1);
               }
             }
          }
        }

        if (id != null) {
           return {
             'id': id,
             'title': title ?? 'Unknown Title',
             'artist': artist ?? 'Unknown Artist',
             'cover': cover,
           };
        }
      }
    } catch (e) {
      print("Odesli resolution error: $e");
    }
    return null;
  }
}
