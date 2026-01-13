import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/hive_service.dart';

class LibraryProvider with ChangeNotifier {
  List<Track> _likedSongs = [];
  List<Track> _downloadedSongs = [];
  List<Playlist> _playlists = [];

  List<Track> get likedSongs => _likedSongs;
  List<Track> get downloadedSongs => _downloadedSongs;
  List<Playlist> get playlists => _playlists;

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
}
