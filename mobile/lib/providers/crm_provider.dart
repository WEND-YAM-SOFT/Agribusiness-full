import 'package:flutter/material.dart';
import '../models/interaction.dart';
import '../models/tache_crm.dart';
import '../services/api_service.dart';

class CrmProvider with ChangeNotifier {
  List<Interaction> _interactions = [];
  List<TacheCRM> _taches = [];
  bool _isLoading = false;

  List<Interaction> get interactions => _interactions;
  List<TacheCRM> get taches => _taches;
  bool get isLoading => _isLoading;

  Future<void> chargerInteractionsClient(String clientId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getInteractionsClient(clientId);
      _interactions = data.map((j) => Interaction.fromJson(j)).toList();
    } catch (e) {
      debugPrint('Erreur interactions: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> ajouterInteractionClient(String clientId, Map<String, dynamic> data) async {
    try {
      await ApiService.ajouterInteractionClient(clientId, data);
      await chargerInteractionsClient(clientId);
      return true;
    } catch (e) {
      debugPrint('Erreur ajout interaction: $e');
      return false;
    }
  }

  Future<void> chargerTachesCrm() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getTachesCrm();
      _taches = data.map((j) => TacheCRM.fromJson(j)).toList();
    } catch (e) {
      debugPrint('Erreur tâches: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> creerTache(Map<String, dynamic> data) async {
    try {
      await ApiService.creerTacheCrm(data);
      await chargerTachesCrm();
      return true;
    } catch (e) {
      debugPrint('Erreur création tâche: $e');
      return false;
    }
  }

  Future<bool> mettreAJourTache(String id, Map<String, dynamic> data) async {
    try {
      await ApiService.mettreAJourTacheCrm(id, data);
      await chargerTachesCrm();
      return true;
    } catch (e) {
      debugPrint('Erreur MAJ tâche: $e');
      return false;
    }
  }

  Future<bool> supprimerTache(String id) async {
    try {
      await ApiService.supprimerTacheCrm(id);
      await chargerTachesCrm();
      return true;
    } catch (e) {
      debugPrint('Erreur suppression tâche: $e');
      return false;
    }
  }

  Future<bool> effacerHistoriqueTaches() async {
    try {
      await ApiService.effacerHistoriqueTachesCrm();
      await chargerTachesCrm();
      return true;
    } catch (e) {
      debugPrint('Erreur historique CRM: $e');
      return false;
    }
  }
}
