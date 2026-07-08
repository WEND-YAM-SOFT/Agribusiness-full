import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/alertes_provider.dart';
import '../models/alerte.dart';

class AlertesScreen extends StatefulWidget {
  const AlertesScreen({super.key});

  @override
  State<AlertesScreen> createState() => _AlertesScreenState();
}

class _AlertesScreenState extends State<AlertesScreen> {
  int _tabIndex = 0;
  bool _showTodoHistory = false;
  bool _showAutomaticHistory = false;

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

          // Séparer les alertes en retard
          final maintenant = DateTime.now();
          final base = _tabIndex == 0 ? provider.alertes : provider.alertesAutomatiques;
          final historiqueTodo = provider.historiqueAlertes;
          final historiqueAuto = provider.historiqueAlertesAutomatiques;
          final historique = _tabIndex == 0 ? historiqueTodo : historiqueAuto;
          final enRetard = base.where((a) => a.dateEcheance.isBefore(maintenant)).toList();
          final aVenir = base.where((a) => !a.dateEcheance.isBefore(maintenant)).toList();
          final isEmpty = base.isEmpty && historique.isEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todo list'),
                    selected: _tabIndex == 0,
                    onSelected: (_) => setState(() => _tabIndex = 0),
                  ),
                  ChoiceChip(
                    label: const Text('Alertes automatiques'),
                    selected: _tabIndex == 1,
                    onSelected: (_) => setState(() => _tabIndex = 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_tabIndex == 0)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _periodChip(provider, 'today', 'Ma journée'),
                    _periodChip(provider, 'week', 'Cette semaine'),
                    _periodChip(provider, 'month', 'Ce mois'),
                    _periodChip(provider, 'all', 'Toutes les tâches'),
                  ],
                ),
              if (_tabIndex == 0) const SizedBox(height: 12),
              if (_tabIndex == 0 && historiqueTodo.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<AlertesProvider>().effacerHistorique(),
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Effacer historique'),
                  ),
                ),
              if (_tabIndex == 0 && historiqueTodo.isNotEmpty) const SizedBox(height: 8),
              if (isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _tabIndex == 0 ? Icons.notifications_none : Icons.auto_awesome,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _tabIndex == 0 ? 'Aucune tâche active' : 'Aucune alerte automatique',
                          style: const TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _tabIndex = _tabIndex == 0 ? 1 : 0),
                          icon: Icon(_tabIndex == 0 ? Icons.auto_awesome : Icons.arrow_back),
                          label: Text(_tabIndex == 0 ? 'Voir alertes automatiques' : 'Retour à Todo list'),
                        ),
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
              if (_tabIndex == 0 && historiqueTodo.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  initiallyExpanded: _showTodoHistory,
                  onExpansionChanged: (expanded) => setState(() => _showTodoHistory = expanded),
                  leading: const Icon(Icons.history, color: Colors.blueGrey),
                  title: Text('Historique (${historiqueTodo.length})'),
                  children: [
                    ...historiqueTodo.map((a) => _buildAlerteCard(a, enRetard: false, allowComplete: false)),
                  ],
                ),
              ],
              if (_tabIndex == 1 && historiqueAuto.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  initiallyExpanded: _showAutomaticHistory,
                  onExpansionChanged: (expanded) => setState(() => _showAutomaticHistory = expanded),
                  leading: const Icon(Icons.history, color: Colors.blueGrey),
                  title: Text('Historique alertes automatiques (${historiqueAuto.length})'),
                  children: [
                    ...historiqueAuto.map((a) => _buildAlerteCard(a, enRetard: false, allowComplete: false)),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showAjouterAlerteDialog(),
              icon: const Icon(Icons.add_alert),
              label: const Text('Nouvelle tâche'),
            )
          : null,
    );
  }

  Widget _periodChip(AlertesProvider provider, String period, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: provider.todoPeriod == period,
      onSelected: (_) {
        provider.chargerAlertes(period: period);
      },
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
          ],
        ),
        trailing: allowComplete && alerte.id != null
          ? TextButton.icon(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            label: const Text('Tâche faite'),
                onPressed: () {
                  context.read<AlertesProvider>().marquerFaite(alerte);
                },
            )
            : null,
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
          title: const Text('Nouvelle Alerte'),
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
                    final date = await showDatePicker(
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
}
