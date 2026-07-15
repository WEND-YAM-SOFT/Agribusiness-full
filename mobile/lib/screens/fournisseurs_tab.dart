import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/client.dart';
import '../providers/auth_provider.dart';
import '../providers/fournisseurs_provider.dart';
import '../widgets/international_phone_field.dart';

class FournisseursTab extends StatefulWidget {
  const FournisseursTab({super.key});

  @override
  State<FournisseursTab> createState() => _FournisseursTabState();
}

class _FournisseursTabState extends State<FournisseursTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FournisseursProvider>().chargerFournisseurs();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FournisseursProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) return const Center(child: CircularProgressIndicator());

        final auth = context.watch<AuthProvider>();
        final role = (auth.user?['role'] ?? '').toString();
        final canDelete = auth.hasPermission('clients.delete') || role == 'gestionnaire_ferme';

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher un fournisseur...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () async {
                      _searchController.clear();
                      await context.read<FournisseursProvider>().chargerFournisseurs();
                    },
                  ),
                ),
                onChanged: (value) async {
                  await context.read<FournisseursProvider>().rechercherFournisseurs(value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _showAjoutFournisseur,
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  icon: const Icon(Icons.business, size: 18),
                  label: const Text('Nouveau fournisseur'),
                ),
              ),
            ),
            Expanded(
              child: provider.fournisseurs.isEmpty
                  ? const Center(child: Text('Aucun fournisseur'))
                  : ListView.builder(
                      itemCount: provider.fournisseurs.length,
                      itemBuilder: (_, i) {
                        final f = provider.fournisseurs[i];
                        final entreprise = f.entreprise.isEmpty ? '' : ' • ${f.entreprise}';
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            title: Text(f.nomComplet),
                            subtitle: Text('${f.telephone}$entreprise'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canDelete)
                                  IconButton(
                                    tooltip: 'Supprimer fournisseur',
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _confirmDeleteFournisseur(f),
                                  ),
                                IconButton(
                                  tooltip: 'Modifier fournisseur',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showModifierFournisseur(f),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showAjoutFournisseur() {
    final rootContext = context;
    final prenom = TextEditingController();
    final nom = TextEditingController();
    final telephone = TextEditingController();
    final email = TextEditingController();
    final adresse = TextEditingController();
    final activite = TextEditingController();
    final entreprise = TextEditingController();
    String typeClient = 'pro';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Nouveau fournisseur'),
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
                  onChanged: (v) => setDialog(() => typeClient = v ?? 'pro'),
                  decoration: const InputDecoration(labelText: 'Type fournisseur *'),
                ),
                TextField(
                  controller: activite,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Activité / commentaire *'),
                ),
                TextField(controller: entreprise, decoration: const InputDecoration(labelText: 'Entreprise')),
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
                final fournisseursProvider = rootContext.read<FournisseursProvider>();
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(rootContext);
                final ok = await fournisseursProvider.ajouterFournisseur({
                  'prenom': prenom.text.trim(),
                  'nom': nom.text.trim(),
                  'telephone': telephone.text.trim(),
                  'email': email.text.trim(),
                  'adresse': adresse.text.trim(),
                  'typeClient': typeClient,
                  'commentaireActivite': activite.text.trim(),
                  'entreprise': entreprise.text.trim(),
                });
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Fournisseur ajouté' : 'Erreur lors de la création')),
                );
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showModifierFournisseur(Client fournisseur) {
    final rootContext = context;
    final prenom = TextEditingController(text: fournisseur.prenom);
    final nom = TextEditingController(text: fournisseur.nom);
    final telephone = TextEditingController(text: fournisseur.telephone);
    final email = TextEditingController(text: fournisseur.email);
    final adresse = TextEditingController(text: fournisseur.adresse);
    final activite = TextEditingController(text: fournisseur.commentaireActivite);
    final entreprise = TextEditingController(text: fournisseur.entreprise);
    String typeClient = fournisseur.typeClient;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Modifier fournisseur'),
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
                  onChanged: (v) => setDialog(() => typeClient = v ?? 'pro'),
                  decoration: const InputDecoration(labelText: 'Type fournisseur *'),
                ),
                TextField(
                  controller: activite,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Activité / commentaire *'),
                ),
                TextField(controller: entreprise, decoration: const InputDecoration(labelText: 'Entreprise')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (fournisseur.id == null || fournisseur.id!.isEmpty) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Fournisseur invalide, recharge la liste puis réessaie')),
                  );
                  return;
                }

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
                final fournisseursProvider = rootContext.read<FournisseursProvider>();
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(rootContext);
                final ok = await fournisseursProvider.mettreAJourFournisseur(fournisseur.id!, {
                  'prenom': prenom.text.trim(),
                  'nom': nom.text.trim(),
                  'telephone': telephone.text.trim(),
                  'email': email.text.trim(),
                  'adresse': adresse.text.trim(),
                  'typeClient': typeClient,
                  'commentaireActivite': activite.text.trim(),
                  'entreprise': entreprise.text.trim(),
                });
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Fournisseur modifié' : 'Erreur modification fournisseur')),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteFournisseur(Client fournisseur) async {
    final fournisseurId = fournisseur.id;
    if (fournisseurId == null || fournisseurId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fournisseur invalide, recharge la liste puis réessaie')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer fournisseur'),
        content: Text('Supprimer "${fournisseur.nomComplet}" ?'),
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

    final deleted = await context.read<FournisseursProvider>().supprimerFournisseur(fournisseurId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? 'Fournisseur supprimé' : 'Suppression fournisseur impossible')),
    );
  }
}
