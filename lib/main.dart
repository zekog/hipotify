import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'services/hive_service.dart';
import 'providers/player_provider.dart';
import 'providers/library_provider.dart';
import 'screens/main_screen.dart';
import 'widgets/mini_player.dart';
import 'package:receive_intent/receive_intent.dart';
import 'screens/player_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.audioservice.notification',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  
  try {
    await HiveService.init();
  } catch (e) {
    print("Initialization error: $e");
  }

  runApp(const MyApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

  Future<void> _initIntentListener() async {
    try {
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
            home: const MainScreen(),
            builder: (context, child) {
              return Stack(
                children: [
                  if (child != null) child,
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom, 
                    child: MiniPlayer(),
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
