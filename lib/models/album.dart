class Album {
  final String id;
  final String title;
  final String artistName;
  final String artistId;
  final String coverUuid;
  final String? type;
  final num? popularity;


  Album({
    required this.id,
    required this.title,
    required this.artistName,
    required this.artistId,
    required this.coverUuid,
    this.type,
    this.popularity,
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
      type: json['type']?.toString(),
      popularity: _normalizePopularity(json['popularity']),
    );
  }

  static num? _normalizePopularity(dynamic value) {
    if (value == null) return null;
    num? pop;
    if (value is num) {
      pop = value;
    } else {
      pop = num.tryParse(value.toString());
    }
    
    if (pop != null && pop > 0 && pop <= 1.0) {
      return pop * 100.0;
    }
    return pop;
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
      'popularity': popularity,
    };
  }
}
