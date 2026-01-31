import 'dart:io';
import 'package:discord_rpc/discord_rpc.dart';
import '../models/track.dart';

class DiscordRpcService {
  static const String _appId = '1335028591873130638'; 
  static bool _initialized = false;
  static DiscordRPC? _rpc;

  static void init() {
    if (_initialized || !Platform.isLinux) return; // Only enable on Linux for now
    try {
      DiscordRPC.initialize();
      _rpc = DiscordRPC(applicationId: _appId);
      _rpc!.start(autoRegister: true);
      _initialized = true;
      print("Discord RPC Initialized (via discord_rpc package)");
    } catch (e) {
      print("Error initializing Discord RPC: $e");
      _initialized = false;
    }
  }

  static Future<void> updatePresence(Track track, {bool isPaused = false, int? positionSeconds}) async {
    if (!_initialized || _rpc == null) return;

    try {
      _rpc!.updatePresence(
        DiscordPresence(
          state: track.artistName,
          details: track.title,
          startTimeStamp: !isPaused ? DateTime.now().millisecondsSinceEpoch : null,
          largeImageKey: 'logo',
          largeImageText: 'Hipotify',
          smallImageKey: isPaused ? 'pause' : 'play',
          smallImageText: isPaused ? 'Paused' : 'Playing',
        ),
      );
    } catch (e) {
      print("Error updating Discord presence: $e");
    }
  }
  
  static void clear() {
    if (!_initialized || _rpc == null) return;
    try {
      _rpc!.clearPresence();
    } catch (e) {
      print("Error clearing Discord activity: $e");
    }
  }
  
  static void dispose() {
    if (!_initialized || _rpc == null) return;
    try {
      _rpc!.shutDown();
    } catch (e) {
      print("Error shutting down Discord RPC: $e");
    }
    _rpc = null;
    _initialized = false;
  }
}
