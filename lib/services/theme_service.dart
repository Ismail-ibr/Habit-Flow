import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeService extends ChangeNotifier {
  bool _isDarkMode = false;
  static const _settingsBox = 'settings';
  static const _isDarkKey = 'isDarkMode';

  ThemeService() {
    try {
      final box = Hive.box(_settingsBox);
      _isDarkMode = box.get(_isDarkKey, defaultValue: false) as bool;
    } catch (_) {
      // If box isn't open yet or other issues, default to false
      _isDarkMode = false;
    }
  }

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    try {
      final box = Hive.box(_settingsBox);
      box.put(_isDarkKey, _isDarkMode);
    } catch (_) {
      // ignore if box not available
    }
    notifyListeners();
  }

  /// Set theme explicitly and persist it
  void setDarkMode(bool value) {
    _isDarkMode = value;
    try {
      final box = Hive.box(_settingsBox);
      box.put(_isDarkKey, _isDarkMode);
    } catch (_) {}
    notifyListeners();
  }

  ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: Colors.deepPurple,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.purple.shade50,
        foregroundColor: Colors.black87,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.deepPurple,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.deepPurple,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.grey.shade800,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.deepPurple,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      scaffoldBackgroundColor: Colors.grey.shade900,
    );
  }
}
