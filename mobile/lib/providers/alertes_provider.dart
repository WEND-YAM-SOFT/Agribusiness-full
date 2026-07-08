import 'package:flutter/material.dart';
import '../models/alerte.dart';
import '../services/api_service.dart';

class AlertesProvider with ChangeNotifier {
  List<Alerte> _alertes = [];
  List<Alerte> _alertesAutomatiques = [];
  List<Alerte> _historiqueAlertes = [];
  List<Alerte> _historiqueAlertesAutomatiques = [];
  bool _isLoading = false;
  String _todoPeriod = 'all';

  List<Alerte> get alertes => _alertes;
  List<Alerte> get alertesAutomatiques => _alertesAutomatiques;
  List<Alerte> get historiqueAlertes => _historiqueAlertes;
  List<Alerte> get historiqueAlertesAutomatiques => _historiqueAlertesAutomatiques;
  bool get isLoading => _isLoading;
  String get todoPeriod => _todoPeriod;

  Future<void> chargerAlertes({String? period}) async {
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
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getAlertesAutomatiques();
      _alertesAutomatiques = data.map((json) => Alerte.fromJson(json)).toList();
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
}
