import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
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
                icon: Icon(_showStats ? Icons.analytics : Icons.analytics_outlined),
                onPressed: () => setState(() => _showStats = !_showStats),
                tooltip: "Stats for Nerds",
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {},
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
                            ? LyricsViewer(lyrics: player.currentLyrics!, player: player.player)
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
                          IconButton(
                            icon: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked ? Theme.of(context).primaryColor : Colors.white,
                              size: 28,
                            ),
                            onPressed: () => library.toggleLike(track),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Seek Bar
                      StreamBuilder<Duration>(
                        stream: player.player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration = player.player.duration ?? Duration.zero;
                          
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
                                  value: position.inSeconds.toDouble().clamp(0, duration.inSeconds.toDouble()),
                                  max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
                                  onChanged: (value) {
                                    player.player.seek(Duration(seconds: value.toInt()));
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
                            icon: Icon(
                              Icons.lyrics_outlined,
                              color: (_showLyrics && player.currentLyrics != null) ? Theme.of(context).primaryColor : Colors.white.withOpacity(0.6),
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
                            icon: const Icon(Icons.skip_previous, size: 42, color: Colors.white),
                            onPressed: () => player.previous(),
                          ),
                          _buildPlayPauseButton(player),
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 42, color: Colors.white),
                            onPressed: () => player.next(),
                          ),
                          IconButton(
                            icon: Icon(
                              isDownloaded ? Icons.download_done : Icons.download,
                              color: isDownloaded ? Theme.of(context).primaryColor : Colors.white.withOpacity(0.6),
                            ),
                              onPressed: isDownloaded ? null : () async {
                                try {
                                  await DownloadService.downloadTrack(
                                    track, 
                                    onProgress: (received, total) {}
                                  );
                                  if (context.mounted) {
                                    library.refreshDownloads();
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Started")));
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                                  }
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
        final playing = snapshot.data ?? false;
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
}
