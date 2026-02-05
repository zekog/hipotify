import '../services/spotify_service.dart';
import '../services/youtube_music_service.dart';

enum TrackSource {
  spotify,
  youtube,
}

class ConvertibleTrack {
  final String title;
  final String? artist;
  final String? album;
  final String originalId;
  final String? isrc;
  final Duration? duration;
  final TrackSource source;
  final bool isRemix;
  final bool isCover;

  ConvertibleTrack({
    required this.title,
    this.artist,
    this.album,
    required this.originalId,
    this.isrc,
    this.duration,
    required this.source,
    this.isRemix = false,
    this.isCover = false,
  });

  factory ConvertibleTrack.fromSpotify(SpotifyTrack track) {
    return ConvertibleTrack(
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: _parseDuration(track.duration),
      originalId: track.id,
      isrc: track.isrc,
      source: TrackSource.spotify,
      isRemix: track.isRemix,
      isCover: track.isCover,
    );
  }

  factory ConvertibleTrack.fromYouTube(YouTubeTrack track) {
    return ConvertibleTrack(
      title: track.title,
      artist: track.artist,
      duration: _parseDuration(track.duration),
      originalId: track.videoId,
      source: TrackSource.youtube,
      isRemix: track.isRemix,
      isCover: track.isCover,
    );
  }

  static Duration? _parseDuration(String? durationStr) {
    if (durationStr == null) return null;
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      } else if (parts.length == 3) {
        return Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1]), seconds: int.parse(parts[2]));
      }
    } catch (_) {}
    return null;
  }

  /// Get search queries for finding this track on Tidal
  List<String> get searchQueries {
    final queries = <String>[];
    
    final cleanTitle = _cleanTitle(title);
    final primaryArtist = _getPrimaryArtist(artist);
    
    // 1. Clean Title + Primary Artist (Most likely to succeed)
    if (primaryArtist != null) {
      queries.add('$cleanTitle $primaryArtist');
    }
    
    // 2. Original Title + Primary Artist (In case cleaning removed too much)
    if (title != cleanTitle && primaryArtist != null) {
      queries.add('$title $primaryArtist');
    }
    
    // 3. Just Clean Title
    queries.add(cleanTitle);
    
    // 4. Just Original Title
    if (title != cleanTitle) {
      queries.add(title);
    }
    
    // 5. Title + Album (if available)
    if (album != null && album!.isNotEmpty) {
      queries.add('$cleanTitle $album');
    }
    
    return queries;
  }
  
  String _cleanTitle(String text) {
    // Remove common junk like (feat. X), [Official Video], etc.
    var clean = text;
    
    final patterns = [
      RegExp(r'\s*[\(\[](?:feat\.?|ft\.?|featuring)[^\)\]]+[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[](?:Official|Music|Video|Audio|Lyric|Cover|Prod\.?)[^\)\]]*[\)\]]', caseSensitive: false),
      RegExp(r'\s*[\(\[](?:Remastered|Remaster)[^\)\]]*[\)\]]', caseSensitive: false),
      RegExp(r'\s*-\s*(?:Remastered|Remaster).*$', caseSensitive: false),
    ];
    
    for (final pattern in patterns) {
      clean = clean.replaceAll(pattern, '');
    }
    
    return clean.trim();
  }
  
  String? _getPrimaryArtist(String? artist) {
    if (artist == null) return null;
    // content before first comma or 'feat' or 'ft' or '&'
    // Actually, sometimes "&" implies a duo name, so be careful.
    // Safest is to take up to the first comma.
    if (artist.contains(',')) {
      return artist.split(',').first.trim();
    }
    return artist;
  }
}
