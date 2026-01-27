import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/enums.dart';
import 'package:flutter_chrome_cast/models.dart';
import 'package:flutter_chrome_cast/common/rfc5646_language.dart';
import 'package:just_audio/just_audio.dart';
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

  // Loop mode: 0 = off, 1 = track, 2 = playlist
  int _loopMode = 0;
  int get loopMode => _loopMode;

  Future<void> toggleLoopMode() async {
    _loopMode = (_loopMode + 1) % 3;
    if (_loopMode == 1) {
      // Loop track
      await _player.setLoopMode(LoopMode.one);
    } else if (_loopMode == 2) {
      // Loop playlist
      await _player.setLoopMode(LoopMode.all);
    } else {
      // Off
      await _player.setLoopMode(LoopMode.off);
    }
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
    _initCast();
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
          _currentIndex = newQueueIndex.toInt();
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
        _currentIndex = newQueueIndex.toInt();
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

  Future<void> playRandomTrack() async {
    if (_queue.isEmpty) return;
    final random = (DateTime.now().millisecondsSinceEpoch % _queue.length);
    _currentIndex = random;
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
      
      AudioSource audioSource;
      final urlString = uri.toString();
      
      // Check if this is a DASH manifest (data URI)
      if (urlString.startsWith('data:application/dash+xml')) {
        print("PlayerProvider: Using DASH audio source");
        audioSource = DashAudioSource(
          uri,
          tag: track.toMediaItem(),
        );
      } else {
        audioSource = AudioSource.uri(
          uri,
          tag: track.toMediaItem(),
        );
      }

      _playlist = ConcatenatingAudioSource(children: [audioSource]);
      
      print("PlayerProvider: Setting audio source: $urlString");
      await _player.setAudioSource(_playlist!);
      print("PlayerProvider: Playing...");
      await _player.play();
      print("PlayerProvider: Playback started");
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
      final urlString = uri.toString();
      
      AudioSource source;
      if (urlString.startsWith('data:application/dash+xml')) {
        source = DashAudioSource(uri, tag: track.toMediaItem());
      } else {
        source = AudioSource.uri(uri, tag: track.toMediaItem());
      }
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
      final urlString = uri.toString();
      
      AudioSource source;
      if (urlString.startsWith('data:application/dash+xml')) {
        source = DashAudioSource(uri, tag: track.toMediaItem());
      } else {
        source = AudioSource.uri(uri, tag: track.toMediaItem());
      }
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
    if (_isCasting) {
      if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
        await castCurrentTrack();
        notifyListeners();
      } else if (_loopMode == 2) {
        // Loop playlist - go to first track
        _currentIndex = 0;
        await castCurrentTrack();
        notifyListeners();
      }
      return;
    }
    
    // Check if we can go to next track in queue
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _loadAndPlayQueue();
    } else if (_loopMode == 2) {
      // Loop playlist - go to first track
      _currentIndex = 0;
      await _loadAndPlayQueue();
    } else if (_player.hasNext) {
      // Fallback to player's next (in case of windowing issues)
      await _player.seekToNext();
    }
  }

  Future<void> previous() async {
    if (_isCasting) {
      if (_currentIndex > 0) {
        _currentIndex--;
        await castCurrentTrack();
        notifyListeners();
      } else if (_loopMode == 2) {
        // Loop playlist - go to last track
        _currentIndex = _queue.length - 1;
        await castCurrentTrack();
        notifyListeners();
      }
      return;
    }
    
    // Check if we can go to previous track in queue
    if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlayQueue();
    } else if (_loopMode == 2) {
      // Loop playlist - go to last track
      _currentIndex = _queue.length - 1;
      await _loadAndPlayQueue();
    } else if (_player.hasPrevious) {
      // Fallback to player's previous (in case of windowing issues)
      await _player.seekToPrevious();
    }
  }

  Future<void> togglePlayPause() async {
    if (_isCasting) {
      final state = GoogleCastRemoteMediaClient.instance.mediaStatus?.playerState;
      if (state == CastMediaPlayerState.playing) {
        await GoogleCastRemoteMediaClient.instance.pause();
      } else {
        await GoogleCastRemoteMediaClient.instance.play();
      }
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration position) async {
    if (_isCasting) {
      await GoogleCastRemoteMediaClient.instance.seek(GoogleCastMediaSeekOption(
        position: position,
        resumeState: GoogleCastMediaResumeState.unchanged,
      ));
      return;
    }
    await _player.seek(position);
  }

  void _initCast() async {
    const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
    GoogleCastOptions? options;
    if (Platform.isIOS) {
      options = IOSGoogleCastOptions(
        GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
      );
    } else if (Platform.isAndroid) {
      options = GoogleCastOptionsAndroid(
        appId: appId,
      );
    }
    if (options != null) {
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      print("PlayerProvider: Cast context initialized with appId: $appId");
      
      // Listen to cast status
      _castStatusSubscription?.cancel();
      _castStatusSubscription = GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen((status) {
        print("PlayerProvider: Cast status updated: ${status?.playerState}");
        notifyListeners();
      });

      // Listen to session changes to detect disconnects
      _sessionSubscription?.cancel();
      _sessionSubscription = GoogleCastSessionManager.instance.currentSessionStream.listen((session) {
        final state = session?.connectionState;
        print("PlayerProvider: Cast session updated: ${session?.device?.deviceID}, state: $state");
        
        if (session == null || state == GoogleCastConnectState.disconnected) {
          if (_isCasting) {
            print("PlayerProvider: Session ended or disconnected, resetting state");
            _isCasting = false;
            _connectedDevice = null;
            _castStatusSubscription?.cancel();
            _castStatusSubscription = null;
            notifyListeners();
          }
        } else if (state == GoogleCastConnectState.connected) {
          if (!_isCasting || _connectedDevice?.deviceID != session.device?.deviceID) {
            print("PlayerProvider: Session connected, updating state");
            _isCasting = true;
            _connectedDevice = session.device;
            notifyListeners();
            
            // If we just connected and have a queue, trigger casting
            if (_queue.isNotEmpty) {
              castCurrentTrack();
            }
          }
        } else {
          // Other states (connecting, disconnecting) - just notify to update UI if needed
          notifyListeners();
        }
      });

      // Sync initial session state
      final currentSession = GoogleCastSessionManager.instance.currentSession;
      if (currentSession != null && currentSession.connectionState == GoogleCastConnectState.connected) {
        print("PlayerProvider: Found existing connected session");
        _isCasting = true;
        _connectedDevice = currentSession.device;
        notifyListeners();
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    _castStatusSubscription?.cancel();
    _sessionSubscription?.cancel();
    super.dispose();
  }

  void _fetchLyrics(String trackId) {
    _currentLyrics = null;
    notifyListeners();
    
    ApiService.getLyrics(trackId).then((lyrics) {
      if (_queue.isNotEmpty && _currentIndex < _queue.length && _queue[_currentIndex].id == trackId) {
        _currentLyrics = lyrics;
        notifyListeners();
        
        // If we are casting, we need to update the receiver with the new lyrics
        if (_isCasting) {
          castCurrentTrack();
        }
      }
    });
  }

  // Cast
  List<GoogleCastDevice> _castDevices = [];
  GoogleCastDevice? _connectedDevice;
  bool _isCasting = false;
  StreamSubscription<GoggleCastMediaStatus?>? _castStatusSubscription;
  StreamSubscription<GoogleCastSession?>? _sessionSubscription;
  
  List<GoogleCastDevice> get castDevices => _castDevices;
  GoogleCastDevice? get connectedDevice => _connectedDevice;
  bool get isCasting => _isCasting;

  Future<void> startCastDiscovery() async {
    _castDevices = [];
    notifyListeners();
    try {
      GoogleCastDiscoveryManager.instance.devicesStream.listen((devices) {
        _castDevices = devices;
        notifyListeners();
      });
      await GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (e) {
      // Error discovering cast devices
    }
  }

  Future<void> connectAndCast(GoogleCastDevice device) async {
    try {
      print("PlayerProvider: connectAndCast - Starting session with ${device.friendlyName}");
      // We don't set _isCasting here anymore; the listener will handle it
      // when the connection state transitions to 'connected'.
      await GoogleCastSessionManager.instance.startSessionWithDevice(device);
    } catch (e) {
      print("PlayerProvider: Error connecting to cast device: $e");
      _connectedDevice = null;
      _isCasting = false;
      notifyListeners();
    }
  }

  Future<Uri> _getCastableUri(Track track) async {
    // Try HIGH quality first for casting as it's more likely to be a direct URL (AAC/MP3)
    // than HI_RES_LOSSLESS (DASH data URI)
    try {
      final metadata = await ApiService.getStreamMetadata(track.id, quality: 'HIGH');
      final url = metadata['url'] as String;
      if (!url.startsWith('data:')) {
        print("PlayerProvider: Found direct URL for casting (HIGH): $url");
        return Uri.parse(url);
      }
    } catch (e) {
      print("PlayerProvider: Failed to get HIGH quality URL for casting: $e");
    }
    
    // Fallback to default quality
    return await _getUri(track);
  }

  Future<void> castCurrentTrack() async {
    if (_connectedDevice == null || _queue.isEmpty) return;
    
    final track = _queue[_currentIndex];
    print("PlayerProvider: castCurrentTrack - track: ${track.title}");
    try {
      Uri uri = await _getCastableUri(track);
      print("PlayerProvider: castCurrentTrack - URI: $uri");
      
      // TEST: If you want to test with a public URL, uncomment the line below
      // uri = Uri.parse("https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3");
      
      if (uri.scheme == 'file') {
        print("Cannot cast local file: $uri");
        return;
      }
      
      String contentType = 'audio/mpeg'; // Default
      final uriString = uri.toString().toLowerCase();
      if (uriString.contains('dash+xml') || uri.path.endsWith('.mpd')) {
        contentType = 'application/dash+xml';
      } else if (uri.path.endsWith('.mp4') || uri.path.endsWith('.m4a') || uriString.contains('audio/mp4')) {
        contentType = 'audio/mp4';
      } else if (uri.path.endsWith('.flac') || uriString.contains('audio/flac')) {
        contentType = 'audio/flac';
      } else if (uri.path.endsWith('.wav') || uriString.contains('audio/wav')) {
        contentType = 'audio/wav';
      }
      
      print("PlayerProvider: castCurrentTrack - contentType: $contentType");

      final mediaInfo = GoogleCastMediaInformation(
        contentId: uri.toString(),
        contentUrl: uri,
        streamType: CastMediaStreamType.buffered,
        contentType: contentType,
        duration: _player.duration ?? (track.duration > 0 ? Duration(seconds: track.duration) : null),
        metadata: GoogleCastMusicMediaMetadata(
          title: track.title,
          artist: track.artistName,
          albumName: track.albumTitle,
          images: [
            GoogleCastImage(url: Uri.parse(track.coverUrl))
          ],
          releaseDate: DateTime(2024, 1, 1), // Safe dummy date to avoid NPE
        ),
        tracks: _currentLyrics?.toWebVTT() != null ? [
          GoogleCastMediaTrack(
            trackId: 1,
            type: TrackType.text,
            trackContentId: 'data:text/vtt;base64,${base64Encode(utf8.encode(_currentLyrics!.toWebVTT()!))}',
            trackContentType: 'text/vtt',
            name: 'Lyrics',
            language: Rfc5646Language.english,
            subtype: TextTrackType.subtitles,
          )
        ] : null,
      );

      print("PlayerProvider: castCurrentTrack - Loading media (autoPlay: true)...");
      await GoogleCastRemoteMediaClient.instance.loadMedia(mediaInfo, autoPlay: true);
      print("PlayerProvider: castCurrentTrack - Media loaded successfully");
      
      // Activate lyrics track if available
      if (_currentLyrics?.toWebVTT() != null) {
        await GoogleCastRemoteMediaClient.instance.setActiveTrackIDs([1]);
        print("PlayerProvider: castCurrentTrack - Lyrics track activated");
      }
      
      // Explicitly call play to ensure it starts on some devices
      await GoogleCastRemoteMediaClient.instance.play();
      print("PlayerProvider: castCurrentTrack - Play command sent");
      
      // Pause local player
      _player.pause();
      
    } catch (e, stack) {
      print("Error casting track: $e");
      print(stack);
    }
  }
  
  Future<void> stopCasting() async {
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
      _connectedDevice = null;
      _isCasting = false;
      _castStatusSubscription?.cancel();
      _castStatusSubscription = null;
      notifyListeners();
    } catch (e) {
      // Error stopping cast
    }
  }
}

