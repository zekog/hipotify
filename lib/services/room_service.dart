import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'supabase_config.dart';
import '../models/track.dart';

class RoomService {
  static SupabaseClient get _client {
    if (!SupabaseConfig.isConfigured) {
      throw Exception("Supabase not initialized.");
    }
    return Supabase.instance.client;
  }

  static RealtimeChannel? _channel;

  static Future<String> createRoom(Track initialTrack) async {
    if (!AuthService.isLoggedIn) throw Exception("Login required");

    // Generate a random 6-digit room ID
    final roomId = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
    
    await _client.from('rooms').insert({
      'id': roomId,
      'host_id': AuthService.currentUser!.id,
      'current_track_id': initialTrack.id,
      'current_track_data': initialTrack.toJson(),
      'position_ms': 0,
      'is_playing': true,
    });
    
    return roomId;
  }
  static RealtimeChannel joinChannel(String roomId, {
    required Function(Map<String, dynamic>) onSync,
    required Function(List<dynamic>) onPresenceUpdate,
  }) {
    _channel?.unsubscribe();
    
    final channelName = 'room:$roomId';
    _channel = _client.channel(channelName);

    _channel!.onBroadcast(
      event: 'sync',
      callback: (payload) {
        onSync(payload);
      },
    );

    _channel!.onPresenceSync((payload) {
      final presences = _channel!.presenceState();
      onPresenceUpdate(presences);
    });

    _channel!.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        final user = AuthService.currentUser;
        await _channel!.track({
          'user_id': user?.id,
          'username': user?.email?.split('@')[0] ?? 'Guest',
          'joined_at': DateTime.now().toIso8601String(),
        });
      }
    });

    return _channel!;
  }

  static void broadcastUpdate(String roomId, Map<String, dynamic> data) {
    // Using dynamic to bypass enum visibility issues in different project versions
    (_channel as dynamic)?.send(
      type: 'broadcast',
      event: 'sync',
      payload: data,
    );
  }

  static void leaveChannel() {
    _channel?.unsubscribe();
    _channel = null;
  }

  static Future<void> updateRoom(String roomId, {
    Track? track,
    int? positionMs,
    bool? isPlaying,
  }) async {
    final Map<String, dynamic> updates = {};
    if (track != null) {
      updates['current_track_id'] = track.id;
      updates['current_track_data'] = track.toJson();
    }
    if (positionMs != null) updates['position_ms'] = positionMs;
    if (isPlaying != null) updates['is_playing'] = isPlaying;
    
    updates['last_sync_at'] = DateTime.now().toIso8601String();
    
    await _client.from('rooms').update(updates).eq('id', roomId);
    
    // Also broadcast via Realtime for instant updates
    broadcastUpdate(roomId, updates);
  }

  static Stream<Map<String, dynamic>> listenToRoom(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((data) => data.isNotEmpty ? data.first : <String, dynamic>{});
  }

  static Future<void> deleteRoom(String roomId) async {
    leaveChannel();
    await _client.from('rooms').delete().eq('id', roomId);
  }
}
