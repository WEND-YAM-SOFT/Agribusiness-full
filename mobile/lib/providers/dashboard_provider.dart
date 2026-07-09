import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class DashboardProvider with ChangeNotifier {
  DashboardProvider() {
    _restaurerFiltres();
  }

  Map<String, dynamic> _global = {};
  Map<String, dynamic> _crm = {};
  List<Map<String, dynamic>> _bandes = [];
  bool _isLoading = false;
  String? _lastError;
  bool _filtresRestaures = false;
  String _period = 'mois';
  String _selectedBandeId = '';
  String _selectedBatiment = '';

  Map<String, dynamic> get global => _global;
  Map<String, dynamic> get crm => _crm;
  List<Map<String, dynamic>> get bandes => _bandes;
  String? get lastError => _lastError;
  List<String> get batiments => _bandes
      .map((b) => (b['batiment'] ?? '').toString())
      .where((b) => b.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  List<Map<String, dynamic>> get bandesFiltreesPourBatiment {
    if (_selectedBatiment.isEmpty) return _bandes;
    return _bandes.where((b) => (b['batiment'] ?? '').toString() == _selectedBatiment).toList();
  }
  bool get isLoading => _isLoading;
  String get period => _period;
  String get selectedBandeId => _selectedBandeId;
  String get selectedBatiment => _selectedBatiment;

  Future<void> chargerDashboards({String? period, String? bandeId, String? batiment}) async {
    if (!_filtresRestaures) {
      await _restaurerFiltres(notify: false);
    }

    _isLoading = true;
    _lastError = null;
    if (period != null) {
      _period = period;
    }
    if (bandeId != null) {
      _selectedBandeId = bandeId;
    }
    if (batiment != null) {
      _selectedBatiment = batiment;
    }
    notifyListeners();

    if (_bandes.isEmpty) {
      try {
        final actives = await ApiService.getBandesActives();
        final historiques = await ApiService.getBandesHistorique();
        _bandes = [...actives, ...historiques]
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (e) {
        _lastError = e.toString().replaceFirst('Exception: ', '').trim();
        debugPrint('Erreur chargement bandes dashboard: $e');
      }
    }

    _validerFiltresSelectionnes();
    await _sauvegarderFiltres();

    try {
      _global = await ApiService.getGlobalDashboard(
        period: _period,
        bandeId: _selectedBandeId.isEmpty ? null : _selectedBandeId,
        batiment: _selectedBatiment.isEmpty ? null : _selectedBatiment,
      );
    } catch (e) {
      _global = {};
      _lastError = e.toString().replaceFirst('Exception: ', '').trim();
      debugPrint('Erreur dashboard global: $e');
    }

    try {
      _crm = await ApiService.getCrmDashboard();
    } catch (e) {
      _crm = {};
      _lastError ??= e.toString().replaceFirst('Exception: ', '').trim();
      debugPrint('Erreur dashboard CRM: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void _validerFiltresSelectionnes() {
    if (_selectedBatiment.isNotEmpty) {
      final batimentExiste = _bandes.any(
        (b) => (b['batiment'] ?? '').toString() == _selectedBatiment,
      );
      if (!batimentExiste) {
        _selectedBatiment = '';
      }
    }

    if (_selectedBatiment.isNotEmpty && _selectedBandeId.isNotEmpty) {
      final bandeToujoursValide = _bandes.any(
        (b) => (b['batiment'] ?? '').toString() == _selectedBatiment &&
            (b['id'] ?? b['_id']).toString() == _selectedBandeId,
      );
      if (!bandeToujoursValide) {
        _selectedBandeId = '';
      }
    }
  }

  Future<void> _restaurerFiltres({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    _period = prefs.getString('dashboard.period') ?? 'mois';
    _selectedBatiment = prefs.getString('dashboard.selectedBatiment') ?? '';
    _selectedBandeId = prefs.getString('dashboard.selectedBandeId') ?? '';
    _filtresRestaures = true;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _sauvegarderFiltres() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dashboard.period', _period);
    await prefs.setString('dashboard.selectedBatiment', _selectedBatiment);
    await prefs.setString('dashboard.selectedBandeId', _selectedBandeId);
  }
}
