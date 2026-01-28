import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../models/tidal_playlist.dart';
import '../services/hive_service.dart';

class LibraryProvider with ChangeNotifier {
  List<Track> _likedSongs = [];
  List<Track> _downloadedSongs = [];
  List<Playlist> _playlists = [];
  List<TidalPlaylist> _savedTidalPlaylists = [];

  List<Track> get likedSongs => _likedSongs;
  List<Track> get downloadedSongs => _downloadedSongs;
  List<Playlist> get playlists => _playlists;
  List<TidalPlaylist> get savedTidalPlaylists => _savedTidalPlaylists;

  LibraryProvider() {
    _loadLibrary();
  }

  void _loadLibrary() {
    _likedSongs = HiveService.getLikedSongs();
    
    // Load downloads
    final downloadKeys = HiveService.downloadsBox.keys;
    _downloadedSongs = downloadKeys
        .map((key) => HiveService.getDownloadedTrack(key.toString()))
        .whereType<Track>()
        .toList();

    // Load playlists
    _playlists = HiveService.getPlaylists();
    _savedTidalPlaylists = HiveService.getSavedTidalPlaylists();

    notifyListeners();
  }

  Future<void> toggleLike(Track track) async {
    await HiveService.toggleLike(track);
    _loadLibrary(); // Reload to update UI
  }

  bool isLiked(String trackId) {
    return HiveService.isLiked(trackId);
  }

  Future<void> refreshDownloads() async {
    _loadLibrary();
  }

  Playlist? getPlaylistById(String playlistId) {
    try {
      return _playlists.firstWhere((p) => p.id == playlistId);
    } catch (_) {
      return null;
    }
  }

  Future<Playlist> createPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Playlist name cannot be empty');
    }

    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: trimmed,
      tracks: const [],
    );
    await HiveService.savePlaylist(playlist);
    _loadLibrary();
    return playlist;
  }

  Future<void> deletePlaylist(String playlistId) async {
    await HiveService.deletePlaylist(playlistId);
    _loadLibrary();
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    await HiveService.savePlaylist(playlist);
    _loadLibrary();
  }

  Future<void> reorderPlaylistTracks(String playlistId, int oldIndex, int newIndex) async {
    final playlist = HiveService.getPlaylist(playlistId) ?? getPlaylistById(playlistId);
    if (playlist == null) {
      throw Exception('Playlist not found');
    }

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final tracks = List<Track>.from(playlist.tracks);
    final track = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, track);

    final updated = Playlist(
      id: playlist.id,
      name: playlist.name,
      tracks: tracks,
    );

    await HiveService.savePlaylist(updated);
    _loadLibrary();
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final playlist = HiveService.getPlaylist(playlistId) ?? getPlaylistById(playlistId);
    if (playlist == null) {
      throw Exception('Playlist not found');
    }

    final exists = playlist.tracks.any((t) => t.id == track.id);
    if (exists) return;

    final updated = Playlist(
      id: playlist.id,
      name: playlist.name,
      tracks: [...playlist.tracks, track],
    );

    await HiveService.savePlaylist(updated);
    _loadLibrary();
  }

  Future<bool> toggleTrackInPlaylist(String playlistId, Track track) async {
    final playlist = HiveService.getPlaylist(playlistId) ?? getPlaylistById(playlistId);
    if (playlist == null) {
      throw Exception('Playlist not found');
    }

    final exists = playlist.tracks.any((t) => t.id == track.id);
    final updated = Playlist(
      id: playlist.id,
      name: playlist.name,
      tracks: exists
          ? playlist.tracks.where((t) => t.id != track.id).toList()
          : [...playlist.tracks, track],
    );

    await HiveService.savePlaylist(updated);
    _loadLibrary();
    return !exists; // Return true if added, false if removed
  }

  bool isTrackInPlaylist(String playlistId, String trackId) {
    final playlist = getPlaylistById(playlistId);
    if (playlist == null) return false;
    return playlist.tracks.any((t) => t.id == trackId);
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlist = HiveService.getPlaylist(playlistId) ?? getPlaylistById(playlistId);
    if (playlist == null) {
      throw Exception('Playlist not found');
    }

    final updated = Playlist(
      id: playlist.id,
      name: playlist.name,
      tracks: playlist.tracks.where((t) => t.id != trackId).toList(),
    );

    await HiveService.savePlaylist(updated);
    _loadLibrary();
  }

  // Tidal Playlists
  Future<void> toggleSavePlaylist(TidalPlaylist playlist) async {
    if (HiveService.isTidalPlaylistSaved(playlist.id)) {
      await HiveService.removeTidalPlaylist(playlist.id);
    } else {
      await HiveService.saveTidalPlaylist(playlist);
    }
    _loadLibrary();
  }

  bool isPlaylistSaved(String playlistId) {
    return HiveService.isTidalPlaylistSaved(playlistId);
  }
}
