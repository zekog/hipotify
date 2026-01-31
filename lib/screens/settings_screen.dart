import 'package:flutter/material.dart';
import '../services/hive_service.dart';
import '../utils/snackbar_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiUrlController = TextEditingController();
  String _selectedQuality = 'LOSSLESS';
  String _selectedTheme = 'dark';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _apiUrlController.text = HiveService.apiUrl ?? '';
      _selectedQuality = HiveService.audioQuality;
      _selectedTheme = HiveService.themeMode;
    });
  }

  Future<void> _saveSettings() async {
    await HiveService.setApiUrl(_apiUrlController.text);
    await HiveService.setAudioQuality(_selectedQuality);
    await HiveService.setThemeMode(_selectedTheme);
    // Backward compatibility if needed, otherwise we can ignore amoledMode legacy
    if (_selectedTheme == 'amoled') {
       await HiveService.setAmoledMode(true);
    } else {
       await HiveService.setAmoledMode(false);
    }
    if (mounted) {
      showSnackBar(context, 'Settings Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FocusScope(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text('API Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _apiUrlController,
              textInputAction: TextInputAction.next, // Move to next field on Enter
              onSubmitted: (_) => FocusScope.of(context).nextFocus(), // Explicitly move focus
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'https://triton.squid.wtf',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Audio Quality', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedQuality,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'HI_RES_LOSSLESS', child: Text('Hi-Res Lossless')),
                DropdownMenuItem(value: 'LOSSLESS', child: Text('Lossless')),
                DropdownMenuItem(value: 'HIGH', child: Text('High')),
                DropdownMenuItem(value: 'LOW', child: Text('Low')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedQuality = value);
                }
              },
            ),
            const SizedBox(height: 20),
            const Text('Appearance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedTheme,
              decoration: const InputDecoration(
                labelText: 'Theme',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'dark', child: Text('Dark Grey (Default)')),
                DropdownMenuItem(value: 'amoled', child: Text('Amoled Black')),
                DropdownMenuItem(value: 'monet', child: Text('Monet (Dynamic Color)')),
                DropdownMenuItem(value: 'catppuccin_latte', child: Text('Catppuccin 🌻 Latte')),
                DropdownMenuItem(value: 'catppuccin_frappe', child: Text('Catppuccin 🪴 Frappé')),
                DropdownMenuItem(value: 'catppuccin_macchiato', child: Text('Catppuccin 🌺 Macchiato')),
                DropdownMenuItem(value: 'catppuccin_mocha', child: Text('Catppuccin 🌿 Mocha')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedTheme = value);
                }
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('SAVE SETTINGS', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Clear All Data?"),
                      content: const Text("This will reset your settings, likes, and downloads."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("CLEAR", style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await HiveService.clearAll();
                    showSnackBar(context, "All data cleared. Restart app.");
                  }
                },
                child: const Text("CLEAR ALL DATA & CACHE"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
