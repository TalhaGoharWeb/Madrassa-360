/// ذخیرہ کی خدمت
/// Local Storage Service using SharedPreferences

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_handler.dart';

class StorageService {
  static SharedPreferences? _prefs;

  /// Initialize storage
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      throw StorageException('ذخیرہ شروع کرنے میں خرابی');
    }
  }

  /// Save string value
  static Future<void> saveString(String key, String value) async {
    try {
      await _ensureInitialized();
      await _prefs!.setString(key, value);
    } catch (e) {
      throw StorageException('ڈیٹا محفوظ کرنے میں خرابی');
    }
  }

  /// Get string value
  static String? getString(String key, {String? defaultValue}) {
    try {
      _ensureInitializedSync();
      return _prefs!.getString(key) ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// Save integer value
  static Future<void> saveInt(String key, int value) async {
    try {
      await _ensureInitialized();
      await _prefs!.setInt(key, value);
    } catch (e) {
      throw StorageException('ڈیٹا محفوظ کرنے میں خرابی');
    }
  }

  /// Get integer value
  static int? getInt(String key, {int? defaultValue}) {
    try {
      _ensureInitializedSync();
      return _prefs!.getInt(key) ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// Save boolean value
  static Future<void> saveBool(String key, bool value) async {
    try {
      await _ensureInitialized();
      await _prefs!.setBool(key, value);
    } catch (e) {
      throw StorageException('ڈیٹا محفوظ کرنے میں خرابی');
    }
  }

  /// Get boolean value
  static bool? getBool(String key, {bool? defaultValue}) {
    try {
      _ensureInitializedSync();
      return _prefs!.getBool(key) ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// Save double value
  static Future<void> saveDouble(String key, double value) async {
    try {
      await _ensureInitialized();
      await _prefs!.setDouble(key, value);
    } catch (e) {
      throw StorageException('ڈیٹا محفوظ کرنے میں خرابی');
    }
  }

  /// Get double value
  static double? getDouble(String key, {double? defaultValue}) {
    try {
      _ensureInitializedSync();
      return _prefs!.getDouble(key) ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// Save object as JSON
  static Future<void> saveObject(String key, Map<String, dynamic> value) async {
    try {
      await _ensureInitialized();
      final jsonString = json.encode(value);
      await _prefs!.setString(key, jsonString);
    } catch (e) {
      throw StorageException('ڈیٹا محفوظ کرنے میں خرابی');
    }
  }

  /// Get object from JSON
  static Map<String, dynamic>? getObject(String key) {
    try {
      _ensureInitializedSync();
      final jsonString = _prefs!.getString(key);
      if (jsonString == null) return null;
      return json.decode(jsonString);
    } catch (e) {
      return null;
    }
  }

  /// Save list of strings
  static Future<void> saveStringList(String key, List<String> value) async {
    try {
      await _ensureInitialized();
      await _prefs!.setStringList(key, value);
    } catch (e) {
      throw StorageException('ڈیٹا محفوظ کرنے میں خرابی');
    }
  }

  /// Get list of strings
  static List<String>? getStringList(String key) {
    try {
      _ensureInitializedSync();
      return _prefs!.getStringList(key);
    } catch (e) {
      return null;
    }
  }

  /// Remove value by key
  static Future<void> remove(String key) async {
    try {
      await _ensureInitialized();
      await _prefs!.remove(key);
    } catch (e) {
      throw StorageException('ڈیٹا حذف کرنے میں خرابی');
    }
  }

  /// Clear all stored data
  static Future<void> clear() async {
    try {
      await _ensureInitialized();
      await _prefs!.clear();
    } catch (e) {
      throw StorageException('ڈیٹا صاف کرنے میں خرابی');
    }
  }

  /// Check if key exists
  static bool containsKey(String key) {
    try {
      _ensureInitializedSync();
      return _prefs!.containsKey(key);
    } catch (e) {
      return false;
    }
  }

  /// Get all keys
  static Set<String> getAllKeys() {
    try {
      _ensureInitializedSync();
      return _prefs!.getKeys();
    } catch (e) {
      return {};
    }
  }

  /// Ensure SharedPreferences is initialized
  static Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await init();
    }
  }

  /// Ensure SharedPreferences is initialized (sync)
  static void _ensureInitializedSync() {
    if (_prefs == null) {
      throw StorageException('ذخیرہ ابھی تک شروع نہیں ہوا');
    }
  }
}

/// Storage Keys Constants
class StorageKeys {
  static const String userToken = 'user_token';
  static const String userData = 'user_data';
  static const String theme = 'app_theme';
  static const String language = 'app_language';
  static const String rememberMe = 'remember_me';
  static const String lastLogin = 'last_login';
  static const String fcmToken = 'fcm_token';
  static const String isFirstLaunch = 'is_first_launch';
  static const String cachedStudents = 'cached_students';
  static const String cachedAttendance = 'cached_attendance';
}
