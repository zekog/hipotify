class TidalPlaylist {
  final String id;
  final String title;
  final String? description;
  final int numberOfTracks;
  final String imageUrl;
  final String? creatorName;

  TidalPlaylist({
    required this.id,
    required this.title,
    this.description,
    required this.numberOfTracks,
    required this.imageUrl,
    this.creatorName,
  });

  factory TidalPlaylist.fromJson(Map<String, dynamic> json) {
    // Tidal API uses 'uuid' for playlists
    final id = json['uuid']?.toString() ?? json['id']?.toString() ?? '';
    final imageUuid = json['image'] ?? json['squareImage'] ?? json['uuid'];
    
    return TidalPlaylist(
      id: id,
      title: json['title'] ?? 'Unknown Playlist',
      description: json['description'],
      numberOfTracks: json['numberOfTracks'] ?? 0,
      imageUrl: imageUuid != null 
          ? 'https://resources.tidal.com/images/${imageUuid.toString().replaceAll('-', '/')}/640x640.jpg'
          : '',
      creatorName: json['creator']?['name'] ?? json['creatorName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': id,
      'title': title,
      'description': description,
      'numberOfTracks': numberOfTracks,
      'image': imageUrl.split('/').reversed.skip(1).take(1).firstOrNull, // Rough extraction of UUID if needed
      'imageUrl': imageUrl,
      'creatorName': creatorName,
    };
  }
}
