import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for extracting playlist data from YouTube Music/YouTube
class YouTubeMusicService {
  static final http.Client _client = http.Client();
  
  /// Extracts playlist ID from various YouTube/YTMusic URL formats
  static String? extractPlaylistId(String url) {
    final patterns = [
      RegExp(r'[?&]list=([a-zA-Z0-9_-]+)'),
      RegExp(r'youtube\.com/playlist\?list=([a-zA-Z0-9_-]+)'),
      RegExp(r'music\.youtube\.com/playlist\?list=([a-zA-Z0-9_-]+)'),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
  
  /// Fetches playlist metadata and track list using YouTube's internal API
  static Future<YouTubePlaylist?> fetchPlaylist(String playlistId) async {
    try {
      final url = 'https://www.youtube.com/playlist?list=$playlistId';
      final response = await _client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      });
      
      if (response.statusCode != 200) {
        print("YouTubeMusicService: Failed to fetch playlist page: ${response.statusCode}");
        return null;
      }
      
      final html = response.body;
      
      // Extract ytInitialData JSON from the page
      final dataMatch = RegExp(r'var ytInitialData = (\{.+?\});', dotAll: true).firstMatch(html);
      if (dataMatch == null) {
        final altMatch = RegExp(r'ytInitialData\s*=\s*(\{.+?\});', dotAll: true).firstMatch(html);
        if (altMatch == null) {
          print("YouTubeMusicService: Could not find ytInitialData in page");
          return null;
        }
        return _parseYtInitialData(altMatch.group(1)!);
      }
      
      return _parseYtInitialData(dataMatch.group(1)!);
    } catch (e) {
      print("YouTubeMusicService: Error fetching playlist: $e");
      return null;
    }
  }
  
  static YouTubePlaylist? _parseYtInitialData(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      
      // Navigate to playlist content
      final contents = data['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]
          ?['tabRenderer']?['content']?['sectionListRenderer']?['contents']?[0]
          ?['itemSectionRenderer']?['contents']?[0]?['playlistVideoListRenderer']?['contents'];
      
      if (contents == null || contents is! List) {
        print("YouTubeMusicService: Could not find playlist contents");
        return null;
      }
      
      // Extract playlist title
      final metadata = data['metadata']?['playlistMetadataRenderer'];
      final title = metadata?['title'] as String? ?? 'Unknown Playlist';
      
      // Extract tracks
      final tracks = <YouTubeTrack>[];
      for (final item in contents) {
        final videoRenderer = item['playlistVideoRenderer'];
        if (videoRenderer == null) continue;
        
        final videoId = videoRenderer['videoId'] as String?;
        final titleRuns = videoRenderer['title']?['runs'] as List?;
        final videoTitle = titleRuns?.isNotEmpty == true 
            ? titleRuns![0]['text'] as String? 
            : null;
        
        // Extract artist from short byline or owner text
        String? artist;
        final shortByline = videoRenderer['shortBylineText']?['runs'] as List?;
        if (shortByline?.isNotEmpty == true) {
          artist = shortByline![0]['text'] as String?;
        }
        
        // Try to get more metadata from videoInfo
        final videoInfo = videoRenderer['videoInfo']?['runs'] as List?;
        
        // Duration
        final lengthText = videoRenderer['lengthText']?['simpleText'] as String?;
        
        // Index in playlist
        final index = videoRenderer['index']?['simpleText'] as String?;
        
        if (videoId != null && videoTitle != null) {
          tracks.add(YouTubeTrack.parse(
            videoId: videoId,
            originalTitle: videoTitle,
            channelName: artist,
            duration: lengthText,
            index: index,
          ));
        }
      }
      
      return YouTubePlaylist(
        id: '',
        title: title,
        tracks: tracks,
      );
    } catch (e) {
      print("YouTubeMusicService: Error parsing ytInitialData: $e");
      return null;
    }
  }
}

class YouTubePlaylist {
  final String id;
  final String title;
  final List<YouTubeTrack> tracks;
  
  YouTubePlaylist({
    required this.id,
    required this.title,
    required this.tracks,
  });
}

class YouTubeTrack {
  final String videoId;
  final String title;           // Cleaned title (just the song name)
  final String? artist;         // Extracted artist
  final String? duration;
  final String originalTitle;   // Full original title
  final bool isRemix;           // Whether this is a remix
  final bool isCover;           // Whether this is a cover
  final String? featuredArtist; // Featured artist if any
  
  YouTubeTrack({
    required this.videoId,
    required this.title,
    this.artist,
    this.duration,
    required this.originalTitle,
    this.isRemix = false,
    this.isCover = false,
    this.featuredArtist,
  });
  
  /// Smart parsing of YouTube video title to extract song metadata
  factory YouTubeTrack.parse({
    required String videoId,
    required String originalTitle,
    String? channelName,
    String? duration,
    String? index,
  }) {
    String workingTitle = originalTitle;
    String? artist = channelName;
    String? featuredArtist;
    bool isRemix = false;
    bool isCover = false;
    
    // Detect remix/cover/live
    final lowerTitle = originalTitle.toLowerCase();
    isRemix = lowerTitle.contains('remix') || 
              lowerTitle.contains('bootleg') ||
              lowerTitle.contains('edit)') ||
              lowerTitle.contains('edit]');
    isCover = lowerTitle.contains('cover') || lowerTitle.contains('acoustic version');
    
    // Remove common suffixes
    final suffixPatterns = [
      RegExp(r'\s*[\(\[](Official\s*)?(Music\s*)?(Video|Audio|Lyric|Lyrics|Visualizer|MV|M/V|AMV|PV)[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]HD[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]4K[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]HQ[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]Explicit[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]Clean[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]Remastered[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]\d{4}\s*(Remaster)?[\)\]]', caseSensitive: false), // Year
      RegExp(r'\s*[\(\[]VEVO[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[](Full\s*(Song|Version|Audio))[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[]prod\.?\s*[^\)\]]+[\)\]]', caseSensitive: false), // Producer credits
      RegExp(r'\s*【[^】]+】', caseSensitive: false), // Japanese brackets
      RegExp(r'\s*「[^」]+」', caseSensitive: false), // Japanese quotes
    ];
    
    for (final pattern in suffixPatterns) {
      workingTitle = workingTitle.replaceAll(pattern, '');
    }
    
    // Extract featured artist patterns
    final featPatterns = [
      RegExp(r'\s*[\(\[](?:feat\.?|ft\.?|featuring)\s+([^\)\]]+)[\)\]]', caseSensitive: false),
      RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+(.+?)(?:\s*[-–|]|$)', caseSensitive: false),
    ];
    
    for (final pattern in featPatterns) {
      final match = pattern.firstMatch(workingTitle);
      if (match != null) {
        featuredArtist = match.group(1)?.trim();
        workingTitle = workingTitle.replaceFirst(pattern, '');
      }
    }
    
    // Try to extract "Artist - Title" format
    final separatorPatterns = [
      RegExp(r'^(.+?)\s*[-–—|]\s*(.+)$'),  // Standard separators
      RegExp(r'^(.+?)\s*「(.+?)」'),        // Japanese format
      RegExp(r'^(.+?)\s*『(.+?)』'),        // Japanese format alt
    ];
    
    for (final pattern in separatorPatterns) {
      final match = pattern.firstMatch(workingTitle);
      if (match != null) {
        final part1 = match.group(1)?.trim() ?? '';
        final part2 = match.group(2)?.trim() ?? '';
        
        // Heuristics: If channel is "Topic", part1 is likely the artist
        // If part1 is shorter and doesn't contain certain keywords, it's likely the artist
        if (channelName?.contains('Topic') == true ||
            channelName?.contains('VEVO') == true ||
            (part1.length < part2.length && !_looksLikeSongTitle(part1))) {
          artist = part1;
          workingTitle = part2;
        } else if (_looksLikeArtistName(part1)) {
          artist = part1;
          workingTitle = part2;
        }
        break;
      }
    }
    
    // Clean up artist name
    if (artist != null) {
      artist = artist
          .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
          .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*Official$', caseSensitive: false), '')
          .trim();
    }
    
    // Final cleanup
    workingTitle = workingTitle
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    return YouTubeTrack(
      videoId: videoId,
      title: workingTitle,
      artist: artist,
      duration: duration,
      originalTitle: originalTitle,
      isRemix: isRemix,
      isCover: isCover,
      featuredArtist: featuredArtist,
    );
  }
  
  static bool _looksLikeSongTitle(String text) {
    final lower = text.toLowerCase();
    return lower.contains('song') ||
           lower.contains('remix') ||
           lower.contains('version') ||
           lower.contains('intro') ||
           lower.contains('outro');
  }
  
  static bool _looksLikeArtistName(String text) {
    // Artists often have all caps names or capitalized words
    final words = text.split(' ');
    if (words.length <= 3) return true;
    return false;
  }
  
  /// Creates multiple search queries for finding this track (ordered by priority)
  List<String> get searchQueries {
    final queries = <String>[];
    
    // Primary: cleaned title + artist
    if (artist != null && artist!.isNotEmpty) {
      queries.add('$title $artist');
    }
    
    // Secondary: just the cleaned title
    queries.add(title);
    
    // Tertiary: title with featured artist
    if (featuredArtist != null) {
      queries.add('$title $featuredArtist');
    }
    
    // Fallback: use original title but cleaned
    if (queries.length < 3) {
      final fallback = originalTitle
          .replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), '')
          .trim();
      if (!queries.contains(fallback)) {
        queries.add(fallback);
      }
    }
    
    return queries;
  }
  
  /// Legacy single query
  String get searchQuery => searchQueries.first;
}
