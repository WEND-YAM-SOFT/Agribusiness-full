import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/bandes_provider.dart';
import '../models/bande.dart';
import '../services/api_service.dart';
import 'poids_screen.dart';
import 'climat_screen.dart';
import '../widgets/iso_calendar_picker.dart';

class SuiviScreen extends StatefulWidget {
  final Bande bande;
  const SuiviScreen({super.key, required this.bande});

  @override
  State<SuiviScreen> createState() => _SuiviScreenState();
}

class _SuiviScreenState extends State<SuiviScreen> {
  final TextEditingController _alimentationCtrl = TextEditingController();
  final TextEditingController _mortaliteCtrl = TextEditingController(text: '0');
  final TextEditingController _eauCtrl = TextEditingController();
  final TextEditingController _obsCtrl = TextEditingController();
  DateTime _dateSuivi = DateTime.now();
  List<Map<String, dynamic>> _stocksAliment = [];
  List<Map<String, dynamic>> _stocksProphylaxie = [];
  String? _selectedAlimentStockId;
  bool _showSuiviForm = false;

  Map<String, dynamic>? _dashboardData;
  bool _loadingForecast = true;
  List<EvenementPrevisionnel> _eventsPrevisionnels = [];
  bool _loadingEvents = true;

  @override
  void initState() {
    super.initState();
    _loadForecast();
    _loadEvents();
    _loadStocks();
  }

  @override
  void dispose() {
    _alimentationCtrl.dispose();
    _mortaliteCtrl.dispose();
    _eauCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStocks() async {
    try {
      final data = await ApiService.getStocks();
      if (!mounted) return;

      final normalized = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final aliments = normalized.where((s) => (s['categorie'] ?? '').toString() == 'aliment').toList();
      final prophylaxie = normalized
          .where((s) => (s['categorie'] ?? '').toString() != 'aliment' && (s['categorie'] ?? '').toString() != 'materiel')
          .toList();

      setState(() {
        _stocksAliment = aliments;
        _stocksProphylaxie = prophylaxie;
        if (_selectedAlimentStockId == null && _stocksAliment.isNotEmpty) {
          _selectedAlimentStockId = _stocksAliment.first['_id']?.toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stocksAliment = [];
        _stocksProphylaxie = [];
      });
    }
  }

  String _stockNameById(List<Map<String, dynamic>> list, String? id) {
    if (id == null || id.isEmpty) return '';
    for (final s in list) {
      if (s['_id']?.toString() == id) {
        return (s['nom'] ?? '').toString();
      }
    }
    return '';
  }

  Future<void> _loadForecast() async {
    try {
      final data = await ApiService.getSuiviDashboardBande(widget.bande.id!);
      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        _loadingForecast = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dashboardData = null;
        _loadingForecast = false;
      });
    }
  }

  Future<void> _loadEvents() async {
    try {
      final data = await ApiService.getEvenementsPrevisionnels(widget.bande.id!);
      if (!mounted) return;
      setState(() {
        _eventsPrevisionnels = data.map((e) => EvenementPrevisionnel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _loadingEvents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _eventsPrevisionnels = [];
        _loadingEvents = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final bande = widget.bande;

    return Scaffold(
      appBar: AppBar(
        title: Text('Suivi cycle - ${bande.nom}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_note),
            tooltip: 'Planifier événement',
            onPressed: _showPlanifierEvenementDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // RÉSUMÉ
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Résumé', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _statRow('Âge', '${bande.ageJours ?? _calcAge(bande)} jours'),
                    _statRow('Effectif actuel', '${bande.nombreActuel}'),
                    _statRow('Mortalité totale', '${bande.mortaliteTotale} (${bande.tauxMortalite ?? "0"}%)'),
                    _statRow('Race', bande.race),
                    _statRow('Type', _typeLabel(bande.typeVolaille)),
                    _statRow('Bâtiment', bande.batiment.isEmpty ? '-' : bande.batiment),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildForecastCard(),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PoidsScreen(bande: bande)));
                    },
                    icon: const Icon(Icons.monitor_weight),
                    label: const Text('Enregistrer prise de poids'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ClimatScreen(bande: bande)));
                    },
                    icon: const Icon(Icons.thermostat),
                    label: const Text('Température/Humidité'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showSuiviForm = !_showSuiviForm),
              icon: Icon(_showSuiviForm ? Icons.expand_less : Icons.edit_note),
              label: Text(_showSuiviForm ? 'Fermer formulaire suivi jour' : 'Ouvrir formulaire suivi jour'),
            ),
            const SizedBox(height: 16),

            if (_showSuiviForm) _buildFormSuiviDuJour(),
            const SizedBox(height: 20),

            _buildEventsPrevisionnels(),
            const SizedBox(height: 24),

            // SUIVI JOURNALIER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Suivi journalier', style: Theme.of(context).textTheme.titleMedium),
                Text('${bande.suiviJournalier.length} entrées', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            if (bande.suiviJournalier.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Aucun suivi enregistré', style: TextStyle(color: Colors.grey))),
                ),
              )
            else
              ...bande.suiviJournalier.reversed.map((suivi) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: Text('J${bande.suiviJournalier.indexOf(suivi) + 1}'),
                  ),
                  title: Text(dateFormat.format(suivi.date)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Poids: ${suivi.poidsMotenG}g | Alim: ${suivi.alimentationKg}kg | Eau: ${suivi.eauLitres}L'),
                      if (suivi.mortaliteJour > 0)
                        Text('Mortalité: ${suivi.mortaliteJour}', style: const TextStyle(color: Colors.red)),
                      if (suivi.observations.isNotEmpty)
                        Text(suivi.observations, style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                  ),
                  isThreeLine: true,
                ),
              )),

          ],
        ),
      ),
    );
  }

  Widget _buildFormSuiviDuJour() {
    final df = DateFormat('dd/MM/yyyy');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Formulaire "Suivi du jour"', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date du suivi'),
              subtitle: Text(df.format(_dateSuivi)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final d = await showIsoDatePicker(
                  context: context,
                  initialDate: _dateSuivi,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (d != null) setState(() => _dateSuivi = d);
              },
            ),
            TextField(
              controller: _alimentationCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Alimentation (kg) *'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _selectedAlimentStockId,
              items: _stocksAliment
                  .map(
                    (s) => DropdownMenuItem<String>(
                      value: s['_id']?.toString(),
                      child: Text('${s['nom']} (${s['quantiteActuelle']} ${s['unite']})'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedAlimentStockId = v),
              decoration: const InputDecoration(labelText: 'Type d\'alimentation *'),
            ),
            TextField(
              controller: _mortaliteCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Mortalité *'),
            ),
            TextField(
              controller: _obsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Observations *'),
            ),
            TextField(
              controller: _eauCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Eau (litres) (optionnel)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _enregistrerSuivi,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enregistrerSuivi() async {
    final alimentation = double.tryParse(_alimentationCtrl.text) ?? 0;
    final mortalite = int.tryParse(_mortaliteCtrl.text) ?? -1;
    final observations = _obsCtrl.text.trim();
    if (alimentation <= 0 || mortalite < 0 || observations.isEmpty || _selectedAlimentStockId == null || _selectedAlimentStockId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne les champs obligatoires du suivi du jour, y compris le type d\'alimentation')),
      );
      return;
    }
    final alimentationType = _stockNameById(_stocksAliment, _selectedAlimentStockId);

    final ok = await context.read<BandesProvider>().ajouterSuivi(widget.bande.id!, {
      'date': _dateSuivi.toIso8601String(),
      'alimentationKg': alimentation,
      'alimentationStockId': _selectedAlimentStockId,
      'alimentationType': alimentationType,
      'mortaliteJour': mortalite,
      'eauLitres': double.tryParse(_eauCtrl.text) ?? 0,
      'observations': observations,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Suivi du jour enregistré' : 'Erreur enregistrement suivi')),
    );
    if (ok) {
      _alimentationCtrl.clear();
      _mortaliteCtrl.text = '0';
      _eauCtrl.clear();
      _obsCtrl.clear();
      _loadStocks();
      _loadForecast();
    }
  }

  Widget _buildEventsPrevisionnels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Événements prévisionnels', style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(
              onPressed: _showPlanifierEvenementDialog,
              icon: const Icon(Icons.add_task),
              label: const Text('Planifier'),
            ),
          ],
        ),
        if (_loadingEvents)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_eventsPrevisionnels.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucun événement prévisionnel planifié'),
            ),
          )
        else
          ..._eventsPrevisionnels.map((evt) {
            final isDone = evt.statut == 'termine';
            final df = DateFormat('dd/MM/yyyy');
            return Card(
              child: ListTile(
                leading: Icon(
                  isDone ? Icons.check_circle : Icons.event,
                  color: isDone ? Colors.green : Colors.orange,
                ),
                title: Text(evt.description),
                subtitle: Text(
                  'Prévu le ${df.format(evt.datePrevue)} • ${evt.priorite}${evt.dateRealisation != null ? ' • Réalisé le ${df.format(evt.dateRealisation!)}' : ''}',
                ),
                trailing: isDone
                    ? const Chip(label: Text('Terminé'))
                    : TextButton(
                        onPressed: () => _terminerEvenement(evt),
                        child: const Text('Terminer'),
                      ),
              ),
            );
          }),
      ],
    );
  }

  void _showPlanifierEvenementDialog() {
    final descCtrl = TextEditingController();
    final comCtrl = TextEditingController();
    final prophylaxieQteCtrl = TextEditingController();
    String type = 'vaccination';
    String priorite = 'moyenne';
    DateTime datePrevue = DateTime.now().add(const Duration(days: 1));
    String? prophylaxieStockId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Planifier un événement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'vaccination', child: Text('Vaccination')),
                    DropdownMenuItem(value: 'traitement', child: Text('Traitement')),
                    DropdownMenuItem(value: 'controle_sanitaire', child: Text('Contrôle sanitaire')),
                    DropdownMenuItem(value: 'pesee', child: Text('Pesée')),
                    DropdownMenuItem(value: 'intervention_diverse', child: Text('Intervention diverse')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? 'vaccination'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date prévue'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(datePrevue)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showIsoDatePicker(
                      context: dialogContext,
                      initialDate: datePrevue,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setDialogState(() => datePrevue = d);
                  },
                ),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description *')),
                DropdownButtonFormField<String>(
                  initialValue: priorite,
                  decoration: const InputDecoration(labelText: 'Priorité'),
                  items: const [
                    DropdownMenuItem(value: 'basse', child: Text('Basse')),
                    DropdownMenuItem(value: 'moyenne', child: Text('Moyenne')),
                    DropdownMenuItem(value: 'haute', child: Text('Haute')),
                    DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                  ],
                  onChanged: (v) => setDialogState(() => priorite = v ?? 'moyenne'),
                ),
                TextField(
                  controller: comCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Commentaires'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: prophylaxieStockId,
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('Aucun consommable prophylaxie')),
                    ..._stocksProphylaxie.map(
                      (s) => DropdownMenuItem<String>(
                        value: s['_id']?.toString(),
                        child: Text('${s['nom']} (${s['quantiteActuelle']} ${s['unite']})'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => prophylaxieStockId = (v == null || v.isEmpty) ? null : v),
                  decoration: const InputDecoration(labelText: 'Consommable prophylaxie lié (optionnel)'),
                ),
                TextField(
                  controller: prophylaxieQteCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantité prophylaxie prévue (optionnel)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (widget.bande.id == null || widget.bande.id!.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cycle introuvable, recharge la liste des cycles')),
                  );
                  return;
                }
                if (descCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Description obligatoire pour planifier un événement')),
                  );
                  return;
                }
                final prophylaxieQte = double.tryParse(prophylaxieQteCtrl.text.trim()) ?? 0;
                if (prophylaxieStockId != null && prophylaxieQte <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Renseigne une quantité prophylaxie > 0 ou enlève le consommable sélectionné')),
                  );
                  return;
                }
                if (prophylaxieStockId == null && prophylaxieQte > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sélectionne un consommable prophylaxie avant de saisir la quantité')),
                  );
                  return;
                }
                final provider = context.read<BandesProvider>();
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);
                final prophylaxieType = _stockNameById(_stocksProphylaxie, prophylaxieStockId);
                final ok = await provider.ajouterEvenementPrevisionnel(widget.bande.id!, {
                  'type': type,
                  'datePrevue': datePrevue.toIso8601String(),
                  'description': descCtrl.text.trim(),
                  'priorite': priorite,
                  'commentaires': comCtrl.text.trim(),
                  'prophylaxieStockId': prophylaxieStockId,
                  'prophylaxieType': prophylaxieType,
                  'prophylaxieQuantite': prophylaxieQte,
                });
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Événement planifié' : 'Erreur planification: ${provider.lastError ?? 'cause inconnue'}')),
                );
                if (ok) {
                  _loadEvents();
                }
              },
              child: const Text('Planifier'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _terminerEvenement(EvenementPrevisionnel evt) async {
    if (widget.bande.id == null || widget.bande.id!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cycle introuvable, recharge la liste des cycles')),
      );
      return;
    }
    if (evt.id == null || evt.id!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Événement invalide, recharge les événements prévisionnels')),
      );
      return;
    }

    final commentaireCtrl = TextEditingController();
    String? prophylaxieStockId = evt.prophylaxieStockId;
    final prophylaxieQteCtrl = TextEditingController(
      text: evt.prophylaxieQuantite > 0 ? evt.prophylaxieQuantite.toString() : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Marquer comme terminé'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: commentaireCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Commentaires de réalisation'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: prophylaxieStockId,
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('Aucun consommable prophylaxie')),
                    ..._stocksProphylaxie.map(
                      (s) => DropdownMenuItem<String>(
                        value: s['_id']?.toString(),
                        child: Text('${s['nom']} (${s['quantiteActuelle']} ${s['unite']})'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => prophylaxieStockId = (v == null || v.isEmpty) ? null : v),
                  decoration: const InputDecoration(labelText: 'Consommable prophylaxie utilisé (optionnel)'),
                ),
                TextField(
                  controller: prophylaxieQteCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantité prophylaxie consommée (optionnel)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final prophylaxieQte = double.tryParse(prophylaxieQteCtrl.text.trim()) ?? 0;
                if (prophylaxieStockId != null && prophylaxieQte <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Renseigne une quantité prophylaxie > 0 ou enlève le consommable sélectionné')),
                  );
                  return;
                }
                if (prophylaxieStockId == null && prophylaxieQte > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sélectionne un consommable prophylaxie avant de saisir la quantité')),
                  );
                  return;
                }

                final provider = context.read<BandesProvider>();
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final ok = await provider.terminerEvenementPrevisionnel(
                      widget.bande.id!,
                      evt.id!,
                      commentairesRealisation: commentaireCtrl.text.trim(),
                      prophylaxieStockId: prophylaxieStockId,
                      prophylaxieType: _stockNameById(_stocksProphylaxie, prophylaxieStockId),
                      prophylaxieQuantite: prophylaxieQte,
                    );
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Événement terminé' : 'Erreur mise à jour événement: ${provider.lastError ?? 'cause inconnue'}')),
                );
                if (ok) {
                  _loadEvents();
                  _loadStocks();
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastCard() {
    if (_loadingForecast) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Chargement du prévisionnel...'),
            ],
          ),
        ),
      );
    }

    final forecast = (_dashboardData?['forecast7j'] as List<dynamic>?) ?? const [];
    final events = (_dashboardData?['eventsPrevisionnels'] as List<dynamic>?) ?? const [];
    final horizon = forecast.isNotEmpty ? forecast.last as Map<String, dynamic> : null;
    final consoReelle = (_dashboardData?['conso'] as List<dynamic>?) ?? const [];
    final consoTheorique = (_dashboardData?['theoriqueConso'] as List<dynamic>?) ?? const [];
    final consoReelleCourante = consoReelle.isNotEmpty
        ? ((consoReelle.last as Map<String, dynamic>)['cumulKg'] as num?)?.toDouble() ?? 0
        : 0;
    final ageCourant = consoReelle.length;
    double consoTheoriqueCourante = 0;
    if (ageCourant > 0 && consoTheorique.isNotEmpty) {
      final row = consoTheorique.whereType<Map<String, dynamic>>().firstWhere(
            (e) => (e['age'] ?? 0) == ageCourant,
            orElse: () => consoTheorique.last as Map<String, dynamic>,
          );
      consoTheoriqueCourante = ((row['cumulKg'] ?? 0) as num).toDouble();
    }
    final ratioReelTheorique = consoTheoriqueCourante > 0
        ? consoReelleCourante / consoTheoriqueCourante
        : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prévisionnel 7 jours', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (horizon != null)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text('Poids projeté: ${_fmt(horizon['poidsProjete'])} g'),
                  Text('Conso cumulée: ${_fmt(horizon['consoCumulProjeteeKg'])} kg'),
                  Text('Mortalité/j: ${_fmt(horizon['mortaliteJourProjetee'])}'),
                ],
              )
            else
              const Text('Pas assez de données pour une prévision fiable.'),
            const SizedBox(height: 8),
            Text(
              'Conso cumulée réel/théorique: ${_fmt(consoReelleCourante)} / ${_fmt(consoTheoriqueCourante)} kg (ratio ${_fmt(ratioReelTheorique)})',
            ),
            if (events.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...events.map((evt) {
                final e = evt as Map<String, dynamic>;
                final sev = (e['severite'] ?? '').toString();
                final color = sev == 'haute' ? Colors.red : Colors.orange;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text((e['message'] ?? '').toString())),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(dynamic value, {int digits = 2}) {
    if (value is num) return value.toStringAsFixed(digits);
    return '0';
  }

  int _calcAge(Bande bande) {
    return DateTime.now().difference(bande.dateOuverture).inDays;
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'poulet_chair': return 'Poulet de chair';
      case 'poule_pondeuse': return 'Poule pondeuse';
      case 'dinde': return 'Dinde';
      case 'canard': return 'Canard';
      default: return type;
    }
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
