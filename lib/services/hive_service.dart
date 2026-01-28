import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/tidal_playlist.dart';

class HiveService {
  static const String boxSettings = 'settings';
  static const String boxLikes = 'likes';
  static const String boxDownloads = 'downloads';
  static const String boxPlaylists = 'playlists';
  static const String boxSavedTidalPlaylists = 'saved_tidal_playlists';
  static const String boxHistory = 'history';

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  static Future<void> init() async {
    if (_isInitialized) return;
    print("HiveService: Initializing Hive...");
    try {
      await Hive.initFlutter('hipotify');
      print("HiveService: Opening boxes...");
      await Hive.openBox(boxSettings);
      await Hive.openBox(boxLikes);
      await Hive.openBox(boxDownloads);
      await Hive.openBox(boxPlaylists);
      await Hive.openBox(boxSavedTidalPlaylists);
      await Hive.openBox(boxHistory);
      _isInitialized = true;
      // Initialize AMOLED mode notifier with saved value
      amoledModeNotifier.value = settingsBox.get('amoledMode', defaultValue: false);
      print("HiveService: Initialization complete.");
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  // Settings
  static Box get settingsBox {
    if (!_isInitialized) throw HiveError("Hive not initialized");
    return Hive.box(boxSettings);
  }
  
  static String? get apiUrl => settingsBox.get('apiUrl');
  static Future<void> setApiUrl(String url) => settingsBox.put('apiUrl', url);

  static String get audioQuality => settingsBox.get('audioQuality', defaultValue: 'LOSSLESS');
  static Future<void> setAudioQuality(String quality) => settingsBox.put('audioQuality', quality);

  static final ValueNotifier<bool> amoledModeNotifier = ValueNotifier<bool>(false);
  
  static bool get amoledMode => amoledModeNotifier.value;
  static Future<void> setAmoledMode(bool enabled) async {
    await settingsBox.put('amoledMode', enabled);
    amoledModeNotifier.value = enabled;
  }

  // Likes
  static Box get likesBox {
    if (!_isInitialized) throw HiveError("Hive not initialized");
    return Hive.box(boxLikes);
  }

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
  static Box get downloadsBox {
    if (!_isInitialized) throw HiveError("Hive not initialized");
    return Hive.box(boxDownloads);
  }

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

  // Playlists
  static Box get playlistsBox {
    if (!_isInitialized) throw HiveError("Hive not initialized");
    return Hive.box(boxPlaylists);
  }

  static List<Playlist> getPlaylists() {
    try {
      return playlistsBox.values
          .where((e) => e is Map)
          .map((e) {
            try {
              return Playlist.fromJson(Map<String, dynamic>.from(e));
            } catch (err) {
              print("Error parsing playlist: $err");
              return null;
            }
          })
          .whereType<Playlist>()
          .toList();
    } catch (e) {
      print("Error loading playlists: $e");
      return [];
    }
  }

  static Playlist? getPlaylist(String playlistId) {
    try {
      final data = playlistsBox.get(playlistId);
      if (data is Map) {
        return Playlist.fromJson(Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e) {
      print("Error loading playlist $playlistId: $e");
      return null;
    }
  }

  static Future<void> savePlaylist(Playlist playlist) async {
    await playlistsBox.put(playlist.id, playlist.toJson());
  }

  static Future<void> deletePlaylist(String playlistId) async {
    await playlistsBox.delete(playlistId);
  }

  // Saved Tidal Playlists
  static Box get savedTidalPlaylistsBox {
    if (!_isInitialized) throw HiveError("Hive not initialized");
    return Hive.box(boxSavedTidalPlaylists);
  }

  static List<TidalPlaylist> getSavedTidalPlaylists() {
    return savedTidalPlaylistsBox.values
        .map((e) => TidalPlaylist.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> saveTidalPlaylist(TidalPlaylist playlist) async {
    await savedTidalPlaylistsBox.put(playlist.id, playlist.toJson());
  }

  static Future<void> removeTidalPlaylist(String playlistId) async {
    await savedTidalPlaylistsBox.delete(playlistId);
  }

  static bool isTidalPlaylistSaved(String playlistId) => savedTidalPlaylistsBox.containsKey(playlistId);

  // History
  static Box get historyBox {
    if (!_isInitialized) throw HiveError("Hive not initialized");
    return Hive.box(boxHistory);
  }

  static List<Track> getRecentlyPlayed() {
    final List<dynamic> history = historyBox.get('tracks', defaultValue: []);
    return history.map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<void> addToHistory(Track track) async {
    // 1. Tracks
    final List<dynamic> history = historyBox.get('tracks', defaultValue: []);
    final List<Map<String, dynamic>> newHistory = history
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['id']?.toString() != track.id.toString())
        .toList();
    
    newHistory.insert(0, track.toJson());
    if (newHistory.length > 30) {
      newHistory.removeLast();
    }
    print("HiveService: Adding track ${track.title} (${track.id}) to history. New history length: ${newHistory.length}");
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

  // Search History
  static const String searchHistoryKey = 'search_history';

  static List<String> getSearchHistory() {
    final List<dynamic> history = historyBox.get(searchHistoryKey, defaultValue: []);
    return history.map((e) => e.toString()).toList();
  }

  static Future<void> addToSearchHistory(String query) async {
    if (query.trim().isEmpty) return;
    
    final List<dynamic> history = historyBox.get(searchHistoryKey, defaultValue: []);
    final List<String> newHistory = history.map((e) => e.toString()).toList();
    
    // Remove if already exists
    newHistory.remove(query.trim());
    
    // Add to beginning
    newHistory.insert(0, query.trim());
    
    // Limit to 8 items
    if (newHistory.length > 8) {
      newHistory.removeRange(8, newHistory.length);
    }
    
    await historyBox.put(searchHistoryKey, newHistory);
  }

  static Future<void> removeFromSearchHistory(String query) async {
    final List<dynamic> history = historyBox.get(searchHistoryKey, defaultValue: []);
    final List<String> newHistory = history.map((e) => e.toString()).toList();
    
    newHistory.remove(query.trim());
    
    await historyBox.put(searchHistoryKey, newHistory);
  }

  static Future<void> clearSearchHistory() async {
    await historyBox.delete(searchHistoryKey);
  }

  static Future<void> clearAll() async {
    await settingsBox.clear();
    await likesBox.clear();
    await downloadsBox.clear();
    await historyBox.clear();
    await Hive.box(boxPlaylists).clear();
  }
}
