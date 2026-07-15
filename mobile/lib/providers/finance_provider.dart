import 'package:flutter/material.dart';
import '../services/api_service.dart';

class FinanceProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _lastError;
  Map<String, dynamic> _solde = {
    'totalEntrees': 0.0,
    'totalSorties': 0.0,
    'soldeCaisse': 0.0,
  };
  List<Map<String, dynamic>> _mouvements = [];
  final Set<String> _sourceFilters = <String>{};
  final Set<int> _weekdayFilters = <int>{};
  int? _monthFilter;
  int? _yearFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  Map<String, dynamic> get solde => _solde;
  List<Map<String, dynamic>> get mouvements => _mouvements;
  Set<String> get sourceFilters => _sourceFilters;
  Set<int> get weekdayFilters => _weekdayFilters;
  int? get monthFilter => _monthFilter;
  int? get yearFilter => _yearFilter;
  DateTime? get dateFrom => _dateFrom;
  DateTime? get dateTo => _dateTo;

  Future<void> chargerTresorerie() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final soldeData = await ApiService.getSoldeTresorerie();
      final mouvementsData = await ApiService.getMouvementsTresorerie(
        limit: 300,
        sources: _sourceFilters.toList(),
        weekdays: _weekdayFilters.toList(),
        month: _monthFilter,
        year: _yearFilter,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      _solde = {
        'totalEntrees': (soldeData['totalEntrees'] ?? 0).toDouble(),
        'totalSorties': (soldeData['totalSorties'] ?? 0).toDouble(),
        'soldeCaisse': (soldeData['soldeCaisse'] ?? 0).toDouble(),
      };
      _mouvements = mouvementsData
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggleSourceFilter(String source) async {
    if (_sourceFilters.contains(source)) {
      _sourceFilters.remove(source);
    } else {
      _sourceFilters.add(source);
    }
    await chargerTresorerie();
  }

  Future<void> setSourceFilters(Iterable<String> sources) async {
    _sourceFilters
      ..clear()
      ..addAll(sources.where((s) => s.trim().isNotEmpty));
    await chargerTresorerie();
  }

  Future<void> toggleWeekdayFilter(int isoWeekday) async {
    if (_weekdayFilters.contains(isoWeekday)) {
      _weekdayFilters.remove(isoWeekday);
    } else {
      _weekdayFilters.add(isoWeekday);
    }
    await chargerTresorerie();
  }

  Future<void> setWeekdayFilters(Iterable<int> weekdays) async {
    _weekdayFilters
      ..clear()
      ..addAll(weekdays.where((d) => d >= 1 && d <= 7));
    await chargerTresorerie();
  }

  Future<void> setMonthFilter(int? month) async {
    _monthFilter = month;
    await chargerTresorerie();
  }

  Future<void> setYearFilter(int? year) async {
    _yearFilter = year;
    await chargerTresorerie();
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    _dateFrom = from;
    _dateTo = to;
    await chargerTresorerie();
  }

  Future<void> clearDateRange() async {
    _dateFrom = null;
    _dateTo = null;
    await chargerTresorerie();
  }

  Future<void> clearAllFilters() async {
    _sourceFilters.clear();
    _weekdayFilters.clear();
    _monthFilter = null;
    _yearFilter = null;
    _dateFrom = null;
    _dateTo = null;
    await chargerTresorerie();
  }

  Future<bool> ajouterDepense(Map<String, dynamic> payload) async {
    try {
      await ApiService.creerDepenseTresorerie(payload);
      await chargerTresorerie();
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> ajouterApprovisionnement(Map<String, dynamic> payload) async {
    try {
      await ApiService.creerApprovisionnementTresorerie(payload);
      await chargerTresorerie();
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> effacerHistoriqueMouvements() async {
    try {
      _lastError = null;
      await ApiService.effacerHistoriqueMouvementsTresorerie();
      await chargerTresorerie();
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}
