import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'hive_service.dart';
// import '../providers/player_provider.dart';
import '../models/track.dart';
import 'auth_service.dart';
import 'local_network_service.dart';

enum ControlMode { local, remote }

class RemoteControlService {
  static final RemoteControlService _instance = RemoteControlService._internal();
  factory RemoteControlService() => _instance;
  RemoteControlService._internal();

  String? _currentDeviceId;
  String? _targetDeviceId;
  ControlMode _mode = ControlMode.local;
  
  final _stateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get remoteStateStream => _stateController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  String get deviceId => _currentDeviceId ?? HiveService.deviceId;
  String? get targetDeviceId => _targetDeviceId;
  ControlMode get mode => _mode;

  dynamic _playerProvider;

  void init(dynamic playerProvider) {
    _playerProvider = playerProvider;
    _ensureDeviceId();
    
    LocalNetworkService().start(deviceId, HiveService.deviceName);

    LocalNetworkService().messageStream.listen((payload) {
      if (payload['event'] == 'command') {
        _handleCommand(payload);
      } else if (payload['event'] == 'state_update') {
        if (_mode == ControlMode.remote) {
          // If we connected via IP PIN, auto-update our target ID to the real UUID
          if (_targetDeviceId != null && _targetDeviceId!.contains('.') && payload['from'] != null) {
            final oldIpId = _targetDeviceId!;
            _targetDeviceId = payload['from'];
            LocalNetworkService().addManualDevice(_targetDeviceId!, 'Manual Device', 45456, oldIpId);
          }
          
          if (_targetDeviceId == payload['from'] || payload['from'] == null) {
            print('RemoteControlService: Received state_update from ${payload['from'] ?? 'unknown'}');
            _stateController.add(payload);
          }
        }
      }
    });

    // When connection status changes, sync state
    LocalNetworkService().targetConnectionStream.listen((isConnected) {
       _connectionController.add(isConnected);
       if (isConnected && _targetDeviceId != null) {
           sendCommand(_targetDeviceId!, 'request_state');
       }
    });
  }

  void _ensureDeviceId() {
    String id = HiveService.deviceId;
    if (id.isEmpty) {
      id = const Uuid().v4();
      HiveService.setDeviceId(id);
    }
    _currentDeviceId = id;
  }

  void _handleCommand(Map<String, dynamic>? payload) {
    if (_playerProvider == null || payload == null) return;

    print('RemoteControlService: Received command payload: $payload');
    final command = payload['command'];
    final data = payload['data'];

    if (command == null) return;

    switch (command) {
      case 'play':
        _playerProvider!.play();
        break;
      case 'pause':
        _playerProvider!.pause();
        break;
      case 'next':
        _playerProvider!.next();
        break;
      case 'previous':
        _playerProvider!.previous();
        break;
      case 'seek':
        _playerProvider!.seek(Duration(milliseconds: data['position']));
        break;
      case 'set_volume':
        _playerProvider!.setVolume(data['volume']);
        break;
      case 'play_track':
        final track = Track.fromJson(data['track']);
        _playerProvider!.playTrack(track);
        break;
      case 'play_playlist':
        final tracksList = (data['tracks'] as List)
            .map((t) => Track.fromJson(Map<String, dynamic>.from(t)))
            .toList();
        final initialIndex = data['initialIndex'] as int? ?? 0;
        _playerProvider!.playPlaylist(tracksList, initialIndex: initialIndex);
        break;
      case 'login_transfer':
        final sessionString = data['session'];
        if (sessionString != null) {
          AuthService.recoverSession(sessionString).then((_) {
            print('RemoteControlService: Login session recovered successfully');
          }).catchError((e) {
            print('RemoteControlService: Error recovering login session: $e');
          });
        }
        break;
      case 'sync_transfer':
        print('RemoteControlService: Received Sync Transfer!');
        _handleSyncTransfer(data);
        break;
      case 'request_state':
        if (_mode == ControlMode.local) {
          _playerProvider!.broadcastRemoteStateExplicitly();
        }
        break;
    }
  }

  Future<void> _handleSyncTransfer(Map<String, dynamic> data) async {
    try {
      final sessionData = data['session'];
      if (sessionData != null) {
        String? sessionString;
        if (sessionData is String) sessionString = sessionData;
        else if (sessionData is Map) sessionString = jsonEncode(sessionData);

        if (sessionString != null && sessionString.trim().isNotEmpty) {
          await AuthService.recoverSession(sessionString);
        }
      }
      
      if (data['settings'] != null) {
        final settings = data['settings'] as Map<String, dynamic>;
        if (settings.containsKey('apiUrl')) await HiveService.setApiUrl(settings['apiUrl']);
        if (settings.containsKey('audioQuality')) await HiveService.setAudioQuality(settings['audioQuality']);
        if (settings.containsKey('amoledMode')) await HiveService.setAmoledMode(settings['amoledMode']);
        if (settings.containsKey('themeMode')) await HiveService.setThemeMode(settings['themeMode']);
      }

      if (data['playlists'] != null) {
        await HiveService.playlistsBox.clear();
        for (final p in List<Map<String, dynamic>>.from(data['playlists'])) await HiveService.playlistsBox.put(p['id'], p);
      }

      if (data['saved_tidal_playlists'] != null) {
        await HiveService.savedTidalPlaylistsBox.clear();
        for (final p in List<Map<String, dynamic>>.from(data['saved_tidal_playlists'])) await HiveService.savedTidalPlaylistsBox.put(p['id'], p);
      }

      if (data['likes'] != null) {
        await HiveService.likesBox.clear();
        for (final l in List<Map<String, dynamic>>.from(data['likes'])) await HiveService.likesBox.put(l['id'], l);
      }

      if (data['history'] != null) {
        final history = data['history'] as Map<String, dynamic>;
        if (history['tracks'] != null) await HiveService.historyBox.put('tracks', history['tracks']);
        if (history['albums'] != null) await HiveService.historyBox.put('albums', history['albums']);
        if (history['artists'] != null) await HiveService.historyBox.put('artists', history['artists']);
      }
      
      print('RemoteControlService: Sync Transfer Applied Successfully');
    } catch (e) {
      print('RemoteControlService: Error applying sync transfer: $e');
    }
  }

  void broadcastState(Map<String, dynamic> state) {
    LocalNetworkService().broadcastToClients({
      'event': 'state_update',
      'from': deviceId,
      ...state,
    });
  }

  Future<void> sendCommand(String targetId, String command, [Map<String, dynamic>? data]) async {
    print('RemoteControlService: Sending command $command to $targetId');
    final payload = {
      'event': 'command',
      'from': deviceId,
      'command': command,
      'data': data,
    };

    if (_targetDeviceId == targetId) {
      LocalNetworkService().sendToTarget(payload);
      return;
    }

    // One-off commands (e.g. login transfer) when not set as target
    final device = LocalNetworkService().getDevice(targetId);
    if (device != null) {
      final success = await LocalNetworkService().sendOneOffCommand(device.ip, device.port, payload);
      print(success ? 'Command sent one-off' : 'Command failed to send one-off');
    } else {
      print('RemoteControlService: Cannot send one-off command, device $targetId not discovered yet');
    }
  }

  void sendLoginSession(String targetId) {
    final session = AuthService.currentSession;
    if (session == null) return;
    
    sendCommand(targetId, 'login_transfer', {
       'session': jsonEncode(session.toJson()),
    });
  }

  void remotePlayTrack(Track track) => sendCommand(_targetDeviceId!, 'play_track', {'track': track.toJson()});

  void remotePlayPlaylist(List<Track> tracks, {int initialIndex = 0}) {
    sendCommand(_targetDeviceId!, 'play_playlist', {
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'initialIndex': initialIndex,
    });
  }

  void setControlTarget(String? targetId) {
    _targetDeviceId = targetId;
    _mode = targetId == null ? ControlMode.local : ControlMode.remote;
    
    LocalNetworkService().disconnectTarget();

    if (targetId != null) {
      final device = LocalNetworkService().getDevice(targetId);
      if (device != null) {
         LocalNetworkService().connectToTarget(device.ip, device.port);
         print('RemoteControlService: Starting connection to target $targetId at ${device.ip}:${device.port}');
      } else {
         print('RemoteControlService: Target not found in discovered list');
         _connectionController.add(false);
      }
    } else {
      _connectionController.add(false);
    }
  }

  // Pairing Logic is mostly deprecated but we keep dummy methods so the UI doesn't break
  String generatePairingCode() {
    return "000000"; // Placeholder, as discovery is automatic now
  }
}
