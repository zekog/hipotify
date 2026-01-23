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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'customCoverPath': customCoverPath,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tracks: (json['tracks'] as List?)
              ?.map((t) {
                if (t is Map) {
                  return Track.fromJson(Map<String, dynamic>.from(t));
                }
                return null;
              })
              .whereType<Track>()
              .toList() ??
          [],
      customCoverPath: json['customCoverPath']?.toString(),
    );
  }

  Playlist copyWith({
    String? id,
    String? name,
    List<Track>? tracks,
    String? customCoverPath,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      customCoverPath: customCoverPath ?? this.customCoverPath,
    );
  }
}
