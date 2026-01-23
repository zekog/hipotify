import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/hive_service.dart';
import '../main.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'download_screen.dart';
import '../widgets/responsive_layout.dart';

class MainScreen extends StatefulWidget {
  final int? initialIndex;
  const MainScreen({super.key, this.initialIndex});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  final GlobalKey<State<SearchScreen>> _searchScreenKey = GlobalKey<State<SearchScreen>>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    // Sync with global bottom nav bar state
    BottomNavBarState.currentIndex.value = _currentIndex;
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

  List<Widget> get _screens => [
    const HomeScreen(),
    SearchScreen(key: _searchScreenKey),
    const LibraryScreen(),
    const DownloadScreen(),
    const SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _currentIndex = index);
    // Sync with global bottom nav bar state
    BottomNavBarState.currentIndex.value = index;
    // Hide MiniPlayer on Download tab (index 3)
    Provider.of<PlayerProvider>(context, listen: false).setMiniPlayerHidden(index == 3);
    
    // Reset SearchScreen to history when navigating to it (index 1)
    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = _searchScreenKey.currentState;
        if (state != null) {
          // Call public method resetToHistory
          (state as dynamic).resetToHistory();
        }
      });
    }
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
      // Bottom navigation bar is now global in MaterialApp builder
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
