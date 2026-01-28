import 'package:just_audio_background/just_audio_background.dart';

class Track {
  final String id;
  final String title;
  final String artistName;
  final String artistId;
  final String albumId;
  final String albumTitle;
  final String albumCoverUuid;
  final String? artistPictureUuid;
  final int duration; // in seconds, optional if API provides it
  final int? trackNumber;
  final String? releaseDate;
  final String? localPath; // For downloaded tracks
  final num? popularity;


  Track({
    required this.id,
    required this.title,
    required this.artistName,
    required this.artistId,
    required this.albumId,
    required this.albumTitle,
    required this.albumCoverUuid,
    this.artistPictureUuid,
    this.duration = 0,
    this.trackNumber,
    this.releaseDate,
    this.localPath,
    this.popularity,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    // Extract artist info
    String? artistName = json['artistName']?.toString();
    String? artistId = json['artistId']?.toString();
    String? artistPictureUuid = json['artistPictureUuid']?.toString() ?? json['artistPicture']?.toString();

    if (artistName == null && json['artist'] is Map) {
      artistName = json['artist']['name']?.toString();
      artistId ??= json['artist']['id']?.toString();
      artistPictureUuid ??= json['artist']['picture']?.toString() ?? json['artist']['pictureUuid']?.toString();
    } else if (artistName == null && json['artists'] is List && (json['artists'] as List).isNotEmpty) {
      final firstArtist = json['artists'][0];
      if (firstArtist is Map) {
        artistName = firstArtist['name']?.toString();
        artistId ??= firstArtist['id']?.toString();
        artistPictureUuid ??= firstArtist['picture']?.toString() ?? firstArtist['pictureUuid']?.toString();
      }
    }

    // Extract album info
    String? albumId = json['albumId']?.toString();
    String? albumTitle = json['albumTitle']?.toString();
    String? albumCoverUuid = json['albumCoverUuid']?.toString() ?? json['coverUuid']?.toString() ?? json['cover']?.toString();
    
    if (json['album'] is Map) {
      albumId ??= json['album']['id']?.toString();
      albumTitle ??= json['album']['title']?.toString();
      albumCoverUuid ??= json['album']['cover']?.toString() ?? json['album']['coverUuid']?.toString();
    }

    return Track(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Title',
      artistName: artistName ?? 'Unknown Artist',
      artistId: artistId ?? '',
      albumId: albumId ?? '',
      albumTitle: albumTitle ?? 'Unknown Album',
      albumCoverUuid: albumCoverUuid ?? '',
      artistPictureUuid: artistPictureUuid,
      duration: json['duration'] ?? 0,
      trackNumber: json['trackNumber'] ?? json['track_number'],
      releaseDate: json['releaseDate']?.toString() ?? json['release_date']?.toString() ?? json['streamStartDate']?.toString(),
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artistName': artistName,
      'artistId': artistId,
      'artistPictureUuid': artistPictureUuid,
      'albumId': albumId,
      'albumTitle': albumTitle,
      'albumCoverUuid': albumCoverUuid,
      'duration': duration,
      'trackNumber': trackNumber,
      'releaseDate': releaseDate,
      'localPath': localPath,
      'popularity': popularity,
    };
  }

  // Helper to get full cover art URL
  String get coverUrl {
    if (albumCoverUuid.isEmpty) return '';
    
    // 1. IPFS
    if (albumCoverUuid.startsWith('ipfs://')) {
      final hash = albumCoverUuid.replaceFirst('ipfs://', '');
      return 'https://ipfs.io/ipfs/$hash';
    }
    
    // 2. Imgur (assuming 7-character alphanumeric IDs are common for Imgur)
    final imgurRegex = RegExp(r'^[a-zA-Z0-9]{7}$');
    if (imgurRegex.hasMatch(albumCoverUuid)) {
      return 'https://i.imgur.com/$albumCoverUuid.jpg';
    }

    // 3. Default: Tidal-style path resolution
    // 3f49a481-68e5-46e4... -> 3f/49/a4/81/...
    final path = albumCoverUuid.replaceAll('-', '/');
    return 'https://resources.tidal.com/images/$path/1280x1280.jpg';
  }

  Track copyWith({
    String? localPath,
    int? trackNumber,
    String? releaseDate,
    String? artistPictureUuid,
    num? popularity,
  }) {
    return Track(
      id: id,
      title: title,
      artistName: artistName,
      artistId: artistId,
      artistPictureUuid: artistPictureUuid ?? this.artistPictureUuid,
      albumId: albumId,
      albumTitle: albumTitle,
      albumCoverUuid: albumCoverUuid,
      duration: duration,
      trackNumber: trackNumber ?? this.trackNumber,
      releaseDate: releaseDate ?? this.releaseDate,
      localPath: localPath ?? this.localPath,
      popularity: popularity ?? this.popularity,
    );
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      album: artistName, // Using artistName as album if not available, or we can use albumId
      title: title,
      artist: artistName,
      duration: duration > 0 ? Duration(seconds: duration) : null,
      artUri: coverUrl.isNotEmpty ? Uri.parse(coverUrl) : null,
    );
  }
}
