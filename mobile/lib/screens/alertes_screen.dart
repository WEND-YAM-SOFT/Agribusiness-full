import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/alertes_provider.dart';
import '../models/alerte.dart';
import '../widgets/iso_calendar_picker.dart';

class AlertesScreen extends StatefulWidget {
  const AlertesScreen({super.key});

  @override
  State<AlertesScreen> createState() => _AlertesScreenState();
}

class _AlertesScreenState extends State<AlertesScreen> {
  bool _showHistory = false;
  String _dateFilter = 'all';
  DateTime? _selectedDate;
  DateTimeRange? _selectedRange;

  static const List<Map<String, String>> _dateFilterOptions = [
    {'value': 'all', 'label': 'Toutes les dates'},
    {'value': 'tomorrow', 'label': 'Demain'},
    {'value': 'date', 'label': 'Date précise'},
    {'value': 'range', 'label': 'Intervalle'},
  ];

  static const List<Map<String, String>> _periodOptions = [
    {'value': 'today', 'label': 'Ma journée'},
    {'value': 'week', 'label': 'Cette semaine'},
    {'value': 'month', 'label': 'Ce mois'},
    {'value': 'all', 'label': 'Toutes les tâches'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertesProvider>().chargerAlertes(period: 'all');
      context.read<AlertesProvider>().chargerAlertesAutomatiques();
      context.read<AlertesProvider>().chargerHistoriqueAlertes();
      context.read<AlertesProvider>().chargerHistoriqueAlertesAutomatiques();
    });
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _matchesDateFilter(Alerte alerte) {
    final d = alerte.dateEcheance;
    if (_dateFilter == 'all') return true;
    if (_dateFilter == 'tomorrow') {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      return _sameDay(d, tomorrow);
    }
    if (_dateFilter == 'date' && _selectedDate != null) {
      return _sameDay(d, _selectedDate!);
    }
    if (_dateFilter == 'range' && _selectedRange != null) {
      final start = DateTime(_selectedRange!.start.year, _selectedRange!.start.month, _selectedRange!.start.day);
      final end = DateTime(_selectedRange!.end.year, _selectedRange!.end.month, _selectedRange!.end.day, 23, 59, 59);
      return !d.isBefore(start) && !d.isAfter(end);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todo list'),
      ),
      body: Consumer<AlertesProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final maintenant = DateTime.now();
          final base = [...provider.alertes, ...provider.alertesAutomatiques];
          final historique = [...provider.historiqueAlertes, ...provider.historiqueAlertesAutomatiques];
          final filtered = base.where(_matchesDateFilter).toList()
            ..sort((a, b) => a.dateEcheance.compareTo(b.dateEcheance));

          final enRetard = filtered.where((a) => a.dateEcheance.isBefore(maintenant)).toList();
          final aVenir = filtered.where((a) => !a.dateEcheance.isBefore(maintenant)).toList();
          final isEmpty = base.isEmpty && historique.isEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _dateFilter,
                decoration: const InputDecoration(
                  labelText: 'Filtre date',
                  border: OutlineInputBorder(),
                ),
                items: _dateFilterOptions
                    .map(
                      (opt) => DropdownMenuItem<String>(
                        value: opt['value'],
                        child: Text(opt['label'] ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  if (value == 'date') {
                    final picked = await showIsoDatePicker(
                      context: context,
                      initialDate: _selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                        _dateFilter = 'date';
                      });
                    }
                    return;
                  }
                  if (value == 'range') {
                    final picked = await showIsoDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDateRange: _selectedRange,
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedRange = picked;
                        _dateFilter = 'range';
                      });
                    }
                    return;
                  }
                  setState(() => _dateFilter = value);
                },
              ),
              if (_dateFilter == 'date' && _selectedDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}'),
                ),
              if (_dateFilter == 'range' && _selectedRange != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Du ${DateFormat('dd/MM').format(_selectedRange!.start)} au ${DateFormat('dd/MM').format(_selectedRange!.end)}'),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: provider.todoPeriod,
                decoration: const InputDecoration(
                  labelText: 'Période',
                  border: OutlineInputBorder(),
                ),
                items: _periodOptions
                    .map(
                      (opt) => DropdownMenuItem<String>(
                        value: opt['value'],
                        child: Text(opt['label'] ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null && value.isNotEmpty) {
                    provider.chargerAlertes(period: value);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (historique.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<AlertesProvider>().effacerHistorique(),
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Effacer historique'),
                  ),
                ),
              if (historique.isNotEmpty) const SizedBox(height: 8),
              if (isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('Aucune tâche active', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              if (enRetard.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.red),
                    const SizedBox(width: 8),
                    Text('En retard (${enRetard.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                  ],
                ),
                const SizedBox(height: 8),
                ...enRetard.map((a) => _buildAlerteCard(a, enRetard: true)),
                const SizedBox(height: 16),
              ],
              if (aVenir.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('À venir (${aVenir.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ...aVenir.map((a) => _buildAlerteCard(a, enRetard: false)),
              ],
              if (historique.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  initiallyExpanded: _showHistory,
                  onExpansionChanged: (expanded) => setState(() => _showHistory = expanded),
                  leading: const Icon(Icons.history, color: Colors.blueGrey),
                  title: Text('Historique (${historique.length})'),
                  children: [
                    ...historique.map((a) => _buildAlerteCard(a, enRetard: false, allowComplete: false)),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAjouterAlerteDialog(),
        icon: const Icon(Icons.add_alert),
        label: const Text('Nouvelle tâche'),
      ),
    );
  }

  Widget _buildAlerteCard(Alerte alerte, {required bool enRetard, bool allowComplete = true}) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    Color prioriteColor;
    switch (alerte.priorite) {
      case 'urgente': prioriteColor = Colors.red; break;
      case 'haute': prioriteColor = Colors.orange; break;
      case 'moyenne': prioriteColor = Colors.blue; break;
      default: prioriteColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: enRetard ? Colors.red.shade50 : null,
      child: ListTile(
        leading: Icon(
          _typeIcon(alerte.type),
          color: enRetard ? Colors.red : Colors.green,
        ),
        title: Text(alerte.titre, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(alerte.message),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(dateFormat.format(alerte.dateEcheance), style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Chip(
                  label: Text(alerte.priorite, style: TextStyle(fontSize: 11, color: prioriteColor)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: prioriteColor.withValues(alpha: 0.1),
                ),
              ],
            ),
            if (allowComplete && alerte.id != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showModifierAlerteDialog(alerte),
                    icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey),
                    label: const Text('Modifier'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      context.read<AlertesProvider>().marquerFaite(alerte);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Tâche faite'),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: null,
        isThreeLine: true,
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'vaccination': return Icons.vaccines;
      case 'alimentation': return Icons.restaurant;
      case 'stock_bas': return Icons.inventory;
      case 'vente': return Icons.sell;
      case 'medicament': return Icons.medication;
      case 'controle_sanitaire': return Icons.health_and_safety;
      case 'pesee': return Icons.monitor_weight;
      case 'intervention_diverse': return Icons.build_circle;
      default: return Icons.notifications;
    }
  }

  void _showAjouterAlerteDialog() {
    final titreCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    String selectedType = 'vaccination';
    String selectedPriorite = 'moyenne';
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle tâche'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titreCtrl, decoration: const InputDecoration(labelText: 'Titre *')),
                TextField(controller: messageCtrl, decoration: const InputDecoration(labelText: 'Message')),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'vaccination', child: Text('Vaccination')),
                    DropdownMenuItem(value: 'alimentation', child: Text('Alimentation')),
                    DropdownMenuItem(value: 'stock_bas', child: Text('Stock bas')),
                    DropdownMenuItem(value: 'vente', child: Text('Vente')),
                    DropdownMenuItem(value: 'medicament', child: Text('Médicament')),
                    DropdownMenuItem(value: 'autre', child: Text('Autre')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedType = v!),
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedPriorite,
                  items: const [
                    DropdownMenuItem(value: 'basse', child: Text('Basse')),
                    DropdownMenuItem(value: 'moyenne', child: Text('Moyenne')),
                    DropdownMenuItem(value: 'haute', child: Text('Haute')),
                    DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedPriorite = v!),
                  decoration: const InputDecoration(labelText: 'Priorité'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Date d\'échéance'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showIsoDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (titreCtrl.text.isEmpty) return;
                Navigator.pop(ctx);
                context.read<AlertesProvider>().creerAlerte({
                  'titre': titreCtrl.text,
                  'message': messageCtrl.text,
                  'type': selectedType,
                  'priorite': selectedPriorite,
                  'dateEcheance': selectedDate.toIso8601String(),
                });
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showModifierAlerteDialog(Alerte alerte) {
    if (alerte.id == null) return;

    final titreCtrl = TextEditingController(text: alerte.titre);
    final messageCtrl = TextEditingController(text: alerte.message);
    String selectedType = alerte.type;
    String selectedPriorite = alerte.priorite;
    DateTime selectedDate = alerte.dateEcheance;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier tâche'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titreCtrl, decoration: const InputDecoration(labelText: 'Titre *')),
                TextField(controller: messageCtrl, decoration: const InputDecoration(labelText: 'Message')),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'vaccination', child: Text('Vaccination')),
                    DropdownMenuItem(value: 'alimentation', child: Text('Alimentation')),
                    DropdownMenuItem(value: 'stock_bas', child: Text('Stock bas')),
                    DropdownMenuItem(value: 'vente', child: Text('Vente')),
                    DropdownMenuItem(value: 'medicament', child: Text('Médicament')),
                    DropdownMenuItem(value: 'autre', child: Text('Autre')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedType = v ?? selectedType),
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedPriorite,
                  items: const [
                    DropdownMenuItem(value: 'basse', child: Text('Basse')),
                    DropdownMenuItem(value: 'moyenne', child: Text('Moyenne')),
                    DropdownMenuItem(value: 'haute', child: Text('Haute')),
                    DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedPriorite = v ?? selectedPriorite),
                  decoration: const InputDecoration(labelText: 'Priorité'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Date d\'échéance'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showIsoDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (titreCtrl.text.trim().isEmpty) return;
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(this.context);
                final provider = context.read<AlertesProvider>();
                bool ok;
                if (alerte.automatique) {
                  // Automatic alerts are generated by rules; convert to a manual editable task.
                  ok = await provider.creerAlerte({
                    'titre': titreCtrl.text.trim(),
                    'message': messageCtrl.text.trim(),
                    'type': selectedType,
                    'priorite': selectedPriorite,
                    'dateEcheance': selectedDate.toIso8601String(),
                    'source': 'todo',
                    'automatique': false,
                  });
                  if (ok) {
                    await provider.marquerFaite(alerte);
                  }
                } else {
                  ok = await provider.mettreAJourAlerte(
                    alerte.id!,
                    {
                      'titre': titreCtrl.text.trim(),
                      'message': messageCtrl.text.trim(),
                      'type': selectedType,
                      'priorite': selectedPriorite,
                      'dateEcheance': selectedDate.toIso8601String(),
                    },
                  );
                }
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok
                      ? (alerte.automatique ? 'Alerte convertie en tâche modifiable' : 'Tâche modifiée')
                      : 'Erreur modification tâche')),
                );
              },
              child: Text(alerte.automatique ? 'Convertir en tâche' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
