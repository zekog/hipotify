class Lyrics {
  final String trackId;
  final String? lyrics;
  final String? subtitles;
  final String? lyricsProvider;

  Lyrics({
    required this.trackId,
    this.lyrics,
    this.subtitles,
    this.lyricsProvider,
  });

  factory Lyrics.fromJson(Map<String, dynamic> json, String trackId) {
    return Lyrics(
      trackId: trackId,
      lyrics: json['lyrics'],
      subtitles: json['subtitles'],
      lyricsProvider: json['lyricsProvider'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lyrics': lyrics,
      'subtitles': subtitles,
      'lyricsProvider': lyricsProvider,
    };
  }

  String? toWebVTT() {
    if (subtitles == null || subtitles!.isEmpty) return null;

    final lines = subtitles!.split(RegExp(r'\r?\n'));
    final regExp = RegExp(r'\[(\d+):(\d+)([:.]\d+)?\](.*)');
    
    StringBuffer vtt = StringBuffer();
    vtt.writeln("WEBVTT");
    vtt.writeln();

    List<_LrcLine> parsedLines = [];
    for (var line in lines) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final msPart = match.group(3) ?? ".000";
        final text = match.group(4)?.trim() ?? "";
        
        if (text.isEmpty) continue;

        double ms = double.parse(msPart.replaceAll(':', '.')) * 1000;
        final startTime = Duration(milliseconds: (minutes * 60 * 1000 + seconds * 1000 + ms.toInt()));
        parsedLines.add(_LrcLine(time: startTime, text: text));
      }
    }

    parsedLines.sort((a, b) => a.time.compareTo(b.time));

    for (int i = 0; i < parsedLines.length; i++) {
      final current = parsedLines[i];
      final next = (i < parsedLines.length - 1) ? parsedLines[i + 1] : null;
      
      // Use next line's start time as end time, or current + 5s if last
      final endTime = next?.time ?? current.time + const Duration(seconds: 5);
      
      vtt.writeln("${_formatVttTime(current.time)} --> ${_formatVttTime(endTime)}");
      vtt.writeln(current.text);
      vtt.writeln();
    }

    return vtt.toString();
  }

  String _formatVttTime(Duration d) {
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return "$hh:$mm:$ss.$ms";
  }
}

class _LrcLine {
  final Duration time;
  final String text;
  _LrcLine({required this.time, required this.text});
}
