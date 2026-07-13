import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/international_phone_field.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();

  final _actuelCtrl = TextEditingController();
  final _nouveauCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<AuthProvider>().user;
    _nomCtrl.text = (user?['nom'] ?? '').toString();
    _prenomCtrl.text = (user?['prenom'] ?? '').toString();
    _emailCtrl.text = (user?['email'] ?? '').toString();
    _telCtrl.text = (user?['telephone'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Profil utilisateur')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Informations personnelles', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(controller: _nomCtrl, decoration: const InputDecoration(labelText: 'Nom')),
                  TextField(controller: _prenomCtrl, decoration: const InputDecoration(labelText: 'Prénom')),
                  TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                  InternationalPhoneField(controller: _telCtrl, labelText: 'Téléphone'),
                  const SizedBox(height: 8),
                  Text('Rôle: ${(user['role'] ?? '').toString()}'),
                  Text('Permissions: ${((user['permissions'] as List?) ?? []).join(', ')}'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (!isValidInternationalPhone(_telCtrl.text.trim())) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Téléphone invalide. Exemple: +221 77 12 34 56')),
                        );
                        return;
                      }

                      final ok = await context.read<AuthProvider>().updateProfile({
                        'nom': _nomCtrl.text.trim(),
                        'prenom': _prenomCtrl.text.trim(),
                        'email': _emailCtrl.text.trim(),
                        'telephone': _telCtrl.text.trim(),
                      });
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'Profil mis à jour' : 'Echec mise à jour')),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Changer mot de passe', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(controller: _actuelCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel')),
                  TextField(controller: _nouveauCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe')),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await context.read<AuthProvider>().changePassword(_actuelCtrl.text, _nouveauCtrl.text);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'Mot de passe mis à jour' : 'Echec changement mot de passe')),
                      );
                    },
                    icon: const Icon(Icons.password),
                    label: const Text('Changer mot de passe'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.read<AuthProvider>().logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Déconnexion'),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
