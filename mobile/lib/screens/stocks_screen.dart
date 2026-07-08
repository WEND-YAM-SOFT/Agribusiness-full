import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/stocks_provider.dart';
import '../models/stock.dart';

class StocksScreen extends StatefulWidget {
  const StocksScreen({super.key});

  @override
  State<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends State<StocksScreen> {
  double? _parseDecimal(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  DateTime _normalizePickedDate(DateTime picked, {DateTime? fallbackTime}) {
    final base = fallbackTime ?? DateTime.now();
    return DateTime(
      picked.year,
      picked.month,
      picked.day,
      base.hour,
      base.minute,
      base.second,
      base.millisecond,
      base.microsecond,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StocksProvider>().chargerStocks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Stocks'),
      ),
      body: Consumer<StocksProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.stocks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Aucun stock', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  Text('Ajoutez aliments, médicaments, etc.'),
                ],
              ),
            );
          }

          // Grouper par catégorie
          final Map<String, List<Stock>> parCategorie = {};
          for (var stock in provider.stocks) {
            parCategorie.putIfAbsent(stock.categorie, () => []).add(stock);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Alertes stock bas
              if (provider.stocks.any((s) => s.enAlerte == true))
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          '${provider.stocks.where((s) => s.enAlerte == true).length} produit(s) en stock bas',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),

              // Liste par catégorie
              ...parCategorie.entries.map((entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _categorieLabel(entry.key),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                    ),
                  ),
                  ...entry.value.map((stock) => _buildStockCard(stock)),
                ],
              )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAjouterStockDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau Stock'),
      ),
    );
  }

  Widget _buildStockCard(Stock stock) {
    final alerte = stock.enAlerte == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: alerte ? Colors.red.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: alerte ? Colors.red.shade100 : Colors.green.shade100,
          child: Icon(
            _categorieIcon(stock.categorie),
            color: alerte ? Colors.red : Colors.green.shade700,
          ),
        ),
        title: Text(stock.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${stock.quantiteActuelle} ${stock.unite} | Seuil: ${stock.seuilAlerte} ${stock.unite} | PU: ${stock.prixUnitaire.toStringAsFixed(0)} FCFA',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green),
              tooltip: 'Entrée',
              onPressed: () => _showMouvementDialog(stock, 'entree'),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.red),
              tooltip: 'Sortie',
              onPressed: () => _showMouvementDialog(stock, 'sortie'),
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.orange),
              tooltip: 'Ajustement',
              onPressed: () => _showMouvementDialog(stock, 'ajustement'),
            ),
            IconButton(
              icon: const Icon(Icons.history, color: Colors.blueGrey),
              tooltip: 'Historique',
              onPressed: () => _showHistoriqueDialog(stock),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Supprimer stock',
              onPressed: () => _confirmerSuppressionStock(stock),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmerSuppressionStock(Stock stock) async {
    if (stock.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce stock ?'),
        content: Text('Le stock "${stock.nom}" sera supprimé définitivement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final provider = context.read<StocksProvider>();
    final ok = await provider.supprimerStock(stock.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Stock supprimé'
              : (provider.lastError?.isNotEmpty == true ? provider.lastError! : 'Suppression impossible'),
        ),
      ),
    );
  }

  String _categorieLabel(String cat) {
    switch (cat) {
      case 'aliment': return 'Aliments';
      case 'medicament': return 'Médicaments';
      case 'vitamine': return 'Vitamines';
      case 'desinfectant': return 'Désinfectants';
      case 'materiel': return 'Matériel';
      default: return 'Autres';
    }
  }

  IconData _categorieIcon(String cat) {
    switch (cat) {
      case 'aliment': return Icons.restaurant;
      case 'medicament': return Icons.medication;
      case 'vitamine': return Icons.science;
      case 'desinfectant': return Icons.cleaning_services;
      case 'materiel': return Icons.build;
      default: return Icons.inventory;
    }
  }

  void _showMouvementDialog(Stock stock, String type) {
    final qteCtrl = TextEditingController();
    final motifCtrl = TextEditingController();
    final prixCtrl = TextEditingController(
      text: type == 'entree' || type == 'ajustement' ? stock.prixUnitaire.toStringAsFixed(0) : '',
    );
    DateTime dateMouvement = DateTime.now();

    Future<void> choisirDate(StateSetter setDialogState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: dateMouvement,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setDialogState(() => dateMouvement = _normalizePickedDate(picked, fallbackTime: dateMouvement));
      }
    }

    String titre;
    if (type == 'entree') {
      titre = 'Entrée de stock';
    } else if (type == 'sortie') {
      titre = 'Sortie de stock';
    } else {
      titre = 'Ajustement de stock';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(titre),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${stock.nom} (actuel: ${stock.quantiteActuelle} ${stock.unite})'),
              const SizedBox(height: 12),
              if (type != 'ajustement')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date *'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(dateMouvement)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => choisirDate(setDialogState),
                ),
              TextField(
                controller: qteCtrl,
                decoration: InputDecoration(
                  labelText: type == 'ajustement'
                      ? 'Nouvelle quantité (${stock.unite})'
                      : 'Quantité (${stock.unite})',
                ),
                keyboardType: TextInputType.number,
              ),
              if (type == 'entree' || type == 'ajustement')
                TextField(
                  controller: prixCtrl,
                  decoration: const InputDecoration(labelText: 'Prix unitaire (FCFA)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              TextField(controller: motifCtrl, decoration: const InputDecoration(labelText: 'Motif')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final qte = _parseDecimal(qteCtrl.text);
                final prixUnitaire = _parseDecimal(prixCtrl.text);
                if (stock.id == null) return;
                if (qte == null || qte < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Quantité invalide')),
                  );
                  return;
                }
                final provider = context.read<StocksProvider>();
                final ok = await provider.ajouterMouvement(stock.id!, {
                  'type': type,
                  'quantite': qte,
                  'motif': motifCtrl.text,
                  'date': (type == 'ajustement' ? DateTime.now() : dateMouvement).toIso8601String(),
                  if (prixUnitaire != null && prixUnitaire > 0) 'prixUnitaire': prixUnitaire,
                });
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Mouvement enregistré'
                          : (provider.lastError?.isNotEmpty == true
                              ? provider.lastError!
                              : 'Erreur lors de la mise à jour du stock'),
                    ),
                  ),
                );
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistoriqueDialog(Stock stock) {
    final rootContext = context;
    final mouvements = [...stock.mouvements]
      ..sort((a, b) => b.date.compareTo(a.date));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Historique - ${stock.nom}'),
        content: SizedBox(
          width: double.maxFinite,
          child: mouvements.isEmpty
              ? const Center(child: Text('Aucun mouvement enregistré'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: mouvements.length,
                  itemBuilder: (context, index) {
                    final m = mouvements[index];
                    final labelType = m.type == 'entree'
                        ? 'Entrée'
                        : m.type == 'sortie'
                            ? 'Sortie'
                            : m.type == 'ajustement'
                                ? 'Ajustement'
                                : 'Création';
                    return ListTile(
                      dense: true,
                      title: Text('$labelType • ${m.quantite.toStringAsFixed(2)} ${stock.unite}'),
                      subtitle: Text(
                        '${DateFormat('dd/MM/yyyy HH:mm').format(m.date)}\n${m.utilisateur}${m.coutUnitaire > 0 ? ' • ${m.coutUnitaire.toStringAsFixed(0)} FCFA/u' : ''}${m.motif.isNotEmpty ? ' • ${m.motif}' : ''}',
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
        actions: [
          if (stock.id != null)
            TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(rootContext);
                final navigator = Navigator.of(ctx);
                final ok = await rootContext.read<StocksProvider>().effacerHistorique(stock.id!);
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Historique effacé' : 'Suppression impossible')),
                );
                if (ok) {
                  navigator.pop();
                }
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Effacer historique'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  void _showAjouterStockDialog() {
    final nomCtrl = TextEditingController();
    final uniteCtrl = TextEditingController(text: 'kg');
    final seuilCtrl = TextEditingController();
    final prixCtrl = TextEditingController();
    String selectedCategorie = 'aliment';
    DateTime dateStock = DateTime.now();

    Future<void> choisirDateStock(StateSetter setDialogState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: dateStock,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setDialogState(() => dateStock = _normalizePickedDate(picked, fallbackTime: dateStock));
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouveau Stock'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nomCtrl, decoration: const InputDecoration(labelText: 'Nom du produit *')),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategorie,
                  items: const [
                    DropdownMenuItem(value: 'aliment', child: Text('Aliment')),
                    DropdownMenuItem(value: 'medicament', child: Text('Médicament')),
                    DropdownMenuItem(value: 'vitamine', child: Text('Vitamine')),
                    DropdownMenuItem(value: 'desinfectant', child: Text('Désinfectant')),
                    DropdownMenuItem(value: 'materiel', child: Text('Matériel')),
                    DropdownMenuItem(value: 'autre', child: Text('Autre')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedCategorie = v!),
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                ),
                TextField(controller: uniteCtrl, decoration: const InputDecoration(labelText: 'Unité (kg, litres, boîtes...)')),
                TextField(controller: seuilCtrl, decoration: const InputDecoration(labelText: 'Seuil d\'alerte'), keyboardType: TextInputType.number),
                TextField(controller: prixCtrl, decoration: const InputDecoration(labelText: 'Prix unitaire (FCFA)'), keyboardType: TextInputType.number),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date *'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(dateStock)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => choisirDateStock(setDialogState),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                final seuil = _parseDecimal(seuilCtrl.text) ?? 0;
                final prix = _parseDecimal(prixCtrl.text) ?? 0;
                if (nomCtrl.text.isEmpty) return;
                Navigator.pop(ctx);
                context.read<StocksProvider>().creerStock({
                  'nom': nomCtrl.text,
                  'categorie': selectedCategorie,
                  'unite': uniteCtrl.text,
                  'seuilAlerte': seuil,
                  'prixUnitaire': prix,
                  'date': dateStock.toIso8601String(),
                });
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }
}
