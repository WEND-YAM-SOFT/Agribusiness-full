import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';
import '../services/api_service.dart';
import '../utils/money_format.dart';

class GlobalDashboardScreen extends StatefulWidget {
  const GlobalDashboardScreen({super.key});

  @override
  State<GlobalDashboardScreen> createState() => _GlobalDashboardScreenState();
}

class _GlobalDashboardScreenState extends State<GlobalDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().chargerDashboards();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de Bord Global'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Rapport PDF',
            onPressed: _showExportLinks,
          ),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final g = provider.global;
          final crm = provider.crm;

          if (g.isEmpty) {
            return const Center(child: Text('Aucune donnée disponible'));
          }

          return RefreshIndicator(
            onRefresh: () => provider.chargerDashboards(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _periodChip('jour', provider),
                    _periodChip('semaine', provider),
                    _periodChip('mois', provider),
                    _periodChip('annee', provider),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: provider.selectedBatiment.isEmpty ? '' : provider.selectedBatiment,
                  decoration: const InputDecoration(
                    labelText: 'Filtrer par bâtiment',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Tous les bâtiments'),
                    ),
                    ...provider.batiments.map(
                      (batiment) => DropdownMenuItem<String>(
                        value: batiment,
                        child: Text(batiment),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    provider.chargerDashboards(batiment: value ?? '', bandeId: '');
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: provider.selectedBandeId.isEmpty ? '' : provider.selectedBandeId,
                  decoration: const InputDecoration(
                    labelText: 'Filtrer par cycle',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Tous les cycles'),
                    ),
                    ...provider.bandesFiltreesPourBatiment.map(
                      (bande) => DropdownMenuItem<String>(
                        value: (bande['id'] ?? bande['_id']).toString(),
                        child: Text(
                          '${(bande['nom'] ?? 'Cycle').toString()}${(bande['batiment'] ?? '').toString().isNotEmpty ? ' - ${(bande['batiment'] ?? '').toString()}' : ''}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    provider.chargerDashboards(bandeId: value ?? '');
                  },
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.45,
                  children: [
                    _kpiCard('CA total', formatAmountFcfa(g['chiffreAffairesTotal'] ?? 0), Colors.green),
                    _kpiCard('Dépenses', formatAmountFcfa(g['depensesTotales'] ?? 0), Colors.red),
                    _kpiCard('Bénéfice net', formatAmountFcfa(g['beneficeNet'] ?? 0), Colors.blue),
                    _kpiCard('Marge', '${(g['marge'] ?? 0).toStringAsFixed(2)} %', Colors.orange),
                    _kpiCard('Consommation aliment', '${(g['consoAliment'] ?? 0).toStringAsFixed(2)} kg', Colors.brown),
                    _kpiCard('Taux mortalité', '${(g['tauxMortalite'] ?? 0).toStringAsFixed(2)} %', Colors.deepOrange),
                    _kpiCard('Clients actifs', '${g['clientsActifs'] ?? 0}', Colors.teal),
                    _kpiCard('Commandes', '${g['nbCommandes'] ?? 0}', Colors.purple),
                  ],
                ),
                const SizedBox(height: 20),
                _chartCard('Évolution des ventes', _lineChartFromAgg(g['ventesParPeriode'] ?? [], Colors.green)),
                const SizedBox(height: 12),
                _chartCard('Évolution des dépenses', _lineChartFromAgg(g['depensesParPeriode'] ?? [], Colors.red)),
                const SizedBox(height: 12),
                _crmSummaryCard(crm),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _periodChip(String period, DashboardProvider provider) {
    final selected = provider.period == period;
    return ChoiceChip(
      label: Text(period.toUpperCase()),
      selected: selected,
      onSelected: (_) => provider.chargerDashboards(period: period),
    );
  }

  Widget _kpiCard(String title, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Spacer(),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(String title, Widget chart) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: chart),
          ],
        ),
      ),
    );
  }

  Widget _lineChartFromAgg(List<dynamic> raw, Color color) {
    if (raw.isEmpty) return const Center(child: Text('Pas de données'));

    final points = <FlSpot>[];
    for (var i = 0; i < raw.length; i++) {
      final val = (raw[i]['total'] ?? 0).toDouble();
      points.add(FlSpot(i.toDouble(), val));
    }

    return LineChart(
      LineChartData(
        lineTouchData: const LineTouchData(enabled: true),
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(show: true),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            barWidth: 3,
            color: color,
            dotData: const FlDotData(show: false),
          )
        ],
      ),
    );
  }

  Widget _crmSummaryCard(Map<String, dynamic> crm) {
    if (crm.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Synthèse CRM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('Total clients: ${crm['totalClients'] ?? 0}'),
                Text('Prospects: ${crm['totalProspects'] ?? 0}'),
                Text('Nouveaux clients: ${crm['nouveauxClients'] ?? 0}'),
                Text('Relances à faire: ${crm['relancesAFaire'] ?? 0}'),
                Text('Commandes en attente: ${crm['commandesEnAttente'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExportLinks() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rapports exportables'),
        content: SelectableText(
          'PDF: ${ApiService.getGlobalPdfReportUrl()}\n\nExcel: ${ApiService.getGlobalExcelReportUrl()}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }
}
