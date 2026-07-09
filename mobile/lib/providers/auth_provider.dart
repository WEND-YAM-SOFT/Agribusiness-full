import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _lastError;
  Timer? _inactivityTimer;
  int _sessionTimeoutMinutes = 30;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  bool get isAuthenticated => _token != null && _user != null;

  bool get isAdmin => (_user?['role'] ?? '') == 'admin';

  List<dynamic> get permissions => (_user?['permissions'] as List?) ?? [];

  bool hasPermission(String permission) {
    if (isAdmin) return true;
    return permissions.contains(permission);
  }

  Future<void> initSession() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    final userStr = prefs.getString('auth_user');
    _sessionTimeoutMinutes = prefs.getInt('session_timeout_minutes') ?? 30;

    if (_token != null && userStr != null) {
      _user = Map<String, dynamic>.from(json.decode(userStr));
      ApiService.setAuthToken(_token);

      try {
        final fresh = await ApiService.getProfil();
        _user = fresh;
        await prefs.setString('auth_user', json.encode(_user));
      } catch (_) {
        await logout(silent: true);
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final data = await ApiService.connexion(email, password);
      _token = data['token'] as String?;
      _user = Map<String, dynamic>.from(data['utilisateur'] ?? {});
      _sessionTimeoutMinutes = (data['sessionTimeoutMinutes'] ?? 30) as int;

      ApiService.setAuthToken(_token);
      await _persistSession();
      _restartInactivityTimer();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '').trim();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout({bool silent = false}) async {
    _inactivityTimer?.cancel();

    if (!silent && _token != null) {
      try {
        await ApiService.deconnexion();
      } catch (_) {}
    }

    _token = null;
    _user = null;
    ApiService.setAuthToken(null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user');

    notifyListeners();
  }

  void registerActivity() {
    if (!isAuthenticated) return;
    _restartInactivityTimer();
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final updated = await ApiService.updateProfil(data);
      _user = updated;
      await _persistSession();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changePassword(String actuel, String nouveau) async {
    try {
      await ApiService.changerMotDePasse(actuel, nouveau);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> forgotPassword(String email) async {
    try {
      return await ApiService.demanderResetMotDePasse(email);
    } catch (_) {
      return null;
    }
  }

  Future<bool> resetPassword(String token, String password) async {
    try {
      await ApiService.reinitialiserMotDePasse(token, password);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString('auth_token', _token!);
    }
    if (_user != null) {
      await prefs.setString('auth_user', json.encode(_user));
    }
    await prefs.setInt('session_timeout_minutes', _sessionTimeoutMinutes);
  }

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(Duration(minutes: _sessionTimeoutMinutes), () {
      logout();
    });
  }
}
