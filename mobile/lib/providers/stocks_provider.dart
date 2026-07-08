import 'package:flutter/material.dart';
import '../models/stock.dart';
import '../services/api_service.dart';

class StocksProvider with ChangeNotifier {
  List<Stock> _stocks = [];
  bool _isLoading = false;
  String? _lastError;

  List<Stock> get stocks => _stocks;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<void> chargerStocks() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final data = await ApiService.getStocks();
      _stocks = data.map((json) => Stock.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> creerStock(Map<String, dynamic> data) async {
    try {
      _lastError = null;
      await ApiService.creerStock(data);
      await chargerStocks();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> ajouterMouvement(String stockId, Map<String, dynamic> data) async {
    try {
      _lastError = null;
      await ApiService.ajouterMouvement(stockId, data);
      await chargerStocks();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> supprimerMouvement(String stockId, String mouvementId) async {
    try {
      _lastError = null;
      await ApiService.supprimerMouvementStock(stockId, mouvementId);
      await chargerStocks();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> effacerHistorique(String stockId) async {
    try {
      _lastError = null;
      await ApiService.effacerHistoriqueStock(stockId);
      await chargerStocks();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> supprimerStock(String stockId) async {
    try {
      _lastError = null;
      await ApiService.supprimerStock(stockId);
      await chargerStocks();
      return true;
    } catch (e) {
      debugPrint('Erreur: $e');
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}
