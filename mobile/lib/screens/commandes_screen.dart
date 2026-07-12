import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/commandes_provider.dart';
import '../providers/clients_provider.dart';
import '../models/commande.dart';
import '../utils/money_format.dart';
import '../widgets/iso_calendar_picker.dart';

class CommandesScreen extends StatefulWidget {
  final bool embedded;
  const CommandesScreen({super.key, this.embedded = false});

  @override
  State<CommandesScreen> createState() => _CommandesScreenState();
}

class _CommandesScreenState extends State<CommandesScreen> {
  late final TextEditingController _searchController;
  bool _creatingOrder = false;
  bool _creatingClient = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CommandesProvider>();
      _searchController.text = provider.searchQuery;
      provider.chargerCommandes();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildContent();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commandes'),
      ),
      body: _buildContent(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNouvelleCommandeDialog(),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Nouvelle Commande'),
      ),
    );
  }

  Widget _buildContent() {
    return Consumer<CommandesProvider>(
      builder: (context, provider, child) {
        final commandes = provider.commandesFiltrees;
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_searchController.text != provider.searchQuery) {
          _searchController.value = _searchController.value.copyWith(
            text: provider.searchQuery,
            selection: TextSelection.collapsed(offset: provider.searchQuery.length),
            composing: TextRange.empty,
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: provider.rechercher,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Rechercher une commande',
                  hintText: 'Client, cycle, produit, montant, note...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Toutes'),
                    onPressed: provider.clearStatutsFilter,
                  ),
                  _statusChip(provider, 'en_attente', 'En attente'),
                  _statusChip(provider, 'confirmee', 'Confirmées'),
                  _statusChip(provider, 'en_preparation', 'En préparation'),
                  _statusChip(provider, 'payee', 'Payées'),
                  _statusChip(provider, 'annulee', 'Annulées'),
                ],
              ),
            ),
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _showNouvelleCommandeDialog,
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: const Text('Nouvelle commande'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: commandes.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Aucune commande', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: commandes.length,
                      itemBuilder: (context, index) {
                        return _buildCommandeCard(commandes[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusChip(CommandesProvider provider, String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: provider.isStatutSelected(value),
      onSelected: (_) => provider.toggleStatut(value),
    );
  }

  Widget _buildCommandeCard(Commande commande) {
    Color statutColor;
    String statutLabel;

    switch (commande.statut) {
      case 'en_attente':
        statutColor = Colors.orange;
        statutLabel = 'En attente';
        break;
      case 'confirmee':
        statutColor = Colors.blue;
        statutLabel = 'Confirmée';
        break;
      case 'en_preparation':
        statutColor = Colors.purple;
        statutLabel = 'En préparation';
        break;
      case 'livree':
        statutColor = Colors.purple;
        statutLabel = 'En préparation';
        break;
      case 'annulee':
        statutColor = Colors.red;
        statutLabel = 'Annulée';
        break;
      case 'payee':
        statutColor = Colors.teal;
        statutLabel = 'Payée';
        break;
      default:
        statutColor = Colors.grey;
        statutLabel = commande.statut;
    }

    final produitPrincipal = commande.produits.isNotEmpty ? commande.produits.first : null;
    final nomProduit = (produitPrincipal?.nom ?? 'Produit').toUpperCase();
    final quantiteTotale = commande.produits.fold<int>(0, (sum, p) => sum + p.quantite);
    final dateCommande = commande.createdAt != null
        ? DateFormat('dd/MM/yyyy').format(commande.createdAt!)
        : '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    nomProduit,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(statutLabel, style: TextStyle(color: statutColor)),
                  backgroundColor: statutColor.withValues(alpha: 0.1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${commande.clientNom.isNotEmpty ? commande.clientNom : 'Client'} • $dateCommande',
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Text(
              'Quantité: ${formatAmount(quantiteTotale)} | Montant: ${formatAmountFcfa(commande.montantTotal)}',
              style: const TextStyle(color: Colors.grey),
            ),
            if (commande.livraisons.isNotEmpty)
              Text('Livraisons: ${commande.livraisons.length}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                PopupMenuButton<String>(
                  onSelected: (statut) {
                    context.read<CommandesProvider>().mettreAJourStatut(commande.id!, statut);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'confirmee', child: Text('Confirmer')),
                    const PopupMenuItem(value: 'en_preparation', child: Text('En préparation')),
                    const PopupMenuItem(value: 'payee', child: Text('Payée')),
                    const PopupMenuItem(value: 'annulee', child: Text('Annuler')),
                  ],
                  child: const Chip(label: Text('Changer statut')),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showAjouterLivraisonDialog(commande),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  icon: const Icon(Icons.local_shipping, size: 16),
                  label: const Text('Livraisons'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showAjouterCommentaireCommandeDialog(commande.id!),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  icon: const Icon(Icons.comment, size: 16),
                  label: const Text('Commenter'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showModifierCommandeDialog(commande),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Modifier'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showNouvelleCommandeDialog() {
    final produitNomController = TextEditingController();
    final produitQteController = TextEditingController();
    final produitPrixController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle Commande'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Produit:', style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(controller: produitNomController, decoration: const InputDecoration(labelText: 'Nom du produit')),
              TextField(controller: produitQteController, decoration: const InputDecoration(labelText: 'Quantité'), keyboardType: TextInputType.number),
              TextField(controller: produitPrixController, decoration: const InputDecoration(labelText: 'Prix unitaire (FCFA)'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              if (produitNomController.text.isEmpty) return;
              final qte = int.tryParse(produitQteController.text) ?? 0;
              final prix = double.tryParse(produitPrixController.text) ?? 0;
              Navigator.pop(ctx);
              // Sélectionner un client avant de créer la commande
              _selectClientPourCommande(
                produitNomController.text,
                qte,
                prix,
              );
            },
            child: const Text('Suivant'),
          ),
        ],
      ),
    );
  }

  void _selectClientPourCommande(String produitNom, int quantite, double prix) {
    context.read<ClientsProvider>().chargerClients();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sélectionner un client'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Consumer<ClientsProvider>(
            builder: (context, provider, child) {
              if (provider.clients.isEmpty) {
                return const Center(child: Text('Aucun client disponible'));
              }
              return ListView.builder(
                itemCount: provider.clients.length,
                itemBuilder: (_, index) {
                  final client = provider.clients[index];
                  return ListTile(
                    title: Text(client.nomComplet),
                    subtitle: Text(client.telephone),
                    onTap: () async {
                      if (_creatingOrder) return;
                      setState(() => _creatingOrder = true);
                      Navigator.pop(ctx);
                      final montant = quantite * prix;
                      final ok = await context.read<CommandesProvider>().creerCommande({
                        'clientId': client.id,
                        'produits': [
                          {'nom': produitNom, 'quantite': quantite, 'prixUnitaire': prix}
                        ],
                        'montantTotal': montant,
                      });
                      if (mounted) setState(() => _creatingOrder = false);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'Commande créée' : 'Erreur création commande')),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final newClientId = await _showQuickAddClientDialog();
              if (!mounted) return;
              if (newClientId != null && newClientId.isNotEmpty) {
                final montant = quantite * prix;
                final ok = await context.read<CommandesProvider>().creerCommande({
                  'clientId': newClientId,
                  'produits': [
                    {'nom': produitNom, 'quantite': quantite, 'prixUnitaire': prix}
                  ],
                  'montantTotal': montant,
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Commande créée avec le nouveau client' : 'Client créé mais commande non enregistrée')),
                );
              } else {
                context.read<ClientsProvider>().chargerClients();
              }
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Nouveau client'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        ],
      ),
    );
  }

  Future<String?> _showQuickAddClientDialog() async {
    final rootContext = context;
    final prenom = TextEditingController();
    final nom = TextEditingController();
    final telephone = TextEditingController();
    final email = TextEditingController();
    final adresse = TextEditingController();
    final activite = TextEditingController();
    String typeClient = 'particulier';
    String? createdClientId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nouveau client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: prenom, decoration: const InputDecoration(labelText: 'Prénom *')),
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom *')),
                TextField(controller: telephone, decoration: const InputDecoration(labelText: 'Téléphone *')),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: adresse, decoration: const InputDecoration(labelText: 'Adresse *')),
                DropdownButtonFormField<String>(
                  initialValue: typeClient,
                  items: const [
                    DropdownMenuItem(value: 'particulier', child: Text('Particulier')),
                    DropdownMenuItem(value: 'pro', child: Text('Professionnel (Pro)')),
                  ],
                  onChanged: (v) => setDialogState(() => typeClient = v ?? 'particulier'),
                  decoration: const InputDecoration(labelText: 'Type client *'),
                ),
                TextField(
                  controller: activite,
                  decoration: const InputDecoration(labelText: 'Activité / commentaire *'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (_creatingClient) return;
                if (prenom.text.trim().isEmpty ||
                    nom.text.trim().isEmpty ||
                    telephone.text.trim().isEmpty ||
                    adresse.text.trim().isEmpty ||
                    activite.text.trim().isEmpty) {
                  return;
                }
                setState(() => _creatingClient = true);
                final clientsProvider = rootContext.read<ClientsProvider>();
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(rootContext);
                final newClientId = await clientsProvider.ajouterClientEtRetourId({
                  'prenom': prenom.text.trim(),
                  'nom': nom.text.trim(),
                  'telephone': telephone.text.trim(),
                  'email': email.text.trim(),
                  'adresse': adresse.text.trim(),
                  'typeClient': typeClient,
                  'commentaireActivite': activite.text.trim(),
                  'statut': 'prospect',
                });
                final ok = newClientId != null && newClientId.isNotEmpty;
                if (ok) {
                  createdClientId = newClientId;
                }
                if (mounted) setState(() => _creatingClient = false);
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Client ajouté' : 'Erreur création client')),
                );
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    return createdClientId;
  }

  void _showAjouterCommentaireCommandeDialog(String commandeId) {
    final commentaireController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Commentaire commande'),
        content: TextField(
          controller: commentaireController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Commentaire',
            hintText: 'Saisir un échange client...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              if (commentaireController.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              context.read<CommandesProvider>().ajouterCommentaire(commandeId, commentaireController.text.trim());
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _showModifierCommandeDialog(Commande commande) {
    final rootContext = context;
    final produitPrincipal = commande.produits.isNotEmpty ? commande.produits.first : null;
    final nomProduitCtrl = TextEditingController(text: produitPrincipal?.nom ?? '');
    final quantiteCtrl = TextEditingController(text: (produitPrincipal?.quantite ?? 0).toString());
    final prixCtrl = TextEditingController(text: (produitPrincipal?.prixUnitaire ?? 0).toStringAsFixed(0));
    final notesCtrl = TextEditingController(text: commande.notes);
    DateTime? dateLivraison = commande.dateLivraison;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Modifier commande'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomProduitCtrl,
                  decoration: const InputDecoration(labelText: 'Nom du produit *'),
                ),
                TextField(
                  controller: quantiteCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantité *'),
                ),
                TextField(
                  controller: prixCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Prix unitaire (FCFA) *'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date de livraison'),
                  subtitle: Text(dateLivraison == null ? '-' : DateFormat('dd/MM/yyyy').format(dateLivraison!)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showIsoDatePicker(
                      context: dialogContext,
                      initialDate: dateLivraison ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => dateLivraison = picked);
                    }
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setDialogState(() => dateLivraison = null),
                    icon: const Icon(Icons.clear),
                    label: const Text('Effacer la date'),
                  ),
                ),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(rootContext);
                final navigator = Navigator.of(dialogContext);

                final nomProduit = nomProduitCtrl.text.trim();
                final quantite = int.tryParse(quantiteCtrl.text.trim()) ?? 0;
                final prix = double.tryParse(prixCtrl.text.trim()) ?? 0;
                if (commande.id == null || commande.id!.isEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('Commande invalide')));
                  return;
                }
                if (nomProduit.isEmpty || quantite <= 0 || prix <= 0) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Renseigne un produit, une quantité et un prix valides')),
                  );
                  return;
                }

                final payload = {
                  'produits': [
                    {'nom': nomProduit, 'quantite': quantite, 'prixUnitaire': prix}
                  ],
                  'montantTotal': quantite * prix,
                  'dateLivraison': dateLivraison?.toIso8601String(),
                  'notes': notesCtrl.text.trim(),
                };

                final ok = await rootContext.read<CommandesProvider>().mettreAJourCommande(commande.id!, payload);
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Commande modifiée' : 'Erreur modification commande')),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAjouterLivraisonDialog(Commande commande) {
    DateTime datePrevue = DateTime.now();
    DateTime? dateReelle;
    String statut = 'planifiee';
    final fraisCtrl = TextEditingController();
    final commentairesCtrl = TextEditingController();

    Future<void> choisirDatePrevue(StateSetter setDialogState) async {
      final picked = await showIsoDatePicker(
        context: context,
        initialDate: datePrevue,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setDialogState(() => datePrevue = picked);
      }
    }

    Future<void> choisirDateReelle(StateSetter setDialogState) async {
      final picked = await showIsoDatePicker(
        context: context,
        initialDate: dateReelle ?? datePrevue,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setDialogState(() => dateReelle = picked);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter une livraison'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date livraison prévue *'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(datePrevue)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => choisirDatePrevue(setDialogState),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date livraison réelle'),
                  subtitle: Text(dateReelle == null ? '-' : DateFormat('dd/MM/yyyy').format(dateReelle!)),
                  trailing: const Icon(Icons.event_available),
                  onTap: () => choisirDateReelle(setDialogState),
                ),
                DropdownButtonFormField<String>(
                  initialValue: statut,
                  decoration: const InputDecoration(labelText: 'Statut livraison'),
                  items: const [
                    DropdownMenuItem(value: 'planifiee', child: Text('Planifiée')),
                    DropdownMenuItem(value: 'en_cours', child: Text('En cours')),
                    DropdownMenuItem(value: 'livree', child: Text('Livrée')),
                    DropdownMenuItem(value: 'annulee', child: Text('Annulée')),
                  ],
                  onChanged: (value) => setDialogState(() => statut = value ?? 'planifiee'),
                ),
                TextField(
                  controller: fraisCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Frais de livraison'),
                ),
                TextField(
                  controller: commentairesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Commentaires'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await context.read<CommandesProvider>().ajouterLivraison(commande.id!, {
                  'dateLivraisonPrevue': datePrevue.toIso8601String(),
                  'dateLivraisonReelle': dateReelle?.toIso8601String(),
                  'statutLivraison': statut,
                  'fraisLivraison': double.tryParse(fraisCtrl.text) ?? 0,
                  'commentaires': commentairesCtrl.text.trim(),
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
