import 'package:flutter/material.dart';
import '../models/interaction.dart';
import '../models/tache_crm.dart';
import '../services/api_service.dart';

class CrmProvider with ChangeNotifier {
  List<Interaction> _interactions = [];
  List<TacheCRM> _taches = [];
  List<Map<String, dynamic>> _pipeline = [];
  List<Map<String, dynamic>> _pipelineStages = [];
  List<Map<String, dynamic>> _leadSources = [];
  double _conversionRate = 0;
  bool _isLoading = false;

  List<Interaction> get interactions => _interactions;
  List<TacheCRM> get taches => _taches;
  List<Map<String, dynamic>> get pipeline => _pipeline;
  List<Map<String, dynamic>> get pipelineStages => _pipelineStages;
  List<Map<String, dynamic>> get leadSources => _leadSources;
  double get conversionRate => _conversionRate;
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

  Future<void> chargerPipelineCommercial() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getPipelineCommercial();
      _pipeline = List<Map<String, dynamic>>.from(
        (data['pipeline'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      _pipelineStages = List<Map<String, dynamic>>.from(
        (data['stages'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      _leadSources = List<Map<String, dynamic>>.from(
        (data['sources'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      _conversionRate = ((data['conversionRate'] ?? 0) as num).toDouble();
    } catch (e) {
      debugPrint('Erreur pipeline: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> mettreAJourPipelineClient(String clientId, Map<String, dynamic> payload) async {
    try {
      await ApiService.mettreAJourPipelineClient(clientId, payload);
      await chargerPipelineCommercial();
      return true;
    } catch (e) {
      debugPrint('Erreur mise a jour pipeline: $e');
      return false;
    }
  }
}
