import 'dart:convert';
import 'package:http/http.dart' as http;

class InfoService {
  // --- Wikipedia for Bio ---
  
  static Future<String?> getArtistBio(String artistName) async {
    // Prioritize English as requested
    String? bio = await _fetchWikipediaBio(artistName, 'en');
    if (bio != null && bio.isNotEmpty) return bio;

    // Fallback to Polish
    return await _fetchWikipediaBio(artistName, 'pl');
  }

  static Future<String?> _fetchWikipediaBio(String query, String lang) async {
    try {
      final uri = Uri.parse(
          'https://$lang.wikipedia.org/w/api.php?action=query&format=json&prop=extracts&exintro=true&explaintext=true&redirects=1&titles=${Uri.encodeComponent(query)}');
      print('InfoService: Fetching bio from $lang wiki: $uri');
      
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pages = data['query']?['pages'];
        if (pages != null && pages is Map && pages.isNotEmpty) {
          final pageId = pages.keys.first;
          if (pageId != "-1") {
            return pages[pageId]['extract'];
          }
        }
      }
    } catch (e) {
      print('InfoService: Error fetching wiki bio ($lang): $e');
    }
    return null;
  }

  // --- Deezer for Top Tracks ---

  static Future<List<String>> getTopTracks(String artistName) async {
    try {
      // 1. Search for artist to get ID
      final searchUri = Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeComponent(artistName)}&limit=1');
      print('InfoService: Searching Deezer artist: $searchUri');
      
      final searchRes = await http.get(searchUri);
      if (searchRes.statusCode != 200) return [];
      
      final searchData = jsonDecode(searchRes.body);
      if (searchData['data'] == null || (searchData['data'] as List).isEmpty) return [];
      
      final artistId = searchData['data'][0]['id'];
      
      // 2. Get Top Tracks
      final topUri = Uri.parse('https://api.deezer.com/artist/$artistId/top?limit=20'); // Fetch 20 to insure good overlap
      print('InfoService: Fetching Deezer top tracks: $topUri');
      
      final topRes = await http.get(topUri);
      if (topRes.statusCode != 200) return [];
      
      final topData = jsonDecode(topRes.body);
      final tracks = topData['data'] as List?;
      
      if (tracks != null) {
        // Return list of titles
        return tracks.map((t) => t['title'].toString()).toList();
      }
    } catch (e) {
      print('InfoService: Error fetching Deezer top tracks: $e');
    }
    return [];
  }
}
