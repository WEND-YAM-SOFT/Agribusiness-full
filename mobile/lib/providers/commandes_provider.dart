import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/commande.dart';
import '../services/api_service.dart';

class CommandesProvider with ChangeNotifier {
  CommandesProvider() {
    _restaurerFiltres();
  }

  List<Commande> _commandes = [];
  bool _isLoading = false;
  Set<String> _selectedStatuts = {};
  String _searchQuery = '';
  bool _filtresRestaures = false;

  List<Commande> get commandes => _commandes;
  bool get isLoading => _isLoading;
  Set<String> get selectedStatuts => _selectedStatuts;
  bool get hasAnyStatutFilter => _selectedStatuts.isNotEmpty;
  bool isStatutSelected(String statut) => _selectedStatuts.contains(statut);
  String get searchQuery => _searchQuery;
  List<Commande> get commandesFiltrees {
    return _commandes.where((commande) {
      final statutOk = _selectedStatuts.isEmpty || _selectedStatuts.contains(commande.statut);
      if (!statutOk) return false;
      if (_searchQuery.trim().isEmpty) return true;

      final query = _searchQuery.trim().toLowerCase();
      final haystack = [
        commande.clientNom,
        commande.bandeNom,
        commande.notes,
        commande.statut,
        commande.montantTotal.toStringAsFixed(0),
        ...commande.produits.map((p) => p.nom),
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  void toggleStatut(String statut) {
    if (_selectedStatuts.contains(statut)) {
      _selectedStatuts.remove(statut);
    } else {
      _selectedStatuts.add(statut);
    }
    _sauvegarderFiltres();
    notifyListeners();
  }

  void clearStatutsFilter() {
    _selectedStatuts.clear();
    _sauvegarderFiltres();
    notifyListeners();
  }

  void rechercher(String query) {
    _searchQuery = query;
    _sauvegarderFiltres();
    notifyListeners();
  }

  Future<void> chargerCommandes() async {
    if (!_filtresRestaures) {
      await _restaurerFiltres();
    }
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getCommandes();
      final parsed = <Commande>[];
      for (final json in data) {
        if (json is! Map) continue;
        try {
          parsed.add(Commande.fromJson(Map<String, dynamic>.from(json)));
        } catch (e) {
          debugPrint('Commande ignorée (format invalide): $e');
        }
      }
      _commandes = parsed;
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> creerCommande(Map<String, dynamic> data) async {
    try {
      final created = await ApiService.creerCommande(data);
      final createdStatut = (created['statut'] ?? 'en_attente').toString();
      if (_selectedStatuts.isNotEmpty && !_selectedStatuts.contains(createdStatut)) {
        _selectedStatuts.clear();
      }
      if (_searchQuery.trim().isNotEmpty) {
        _searchQuery = '';
      }
      await _sauvegarderFiltres();
      await chargerCommandes();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> mettreAJourCommande(String id, Map<String, dynamic> data) async {
    try {
      await ApiService.mettreAJourCommande(id, data);
      await chargerCommandes();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> mettreAJourStatut(String id, String statut) async {
    try {
      await ApiService.mettreAJourStatutCommande(id, statut);
      await chargerCommandes();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> ajouterCommentaire(String id, String message) async {
    try {
      await ApiService.ajouterCommentaireCommande(id, {
        'message': message,
        'auteur': 'Utilisateur'
      });
      await chargerCommandes();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> ajouterLivraison(String commandeId, Map<String, dynamic> data) async {
    try {
      await ApiService.ajouterLivraisonCommande(commandeId, data);
      await chargerCommandes();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<void> _restaurerFiltres() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedStatuts = (prefs.getStringList('commandes.selectedStatuts') ?? const []).toSet();
    _selectedStatuts.remove('toutes');
    _searchQuery = prefs.getString('commandes.searchQuery') ?? '';
    _filtresRestaures = true;
    notifyListeners();
  }

  Future<void> _sauvegarderFiltres() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('commandes.selectedStatuts', _selectedStatuts.toList());
    await prefs.setString('commandes.searchQuery', _searchQuery);
  }
}
