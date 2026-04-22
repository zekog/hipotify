import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/player_provider.dart';
import '../../providers/library_provider.dart';
import '../../models/track.dart';
import '../../models/lyrics.dart';
import '../../services/api_service.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/lyrics_viewer.dart';
import '../../widgets/rotary_scroll_wrapper.dart';
import 'package:wear_os_scrollbar/wear_os_scrollbar.dart';
import '../../services/download_service.dart';
import '../../services/hive_service.dart';

/// Wear OS optimized player screen with rotary crown support and swipe-up menu
class WearOsPlayerScreen extends StatefulWidget {
  const WearOsPlayerScreen({super.key});

  @override
  State<WearOsPlayerScreen> createState() => _WearOsPlayerScreenState();
}

class _WearOsPlayerScreenState extends State<WearOsPlayerScreen>
    with SingleTickerProviderStateMixin {
  bool _showControls = true;
  Timer? _controlsTimer;
  Timer? _volumeDebounceTimer;
  late AnimationController _controlsAnimationController;
  final ValueNotifier<double> _localVolumeNotifier = ValueNotifier<double>(0.0);
  double _localVolumeValue = 0.0;
  bool _isInitVolume = false;
  
  // Rotary virtual scroll handling
  final ScrollController _rotaryController = ScrollController(initialScrollOffset: 1000.0);
  static const double _scrollBaseline = 1000.0;
  bool _isRotaryJumping = false;

  @override
  void initState() {
    super.initState();
    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _showControlsWithTimeout();

    _rotaryController.addListener(_handleRotaryScroll);
  }

  void _handleRotaryScroll() {
    if (!_rotaryController.hasClients || _isRotaryJumping) return;
    
    final currentOffset = _rotaryController.offset;
    final delta = currentOffset - _scrollBaseline;
    
    if (delta.abs() > 0.1) {
      // Sensitivity: higher divisor = slower volume change
      _updateVolume(delta / 400.0);
      
      // Jump back to baseline to allow "infinite" rotation
      _isRotaryJumping = true;
      _rotaryController.jumpTo(_scrollBaseline);
      
      // Reset flag after a tiny delay or microtask to ignore the self-triggered event
      Future.microtask(() => _isRotaryJumping = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitVolume) {
      _isInitVolume = true;
      _localVolumeValue = context.read<PlayerProvider>().player.volume;
      _localVolumeNotifier.value = _localVolumeValue;
    }
  }

  void _showControlsWithTimeout() {
    if (!_showControls) {
      setState(() => _showControls = true);
      _controlsAnimationController.forward();
    }
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _showControls = false);
        _controlsAnimationController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _rotaryController.removeListener(_handleRotaryScroll);
    _rotaryController.dispose();
    _controlsTimer?.cancel();
    _volumeDebounceTimer?.cancel();
    _controlsAnimationController.dispose();
    _localVolumeNotifier.dispose();
    super.dispose();
  }

  void _updateVolume(double delta) {
    if (delta == 0) return;
    
    // Force controls visibility on crown move
    if (!_showControls) _showControlsWithTimeout();
    
    _localVolumeValue = (_localVolumeValue + delta).clamp(0.0, 1.0);
    if (_localVolumeNotifier.value != _localVolumeValue) {
      _localVolumeNotifier.value = _localVolumeValue;
      
      // INSTANT update to the player as requested
      if (mounted) {
        context.read<PlayerProvider>().setVolume(_localVolumeValue);
      }
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    // Swipe Up: Pokaż Menu (Lyrics/Stats)
    if (details.primaryVelocity! < -300) {
       _openPlayerMenu();
    }
    // Swipe Down: Pokaż Menu Akcji (Download/Like/Playlist)
    else if (details.primaryVelocity! > 300) {
       _openActionsMenu();
    }
  }

  void _openActionsMenu() {
    final track = context.read<PlayerProvider>().currentTrack;
    if (track == null) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _WearOsActionsScreen(track: track),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, -1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      )
    );
  }

  void _openPlayerMenu() {
    final track = context.read<PlayerProvider>().currentTrack;
    if (track == null) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _WearOsPlayerMenuScreen(track: track),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PlayerProvider, LibraryProvider>(
      builder: (context, player, library, _) {
        final track = player.effectiveTrack;
        if (track == null) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(player.isRemoteMode ? Icons.cast_connected : Icons.music_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    player.isRemoteMode ? 'Connect to device' : 'No track playing',
                    style: TextStyle(
                      fontSize: WearOsConstants.titleSize,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final isLiked = library.isLiked(track.id);
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 1. Background
              Positioned.fill(
                child: RepaintBoundary(
                  child: _buildBackground(track),
                ),
              ),

              // 2. Custom Volume Arc Indicator
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _localVolumeNotifier,
                    builder: (context, volume, _) {
                      return CustomPaint(
                        painter: VolumeArcPainter(
                          volume: volume,
                          activeColor: Colors.green,
                          inactiveColor: Colors.white10,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 3. Virtual Scroll Layer (To catch rotary crown events like in Lyrics menu)
              Positioned.fill(
                child: RotaryScrollWrapper(
                  controller: _rotaryController,
                  child: SingleChildScrollView(
                    controller: _rotaryController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: 2000, // Dummy scrollable area
                      width: double.infinity,
                    ),
                  ),
                ),
              ),

              // 4. UI Layer
              GestureDetector(
                onTap: _showControlsWithTimeout,
                onVerticalDragEnd: _handleVerticalDragEnd,
                behavior: HitTestBehavior.translucent,
                child: SafeArea(
                    child: Column(
                      children: [
                        if (player.isRemoteMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Icon(Icons.cast_connected, size: 16, color: Theme.of(context).primaryColor),
                          ),
                        _buildTopBar(context, player, isLiked),
                        const Spacer(),
                      _buildTrackInfo(track),
                      const SizedBox(height: WearOsConstants.defaultPadding),
                      _buildProgressBar(player),
                      const SizedBox(height: WearOsConstants.defaultPadding),
                      _buildMainControls(player),
                      Padding(
                        padding: const EdgeInsets.only(top: WearOsConstants.smallPadding, bottom: 8),
                        child: Icon(Icons.keyboard_arrow_up, color: Colors.white.withOpacity(0.3), size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

      },
    );
  }

  Widget _buildBackground(Track track) {
    return CachedNetworkImage(
      imageUrl: track.coverUrl,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => Container(color: Colors.black),
    );
  }

  Widget _buildTopBar(
      BuildContext context, PlayerProvider player, bool isLiked) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: WearOsConstants.smallPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? Colors.pink : Colors.white,
              size: 24,
            ),
            onPressed: () async {
              final currentTrack = player.effectiveTrack;
              if (currentTrack == null) return;
              
              await context
                  .read<LibraryProvider>()
                  .toggleLike(currentTrack);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context
                              .read<LibraryProvider>()
                              .isLiked(currentTrack.id)
                          ? 'Added to favorites'
                          : 'Removed from favorites',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(Track track) {
    return Hero(
      tag: 'album_art_${track.id}',
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              spreadRadius: 5,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CachedNetworkImage(
            imageUrl: track.coverUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: Colors.grey[900],
              child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey[800],
              child: const Icon(Icons.music_note, size: 60),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackInfo(Track track) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: WearOsConstants.defaultPadding),
      child: Column(
        children: [
          Text(
            track.title,
            style: const TextStyle(
              fontSize: WearOsConstants.titleSize,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            track.artistName,
            style: TextStyle(
              fontSize: WearOsConstants.captionSize,
              color: Colors.white.withOpacity(0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(PlayerProvider player) {
    final position = player.effectivePosition;
    final duration = player.effectiveDuration;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WearOsConstants.smallPadding),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          activeTrackColor: player.isRemoteMode ? Colors.green : Theme.of(context).primaryColor,
          inactiveTrackColor: Colors.white10,
          thumbColor: player.isRemoteMode ? Colors.green : Colors.white,
        ),
        child: Slider(
          value: position.inSeconds.toDouble().clamp(0.0, duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0),
          max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
          onChanged: (value) {
            player.seek(Duration(seconds: value.toInt()));
          },
        ),
      ),
    );
  }


  Widget _buildMainControls(PlayerProvider player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: Icons.skip_previous,
          size: 40,
          onTap: () => player.effectivePrevious(),
        ),
        _ControlButton(
          icon: player.effectiveIsPlaying ? Icons.pause : Icons.play_arrow,
          size: 56,
          isPrimary: true,
          onTap: () => player.togglePlayPause(),
        ),
        _ControlButton(
          icon: Icons.skip_next,
          size: 40,
          onTap: () => player.effectiveNext(),
        ),
      ],
    );
  }
}


class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isPrimary ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
          // Black border for visibility on white backgrounds
          border: Border.all(
            color: Colors.black,
            width: isPrimary ? 1.5 : 1.0,
          ),
          boxShadow: isPrimary ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 4,
            )
          ] : null,
        ),
        child: Icon(
          icon,
          color: isPrimary ? Colors.black : Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }
}

/// Menu dla Playera dla wyświetlania Lyrics i Stats
class _WearOsPlayerMenuScreen extends StatefulWidget {
  final Track track;
  const _WearOsPlayerMenuScreen({required this.track});

  @override
  State<_WearOsPlayerMenuScreen> createState() => _WearOsPlayerMenuScreenState();
}

class _WearOsPlayerMenuScreenState extends State<_WearOsPlayerMenuScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RotaryScrollWrapper(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(height: 8),
              
              _buildStatRow('Title', widget.track.title),
              _buildStatRow('Artist', widget.track.artistName),
              
              const SizedBox(height: 16),
              
              const Text(
                'Lyrics',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: WearOsConstants.titleSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 8),
              
              FutureBuilder<Lyrics?>(
                future: ApiService.getLyrics(widget.track.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData || (snapshot.data?.subtitles == null && snapshot.data?.lyrics == null)) {
                    return const SizedBox(
                      height: 60,
                      child: Center(child: Text("No lyrics available", style: TextStyle(color: Colors.white54))),
                    );
                  }
                  
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height - 40,
                    ),
                    child: LyricsViewer(
                      lyrics: snapshot.data!,
                      positionStream: context.read<PlayerProvider>().isRemoteMode 
                        ? Stream.periodic(const Duration(milliseconds: 500), (_) => context.read<PlayerProvider>().effectivePosition)
                        : context.read<PlayerProvider>().player.positionStream,
                      onSeek: (pos) => context.read<PlayerProvider>().seek(pos),
                      textAlign: TextAlign.center,
                      shrinkWrap: false,
                      physics: const BouncingScrollPhysics(),
                      textStyle: const TextStyle(fontSize: 16, color: Colors.white54),
                      activeTextStyle: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                      bottomPadding: 20, // Final fix for the empty space issue
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Ekran akcji dla utworu (Download, Like, Playlisty)
class _WearOsActionsScreen extends StatefulWidget {
  final Track track;
  const _WearOsActionsScreen({required this.track});

  @override
  State<_WearOsActionsScreen> createState() => _WearOsActionsScreenState();
}

class _WearOsActionsScreenState extends State<_WearOsActionsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RotaryScrollWrapper(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              const SizedBox(height: 24),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              const Text(
                'Actions',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              
              // 1. Download
              _ActionTile(
                icon: Icons.download,
                label: 'Download',
                onTap: () async {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download started...'), duration: Duration(seconds: 1))
                    );
                    Navigator.pop(context);
                    await DownloadService.downloadTrack(
                      widget.track,
                      quality: HiveService.audioQuality,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download complete!'), backgroundColor: Colors.green)
                      );
                      context.read<LibraryProvider>().refreshDownloads();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red)
                      );
                    }
                  }
                },
              ),

              // 2. Like
              Consumer2<LibraryProvider, PlayerProvider>(
                builder: (context, library, player, _) {
                  final currentTrack = player.effectiveTrack ?? widget.track;
                  final isLiked = library.isLiked(currentTrack.id);
                  return _ActionTile(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    label: isLiked ? 'Unlike' : 'Like',
                    color: isLiked ? Colors.pink : null,
                    onTap: () => library.toggleLike(currentTrack),
                  );
                },
              ),

              const Divider(color: Colors.white10),

              // 3. New Playlist
              _ActionTile(
                icon: Icons.playlist_add,
                label: 'New Playlist',
                onTap: () => _showNewPlaylistDialog(context),
              ),

              // 4. Existing Playlists
              Consumer<LibraryProvider>(
                builder: (context, library, _) {
                  if (library.playlists.isEmpty) return const SizedBox();
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Add to playlist:', style: TextStyle(fontSize: 10, color: Colors.white54)),
                      ),
                      ...library.playlists.map((playlist) {
                        final inPlaylist = library.isTrackInPlaylist(playlist.id, widget.track.id);
                        return _ActionTile(
                          icon: inPlaylist ? Icons.check_circle : Icons.playlist_add,
                          label: playlist.name,
                          onTap: () {
                            library.addTrackToPlaylist(playlist.id, widget.track);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Added to ${playlist.name}'), duration: const Duration(seconds: 1))
                            );
                          },
                        );
                      }),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewPlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('New Playlist', style: TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Name...',
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final playlist = await context.read<LibraryProvider>().createPlaylist(controller.text);
                if (context.mounted) {
                  context.read<LibraryProvider>().addTrackToPlaylist(playlist.id, widget.track);
                  Navigator.pop(context); // Dialog
                  Navigator.pop(context); // Menu
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created playlist and added track'))
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: color ?? Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VolumeArcPainter extends CustomPainter {
  final double volume;
  final Color activeColor;
  final Color inactiveColor;

  VolumeArcPainter({
    required this.volume,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (volume <= 0) return;
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    
    const startAngle = -0.6; // ~ -35 degrees from 3 o'clock
    const sweepAngle = 1.2;  // ~ 70 degrees total
    
    final bgPaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Draw background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Draw active volume arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * volume,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant VolumeArcPainter oldDelegate) => 
      oldDelegate.volume != volume;
}
