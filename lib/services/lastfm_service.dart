import 'dart:convert';
import 'package:http/http.dart' as http;

class LastFmService {
  static const String _apiKey = '2c3493b827329528d2d6c05d7b57906d'; // Public key commonly used in examples
  static const String _baseUrl = 'http://ws.audioscrobbler.com/2.0/';

  static Future<LastFmArtist?> getArtistInfo(String artistName) async {
    try {
      final uri = Uri.parse('$_baseUrl?method=artist.getinfo&artist=${Uri.encodeComponent(artistName)}&api_key=$_apiKey&format=json');
      print('LastFmService: Fetching info for $artistName: $uri');
      
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final artistData = data['artist'];
        if (artistData != null) {
          return LastFmArtist.fromJson(artistData);
        }
      } else {
        print('LastFmService: Error ${response.statusCode}');
      }
    } catch (e) {
      print('LastFmService: Exception: $e');
    }
    return null;
  }

  static Future<List<LastFmTrack>> getTopTracks(String artistName) async {
    try {
      final uri = Uri.parse('$_baseUrl?method=artist.gettoptracks&artist=${Uri.encodeComponent(artistName)}&api_key=$_apiKey&format=json&limit=50');
      print('LastFmService: Fetching top tracks for $artistName: $uri');

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracksData = data['toptracks']?['track'];
        
        if (tracksData is List) {
          return tracksData.map((t) => LastFmTrack.fromJson(t)).toList();
        }
      }
    } catch (e) {
      print('LastFmService: Exception fetching top tracks: $e');
    }
    return [];
  }
}

class LastFmArtist {
  final String name;
  final String? bio;
  final List<String> tags;

  LastFmArtist({required this.name, this.bio, this.tags = const []});

  factory LastFmArtist.fromJson(Map<String, dynamic> json) {
    String? bioContent;
    final bioData = json['bio'];
    if (bioData != null) {
      // Remove CDATA and links if possible, or just take content
      bioContent = bioData['content'] ?? bioData['summary'];
      // Basic cleanup of links <a href="...">
      if (bioContent != null) {
        bioContent = bioContent.replaceAll(RegExp(r'<[^>]*>'), '');
      }
    }

    List<String> tagsList = [];
    final tagsData = json['tags'];
    if (tagsData != null && tagsData['tag'] is List) {
      tagsList = (tagsData['tag'] as List).map((t) => t['name'].toString()).toList();
    }

    return LastFmArtist(
      name: json['name'] ?? '',
      bio: bioContent,
      tags: tagsList,
    );
  }
}

class LastFmTrack {
  final String name;
  final int playcount;
  final int listeners;
  final String? url;

  LastFmTrack({
    required this.name,
    required this.playcount,
    required this.listeners,
    this.url,
  });

  factory LastFmTrack.fromJson(Map<String, dynamic> json) {
    return LastFmTrack(
      name: json['name'] ?? '',
      playcount: int.tryParse(json['playcount']?.toString() ?? '0') ?? 0,
      listeners: int.tryParse(json['listeners']?.toString() ?? '0') ?? 0,
      url: json['url'],
    );
  }
}
