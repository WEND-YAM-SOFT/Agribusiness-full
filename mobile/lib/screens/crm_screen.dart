import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../models/tache_crm.dart';
import '../providers/auth_provider.dart';
import '../providers/clients_provider.dart';
import '../providers/crm_provider.dart';
import 'commandes_screen.dart';
import '../utils/money_format.dart';
import '../widgets/iso_calendar_picker.dart';
import '../widgets/international_phone_field.dart';

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Client? selectedClient;
  bool _showRelanceHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialiserFiltresClients();
      context.read<CrmProvider>().chargerTachesCrm();
    });
  }

  Future<void> _initialiserFiltresClients() async {
    final provider = context.read<ClientsProvider>();
    await provider.ensureFiltresRestaures();
    if (!mounted) return;
    _searchController.text = provider.searchQuery;
    await provider.chargerClientsPourCrm();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Clients'),
            Tab(icon: Icon(Icons.forum_outlined), text: 'Interactions'),
            Tab(icon: Icon(Icons.task_alt_outlined), text: 'Relances'),
            Tab(icon: Icon(Icons.shopping_cart_outlined), text: 'Commandes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _clientsTab(),
          _interactionsTab(),
          _tachesTab(),
          const CommandesScreen(embedded: true),
        ],
      ),
    );
  }

  Widget _clientsTab() {
    return Consumer<ClientsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) return const Center(child: CircularProgressIndicator());

        final auth = context.watch<AuthProvider>();
        final role = (auth.user?['role'] ?? '').toString();
        final canDeleteClient = auth.hasPermission('clients.delete') || role == 'gestionnaire_ferme';

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher un client...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () async {
                      _searchController.clear();
                      await context.read<ClientsProvider>().viderRechercheCrm();
                    },
                  ),
                ),
                onChanged: (value) async {
                  await context.read<ClientsProvider>().rechercherClientsCrm(value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _filterButton('Tous', null),
                        _filterButton('Prospects', 'prospect'),
                        _filterButton('Actifs', 'actif'),
                        _filterButton('Inactifs', 'inactif'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showAjoutClient,
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Nouveau client'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: provider.clients.length,
                itemBuilder: (_, i) {
                  final c = provider.clients[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      title: Text(c.nomComplet),
                      subtitle: Text('${c.telephone} • ${c.statut}'),
                      trailing: SizedBox(
                        width: canDeleteClient ? 178 : 140,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(child: Text(formatAmountFcfa(c.chiffreAffairesCumul), overflow: TextOverflow.ellipsis)),
                            if (canDeleteClient)
                              IconButton(
                                tooltip: 'Supprimer client',
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () => _confirmDeleteClient(c),
                              ),
                            IconButton(
                              tooltip: 'Modifier client',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showModifierClient(c),
                            ),
                          ],
                        ),
                      ),
                      onTap: () {
                        setState(() => selectedClient = c);
                        _tabController.animateTo(1);
                        context.read<CrmProvider>().chargerInteractionsClient(c.id!);
                      },
                    ),
                  );
                },
              ),
            )
          ],
        );
      },
    );
  }

  void _showAjoutClient() {
    final rootContext = context;
    final prenom = TextEditingController();
    final nom = TextEditingController();
    final telephone = TextEditingController();
    final email = TextEditingController();
    final adresse = TextEditingController();
    final activite = TextEditingController();
    final entreprise = TextEditingController();
    String typeClient = 'particulier';
    String statut = 'prospect';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Nouveau client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: prenom, decoration: const InputDecoration(labelText: 'Prénom *')),
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom *')),
                InternationalPhoneField(controller: telephone, labelText: 'Téléphone *'),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: adresse, decoration: const InputDecoration(labelText: 'Adresse *')),
                DropdownButtonFormField<String>(
                  initialValue: typeClient,
                  items: const [
                    DropdownMenuItem(value: 'particulier', child: Text('Particulier')),
                    DropdownMenuItem(value: 'pro', child: Text('Professionnel (Pro)')),
                  ],
                  onChanged: (v) => setDialog(() => typeClient = v ?? 'particulier'),
                  decoration: const InputDecoration(labelText: 'Type client *'),
                ),
                TextField(
                  controller: activite,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Activité / commentaire *'),
                ),
                TextField(controller: entreprise, decoration: const InputDecoration(labelText: 'Entreprise')),
                DropdownButtonFormField<String>(
                  initialValue: statut,
                  items: const [
                    DropdownMenuItem(value: 'prospect', child: Text('Prospect')),
                    DropdownMenuItem(value: 'actif', child: Text('Actif')),
                    DropdownMenuItem(value: 'inactif', child: Text('Inactif')),
                  ],
                  onChanged: (v) => setDialog(() => statut = v ?? 'prospect'),
                  decoration: const InputDecoration(labelText: 'Statut'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (prenom.text.trim().isEmpty ||
                    nom.text.trim().isEmpty ||
                    adresse.text.trim().isEmpty ||
                    activite.text.trim().isEmpty) {
                  return;
                }
                if (!isValidInternationalPhone(telephone.text.trim())) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Téléphone invalide. Exemple: +221 77 12 34 56')),
                  );
                  return;
                }
                final clientsProvider = rootContext.read<ClientsProvider>();
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(rootContext);
                final ok = await clientsProvider.ajouterClient({
                  'prenom': prenom.text.trim(),
                  'nom': nom.text.trim(),
                  'telephone': telephone.text.trim(),
                  'email': email.text.trim(),
                  'adresse': adresse.text.trim(),
                  'typeClient': typeClient,
                  'commentaireActivite': activite.text.trim(),
                  'entreprise': entreprise.text.trim(),
                  'statut': statut,
                });
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Client ajouté' : 'Erreur lors de la création')),
                );
                if (ok) {
                  await clientsProvider.chargerClientsPourCrm();
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showModifierClient(Client client) {
    final rootContext = context;
    final prenom = TextEditingController(text: client.prenom);
    final nom = TextEditingController(text: client.nom);
    final telephone = TextEditingController(text: client.telephone);
    final email = TextEditingController(text: client.email);
    final adresse = TextEditingController(text: client.adresse);
    final activite = TextEditingController(text: client.commentaireActivite);
    final entreprise = TextEditingController(text: client.entreprise);
    String typeClient = client.typeClient;
    String statut = client.statut;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Modifier client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: prenom, decoration: const InputDecoration(labelText: 'Prénom *')),
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom *')),
                InternationalPhoneField(controller: telephone, labelText: 'Téléphone *'),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: adresse, decoration: const InputDecoration(labelText: 'Adresse *')),
                DropdownButtonFormField<String>(
                  initialValue: typeClient,
                  items: const [
                    DropdownMenuItem(value: 'particulier', child: Text('Particulier')),
                    DropdownMenuItem(value: 'pro', child: Text('Professionnel (Pro)')),
                  ],
                  onChanged: (v) => setDialog(() => typeClient = v ?? 'particulier'),
                  decoration: const InputDecoration(labelText: 'Type client *'),
                ),
                TextField(
                  controller: activite,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Activité / commentaire *'),
                ),
                TextField(controller: entreprise, decoration: const InputDecoration(labelText: 'Entreprise')),
                DropdownButtonFormField<String>(
                  initialValue: statut,
                  items: const [
                    DropdownMenuItem(value: 'prospect', child: Text('Prospect')),
                    DropdownMenuItem(value: 'actif', child: Text('Actif')),
                    DropdownMenuItem(value: 'inactif', child: Text('Inactif')),
                  ],
                  onChanged: (v) => setDialog(() => statut = v ?? 'prospect'),
                  decoration: const InputDecoration(labelText: 'Statut'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (prenom.text.trim().isEmpty ||
                    nom.text.trim().isEmpty ||
                    adresse.text.trim().isEmpty ||
                    activite.text.trim().isEmpty) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Renseigne tous les champs obligatoires (*)')),
                  );
                  return;
                }

                if (!isValidInternationalPhone(telephone.text.trim())) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Téléphone invalide. Exemple: +221 77 12 34 56')),
                  );
                  return;
                }

                final clientsProvider = rootContext.read<ClientsProvider>();
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(rootContext);
                final ok = await clientsProvider.mettreAJourClient(client.id!, {
                  'prenom': prenom.text.trim(),
                  'nom': nom.text.trim(),
                  'telephone': telephone.text.trim(),
                  'email': email.text.trim(),
                  'adresse': adresse.text.trim(),
                  'typeClient': typeClient,
                  'commentaireActivite': activite.text.trim(),
                  'entreprise': entreprise.text.trim(),
                  'statut': statut,
                });

                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Client modifié' : 'Erreur modification client')),
                );
                if (ok) {
                  await clientsProvider.chargerClientsPourCrm();
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteClient(Client client) async {
    final clientId = client.id;
    if (clientId == null || clientId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Client invalide, recharge la liste puis réessaie')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer client'),
        content: Text('Supprimer "${client.nomComplet}" ?'),
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
    if (ok != true || !mounted) return;

    final deleted = await context.read<ClientsProvider>().supprimerClient(clientId);
    if (!mounted) return;

    if (deleted && selectedClient?.id == clientId) {
      setState(() => selectedClient = null);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? 'Client supprimé' : 'Suppression client impossible')),
    );
  }

  Widget _interactionsTab() {
    if (selectedClient == null) {
      return const Center(child: Text('Sélectionnez un client depuis l’onglet Clients'));
    }

    return Consumer<CrmProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) return const Center(child: CircularProgressIndicator());

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Client: ${selectedClient!.nomComplet}'),
                        const SizedBox(height: 2),
                        Text(selectedClient!.telephone, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showAjoutInteraction,
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.add_comment, size: 18),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: provider.interactions.length,
                itemBuilder: (_, i) {
                  final it = provider.interactions[i];
                  return ListTile(
                    leading: const Icon(Icons.forum),
                    title: Text('${it.type.toUpperCase()} - ${it.sujet.isEmpty ? 'Interaction' : it.sujet}'),
                    subtitle: Text('${it.contenu}\nPar ${it.auteur}'),
                    isThreeLine: true,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tachesTab() {
    return Consumer<CrmProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) return const Center(child: CircularProgressIndicator());

        final tachesActives = provider.taches
            .where((t) => t.statut != 'terminee' && t.statut != 'annulee')
            .toList();
        final tachesHistorique = provider.taches
            .where((t) => t.statut == 'terminee' || t.statut == 'annulee')
            .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Tâches et relances commerciales')),
                  if (tachesHistorique.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => context.read<CrmProvider>().effacerHistoriqueTaches(),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      icon: const Icon(Icons.delete_sweep, size: 18),
                      label: const Text('Effacer historique'),
                    ),
                  if (tachesHistorique.isNotEmpty) const SizedBox(width: 8),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showAjoutTache,
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.add_task, size: 18),
                    label: const Text('Nouvelle tâche'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  ...tachesActives.map((t) => _buildTacheCard(t, historique: false)),
                  if (tachesHistorique.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: ExpansionTile(
                        initiallyExpanded: _showRelanceHistory,
                        onExpansionChanged: (expanded) => setState(() => _showRelanceHistory = expanded),
                        leading: const Icon(Icons.history, color: Colors.blueGrey),
                        title: Text('Historique (${tachesHistorique.length})'),
                        children: [
                          ...tachesHistorique.map((t) => _buildTacheCard(t, historique: true)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            )
          ],
        );
      },
    );
  }

  Widget _buildTacheCard(TacheCRM t, {required bool historique}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(t.titre),
        subtitle: Text(
          [
            if (t.clientNom.isNotEmpty) t.clientNom,
            t.type,
            t.priorite,
            t.statut,
          ].join(' • '),
        ),
        trailing: historique
            ? const Icon(Icons.history, color: Colors.blueGrey)
            : Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Modifier',
                    icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey),
                    onPressed: t.id == null ? null : () => _showModifierTache(t),
                  ),
                  IconButton(
                    tooltip: 'Marquer faite',
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: t.id == null || t.statut == 'terminee'
                        ? null
                        : () => context.read<CrmProvider>().mettreAJourTache(t.id!, {'statut': 'terminee'}),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'done') {
                        context.read<CrmProvider>().mettreAJourTache(t.id!, {'statut': 'terminee'});
                      } else if (v == 'delete') {
                        context.read<CrmProvider>().supprimerTache(t.id!);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'done', child: Text('Marquer terminée')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _filterButton(String label, String? statut) {
    final provider = context.watch<ClientsProvider>();
    final isSelected = provider.crmStatutFilter == statut;

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Colors.green.shade50 : null,
        side: BorderSide(
          color: isSelected ? Colors.green : Colors.grey.shade500,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      onPressed: () async {
        await context.read<ClientsProvider>().filtrerClientsCrm(statut);
      },
      child: Text(label),
    );
  }

  void _showAjoutInteraction() {
    if (selectedClient == null) return;
    final sujet = TextEditingController();
    final contenu = TextEditingController();
    String type = 'commentaire';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle interaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'commentaire', child: Text('Commentaire')),
                    DropdownMenuItem(value: 'appel', child: Text('Appel')),
                    DropdownMenuItem(value: 'visite', child: Text('Visite')),
                    DropdownMenuItem(value: 'email', child: Text('Email')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v!),
                ),
                TextField(controller: sujet, decoration: const InputDecoration(labelText: 'Sujet')),
                TextField(controller: contenu, decoration: const InputDecoration(labelText: 'Contenu'), maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (contenu.text.isEmpty) return;
                Navigator.pop(context);
                context.read<CrmProvider>().ajouterInteractionClient(selectedClient!.id!, {
                  'type': type,
                  'sujet': sujet.text,
                  'contenu': contenu.text,
                  'auteur': 'Utilisateur'
                });
              },
              child: const Text('Enregistrer'),
            )
          ],
        ),
      ),
    );
  }

  void _showAjoutTache() {
    context.read<ClientsProvider>().chargerClients();
    final titre = TextEditingController();
    final desc = TextEditingController();
    String type = 'relance';
    String priorite = 'moyenne';
    String statut = 'a_faire';
    DateTime echeance = DateTime.now().add(const Duration(days: 1));
    String? selectedClientId = selectedClient?.id;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle tâche CRM'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titre, decoration: const InputDecoration(labelText: 'Titre *')),
                TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'relance', child: Text('Relance')),
                    DropdownMenuItem(value: 'rendez_vous', child: Text('Rendez-vous')),
                    DropdownMenuItem(value: 'appel', child: Text('Appel')),
                    DropdownMenuItem(value: 'suivi', child: Text('Suivi')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: priorite,
                  items: const [
                    DropdownMenuItem(value: 'basse', child: Text('Basse')),
                    DropdownMenuItem(value: 'moyenne', child: Text('Moyenne')),
                    DropdownMenuItem(value: 'haute', child: Text('Haute')),
                    DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                  ],
                  onChanged: (v) => setDialogState(() => priorite = v!),
                ),
                Consumer<ClientsProvider>(
                  builder: (context, clientsProvider, _) {
                    final items = <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('Aucun client')),
                      ...clientsProvider.clients.map(
                        (client) => DropdownMenuItem<String?>(
                          value: client.id,
                          child: Text(client.nomComplet),
                        ),
                      ),
                    ];
                    final currentValue = items.any((item) => item.value == selectedClientId)
                        ? selectedClientId
                        : null;
                    return DropdownButtonFormField<String?>(
                      initialValue: currentValue,
                      items: items,
                      onChanged: (v) => setDialogState(() => selectedClientId = v),
                      decoration: const InputDecoration(labelText: 'Client lié (optionnel)'),
                    );
                  },
                ),
                    ListTile(
                      title: const Text('Échéance'),
                      subtitle: Text('${echeance.day}/${echeance.month}/${echeance.year}'),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final d = await showIsoDatePicker(
                          context: context,
                          initialDate: echeance,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) {
                          setDialogState(() => echeance = d);
                        }
                      },
                    )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (titre.text.isEmpty) return;
                Navigator.pop(context);
                context.read<CrmProvider>().creerTache({
                  'clientId': selectedClientId,
                  'titre': titre.text,
                  'description': desc.text,
                  'type': type,
                  'priorite': priorite,
                  'statut': statut,
                  'dateEcheance': echeance.toIso8601String(),
                });
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showModifierTache(TacheCRM t) {
    if (t.id == null) return;

    context.read<ClientsProvider>().chargerClients();
    final titre = TextEditingController(text: t.titre);
    final desc = TextEditingController(text: t.description);
    final assigneA = TextEditingController(text: t.assigneA);
    String type = t.type;
    String priorite = t.priorite;
    String statut = t.statut;
    bool rappelActive = t.rappelActive;
    DateTime echeance = t.dateEcheance;
    String? selectedClientId = t.clientId.isEmpty ? null : t.clientId;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier tâche CRM'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titre, decoration: const InputDecoration(labelText: 'Titre *')),
                TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
                TextField(controller: assigneA, decoration: const InputDecoration(labelText: 'Assignée à')),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'relance', child: Text('Relance')),
                    DropdownMenuItem(value: 'rendez_vous', child: Text('Rendez-vous')),
                    DropdownMenuItem(value: 'appel', child: Text('Appel')),
                    DropdownMenuItem(value: 'suivi', child: Text('Suivi')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? type),
                ),
                DropdownButtonFormField<String>(
                  initialValue: priorite,
                  items: const [
                    DropdownMenuItem(value: 'basse', child: Text('Basse')),
                    DropdownMenuItem(value: 'moyenne', child: Text('Moyenne')),
                    DropdownMenuItem(value: 'haute', child: Text('Haute')),
                    DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                  ],
                  onChanged: (v) => setDialogState(() => priorite = v ?? priorite),
                  decoration: const InputDecoration(labelText: 'Priorité'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: statut,
                  items: const [
                    DropdownMenuItem(value: 'a_faire', child: Text('À faire')),
                    DropdownMenuItem(value: 'en_cours', child: Text('En cours')),
                    DropdownMenuItem(value: 'terminee', child: Text('Terminée')),
                    DropdownMenuItem(value: 'annulee', child: Text('Annulée')),
                  ],
                  onChanged: (v) => setDialogState(() => statut = v ?? statut),
                  decoration: const InputDecoration(labelText: 'Statut'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rappel actif'),
                  value: rappelActive,
                  onChanged: (v) => setDialogState(() => rappelActive = v),
                ),
                Consumer<ClientsProvider>(
                  builder: (context, clientsProvider, _) {
                    final items = <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('Aucun client')),
                      ...clientsProvider.clients.map(
                        (client) => DropdownMenuItem<String?>(
                          value: client.id,
                          child: Text(client.nomComplet),
                        ),
                      ),
                    ];
                    final currentValue = items.any((item) => item.value == selectedClientId)
                        ? selectedClientId
                        : null;
                    return DropdownButtonFormField<String?>(
                      initialValue: currentValue,
                      items: items,
                      onChanged: (v) => setDialogState(() => selectedClientId = v),
                      decoration: const InputDecoration(labelText: 'Client lié (optionnel)'),
                    );
                  },
                ),
                ListTile(
                  title: const Text('Échéance'),
                  subtitle: Text('${echeance.day}/${echeance.month}/${echeance.year}'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final d = await showIsoDatePicker(
                      context: context,
                      initialDate: echeance,
                      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (d != null) {
                      setDialogState(() => echeance = d);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (titre.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(this.context);
                final ok = await this.context.read<CrmProvider>().mettreAJourTache(
                  t.id!,
                  {
                    'clientId': selectedClientId,
                    'titre': titre.text.trim(),
                    'description': desc.text.trim(),
                    'type': type,
                    'priorite': priorite,
                    'statut': statut,
                    'rappelActive': rappelActive,
                    'assigneA': assigneA.text.trim(),
                    'dateEcheance': echeance.toIso8601String(),
                  },
                );
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Tâche modifiée' : 'Erreur modification tâche')),
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
