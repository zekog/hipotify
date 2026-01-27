import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import '../providers/player_provider.dart';
import '../widgets/lyrics_viewer.dart';
import '../widgets/glass_container.dart';

class FullScreenPlayer extends StatefulWidget {
  const FullScreenPlayer({super.key});

  @override
  State<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<FullScreenPlayer> {
  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, child) {
        final track = player.currentTrack;
        if (track == null) return const Scaffold(body: Center(child: Text("No track playing")));

        return Scaffold(
          backgroundColor: Colors.black,
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
                  filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),

              // Content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Row(
                    children: [
                      // Left Side: Artwork & Info
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: Container(
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
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              track.title,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              track.artistName,
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 48),

                      // Right Side: Lyrics
                      Expanded(
                        flex: 6,
                        child: GlassContainer(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.black,
                          opacity: 0.3,
                          child: player.currentLyrics != null
                              ? LyricsViewer(
                                  lyrics: player.currentLyrics!,
                                  positionStream: player.isCasting
                                      ? GoogleCastRemoteMediaClient.instance.playerPositionStream
                                      : player.player.positionStream,
                                  onSeek: (pos) => player.seek(pos),
                                  textAlign: TextAlign.left,
                                  textStyle: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    height: 1.5,
                                    color: Colors.white,
                                  ),
                                  activeTextStyle: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    height: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.lyrics_outlined, size: 64, color: Colors.white24),
                                      SizedBox(height: 16),
                                      Text(
                                        "No lyrics available",
                                        style: TextStyle(color: Colors.white54, fontSize: 18),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Close Button
              Positioned(
                top: 24,
                right: 24,
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
