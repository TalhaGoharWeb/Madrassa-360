/// تصدیق کی خدمت
/// Authentication Service (Phase 1 - Local Mock)

import '../utils/error_handler.dart';

enum UserRole { admin, teacher, parent }

class User {
  final String id;
  final String username;
  final String name;
  final UserRole role;
  final String? email;
  final String? phone;

  User({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.email,
    this.phone,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'role': role.toString(),
        'email': email,
        'phone': phone,
      };

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      name: json['name'],
      role: UserRole.values.firstWhere(
        (e) => e.toString() == json['role'],
        orElse: () => UserRole.teacher,
      ),
      email: json['email'],
      phone: json['phone'],
    );
  }
}

class AuthService {
  static User? _currentUser;

  /// Get current logged-in user
  static Future<User?> getCurrentUser() async {
    return _currentUser;
  }

  // Mock credentials for Phase 1
  static final Map<String, Map<String, dynamic>> _mockUsers = {
    'admin': {
      'username': 'admin',
      'password': 'admin123',
      'name': 'منتظم اعظم',
      'role': UserRole.admin,
      'email': 'admin@madrasa360.pk',
      'phone': '03001234567',
    },
    'teacher': {
      'username': 'teacher',
      'password': 'teacher123',
      'name': 'مولانا محمد احمد',
      'role': UserRole.teacher,
      'email': 'teacher@madrasa360.pk',
      'phone': '03001234568',
    },
    'parent': {
      'username': 'parent',
      'password': 'parent123',
      'name': 'محمد علی',
      'role': UserRole.parent,
      'email': 'parent@madrasa360.pk',
      'phone': '03001234569',
    },
  };

  /// Get current logged-in user
  static User? get currentUser => _currentUser;

  /// Check if user is authenticated
  static bool get isAuthenticated => _currentUser != null;

  /// Login with username and password
  static Future<User> login({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    try {
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 1));

      // Find user by role
      final roleKey = role.toString().split('.').last;
      final mockUser = _mockUsers[roleKey];

      if (mockUser == null) {
        throw AuthenticationException('صارف نہیں ملا');
      }

      // Validate credentials
      if (mockUser['username'] != username || mockUser['password'] != password) {
        throw AuthenticationException('غلط صارف نام یا پاسورڈ');
      }

      // Create user object
      _currentUser = User(
        id: roleKey,
        username: mockUser['username'],
        name: mockUser['name'],
        role: mockUser['role'],
        email: mockUser['email'],
        phone: mockUser['phone'],
      );

      return _currentUser!;
    } catch (e) {
      if (e is AuthenticationException) {
        rethrow;
      }
      throw AuthenticationException('لاگ ان میں خرابی');
    }
  }

  /// Logout
  static Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = null;
  }

  /// Change password
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_currentUser == null) {
      throw AuthenticationException('صارف لاگ ان نہیں ہے');
    }

    // Validate current password
    final roleKey = _currentUser!.role.toString().split('.').last;
    final mockUser = _mockUsers[roleKey];

    if (mockUser == null || mockUser['password'] != currentPassword) {
      throw AuthenticationException('موجودہ پاسورڈ غلط ہے');
    }

    // Simulate password update
    await Future.delayed(const Duration(seconds: 1));
    mockUser['password'] = newPassword;
  }

  /// Update user profile
  static Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
  }) async {
    if (_currentUser == null) {
      throw AuthenticationException('صارف لاگ ان نہیں ہے');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    _currentUser = User(
      id: _currentUser!.id,
      username: _currentUser!.username,
      name: name ?? _currentUser!.name,
      role: _currentUser!.role,
      email: email ?? _currentUser!.email,
      phone: phone ?? _currentUser!.phone,
    );
  }

  /// Check if user has specific role
  static bool hasRole(UserRole role) {
    return _currentUser?.role == role;
  }
}
