import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'hive_service.dart';
import 'supabase_config.dart';
import '../models/track.dart';

class CloudSyncService {
  static SupabaseClient get _client {
    if (!SupabaseConfig.isConfigured) {
      throw Exception("Supabase not initialized.");
    }
    return Supabase.instance.client;
  }

  /// Syncs local likes to Supabase and vice versa
  static Future<void> syncLikes() async {
    if (!AuthService.isLoggedIn) return;
    
    final userId = AuthService.currentUser!.id;
    
    try {
      // 1. Fetch remote likes
      final remoteLikes = await _client
          .from('liked_tracks')
          .select()
          .eq('user_id', userId);
          
      final remoteIds = (remoteLikes as List).map((e) => e['track_id'].toString()).toSet();
      
      // 2. Fetch local likes
      final localLikes = HiveService.getLikedSongs();
      final localIds = localLikes.map((e) => e.id.toString()).toSet();
      
      // 3. Push local-only likes to remote
      for (var track in localLikes) {
        if (!remoteIds.contains(track.id)) {
          await _client.from('liked_tracks').upsert({
            'user_id': userId,
            'track_id': track.id,
            'track_data': track.toJson(),
          });
        }
      }
      
      // 4. Pull remote-only likes to local
      for (var remote in remoteLikes) {
        final trackId = remote['track_id'].toString();
        if (!localIds.contains(trackId)) {
          final track = Track.fromJson(Map<String, dynamic>.from(remote['track_data']));
          // We need a silent way to toggle like in Hive without triggering another sync
          // For now, toggleLike is fine if we check if it already exists
          if (!HiveService.isLiked(trackId)) {
            await HiveService.toggleLike(track);
          }
        }
      }
      
      print("CloudSyncService: Likes sync complete.");
    } catch (e) {
      print("CloudSyncService: Error syncing likes: $e");
    }
  }

  /// Initial sync when user logs in
  static Future<void> initialSync() async {
    await syncLikes();
    // TODO: Sync playlists
  }
}
