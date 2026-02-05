import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/hive_service.dart';
import '../models/tidal_playlist.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../widgets/track_tile.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../utils/snackbar_helper.dart';
import '../services/supabase_playlist_service.dart';
import '../models/playlist.dart';
import '../services/auth_service.dart';
import 'account_screen.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  TidalPlaylist? _playlist;
  Playlist? _localPlaylist;
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isEditMode = false;
  bool _isOwned = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      // 1. Check if it's a local playlist in Hive
      final localPlaylist = HiveService.getPlaylist(widget.playlistId);
      if (localPlaylist != null) {
        final isOwned = localPlaylist.ownerId == null || 
            (AuthService.isLoggedIn && localPlaylist.ownerId == AuthService.currentUser?.id);
        setState(() {
          _localPlaylist = localPlaylist;
          _playlist = TidalPlaylist(
            id: localPlaylist.id,
            title: localPlaylist.name,
            imageUrl: '',
            numberOfTracks: localPlaylist.tracks.length,
            creatorName: 'You',
            description: 'Local Playlist',
          );
          _tracks = localPlaylist.tracks;
          _isOwned = isOwned;
          _isLoading = false;
        });
        return;
      }

      // 2. Try fetching from Supabase (Playlist Net)
      try {
        final supabasePlaylist = await SupabasePlaylistService.fetchFullPlaylist(widget.playlistId);
        final isOwned = AuthService.isLoggedIn && supabasePlaylist.ownerId == AuthService.currentUser?.id;
        setState(() {
          _localPlaylist = supabasePlaylist;
          _playlist = TidalPlaylist(
            id: supabasePlaylist.id,
            title: supabasePlaylist.name,
            imageUrl: '',
            numberOfTracks: supabasePlaylist.tracks.length,
            creatorName: isOwned ? 'You' : 'Playlist Net',
            description: supabasePlaylist.isPublic ? 'Public Playlist' : 'Private Playlist',
          );
          _tracks = supabasePlaylist.tracks;
          _isOwned = isOwned;
          _isLoading = false;
        });
        return;
      } catch (_) {
        // Fall through to Tidal API
      }

      // 3. Otherwise fetch from Tidal API
      final playlist = await ApiService.getPlaylistDetails(widget.playlistId);
      final tracks = await ApiService.getPlaylistTracks(widget.playlistId);
      setState(() {
        _playlist = playlist;
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching playlist data: $e");
      if (mounted) {
        showSnackBar(context, "Error: $e");
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: _playlist?.title ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('RENAME'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && _localPlaylist != null && mounted) {
      final updated = Playlist(
        id: _localPlaylist!.id,
        name: newName,
        tracks: _localPlaylist!.tracks,
        ownerId: _localPlaylist!.ownerId,
        isPublic: _localPlaylist!.isPublic,
        customCoverPath: _localPlaylist!.customCoverPath,
      );
      await Provider.of<LibraryProvider>(context, listen: false).updatePlaylist(updated);
      _fetchData();
      if (mounted) showSnackBar(context, 'Playlist renamed!');
    }
  }

  Future<void> _showDeleteDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist?'),
        content: const Text('This action cannot be undone. The playlist will also be removed from the cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await Provider.of<LibraryProvider>(context, listen: false).deletePlaylist(widget.playlistId);
      if (mounted) {
        showSnackBar(context, 'Playlist deleted.');
        Navigator.pop(context);
      }
    }
  }

  Future<void> _publishPlaylist() async {
    if (!AuthService.isLoggedIn) {
      final login = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Login Required'),
          content: const Text('You need to be logged in to publish playlists.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('LOGIN')),
          ],
        ),
      );
      if (login == true && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen()));
      }
      return;
    }

    final descriptionController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish to Playlist Net?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This will make your playlist public for everyone on Hipotify.'),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('PUBLISH')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      showSnackBar(context, 'Publishing...');
      try {
        final playlist = Playlist(
          id: _playlist!.id,
          name: _playlist!.title,
          tracks: _tracks,
          ownerId: _localPlaylist?.ownerId ?? AuthService.currentUser?.id,
          isPublic: true,
        );
        await SupabasePlaylistService.publishPlaylist(
          playlist,
          description: descriptionController.text.trim(),
        );
        // Update local state
        await Provider.of<LibraryProvider>(context, listen: false).updatePlaylist(playlist);
        _fetchData();
        if (mounted) showSnackBar(context, 'Published to Playlist Net!');
      } catch (e) {
        if (mounted) showSnackBar(context, 'Failed to publish: $e');
      }
    }
  }

  Future<void> _unpublishPlaylist() async {
    if (!AuthService.isLoggedIn || !_isOwned || _localPlaylist == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpublish Playlist?'),
        content: const Text('This will make your playlist private. Others will no longer see it on Playlist Net.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('UNPUBLISH')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      showSnackBar(context, 'Unpublishing...');
      try {
        final playlist = Playlist(
          id: _localPlaylist!.id,
          name: _localPlaylist!.name,
          tracks: _localPlaylist!.tracks,
          ownerId: _localPlaylist!.ownerId,
          isPublic: false,
          customCoverPath: _localPlaylist!.customCoverPath,
        );
        await SupabasePlaylistService.publishPlaylist(playlist);
        await Provider.of<LibraryProvider>(context, listen: false).updatePlaylist(playlist);
        _fetchData();
        if (mounted) showSnackBar(context, 'Playlist is now private.');
      } catch (e) {
        if (mounted) showSnackBar(context, 'Failed to unpublish: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text("Playlist not found (ID: ${widget.playlistId})", style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchData, child: const Text("RETRY")),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            actions: _isOwned ? [
              if (_isEditMode) ...[
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Rename Playlist',
                  onPressed: _showRenameDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever),
                  tooltip: 'Delete Playlist',
                  onPressed: _showDeleteDialog,
                ),
              ],
              IconButton(
                icon: Icon(_isEditMode ? Icons.done : Icons.edit_note),
                tooltip: _isEditMode ? 'Done' : 'Edit Mode',
                onPressed: () => setState(() => _isEditMode = !_isEditMode),
              ),
            ] : null,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_playlist!.title, style: const TextStyle(shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _playlist!.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_playlist!.description != null && _playlist!.description!.isNotEmpty) ...[
                    Text(
                      _playlist!.description!,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    "${_playlist!.numberOfTracks} tracks • By ${_playlist!.creatorName ?? 'Tidal'}",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          if (_tracks.isNotEmpty) {
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(_tracks, initialIndex: 0);
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("PLAY"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: () {
                          if (_tracks.isNotEmpty) {
                            final shuffled = List<Track>.from(_tracks)..shuffle();
                            Provider.of<PlayerProvider>(context, listen: false)
                                .playPlaylist(shuffled, initialIndex: 0);
                          }
                        },
                        icon: const Icon(Icons.shuffle),
                      ),
                      const SizedBox(width: 16),
                      Consumer<LibraryProvider>(
                        builder: (context, library, _) {
                          final isSaved = library.isPlaylistSaved(_playlist!.id);
                          return IconButton(
                            onPressed: () async {
                              await library.toggleSavePlaylist(_playlist!);
                              if (context.mounted) {
                                showSnackBar(
                                  context,
                                  library.isPlaylistSaved(_playlist!.id)
                                      ? 'Saved to library!'
                                      : 'Removed from library',
                                );
                              }
                            },
                            icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                            color: isSaved ? Theme.of(context).primaryColor : Colors.white,
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      // Publish/Unpublish toggle
                      if (_isOwned && _localPlaylist != null)
                        _localPlaylist!.isPublic
                            ? IconButton(
                                tooltip: 'Unpublish from Playlist Net',
                                icon: const Icon(Icons.public_off),
                                color: Colors.orange,
                                onPressed: _unpublishPlaylist,
                              )
                            : IconButton(
                                tooltip: 'Publish to Playlist Net',
                                icon: const Icon(Icons.public),
                                onPressed: _publishPlaylist,
                              )
                      else
                        IconButton(
                          tooltip: 'Publish to Playlist Net',
                          icon: const Icon(Icons.public),
                          onPressed: _publishPlaylist,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = _tracks[index];
                final tile = TrackTile(
                  track: track,
                  showMenu: true,
                  onTap: () {
                    Provider.of<PlayerProvider>(context, listen: false)
                        .playPlaylist(_tracks, initialIndex: index);
                  },
                );
                
                if (_isEditMode && _isOwned) {
                  return Dismissible(
                    key: Key('track_${track.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) async {
                      await Provider.of<LibraryProvider>(context, listen: false)
                          .removeTrackFromPlaylist(widget.playlistId, track.id);
                      _fetchData();
                    },
                    child: tile,
                  );
                }
                return tile;
              },
              childCount: _tracks.length,
            ),
          ),
          // Add bottom padding
          SliverToBoxAdapter(
            child: SizedBox(height: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom + 100),
          ),
        ],
      ),
    );
  }
}