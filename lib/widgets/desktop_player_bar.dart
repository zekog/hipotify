import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../screens/full_screen_player.dart';
import 'glass_container.dart';

class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.white.withOpacity(0.7) : Colors.black54;
    final iconColor = isDark ? Colors.white : Colors.black;
    final glassColor = isDark ? Colors.black : Colors.white;

    return Consumer<PlayerProvider>(
      builder: (context, player, child) {
        final track = player.currentTrack;
        if (track == null) return const SizedBox.shrink();

        if (player.errorMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(player.errorMessage!)),
            );
          });
        }

        return GlassContainer(
          height: 120,
          blur: 20,
          opacity: 0.1,
          color: glassColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Row(
              children: [
                // Track Info
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.coverUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey[900]),
                    errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artistName,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Controls
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle),
                          color: secondaryTextColor,
                          onPressed: () {}, // TODO: Implement shuffle
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous),
                          color: iconColor,
                          iconSize: 28,
                          onPressed: () => player.previous(),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: iconColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: Icon(player.player.playing ? Icons.pause : Icons.play_arrow),
                            color: isDark ? Colors.black : Colors.white, // Invert for button content
                            iconSize: 32,
                            onPressed: () => player.togglePlayPause(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          color: iconColor,
                          iconSize: 28,
                          onPressed: () => player.next(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.repeat),
                          color: secondaryTextColor,
                          onPressed: () {}, // TODO: Implement repeat
                        ),
                      ],
                    ),
                    // Progress Bar
                    SizedBox(
                      width: 400,
                      child: StreamBuilder<Duration>(
                        stream: player.player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration = player.player.duration != null && player.player.duration!.inMilliseconds > 0 
                              ? player.player.duration! 
                              : Duration(seconds: track.duration);
                              
                          return SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: iconColor,
                              inactiveTrackColor: iconColor.withOpacity(0.3),
                              thumbColor: iconColor,
                              trackHeight: 2,
                            ),
                            child: Slider(
                              value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()),
                              min: 0,
                              max: duration.inMilliseconds.toDouble(),
                              onChanged: (value) {
                                player.seek(Duration(milliseconds: value.toInt()));
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Volume / Extra
                Row(
                  children: [
                    Icon(Icons.volume_up, color: iconColor),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: iconColor,
                          inactiveTrackColor: iconColor.withOpacity(0.3),
                          thumbColor: iconColor,
                        ),
                        child: StreamBuilder<double>(
                          stream: player.player.volumeStream,
                          builder: (context, snapshot) {
                            final volume = snapshot.data ?? 1.0;
                            return Slider(
                              value: volume,
                              onChanged: (value) {
                                player.player.setVolume(value);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.open_in_full),
                      color: iconColor,
                      tooltip: "Full Screen",
                      onPressed: () {
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => const FullScreenPlayer(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return FadeTransition(opacity: animation, child: child);
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
