import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/player_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/hive_service.dart';
import '../../models/track.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/rotary_scroll_wrapper.dart';
import 'wear_os_player_screen.dart';
import 'wear_os_search_screen.dart';
import 'wear_os_library_screen.dart';
import 'wear_os_settings_screen.dart';

/// Wear OS optimized home screen with vertical scrolling
class WearOsHomeScreen extends StatefulWidget {
  const WearOsHomeScreen({super.key});

  @override
  State<WearOsHomeScreen> createState() => _WearOsHomeScreenState();
}

class _WearOsHomeScreenState extends State<WearOsHomeScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sprawdzenie zmiennych stanu i historii użyciem providera
    final recentTracks = HiveService.getRecentlyPlayed();
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      backgroundColor: Colors.black, // Dla ekranów OLED w zegarkach AMOLED
      body: RotaryScrollWrapper(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(
            vertical: 40, // Odejście dla okrągłych krawędzi (flat tire i bezel)
            horizontal: WearOsConstants.defaultPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zegarek / Powitanie
              Center(child: _buildHeader()),
              
              const SizedBox(height: WearOsConstants.largePadding),

              // Ostrzeżenie o braku API, zastępuje AlertDialog ze startu
              if (HiveService.apiUrl == null || HiveService.apiUrl!.isEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red),
                  ),
                  child: const Text(
                    'No API Configure. Go to Settings!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: WearOsConstants.captionSize,
                    ),
                  ),
                ),

              // Karta Now Playing (jeśli leci muzyka)
              if (player.effectiveTrack != null) ...[
                _buildNowPlayingCard(context, player),
                const SizedBox(height: WearOsConstants.defaultPadding),
              ],


              // Główne kafelki nawigacji (Zamiast dolnego paska nawigacyjnego)
              _WearOsMenuButton(
                icon: Icons.search,
                label: 'Search',
                color: Colors.green,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WearOsSearchScreen()),
                ),
              ),
              const SizedBox(height: WearOsConstants.smallPadding),
              
              _WearOsMenuButton(
                icon: Icons.library_music,
                label: 'Library',
                color: Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WearOsLibraryScreen()),
                ),
              ),
              const SizedBox(height: WearOsConstants.smallPadding),

              _WearOsMenuButton(
                icon: Icons.settings,
                label: 'Settings',
                color: Colors.grey,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WearOsSettingsScreen()),
                ),
              ),
              
              const SizedBox(height: WearOsConstants.largePadding),

              // Sekcja Ostatnio odtwarzane
              if (recentTracks.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    'Recent',
                    style: TextStyle(
                      fontSize: WearOsConstants.titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildRecentTracksList(context, recentTracks),
                const SizedBox(height: WearOsConstants.largePadding),
              ],

              // Sekcja Polubione utwory
              if (library.likedSongs.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    'Liked',
                    style: TextStyle(
                      fontSize: WearOsConstants.titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildLikedSongsList(context, library.likedSongs),
                const SizedBox(height: WearOsConstants.largePadding),
              ],
              
              // Lekki odstęp u dołu na wypadek przysłonięcia przez obudowę okrągłą zegarka
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(minutes: 1)),
      builder: (context, _) {
        final now = DateTime.now();
        return Text(
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontSize: WearOsConstants.largeHeadlineSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        );
      },
    );
  }

  Widget _buildNowPlayingCard(BuildContext context, PlayerProvider player) {
    final track = player.effectiveTrack!;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const WearOsPlayerScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: player.isRemoteMode ? Colors.green : Theme.of(context).primaryColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Przycisk Play/Pause mały
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: player.isRemoteMode ? Colors.green : Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                player.effectiveIsPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.black,
                size: 20,
              ),
            ),
            if (player.isRemoteMode) ...[
              const SizedBox(width: 4),
              const Icon(Icons.cast_connected, size: 10, color: Colors.green),
            ],
            const SizedBox(width: 12),
            // Informacja o utworze
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: WearOsConstants.titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: WearOsConstants.captionSize,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildRecentTracksList(BuildContext context, List<Track> tracks) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tracks.take(10).length, // Ograniczenie ilości na zegarku
        itemBuilder: (context, index) {
          final track = tracks[index];
          return Padding(
            padding: const EdgeInsets.only(right: WearOsConstants.smallPadding),
            child: GestureDetector(
              onTap: () {
                context.read<PlayerProvider>().playTrack(track);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[800],
                        width: 56,
                        height: 56,
                        child: const Icon(Icons.music_note, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 56,
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: WearOsConstants.captionSize,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLikedSongsList(BuildContext context, List<Track> tracks) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tracks.take(10).length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return Padding(
            padding: const EdgeInsets.only(right: WearOsConstants.smallPadding),
            child: GestureDetector(
              onTap: () {
                context.read<PlayerProvider>().playTrack(track);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WearOsPlayerScreen()),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[800],
                        width: 56,
                        height: 56,
                        child: const Icon(Icons.music_note, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 56,
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: WearOsConstants.captionSize,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WearOsMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _WearOsMenuButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: WearOsConstants.bodySize + 2,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
