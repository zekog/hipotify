class Album {
  final String id;
  final String title;
  final String artistName;
  final String artistId;
  final String coverUuid;

  Album({
    required this.id,
    required this.title,
    required this.artistName,
    required this.artistId,
    required this.coverUuid,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    // Extract artist info from nested objects if available
    String? artistName = json['artistName']?.toString();
    String? artistId = json['artistId']?.toString();

    if (artistName == null && json['artist'] is Map) {
      artistName = json['artist']['name']?.toString();
      artistId ??= json['artist']['id']?.toString();
    } else if (artistName == null && json['artists'] is List && (json['artists'] as List).isNotEmpty) {
      final firstArtist = json['artists'][0];
      if (firstArtist is Map) {
        artistName = firstArtist['name']?.toString();
        artistId ??= firstArtist['id']?.toString();
      }
    }

    return Album(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Album',
      artistName: artistName ?? 'Unknown Artist',
      artistId: artistId ?? '',
      coverUuid: json['coverUuid']?.toString() ?? json['cover']?.toString() ?? '',
    );
  }

  String get coverUrl {
    if (coverUuid.isEmpty) return '';
    final path = coverUuid.replaceAll('-', '/');
    return 'https://resources.tidal.com/images/$path/320x320.jpg';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artistName': artistName,
      'artistId': artistId,
      'coverUuid': coverUuid,
    };
  }
}
