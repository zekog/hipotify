import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'supabase_config.dart';
import '../models/playlist.dart';
import '../models/track.dart';

class SupabasePlaylistService {
  static SupabaseClient get _client {
    if (!SupabaseConfig.isConfigured) {
      throw Exception("Supabase not initialized.");
    }
    return Supabase.instance.client;
  }

  /// Publishes a local playlist to the Supabase network.
  static Future<void> publishPlaylist(Playlist playlist, {String? description}) async {
    if (!AuthService.isLoggedIn) throw Exception("Login required to publish playlists");

    // Ensure profile exists before publishing (prevents foreign key violation)
    await AuthService.ensureProfileExists();

    final userId = AuthService.currentUser!.id;

    // 1. Create/Update playlist metadata
    try {
      final response = await _client.from('playlists').upsert({
        'id': playlist.id,
        'user_id': userId,
        'title': playlist.name,
        'description': description,
        'is_public': playlist.isPublic,
      }).select().single();

      final playlistId = response['id'];

    // 2. Clear old items and add new ones (simple replacement for consistency)
    await _client.from('playlist_items').delete().eq('playlist_id', playlistId);

    final items = playlist.tracks.asMap().entries.map((entry) {
      final index = entry.key;
      final track = entry.value;
      return {
        'playlist_id': playlistId,
        'track_id': track.id,
        'track_data': track.toJson(),
        'position': index,
      };
    }).toList();

      if (items.isNotEmpty) {
        await _client.from('playlist_items').insert(items);
      }
    } catch (e) {
      print("SupabasePlaylistService: Error publishing playlist: $e");
      rethrow;
    }
  }

  /// Fetches public playlists from the network.
  static Future<List<Map<String, dynamic>>> getPublicPlaylists() async {
    final response = await _client
        .from('playlists')
        .select('*, profiles(username)')
        .eq('is_public', true)
        .order('created_at', ascending: false);
    
    return List<Map<String, dynamic>>.from(response);
  }

  /// Fetches a full playlist with all tracks from Supabase.
  static Future<Playlist> fetchFullPlaylist(String playlistId) async {
    final playlistData = await _client
        .from('playlists')
        .select('*, playlist_items(*)')
        .eq('id', playlistId)
        .single();

    final tracksData = List<Map<String, dynamic>>.from(playlistData['playlist_items']);
    // Sort by position
    tracksData.sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

    final tracks = tracksData.map((item) {
      return Track.fromJson(Map<String, dynamic>.from(item['track_data']));
    }).toList();

    return Playlist(
      id: playlistData['id'].toString(),
      name: playlistData['title'],
      tracks: tracks,
      ownerId: playlistData['user_id'],
      isPublic: playlistData['is_public'],
    );
  }

  /// Fetches all playlists owned by the current user.
  static Future<List<Playlist>> getUserPlaylists() async {
    if (!AuthService.isLoggedIn) return [];
    
    final userId = AuthService.currentUser!.id;
    final response = await _client
        .from('playlists')
        .select('*, playlist_items(*)')
        .eq('user_id', userId);
    
    final List<Playlist> playlists = [];
    for (var p in response) {
      final tracksData = List<Map<String, dynamic>>.from(p['playlist_items'] ?? []);
      tracksData.sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
      
      final tracks = tracksData.map((item) {
        return Track.fromJson(Map<String, dynamic>.from(item['track_data']));
      }).toList();

      playlists.add(Playlist(
        id: p['id'].toString(),
        name: p['title'],
        tracks: tracks,
        ownerId: p['user_id'],
        isPublic: p['is_public'],
      ));
    }
    return playlists;
  }

  /// Deletes a playlist from Supabase.
  static Future<void> deletePlaylist(String playlistId) async {
    if (!AuthService.isLoggedIn) throw Exception("Login required");
    
    // Safety check: ensure user owns the playlist
    final userId = AuthService.currentUser!.id;
    
    // First, delete items (due to foreign keys, though CASCADE should handle it if set up)
    await _client.from('playlist_items').delete().eq('playlist_id', playlistId);
    
    // Then delete playlist
    await _client.from('playlists').delete().eq('id', playlistId).eq('user_id', userId);
  }
}
