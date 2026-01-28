class Artist {
  final String id;
  final String name;
  final String pictureUuid;
  final num? popularity;


  Artist({
    required this.id,
    required this.name,
    required this.pictureUuid,
    this.popularity,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Artist',
      pictureUuid: json['pictureUuid']?.toString() ?? json['picture']?.toString() ?? '',
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

  String get pictureUrl {
    if (pictureUuid.isEmpty) return '';
    final path = pictureUuid.replaceAll('-', '/');
    return 'https://resources.tidal.com/images/$path/320x320.jpg';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pictureUuid': pictureUuid,
      'popularity': popularity,
    };
  }
}
