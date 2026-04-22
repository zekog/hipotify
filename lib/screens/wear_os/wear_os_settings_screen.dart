import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/hive_service.dart';
import '../../widgets/responsive_layout.dart';
import '../account_screen.dart';
import '../settings/connect_settings_screen.dart';
import '../../services/auth_service.dart';
import '../../widgets/rotary_scroll_wrapper.dart';

/// Wear OS optimized settings screen
class WearOsSettingsScreen extends StatefulWidget {
  const WearOsSettingsScreen({super.key});

  @override
  State<WearOsSettingsScreen> createState() => _WearOsSettingsScreenState();
}

class _WearOsSettingsScreenState extends State<WearOsSettingsScreen> {
  final ScrollController _scrollController = ScrollController();
  final _apiUrlController = TextEditingController();
  String _selectedQuality = 'LOSSLESS';
  String _selectedTheme = 'dark';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showClearDataDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WearOsClearDataConfirmScreen(
          onCleared: () async {
            await HiveService.clearAll();
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All data cleared.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  void _showThemePicker() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WearOsThemePickerScreen(
          currentTheme: _selectedTheme,
          onThemeSelected: (val) {
            setState(() => _selectedTheme = val);
            _saveSettings();
          },
        ),
      ),
    );
  }

  void _showQualityPicker() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WearOsQualityPickerScreen(
          currentQuality: _selectedQuality,
          onQualitySelected: (val) {
            setState(() => _selectedQuality = val);
            _saveSettings();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RotaryScrollWrapper(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(
              vertical: 40,
              horizontal: WearOsConstants.defaultPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: WearOsConstants.headlineSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: WearOsConstants.defaultPadding),

                // Account section
                _SettingTile(
                  icon: Icons.person_outline,
                  title: 'Account',
                  subtitle: AuthService.isLoggedIn
                      ? (AuthService.currentUser?.email ?? 'Logged In')
                      : 'Login/Register',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    );
                  },
                ),

                const Divider(height: 32, color: Colors.white24),

                // Hipotify Connect
                _SettingTile(
                  icon: Icons.cast_connected,
                  title: 'Hipotify Connect',
                  subtitle: 'Control other devices',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ConnectSettingsScreen()),
                    );
                  },
                ),

                const Divider(height: 32, color: Colors.white24),

                // API URL
                const Text(
                  'API Configuration',
                  style: TextStyle(
                    fontSize: WearOsConstants.captionSize,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: WearOsConstants.smallPadding),
                TextField(
                  controller: _apiUrlController,
                  style: const TextStyle(fontSize: WearOsConstants.bodySize),
                  decoration: InputDecoration(
                    hintText: 'https://api.example.com',
                    hintStyle: TextStyle(
                      fontSize: WearOsConstants.bodySize,
                      color: Colors.white.withOpacity(0.4),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: WearOsConstants.defaultPadding,
                      vertical: WearOsConstants.smallPadding,
                    ),
                  ),
                  onSubmitted: (_) => _saveSettings(),
                ),

                const Divider(height: 32, color: Colors.white24),

                // Quality
                _SettingTile(
                  icon: Icons.high_quality,
                  title: 'Audio Quality',
                  subtitle: _getQualityLabel(_selectedQuality),
                  onTap: _showQualityPicker,
                ),

                const Divider(height: 32, color: Colors.white24),

                // Theme
                _SettingTile(
                  icon: Icons.palette,
                  title: 'Theme',
                  subtitle: _getThemeLabel(_selectedTheme),
                  onTap: _showThemePicker,
                ),

                const Divider(height: 32, color: Colors.white24),

                // Clear data
                GestureDetector(
                  onTap: _showClearDataDialog,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(WearOsConstants.defaultPadding),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline,
                            color: Colors.red[400], size: 20),
                        const SizedBox(width: WearOsConstants.smallPadding),
                        Text(
                          'Clear Data',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontSize: WearOsConstants.bodySize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: WearOsConstants.largePadding),

                // Version info
                Center(
                  child: Text(
                    'Hipotify v1.0.0',
                    style: TextStyle(
                      fontSize: WearOsConstants.captionSize,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getQualityLabel(String quality) {
    switch (quality) {
      case 'HI_RES_LOSSLESS': return 'Hi-Res Lossless';
      case 'LOSSLESS': return 'Lossless';
      case 'HIGH': return 'High';
      case 'LOW': return 'Low';
      default: return quality;
    }
  }

  String _getThemeLabel(String theme) {
    switch (theme) {
      case 'dark': return 'Dark';
      case 'amoled': return 'AMOLED';
      case 'monet': return 'Monet';
      case 'catppuccin_mocha': return 'Mocha';
      case 'catppuccin_frappe': return 'Frappé';
      case 'catppuccin_macchiato': return 'Macchiato';
      case 'catppuccin_latte': return 'Latte';
      default: return theme;
    }
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: Theme.of(context).primaryColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: WearOsConstants.bodySize),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: WearOsConstants.captionSize,
                color: Colors.white.withOpacity(0.6),
              ),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.white54),
      onTap: onTap,
    );
  }
}

// ----------------------------------------------------------------------
// Pełnoekranowe Widoki (zamiast Bottom Sheet i Dialogów)
// ----------------------------------------------------------------------

class _WearOsThemePickerScreen extends StatelessWidget {
  final String currentTheme;
  final Function(String) onThemeSelected;

  const _WearOsThemePickerScreen({
    required this.currentTheme,
    required this.onThemeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final themes = [
      _ThemeOption('dark', 'Dark', Colors.grey),
      _ThemeOption('amoled', 'AMOLED', Colors.black),
      _ThemeOption('monet', 'Monet', Colors.blue),
      _ThemeOption('catppuccin_mocha', 'Mocha', const Color(0xFFcba6f7)),
      _ThemeOption('catppuccin_frappe', 'Frappe', const Color(0xFFca9ee6)),
      _ThemeOption('catppuccin_macchiato', 'Macchiato', const Color(0xFFc6a0f6)),
      _ThemeOption('catppuccin_latte', 'Latte', const Color(0xFF8839ef)),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RotaryScrollWrapper(
          controller: ScrollController(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              vertical: 40,
              horizontal: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Theme',
                  style: TextStyle(
                    fontSize: WearOsConstants.titleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: WearOsConstants.defaultPadding),
                ...themes.map((theme) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: theme.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      title: Text(theme.label),
                      trailing: currentTheme == theme.value
                          ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                          : null,
                      onTap: () {
                        onThemeSelected(theme.value);
                        Navigator.pop(context);
                      },
                    )),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WearOsQualityPickerScreen extends StatelessWidget {
  final String currentQuality;
  final Function(String) onQualitySelected;

  const _WearOsQualityPickerScreen({
    required this.currentQuality,
    required this.onQualitySelected,
  });

  @override
  Widget build(BuildContext context) {
    final qualities = [
      _QualityOption('HI_RES_LOSSLESS', 'Hi-Res Lossless', 'Best quality'),
      _QualityOption('LOSSLESS', 'Lossless', 'CD quality'),
      _QualityOption('HIGH', 'High', 'Compressed'),
      _QualityOption('LOW', 'Low', 'Data saver'),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RotaryScrollWrapper(
          controller: ScrollController(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              vertical: 40,
              horizontal: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Audio Quality',
                  style: TextStyle(
                    fontSize: WearOsConstants.titleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: WearOsConstants.defaultPadding),
                ...qualities.map((quality) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(quality.label),
                      subtitle: Text(
                        quality.description,
                        style: TextStyle(
                          fontSize: WearOsConstants.captionSize,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      trailing: currentQuality == quality.value
                          ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                          : null,
                      onTap: () {
                        onQualitySelected(quality.value);
                        Navigator.pop(context);
                      },
                    )),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WearOsClearDataConfirmScreen extends StatelessWidget {
  final VoidCallback onCleared;

  const _WearOsClearDataConfirmScreen({required this.onCleared});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'Clear All Data?',
                  style: TextStyle(fontSize: WearOsConstants.titleSize, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This resets settings, likes, and downloads.',
                  style: TextStyle(fontSize: WearOsConstants.captionSize, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                  onPressed: onCleared,
                  child: const Text('YES, CLEAR', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeOption {
  final String value;
  final String label;
  final Color color;

  _ThemeOption(this.value, this.label, this.color);
}

class _QualityOption {
  final String value;
  final String label;
  final String description;

  _QualityOption(this.value, this.label, this.description);
}
