import 'package:flutter/material.dart';
import '../models/bande.dart';
import '../services/api_service.dart';

class BandesProvider with ChangeNotifier {
  List<Bande> _bandesActives = [];
  List<Bande> _bandesHistorique = [];
  bool _isLoading = false;
  String? _lastError;

  List<Bande> get bandesActives => _bandesActives;
  List<Bande> get bandesHistorique => _bandesHistorique;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<void> chargerBandesActives() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getBandesActives();
      _bandesActives = data.map((json) => Bande.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> chargerHistorique() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getBandesHistorique();
      _bandesHistorique = data.map((json) => Bande.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> ouvrirBande(Map<String, dynamic> data) async {
    try {
      await ApiService.creerBande(data);
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> fermerBande(String id) async {
    _lastError = null;
    try {
      await ApiService.fermerBande(id);
      await chargerBandesActives();
      await chargerHistorique();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      return false;
    }
  }

  Future<bool> supprimerBande(String id) async {
    _lastError = null;
    if (id.isEmpty) {
      _lastError = 'ID cycle manquant';
      return false;
    }
    try {
      await ApiService.supprimerBande(id);
      await chargerHistorique();
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      return false;
    }
  }

  Future<bool> ajouterSuivi(String bandeId, Map<String, dynamic> data) async {
    try {
      await ApiService.ajouterSuivi(bandeId, data);
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> ajouterEvenementSante(String bandeId, Map<String, dynamic> data) async {
    try {
      await ApiService.ajouterEvenementSante(bandeId, data);
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> ajouterRelevePoids(String bandeId, Map<String, dynamic> data) async {
    try {
      await ApiService.ajouterRelevePoids(bandeId, data);
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> ajouterReleveClimat(String bandeId, Map<String, dynamic> data) async {
    try {
      await ApiService.ajouterReleveClimat(bandeId, data);
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> ajouterEvenementPrevisionnel(String bandeId, Map<String, dynamic> data) async {
    _lastError = null;
    if (bandeId.isEmpty) {
      _lastError = 'ID cycle manquant';
      return false;
    }
    try {
      await ApiService.ajouterEvenementPrevisionnel(bandeId, data);
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      return false;
    }
  }

  Future<bool> terminerEvenementPrevisionnel(
    String bandeId,
    String eventId, {
    String commentairesRealisation = '',
    String? prophylaxieStockId,
    String prophylaxieType = '',
    double prophylaxieQuantite = 0,
  }) async {
    _lastError = null;
    if (bandeId.isEmpty || eventId.isEmpty) {
      _lastError = 'ID cycle ou événement manquant';
      return false;
    }
    try {
      await ApiService.terminerEvenementPrevisionnel(bandeId, eventId, {
        'dateRealisation': DateTime.now().toIso8601String(),
        'commentairesRealisation': commentairesRealisation,
        'prophylaxieStockId': prophylaxieStockId,
        'prophylaxieType': prophylaxieType,
        'prophylaxieQuantite': prophylaxieQuantite,
      });
      await chargerBandesActives();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      return false;
    }
  }
}
