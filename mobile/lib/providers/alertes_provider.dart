import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alerte.dart';
import '../services/api_service.dart';

class AlertesProvider with ChangeNotifier {
  List<Alerte> _alertes = [];
  List<Alerte> _alertesAutomatiques = [];
  List<Alerte> _historiqueAlertes = [];
  List<Alerte> _historiqueAlertesAutomatiques = [];
  Set<String> _dismissedAutoAlertKeys = {};
  bool _isLoading = false;
  String _todoPeriod = 'all';

  static const String _dismissedAutoAlertPrefsKey = 'alertes.dismissedAutoDaily';

  List<Alerte> get alertes => _alertes;
  List<Alerte> get alertesAutomatiques => _alertesAutomatiques;
  List<Alerte> get historiqueAlertes => _historiqueAlertes;
  List<Alerte> get historiqueAlertesAutomatiques => _historiqueAlertesAutomatiques;
  bool get isLoading => _isLoading;
  String get todoPeriod => _todoPeriod;

  Future<void> chargerAlertes({String? period}) async {
    await _loadDismissedAutoAlerts();
    _isLoading = true;
    if (period != null) {
      _todoPeriod = period;
    }
    notifyListeners();
    try {
      final data = await ApiService.getAlertesActives(period: _todoPeriod);
      _alertes = data.map((json) => Alerte.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> chargerAlertesAutomatiques() async {
    await _loadDismissedAutoAlerts();
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getAlertesAutomatiques();
      _alertesAutomatiques = data
          .map((json) => Alerte.fromJson(json))
          .where((a) => !_dismissedAutoAlertKeys.contains(_dismissKeyForToday(a.id)))
          .toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> chargerHistoriqueAlertes() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getHistoriqueAlertes();
      _historiqueAlertes = data.map((json) => Alerte.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> chargerHistoriqueAlertesAutomatiques() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getHistoriqueAlertesAutomatiques();
      _historiqueAlertesAutomatiques = data.map((json) => Alerte.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> creerAlerte(Map<String, dynamic> data) async {
    try {
      await ApiService.creerAlerte(data);
      await chargerAlertes();
      await chargerHistoriqueAlertes();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> marquerFaite(Alerte alerte) async {
    try {
      await _loadDismissedAutoAlerts();
      await ApiService.marquerAlerteFaite(
        alerte.id ?? '',
        data: {
          'titre': alerte.titre,
          'message': alerte.message,
          'type': alerte.type,
          'dateEcheance': alerte.dateEcheance.toIso8601String(),
          'priorite': alerte.priorite,
          'source': alerte.source,
        },
      );
      if (alerte.automatique || _isSyntheticAlerteId(alerte.id)) {
        _dismissedAutoAlertKeys.add(_dismissKeyForToday(alerte.id));
        await _saveDismissedAutoAlerts();
      }
      await chargerAlertes();
      await chargerAlertesAutomatiques();
      await chargerHistoriqueAlertes();
      await chargerHistoriqueAlertesAutomatiques();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> mettreAJourAlerte(String id, Map<String, dynamic> data) async {
    try {
      await ApiService.mettreAJourAlerte(id, data);
      await chargerAlertes(period: _todoPeriod);
      await chargerHistoriqueAlertes();
      return true;
    } catch (e) {
      debugPrint('Erreur MAJ alerte: $e');
      return false;
    }
  }

  Future<bool> effacerHistorique() async {
    try {
      await ApiService.effacerHistoriqueAlertes();
      await chargerHistoriqueAlertes();
      await chargerAlertes(period: _todoPeriod);
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  bool _isSyntheticAlerteId(String? id) {
    if (id == null || id.isEmpty) return false;
    return id.startsWith('stock-')
        || id.startsWith('sanitaire-')
        || id.startsWith('prevision-')
        || id.startsWith('commercial-')
        || id.startsWith('crm-task-');
  }

  String _todayStamp() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  String _dismissKeyForToday(String? id) {
    return '${id ?? ''}|${_todayStamp()}';
  }

  Future<void> _loadDismissedAutoAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_dismissedAutoAlertPrefsKey) ?? const [];
    final today = _todayStamp();
    _dismissedAutoAlertKeys = stored.where((x) => x.endsWith('|$today')).toSet();
    await prefs.setStringList(_dismissedAutoAlertPrefsKey, _dismissedAutoAlertKeys.toList());
  }

  Future<void> _saveDismissedAutoAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedAutoAlertPrefsKey, _dismissedAutoAlertKeys.toList());
  }
}
