import 'package:flutter/material.dart';

import '../models/client.dart';
import '../services/api_service.dart';

class FournisseursProvider with ChangeNotifier {
  List<Client> _fournisseurs = [];
  bool _isLoading = false;

  List<Client> get fournisseurs => _fournisseurs;
  bool get isLoading => _isLoading;

  Future<void> chargerFournisseurs() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getFournisseurs();
      _fournisseurs = data.map((json) => Client.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur fournisseurs: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> rechercherFournisseurs(String query) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = query.trim().isEmpty
          ? await ApiService.getFournisseurs()
          : await ApiService.rechercherFournisseurs(query);
      _fournisseurs = data.map((json) => Client.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur fournisseurs: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> ajouterFournisseur(Map<String, dynamic> data) async {
    try {
      await ApiService.creerFournisseur(data);
      await chargerFournisseurs();
      return true;
    } catch (e) {
      debugPrint('Erreur fournisseurs: $e');
      return false;
    }
  }

  Future<bool> mettreAJourFournisseur(String id, Map<String, dynamic> data) async {
    try {
      await ApiService.mettreAJourFournisseur(id, data);
      await chargerFournisseurs();
      return true;
    } catch (e) {
      debugPrint('Erreur fournisseurs: $e');
      return false;
    }
  }

  Future<bool> supprimerFournisseur(String id) async {
    try {
      await ApiService.supprimerFournisseur(id);
      await chargerFournisseurs();
      return true;
    } catch (e) {
      debugPrint('Erreur fournisseurs: $e');
      return false;
    }
  }
}
