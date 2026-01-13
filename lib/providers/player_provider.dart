import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import '../models/lyrics.dart';
import '../services/api_service.dart';
import '../services/hive_service.dart';

class PlayerProvider with ChangeNotifier, WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  List<Track> _queue = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _currentMetadata;
  Lyrics? _currentLyrics;

  AudioPlayer get player => _player;
  List<Track> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get currentMetadata => _currentMetadata;
  Lyrics? get currentLyrics => _currentLyrics;
  Track? get currentTrack => _queue.isNotEmpty && _currentIndex < _queue.length ? _queue[_currentIndex] : null;
  
  // MiniPlayer visibility logic
  bool _isMiniPlayerHidden = false;
  bool get isMiniPlayerHidden => _isMiniPlayerHidden;

  void setMiniPlayerHidden(bool hidden) {
    _isMiniPlayerHidden = hidden;
    notifyListeners();
  }



  ConcatenatingAudioSource? _playlist;
  int _windowStartIndex = 0;

  PlayerProvider() {
    _init();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _player.stop();
    }
  }

  void _init() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // If we reached the end of the buffer, try to load more?
        // Usually sequenceState handles the transition.
      }
      notifyListeners();
    });
    
    // Listen to current item index in the ConcatenatingAudioSource
    _player.currentIndexStream.listen((index) {
      if (index != null) {
        // Update the global queue index based on the window start
        final newQueueIndex = _windowStartIndex + index;
        if (newQueueIndex != _currentIndex && newQueueIndex >= 0 && newQueueIndex < _queue.length) {
          _currentIndex = newQueueIndex;
          _fetchLyrics(_queue[_currentIndex].id);
          HiveService.addToHistory(_queue[_currentIndex]);
          notifyListeners();
          // Preload neighbors when index changes
          _updatePlaybackWindow();
        }
      }
    });

    // Listen to sequence state for background skips
    _player.sequenceStateStream.listen((sequenceState) {
      if (sequenceState == null) return;
      final index = sequenceState.currentIndex;
      // The index here is relative to the ConcatenatingAudioSource
      final newQueueIndex = _windowStartIndex + index;
      if (newQueueIndex != _currentIndex && newQueueIndex >= 0 && newQueueIndex < _queue.length) {
        _currentIndex = newQueueIndex;
        _fetchLyrics(_queue[_currentIndex].id);
        notifyListeners();
        _updatePlaybackWindow();
      }
    });
  }

  Future<void> playTrack(Track track) async {
    _queue = [track];
    _currentIndex = 0;
    await _loadAndPlayQueue();
  }

  Future<void> playPlaylist(List<Track> tracks, {int initialIndex = 0}) async {
    _queue = List.from(tracks);
    _currentIndex = initialIndex;
    await _loadAndPlayQueue();
  }

  Future<void> _loadAndPlayQueue() async {
    if (_queue.isEmpty) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Initialize window at current index
      _windowStartIndex = _currentIndex;
      
      // Load ONLY the current track initially for speed
      final track = _queue[_currentIndex];
      final uri = await _getUri(track);
      
      final audioSource = AudioSource.uri(
        uri,
        tag: track.toMediaItem(),
      );

      _playlist = ConcatenatingAudioSource(children: [audioSource]);
      
      await _player.setAudioSource(_playlist!);
      await _player.play();
      HiveService.addToHistory(_queue[_currentIndex]);

      // After playback starts, load neighbors
      _updatePlaybackWindow();

    } catch (e) {
      print("Error playing track: $e");
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updatePlaybackWindow() async {
    if (_playlist == null) return;

    // We want to ensure we have [Prev, Current, Next] loaded if possible.
    // Actually, for "Skip" to work, we definitely need Next.
    // For "Prev" to work, we need Prev.
    
    // 1. Load Next if missing
    // The index of 'Current' in playlist is (_currentIndex - _windowStartIndex)
    final playerIndex = _currentIndex - _windowStartIndex;
    
    // Check if we have a Next in Queue but not in Playlist
    // Playlist length is _playlist!.length
    // If playerIndex is the last item, we need to add one if queue has more.
    if (playerIndex == _playlist!.length - 1 && _currentIndex < _queue.length - 1) {
      _fetchAndAddNext(_currentIndex + 1);
    }

    // 2. Load Prev if missing
    // If playerIndex is 0 and we have items before in queue
    if (playerIndex == 0 && _currentIndex > 0) {
      _fetchAndAddPrev(_currentIndex - 1);
    }
  }

  Future<void> _fetchAndAddNext(int queueIndex) async {
    try {
      final track = _queue[queueIndex];
      print("Preloading Next: ${track.title}");
      final uri = await _getUri(track);
      final source = AudioSource.uri(uri, tag: track.toMediaItem());
      await _playlist?.add(source);
    } catch (e) {
      print("Error preloading next: $e");
    }
  }

  Future<void> _fetchAndAddPrev(int queueIndex) async {
    try {
      final track = _queue[queueIndex];
      print("Preloading Prev: ${track.title}");
      final uri = await _getUri(track);
      final source = AudioSource.uri(uri, tag: track.toMediaItem());
      await _playlist?.insert(0, source);
      // Since we inserted at 0, the window start index decreases
      _windowStartIndex--;
    } catch (e) {
      print("Error preloading prev: $e");
    }
  }

  Future<Uri> _getUri(Track track) async {
     // 1. Check Offline
     final downloadedTrack = HiveService.getDownloadedTrack(track.id);
     if (downloadedTrack != null && downloadedTrack.localPath != null && await File(downloadedTrack.localPath!).exists()) {
       return Uri.file(downloadedTrack.localPath!);
     }
     
     // 2. Fetch Metadata
     // If it's the current track, we might want to update _currentMetadata
     // But for preloading, we shouldn't overwrite it if it's not playing?
     // Actually, _currentMetadata is just for UI.
     final metadata = await ApiService.getStreamMetadata(track.id);
     
     if (track.id == _queue[_currentIndex].id) {
       _currentMetadata = metadata;
       _fetchLyrics(track.id);
     }
     
     final url = metadata['url']?.toString();
     if (url == null || url.isEmpty) {
       throw Exception("No stream URL found for track: ${track.title}");
     }
     
     return Uri.parse(url);
  }

  Future<void> next() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else if (_currentIndex < _queue.length - 1) {
      // If player doesn't have next (loading failed?), try to force load
      _currentIndex++;
      await _loadAndPlayQueue();
    }
  }

  Future<void> previous() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlayQueue();
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }
  void _fetchLyrics(String trackId) {
    _currentLyrics = null;
    notifyListeners();
    
    ApiService.getLyrics(trackId).then((lyrics) {
      if (_queue.isNotEmpty && _currentIndex < _queue.length && _queue[_currentIndex].id == trackId) {
        _currentLyrics = lyrics;
        notifyListeners();
      }
    });
  }
}

