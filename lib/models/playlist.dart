import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final List<Track> tracks;
  final String? customCoverPath;

  Playlist({
    required this.id,
    required this.name,
    required this.tracks,
    this.customCoverPath,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Playlist',
      tracks: (json['tracks'] as List? ?? [])
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      customCoverPath: json['customCoverPath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'customCoverPath': customCoverPath,
    };
  }
}
