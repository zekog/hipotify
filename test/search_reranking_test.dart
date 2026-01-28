import 'package:flutter_test/flutter_test.dart';
import 'package:hipotify/models/track.dart';
import 'package:hipotify/models/artist.dart';
import 'package:hipotify/models/album.dart';

void main() {
  group('Search Re-ranking Logic Mock Test', () {
    test('Calculate score based on history and popularity', () {
      // This is a conceptual test since we can't easily mock HiveService in a simple script
      // but we can verify the logic if we were to extract it.
      
      final track1 = Track(
        id: '1',
        title: 'Popular Track',
        artistName: 'Ado',
        artistId: 'ado1',
        albumId: 'album1',
        albumTitle: 'Album 1',
        albumCoverUuid: '',
        popularity: 80,
      );

      final track2 = Track(
        id: '2',
        title: 'Recent Track',
        artistName: 'Other',
        artistId: 'other1',
        albumId: 'album2',
        albumTitle: 'Album 2',
        albumCoverUuid: '',
        popularity: 20,
      );

      // Mocking the logic from ApiService
      double calculateScore(dynamic item, int originalIndex, Set<String> recentTrackIds, Set<String> recentArtistIds, Set<String> recentAlbumIds, String normalizedQuery) {
        double score = 1000.0 / (originalIndex + 1);
        
        String itemId = "";
        String itemTitle = "";
        String itemArtist = "";
        String itemAlbum = "";
        if (item is Track) { 
          itemId = item.id.toString().trim(); 
          itemTitle = item.title; 
          itemArtist = item.artistName;
          itemAlbum = item.albumTitle;
        }
        else if (item is Artist) { 
          itemId = item.id.toString().trim(); 
          itemTitle = item.name; 
        }
        else if (item is Album) { 
          itemId = item.id.toString().trim(); 
          itemTitle = item.title; 
          itemArtist = item.artistName;
        }

        final lowerTitle = itemTitle.toLowerCase();
        final lowerArtist = itemArtist.toLowerCase();
        final lowerAlbum = itemAlbum.toLowerCase();

        // 1. Title Match Bonus
        if (lowerTitle == normalizedQuery) {
          score += 3000.0;
        } else if (lowerTitle.startsWith(normalizedQuery)) {
          score += 1000.0;
        } else if (lowerTitle.contains(normalizedQuery)) {
          score += 500.0;
        }

        // 2. Artist Match Bonus
        if (lowerArtist.isNotEmpty) {
          if (lowerArtist == normalizedQuery) {
            score += 2000.0;
          } else if (lowerArtist.startsWith(normalizedQuery)) {
            score += 1000.0;
          } else if (lowerArtist.contains(normalizedQuery)) {
            score += 500.0;
          }
        }

        // 3. Album Match Bonus
        if (lowerAlbum.isNotEmpty) {
          if (lowerAlbum == normalizedQuery) {
            score += 1500.0;
          } else if (lowerAlbum.startsWith(normalizedQuery)) {
            score += 800.0;
          } else if (lowerAlbum.contains(normalizedQuery)) {
            score += 400.0;
          }
        }

        // 4. Contextual Boost
        if (item is Track || item is Album) {
          if (lowerArtist == normalizedQuery) score += 1000.0;
          if (lowerAlbum == normalizedQuery) score += 500.0;
        }

        // 5. Transliteration Match (Script Match)
        final bool queryIsLatin = RegExp(r'^[a-zA-Z0-9\s\p{P}]+$', unicode: true).hasMatch(normalizedQuery);
        if (queryIsLatin) {
          final bool hasNonLatin = RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]', unicode: true).hasMatch(itemTitle) || 
                                   RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]', unicode: true).hasMatch(itemArtist);
          if (hasNonLatin) {
            score += 2000.0;
          }
        }

        // 6. History & Popularity
        if (item is Track) {
          if (recentTrackIds.contains(itemId)) score += 10000.0;
          else if (recentArtistIds.contains(item.artistId)) score += 3000.0;
          else if (recentAlbumIds.contains(item.albumId)) score += 2000.0;
          score += (item.popularity ?? 0) * 10.0;
        } else if (item is Artist) {
          if (recentArtistIds.contains(itemId)) score += 10000.0;
          score += (item.popularity ?? 0) * 10.0;
        } else if (item is Album) {
          if (recentAlbumIds.contains(itemId)) score += 10000.0;
          else if (recentArtistIds.contains(item.artistId)) score += 3000.0;
          score += (item.popularity ?? 0) * 10.0;
        }
        return score;
      }

      final recentTrackIds = {'2'};
      final recentArtistIds = {'ado1'};
      final recentAlbumIds = <String>{};
      
      // Test 1: History vs Popularity
      final query1 = 'popular';
      final score1 = calculateScore(track1, 0, recentTrackIds, recentArtistIds, recentAlbumIds, query1);
      final score2 = calculateScore(track2, 1, recentTrackIds, recentArtistIds, recentAlbumIds, query1);

      print('Score 1 (Popular, Artist in history, Title match): $score1');
      print('Score 2 (Recent track, No title match): $score2');

      expect(score2 > score1, isTrue, reason: 'Recently played track should have higher score than popular track from history artist');

      // Test 2: Transliteration Match (inabakumori -> 稲葉曇)
      final artistJP = Artist(id: 'jp1', name: '稲葉曇', pictureUuid: '', popularity: 70);
      final artistEN = Artist(id: 'en1', name: 'Some Other Artist', pictureUuid: '', popularity: 80);
      
      final queryJP = 'inabakumori';
      final scoreJP = calculateScore(artistJP, 0, {}, {}, {}, queryJP);
      final scoreEN = calculateScore(artistEN, 1, {}, {}, {}, queryJP);
      
      print('Score JP (Transliteration Match): $scoreJP');
      print('Score EN (No Match): $scoreEN');
      
      expect(scoreJP > scoreEN, isTrue, reason: 'Japanese artist should be boosted for Latin query even if name doesn\'t literally match');
    });
  });
}
