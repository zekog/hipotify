import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/hive_service.dart';
import '../../services/remote_control_service.dart';
import '../../services/auth_service.dart';
import '../../services/local_network_service.dart';
import '../../providers/player_provider.dart';
import '../../widgets/pairing_dialog.dart';
import '../../widgets/rotary_scroll_wrapper.dart';
import '../../widgets/responsive_layout.dart';

class ConnectSettingsScreen extends StatefulWidget {
  const ConnectSettingsScreen({super.key});

  @override
  State<ConnectSettingsScreen> createState() => _ConnectSettingsScreenState();
}

class _ConnectSettingsScreenState extends State<ConnectSettingsScreen> {
  final _remoteService = RemoteControlService();
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isEditingName = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = HiveService.deviceName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _saveName() {
    if (_nameController.text.isNotEmpty) {
      HiveService.setDeviceName(_nameController.text);
      setState(() => _isEditingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<PlayerProvider>(context);
    final isWearOs = ResponsiveLayout.isWearOs(context);

    return Scaffold(
      appBar: isWearOs ? null : AppBar(
        title: const Text('Hipotify Connect'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => showDialog(
              context: context,
              builder: (context) => const PairingDialog(),
            ),
            tooltip: 'Manual QR Connect',
          ),
        ],
      ),
      body: RotaryScrollWrapper(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.all(isWearOs ? 24 : 16).copyWith(
            top: isWearOs ? 40 : 16,
            bottom: isWearOs ? 40 : 16,
          ),
          children: [
            if (isWearOs) ...[
              const Center(
                child: Text(
                  'Connect',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildDeviceStatus(playerProvider, isWearOs),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Available Devices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isWearOs)
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (context) => const PairingDialog(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<dynamic>>(
              stream: LocalNetworkService().discoveredDevicesStream,
              initialData: const [],
              builder: (context, snapshot) {
                final pairedDevices = snapshot.data ?? [];
                
                if (pairedDevices.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.wifi_tethering, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Searching for nearby devices...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                return Column(
                  children: pairedDevices.map((device) => _buildDeviceTile({
                    'id': device.id,
                    'name': device.name,
                    'ip': device.ip,
                    'port': device.port,
                  }, playerProvider)).toList(),
                );
              },
            ),
            const SizedBox(height: 32),
            if (!isWearOs) _buildInfoSection(),
            if (isWearOs) const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }


  Widget _buildDeviceStatus(PlayerProvider playerProvider, bool isWearOs) {
    return Card(
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isWearOs ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phone_android, 
                    color: Theme.of(context).primaryColor,
                    size: isWearOs ? 16 : 24,
                  ),
                ),
                SizedBox(width: isWearOs ? 10 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This Device',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      if (_isEditingName)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nameController,
                                autofocus: true,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: _saveName,
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                                child: Text(
                                  HiveService.deviceName,
                                  style: TextStyle(
                                    fontSize: isWearOs ? 16 : 18, 
                                    fontWeight: FontWeight.bold
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                              onPressed: () => setState(() => _isEditingName = true),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Control Mode',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        playerProvider.isRemoteMode ? 'Remote Control' : 'Local Player',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: isWearOs ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (playerProvider.isRemoteMode)
                  ElevatedButton(
                    onPressed: () => _remoteService.setControlTarget(null),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.1),
                      foregroundColor: Colors.red,
                      elevation: 0,
                      padding: isWearOs ? const EdgeInsets.symmetric(horizontal: 12) : null,
                    ),
                    child: Text(
                      isWearOs ? 'STOP' : 'STOP REMOTE',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(Map<String, dynamic> device, PlayerProvider playerProvider) {
    final isTarget = _remoteService.targetDeviceId == device['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isTarget ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: isTarget ? Border.all(color: Theme.of(context).primaryColor.withOpacity(0.5)) : null,
      ),
      child: ListTile(
        leading: Icon(
          _getDeviceIcon(device['name']),
          color: isTarget ? Theme.of(context).primaryColor : Colors.white70,
        ),
        title: Text(
          device['name'],
          style: TextStyle(
            fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isTarget ? 'Currently Controlling' : 'Ready to Connect',
          style: TextStyle(
            color: isTarget ? Theme.of(context).primaryColor : Colors.grey,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (AuthService.isLoggedIn)
              TextButton.icon(
                icon: const Icon(Icons.sync_lock, size: 18),
                label: const Text('LOGIN', style: TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () {
                  _remoteService.sendLoginSession(device['id']);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Login request sent to device')),
                  );
                },
              ),
            Switch(
              value: isTarget,
              onChanged: (value) {
                if (value) {
                  _remoteService.setControlTarget(device['id']);
                } else {
                  _remoteService.setControlTarget(null);
                }
              },
              activeColor: Theme.of(context).primaryColor,
            ),
          ],
        ),
        onTap: () {
          _remoteService.setControlTarget(isTarget ? null : device['id']);
        },
      ),
    );
  }

  IconData _getDeviceIcon(String name) {
    name = name.toLowerCase();
    if (name.contains('watch') || name.contains('wear')) return Icons.watch;
    if (name.contains('pc') || name.contains('computer') || name.contains('desktop') || name.contains('laptop')) return Icons.desktop_windows;
    return Icons.phone_android;
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.1)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hipotify Connect allows you to use this device as a remote control for your other paired devices. When active, playback commands will be sent to the selected device.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
