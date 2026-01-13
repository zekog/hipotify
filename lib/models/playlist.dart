import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final List<Track> tracks;

  Playlist({
    required this.id,
    required this.name,
    required this.tracks,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      tracks: (json['tracks'] as List?)
              ?.map((t) => Track.fromJson(t))
              .toList() ??
          [],
    );
  }
}
