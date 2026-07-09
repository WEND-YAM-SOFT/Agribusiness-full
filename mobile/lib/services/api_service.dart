import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ApiService {
  static String? _authToken;

  static void setAuthToken(String? token) {
    _authToken = token;
  }

  static Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{};
    if (jsonBody) headers['Content-Type'] = 'application/json';
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  static Future<http.Response> _get(String path, {Map<String, String>? query}) {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    return http.get(uri, headers: _headers());
  }

  static Future<http.Response> _post(String path, {Map<String, dynamic>? body}) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(jsonBody: true),
      body: body == null ? null : json.encode(body),
    );
  }

  static Future<http.Response> _put(String path, {Map<String, dynamic>? body}) {
    return http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers(jsonBody: true),
      body: body == null ? null : json.encode(body),
    );
  }

  static Future<http.Response> _delete(String path) {
    return http.delete(Uri.parse('$baseUrl$path'), headers: _headers());
  }

  static dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    return json.decode(response.body);
  }

    static dynamic _ensureSuccess(http.Response response, {List<int> accepted = const [200], String? endpoint}) {
    if (accepted.contains(response.statusCode)) {
      return _decode(response);
    }

        dynamic data;
    try {
            data = _decode(response);
    } catch (_) {
            data = null;
        }

        if (data is Map && data['message'] != null) {
            final msg = data['message'].toString();
            if (endpoint != null && endpoint.isNotEmpty) {
                throw Exception('$msg [$endpoint]');
            }
            throw Exception(msg);
    }

        if (endpoint != null && endpoint.isNotEmpty) {
            throw Exception('Erreur API (${response.statusCode}) [$endpoint]');
        }
        throw Exception('Erreur API (${response.statusCode})');
  }

  // BANDES
  static Future<List<dynamic>> getBandesActives() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/actives')) ?? []);

  static Future<List<dynamic>> getBandesHistorique() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/historique')) ?? []);

  static Future<Map<String, dynamic>> creerBande(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/bandes', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> fermerBande(String id) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/bandes/$id/fermer')));

    static Future<void> supprimerBande(String id) async {
        _ensureSuccess(await _delete('/bandes/$id'), endpoint: 'DELETE /bandes/$id');
    }

  static Future<Map<String, dynamic>> mettreAJourBande(String id, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/bandes/$id', body: data)));

  static Future<Map<String, dynamic>> getStatsBande(String id) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _get('/bandes/$id/stats')));

  static Future<List<dynamic>> getComparaisonBandes() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/comparaison')) ?? []);

  static Future<List<dynamic>> getPerformancesBatiment() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/performances/batiment')) ?? []);

  static Future<Map<String, dynamic>> getSuiviDashboardBande(String bandeId) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _get('/dashboard/bandes/$bandeId/suivi')));

  // SUIVI / SANTE
  static Future<Map<String, dynamic>> ajouterSuivi(String bandeId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/bandes/$bandeId/suivi', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> ajouterRelevePoids(String bandeId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/bandes/$bandeId/poids', body: data), accepted: const [201]));

  static Future<List<dynamic>> getRelevesPoids(String bandeId) async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/$bandeId/poids')) ?? []);

  static Future<Map<String, dynamic>> ajouterReleveClimat(String bandeId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/bandes/$bandeId/climat', body: data), accepted: const [201]));

  static Future<List<dynamic>> getRelevesClimat(String bandeId) async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/$bandeId/climat')) ?? []);

  static Future<List<dynamic>> getSuivis(String bandeId) async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/$bandeId/suivis')) ?? []);

  static Future<Map<String, dynamic>> ajouterEvenementSante(String bandeId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/bandes/$bandeId/sante', body: data), accepted: const [201]));

  static Future<List<dynamic>> getEvenementsSante(String bandeId) async =>
      List<dynamic>.from(_ensureSuccess(await _get('/bandes/$bandeId/sante')) ?? []);

  static Future<List<dynamic>> getEvenementsPrevisionnels(String bandeId) async =>
      List<dynamic>.from(await _getEvenementsPrevisionnelsWithFallback(bandeId));

  static Future<Map<String, dynamic>> ajouterEvenementPrevisionnel(String bandeId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await _ajouterEvenementPrevisionnelWithFallback(bandeId, data));

  static Future<Map<String, dynamic>> terminerEvenementPrevisionnel(String bandeId, String eventId, Map<String, dynamic> data) async =>
            Map<String, dynamic>.from(await _terminerEvenementPrevisionnelWithFallback(bandeId, eventId, data));

    static Future<List<dynamic>> _getEvenementsPrevisionnelsWithFallback(String bandeId) async {
        if (bandeId.isEmpty) {
            throw Exception('ID cycle manquant');
        }

        final primary = await _get('/bandes/$bandeId/evenements-previsionnels');
        if (primary.statusCode != 404) {
            return List<dynamic>.from(_ensureSuccess(primary, endpoint: 'GET /bandes/$bandeId/evenements-previsionnels') ?? []);
        }

        final fallback = await _get('/cycles/$bandeId/evenements-previsionnels');
        return List<dynamic>.from(_ensureSuccess(fallback, endpoint: 'GET /cycles/$bandeId/evenements-previsionnels') ?? []);
    }

    static Future<Map<String, dynamic>> _ajouterEvenementPrevisionnelWithFallback(String bandeId, Map<String, dynamic> data) async {
        if (bandeId.isEmpty) {
            throw Exception('ID cycle manquant');
        }

        final primary = await _post('/bandes/$bandeId/evenements-previsionnels', body: data);
        if (primary.statusCode != 404) {
            return Map<String, dynamic>.from(_ensureSuccess(primary, accepted: const [201], endpoint: 'POST /bandes/$bandeId/evenements-previsionnels'));
        }

        final fallback = await _post('/cycles/$bandeId/evenements-previsionnels', body: data);
        return Map<String, dynamic>.from(_ensureSuccess(fallback, accepted: const [201], endpoint: 'POST /cycles/$bandeId/evenements-previsionnels'));
    }

    static Future<Map<String, dynamic>> _terminerEvenementPrevisionnelWithFallback(String bandeId, String eventId, Map<String, dynamic> data) async {
        if (bandeId.isEmpty) {
            throw Exception('ID cycle manquant');
        }
        if (eventId.isEmpty) {
            throw Exception('ID événement manquant');
        }

        final primary = await _put('/bandes/$bandeId/evenements-previsionnels/$eventId/terminer', body: data);
        if (primary.statusCode != 404) {
            return Map<String, dynamic>.from(_ensureSuccess(primary, endpoint: 'PUT /bandes/$bandeId/evenements-previsionnels/$eventId/terminer'));
        }

        final fallback = await _put('/cycles/$bandeId/evenements-previsionnels/$eventId/terminer', body: data);
        return Map<String, dynamic>.from(_ensureSuccess(fallback, endpoint: 'PUT /cycles/$bandeId/evenements-previsionnels/$eventId/terminer'));
    }

  // STOCKS
  static Future<List<dynamic>> getStocks() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/stocks')) ?? []);

  static Future<List<dynamic>> getStocksEnAlerte() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/stocks/alertes')) ?? []);

  static Future<Map<String, dynamic>> creerStock(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/stocks', body: data), accepted: const [201]));

    static Future<void> supprimerStock(String stockId) async {
        _ensureSuccess(await _delete('/stocks/$stockId'));
    }

  static Future<Map<String, dynamic>> ajouterMouvement(String stockId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/stocks/$stockId/mouvement', body: data)));

  static Future<Map<String, dynamic>> supprimerMouvementStock(String stockId, String mouvementId) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _delete('/stocks/$stockId/mouvements/$mouvementId')));

  static Future<Map<String, dynamic>> effacerHistoriqueStock(String stockId) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _delete('/stocks/$stockId/mouvements')));

  // ALERTES
  static Future<List<dynamic>> getAlertesActives({String period = 'all'}) async =>
      List<dynamic>.from(_ensureSuccess(await _get('/alertes/actives', query: {'period': period})) ?? []);

  static Future<List<dynamic>> getAlertesAutomatiques() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/alertes/automatiques')) ?? []);

  static Future<List<dynamic>> getHistoriqueAlertes() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/alertes/historique')) ?? []);

  static Future<List<dynamic>> getHistoriqueAlertesAutomatiques() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/alertes/automatiques/historique')) ?? []);

  static Future<List<dynamic>> getAlertesRetard() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/alertes/retard')) ?? []);

  static Future<Map<String, dynamic>> creerAlerte(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/alertes', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> marquerAlerteFaite(String id, {Map<String, dynamic>? data}) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/alertes/$id/fait', body: data ?? {})));

  static Future<Map<String, dynamic>> mettreAJourAlerte(String id, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/alertes/$id', body: data)));

    static Future<void> effacerHistoriqueAlertes() async {
        _ensureSuccess(await _delete('/alertes/historique/all'));
    }

  // CLIENTS
  static Future<List<dynamic>> getClients({String? statut, String? q}) async {
    final params = <String, String>{};
    if (statut != null && statut.isNotEmpty) params['statut'] = statut;
    if (q != null && q.isNotEmpty) params['q'] = q;
    return List<dynamic>.from(_ensureSuccess(await _get('/clients', query: params)) ?? []);
  }

  static Future<List<dynamic>> rechercherClients(String query) async =>
      List<dynamic>.from(_ensureSuccess(await _get('/clients/recherche', query: {'q': query})) ?? []);

  static Future<Map<String, dynamic>> creerClient(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/clients', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> mettreAJourClient(String id, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/clients/$id', body: data)));

  // COMMANDES
  static Future<List<dynamic>> getCommandes() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/commandes')) ?? []);

  static Future<Map<String, dynamic>> creerCommande(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/commandes', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> mettreAJourCommande(String id, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/commandes/$id', body: data)));

  static Future<Map<String, dynamic>> mettreAJourStatutCommande(String id, String statut) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/commandes/$id/statut', body: {'statut': statut})));

  static Future<Map<String, dynamic>> ajouterCommentaireCommande(String commandeId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/commandes/$commandeId/commentaires', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> ajouterLivraisonCommande(String commandeId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/commandes/$commandeId/livraisons', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> mettreAJourLivraisonCommande(String commandeId, String livraisonId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/commandes/$commandeId/livraisons/$livraisonId', body: data)));

  static Future<Map<String, dynamic>> getHistoriqueCommande(String commandeId) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _get('/commandes/historique/$commandeId')));

  // TRESORERIE / FINANCE
  static Future<Map<String, dynamic>> getSoldeTresorerie() async =>
      Map<String, dynamic>.from(_ensureSuccess(await _get('/finance/solde')));

    static Future<List<dynamic>> getMouvementsTresorerie({
        int limit = 200,
        String? period,
        String? source,
        List<String>? sources,
        List<int>? weekdays,
        int? month,
        int? year,
        DateTime? dateFrom,
        DateTime? dateTo,
    }) async {
        final query = <String, String>{'limit': '$limit'};
        if (period != null && period.isNotEmpty) query['period'] = period;
        if (source != null && source.isNotEmpty) query['source'] = source;
        if (sources != null && sources.isNotEmpty) query['sources'] = sources.join(',');
        if (weekdays != null && weekdays.isNotEmpty) query['weekdays'] = weekdays.join(',');
        if (month != null && month >= 1 && month <= 12) query['month'] = '$month';
        if (year != null && year > 0) query['year'] = '$year';
        if (dateFrom != null) query['dateFrom'] = dateFrom.toIso8601String();
        if (dateTo != null) query['dateTo'] = dateTo.toIso8601String();
        return List<dynamic>.from(_ensureSuccess(await _get('/finance/mouvements', query: query)) ?? []);
    }

  static Future<Map<String, dynamic>> creerDepenseTresorerie(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/finance/depenses', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> creerApprovisionnementTresorerie(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/finance/approvisionnements', body: data), accepted: const [201]));

    static Future<void> effacerHistoriqueMouvementsTresorerie() async {
        _ensureSuccess(await _delete('/finance/mouvements'));
    }

  // CRM
  static Future<Map<String, dynamic>> getCrmDashboard() async =>
      Map<String, dynamic>.from(_ensureSuccess(await _get('/crm/dashboard')));

  static Future<List<dynamic>> getInteractionsClient(String clientId) async =>
      List<dynamic>.from(_ensureSuccess(await _get('/crm/clients/$clientId/interactions')) ?? []);

  static Future<Map<String, dynamic>> ajouterInteractionClient(String clientId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/crm/clients/$clientId/interactions', body: data), accepted: const [201]));

  static Future<List<dynamic>> getTachesCrm() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/crm/taches')) ?? []);

  static Future<Map<String, dynamic>> creerTacheCrm(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/crm/taches', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> mettreAJourTacheCrm(String id, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/crm/taches/$id', body: data)));

  static Future<void> supprimerTacheCrm(String id) async {
    _ensureSuccess(await _delete('/crm/taches/$id'));
  }

    static Future<void> effacerHistoriqueTachesCrm() async {
        _ensureSuccess(await _delete('/crm/taches/historique/all'));
    }

  // Dashboard / Reports
    static Future<Map<String, dynamic>> getGlobalDashboard({String period = 'mois', String? bandeId, String? batiment}) async =>
            Map<String, dynamic>.from(_ensureSuccess(await _get('/dashboard/global', query: {
                'period': period,
                if (bandeId != null && bandeId.isNotEmpty) 'bandeId': bandeId,
                if (batiment != null && batiment.isNotEmpty) 'batiment': batiment,
            })));

  static String getGlobalPdfReportUrl() => '$baseUrl/reports/global.pdf';
  static String getGlobalExcelReportUrl() => '$baseUrl/reports/global.xlsx';

  // AUTH
  static Future<Map<String, dynamic>> inscription(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/auth/inscription', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> connexion(String email, String motDePasse) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/auth/connexion', body: {'email': email, 'motDePasse': motDePasse})));

  static Future<Map<String, dynamic>> getProfil() async =>
      Map<String, dynamic>.from(_ensureSuccess(await _get('/auth/profil')));

  static Future<Map<String, dynamic>> updateProfil(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/auth/profil', body: data)));

  static Future<Map<String, dynamic>> changerMotDePasse(String actuel, String nouveau) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/auth/mot-de-passe', body: {
        'motDePasseActuel': actuel,
        'nouveauMotDePasse': nouveau,
      })));

  static Future<Map<String, dynamic>> demanderResetMotDePasse(String email) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/auth/mot-de-passe/oublie', body: {'email': email})));

  static Future<Map<String, dynamic>> reinitialiserMotDePasse(String token, String nouveau) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/auth/mot-de-passe/reinitialiser', body: {
        'token': token,
        'nouveauMotDePasse': nouveau,
      })));

  static Future<void> deconnexion() async {
    _ensureSuccess(await _post('/auth/deconnexion'));
  }

  // USERS ADMIN
  static Future<List<dynamic>> getUtilisateurs() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/users')) ?? []);

  static Future<Map<String, dynamic>> creerUtilisateur(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _post('/users', body: data), accepted: const [201]));

  static Future<Map<String, dynamic>> updateUtilisateur(String id, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/users/$id', body: data)));

  static Future<Map<String, dynamic>> activerUtilisateur(String id) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/users/$id/activer')));

  static Future<Map<String, dynamic>> desactiverUtilisateur(String id) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/users/$id/desactiver')));

  static Future<Map<String, dynamic>> resetMotDePasseUtilisateur(String id, {String? motDePasseTemporaire}) async =>
            Map<String, dynamic>.from(_ensureSuccess(await _put(
                '/users/$id/reset-password',
                body: motDePasseTemporaire == null ? {} : {'motDePasseTemporaire': motDePasseTemporaire},
            )));

  static Future<void> supprimerUtilisateur(String id) async {
    _ensureSuccess(await _delete('/users/$id'));
  }

  // CONFIG ADMIN
  static Future<Map<String, dynamic>> getConfig() async =>
      Map<String, dynamic>.from(_ensureSuccess(await _get('/config')));

  static Future<Map<String, dynamic>> updateConfig(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(_ensureSuccess(await _put('/config', body: data)));

  static Future<List<dynamic>> getAuditLogs() async =>
      List<dynamic>.from(_ensureSuccess(await _get('/config/audit')) ?? []);

    static Future<void> effacerAuditLogs() async {
        _ensureSuccess(await _delete('/config/audit'));
    }
}
