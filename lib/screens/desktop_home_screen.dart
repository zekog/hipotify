import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/hive_service.dart';
import '../widgets/glass_container.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'download_screen.dart';
import '../widgets/desktop_player_bar.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(),
    const LibraryScreen(),
    const DownloadScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final unselectedTextColor = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;
    final glassColor = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background Gradient (only for dark/amoled, or rely on theme)
          // Removing hardcoded dark gradient to respect theme background
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    // Navigation Rail
                    SizedBox(
                      width: 100,
                      child: GlassContainer(
                        blur: 20,
                        opacity: 0.1,
                        color: glassColor,
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            // App Logo or Icon
                            Icon(Icons.music_note, color: textColor, size: 40),
                            const SizedBox(height: 40),
                            Expanded(
                              child: NavigationRail(
                                backgroundColor: Colors.transparent,
                                selectedIndex: _selectedIndex,
                                onDestinationSelected: (int index) {
                                  setState(() {
                                    _selectedIndex = index;
                                  });
                                },
                                labelType: NavigationRailLabelType.all,
                                selectedLabelTextStyle: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                unselectedLabelTextStyle: TextStyle(
                                  color: unselectedTextColor,
                                  fontSize: 12,
                                ),
                                selectedIconTheme: IconThemeData(color: textColor, size: 28),
                                unselectedIconTheme: IconThemeData(color: unselectedTextColor, size: 24),
                                destinations: const [
                                  NavigationRailDestination(
                                    icon: Icon(Icons.home_filled),
                                    label: Text('Home'),
                                  ),
                                  NavigationRailDestination(
                                    icon: Icon(Icons.search),
                                    label: Text('Search'),
                                  ),
                                  NavigationRailDestination(
                                    icon: Icon(Icons.library_music),
                                    label: Text('Library'),
                                  ),
                                  NavigationRailDestination(
                                    icon: Icon(Icons.download),
                                    label: Text('Downloads'),
                                  ),
                                  NavigationRailDestination(
                                    icon: Icon(Icons.settings),
                                    label: Text('Settings'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Main Content Area
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                        child: GlassContainer(
                          blur: 10,
                          opacity: 0.05,
                          borderRadius: BorderRadius.circular(24),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: IndexedStack(
                              index: _selectedIndex,
                              children: _screens,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Player Bar
              const DesktopPlayerBar(),
            ],
          ),
        ],
      ),
    );
  }
}
