import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/clients_provider.dart';
import '../models/client.dart';
import '../widgets/international_phone_field.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _searchController = TextEditingController();
  String _typeFilter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialiserRecherche();
    });
  }

  Future<void> _initialiserRecherche() async {
    final provider = context.read<ClientsProvider>();
    await provider.ensureFiltresRestaures();
    _searchController.text = provider.searchQuery;
    await provider.appliquerRecherchePersistante();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM - Clients'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                    await context.read<ClientsProvider>().viderRecherche();
                  },
                ),
              ),
              onChanged: (value) async {
                final provider = context.read<ClientsProvider>();
                await provider.setSearchQuery(value);
                if (value.length >= 2) {
                  await provider.rechercherClients(value, sauvegarder: false);
                } else if (value.isEmpty) {
                  await provider.chargerClients();
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: DropdownButtonFormField<String>(
              initialValue: _typeFilter,
              decoration: const InputDecoration(
                labelText: 'Type client',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem<String>(value: '', child: Text('Tous')),
                DropdownMenuItem<String>(value: 'particulier', child: Text('Particulier')),
                DropdownMenuItem<String>(value: 'pro', child: Text('Professionnel (Pro)')),
              ],
              onChanged: (value) {
                setState(() {
                  _typeFilter = value ?? '';
                });
              },
            ),
          ),
          Expanded(
            child: Consumer<ClientsProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final filteredClients = _typeFilter.isEmpty
                    ? provider.clients
                    : provider.clients.where((c) => c.typeClient == _typeFilter).toList();

                if (filteredClients.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Aucun client', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: filteredClients.length,
                  itemBuilder: (context, index) {
                    return _buildClientTile(filteredClients[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showClientFormDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nouveau Client'),
      ),
    );
  }

  Widget _buildClientTile(Client client) {
    final auth = context.watch<AuthProvider>();
    final role = (auth.user?['role'] ?? '').toString();
    final canDeleteClient = auth.hasPermission('clients.delete') || role == 'gestionnaire_ferme';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Text(
            '${client.prenom[0]}${client.nom[0]}',
            style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(client.nomComplet, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(client.telephone),
            Text(client.typeClient == 'pro' ? 'Client Pro' : 'Client Particulier'),
            if (client.entreprise.isNotEmpty) Text(client.entreprise, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        trailing: SizedBox(
          width: canDeleteClient ? 130 : 90,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (canDeleteClient)
                IconButton(
                  tooltip: 'Supprimer client',
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _confirmDeleteClient(client),
                ),
              IconButton(
                tooltip: 'Modifier client',
                icon: const Icon(Icons.edit),
                onPressed: () => _showClientFormDialog(client: client),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
        onTap: () => _showClientDetails(client),
      ),
    );
  }

  void _showClientDetails(Client client) {
    final auth = context.read<AuthProvider>();
    final role = (auth.user?['role'] ?? '').toString();
    final canDeleteClient = auth.hasPermission('clients.delete') || role == 'gestionnaire_ferme';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.green.shade100,
                  child: Text(
                    '${client.prenom[0]}${client.nom[0]}',
                    style: TextStyle(fontSize: 24, color: Colors.green.shade700),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(child: Text(client.nomComplet, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              if (client.entreprise.isNotEmpty)
                Center(child: Text(client.entreprise, style: const TextStyle(fontSize: 16, color: Colors.grey))),
              const SizedBox(height: 24),
              _infoRow(Icons.phone, 'Téléphone', client.telephone),
              if (client.email.isNotEmpty) _infoRow(Icons.email, 'Email', client.email),
              if (client.adresse.isNotEmpty) _infoRow(Icons.location_on, 'Adresse', client.adresse),
              _infoRow(Icons.badge, 'Type client', client.typeClient == 'pro' ? 'Professionnel' : 'Particulier'),
              if (client.commentaireActivite.isNotEmpty) _infoRow(Icons.work_outline, 'Activité', client.commentaireActivite),
              if (client.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(client.notes),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showClientFormDialog(client: client);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Modifier le client'),
                ),
              ),
              if (canDeleteClient) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDeleteClient(client);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    label: const Text('Supprimer le client', style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],
            ],
          ),
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer client'),
        content: Text('Supprimer "${client.nomComplet}" ? Cette action est irréversible.'),
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

    if (confirm != true || !mounted) return;

    final ok = await context.read<ClientsProvider>().supprimerClient(clientId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Client supprimé' : 'Suppression impossible')),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.green),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(value, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  void _showClientFormDialog({Client? client}) {
    final isEdit = client != null;
    final nomController = TextEditingController();
    final prenomController = TextEditingController();
    final telephoneController = TextEditingController();
    final emailController = TextEditingController();
    final adresseController = TextEditingController();
    final entrepriseController = TextEditingController();
    final activiteController = TextEditingController();
    final notesController = TextEditingController();
    String typeClient = client?.typeClient ?? 'particulier';

    if (isEdit) {
      nomController.text = client.nom;
      prenomController.text = client.prenom;
      telephoneController.text = client.telephone;
      emailController.text = client.email;
      adresseController.text = client.adresse;
      entrepriseController.text = client.entreprise;
      activiteController.text = client.commentaireActivite;
      notesController.text = client.notes;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Modifier Client' : 'Nouveau Client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: prenomController, decoration: const InputDecoration(labelText: 'Prénom *')),
                TextField(controller: nomController, decoration: const InputDecoration(labelText: 'Nom *')),
                InternationalPhoneField(controller: telephoneController, labelText: 'Téléphone *'),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
                TextField(controller: adresseController, decoration: const InputDecoration(labelText: 'Adresse *')),
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
                  controller: activiteController,
                  decoration: const InputDecoration(labelText: 'Activité / commentaire *'),
                  maxLines: 2,
                ),
                TextField(controller: entrepriseController, decoration: const InputDecoration(labelText: 'Entreprise')),
                TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Notes')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (nomController.text.trim().isEmpty ||
                    prenomController.text.trim().isEmpty ||
                    adresseController.text.trim().isEmpty ||
                    activiteController.text.trim().isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Renseigne tous les champs obligatoires (*)')),
                  );
                  return;
                }

                if (!isValidInternationalPhone(telephoneController.text.trim())) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Téléphone invalide. Exemple: +221 77 12 34 56')),
                  );
                  return;
                }

                if (isEdit && (client.id == null || client.id!.isEmpty)) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Client invalide, recharge la liste puis réessaie')),
                  );
                  return;
                }

                final clientsProvider = context.read<ClientsProvider>();
                final navigator = Navigator.of(dialogContext);

                final payload = {
                  'nom': nomController.text.trim(),
                  'prenom': prenomController.text.trim(),
                  'telephone': telephoneController.text.trim(),
                  'email': emailController.text.trim(),
                  'adresse': adresseController.text.trim(),
                  'typeClient': typeClient,
                  'commentaireActivite': activiteController.text.trim(),
                  'entreprise': entrepriseController.text.trim(),
                  'notes': notesController.text.trim(),
                };

                bool ok;
                if (isEdit) {
                  ok = await clientsProvider.mettreAJourClient(client.id!, payload);
                } else {
                  ok = await clientsProvider.ajouterClient(payload);
                }

                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? (isEdit ? 'Client modifié' : 'Client ajouté') : 'Erreur modification client, vérifie les champs saisis')),
                );
              },
              child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
            ),
          ],
        ),
      ),
    );
  }
}
