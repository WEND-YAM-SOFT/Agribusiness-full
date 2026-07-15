import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'providers/bandes_provider.dart';
import 'providers/clients_provider.dart';
import 'providers/fournisseurs_provider.dart';
import 'providers/commandes_provider.dart';
import 'providers/stocks_provider.dart';
import 'providers/alertes_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/crm_provider.dart';
import 'providers/finance_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/admin_provider.dart';

void main() {
  runApp(const AgriBusiness());
}

class AgriBusiness extends StatelessWidget {
  const AgriBusiness({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..initSession()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
        ChangeNotifierProvider(create: (_) => BandesProvider()),
        ChangeNotifierProvider(create: (_) => ClientsProvider()),
        ChangeNotifierProvider(create: (_) => FournisseursProvider()),
        ChangeNotifierProvider(create: (_) => CommandesProvider()),
        ChangeNotifierProvider(create: (_) => StocksProvider()),
        ChangeNotifierProvider(create: (_) => AlertesProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => CrmProvider()),
        ChangeNotifierProvider(create: (_) => FinanceProvider()),
      ],
      child: MaterialApp(
        title: 'AgriBusiness',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const _AppGate(),
      ),
    );
  }
}

class _AppGate extends StatelessWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final child = auth.isAuthenticated ? const HomeScreen() : const LoginScreen();

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => auth.registerActivity(),
          onPointerMove: (_) => auth.registerActivity(),
          child: child,
        );
      },
    );
  }
}
