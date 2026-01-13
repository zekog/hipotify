class Artist {
  final String id;
  final String name;
  final String pictureUuid;

  Artist({
    required this.id,
    required this.name,
    required this.pictureUuid,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Artist',
      pictureUuid: json['pictureUuid']?.toString() ?? json['picture']?.toString() ?? '',
    );
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
    };
  }
}
