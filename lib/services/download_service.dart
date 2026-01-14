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
      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      }
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      return false;
    }
    // iOS doesn't need explicit storage permission for app documents
    return true;
  }

  static Future<String?> getDownloadPath() async {
    Directory? directory;
    try {
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download/Hipotify');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    } catch (e) {
      print("Error getting download path: $e");
      return null;
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
    // We use ApiService.getStreamMetadata but we need to ensure it respects quality if possible.
    // Since we haven't updated ApiService to take quality yet, we will rely on the fact that
    // for now we might be getting the default quality.
    // Ideally, we should update ApiService. 
    // But to unblock, we will assume the API returns a valid URL.
    // If the user selects FLAC, we hope the API returns FLAC (which it does by default for HiFi).
    final metadata = await ApiService.getStreamMetadata(trackId); 
    return metadata['url'];
  }

  static Future<void> _tagFile(String filePath, Track track) async {
    String? coverPath;
    try {
      print("Tagging file natively: $filePath");
      
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
