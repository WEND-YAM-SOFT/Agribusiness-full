import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/finance_provider.dart';
import '../utils/money_format.dart';
import '../widgets/iso_calendar_picker.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final TextEditingController _yearCtrl = TextEditingController();
  bool _showMouvements = false;

  double? _parseDecimal(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  static const List<Map<String, String>> _sourceOptions = [
    {'value': '', 'label': 'Tous les types'},
    {'value': 'approvisionnement', 'label': 'Approvisionnement'},
    {'value': 'depense', 'label': 'Depense'},
    {'value': 'vente', 'label': 'Vente'},
    {'value': 'stock_entree', 'label': 'Achat stock'},
    {'value': 'stock_sortie', 'label': 'Ancienne sortie stock'},
    {'value': 'correction', 'label': 'Correction'},
  ];

  static const List<Map<String, dynamic>> _monthOptions = [
    {'value': null, 'label': 'Tous les mois'},
    {'value': 1, 'label': 'Janvier'},
    {'value': 2, 'label': 'Fevrier'},
    {'value': 3, 'label': 'Mars'},
    {'value': 4, 'label': 'Avril'},
    {'value': 5, 'label': 'Mai'},
    {'value': 6, 'label': 'Juin'},
    {'value': 7, 'label': 'Juillet'},
    {'value': 8, 'label': 'Aout'},
    {'value': 9, 'label': 'Septembre'},
    {'value': 10, 'label': 'Octobre'},
    {'value': 11, 'label': 'Novembre'},
    {'value': 12, 'label': 'Decembre'},
  ];

  static const List<Map<String, dynamic>> _weekdayOptions = [
    {'value': 1, 'label': 'Lun'},
    {'value': 2, 'label': 'Mar'},
    {'value': 3, 'label': 'Mer'},
    {'value': 4, 'label': 'Jeu'},
    {'value': 5, 'label': 'Ven'},
    {'value': 6, 'label': 'Sam'},
    {'value': 7, 'label': 'Dim'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceProvider>().chargerTresorerie();
    });
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tresorerie / Finance')),
      body: Consumer<FinanceProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final solde = provider.solde;
          final totalEntrees = (solde['totalEntrees'] ?? 0) as num;
          final totalSorties = (solde['totalSorties'] ?? 0) as num;
          final soldeCaisse = (solde['soldeCaisse'] ?? 0) as num;

          return RefreshIndicator(
            onRefresh: provider.chargerTresorerie,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Solde de caisse', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Solde actuel: ${formatAmountFcfa(soldeCaisse)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('Total entrees: ${formatAmountFcfa(totalEntrees)}'),
                        Text('Total sorties: ${formatAmountFcfa(totalSorties)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showAjouterDepenseDialog,
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Ajouter depense'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showApprovisionnementDialog,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Approvisionner'),
                      ),
                    ),
                  ],
                ),
                if (provider.lastError != null && provider.lastError!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(provider.lastError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                _buildFiltresCard(provider),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Mouvements de tresorerie', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final financeProvider = context.read<FinanceProvider>();
                        final messenger = ScaffoldMessenger.of(context);
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Effacer l\'historique ?'),
                            content: const Text('Cette action supprimera tous les mouvements de trésorerie.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('Effacer'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true || !mounted) return;
                        final ok = await financeProvider.effacerHistoriqueMouvements();
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text(ok ? 'Historique effacé' : 'Suppression impossible')),
                        );
                      },
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text('Effacer historique'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  initiallyExpanded: _showMouvements,
                  onExpansionChanged: (expanded) => setState(() => _showMouvements = expanded),
                  leading: const Icon(Icons.history),
                  title: Text('Afficher historique (${provider.mouvements.length})'),
                  children: [
                    if (provider.mouvements.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Aucun mouvement enregistre')))
                    else
                      ...provider.mouvements.map(_buildMouvementTile),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFiltresCard(FinanceProvider provider) {
    final providerYear = provider.yearFilter;
    final targetYearText = providerYear?.toString() ?? '';
    if (_yearCtrl.text != targetYearText) {
      _yearCtrl.text = targetYearText;
    }

    final dateRangeLabel = (provider.dateFrom != null && provider.dateTo != null)
        ? '${DateFormat('dd/MM/yyyy').format(provider.dateFrom!)} - ${DateFormat('dd/MM/yyyy').format(provider.dateTo!)}'
        : 'Aucun intervalle';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtres mouvements', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Type de mouvement'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sourceOptions
                  .where((opt) => (opt['value'] ?? '').isNotEmpty)
                  .map((opt) {
                    final value = opt['value']!;
                    final selected = provider.sourceFilters.contains(value);
                    return FilterChip(
                      label: Text(opt['label'] ?? ''),
                      selected: selected,
                      onSelected: (_) => context.read<FinanceProvider>().toggleSourceFilter(value),
                    );
                  })
                  .toList(),
            ),
            const SizedBox(height: 8),
            const Text('Jours de la semaine'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _weekdayOptions.map((opt) {
                final value = opt['value'] as int;
                final selected = provider.weekdayFilters.contains(value);
                return FilterChip(
                  label: Text(opt['label'] as String),
                  selected: selected,
                  onSelected: (_) => context.read<FinanceProvider>().toggleWeekdayFilter(value),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: provider.monthFilter,
                    decoration: const InputDecoration(labelText: 'Mois'),
                    items: _monthOptions
                        .map(
                          (opt) => DropdownMenuItem<int?>(
                            value: opt['value'] as int?,
                            child: Text(opt['label'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => context.read<FinanceProvider>().setMonthFilter(v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Annee',
                      suffixIcon: IconButton(
                        onPressed: () {
                          _yearCtrl.clear();
                          context.read<FinanceProvider>().setYearFilter(null);
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    onSubmitted: (value) {
                      final parsed = int.tryParse(value.trim());
                      context.read<FinanceProvider>().setYearFilter(parsed);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Intervalle de date'),
              subtitle: Text(dateRangeLabel),
              trailing: const Icon(Icons.date_range),
              onTap: _showDateRangePicker,
            ),
            if (provider.dateFrom != null || provider.dateTo != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.read<FinanceProvider>().clearDateRange(),
                  icon: const Icon(Icons.clear),
                  label: const Text('Effacer intervalle'),
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => context.read<FinanceProvider>().clearAllFilters(),
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Reinitialiser filtres'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDateRangePicker() async {
    final provider = context.read<FinanceProvider>();
    final picked = await showIsoDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: provider.dateFrom != null && provider.dateTo != null
          ? DateTimeRange(start: provider.dateFrom!, end: provider.dateTo!)
          : null,
    );
    if (picked != null) {
      await provider.setDateRange(picked.start, picked.end);
    }
  }

  Widget _buildMouvementTile(Map<String, dynamic> m) {
    final date = m['date'] != null ? DateTime.tryParse(m['date'].toString()) : null;
    final formattedDate = date != null ? DateFormat('dd/MM/yyyy HH:mm').format(date) : '-';
    final nature = (m['nature'] ?? '').toString();
    final isEntree = nature == 'entree';
    final montant = (m['montant'] ?? 0) as num;
    final quiPrenom = (m['quiPrenom'] ?? '').toString();
    final quiNom = (m['quiNom'] ?? '').toString();
    final source = (m['source'] ?? '').toString();
    final categorie = (m['categorie'] ?? '').toString();
    final type = (m['type'] ?? '').toString();
    final commentaire = (m['commentaire'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(isEntree ? Icons.call_received : Icons.call_made, color: isEntree ? Colors.green : Colors.red),
        title: Text('${isEntree ? 'Entree' : 'Sortie'}: ${formatAmountFcfa(montant)}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$formattedDate • $quiPrenom $quiNom'),
            Text('Source: $source • Categorie: $categorie • Type: $type'),
            if (commentaire.isNotEmpty) Text(commentaire, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  void _showAjouterDepenseDialog() {
    final quiNomCtrl = TextEditingController();
    final quiPrenomCtrl = TextEditingController();
    final categorieCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final montantCtrl = TextEditingController();
    final commentaireCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nouvelle depense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: quiPrenomCtrl, decoration: const InputDecoration(labelText: 'Prenom *')),
                TextField(controller: quiNomCtrl, decoration: const InputDecoration(labelText: 'Nom *')),
                TextField(controller: categorieCtrl, decoration: const InputDecoration(labelText: 'Categorie *')),
                TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Type *')),
                TextField(controller: montantCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Montant *')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showIsoDatePicker(
                      context: dialogContext,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                TextField(controller: commentaireCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Commentaire')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(dialogContext);
                final montant = _parseDecimal(montantCtrl.text) ?? 0;
                if (quiNomCtrl.text.trim().isEmpty ||
                    quiPrenomCtrl.text.trim().isEmpty ||
                    categorieCtrl.text.trim().isEmpty ||
                    typeCtrl.text.trim().isEmpty ||
                    montant <= 0) {
                  messenger.showSnackBar(const SnackBar(content: Text('Renseigne tous les champs obligatoires (*)')));
                  return;
                }
                final ok = await context.read<FinanceProvider>().ajouterDepense({
                  'quiNom': quiNomCtrl.text.trim(),
                  'quiPrenom': quiPrenomCtrl.text.trim(),
                  'categorie': categorieCtrl.text.trim(),
                  'type': typeCtrl.text.trim(),
                  'montant': montant,
                  'date': selectedDate.toIso8601String(),
                  'commentaire': commentaireCtrl.text.trim(),
                });
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Depense enregistree' : 'Erreur enregistrement depense')),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showApprovisionnementDialog() {
    final quiNomCtrl = TextEditingController();
    final quiPrenomCtrl = TextEditingController();
    final montantCtrl = TextEditingController();
    final commentaireCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Approvisionnement caisse'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: quiPrenomCtrl, decoration: const InputDecoration(labelText: 'Prenom *')),
                TextField(controller: quiNomCtrl, decoration: const InputDecoration(labelText: 'Nom *')),
                TextField(controller: montantCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Montant *')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showIsoDatePicker(
                      context: dialogContext,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                TextField(controller: commentaireCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Commentaire')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(dialogContext);
                final montant = _parseDecimal(montantCtrl.text) ?? 0;
                if (quiNomCtrl.text.trim().isEmpty || quiPrenomCtrl.text.trim().isEmpty || montant <= 0) {
                  messenger.showSnackBar(const SnackBar(content: Text('Renseigne tous les champs obligatoires (*)')));
                  return;
                }
                final ok = await context.read<FinanceProvider>().ajouterApprovisionnement({
                  'quiNom': quiNomCtrl.text.trim(),
                  'quiPrenom': quiPrenomCtrl.text.trim(),
                  'montant': montant,
                  'date': selectedDate.toIso8601String(),
                  'commentaire': commentaireCtrl.text.trim(),
                });
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Approvisionnement enregistre' : 'Erreur enregistrement approvisionnement')),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
