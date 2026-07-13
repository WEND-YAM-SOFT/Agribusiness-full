import 'package:flutter/material.dart';

import '../services/api_service.dart';

class AdminProvider with ChangeNotifier {
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _auditLogs = [];
  String? _lastError;

  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get users => _users;
  Map<String, dynamic>? get config => _config;
  List<Map<String, dynamic>> get auditLogs => _auditLogs;
  String? get lastError => _lastError;

  Future<void> loadAll() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final usersData = await ApiService.getUtilisateurs();
      _users = usersData.map((e) => Map<String, dynamic>.from(e)).toList();

      try {
        final configData = await ApiService.getConfig();
        _config = Map<String, dynamic>.from(configData);
      } catch (e) {
        _lastError = e.toString().replaceFirst('Exception: ', '').trim();
      }

      try {
        final logsData = await ApiService.getAuditLogs();
        _auditLogs = logsData.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        _lastError ??= e.toString().replaceFirst('Exception: ', '').trim();
      }
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '').trim();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> createUser(Map<String, dynamic> data) async {
    try {
      _lastError = null;
      final resp = await ApiService.creerUtilisateur(data);
      await loadAll();
      return resp;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '').trim();
      return null;
    }
  }

  Future<bool> updateUser(String id, Map<String, dynamic> data) async {
    try {
      await ApiService.updateUtilisateur(id, data);
      await loadAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleUserActive(String id, bool active) async {
    try {
      if (active) {
        await ApiService.activerUtilisateur(id);
      } else {
        await ApiService.desactiverUtilisateur(id);
      }
      await loadAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> resetPassword(String id) async {
    try {
      final resp = await ApiService.resetMotDePasseUtilisateur(id);
      await loadAll();
      return resp['motDePasseTemporaire'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteUser(String id) async {
    try {
      await ApiService.supprimerUtilisateur(id);
      await loadAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateConfig(Map<String, dynamic> data) async {
    try {
      _config = await ApiService.updateConfig(data);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearAuditLogs() async {
    try {
      await ApiService.effacerAuditLogs();
      await loadAll();
      return true;
    } catch (_) {
      return false;
    }
  }
}
