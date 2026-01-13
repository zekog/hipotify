import 'package:hive_flutter/hive_flutter.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';

class HiveService {
  static const String boxSettings = 'settings';
  static const String boxLikes = 'likes';
  static const String boxDownloads = 'downloads';
  static const String boxPlaylists = 'playlists';
  static const String boxHistory = 'history';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(boxSettings);
    await Hive.openBox(boxLikes);
    await Hive.openBox(boxDownloads);
    await Hive.openBox(boxPlaylists);
    await Hive.openBox(boxHistory);
  }

  // Settings
  static Box get settingsBox => Hive.box(boxSettings);
  
  static String? get apiUrl => settingsBox.get('apiUrl');
  static Future<void> setApiUrl(String url) => settingsBox.put('apiUrl', url);

  static String get audioQuality => settingsBox.get('audioQuality', defaultValue: 'LOSSLESS');
  static Future<void> setAudioQuality(String quality) => settingsBox.put('audioQuality', quality);

  // Likes
  static Box get likesBox => Hive.box(boxLikes);

  static List<Track> getLikedSongs() {
    return likesBox.values.map((e) {
      // Assuming we store as Map/JSON
      return Track.fromJson(Map<String, dynamic>.from(e));
    }).toList();
  }

  static Future<void> toggleLike(Track track) async {
    if (likesBox.containsKey(track.id)) {
      await likesBox.delete(track.id);
    } else {
      await likesBox.put(track.id, track.toJson());
    }
  }

  static bool isLiked(String trackId) => likesBox.containsKey(trackId);

  // Downloads
  static Box get downloadsBox => Hive.box(boxDownloads);

  static Future<void> saveDownload(Track track, String localPath) async {
    final downloadedTrack = track.copyWith(localPath: localPath);
    await downloadsBox.put(track.id, downloadedTrack.toJson());
  }

  static Track? getDownloadedTrack(String trackId) {
    final data = downloadsBox.get(trackId);
    if (data != null) {
      return Track.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }
  
  static Future<void> removeDownload(String trackId) async {
    await downloadsBox.delete(trackId);
  }

  // History
  static Box get historyBox => Hive.box(boxHistory);

  static List<Track> getRecentlyPlayed() {
    final List<dynamic> history = historyBox.get('tracks', defaultValue: []);
    return history.map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<void> addToHistory(Track track) async {
    // 1. Tracks
    final List<dynamic> history = historyBox.get('tracks', defaultValue: []);
    final List<Map<String, dynamic>> newHistory = history
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['id'] != track.id)
        .toList();
    
    newHistory.insert(0, track.toJson());
    if (newHistory.length > 30) {
      newHistory.removeLast();
    }
    await historyBox.put('tracks', newHistory);

    // 2. Albums
    final List<dynamic> albums = historyBox.get('albums', defaultValue: []);
    final List<Map<String, dynamic>> newAlbums = albums
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['id'] != track.albumId)
        .toList();
    
    final album = Album(
      id: track.albumId,
      title: track.albumTitle,
      artistName: track.artistName,
      artistId: track.artistId,
      coverUuid: track.albumCoverUuid,
    );
    
    newAlbums.insert(0, album.toJson());
    if (newAlbums.length > 20) {
      newAlbums.removeLast();
    }
    await historyBox.put('albums', newAlbums);

    // 3. Artists
    final List<dynamic> artists = historyBox.get('artists', defaultValue: []);
    final List<Map<String, dynamic>> newArtists = artists
        .where((e) => e is Map)
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['id'] != track.artistId)
        .toList();
    
    final artist = Artist(
      id: track.artistId,
      name: track.artistName,
      pictureUuid: track.artistPictureUuid ?? '',
    );
    
    newArtists.insert(0, artist.toJson());
    if (newArtists.length > 20) {
      newArtists.removeLast();
    }
    await historyBox.put('artists', newArtists);
  }

  static List<Album> getRecentAlbums() {
    final List<dynamic> albums = historyBox.get('albums', defaultValue: []);
    return albums
        .where((e) => e is Map)
        .map((e) => Album.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<Artist> getRecentArtists() {
    final List<dynamic> artists = historyBox.get('artists', defaultValue: []);
    try {
      return artists.map((e) {
        if (e is! Map) {
          // Legacy format (String) or corrupted data, skip
          return null;
        }
        return Artist.fromJson(Map<String, dynamic>.from(e));
      }).whereType<Artist>().toList();
    } catch (e) {
      print("Error parsing recent artists: $e");
      return [];
    }
  }

  static Future<void> clearAll() async {
    await settingsBox.clear();
    await likesBox.clear();
    await downloadsBox.clear();
    await historyBox.clear();
    await Hive.box(boxPlaylists).clear();
  }
}
