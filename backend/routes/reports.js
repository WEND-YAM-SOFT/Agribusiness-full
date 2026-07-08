const express = require('express');
const router = express.Router();
const PDFDocument = require('pdfkit');
const ExcelJS = require('exceljs');
const Commande = require('../models/Commande');
const Depense = require('../models/Depense');
const Bande = require('../models/Bande');

router.get('/global.pdf', async (req, res) => {
  const doc = new PDFDocument({ margin: 32 });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', 'attachment; filename=rapport-global.pdf');
  doc.pipe(res);

  const commandes = await Commande.find();
  const depenses = await Depense.find();
  const bandes = await Bande.find();

  const ca = commandes.reduce((s, c) => s + c.montantTotal, 0);
  const dep = depenses.reduce((s, d) => s + d.montant, 0);
  const benef = ca - dep;
  const effectifInitial = bandes.reduce((s, b) => s + (b.nombreInitial || 0), 0);
  const mortalite = bandes.reduce((s, b) => s + (b.mortaliteTotale || 0), 0);

  doc.fontSize(18).text('Rapport Global AgriBusiness');
  doc.moveDown();
  doc.fontSize(12).text(`Chiffre d'affaires: ${ca.toFixed(0)} FCFA`);
  doc.text(`Depenses: ${dep.toFixed(0)} FCFA`);
  doc.text(`Benefice net: ${benef.toFixed(0)} FCFA`);
  doc.text(`Taux mortalite cumule: ${effectifInitial > 0 ? ((mortalite / effectifInitial) * 100).toFixed(2) : 0}%`);
  doc.text(`Nombre de commandes: ${commandes.length}`);
  doc.text(`Nombre de bandes: ${bandes.length}`);
  doc.end();
});

router.get('/global.xlsx', async (req, res) => {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('KPI');

  const commandes = await Commande.find();
  const depenses = await Depense.find();
  const bandes = await Bande.find();

  const ca = commandes.reduce((s, c) => s + c.montantTotal, 0);
  const dep = depenses.reduce((s, d) => s + d.montant, 0);
  const benef = ca - dep;
  const effectifInitial = bandes.reduce((s, b) => s + (b.nombreInitial || 0), 0);
  const mortalite = bandes.reduce((s, b) => s + (b.mortaliteTotale || 0), 0);

  sheet.addRow(['Indicateur', 'Valeur']);
  sheet.addRow(['Chiffre d\'affaires', ca]);
  sheet.addRow(['Depenses', dep]);
  sheet.addRow(['Benefice net', benef]);
  sheet.addRow(['Taux mortalite cumule (%)', effectifInitial > 0 ? (mortalite / effectifInitial) * 100 : 0]);
  sheet.addRow(['Nombre de commandes', commandes.length]);
  sheet.addRow(['Nombre de bandes', bandes.length]);

  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', 'attachment; filename=rapport-global.xlsx');
  await workbook.xlsx.write(res);
  res.end();
});

module.exports = router;
