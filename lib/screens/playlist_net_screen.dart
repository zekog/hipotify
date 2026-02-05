import 'package:flutter/material.dart';
import '../services/supabase_playlist_service.dart';
import '../services/hive_service.dart';
import '../models/playlist.dart';
import '../utils/snackbar_helper.dart';
import 'playlist_screen.dart';

class PlaylistNetScreen extends StatefulWidget {
  const PlaylistNetScreen({super.key});

  @override
  State<PlaylistNetScreen> createState() => _PlaylistNetScreenState();
}

class _PlaylistNetScreenState extends State<PlaylistNetScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _playlists = [];

  @override
  void initState() {
    super.initState();
    _fetchPlaylists();
  }

  Future<void> _fetchPlaylists() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupabasePlaylistService.getPublicPlaylists();
      setState(() => _playlists = data);
    } catch (e) {
      if (mounted) showSnackBar(context, 'Error loading network: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist Net'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPlaylists,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchPlaylists,
              child: _playlists.isEmpty
                  ? const Center(child: Text('No public playlists found'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _playlists.length,
                      itemBuilder: (context, index) {
                        final item = _playlists[index];
                        final username = item['profiles']?['username'] ?? 'Unknown';
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(item['title'] ?? 'Untitled'),
                            subtitle: Text('by $username • ${item['description'] ?? ''}'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'import') {
                                  _importPlaylist(item['id'].toString());
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'import',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download),
                                      SizedBox(width: 8),
                                      Text('Import to Library'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _openPlaylist(item['id'].toString()),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Future<void> _importPlaylist(String id) async {
    showSnackBar(context, 'Importing playlist...');
    try {
      final fullPlaylist = await SupabasePlaylistService.fetchFullPlaylist(id);
      // Generate a new ID for the local copy to avoid conflicts if edited
      final localPlaylist = Playlist(
        id: 'imported_${DateTime.now().millisecondsSinceEpoch}',
        name: '${fullPlaylist.name} (Imported)',
        tracks: fullPlaylist.tracks,
      );
      
      await HiveService.playlistsBox.put(localPlaylist.id, localPlaylist.toJson());
      if (mounted) showSnackBar(context, 'Added to your Library!');
    } catch (e) {
      if (mounted) showSnackBar(context, 'Import failed: $e');
    }
  }

  void _openPlaylist(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(playlistId: id),
      ),
    );
  }
}
