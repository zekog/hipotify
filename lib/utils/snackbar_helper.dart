import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../main.dart';

/// Helper function to dynamically calculate snackbar margin that accounts for mini player visibility
EdgeInsets getSnackBarMargin(BuildContext context) {
  final player = Provider.of<PlayerProvider>(context, listen: false);
  final isPlayerVisible = MiniPlayerVisibilityObserver.isPlayerVisible.value;
  final isMiniPlayerVisible = player.currentTrack != null && 
                              !isPlayerVisible && 
                              !player.isMiniPlayerHidden;
  
  if (!isMiniPlayerVisible) {
    return EdgeInsets.only(
      bottom: MediaQuery.of(context).padding.bottom + 8,
      left: 8,
      right: 8,
    );
  }

  // Dynamically detect heights
  double miniPlayerHeight = 0;
  double bottomNavBarHeight = kBottomNavigationBarHeight;
  double additionalSpacing = 16; // Spacing between snackbar and mini player

  // Try to get mini player height from RenderBox
  try {
    final miniPlayerContext = miniPlayerKey.currentContext;
    if (miniPlayerContext != null) {
      final RenderBox? miniPlayerBox = miniPlayerContext.findRenderObject() as RenderBox?;
      if (miniPlayerBox != null && miniPlayerBox.hasSize) {
        miniPlayerHeight = miniPlayerBox.size.height;
      }
    }
  } catch (e) {
    // Fallback to default height if measurement fails
  }

  // If mini player height wasn't measured, use default
  // Mini player: 64px height + 8px top padding + 8px bottom padding = 80px
  if (miniPlayerHeight == 0) {
    miniPlayerHeight = 80;
  }

  // Calculate total bottom margin
  final totalBottomMargin = MediaQuery.of(context).padding.bottom + 
                            bottomNavBarHeight + 
                            miniPlayerHeight + 
                            additionalSpacing;

  return EdgeInsets.only(
    bottom: totalBottomMargin,
    left: 8,
    right: 8,
  );
}

/// Helper function to show a snackbar at the top of the screen with fade animations
void showSnackBar(BuildContext context, String message, {Duration? duration}) {
  // Use Overlay to display snackbar above everything
  final overlay = navigatorKey.currentState?.overlay;
  if (overlay == null) {
    // Fallback to context overlay if navigatorKey is not available
    final contextOverlay = Overlay.of(context);
    _showTopSnackBar(contextOverlay, message, duration);
    return;
  }
  
  _showTopSnackBar(overlay, message, duration);
}

void _showTopSnackBar(OverlayState overlay, String message, Duration? duration) {
  final actualDuration = duration ?? const Duration(seconds: 2);
  final fadeOutDuration = const Duration(milliseconds: 300);
  
  late OverlayEntry overlayEntry;
  bool removed = false;
  void safeRemove() {
    if (removed) return;
    try {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
        removed = true;
      }
    } catch (e) {
      print("SnackbarHelper: Error removing overlay: $e");
    }
  }

  overlayEntry = OverlayEntry(
    opaque: false,
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      right: 8,
      child: IgnorePointer(
        ignoring: true,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: _AnimatedSnackBar(
              message: message,
              duration: actualDuration,
              fadeOutDuration: fadeOutDuration,
              onDismiss: safeRemove,
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(overlayEntry);

  // Remove overlay entry after duration + fade out time (backup removal)
  Future.delayed(actualDuration + fadeOutDuration + const Duration(milliseconds: 500), safeRemove);
}

class _AnimatedSnackBar extends StatefulWidget {
  final String message;
  final Duration duration;
  final Duration fadeOutDuration;
  final VoidCallback onDismiss;

  const _AnimatedSnackBar({
    required this.message,
    required this.duration,
    required this.fadeOutDuration,
    required this.onDismiss,
  });

  @override
  State<_AnimatedSnackBar> createState() => _AnimatedSnackBarState();
}

class _AnimatedSnackBarState extends State<_AnimatedSnackBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: widget.fadeOutDuration,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Start fade in
    _controller.forward();

    // Start fade out before duration ends
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF323232),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
