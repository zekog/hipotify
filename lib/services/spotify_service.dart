import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for extracting playlist data from Spotify
class SpotifyService {
  static final http.Client _client = http.Client();
  
  /// Extracts playlist ID from various Spotify URL formats
  static String? extractPlaylistId(String url) {
    // Pattern for Spotify: open.spotify.com/playlist/xxx
    // Pattern for short links: spotify.link/xxx (would need redirect following)
    
    final patterns = [
      RegExp(r'open\.spotify\.com/playlist/([a-zA-Z0-9]+)'),
      RegExp(r'spotify\.com/playlist/([a-zA-Z0-9]+)'),
      RegExp(r'spotify:playlist:([a-zA-Z0-9]+)'),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
  
  /// Fetches playlist metadata and track list using Spotify's embed page
  static Future<SpotifyPlaylist?> fetchPlaylist(String playlistId) async {
    try {
      // Spotify embed page contains JSON data with track info
      final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
      final response = await _client.get(Uri.parse(embedUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml',
        'Accept-Language': 'en-US,en;q=0.9',
      });
      
      if (response.statusCode != 200) {
        print("SpotifyService: Failed to fetch embed page: ${response.statusCode}");
        return null;
      }
      
      final html = response.body;
      
      // Try to extract __NEXT_DATA__ or similar JSON from the page
      var dataMatch = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(\{.+?\})</script>', dotAll: true).firstMatch(html);
      if (dataMatch != null) {
        return _parseNextData(dataMatch.group(1)!);
      }
      
      // Try resource script pattern
      dataMatch = RegExp(r'<script[^>]*>\s*Spotify\s*=\s*(\{.+?\});\s*</script>', dotAll: true).firstMatch(html);
      if (dataMatch != null) {
        return _parseSpotifyData(dataMatch.group(1)!);
      }
      
      // Try extracting from window.__SSR_DATA__
      dataMatch = RegExp(r'window\.__SSR_DATA__\s*=\s*(\{.+?\});', dotAll: true).firstMatch(html);
      if (dataMatch != null) {
        return _parseSSRData(dataMatch.group(1)!);
      }
      
      // Try generic session / initial data patterns
      dataMatch = RegExp(r'<script[^>]*>\s*session\s*=\s*(\{.+?\});\s*</script>', dotAll: true).firstMatch(html);
      if (dataMatch != null) {
        return _parseSessionData(dataMatch.group(1)!);
      }
      
      // Fallback: try to fetch playlist page directly
      return await _fetchFromPlaylistPage(playlistId);
    } catch (e) {
      print("SpotifyService: Error fetching playlist: $e");
      return null;
    }
  }
  
  static SpotifyPlaylist? _parseNextData(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      final pageProps = data['props']?['pageProps'];
      if (pageProps == null) return null;
      
      final playlistData = pageProps['playlist'] ?? pageProps['state']?['data']?['entity'];
      if (playlistData == null) return null;
      
      final title = playlistData['name'] as String? ?? 'Unknown Playlist';
      final tracksData = playlistData['tracks']?['items'] ?? playlistData['trackList'] ?? [];
      
      final tracks = <SpotifyTrack>[];
      for (final item in tracksData) {
        final track = item['track'] ?? item;
        if (track == null) continue;
        
        final trackId = track['id'] as String? ?? track['uri']?.toString().split(':').last;
        final trackTitle = (track['name'] ?? track['title']) as String?;
        
        // Get artists
        String? artist;
        final artistsList = track['artists'] as List?;
        if (artistsList?.isNotEmpty == true) {
          artist = (artistsList![0]['name'] as String?) ?? '';
          // Join additional artists
          if (artistsList.length > 1) {
            final others = artistsList.skip(1).map((a) => a['name'] as String?).where((n) => n != null).join(', ');
            if (others.isNotEmpty) {
              artist = '$artist, $others';
            }
          }
        } else if (track['subtitle'] != null) {
          // Embed format uses 'subtitle' for artists
          artist = track['subtitle'] as String?;
        }
        
        // Get album
        final album = track['album']?['name'] as String?;
        
        // Duration
        final durationMs = track['duration_ms'] as int? ?? track['duration'] as int?;
        String? duration;
        if (durationMs != null) {
          final minutes = durationMs ~/ 60000;
          final seconds = (durationMs % 60000) ~/ 1000;
          duration = '$minutes:${seconds.toString().padLeft(2, '0')}';
        }
        
        // ISRC
        final isrc = track['external_ids']?['isrc'] as String?;

        if (trackId != null && trackTitle != null) {
          tracks.add(SpotifyTrack(
            id: trackId,
            title: trackTitle,
            artist: artist,
            album: album,
            duration: duration,
            isrc: isrc,
          ));
        }
      }
      
      return SpotifyPlaylist(
        id: '',
        title: title,
        tracks: tracks,
      );
    } catch (e) {
      print("SpotifyService: Error parsing __NEXT_DATA__: $e");
      return null;
    }
  }
  
  static SpotifyPlaylist? _parseSpotifyData(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      
      // Usually found under Entity or similarly named keys
      final entity = data['Entity'] ?? data['entity'];
      if (entity == null) return null;
      
      final title = entity['name'] as String? ?? 'Unknown Playlist';
      final trackList = entity['tracks']?['items'] ?? entity['trackList'];
      
      if (trackList == null || trackList is! List) return null;
      
      final tracks = <SpotifyTrack>[];
      for (final item in trackList) {
        final track = item['track'] ?? item;
        if (track == null) continue;
        
        final trackId = track['id'] as String? ?? track['uri']?.toString().split(':').last;
        final trackTitle = track['name'] as String?;
        
        // Artists
        String? artist;
        final artistsList = track['artists'] as List?;
        if (artistsList?.isNotEmpty == true) {
          artist = artistsList![0]['name'] as String?;
        }
        
        // Album
        final album = track['album']?['name'] as String?;
        
        if (trackId != null && trackTitle != null) {
          tracks.add(SpotifyTrack(
            id: trackId,
            title: trackTitle,
            artist: artist,
            album: album,
          ));
        }
      }
      
      if (tracks.isEmpty) return null;
      
      return SpotifyPlaylist(
        id: '',
        title: title,
        tracks: tracks,
      );
    } catch (e) {
      print("SpotifyService: Error parsing Spotify data: $e");
      return null;
    }
  }
  
  static SpotifyPlaylist? _parseSSRData(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      final entity = data['entities']?['items']?.values?.first;
      if (entity == null) return null;
      
      final title = entity['name'] as String? ?? 'Unknown Playlist';
      final trackList = entity['tracks']?['items'] ?? [];
      
      final tracks = <SpotifyTrack>[];
      for (final item in trackList) {
        final track = item['track'] ?? item;
        if (track == null) continue;
        
        final trackId = track['id'] as String?;
        final trackTitle = track['name'] as String?;
        final artist = (track['artists'] as List?)?.isNotEmpty == true
            ? track['artists'][0]['name'] as String?
            : null;
        
        if (trackId != null && trackTitle != null) {
          tracks.add(SpotifyTrack(
            id: trackId,
            title: trackTitle,
            artist: artist,
          ));
        }
      }
      
      return SpotifyPlaylist(id: '', title: title, tracks: tracks);
    } catch (e) {
      print("SpotifyService: Error parsing SSR data: $e");
      return null;
    }
  }
  
  static Future<SpotifyPlaylist?> _fetchFromPlaylistPage(String playlistId) async {
    try {
      final url = 'https://open.spotify.com/playlist/$playlistId';
      final response = await _client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': 'text/html',
        'Accept-Language': 'en-US,en;q=0.9',
      });
      
      if (response.statusCode != 200) return null;
      
      final html = response.body;
      
      // Extract playlist title from meta tags
      final titleMatch = RegExp(r'<meta property="og:title" content="([^"]+)"').firstMatch(html);
      final title = titleMatch?.group(1) ?? 'Spotify Playlist';
      
      // Try to find track data in Spotify's script content
      // Look for the apolloState or similar data structures
      final scriptMatch = RegExp(r'<script[^>]*>\s*window\.__APOLLO_STATE__\s*=\s*(\{.+?\});\s*</script>', dotAll: true).firstMatch(html);
      
      if (scriptMatch != null) {
        try {
          final apolloData = jsonDecode(scriptMatch.group(1)!);
          return _parseApolloState(apolloData, title);
        } catch (_) {}
      }
      
      // As fallback, try regex extraction of track info from HTML
      return _extractTracksFromHtml(html, title);
    } catch (e) {
      print("SpotifyService: Error fetching playlist page: $e");
      return null;
    }
  }
  
  static SpotifyPlaylist? _parseApolloState(Map<String, dynamic> data, String playlistTitle) {
    try {
      final tracks = <SpotifyTrack>[];
      
      // Apollo state stores tracks separately
      data.forEach((key, value) {
        if (key.startsWith('Track:') && value is Map) {
          final trackId = value['id'] as String? ?? key.replaceFirst('Track:', '');
          final name = value['name'] as String?;
          if (name != null) {
            // Try to get artist reference
            String? artist;
            final artistRefs = value['artists'] as List?;
            if (artistRefs?.isNotEmpty == true) {
              final artistRef = artistRefs![0];
              if (artistRef is Map && artistRef['name'] != null) {
                artist = artistRef['name'] as String?;
              }
            }
            
            tracks.add(SpotifyTrack(
              id: trackId,
              title: name,
              artist: artist,
            ));
          }
        }
      });
      
      if (tracks.isEmpty) return null;
      
      return SpotifyPlaylist(
        id: '',
        title: playlistTitle,
        tracks: tracks,
      );
    } catch (e) {
      return null;
    }
  }

  static SpotifyPlaylist? _parseSessionData(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      // Try to find any object that looks like a playlist with tracks
      // This is a "fuzzy" search through the JSON structure
      
      SpotifyPlaylist? found;
      
      void search(dynamic node) {
        if (found != null) return;
        
        if (node is Map) {
          if (node['__typename'] == 'Playlist' || node['type'] == 'playlist') {
             // Check for tracks
             final tracksNode = node['tracks'];
             if (tracksNode is Map && tracksNode['items'] is List) {
               final name = node['name'] as String? ?? 'Unknown Playlist';
               final trackList = tracksNode['items'] as List;
               
               if (trackList.isNotEmpty) {
                 final tracks = <SpotifyTrack>[];
                 for (final item in trackList) {
                   final track = item['track'] ?? item; // sometimes item is the track directly
                   if (track is Map) {
                     final id = track['id'] ?? track['uri']?.toString().split(':').last;
                     final title = track['name'];
                     
                     if (id != null && title != null) {
                       String? artistName;
                       final artists = track['artists'];
                       if (artists is List && artists.isNotEmpty) {
                         artistName = artists[0]['name'];
                       }
                       
                       tracks.add(SpotifyTrack(
                         id: id, 
                         title: title,
                         artist: artistName,
                         album: track['album']?['name'],
                         isrc: track['external_ids']?['isrc'],
                       ));
                     }
                   }
                 }
                 
                 if (tracks.isNotEmpty) {
                   found = SpotifyPlaylist(id: '', title: name, tracks: tracks);
                   return;
                 }
               }
             }
          }
          
          node.forEach((_, value) => search(value));
        } else if (node is List) {
          for (final item in node) search(item);
        }
      }
      
      search(data);
      return found;
    } catch (e) {
      print("SpotifyService: Error parsing session data: $e");
      return null;
    }
  }
  
  static SpotifyPlaylist? _extractTracksFromHtml(String html, String title) {
    // Fallback: extract track info from HTML structure
    // This is fragile but works as last resort
    final tracks = <SpotifyTrack>[];
    
    // Look for track rows in the HTML
    final trackPattern = RegExp(
      r'data-testid="tracklist-row"[^>]*>.*?'
      r'<a[^>]*href="/track/([^"]+)"[^>]*>([^<]+)</a>.*?'
      r'<a[^>]*href="/artist/[^"]+"[^>]*>([^<]+)</a>',
      dotAll: true,
    );
    
    for (final match in trackPattern.allMatches(html)) {
      final id = match.group(1);
      final trackTitle = match.group(2);
      final artist = match.group(3);
      
      if (id != null && trackTitle != null) {
        tracks.add(SpotifyTrack(
          id: id,
          title: _decodeHtmlEntities(trackTitle),
          artist: artist != null ? _decodeHtmlEntities(artist) : null,
        ));
      }
    }
    
    if (tracks.isEmpty) return null;
    
    return SpotifyPlaylist(id: '', title: title, tracks: tracks);
  }
  
  static Future<SpotifyTrack?> fetchTrack(String trackId) async {
    try {
      // Use embed page for single track too
      final embedUrl = 'https://open.spotify.com/embed/track/$trackId';
      final response = await _client.get(Uri.parse(embedUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': 'text/html',
      });
      
      if (response.statusCode != 200) return null;
      
      final html = response.body;

      // Try extract __NEXT_DATA__
      var dataMatch = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(\{.+?\})</script>', dotAll: true).firstMatch(html);
      if (dataMatch != null) {
         try {
           final data = jsonDecode(dataMatch.group(1)!);
           final props = data['props']?['pageProps'];
           final entity = props['state']?['data']?['entity'] ?? props['entity'];
           
           if (entity != null) {
              final id = entity['id'] as String? ?? trackId;
              final title = entity['name'] as String?;
              final durationMs = entity['duration_ms'] as int?;
              final isrc = entity['external_ids']?['isrc'] as String?;
              
              String? artist;
              final artists = entity['artists'] as List?;
              if (artists != null && artists.isNotEmpty) {
                artist = artists[0]['name'];
              } else {
                 artist = entity['subtitle'] as String?; // Embed fallback
              }

              if (title != null) {
                 String? duration;
                 if (durationMs != null) {
                    final minutes = durationMs ~/ 60000;
                    final seconds = (durationMs % 60000) ~/ 1000;
                    duration = '$minutes:${seconds.toString().padLeft(2, '0')}';
                 }

                 // Fallback to MusicBrainz if ISRC is missing
                 String? finalIsrc = isrc;
                 if (finalIsrc == null && artist != null) {
                   try {
                     finalIsrc = await _fetchIsrcFromMusicBrainz(artist, title);
                     if (finalIsrc != null) {
                       print('SpotifyService: Found ISRC via MusicBrainz: $finalIsrc');
                     }
                   } catch (e) {
                     print('SpotifyService: MusicBrainz fallback failed: $e');
                   }
                 }

                 return SpotifyTrack(
                   id: id,
                   title: title,
                   artist: artist,
                   album: entity['album']?['name'],
                   duration: duration,
                   isrc: finalIsrc,
                 );
              }
           }
         } catch (e) {
           print("Error parsing track next data: $e");
         }
      }
      
      return null;
    } catch (e) {
      print("SpotifyService: Error fetching track: $e");
      return null;
    }
  }

  static Future<String?> _fetchIsrcFromMusicBrainz(String artist, String title) async {
    try {
      final query = 'artist:${Uri.encodeComponent(artist)} AND recording:${Uri.encodeComponent(title)}';
      final uri = Uri.parse('https://musicbrainz.org/ws/2/recording?query=$query&fmt=json&limit=1');
      
      final response = await _client.get(uri, headers: {
        'User-Agent': 'Hipotify/1.0.0 ( mailto:zek@example.com )',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final recordings = data['recordings'] as List?;
        if (recordings != null && recordings.isNotEmpty) {
          final isrcs = recordings[0]['isrcs'] as List?;
          if (isrcs != null && isrcs.isNotEmpty) {
            return isrcs[0] as String;
          }
        }
      }
    } catch (e) {
       print("MusicBrainz error: $e");
    }
    return null;
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }
}

class SpotifyPlaylist {
  final String id;
  final String title;
  final List<SpotifyTrack> tracks;
  
  SpotifyPlaylist({
    required this.id,
    required this.title,
    required this.tracks,
  });
}

class SpotifyTrack {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? duration;
  final String? isrc;
  
  SpotifyTrack({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.isrc,
  });
  
  /// Check if this track is likely a remix
  bool get isRemix {
    final lower = title.toLowerCase();
    return lower.contains('remix') ||
           lower.contains('bootleg') ||
           lower.contains('edit)') ||
           lower.contains('edit]');
  }
  
  /// Check if this track is a cover
  bool get isCover {
    final lower = title.toLowerCase();
    return lower.contains('cover') || lower.contains('acoustic version');
  }
  
  /// Get search queries for finding this track on Tidal
  List<String> get searchQueries {
    final queries = <String>[];
    
    // Primary: title + artist
    if (artist != null && artist!.isNotEmpty) {
      queries.add('$title $artist');
    }
    
    // Secondary: just title
    queries.add(title);
    
    // Tertiary: title + album if available
    if (album != null && album!.isNotEmpty) {
      queries.add('$title $album');
    }
    
    return queries;
  }
  
  String get searchQuery => searchQueries.first;
}
