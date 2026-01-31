import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/hive_service.dart';
import 'providers/player_provider.dart';
import 'providers/library_provider.dart';
import 'screens/main_screen.dart';
import 'widgets/mini_player.dart';
import 'package:receive_intent/receive_intent.dart';
import 'screens/player_screen.dart';
import 'screens/desktop_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("Main: Initializing...");
  
  String? initError;

  try {
    // Lock orientation to portrait only on mobile
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    
    print("Main: Initializing JustAudioMediaKit...");
    JustAudioMediaKit.ensureInitialized();

    if (Platform.isAndroid || Platform.isIOS) {
      print("Main: Initializing JustAudioBackground...");
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.ryanheise.audioservice.notification',
        androidNotificationChannelName: 'Audio playback',
        androidNotificationOngoing: true,
      );
    }
    
    print("Main: Initializing Hive...");
    await HiveService.init();
    print("Main: Hive initialized.");
  } catch (e) {
    print("Initialization error: $e");
    initError = e.toString();
  }

  print("Main: Running App...");
  runApp(MyApp(initError: initError));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey miniPlayerKey = GlobalKey();

// Global bottom navigation bar state
class BottomNavBarState {
  static final ValueNotifier<int> currentIndex = ValueNotifier<int>(0);
  
  static void navigateToMainScreen(BuildContext context, int index) {
    currentIndex.value = index;
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainScreen(initialIndex: index)),
      (route) => false,
    );
  }
}

class MiniPlayerVisibilityObserver extends NavigatorObserver {
  static final ValueNotifier<bool> isPlayerVisible = ValueNotifier(false);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateVisibility(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _updateVisibility(previousRoute);
    }
  }

  void _updateVisibility(Route<dynamic> topRoute) {
    // Hide mini player if we are on PlayerScreen
    isPlayerVisible.value = topRoute.settings.name == 'PlayerScreen';
  }
}

final MiniPlayerVisibilityObserver playerObserver = MiniPlayerVisibilityObserver();

// Global bottom navigation bar widget
class _GlobalBottomNavBar extends StatefulWidget {
  @override
  State<_GlobalBottomNavBar> createState() => _GlobalBottomNavBarState();
}

class _GlobalBottomNavBarState extends State<_GlobalBottomNavBar> {
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createOverlay();
    });
  }

  void _createOverlay() {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<bool>(
        valueListenable: MiniPlayerVisibilityObserver.isPlayerVisible,
        builder: (context, isPlayerVisible, _) {
          if (isPlayerVisible) {
            return const SizedBox.shrink(); // Hide on PlayerScreen
          }
          
          return Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: BottomNavBarState.currentIndex,
              builder: (context, currentIndex, _) {
                return Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                        ),
                        child: SafeArea(
                          top: false,
                          child: BottomNavigationBar(
                            currentIndex: currentIndex,
                            onTap: (index) {
                              BottomNavBarState.currentIndex.value = index;
                              navigatorKey.currentState?.pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => MainScreen(initialIndex: index),
                                ),
                                (route) => route.settings.name == 'PlayerScreen' ? true : false,
                              );
                            },
                            backgroundColor: Colors.transparent,
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
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // This widget doesn't render anything itself
  }
}

class MyApp extends StatefulWidget {
  final String? initError;
  const MyApp({super.key, this.initError});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initIntentListener();
  }

  @override
  void dispose() {
    // Reset orientation preferences when app is disposed
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _initIntentListener() async {
    if (!Platform.isAndroid) return;
    
    try {
      print("MyApp: Initializing Intent Listener...");
      // Check initial intent
      final initialIntent = await ReceiveIntent.getInitialIntent();
      if (initialIntent != null && initialIntent.action == 'com.ryanheise.audioservice.NOTIFICATION_CLICK') {
        _navigateToPlayer();
      }

      // Listen for new intents
      ReceiveIntent.receivedIntentStream.listen((intent) {
        if (intent?.action == 'com.ryanheise.audioservice.NOTIFICATION_CLICK') {
          _navigateToPlayer();
        }
      });
    } catch (e) {
      print("Error listening to intents: $e");
    }
  }

  void _navigateToPlayer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MiniPlayerVisibilityObserver.isPlayerVisible.value) return;

      navigatorKey.currentState?.push(
        PageRouteBuilder(
          settings: const RouteSettings(name: 'PlayerScreen'),
          pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeOutCubic;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initError != null) {
      return MaterialApp(
        title: 'Hipotify',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF121212),
          useMaterial3: true,
        ),
        home: InitializationErrorScreen(error: widget.initError!),
      );
    }

    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
      ],
       child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return ValueListenableBuilder<String>(
            valueListenable: HiveService.themeModeNotifier,
            builder: (context, themeMode, _) {
              ThemeData themeData;
              
              if (themeMode == 'monet' && darkDynamic != null) {
                 themeData = ThemeData(
                   useMaterial3: true,
                   colorScheme: darkDynamic,
                   brightness: Brightness.dark,
                   scaffoldBackgroundColor: darkDynamic.background,
                 );
              } else if (themeMode == 'catppuccin_mocha') {
                 // Catppuccin Mocha
                 const bg = Color(0xFF1e1e2e);
                 const primary = Color(0xFFcba6f7); // Mauve
                 const secondary = Color(0xFF89b4fa); // Blue
                 const surface = Color(0xFF313244);
                 const text = Color(0xFFcdd6f4);
                 
                 themeData = ThemeData(
                   useMaterial3: true,
                   brightness: Brightness.dark,
                   scaffoldBackgroundColor: bg,
                   primaryColor: primary,
                   cardColor: surface,
                   canvasColor: bg,
                   colorScheme: const ColorScheme.dark(
                     primary: primary,
                     secondary: secondary,
                     tertiary: Color(0xFFf5c2e7), // Pink
                     surface: surface,
                     background: bg,
                     onPrimary: Color(0xFF11111b), // Crust
                     onSecondary: Color(0xFF11111b), // Crust
                     onSurface: text,
                     onBackground: text,
                     error: Color(0xFFf38ba8), // Red
                   ),
                   bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                     backgroundColor: bg,
                     selectedItemColor: primary,
                     unselectedItemColor: Color(0xFFa6adc8), // Subtext0
                   ),
                   textTheme:  TextTheme(
                    bodyLarge: TextStyle(color: text),
                    bodyMedium: TextStyle(color: text), 
                    titleLarge: TextStyle(color: text),
                   ),
                   iconTheme: IconThemeData(color: text),
                 );
              } else if (themeMode == 'catppuccin_frappe') {
                 // Catppuccin Frappe
                 const bg = Color(0xFF303446);
                 const primary = Color(0xFFca9ee6); // Mauve
                 const secondary = Color(0xFF8caaee); // Blue
                 const surface = Color(0xFF414559);
                 const text = Color(0xFFc6d0f5);
                 
                 themeData = ThemeData(
                   useMaterial3: true,
                   brightness: Brightness.dark,
                   scaffoldBackgroundColor: bg,
                   primaryColor: primary,
                   cardColor: surface,
                   canvasColor: bg,
                   colorScheme: const ColorScheme.dark(
                     primary: primary,
                     secondary: secondary,
                     tertiary: Color(0xFFf4b8e4), // Pink
                     surface: surface,
                     background: bg,
                     onPrimary: Color(0xFF232634), // Crust
                     onSecondary: Color(0xFF232634), // Crust
                     onSurface: text,
                     onBackground: text,
                     error: Color(0xFFe78284), // Red
                   ),
                   bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                     backgroundColor: bg,
                     selectedItemColor: primary,
                     unselectedItemColor: Color(0xFFa5adce), // Subtext0
                   ),
                   textTheme:  TextTheme(
                    bodyLarge: TextStyle(color: text),
                    bodyMedium: TextStyle(color: text), 
                    titleLarge: TextStyle(color: text),
                   ),
                   iconTheme: IconThemeData(color: text),
                 );
              } else if (themeMode == 'catppuccin_macchiato') {
                 // Catppuccin Macchiato
                 const bg = Color(0xFF24273a);
                 const primary = Color(0xFFc6a0f6); // Mauve
                 const secondary = Color(0xFF8aadf4); // Blue
                 const surface = Color(0xFF363a4f);
                 const text = Color(0xFFcad3f5);
                 
                 themeData = ThemeData(
                   useMaterial3: true,
                   brightness: Brightness.dark,
                   scaffoldBackgroundColor: bg,
                   primaryColor: primary,
                   cardColor: surface,
                   canvasColor: bg,
                   colorScheme: const ColorScheme.dark(
                     primary: primary,
                     secondary: secondary,
                     tertiary: Color(0xFFf5bde6), // Pink
                     surface: surface,
                     background: bg,
                     onPrimary: Color(0xFF181926), // Crust
                     onSecondary: Color(0xFF181926), // Crust
                     onSurface: text,
                     onBackground: text,
                     error: Color(0xFFed8796), // Red
                   ),
                   bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                     backgroundColor: bg,
                     selectedItemColor: primary,
                     unselectedItemColor: Color(0xFFa5adcb), // Subtext0
                   ),
                   textTheme:  TextTheme(
                    bodyLarge: TextStyle(color: text),
                    bodyMedium: TextStyle(color: text), 
                    titleLarge: TextStyle(color: text),
                   ),
                   iconTheme: IconThemeData(color: text),
                 );
              } else if (themeMode == 'catppuccin_latte') {
                 // Catppuccin Latte
                 const bg = Color(0xFFeff1f5);
                 const primary = Color(0xFF8839ef); // Mauve
                 const secondary = Color(0xFF1e66f5); // Blue
                 const surface = Color(0xFFccd0da);
                 const text = Color(0xFF4c4f69);

                 themeData = ThemeData(
                   useMaterial3: true,
                   brightness: Brightness.light,
                   scaffoldBackgroundColor: bg,
                   primaryColor: primary,
                   cardColor: surface,
                   canvasColor: bg,
                   colorScheme: const ColorScheme.light(
                     primary: primary,
                     secondary: secondary,
                     tertiary: Color(0xFFea76cb), // Pink
                     surface: surface,
                     background: bg,
                     onPrimary: Color(0xFFdce0e8), // Crust
                     onSecondary: Color(0xFFdce0e8), // Crust
                     onSurface: text,
                     onBackground: text,
                     error: Color(0xFFd20f39), // Red
                   ),
                   bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                     backgroundColor: bg,
                     selectedItemColor: primary,
                     unselectedItemColor: Color(0xFF9ca0b0), // Overlay0
                   ),
                   textTheme: GoogleFonts.montserratTextTheme(ThemeData.light().textTheme).apply(
                      bodyColor: text,
                      displayColor: text,
                   ),
                   iconTheme: IconThemeData(color: text),
                 );
              } else if (themeMode == 'amoled') {
                 themeData = ThemeData(
                   brightness: Brightness.dark,
                   scaffoldBackgroundColor: Colors.black,
                   primaryColor: const Color(0xFF1DB954),
                   colorScheme: const ColorScheme.dark(
                     primary: Color(0xFF1DB954),
                     secondary: Color(0xFF1DB954),
                     surface: Colors.black,
                     background: Colors.black,
                   ),
                   bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                     backgroundColor: Colors.black,
                     selectedItemColor: Colors.white,
                     unselectedItemColor: Colors.grey,
                     type: BottomNavigationBarType.fixed,
                   ),
                   useMaterial3: true,
                 );
              } else {
                 // Default Dark
                 themeData = ThemeData(
                   brightness: Brightness.dark,
                   scaffoldBackgroundColor: const Color(0xFF121212),
                   primaryColor: const Color(0xFF1DB954),
                   colorScheme: const ColorScheme.dark(
                     primary: Color(0xFF1DB954),
                     secondary: Color(0xFF1DB954),
                     surface: Color(0xFF121212),
                     background: Color(0xFF121212),
                   ),
                   bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                     backgroundColor: Color(0xFF121212),
                     selectedItemColor: Colors.white,
                     unselectedItemColor: Colors.grey,
                     type: BottomNavigationBarType.fixed,
                   ),
                   useMaterial3: true,
                 );
              }

              // Apply Font (except for Latte which already applied it on light theme base, wait, better to apply consistently)
              if (themeMode != 'catppuccin_latte') {
                 final isCatppuccin = themeMode != null && themeMode.contains('catppuccin');
                 Color? bodyColor;

                 if (themeMode == 'catppuccin_mocha') bodyColor = const Color(0xFFcdd6f4);
                 else if (themeMode == 'catppuccin_frappe') bodyColor = const Color(0xFFc6d0f5);
                 else if (themeMode == 'catppuccin_macchiato') bodyColor = const Color(0xFFcad3f5);
                 else bodyColor = Colors.white;

                themeData = themeData.copyWith(
                  textTheme: GoogleFonts.montserratTextTheme(
                    themeData.textTheme.apply(
                      bodyColor: bodyColor,
                      displayColor: bodyColor,
                    ),
                  ),
                );
              }

              return MaterialApp(
                navigatorKey: navigatorKey,
                navigatorObservers: [playerObserver],
                title: 'Hipotify',
                debugShowCheckedModeBanner: false,
                theme: themeData,
                home: isDesktop ? const DesktopHomeScreen() : const MainScreen(),
                builder: (context, child) {
                  if (isDesktop) {
                    return child!;
                  }
                  return Stack(
                    children: [
                      if (child != null) child,
                      // Global bottom navigation bar using Overlay
                      _GlobalBottomNavBar(),
                      // Mini player - positioned above bottom navigation bar
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom, 
                        child: MiniPlayer(key: miniPlayerKey),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class InitializationErrorScreen extends StatelessWidget {
  final String error;
  const InitializationErrorScreen({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    final isLockError = error.contains('lock failed') || error.contains('errno = 11');

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                "Initialization Failed",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                isLockError 
                  ? "Another instance of Hipotify is already running and using the database.\n\nPlease close all other instances and try again."
                  : "An error occurred during startup:\n$error",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => exit(0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text("CLOSE APP"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
