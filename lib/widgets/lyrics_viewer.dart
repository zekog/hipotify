import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/lyrics.dart';

class LyricsViewer extends StatefulWidget {
  final Lyrics lyrics;
  final Stream<Duration> positionStream;
  final Function(Duration) onSeek;

  const LyricsViewer({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.onSeek,
  });

  @override
  State<LyricsViewer> createState() => _LyricsViewerState();
}

class _LyricsViewerState extends State<LyricsViewer> {
  final ScrollController _scrollController = ScrollController();
  List<_LrcLine> _lines = [];
  int _currentLineIndex = -1;
  StreamSubscription? _positionSubscription;
  bool _isUserScrolling = false;
  Timer? _resumeTimer;
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _positionSubscription = widget.positionStream.listen((position) {
      _updateCurrentLine(position);
    });
  }

  @override
  void didUpdateWidget(LyricsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics.trackId != widget.lyrics.trackId) {
      _lineKeys.clear();
      _parseLyrics();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _scrollController.dispose();
    _resumeTimer?.cancel();
    super.dispose();
  }

  void _parseLyrics() {
    if (widget.lyrics.subtitles == null || widget.lyrics.subtitles!.isEmpty) {
      _lines = [];
      return;
    }

    final lines = widget.lyrics.subtitles!.split(RegExp(r'\r?\n'));
    final regExp = RegExp(r'\[(\d+):(\d+)([:.]\d+)?\](.*)');
    
    _lines = lines.map((line) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final minutesStr = match.group(1);
        final secondsStr = match.group(2);
        final msPart = match.group(3);
        final textPart = match.group(4);

        if (minutesStr == null || secondsStr == null) return null;

        final minutes = int.parse(minutesStr);
        final seconds = int.parse(secondsStr);
        
        double ms = 0;
        if (msPart != null) {
          ms = double.parse(msPart.replaceAll(':', '.')) * 1000;
        }
        final time = Duration(milliseconds: (minutes * 60 * 1000 + seconds * 1000 + ms.toInt()));
        final text = (textPart ?? "").trim();
        if (text.isEmpty) return null;
        return _LrcLine(time: time, text: text);
      }
      return null;
    }).whereType<_LrcLine>().toList();
    
    _lines.sort((a, b) => a.time.compareTo(b.time));
  }

  void _updateCurrentLine(Duration position) {
    if (_lines.isEmpty) return;

    int index = _lines.lastIndexWhere((line) => line.time <= position);
    if (index != _currentLineIndex) {
      setState(() {
        _currentLineIndex = index;
      });
      if (!_isUserScrolling) {
        // Delay slightly to allow the UI to update before scrolling
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCurrentLine();
        });
      }
    }
  }

  void _scrollToCurrentLine() {
    if (_currentLineIndex < 0 || !_scrollController.hasClients) return;
    
    final key = _lineKeys[_currentLineIndex];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        alignment: 0.5, // Center the line
      );
    }
  }

  void _onUserScroll() {
    if (!_isUserScrolling) {
      setState(() {
        _isUserScrolling = true;
      });
    }
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isUserScrolling = false;
        });
        _scrollToCurrentLine();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return _buildPlainLyrics();
    }

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              if (notification.dragDetails != null) {
                _onUserScroll();
              }
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.45),
            itemCount: _lines.length,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 1000, // Keep more items in tree for ensureVisible
            itemBuilder: (context, index) {
              final line = _lines[index];
              final isCurrent = index == _currentLineIndex;
              final isPast = index < _currentLineIndex;
              
              final key = _lineKeys.putIfAbsent(index, () => GlobalKey());
              
              return GestureDetector(
                key: key,
                onTap: () {
                  widget.onSeek(line.time);
                  setState(() {
                    _isUserScrolling = false;
                  });
                  Future.delayed(const Duration(milliseconds: 50), _scrollToCurrentLine);
                },
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 500),
                  opacity: isCurrent ? 1.0 : (isPast ? 0.3 : 0.5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
                    transform: Matrix4.identity()..scale(isCurrent ? 1.08 : 1.0),
                    transformAlignment: Alignment.centerLeft,
                    child: Text(
                      line.text,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCurrent ? 32 : 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.8,
                        height: 1.2,
                        shadows: isCurrent ? [
                          Shadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          )
                        ] : null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_isUserScrolling)
          Positioned(
            bottom: 40,
            right: 30,
            child: FadeInUp(
              duration: const Duration(milliseconds: 400),
              child: FloatingActionButton(
                onPressed: () {
                  setState(() {
                    _isUserScrolling = false;
                  });
                  _scrollToCurrentLine();
                },
                backgroundColor: Colors.white.withOpacity(0.15),
                elevation: 0,
                child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlainLyrics() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Text(
        widget.lyrics.lyrics ?? "No lyrics available",
        textAlign: TextAlign.left,
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.6,
        ),
      ),
    );
  }
}

class _LrcLine {
  final Duration time;
  final String text;

  _LrcLine({required this.time, required this.text});
}

// Simple FadeInUp animation helper
class FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const FadeInUp({super.key, required this.child, required this.duration});

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _offset = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}
