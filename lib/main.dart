import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:tp6/services/local_storage_service.dart';
import 'package:tp6/services/notification_service.dart';
import 'package:tp6/services/sync_service.dart';
import 'package:tp6/services/theme_service.dart';
import 'package:tp6/screens/auth_screen.dart';
import 'package:tp6/screens/home_screen.dart';
import 'package:tp6/screens/profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDuFWx7z-msIZOMACnseSjPq2AABlWQd50", //current key
      appId: "1:589580880782:android:0d688730ecb17444f2f2df", //mobilesdk app id
      messagingSenderId: "589580880782", // project number
      projectId: "tp-6-81242", //project id
    ),
  );
  // init local storage, notifications and sync
  await LocalStorageService().init();
  await NotificationService().init();
  await NotificationService().requestPermissions();
  SyncService().start();

  runApp(
    ChangeNotifierProvider(create: (_) => ThemeService(), child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const AuthGate(),
          routes: {
            '/login': (context) => const AuthScreen(),
            '/home': (context) => const HomePage(),
            '/profile': (context) => const ProfileScreen(),
          },
          theme: themeService.lightTheme,
          darkTheme: themeService.darkTheme,
          themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        );
      },
    );
  }
}

/// Shows [HomePage] when user is signed in, otherwise shows [AuthScreen].
/// Also triggers a pull-and-merge on sign-in so local data is up-to-date.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _handledUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user != null) {
          // When a new user appears, pull remote data and merge locally once.
          if (_handledUid != user.uid) {
            _handledUid = user.uid;
            // run asynchronously after build to avoid re-entrancy
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await SyncService().pullAndMergeForCurrentUser();
              // reload local habits to schedule notifications
              final local = LocalStorageService();
              await local.init();
              // load habits which will run missed checks and persist them
              await local.getHabitsForUser(user.uid);
            });
          }
          return const HomePage();
        }
        return const AuthScreen();
      },
    );
  }
}
