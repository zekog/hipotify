import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
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
  
  try {
    print("Main: Initializing Hive...");
    await HiveService.init();
    print("Main: Hive initialized.");
  } catch (e) {
    print("Initialization error (Hive): $e");
  }

  print("Main: Running App...");
  runApp(const MyApp());
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
                        height: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom,
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
  const MyApp({super.key});

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
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
      ],
      child: ValueListenableBuilder<bool>(
        valueListenable: HiveService.amoledModeNotifier,
        builder: (context, amoledMode, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [playerObserver],
            title: 'Hipotify',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: amoledMode ? Colors.black : const Color(0xFF121212),
              primaryColor: const Color(0xFF1DB954),
              colorScheme: ColorScheme.dark(
                primary: const Color(0xFF1DB954),
                secondary: const Color(0xFF1DB954),
                surface: amoledMode ? Colors.black : const Color(0xFF121212),
                background: amoledMode ? Colors.black : const Color(0xFF121212),
              ),
              bottomNavigationBarTheme: BottomNavigationBarThemeData(
                backgroundColor: amoledMode ? Colors.black : const Color(0xFF121212),
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.grey,
                type: BottomNavigationBarType.fixed,
              ),
              textTheme: GoogleFonts.montserratTextTheme(
                Theme.of(context).textTheme.apply(
                  bodyColor: Colors.white,
                  displayColor: Colors.white,
                ),
              ),
              useMaterial3: true,
            ),
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
      ),
    );
  }
}
