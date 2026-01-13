import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/download_service.dart';
import '../services/api_service.dart';
import '../models/track.dart';
import '../models/album.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  bool _isDownloading = false;
  String _statusMessage = "";
  double _progress = 0.0;

  Future<String?> _showQualitySelectionDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Select Quality"),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'HI_RES_LOSSLESS'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text("FLAC (Hi-Res Lossless)"),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'LOSSLESS'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text("FLAC (Lossless)"),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'HIGH'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text("AAC (High Quality)"),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'LOW'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text("AAC (Low Quality)"),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCurrentTrack(Track track) async {
    final quality = await _showQualitySelectionDialog();
    if (quality == null) return;

    setState(() {
      _isDownloading = true;
      _statusMessage = "Downloading ${track.title} ($quality)...";
      _progress = 0.0;
    });

    try {
      await DownloadService.downloadTrack(
        track,
        quality: quality,
        onProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Complete!")));
        setState(() => _statusMessage = "Download Complete");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _statusMessage = "Error: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _downloadAlbumZip() async {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final currentTrack = player.currentTrack;
    
    if (currentTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No track playing")));
      return;
    }

    final quality = await _showQualitySelectionDialog();
    if (quality == null) return;

    setState(() {
      _isDownloading = true;
      _statusMessage = "Fetching Album Details...";
      _progress = 0.0;
    });

    try {
      // 1. Fetch Album Details (for title/cover)
      final album = await ApiService.getAlbumDetails(currentTrack.albumId);
      
      // 2. Fetch Album Tracks (full list)
      setState(() => _statusMessage = "Fetching Track List...");
      final tracks = await ApiService.getAlbumTracks(currentTrack.albumId);

      if (tracks.isEmpty) {
        throw Exception("No tracks found for this album");
      }

      setState(() => _statusMessage = "Zipping Album ($quality)...");

      await DownloadService.downloadAlbumZip(
        album,
        tracks,
        quality: quality,
        onProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloaded ${album.title} Complete!")));
        setState(() => _statusMessage = "Album Download Complete");
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _statusMessage = "Error: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerProvider>(context);
    final track = player.currentTrack;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Download", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.1),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              if (track != null) ...[
                // Album Art Card
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      track.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.music_note, size: 80, color: Colors.white54),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Track Info
                Text(
                  track.title,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  track.artistName,
                  style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.7)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Action Buttons
                _buildDownloadButton(
                  icon: Icons.download_rounded,
                  label: "Download Track",
                  onPressed: _isDownloading ? null : () => _downloadCurrentTrack(track),
                  isPrimary: true,
                ),
                const SizedBox(height: 16),
                _buildDownloadButton(
                  icon: Icons.folder_zip_rounded,
                  label: "Download Album ZIP",
                  onPressed: _isDownloading ? null : () => _downloadAlbumZip(),
                  isPrimary: false,
                ),
              ] else ...[
                Icon(Icons.cloud_download_outlined, size: 100, color: Colors.white.withOpacity(0.2)),
                const SizedBox(height: 24),
                Text(
                  "No Track Playing",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5)),
                ),
                const SizedBox(height: 8),
                Text(
                  "Play a song to see download options",
                  style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.3)),
                ),
              ],
              
              if (_isDownloading) ...[
                const SizedBox(height: 40),
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Theme.of(context).primaryColor : Colors.white.withOpacity(0.1),
          foregroundColor: Colors.white,
          elevation: isPrimary ? 4 : 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          disabledBackgroundColor: Colors.white.withOpacity(0.05),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
