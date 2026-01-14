import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/hive_service.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'download_screen.dart';
import '../widgets/responsive_layout.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Check if API URL is set on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (HiveService.apiUrl == null || HiveService.apiUrl!.isEmpty) {
        _showSetupDialog();
      }
    });
  }

  void _showSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Setup Required"),
        content: const Text("Please configure your API Base URL in Settings to start streaming."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 4); // Switch to Settings tab
            },
            child: const Text("GO TO SETTINGS"),
          ),
        ],
      ),
    );
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(),
    const LibraryScreen(),
    const DownloadScreen(),
    const SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _currentIndex = index);
    // Hide MiniPlayer on Download tab (index 3)
    Provider.of<PlayerProvider>(context, listen: false).setMiniPlayerHidden(index == 3);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileScaffold: _buildMobileScaffold(),
      tvScaffold: _buildTvScaffold(),
    );
  }

  Widget _buildMobileScaffold() {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onItemTapped,
            backgroundColor: Colors.black.withOpacity(0.5),
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Theme.of(context).primaryColor,
            unselectedItemColor: Colors.white.withOpacity(0.5),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
              BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
              BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Download'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvScaffold() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onItemTapped,
            backgroundColor: const Color(0xFF121212),
            selectedIconTheme: IconThemeData(color: Theme.of(context).primaryColor, size: 32),
            unselectedIconTheme: IconThemeData(color: Colors.white.withOpacity(0.5), size: 28),
            labelType: NavigationRailLabelType.all,
            selectedLabelTextStyle: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
            unselectedLabelTextStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            groupAlignment: 0.0, // Center items vertically
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.home_filled), label: Text('Home')),
              NavigationRailDestination(icon: Icon(Icons.search), label: Text('Search')),
              NavigationRailDestination(icon: Icon(Icons.library_music), label: Text('Library')),
              NavigationRailDestination(icon: Icon(Icons.download), label: Text('Download')),
              NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white10),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }
}
