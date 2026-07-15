const express = require('express');
const PDFDocument = require('pdfkit');
const ExcelJS = require('exceljs');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');
const { requireAnyPermission } = require('../middleware/auth');

const router = express.Router();

async function computeGlobalKpi(api, companyId) {
  const [commandesRes, tresoRes, bandesRes] = await Promise.all([
    api.from('commandes').select('id,montant_total').eq('company_id', companyId),
    api.from('tresorerie_mouvements').select('nature,montant').eq('company_id', companyId),
    api.from('bandes').select('id,nombre_initial,mortalite_totale').eq('company_id', companyId),
  ]);

  if (commandesRes.error) throw new Error(commandesRes.error.message);
  if (tresoRes.error) throw new Error(tresoRes.error.message);
  if (bandesRes.error) throw new Error(bandesRes.error.message);

  const commandes = commandesRes.data || [];
  const sorties = (tresoRes.data || []).filter((m) => m.nature === 'sortie');
  const bandes = bandesRes.data || [];

  const ca = commandes.reduce((s, c) => s + Number(c.montant_total || 0), 0);
  const dep = sorties.reduce((s, d) => s + Number(d.montant || 0), 0);
  const benef = ca - dep;
  const effectifInitial = bandes.reduce((s, b) => s + Number(b.nombre_initial || 0), 0);
  const mortalite = bandes.reduce((s, b) => s + Number(b.mortalite_totale || 0), 0);

  return {
    ca,
    dep,
    benef,
    tauxMortalite: effectifInitial > 0 ? ((mortalite / effectifInitial) * 100) : 0,
    nbCommandes: commandes.length,
    nbBandes: bandes.length,
  };
}

router.get('/global.pdf', requireAnyPermission(['reports.sales', 'reports.tech', 'reports.full']), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const kpi = await computeGlobalKpi(api, companyId);

    const doc = new PDFDocument({ margin: 32 });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename=rapport-global.pdf');
    doc.pipe(res);

    doc.fontSize(18).text('Rapport Global AgriBusiness');
    doc.moveDown();
    doc.fontSize(12).text(`Chiffre d'affaires: ${kpi.ca.toFixed(0)} FCFA`);
    doc.text(`Depenses: ${kpi.dep.toFixed(0)} FCFA`);
    doc.text(`Benefice net: ${kpi.benef.toFixed(0)} FCFA`);
    doc.text(`Taux mortalite cumule: ${kpi.tauxMortalite.toFixed(2)}%`);
    doc.text(`Nombre de commandes: ${kpi.nbCommandes}`);
    doc.text(`Nombre de bandes: ${kpi.nbBandes}`);
    doc.end();
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/global.xlsx', requireAnyPermission(['reports.sales', 'reports.tech', 'reports.full']), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const kpi = await computeGlobalKpi(api, companyId);

    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('KPI');

    sheet.addRow(['Indicateur', 'Valeur']);
    sheet.addRow(["Chiffre d'affaires", kpi.ca]);
    sheet.addRow(['Depenses', kpi.dep]);
    sheet.addRow(['Benefice net', kpi.benef]);
    sheet.addRow(['Taux mortalite cumule (%)', kpi.tauxMortalite]);
    sheet.addRow(['Nombre de commandes', kpi.nbCommandes]);
    sheet.addRow(['Nombre de bandes', kpi.nbBandes]);

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=rapport-global.xlsx');
    await workbook.xlsx.write(res);
    return res.end();
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
