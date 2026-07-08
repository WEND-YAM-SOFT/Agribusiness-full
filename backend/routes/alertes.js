const express = require('express');
const router = express.Router();
const Alerte = require('../models/Alerte');
const Stock = require('../models/Stock');
const Bande = require('../models/Bande');
const Commande = require('../models/Commande');
const TacheCRM = require('../models/TacheCRM');

function getPeriodBounds(period) {
  const now = new Date();
  const start = new Date(now);
  const end = new Date(now);

  switch (period) {
    case 'today':
      start.setHours(0, 0, 0, 0);
      end.setHours(23, 59, 59, 999);
      return { start, end };
    case 'week': {
      const day = (now.getDay() + 6) % 7;
      start.setDate(now.getDate() - day);
      start.setHours(0, 0, 0, 0);
      end.setDate(start.getDate() + 6);
      end.setHours(23, 59, 59, 999);
      return { start, end };
    }
    case 'month':
      start.setDate(1);
      start.setHours(0, 0, 0, 0);
      end.setMonth(start.getMonth() + 1, 0);
      end.setHours(23, 59, 59, 999);
      return { start, end };
    default:
      return null;
  }
}

// Obtenir toutes les alertes actives
router.get('/actives', async (req, res) => {
  try {
    const query = { statut: 'active' };
    const period = (req.query.period || 'all').toString().toLowerCase();
    const bounds = getPeriodBounds(period);
    if (bounds) {
      query.dateEcheance = { $gte: bounds.start, $lte: bounds.end };
    }

    const alertes = await Alerte.find(query)
      .populate('bandeId', 'nom')
      .sort({ dateEcheance: 1 });
    res.json(alertes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Alertes automatiques agrégées depuis les autres modules
router.get('/automatiques', async (req, res) => {
  try {
    const maintenant = new Date();
    const alertes = [];

    // 1) Stocks en seuil mini (aliment/medicament/vaccin)
    const stocksBas = await Stock.find({
      $expr: { $lte: ['$quantiteActuelle', '$seuilAlerte'] }
    }).select('nom categorie quantiteActuelle seuilAlerte unite');

    for (const s of stocksBas) {
      const categorie = (s.categorie || '').toLowerCase();
      const nom = (s.nom || '').toLowerCase();
      const isVaccin = nom.includes('vaccin');
      const isTarget = categorie === 'aliment' || categorie === 'medicament' || isVaccin;
      if (!isTarget) continue;

      alertes.push({
        id: `stock-${s._id}`,
        titre: `Stock bas: ${s.nom}`,
        message: `Niveau ${s.quantiteActuelle} ${s.unite} (seuil ${s.seuilAlerte} ${s.unite})`,
        type: 'stock_bas',
        priorite: 'haute',
        dateEcheance: maintenant,
        source: 'stock',
        automatique: true,
      });
    }

    // 2) Alertes sanitaires prévues sur bandes (approche échéance)
    const bandes = await Bande.find({ statut: 'ouverte' }).select('nom evenementsSante evenementsPrevisionnels');
    for (const b of bandes) {
      const events = Array.isArray(b.evenementsSante) ? b.evenementsSante : [];
      for (const e of events) {
        if (!e.date) continue;
        const d = new Date(e.date);
        if (Number.isNaN(d.getTime())) continue;
        if (d < maintenant) continue;
        const type = (e.type || '').toLowerCase();
        const isSanitary = ['vaccination', 'traitement', 'autre'].includes(type) ||
          (e.description || '').toLowerCase().includes('controle');
        if (!isSanitary) continue;

        alertes.push({
          id: `sanitaire-${b._id}-${e._id}`,
          titre: `Événement sanitaire: ${b.nom}`,
          message: e.description || 'Événement sanitaire planifié',
          type: 'vaccination',
          priorite: 'moyenne',
          dateEcheance: d,
          source: 'sanitaire',
          automatique: true,
        });
      }

      const planned = Array.isArray(b.evenementsPrevisionnels) ? b.evenementsPrevisionnels : [];
      for (const p of planned) {
        if (!p.datePrevue || p.statut === 'termine') continue;
        const d = new Date(p.datePrevue);
        if (Number.isNaN(d.getTime())) continue;

        const msToDue = d.getTime() - maintenant.getTime();
        const withinWindow = msToDue <= (2 * 24 * 60 * 60 * 1000);
        if (!withinWindow) continue;

        const overdue = msToDue < 0;
        alertes.push({
          id: `prevision-${b._id}-${p._id}`,
          titre: `${overdue ? 'Événement en retard' : 'Événement prévu'}: ${b.nom}`,
          message: p.description || 'Événement planifié',
          type: p.type || 'autre',
          priorite: p.priorite || (overdue ? 'haute' : 'moyenne'),
          dateEcheance: d,
          source: 'planification',
          automatique: true,
          bandeId: b._id,
          eventId: p._id,
        });
      }
    }

    // 3) Alertes commerciales
    const commandesApreparer = await Commande.countDocuments({ statut: { $in: ['confirmee', 'en_preparation'] } });
    if (commandesApreparer > 0) {
      alertes.push({
        id: 'commercial-prepare',
        titre: 'Commandes à préparer',
        message: `${commandesApreparer} commande(s) à préparer`,
        type: 'vente',
        priorite: 'haute',
        dateEcheance: maintenant,
        source: 'commercial',
        automatique: true,
      });
    }

    const commandesAlivrer = await Commande.countDocuments({
      $or: [
        { statut: { $in: ['confirmee', 'en_preparation', 'payee'] } },
        { 'livraisons.statutLivraison': { $in: ['planifiee', 'en_cours'] } }
      ]
    });
    if (commandesAlivrer > 0) {
      alertes.push({
        id: 'commercial-livraison',
        titre: 'Commandes à livrer',
        message: `${commandesAlivrer} commande(s) à livrer`,
        type: 'vente',
        priorite: 'haute',
        dateEcheance: maintenant,
        source: 'commercial',
        automatique: true,
      });
    }

    const relancesClients = await TacheCRM.find({
      statut: { $in: ['a_faire', 'en_cours'] },
      dateEcheance: { $lte: new Date(maintenant.getTime() + 2 * 24 * 60 * 60 * 1000) },
    })
      .populate('clientId', 'nom prenom telephone')
      .sort({ dateEcheance: 1 });
    for (const tache of relancesClients) {
      const clientNom = tache.clientId
        ? `${tache.clientId.prenom || ''} ${tache.clientId.nom || ''}`.trim()
        : '';
      const overdue = new Date(tache.dateEcheance).getTime() < maintenant.getTime();
      alertes.push({
        id: `crm-task-${tache._id}`,
        titre: tache.titre || 'Relance CRM',
        message: [
          clientNom ? `Client: ${clientNom}` : null,
          tache.description || null,
        ].filter(Boolean).join(' • '),
        type: 'vente',
        priorite: tache.priorite || (overdue ? 'haute' : 'moyenne'),
        dateEcheance: tache.dateEcheance,
        source: 'crm_tache',
        automatique: true,
      });
    }

    alertes.sort((a, b) => new Date(a.dateEcheance) - new Date(b.dateEcheance));
    res.json(alertes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir alertes du jour
router.get('/aujourdhui', async (req, res) => {
  try {
    const debut = new Date();
    debut.setHours(0, 0, 0, 0);
    const fin = new Date();
    fin.setHours(23, 59, 59, 999);

    const alertes = await Alerte.find({
      statut: 'active',
      dateEcheance: { $gte: debut, $lte: fin }
    }).populate('bandeId', 'nom');
    res.json(alertes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir alertes en retard
router.get('/retard', async (req, res) => {
  try {
    const alertes = await Alerte.find({
      statut: 'active',
      dateEcheance: { $lt: new Date() }
    }).populate('bandeId', 'nom');
    res.json(alertes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.get('/historique', async (req, res) => {
  try {
    const alertes = await Alerte.find({
      statut: { $in: ['faite', 'ignoree'] },
      automatique: { $ne: true },
    })
      .populate('bandeId', 'nom')
      .sort({ updatedAt: -1, dateEcheance: -1 });
    res.json(alertes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.get('/automatiques/historique', async (req, res) => {
  try {
    const alertes = await Alerte.find({
      statut: { $in: ['faite', 'ignoree'] },
      automatique: true,
    })
      .populate('bandeId', 'nom')
      .sort({ updatedAt: -1, dateEcheance: -1 });
    res.json(alertes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Créer une alerte
router.post('/', async (req, res) => {
  const alerte = new Alerte({
    titre: req.body.titre,
    message: req.body.message,
    type: req.body.type,
    dateEcheance: req.body.dateEcheance,
    bandeId: req.body.bandeId,
    recurrence: req.body.recurrence,
    priorite: req.body.priorite,
    source: req.body.source || 'todo',
    automatique: req.body.automatique === true,
  });

  try {
    const nouvelleAlerte = await alerte.save();
    res.status(201).json(nouvelleAlerte);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Marquer une alerte comme faite
router.put('/:id/fait', async (req, res) => {
  try {
    if (req.params.id.startsWith('crm-task-')) {
      const tacheId = req.params.id.replace('crm-task-', '');
      const tache = await TacheCRM.findById(tacheId);
      if (!tache) return res.status(404).json({ message: 'Tâche CRM non trouvée' });
      if (tache.statut === 'terminee') {
        return res.json({ id: req.params.id, source: 'crm_tache', alreadyDone: true });
      }
      tache.statut = 'terminee';
      const tacheMAJ = await tache.save();

      await Alerte.create({
        titre: tache.titre || 'Relance CRM',
        message: tache.description || 'Tâche CRM terminée',
        type: 'vente',
        dateEcheance: tache.dateEcheance || new Date(),
        statut: 'faite',
        recurrence: 'aucune',
        priorite: tache.priorite || 'moyenne',
        source: 'crm_tache',
        automatique: true,
      });

      return res.json({ id: req.params.id, source: 'crm_tache', tache: tacheMAJ });
    }

    if (
      req.params.id.startsWith('stock-') ||
      req.params.id.startsWith('sanitaire-') ||
      req.params.id.startsWith('prevision-') ||
      req.params.id.startsWith('commercial-')
    ) {
      const now = new Date();
      const archive = await Alerte.create({
        titre: req.body.titre || 'Alerte automatique traitée',
        message: req.body.message || `Alerte ${req.params.id} marquée faite`,
        type: req.body.type || 'autre',
        dateEcheance: req.body.dateEcheance ? new Date(req.body.dateEcheance) : now,
        statut: 'faite',
        recurrence: 'aucune',
        priorite: req.body.priorite || 'moyenne',
        source: req.body.source || 'automatique',
        automatique: true,
      });
      return res.json({ id: req.params.id, source: 'automatique', archive });
    }

    const alerte = await Alerte.findById(req.params.id);
    if (!alerte) return res.status(404).json({ message: 'Alerte non trouvée' });
    alerte.statut = 'faite';
    const alerteMAJ = await alerte.save();
    res.json(alerteMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.delete('/historique/all', async (req, res) => {
  try {
    const result = await Alerte.deleteMany({ statut: { $in: ['faite', 'ignoree'] }, automatique: { $ne: true } });
    res.json({ message: 'Historique supprimé', deletedCount: result.deletedCount || 0 });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Supprimer une alerte
router.delete('/:id', async (req, res) => {
  try {
    const alerte = await Alerte.findById(req.params.id);
    if (!alerte) return res.status(404).json({ message: 'Alerte non trouvée' });
    await alerte.deleteOne();
    res.json({ message: 'Alerte supprimée' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
