import 'package:agribusiness/models/alerte.dart';
import 'package:agribusiness/models/bande.dart';
import 'package:agribusiness/models/stock.dart';
import 'package:agribusiness/providers/alertes_provider.dart';
import 'package:agribusiness/providers/stocks_provider.dart';
import 'package:agribusiness/screens/alertes_screen.dart';
import 'package:agribusiness/screens/roadmap_screen.dart';
import 'package:agribusiness/screens/stocks_screen.dart';
import 'package:agribusiness/screens/suivi_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStocksProvider extends StocksProvider {
  FakeStocksProvider({required List<Stock> stocks}) : _stocksState = List<Stock>.from(stocks);

  final List<Stock> _stocksState;
  int chargerStocksCalls = 0;
  final List<Map<String, dynamic>> ajouterMouvementCalls = [];
  final List<String> effacerHistoriqueCalls = [];

  @override
  List<Stock> get stocks => _stocksState;

  @override
  bool get isLoading => false;

  @override
  String? get lastError => null;

  @override
  Future<void> chargerStocks() async {
    chargerStocksCalls += 1;
  }

  @override
  Future<bool> ajouterMouvement(String stockId, Map<String, dynamic> data) async {
    ajouterMouvementCalls.add({'stockId': stockId, ...data});
    final index = _stocksState.indexWhere((stock) => stock.id == stockId);
    if (index == -1) return false;

    final current = _stocksState[index];
    final type = (data['type'] ?? '').toString();
    final quantite = (data['quantite'] as num).toDouble();
    final price = ((data['prixUnitaire'] ?? current.prixUnitaire) as num).toDouble();
    final movement = MouvementStock(
      id: 'mvt-${ajouterMouvementCalls.length}',
      date: DateTime.parse(data['date'].toString()),
      type: type,
      quantite: quantite,
      utilisateur: 'tester',
      motif: (data['motif'] ?? '').toString(),
      coutUnitaire: price,
    );

    var nextQty = current.quantiteActuelle;
    if (type == 'entree') nextQty += quantite;
    if (type == 'sortie') nextQty -= quantite;
    if (type == 'ajustement') nextQty = quantite;

    _stocksState[index] = Stock(
      id: current.id,
      nom: current.nom,
      categorie: current.categorie,
      unite: current.unite,
      quantiteActuelle: nextQty,
      seuilAlerte: current.seuilAlerte,
      prixUnitaire: price,
      fournisseur: current.fournisseur,
      emplacement: current.emplacement,
      dateExpiration: current.dateExpiration,
      dateCreationStock: current.dateCreationStock,
      enAlerte: current.enAlerte,
      notes: current.notes,
      mouvements: [...current.mouvements, movement],
    );
    notifyListeners();
    return true;
  }

  @override
  Future<bool> effacerHistorique(String stockId) async {
    effacerHistoriqueCalls.add(stockId);
    final index = _stocksState.indexWhere((stock) => stock.id == stockId);
    if (index == -1) return false;
    final current = _stocksState[index];
    _stocksState[index] = Stock(
      id: current.id,
      nom: current.nom,
      categorie: current.categorie,
      unite: current.unite,
      quantiteActuelle: current.quantiteActuelle,
      seuilAlerte: current.seuilAlerte,
      prixUnitaire: current.prixUnitaire,
      fournisseur: current.fournisseur,
      emplacement: current.emplacement,
      dateExpiration: current.dateExpiration,
      dateCreationStock: current.dateCreationStock,
      enAlerte: current.enAlerte,
      notes: current.notes,
      mouvements: const [],
    );
    notifyListeners();
    return true;
  }
}

class FakeAlertesProvider extends AlertesProvider {
  FakeAlertesProvider({
    required List<Alerte> alertes,
    required List<Alerte> alertesAutomatiques,
    required List<Alerte> historiqueAlertes,
    required List<Alerte> historiqueAlertesAutomatiques,
  })  : _alertesState = List<Alerte>.from(alertes),
        _alertesAutoState = List<Alerte>.from(alertesAutomatiques),
        _historiqueState = List<Alerte>.from(historiqueAlertes),
        _historiqueAutoState = List<Alerte>.from(historiqueAlertesAutomatiques);

  final List<Alerte> _alertesState;
  final List<Alerte> _alertesAutoState;
  final List<Alerte> _historiqueState;
  final List<Alerte> _historiqueAutoState;
  int chargerAlertesCalls = 0;
  int chargerAlertesAutomatiquesCalls = 0;
  int chargerHistoriqueAlertesCalls = 0;
  int chargerHistoriqueAlertesAutomatiquesCalls = 0;
  int effacerHistoriqueCalls = 0;

  @override
  List<Alerte> get alertes => _alertesState;

  @override
  List<Alerte> get alertesAutomatiques => _alertesAutoState;

  @override
  List<Alerte> get historiqueAlertes => _historiqueState;

  @override
  List<Alerte> get historiqueAlertesAutomatiques => _historiqueAutoState;

  @override
  bool get isLoading => false;

  @override
  String get todoPeriod => 'all';

  @override
  Future<void> chargerAlertes({String? period}) async {
    chargerAlertesCalls += 1;
  }

  @override
  Future<void> chargerAlertesAutomatiques() async {
    chargerAlertesAutomatiquesCalls += 1;
  }

  @override
  Future<void> chargerHistoriqueAlertes() async {
    chargerHistoriqueAlertesCalls += 1;
  }

  @override
  Future<void> chargerHistoriqueAlertesAutomatiques() async {
    chargerHistoriqueAlertesAutomatiquesCalls += 1;
  }

  @override
  Future<bool> effacerHistorique() async {
    effacerHistoriqueCalls += 1;
    _historiqueState.clear();
    _historiqueAutoState.clear();
    notifyListeners();
    return true;
  }
}

Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  testWidgets('Stocks UI allows adding two movements and opening history', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = FakeStocksProvider(
      stocks: [
        Stock(
          id: 'stock-1',
          nom: 'Stock Test',
          categorie: 'aliment',
          unite: 'kg',
          quantiteActuelle: 10,
          seuilAlerte: 2,
          prixUnitaire: 1000,
          notes: 'test',
          mouvements: [
            MouvementStock(
              id: 'initial',
              date: DateTime(2026, 7, 12, 8, 0),
              type: 'creation',
              quantite: 10,
              utilisateur: 'tester',
              motif: 'stock initial',
              coutUnitaire: 1000,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<StocksProvider>.value(
        value: provider,
        child: _wrapWithMaterialApp(const StocksScreen()),
      ),
    );
    await tester.pump();

    expect(provider.chargerStocksCalls, 1);
    expect(find.text('Stock Test'), findsOneWidget);

    await tester.tap(find.byTooltip('Entrée'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '5');
    await tester.enterText(find.byType(TextField).at(1), '1000');
    await tester.enterText(find.byType(TextField).at(2), 'entree 1');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sortie'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), 'sortie 1');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(provider.ajouterMouvementCalls.length, 2);

    await tester.tap(find.byTooltip('Historique'));
    await tester.pumpAndSettle();

    expect(find.text('Historique - Stock Test'), findsOneWidget);
    expect(find.textContaining('entree 1'), findsOneWidget);
    expect(find.textContaining('sortie 1'), findsOneWidget);
  });

  testWidgets('Todo UI triggers clear history and includes manual plus automatic history', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = FakeAlertesProvider(
      alertes: const [],
      alertesAutomatiques: const [],
      historiqueAlertes: [
        Alerte(
          id: 'hist-1',
          titre: 'Historique manuel',
          message: 'Manuel',
          type: 'autre',
          dateEcheance: DateTime(2026, 7, 10),
          statut: 'faite',
        ),
      ],
      historiqueAlertesAutomatiques: [
        Alerte(
          id: 'hist-auto-1',
          titre: 'Historique auto',
          message: 'Auto',
          type: 'stock_bas',
          dateEcheance: DateTime(2026, 7, 11),
          statut: 'faite',
          automatique: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AlertesProvider>.value(
        value: provider,
        child: _wrapWithMaterialApp(const AlertesScreen()),
      ),
    );
    await tester.pump();

    expect(provider.chargerAlertesCalls, 1);
    expect(provider.chargerAlertesAutomatiquesCalls, 1);
    expect(provider.chargerHistoriqueAlertesCalls, 1);
    expect(provider.chargerHistoriqueAlertesAutomatiquesCalls, 1);

    expect(find.text('Effacer historique'), findsOneWidget);
    expect(find.text('Historique (2)'), findsOneWidget);

    await tester.tap(find.text('Effacer historique'));
    await tester.pumpAndSettle();

    expect(provider.effacerHistoriqueCalls, 1);
    expect(find.text('Historique (2)'), findsNothing);
  });

  testWidgets('Todo UI does not overflow on small screens', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = FakeAlertesProvider(
      alertes: [
        Alerte(
          id: 'todo-active-1',
          titre: 'Tache active longue',
          message: 'Message long pour verifier le rendu sur petit ecran',
          type: 'autre',
          dateEcheance: DateTime(2026, 7, 13),
          priorite: 'haute',
        ),
      ],
      alertesAutomatiques: const [],
      historiqueAlertes: const [],
      historiqueAlertesAutomatiques: const [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AlertesProvider>.value(
        value: provider,
        child: _wrapWithMaterialApp(const AlertesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tache active longue'), findsOneWidget);
    expect(find.text('Tâche faite'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Roadmap gantt bars align with month header cells', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'roadmap.productionPlans': '''[
        {
          "id": "plan-1",
          "name": "Plan test",
          "start": "2026-01-01T00:00:00.000",
          "end": "2026-03-31T00:00:00.000",
          "tasks": [
            {
              "id": "task-1",
              "title": "Tache Q1",
              "start": "2026-01-01T00:00:00.000",
              "end": "2026-03-31T00:00:00.000",
              "color": 4278190335,
              "group": false,
              "milestones": [],
              "subTasks": []
            }
          ],
          "highlightedDates": []
        }
      ]''',
      'roadmap.selectedPlanId': 'plan-1',
    });

    await tester.pumpWidget(const MaterialApp(home: RoadmapScreen()));
    await tester.pumpAndSettle();

    final jan = find.byKey(const ValueKey('roadmap-month-2026-1'));
    final feb = find.byKey(const ValueKey('roadmap-month-2026-2'));
    final mar = find.byKey(const ValueKey('roadmap-month-2026-3'));
    final headerTimeline = find.byKey(const ValueKey('roadmap-header-timeline'));
    final taskTimeline = find.byKey(const ValueKey('roadmap-task-timeline-task-1'));
    final bar = find.byKey(const ValueKey('roadmap-bar-task-1'));

    expect(jan, findsOneWidget);
    expect(feb, findsOneWidget);
    expect(mar, findsOneWidget);
    expect(headerTimeline, findsOneWidget);
    expect(taskTimeline, findsOneWidget);
    expect(bar, findsOneWidget);

    final janRect = tester.getRect(jan);
    final febRect = tester.getRect(feb);
    final marRect = tester.getRect(mar);
    final headerTimelineRect = tester.getRect(headerTimeline);
    final taskTimelineRect = tester.getRect(taskTimeline);
    final barRect = tester.getRect(bar);

    expect((janRect.width - febRect.width).abs(), lessThan(0.1));
    expect((febRect.width - marRect.width).abs(), lessThan(0.1));
    expect((headerTimelineRect.width - taskTimelineRect.width).abs(), lessThan(0.1));
    expect((barRect.left - taskTimelineRect.left).abs(), lessThan(0.1));
    expect((barRect.right - taskTimelineRect.right).abs(), lessThan(0.1));
    expect((barRect.width - (janRect.width + febRect.width + marRect.width)).abs(), lessThan(0.2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Roadmap UI can create a planning', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: RoadmapScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Créez votre premier planning'), findsOneWidget);

    await tester.tap(find.byTooltip('Nouveau planning'));
    await tester.pumpAndSettle();

    expect(find.text('Nouveau planning macro'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Planning Test UI');

    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();

    expect(find.text('Planning Test UI'), findsWidgets);
    expect(find.textContaining('Macro planning mensuel'), findsOneWidget);
  });

  testWidgets('Suivi day form refreshes selected date immediately', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bande = Bande(
      id: 'bande-1',
      nom: 'Cycle test',
      dateOuverture: DateTime(2026, 7, 1),
      typeVolaille: 'poulet_chair',
      race: 'Cobb',
      nombreInitial: 100,
      nombreActuel: 100,
    );

    await tester.pumpWidget(MaterialApp(home: SuiviScreen(bande: bande)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ouvrir formulaire suivi jour'));
    await tester.pumpAndSettle();

    expect(find.text('13/07/2026'), findsOneWidget);

    await tester.tap(find.text('Date du suivi'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(find.text('15/07/2026'), findsOneWidget);
    expect(find.text('Formulaire suivi du jour'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
