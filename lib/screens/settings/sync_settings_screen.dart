import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../services/remote_control_service.dart';
import '../../services/local_network_service.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/rotary_scroll_wrapper.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _scrollController = ScrollController();
  final _remoteService = RemoteControlService();

  bool _syncSession = true;
  bool _syncSettings = true;
  bool _syncLibrary = true;
  bool _syncHistory = false;

  bool _isSyncing = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _performSync() async {
    final targetId = _remoteService.targetDeviceId;
    final target = targetId != null ? LocalNetworkService().getDevice(targetId) : null;
    
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a device first.')),
      );
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final payload = <String, dynamic>{};

      if (_syncSession) {
        payload['session'] = AuthService.currentSession != null 
            ? jsonEncode(AuthService.currentSession!.toJson()) 
            : '';
      }

      if (_syncSettings) {
        payload['settings'] = {
          'apiUrl': HiveService.apiUrl,
          'audioQuality': HiveService.audioQuality,
          'amoledMode': HiveService.amoledMode,
          'themeMode': HiveService.themeMode,
        };
      }

      if (_syncLibrary) {
        payload['playlists'] = HiveService.playlistsBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
        payload['saved_tidal_playlists'] = HiveService.savedTidalPlaylistsBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
        payload['likes'] = HiveService.likesBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      if (_syncHistory) {
        payload['history'] = {
          'tracks': HiveService.historyBox.get('tracks', defaultValue: []),
          'albums': HiveService.historyBox.get('albums', defaultValue: []),
          'artists': HiveService.historyBox.get('artists', defaultValue: []),
        };
      }

      await _remoteService.sendCommand(target.id, 'sync_transfer', payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings Synced Successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileScaffold: _buildScaffold(context, isCompact: false),
      tabletScaffold: _buildScaffold(context, isCompact: false),
      wearOsScaffold: _buildScaffold(context, isCompact: true),
    );
  }

  Widget _buildScaffold(BuildContext context, {required bool isCompact}) {
    final targetId = _remoteService.targetDeviceId;
    final target = targetId != null ? LocalNetworkService().getDevice(targetId) : null;

    Widget content = ListView(
      controller: _scrollController,
      padding: EdgeInsets.all(isCompact ? 16 : 24),
      children: [
        if (!isCompact)
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Text(
              'Super Sync',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
        
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          tileColor: Colors.white.withOpacity(0.05),
          leading: const Icon(Icons.person, color: Colors.blue),
          title: Text('Account Session', style: TextStyle(fontSize: isCompact ? 12 : 16)),
          trailing: Switch(
            value: _syncSession,
            onChanged: (v) => setState(() => _syncSession = v),
          ),
        ),
        SizedBox(height: isCompact ? 8 : 12),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          tileColor: Colors.white.withOpacity(0.05),
          leading: const Icon(Icons.settings, color: Colors.green),
          title: Text('App Settings', style: TextStyle(fontSize: isCompact ? 12 : 16)),
          trailing: Switch(
            value: _syncSettings,
            onChanged: (v) => setState(() => _syncSettings = v),
          ),
        ),
        SizedBox(height: isCompact ? 8 : 12),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          tileColor: Colors.white.withOpacity(0.05),
          leading: const Icon(Icons.library_music, color: Colors.purple),
          title: Text('Playlists & Likes', style: TextStyle(fontSize: isCompact ? 12 : 16)),
          trailing: Switch(
            value: _syncLibrary,
            onChanged: (v) => setState(() => _syncLibrary = v),
          ),
        ),
        SizedBox(height: isCompact ? 8 : 12),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          tileColor: Colors.white.withOpacity(0.05),
          leading: const Icon(Icons.history, color: Colors.orange),
          title: Text('History', style: TextStyle(fontSize: isCompact ? 12 : 16)),
          trailing: Switch(
            value: _syncHistory,
            onChanged: (v) => setState(() => _syncHistory = v),
          ),
        ),
        SizedBox(height: isCompact ? 24 : 32),

        if (target == null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You must be connected to a device to sync settings.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          )
        else
          ElevatedButton(
            onPressed: (_isSyncing || (!_syncSession && !_syncSettings && !_syncLibrary && !_syncHistory)) ? null : _performSync,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isSyncing
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('BLAST TO ${target.name.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
      ],
    );

    if (isCompact) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: RotaryScrollWrapper(controller: _scrollController, child: content),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Super Sync')),
      body: content,
    );
  }
}
