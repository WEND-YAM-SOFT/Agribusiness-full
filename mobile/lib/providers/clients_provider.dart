import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/client.dart';
import '../services/api_service.dart';

class ClientsProvider with ChangeNotifier {
  ClientsProvider() {
    _restaurerFiltres();
  }

  List<Client> _clients = [];
  bool _isLoading = false;
  bool _filtresRestaures = false;
  String _searchQuery = '';
  String _crmStatut = '';

  List<Client> get clients => _clients;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String? get crmStatutFilter => _crmStatut.isEmpty ? null : _crmStatut;

  Future<void> ensureFiltresRestaures() async {
    if (_filtresRestaures) return;
    await _restaurerFiltres();
  }

  Future<void> chargerClients({String? statut}) async {
    await ensureFiltresRestaures();
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getClients(statut: statut);
      _clients = data.map((json) => Client.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> rechercherClients(String query, {bool sauvegarder = true}) async {
    await ensureFiltresRestaures();
    if (sauvegarder) {
      await setSearchQuery(query);
    }
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.rechercherClients(query);
      _clients = data.map((json) => Client.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    await _sauvegarderFiltres();
  }

  Future<void> appliquerRecherchePersistante() async {
    await ensureFiltresRestaures();
    final query = _searchQuery.trim();
    if (query.length >= 2) {
      await rechercherClients(query, sauvegarder: false);
      return;
    }
    await chargerClients();
  }

  Future<void> viderRecherche() async {
    await setSearchQuery('');
    await chargerClients();
  }

  Future<void> chargerClientsPourCrm() async {
    await ensureFiltresRestaures();
    final query = _searchQuery.trim();
    if (query.length >= 2) {
      await rechercherClients(query, sauvegarder: false);
      if (crmStatutFilter != null) {
        _clients = _clients.where((c) => c.statut == crmStatutFilter).toList();
        notifyListeners();
      }
      return;
    }

    await chargerClients(statut: crmStatutFilter);
  }

  Future<void> filtrerClientsCrm(String? statut) async {
    _crmStatut = statut ?? '';
    await _sauvegarderFiltres();
    await chargerClientsPourCrm();
  }

  Future<void> rechercherClientsCrm(String query) async {
    await setSearchQuery(query);
    await chargerClientsPourCrm();
  }

  Future<void> viderRechercheCrm() async {
    await setSearchQuery('');
    await chargerClientsPourCrm();
  }

  Future<bool> ajouterClient(Map<String, dynamic> data) async {
    try {
      await ApiService.creerClient(data);
      await chargerClients();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<String?> ajouterClientEtRetourId(Map<String, dynamic> data) async {
    try {
      final created = await ApiService.creerClient(data);
      await chargerClients();
      return created['_id']?.toString();
    } catch (e) {
      debugPrint('Erreur: $e');
      return null;
    }
  }

  Future<bool> mettreAJourClient(String id, Map<String, dynamic> data) async {
    try {
      await ApiService.mettreAJourClient(id, data);
      await chargerClients();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<bool> supprimerClient(String id) async {
    try {
      await ApiService.supprimerClient(id);
      await appliquerRecherchePersistante();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      return false;
    }
  }

  Future<void> _restaurerFiltres() async {
    final prefs = await SharedPreferences.getInstance();
    _searchQuery = prefs.getString('clients.searchQuery') ?? '';
    _crmStatut = prefs.getString('crm.clients.statut') ?? '';
    _filtresRestaures = true;
    notifyListeners();
  }

  Future<void> _sauvegarderFiltres() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('clients.searchQuery', _searchQuery);
    await prefs.setString('crm.clients.statut', _crmStatut);
  }
}
