import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import '../services/local_network_service.dart';
import '../services/remote_control_service.dart';
import '../services/auth_service.dart';
import 'rotary_scroll_wrapper.dart';
import 'responsive_layout.dart';

class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key});

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  final _remoteService = RemoteControlService();
  final _scrollController = ScrollController();
  final _pinController = TextEditingController();
  bool _isScanning = false;
  bool _isConnecting = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.startsWith('HIPOTIFY_SYNC|') == false) {
        final parts = code.split('|');
        if (parts.length >= 4) {
          final id = parts[0];
          final name = parts[1];
          final port = int.tryParse(parts[2]);
          final ip = parts[3];

          if (port != null && id.isNotEmpty) {
            LocalNetworkService().addManualDevice(id, name, port, ip);
            setState(() => _isScanning = false);
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Found device $name! You can now select it from the list.')),
              );
              Navigator.pop(context);
            }
            break;
          }
        }
      }
    }
  }

  Future<void> _pairWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;

    setState(() => _isConnecting = true);

    final localIp = LocalNetworkService().localIp;
    if (localIp == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Local IP found on this device. Are you connected to Wi-Fi?')),
        );
        setState(() => _isConnecting = false);
      }
      return;
    }

    // Subnet Auto-Guesser
    // if my IP is 192.168.0.50 and i type 146 -> 192.168.0.146
    final parts = localIp.split('.');
    String targetIp = pin;
    if (!pin.contains('.') && parts.length == 4) {
       targetIp = '${parts[0]}.${parts[1]}.${parts[2]}.$pin';
    }

    final success = await LocalNetworkService().connectToTarget(targetIp, 45456);
    
    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      // Add the device to the manager so it is visible in ConnectSettingsScreen
      LocalNetworkService().addManualDevice(targetIp, 'Manual ($targetIp)', 45456, targetIp);
      _remoteService.setControlTarget(targetIp); // Force UI into Remote mode for this device immediately
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected & remote mode active for $targetIp')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect to IP. Check PIN and ensure app is open.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileScaffold: _buildDialog(context, isCompact: false),
      tabletScaffold: _buildDialog(context, isCompact: false),
      wearOsScaffold: _buildDialog(context, isCompact: true),
    );
  }

  Widget _buildDialog(BuildContext context, {required bool isCompact}) {
    final content = _buildContent(context, isCompact);
    
    if (isCompact) {
      return Material(
        color: const Color(0xFF121212),
        child: RotaryScrollWrapper(
          controller: _scrollController,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
            children: [content],
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: const Color(0xFF1E1E1E),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: SingleChildScrollView(child: content),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isCompact) {
    if (_isScanning) {
      return _buildScannerView(isCompact);
    }

    final localIp = LocalNetworkService().localIp ?? 'Unknown';
    final splitIp = localIp.split('.');
    final myPin = splitIp.length == 4 ? splitIp[3] : localIp;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Connect Device',
          style: TextStyle(
            fontSize: isCompact ? 20 : 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your Smart IP PIN is:',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: isCompact ? 12 : 14),
        ),
        Text(
          myPin,
          style: TextStyle(
            fontSize: isCompact ? 28 : 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 24),
        _buildInputSection(isCompact),
        const SizedBox(height: 24),
        if (!isCompact && (Platform.isAndroid || Platform.isIOS)) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _isScanning = true),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('SCAN OTHER DEVICE'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5)),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildQRCodeSection(isCompact),
      ],
    );
  }

  Widget _buildInputSection(bool isCompact) {
    return Column(
      children: [
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isCompact ? 24 : 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            color: Colors.white,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'PIN...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            counterText: '',
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isConnecting ? null : _pairWithPin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 16),
            ),
            child: _isConnecting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('CONNECT VIA PIN', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildQRCodeSection(bool isCompact) {
    final code = LocalNetworkService().localQrData;
    
    if (code == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      children: [
        const Text(
          'Scan on Phone',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: code,
            version: QrVersions.auto,
            size: isCompact ? 120 : 180,
            gapless: false,
          ),
        ),
      ],
    );
  }

  Widget _buildScannerView(bool isCompact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Scan QR Code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => setState(() => _isScanning = false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Theme.of(context).primaryColor, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: MobileScanner(
            onDetect: _onDetect,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Point your camera at the QR code on your watch.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ],
    );
  }
}
