import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration administrateur'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Utilisateurs'),
            Tab(text: 'Paramètres'),
            Tab(text: 'Audit'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _usersTab(),
          _settingsTab(),
          _auditTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showCreateUserDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Ajouter utilisateur'),
            )
          : null,
    );
  }

  Widget _usersTab() {
    return Consumer<AdminProvider>(
      builder: (context, admin, _) {
        if (admin.isLoading) return const Center(child: CircularProgressIndicator());

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: admin.users.length,
          itemBuilder: (_, i) {
            final u = admin.users[i];
            return Card(
              child: ListTile(
                title: Text('${u['nom'] ?? ''} ${u['prenom'] ?? ''}'),
                subtitle: Text('${u['email']} • rôle: ${u['role']}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Réinitialiser mot de passe',
                      onPressed: () async {
                        final temp = await context.read<AdminProvider>().resetPassword((u['id'] ?? u['_id']).toString());
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(temp == null ? 'Echec reset' : 'Mot de passe temporaire: $temp')),
                        );
                      },
                      icon: const Icon(Icons.lock_reset),
                    ),
                    Switch(
                      value: (u['actif'] ?? false) == true,
                      onChanged: (v) => context.read<AdminProvider>().toggleUserActive((u['id'] ?? u['_id']).toString(), v),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        final id = (u['id'] ?? u['_id']).toString();
                        if (value == 'delete') {
                          await context.read<AdminProvider>().deleteUser(id);
                        } else if (value == 'admin') {
                          await context.read<AdminProvider>().updateUser(id, {'role': 'admin'});
                        } else if (value == 'utilisateur') {
                          await context.read<AdminProvider>().updateUser(id, {'role': 'utilisateur'});
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'admin', child: Text('Rôle Admin')),
                        PopupMenuItem(value: 'utilisateur', child: Text('Rôle Utilisateur')),
                        PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsTab() {
    return Consumer<AdminProvider>(
      builder: (context, admin, _) {
        final cfg = admin.config ?? {};
        final nameCtrl = TextEditingController(text: (cfg['nomApplication'] ?? 'AgriBusiness').toString());
        final deviseCtrl = TextEditingController(text: (cfg['devise'] ?? 'FCFA').toString());
        final timeoutCtrl = TextEditingController(text: (cfg['sessionTimeoutMinutes'] ?? 30).toString());
        final refs = Map<String, dynamic>.from((cfg['referencesTheoriques'] ?? {}) as Map);

        Map<String, dynamic> refFor(String key, {required int d, required int p, required double c}) {
          final source = refs[key] is Map ? Map<String, dynamic>.from(refs[key] as Map) : <String, dynamic>{};
          return {
            'dureeJours': source['dureeJours'] ?? d,
            'poidsFinalG': source['poidsFinalG'] ?? p,
            'consoTotaleKgParTete': source['consoTotaleKgParTete'] ?? c,
            'courbeTheorique': _normalizeCourbe(source['courbeTheorique']),
          };
        }

        final refPoulet = refFor('poulet_chair', d: 42, p: 2500, c: 4.2);
        final refPondeuse = refFor('poule_pondeuse', d: 140, p: 1800, c: 14.0);
        final refDinde = refFor('dinde', d: 90, p: 7000, c: 18.0);
        final refCanard = refFor('canard', d: 50, p: 3200, c: 6.0);
        final refAutre = refFor('autre', d: 45, p: 2500, c: 5.0);

        final pouletDureeCtrl = TextEditingController(text: '${refPoulet['dureeJours']}');
        final pouletPoidsCtrl = TextEditingController(text: '${refPoulet['poidsFinalG']}');
        final pouletConsoCtrl = TextEditingController(text: '${refPoulet['consoTotaleKgParTete']}');

        final pondeuseDureeCtrl = TextEditingController(text: '${refPondeuse['dureeJours']}');
        final pondeusePoidsCtrl = TextEditingController(text: '${refPondeuse['poidsFinalG']}');
        final pondeuseConsoCtrl = TextEditingController(text: '${refPondeuse['consoTotaleKgParTete']}');

        final dindeDureeCtrl = TextEditingController(text: '${refDinde['dureeJours']}');
        final dindePoidsCtrl = TextEditingController(text: '${refDinde['poidsFinalG']}');
        final dindeConsoCtrl = TextEditingController(text: '${refDinde['consoTotaleKgParTete']}');

        final canardDureeCtrl = TextEditingController(text: '${refCanard['dureeJours']}');
        final canardPoidsCtrl = TextEditingController(text: '${refCanard['poidsFinalG']}');
        final canardConsoCtrl = TextEditingController(text: '${refCanard['consoTotaleKgParTete']}');

        final autreDureeCtrl = TextEditingController(text: '${refAutre['dureeJours']}');
        final autrePoidsCtrl = TextEditingController(text: '${refAutre['poidsFinalG']}');
        final autreConsoCtrl = TextEditingController(text: '${refAutre['consoTotaleKgParTete']}');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom application')),
            TextField(controller: deviseCtrl, decoration: const InputDecoration(labelText: 'Devise')),
            TextField(controller: timeoutCtrl, decoration: const InputDecoration(labelText: 'Timeout session (minutes)'), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            Text('Références théoriques (courbes)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _refSection(
              title: 'Poulet de chair',
              duree: pouletDureeCtrl,
              poids: pouletPoidsCtrl,
              conso: pouletConsoCtrl,
              courbeCount: (refPoulet['courbeTheorique'] as List).length,
              onEditCurve: () async {
                final updated = await _showCourbeDialog('Poulet de chair', refPoulet['courbeTheorique'] as List<dynamic>);
                if (updated != null) {
                  refPoulet['courbeTheorique'] = updated;
                }
              },
            ),
            _refSection(
              title: 'Poule pondeuse',
              duree: pondeuseDureeCtrl,
              poids: pondeusePoidsCtrl,
              conso: pondeuseConsoCtrl,
              courbeCount: (refPondeuse['courbeTheorique'] as List).length,
              onEditCurve: () async {
                final updated = await _showCourbeDialog('Poule pondeuse', refPondeuse['courbeTheorique'] as List<dynamic>);
                if (updated != null) {
                  refPondeuse['courbeTheorique'] = updated;
                }
              },
            ),
            _refSection(
              title: 'Dinde',
              duree: dindeDureeCtrl,
              poids: dindePoidsCtrl,
              conso: dindeConsoCtrl,
              courbeCount: (refDinde['courbeTheorique'] as List).length,
              onEditCurve: () async {
                final updated = await _showCourbeDialog('Dinde', refDinde['courbeTheorique'] as List<dynamic>);
                if (updated != null) {
                  refDinde['courbeTheorique'] = updated;
                }
              },
            ),
            _refSection(
              title: 'Canard',
              duree: canardDureeCtrl,
              poids: canardPoidsCtrl,
              conso: canardConsoCtrl,
              courbeCount: (refCanard['courbeTheorique'] as List).length,
              onEditCurve: () async {
                final updated = await _showCourbeDialog('Canard', refCanard['courbeTheorique'] as List<dynamic>);
                if (updated != null) {
                  refCanard['courbeTheorique'] = updated;
                }
              },
            ),
            _refSection(
              title: 'Autre',
              duree: autreDureeCtrl,
              poids: autrePoidsCtrl,
              conso: autreConsoCtrl,
              courbeCount: (refAutre['courbeTheorique'] as List).length,
              onEditCurve: () async {
                final updated = await _showCourbeDialog('Autre', refAutre['courbeTheorique'] as List<dynamic>);
                if (updated != null) {
                  refAutre['courbeTheorique'] = updated;
                }
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final ok = await context.read<AdminProvider>().updateConfig({
                  'nomApplication': nameCtrl.text.trim(),
                  'devise': deviseCtrl.text.trim(),
                  'sessionTimeoutMinutes': int.tryParse(timeoutCtrl.text) ?? 30,
                  'referencesTheoriques': {
                    'poulet_chair': {
                      'dureeJours': int.tryParse(pouletDureeCtrl.text) ?? 42,
                      'poidsFinalG': double.tryParse(pouletPoidsCtrl.text) ?? 2500,
                      'consoTotaleKgParTete': double.tryParse(pouletConsoCtrl.text) ?? 4.2,
                      'courbeTheorique': _normalizeCourbe(refPoulet['courbeTheorique']),
                    },
                    'poule_pondeuse': {
                      'dureeJours': int.tryParse(pondeuseDureeCtrl.text) ?? 140,
                      'poidsFinalG': double.tryParse(pondeusePoidsCtrl.text) ?? 1800,
                      'consoTotaleKgParTete': double.tryParse(pondeuseConsoCtrl.text) ?? 14.0,
                      'courbeTheorique': _normalizeCourbe(refPondeuse['courbeTheorique']),
                    },
                    'dinde': {
                      'dureeJours': int.tryParse(dindeDureeCtrl.text) ?? 90,
                      'poidsFinalG': double.tryParse(dindePoidsCtrl.text) ?? 7000,
                      'consoTotaleKgParTete': double.tryParse(dindeConsoCtrl.text) ?? 18.0,
                      'courbeTheorique': _normalizeCourbe(refDinde['courbeTheorique']),
                    },
                    'canard': {
                      'dureeJours': int.tryParse(canardDureeCtrl.text) ?? 50,
                      'poidsFinalG': double.tryParse(canardPoidsCtrl.text) ?? 3200,
                      'consoTotaleKgParTete': double.tryParse(canardConsoCtrl.text) ?? 6.0,
                      'courbeTheorique': _normalizeCourbe(refCanard['courbeTheorique']),
                    },
                    'autre': {
                      'dureeJours': int.tryParse(autreDureeCtrl.text) ?? 45,
                      'poidsFinalG': double.tryParse(autrePoidsCtrl.text) ?? 2500,
                      'consoTotaleKgParTete': double.tryParse(autreConsoCtrl.text) ?? 5.0,
                      'courbeTheorique': _normalizeCourbe(refAutre['courbeTheorique']),
                    },
                  },
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Paramètres sauvegardés' : 'Erreur sauvegarde')),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
            )
          ],
        );
      },
    );
  }

  Widget _refSection({
    required String title,
    required TextEditingController duree,
    required TextEditingController poids,
    required TextEditingController conso,
    required int courbeCount,
    required Future<void> Function() onEditCurve,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: duree,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Durée (jours)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: poids,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Poids final (g)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: conso,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Conso totale/tête (kg)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Courbe théorique: $courbeCount point(s) renseigné(s)')),
                OutlinedButton.icon(
                  onPressed: onEditCurve,
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Éditer tableau'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _auditTab() {
    return Consumer<AdminProvider>(
      builder: (context, admin, _) {
        if (admin.isLoading) return const Center(child: CircularProgressIndicator());
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(child: Text('Historique d\'audit')),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await context.read<AdminProvider>().clearAuditLogs();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'Audit effacé' : 'Erreur lors de l\'effacement')),
                      );
                    },
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Effacer'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: admin.auditLogs.isEmpty
                  ? const Center(child: Text('Aucun log'))
                  : ListView.builder(
                      itemCount: admin.auditLogs.length,
                      itemBuilder: (_, i) {
                        final log = admin.auditLogs[i];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text((log['action'] ?? '').toString()),
                          subtitle: Text('${log['userEmail'] ?? ''} • ${log['createdAt'] ?? ''}'),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _normalizeCourbe(dynamic raw) {
    final source = raw is List ? raw : const [];
    final points = <Map<String, dynamic>>[];
    for (final item in source) {
      if (item is! Map) continue;
      final age = int.tryParse('${item['age'] ?? ''}') ?? 0;
      final poids = double.tryParse('${item['poidsG'] ?? ''}');
      final conso = double.tryParse('${item['consoCumuleeKg'] ?? ''}');
      if (age <= 0 || age > 500) continue;
      if (poids == null && conso == null) continue;
      points.add({
        'age': age,
        ...(poids == null ? const <String, dynamic>{} : <String, dynamic>{'poidsG': poids}),
        ...(conso == null ? const <String, dynamic>{} : <String, dynamic>{'consoCumuleeKg': conso}),
      });
    }
    points.sort((a, b) => (a['age'] as int).compareTo(b['age'] as int));
    return points;
  }

  Future<List<Map<String, dynamic>>?> _showCourbeDialog(String title, List<dynamic> initial) async {
    final initialPoints = _normalizeCourbe(initial);
    final byAge = <int, Map<String, dynamic>>{
      for (final point in initialPoints) point['age'] as int: point,
    };
    final rows = List.generate(500, (index) {
      final age = index + 1;
      final point = byAge[age];
      return <String, dynamic>{
        'age': age,
        'poidsText': point?['poidsG']?.toString() ?? '',
        'consoText': point?['consoCumuleeKg']?.toString() ?? '',
      };
    });

    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Courbe théorique - $title'),
          content: SizedBox(
            width: 920,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Âge en abscisse, jusqu\'à 500 lignes. Tu peux laisser les lignes inutiles vides.'),
                const SizedBox(height: 12),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 70, child: Text('Age ${row['age']}')),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: row['poidsText'] as String,
                                  decoration: const InputDecoration(labelText: 'Poids théorique (g)'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (value) => row['poidsText'] = value.trim(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: row['consoText'] as String,
                                  decoration: const InputDecoration(labelText: 'Conso cumulée (kg/tête)'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (value) => row['consoText'] = value.trim(),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                final points = <Map<String, dynamic>>[];
                for (final row in rows) {
                  final poidsText = (row['poidsText'] as String).trim();
                  final consoText = (row['consoText'] as String).trim();
                  if (poidsText.isEmpty && consoText.isEmpty) continue;
                  final poids = poidsText.isEmpty ? null : double.tryParse(poidsText);
                  final conso = consoText.isEmpty ? null : double.tryParse(consoText);
                  if (poids == null && conso == null) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Valeurs invalides à l\'âge ${row['age']}')),
                    );
                    return;
                  }
                  points.add({
                    'age': row['age'],
                    ...(poids == null ? const <String, dynamic>{} : <String, dynamic>{'poidsG': poids}),
                    ...(conso == null ? const <String, dynamic>{} : <String, dynamic>{'consoCumuleeKg': conso}),
                  });
                }
                Navigator.pop(dialogContext, points);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateUserDialog() {
    final nom = TextEditingController();
    final prenom = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final mdp = TextEditingController();
    String role = 'utilisateur';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Ajouter utilisateur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom')),
                TextField(controller: prenom, decoration: const InputDecoration(labelText: 'Prénom')),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Téléphone')),
                TextField(controller: mdp, decoration: const InputDecoration(labelText: 'Mot de passe temporaire')),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(value: 'utilisateur', child: Text('Utilisateur')),
                    DropdownMenuItem(value: 'admin', child: Text('Administrateur')),
                  ],
                  onChanged: (v) => setDialog(() => role = v ?? 'utilisateur'),
                  decoration: const InputDecoration(labelText: 'Rôle'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final resp = await context.read<AdminProvider>().createUser({
                  'nom': nom.text.trim(),
                  'prenom': prenom.text.trim(),
                  'email': email.text.trim(),
                  'telephone': phone.text.trim(),
                  'role': role,
                  if (mdp.text.trim().isNotEmpty) 'motDePasseTemporaire': mdp.text.trim(),
                });

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(resp == null
                        ? 'Erreur création'
                        : 'Créé. MDP temporaire: ${(resp['motDePasseTemporaire'] ?? '')}'),
                  ),
                );
                if (resp != null) Navigator.pop(context);
              },
              child: const Text('Créer'),
            )
          ],
        ),
      ),
    );
  }
}
