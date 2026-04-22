import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import '../models/track.dart';
import '../models/album.dart';
import 'api_service.dart';
import 'hive_service.dart';

class DownloadService {
  static final Dio _dio = Dio();

  static Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      try {
        // Wear OS and some Android versions might not support the MANAGE_EXTERNAL_STORAGE intent,
        // causing an ActivityNotFoundException.
        if (await Permission.manageExternalStorage.request().isGranted) {
          return true;
        }
      } catch (e) {
        print("DownloadService: manageExternalStorage request failed (common on Wear OS): $e");
      }
      
      // Fallback to standard storage permissions
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      
      // On Android 13+ (Wear OS 4), standard storage permission might return denied 
      // even if we can write to some scoped locations. We return true and let 
      // the actual file operation decide if it has access.
      return true;
    }
    // iOS doesn't need explicit storage permission for app documents
    return true;
  }

  static Future<String?> getDownloadPath() async {
    Directory? directory;
    try {
      if (Platform.isAndroid) {
        // 1. Try public Downloads folder
        directory = Directory('/storage/emulated/0/Download/Hipotify');
        
        bool canWrite = false;
        try {
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }
          // Verify write access for Scoped Storage
          final testFile = File("${directory.path}/.test_write");
          await testFile.writeAsString("test");
          await testFile.delete();
          canWrite = true;
        } catch (e) {
          print("DownloadService: Public Download folder not accessible ($e). Falling back to app-specific storage.");
          canWrite = false;
        }

        if (!canWrite) {
          // 2. Fallback to app-specific external storage
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            directory = Directory('${externalDir.path}/HipotifyDownloads');
          } else {
            // 3. Fallback to app documents
            directory = await getApplicationDocumentsDirectory();
          }
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
 
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    } catch (e) {
      print("Error getting download path: $e");
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    }
  }

  static String sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String getExtensionForQuality(String quality) {
    switch (quality) {
      case 'LOW':
      case 'HIGH':
        return 'm4a';
      default:
        return 'flac';
    }
  }

  static const MethodChannel _channel = MethodChannel('com.example.hipotify/media_scanner');
  static const MethodChannel _metadataChannel = MethodChannel('com.example.hipotify/metadata');

  static Future<void> _scanFile(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
      print("MediaScanner invoked for: $path");
    } catch (e) {
      print("MediaScanner error: $e");
    }
  }

  static Future<void> downloadTrack(Track track, {String quality = 'HI_RES_LOSSLESS', Function(int, int)? onProgress}) async {
    try {
      if (!await requestPermission()) {
        throw Exception("Permission denied");
      }

      final downloadPath = await getDownloadPath();
      if (downloadPath == null) throw Exception("Could not get download path");

      print("DownloadService: Fetching metadata for track ${track.id} (Quality: $quality)...");
      
      final url = await _getStreamUrlWithQuality(track.id, quality);
      
      if (url == null || url.isEmpty) {
        throw Exception("No download URL found");
      }

      final extension = getExtensionForQuality(quality);
      final fileName = "${sanitizeFilename(track.artistName)} - ${sanitizeFilename(track.title)}.$extension";
      final savePath = "$downloadPath/$fileName";

      await _downloadWithRetry(url, savePath, onProgress: onProgress);

      // Verify file existence
      final file = File(savePath);
      if (await file.exists()) {
        final size = await file.length();
        print("VERIFICATION: File exists at $savePath with size $size bytes");
        if (size == 0) {
           print("WARNING: File size is 0 bytes!");
        }
      } else {
        print("VERIFICATION: File DOES NOT EXIST at $savePath");
        throw Exception("File verification failed: File not found after download");
      }

      // Tag file with metadata
      await _tagFile(savePath, track);
      
      // Register in Hive as downloaded
      await HiveService.saveDownload(track, savePath);
      
      // Scan file so it appears in gallery/downloads with metadata
      await _scanFile(savePath);
      
      print("Downloaded and tagged to: $savePath");
    } catch (e) {
      print("Download error: $e");
      rethrow;
    }
  }

  static Future<String?> _getStreamUrlWithQuality(String trackId, String quality) async {
    // 1. Try requested quality
    final metadata = await ApiService.getStreamMetadata(trackId, quality: quality); 
    String? url = metadata['url'];
    
    // 2. DASH Fallback Logic:
    // If the URL is a DASH manifest (data: URI), we can't download it as a single file.
    // Fallback to HIGH (which is almost always a direct M4A/AAC link)
    if (url != null && url.startsWith('data:')) {
      print("DownloadService: Quality $quality returned DASH manifest. Falling back to HIGH for download.");
      final fallbackMetadata = await ApiService.getStreamMetadata(trackId, quality: 'HIGH');
      url = fallbackMetadata['url'];
    }
    
    return url;
  }

  static Future<void> _tagFile(String filePath, Track track) async {
    String? coverPath;
    try {
      print("Tagging file natively: $filePath");
      
      final file = File(filePath);
      if (!await file.exists()) {
        print("Tagging Error: File not found at $filePath");
        return;
      }
      
      // Basic sanity check: ensure it's not an XML manifest
      final head = await file.openRead(0, 100).first;
      final headStr = String.fromCharCodes(head);
      if (headStr.contains('<?xml') || headStr.contains('<MPD')) {
        print("Tagging Error: Downloaded file appears to be an XML manifest, not audio. Skipping tagging.");
        return;
      }
      if (track.coverUrl.isNotEmpty) {
        // Download cover art to temp file
        final tempDir = await getTemporaryDirectory();
        coverPath = "${tempDir.path}/cover_${track.id}.jpg";
        
        print("Downloading cover art for tagging: ${track.coverUrl}");
        await _dio.download(track.coverUrl, coverPath);
        
        final coverFile = File(coverPath);
        if (await coverFile.exists() && await coverFile.length() > 0) {
          print("Cover art downloaded successfully: $coverPath (${await coverFile.length()} bytes)");
        } else {
          print("Cover art download failed or empty: $coverPath");
          coverPath = null;
        }
      } else {
        print("No cover URL for track: ${track.id}");
      }
      
      if (Platform.isAndroid) {
        await _metadataChannel.invokeMethod('tagFile', {
          'path': filePath,
          'title': track.title,
          'artist': track.artistName,
          'album': track.albumTitle,
          'trackNumber': track.trackNumber,
          'releaseDate': track.releaseDate,
          'coverPath': coverPath,
        });
      } else if (Platform.isIOS) {
        // iOS metadata tagging skipped - audiotags has linker issues in CI
        print("iOS: Skipping metadata tagging (not supported in this build)");
      }

      print("Successfully tagged natively: ${track.title}");
      
    } catch (e) {
      print("Error during native tagging: $e");
    } finally {
      // Cleanup temp cover
      if (coverPath != null) {
        try {
          final coverFile = File(coverPath);
          if (await coverFile.exists()) await coverFile.delete();
        } catch (e) {
          print("Error cleaning up temp cover: $e");
        }
      }
    }
  }

  static Future<void> _downloadWithRetry(String url, String savePath, {Function(int, int)? onProgress}) async {
    int attempts = 0;
    while (attempts < 3) {
      try {
        await _dio.download(url, savePath, onReceiveProgress: onProgress);
        return;
      } catch (e) {
        attempts++;
        print("Download attempt $attempts failed: $e");
        if (attempts >= 3) rethrow;
        await Future.delayed(Duration(seconds: 1 * attempts));
      }
    }
  }

  static Future<void> downloadAlbumZip(Album album, List<Track> tracks, {String quality = 'HI_RES_LOSSLESS', Function(int, int)? onProgress}) async {
    try {
      if (!await requestPermission()) throw Exception("Permission denied");
      final downloadPath = await getDownloadPath();
      if (downloadPath == null) throw Exception("Could not get download path");

      final archive = Archive();
      int totalBytes = tracks.length * 100; 
      int processedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final albumDir = Directory('${tempDir.path}/${sanitizeFilename(album.title)}');
      if (!await albumDir.exists()) await albumDir.create();

      final extension = getExtensionForQuality(quality);

      for (var i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        try {
           final url = await _getStreamUrlWithQuality(track.id, quality);
           if (url != null) {
             final fileName = "${sanitizeFilename(track.artistName)} - ${sanitizeFilename(track.title)}.$extension";
             final savePath = "${albumDir.path}/$fileName";
             await _downloadWithRetry(url, savePath);
             
             // Tag the file before adding to zip
             await _tagFile(savePath, track);
             
             final file = File(savePath);
             final bytes = await file.readAsBytes();
             final archiveFile = ArchiveFile(fileName, bytes.length, bytes);
             archive.addFile(archiveFile);
           }
        } catch (e) {
          print("Failed to download track for zip: ${track.title} - $e");
          final errorLog = "Failed to download: ${track.title}\nError: $e";
          archive.addFile(ArchiveFile("error_${track.id}.txt", errorLog.length, errorLog.codeUnits));
        }

        processedBytes += 100;
        if (onProgress != null) onProgress(processedBytes, totalBytes);
      }

      final zipEncoder = ZipEncoder();
      final zipFile = File('$downloadPath/${sanitizeFilename(album.title)}.zip');
      final encodedZip = zipEncoder.encode(archive);
      if (encodedZip == null) throw Exception("Failed to encode zip");
      
      await zipFile.writeAsBytes(encodedZip);
      await albumDir.delete(recursive: true);
      
      // Verify file existence
      if (await zipFile.exists()) {
        final size = await zipFile.length();
        print("VERIFICATION: Zip file exists at ${zipFile.path} with size $size bytes");
        if (size == 0) {
           print("WARNING: Zip file size is 0 bytes!");
        }
        // Scan file so it appears in gallery/downloads
        await _scanFile(zipFile.path);
      } else {
        print("VERIFICATION: Zip file DOES NOT EXIST at ${zipFile.path}");
        throw Exception("File verification failed: Zip file not found after creation");
      }

      print("Album zipped to: ${zipFile.path}");
      
    } catch (e) {
      print("Album download error: $e");
      rethrow;
    }
  }
}
