import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _error;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B5D3B), Color(0xFF2E7D32), Color(0xFFE8F5E9)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isMobile ? 420 : 520),
            child: Card(
              margin: const EdgeInsets.all(24),
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'AgriBusiness',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connexion sécurisée',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Email requis' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Mot de passe requis' : null,
                      ),
                      const SizedBox(height: 8),
                      if (_error != null)
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: auth.isLoading ? null : _submit,
                        icon: const Icon(Icons.login),
                        label: auth.isLoading
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Se connecter'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text('Mot de passe oublié ?'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Compte admin par défaut: admin@agribusiness.local / Admin@123',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await context.read<AuthProvider>().login(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );

    if (!ok && mounted) {
      setState(() => _error = 'Identifiants incorrects ou compte inactif');
    }
  }

  void _showForgotPasswordDialog() {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final tokenCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Réinitialiser le mot de passe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final resp = await context.read<AuthProvider>().forgotPassword(emailCtrl.text.trim());
                    if (resp != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text((resp['message'] ?? 'Email envoyé.').toString())),
                      );
                    }
                  },
                  icon: const Icon(Icons.mark_email_read),
                  label: const Text('Envoyer l\'email'),
                ),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Token reçu par email',
                    hintText: 'Collez le code reçu dans votre boîte mail',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Nouveau mot de passe'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final ok = await context.read<AuthProvider>().resetPassword(tokenCtrl.text.trim(), passCtrl.text);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Mot de passe réinitialisé' : 'Echec réinitialisation')),
                );
                if (ok) Navigator.pop(ctx);
              },
              child: const Text('Réinitialiser'),
            ),
          ],
        ),
      ),
    );
  }
}
