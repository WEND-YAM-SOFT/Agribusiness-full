const express = require('express');
const router = express.Router();
const TresorerieMouvement = require('../models/TresorerieMouvement');
const { enregistrerMouvement, extraireNomPrenomUtilisateur } = require('../services/finance_service');

router.get('/mouvements', async (req, res) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit || 200), 1), 1000);
    const filter = {};

    const source = (req.query.source || '').toString().trim();
    const sourcesRaw = (req.query.sources || '').toString().trim();
    if (sourcesRaw) {
      const sourceList = sourcesRaw
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);
      if (sourceList.length > 0) {
        filter.source = { $in: sourceList };
      }
    } else if (source) {
      filter.source = source;
    }

    const now = new Date();
    const period = (req.query.period || '').toString().trim().toLowerCase();
    if (period === 'semaine' || period === 'mois' || period === 'annee') {
      let start = new Date(now);
      if (period === 'semaine') {
        const day = start.getDay();
        const diffToMonday = day === 0 ? 6 : day - 1;
        start.setDate(start.getDate() - diffToMonday);
      } else if (period === 'mois') {
        start = new Date(start.getFullYear(), start.getMonth(), 1);
      } else if (period === 'annee') {
        start = new Date(start.getFullYear(), 0, 1);
      }
      start.setHours(0, 0, 0, 0);
      filter.date = { ...(filter.date || {}), $gte: start };
    }

    const yearRaw = (req.query.year || '').toString().trim();
    const monthRaw = (req.query.month || '').toString().trim();
    const year = Number(yearRaw);
    const month = Number(monthRaw);
    if (!Number.isNaN(year) && year >= 2000 && year <= 2100) {
      if (!Number.isNaN(month) && month >= 1 && month <= 12) {
        const start = new Date(year, month - 1, 1, 0, 0, 0, 0);
        const end = new Date(year, month, 0, 23, 59, 59, 999);
        filter.date = {
          ...(filter.date || {}),
          $gte: start,
          $lte: end,
        };
      } else {
        const start = new Date(year, 0, 1, 0, 0, 0, 0);
        const end = new Date(year, 11, 31, 23, 59, 59, 999);
        filter.date = {
          ...(filter.date || {}),
          $gte: start,
          $lte: end,
        };
      }
    }

    const dateFromRaw = (req.query.dateFrom || '').toString().trim();
    const dateToRaw = (req.query.dateTo || '').toString().trim();
    if (dateFromRaw) {
      const dateFrom = new Date(dateFromRaw);
      if (!Number.isNaN(dateFrom.getTime())) {
        dateFrom.setHours(0, 0, 0, 0);
        filter.date = { ...(filter.date || {}), $gte: dateFrom };
      }
    }
    if (dateToRaw) {
      const dateTo = new Date(dateToRaw);
      if (!Number.isNaN(dateTo.getTime())) {
        dateTo.setHours(23, 59, 59, 999);
        filter.date = { ...(filter.date || {}), $lte: dateTo };
      }
    }

    const weekdaysRaw = (req.query.weekdays || '').toString().trim();
    if (weekdaysRaw) {
      const weekdays = weekdaysRaw
        .split(',')
        .map((w) => Number(w.trim()))
        .filter((w) => !Number.isNaN(w) && w >= 1 && w <= 7);
      if (weekdays.length > 0) {
        filter.$expr = {
          $in: [{ $isoDayOfWeek: '$date' }, weekdays],
        };
      }
    }

    const mouvements = await TresorerieMouvement.find(filter).sort({ date: -1, createdAt: -1 }).limit(limit);
    res.json(mouvements);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.get('/solde', async (_req, res) => {
  try {
    const aggregation = await TresorerieMouvement.aggregate([
      {
        $group: {
          _id: null,
          totalEntrees: {
            $sum: {
              $cond: [{ $eq: ['$nature', 'entree'] }, '$montant', 0],
            },
          },
          totalSorties: {
            $sum: {
              $cond: [{ $eq: ['$nature', 'sortie'] }, '$montant', 0],
            },
          },
        },
      },
    ]);

    const totals = aggregation[0] || { totalEntrees: 0, totalSorties: 0 };
    res.json({
      totalEntrees: Number(totals.totalEntrees || 0),
      totalSorties: Number(totals.totalSorties || 0),
      soldeCaisse: Number(totals.totalEntrees || 0) - Number(totals.totalSorties || 0),
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.post('/depenses', async (req, res) => {
  try {
    const quiNom = (req.body.quiNom || '').toString().trim();
    const quiPrenom = (req.body.quiPrenom || '').toString().trim();
    const categorie = (req.body.categorie || '').toString().trim();
    const type = (req.body.type || '').toString().trim();
    const montant = Number(req.body.montant || 0);
    const commentaire = (req.body.commentaire || '').toString().trim();
    const date = req.body.date ? new Date(req.body.date) : new Date();

    if (!quiNom || !quiPrenom || !categorie || !type || montant <= 0 || Number.isNaN(date.getTime())) {
      return res.status(400).json({
        message: 'Champs obligatoires: quiNom, quiPrenom, categorie, type, montant (>0), date valide',
      });
    }

    const mouv = await enregistrerMouvement({
      nature: 'sortie',
      source: 'depense',
      quiNom,
      quiPrenom,
      categorie,
      type,
      montant,
      date,
      commentaire,
      referenceType: 'manuel',
    });

    res.status(201).json(mouv);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.post('/approvisionnements', async (req, res) => {
  try {
    const quiNom = (req.body.quiNom || '').toString().trim();
    const quiPrenom = (req.body.quiPrenom || '').toString().trim();
    const montant = Number(req.body.montant || 0);
    const commentaire = (req.body.commentaire || '').toString().trim();
    const date = req.body.date ? new Date(req.body.date) : new Date();

    if (!quiNom || !quiPrenom || montant <= 0 || Number.isNaN(date.getTime())) {
      return res.status(400).json({
        message: 'Champs obligatoires: quiNom, quiPrenom, montant (>0), date valide',
      });
    }

    const userName = extraireNomPrenomUtilisateur(req.user);
    const mouv = await enregistrerMouvement({
      nature: 'entree',
      source: 'approvisionnement',
      quiNom,
      quiPrenom,
      categorie: 'caisse',
      type: 'approvisionnement',
      montant,
      date,
      commentaire: commentaire || `Déclaré par ${userName.quiPrenom} ${userName.quiNom}`,
      referenceType: 'manuel',
    });

    res.status(201).json(mouv);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.delete('/mouvements', async (_req, res) => {
  try {
    const result = await TresorerieMouvement.deleteMany({});
    res.json({ message: 'Historique des mouvements supprimé', deletedCount: result.deletedCount || 0 });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
