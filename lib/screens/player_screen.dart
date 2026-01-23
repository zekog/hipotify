import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_service.dart';
import '../models/track.dart';
import '../widgets/lyrics_viewer.dart';
import 'artist_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showStats = false;
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    print("PlayerScreen: initState");
  }

  @override
  void dispose() {
    print("PlayerScreen: dispose");
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<String?> _promptForPlaylistName(BuildContext dialogContext) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: dialogContext,
      builder: (context) {
        return AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Playlist name',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    final name = result?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _showAddToPlaylistMenu(
    BuildContext context,
    Track track,
    LibraryProvider library,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Center(
          child: Material(
            type: MaterialType.card,
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF1E1E1E),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
              child: Consumer<LibraryProvider>(
                builder: (context, lib, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Add to playlist',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.add, color: Colors.white),
                              title: const Text('New playlist', style: TextStyle(color: Colors.white)),
                              onTap: () async {
                                Navigator.of(context).pop();
                                final name = await _promptForPlaylistName(context);
                                if (name == null) return;

                                try {
                                  final playlist = await library.createPlaylist(name);
                                  await library.addTrackToPlaylist(playlist.id, track);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Added to "${playlist.name}"')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                            if (lib.playlists.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No playlists yet',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            else
                              ...lib.playlists.map(
                                (p) {
                                  final isInPlaylist = library.isTrackInPlaylist(p.id, track.id);
                                  return ListTile(
                                    leading: Icon(
                                      isInPlaylist ? Icons.check_circle : Icons.queue_music,
                                      color: isInPlaylist ? Theme.of(context).primaryColor : Colors.white,
                                    ),
                                    title: Text(p.name, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(
                                      '${p.tracks.length} tracks',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    onTap: () async {
                                      Navigator.of(context).pop();
                                      try {
                                        final wasAdded = await library.toggleTrackInPlaylist(p.id, track);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                wasAdded
                                                    ? 'Added to "${p.name}"'
                                                    : 'Removed from "${p.name}"',
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Failed: $e')),
                                          );
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PlayerProvider, LibraryProvider>(
      builder: (context, player, library, child) {
        final track = player.currentTrack;
        if (track == null) return const Scaffold(body: Center(child: Text("No track playing")));

        final isLiked = library.isLiked(track.id);
        final isDownloaded = library.downloadedSongs.any((t) => t.id == track.id);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.cast, color: player.isCasting ? Colors.green : Colors.white),
                onPressed: () => _showCastDialog(context, player),
                tooltip: "Cast to Device",
              ),
              IconButton(
                icon: Icon(_showStats ? Icons.analytics : Icons.analytics_outlined),
                onPressed: () => setState(() => _showStats = !_showStats),
                tooltip: "Stats for Nerds",
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onOpened: () {
                  // Hide mini player when menu opens
                  player.setMiniPlayerHidden(true);
                },
                onCanceled: () {
                  // Show mini player again when menu is canceled
                  player.setMiniPlayerHidden(false);
                },
                onSelected: (value) async {
                  // Show mini player again after selection
                  player.setMiniPlayerHidden(false);
                  
                  if (value == 'add_to_playlist') {
                    // Close player first
                    Navigator.of(context).pop();
                    // Show playlist selection menu
                    await _showAddToPlaylistMenu(context, track, library);
                    // Return to player after selection
                    if (context.mounted && player.currentTrack != null) {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          settings: const RouteSettings(name: 'PlayerScreen'),
                          pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            const begin = Offset(0.0, 1.0);
                            const end = Offset.zero;
                            const curve = Curves.easeOutCubic;
                            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                            return SlideTransition(position: animation.drive(tween), child: child);
                          },
                        ),
                      );
                    }
                  } else if (value == 'download') {
                    if (!isDownloaded) {
                      try {
                        await DownloadService.downloadTrack(
                          track, 
                          onProgress: (received, total) {}
                        );
                        if (context.mounted) {
                          library.refreshDownloads();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Download Started"))
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Error: $e"))
                          );
                        }
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'add_to_playlist',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_add),
                        SizedBox(width: 8),
                        Text('Add to playlist'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'download',
                    enabled: !isDownloaded,
                    child: Row(
                      children: [
                        Icon(isDownloaded ? Icons.download_done : Icons.download),
                        const SizedBox(width: 8),
                        Text(isDownloaded ? 'Downloaded' : 'Download'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Stack(
            children: [
              // Background Image (Blurred)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: track.coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(color: Colors.black),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
              ),

              // Main Content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  child: Column(
                    children: [
                      // Artwork or Lyrics
                      Expanded(
                        child: Center(
                          child: (_showLyrics && player.currentLyrics != null)
                            ? LyricsViewer(
                                lyrics: player.currentLyrics!, 
                                positionStream: player.isCasting 
                                  ? GoogleCastRemoteMediaClient.instance.playerPositionStream 
                                  : player.player.positionStream,
                                onSeek: (pos) => player.seek(pos),
                              )
                            : _buildArtworkView(track),
                        ),
                      ),
                      
                      const SizedBox(height: 24),

                      // Title & Artist
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    if (track.artistId.isNotEmpty) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ArtistScreen(artistId: track.artistId),
                                        ),
                                      );
                                    }
                                  },
                                  child: Text(
                                    track.artistName,
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white.withOpacity(0.7),
                                      decoration: TextDecoration.underline,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: _showLyrics ? 'Hide lyrics' : 'Show lyrics',
                                icon: Icon(
                                  Icons.lyrics_outlined,
                                  color: (_showLyrics && player.currentLyrics != null) 
                                      ? Theme.of(context).primaryColor 
                                      : Colors.white.withOpacity(0.7),
                                  size: 28,
                                ),
                                onPressed: () {
                                  if (player.currentLyrics == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Lyrics not available for this track"),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => _showLyrics = !_showLyrics);
                                },
                              ),
                              IconButton(
                                tooltip: isLiked ? 'Remove from liked' : 'Add to liked',
                                icon: Icon(
                                  isLiked ? Icons.favorite : Icons.favorite_border,
                                  color: isLiked ? Theme.of(context).primaryColor : Colors.white,
                                  size: 28,
                                ),
                                onPressed: () async {
                                  await library.toggleLike(track);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          library.isLiked(track.id)
                                              ? 'Added to favorites!'
                                              : 'Removed from favorites',
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Seek Bar
                      StreamBuilder<Duration>(
                        stream: player.isCasting 
                          ? GoogleCastRemoteMediaClient.instance.playerPositionStream 
                          : player.player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration = player.isCasting
                            ? (GoogleCastRemoteMediaClient.instance.mediaStatus?.mediaInformation?.duration ?? Duration.zero)
                            : (player.player.duration ?? Duration.zero);
                          
                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  trackHeight: 4,
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white.withOpacity(0.2),
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white.withOpacity(0.1),
                                ),
                                child: Slider(
                                  value: position.inSeconds.toDouble().clamp(0.0, duration.inSeconds.toDouble()).toDouble(),
                                  max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
                                  onChanged: (value) {
                                    player.seek(Duration(seconds: value.toInt()));
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(position), style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                                    Text(_formatDuration(duration), style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            tooltip: 'Play random track',
                            icon: const Icon(Icons.shuffle, size: 28, color: Colors.white),
                            onPressed: () async {
                              await player.playRandomTrack();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Playing random track'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous, size: 42, color: Colors.white),
                            onPressed: () => player.previous(),
                          ),
                          _buildPlayPauseButton(player),
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 42, color: Colors.white),
                            onPressed: () => player.next(),
                          ),
                          IconButton(
                            tooltip: player.loopMode == 0 
                                ? 'Loop off' 
                                : player.loopMode == 1 
                                    ? 'Loop track' 
                                    : 'Loop playlist',
                            icon: Icon(
                              player.loopMode == 1 
                                  ? Icons.repeat_one 
                                  : Icons.repeat,
                              size: 28,
                              color: player.loopMode == 0 
                                  ? Colors.white.withOpacity(0.6)
                                  : Theme.of(context).primaryColor,
                            ),
                            onPressed: () async {
                              await player.toggleLoopMode();
                              if (context.mounted) {
                                String message;
                                if (player.loopMode == 1) {
                                  message = 'Looping track';
                                } else if (player.loopMode == 2) {
                                  message = 'Looping playlist';
                                } else {
                                  message = 'Loop off';
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(message),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // Stats for Nerds Overlay
              if (_showStats) _buildStatsOverlay(player),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtworkView(Track track) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: track.coverUrl,
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.width * 0.8,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey[900], child: const Center(child: CircularProgressIndicator())),
          errorWidget: (context, url, error) => Container(color: Colors.grey[800], child: const Icon(Icons.music_note, size: 80)),
        ),
      ),
    );
  }

  // _buildLyricsView is now replaced by LyricsViewer widget

  Widget _buildPlayPauseButton(PlayerProvider player) {
    return StreamBuilder<bool>(
      stream: player.player.playingStream,
      builder: (context, snapshot) {
        bool playing = snapshot.data ?? false;
        if (player.isCasting) {
          final castState = GoogleCastRemoteMediaClient.instance.mediaStatus?.playerState;
          playing = castState == CastMediaPlayerState.playing;
        }
        return Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: IconButton(
            icon: Icon(
              playing ? Icons.pause : Icons.play_arrow,
              color: Colors.black,
              size: 40,
            ),
            onPressed: () => player.togglePlayPause(),
          ),
        );
      },
    );
  }

  Widget _buildStatsOverlay(PlayerProvider player) {
    final meta = player.currentMetadata;
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black.withOpacity(0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("STATS FOR NERDS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                const Divider(color: Colors.white24),
                _statRow("Quality", meta?['audioQuality'] ?? "Unknown"),
                _statRow("Mode", meta?['audioMode'] ?? "Unknown"),
                _statRow("Bit Depth", "${meta?['bitDepth'] ?? '--'} bit"),
                _statRow("Sample Rate", "${meta?['sampleRate'] ?? '--'} Hz"),
                StreamBuilder<Duration>(
                  stream: player.player.bufferedPositionStream,
                  builder: (context, snap) => _statRow("Buffer", _formatDuration(snap.data)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  void _showCastDialog(BuildContext context, PlayerProvider player) {
    player.startCastDiscovery();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Google Cast", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 300,
          height: 400,
          child: Consumer<PlayerProvider>(
            builder: (context, player, child) {
              return Column(
                children: [
                  if (player.isCasting && player.connectedDevice != null)
                    ListTile(
                      title: Text(player.connectedDevice!.friendlyName, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      subtitle: const Text("Connected", style: TextStyle(color: Colors.green)),
                      leading: const Icon(Icons.cast_connected, color: Colors.green),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          player.stopCasting();
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: player.castDevices.isEmpty
                      ? const Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text("Searching for devices...", style: TextStyle(color: Colors.white70)),
                          ],
                        ))
                      : ListView.builder(
                          itemCount: player.castDevices.length,
                          itemBuilder: (context, index) {
                            final device = player.castDevices[index];
                            final isConnected = player.connectedDevice?.deviceID == device.deviceID;
                            return ListTile(
                              title: Text(device.friendlyName, style: TextStyle(color: isConnected ? Colors.green : Colors.white)),
                              leading: Icon(Icons.tv, color: isConnected ? Colors.green : Colors.white),
                              onTap: isConnected ? null : () {
                                player.connectAndCast(device);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
}
