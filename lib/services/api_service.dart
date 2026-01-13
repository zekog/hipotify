import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'hive_service.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/lyrics.dart';

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

  static Future<List<dynamic>> search(String query, {int offset = 0, int limit = 25}) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final List<dynamic> allItems = [];
      final Set<String> seenIds = {};

      Future<void> performSearch(String typeParam, [String? inferredType]) async {
        final uri = Uri.parse('$_baseUrl/search?$typeParam=$encodedQuery&offset=$offset&index=$offset&limit=$limit');
        print("API Search ($typeParam): $uri");
        final response = await http.get(uri, headers: _headers);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final resultData = data['data'] ?? data;
          
          void scan(dynamic value, [String? currentInferredType]) {
            if (value == null) {
              return;
            }
            if (value is List) {
              for (var item in value) {
                scan(item, currentInferredType);
              }
              return;
            }
            if (value is Map) {
              final item = value['item'] ?? value;
              String? type = item['type']?.toString().toLowerCase() ?? currentInferredType;
              final id = item['id']?.toString();

              if (id != null) {
                // Refined type guessing
                if (type == null || type == 'main' || type == 'contributor') {
                  if (item['duration'] != null) type = 'track';
                  else if (item['artistRoles'] != null || item['artistTypes'] != null || item['picture'] != null) type = 'artist';
                  else if (item['cover'] != null || item['releaseDate'] != null || item['numberOfTracks'] != null) type = 'album';
                  else if (item['title'] != null && item['artist'] != null) type = 'track';
                }

                // Ensure we don't add an album as a track or vice-versa
                bool isAlbum = type == 'album' || item['numberOfTracks'] != null;
                bool isTrack = type == 'track' || type == 'song' || item['duration'] != null;

                if (isAlbum && type != 'album') type = 'album';
                if (isTrack && !isAlbum && type != 'track') type = 'track';

                if (type == 'track' || type == 'song' || type == 'artist' || type == 'album') {
                  final uniqueId = '${type}_$id';
                  if (!seenIds.contains(uniqueId)) {
                    seenIds.add(uniqueId);
                    if (type == 'artist') {
                      allItems.add(Artist.fromJson(item));
                    } else if (type == 'album') {
                      allItems.add(Album.fromJson(item));
                    } else {
                      allItems.add(Track.fromJson(item));
                    }
                  }
                  // Even if we added the item, we might want to scan its children (e.g. tracks in an album)
                  // but for search results we usually want the top-level items.
                  // However, let's continue scanning to be safe, but skip the 'item' key to avoid loops.
                }
              }

              value.forEach((key, val) {
                if (key == 'item') {
                  return;
                }
                String? nextInferredType = currentInferredType;
                if (key == 'artists') nextInferredType = 'artist';
                else if (key == 'albums') nextInferredType = 'album';
                else if (key == 'tracks' || key == 'songs') nextInferredType = 'track';
                scan(val, nextInferredType);
              });
            }
          }

          scan(resultData, inferredType);
        }
      }

      await Future.wait([
        performSearch('s', 'track'),
        performSearch('a', 'artist'),
        performSearch('al', 'album'),
      ]);

      print("API Search Found ${allItems.length} items total");
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
    // Regex-based parsing to find BaseURL
    // Look for <BaseURL>...</BaseURL>
    final baseUrlRegex = RegExp(r'<BaseURL[^>]*>([^<]+)<\/BaseURL>', caseSensitive: false);
    final matches = baseUrlRegex.allMatches(manifestText);
    
    for (final match in matches) {
      final url = match.group(1)?.trim();
      if (url != null && _isValidMediaUrl(url)) {
        return url;
      }
    }
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
}
