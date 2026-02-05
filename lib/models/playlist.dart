import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final List<Track> tracks;
  final String? customCoverPath;
  final String? ownerId;
  final bool isPublic;

  Playlist({
    required this.id,
    required this.name,
    required this.tracks,
    this.customCoverPath,
    this.ownerId,
    this.isPublic = false,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? (json['title']?.toString() ?? 'Unknown Playlist'),
      tracks: (json['tracks'] as List? ?? [])
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      customCoverPath: json['customCoverPath']?.toString(),
      ownerId: json['ownerId']?.toString() ?? json['user_id']?.toString(),
      isPublic: json['isPublic'] ?? json['is_public'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'customCoverPath': customCoverPath,
      'ownerId': ownerId,
      'isPublic': isPublic,
    };
  }
}
