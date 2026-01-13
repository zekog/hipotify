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
}
