const express = require('express');
const router = express.Router();
const Client = require('../models/Client');
const Interaction = require('../models/Interaction');
const TacheCRM = require('../models/TacheCRM');
const Commande = require('../models/Commande');

// Dashboard CRM
router.get('/dashboard', async (req, res) => {
  try {
    const totalClients = await Client.countDocuments();
    const totalProspects = await Client.countDocuments({ statut: 'prospect' });
    const clientsActifs = await Client.countDocuments({ statut: 'actif' });

    const debutMois = new Date();
    debutMois.setDate(1);
    debutMois.setHours(0, 0, 0, 0);

    const nouveauxClients = await Client.countDocuments({ createdAt: { $gte: debutMois } });
    const commandesEnAttente = await Commande.countDocuments({ statut: 'en_attente' });
    const relancesAFaire = await TacheCRM.countDocuments({
      statut: { $in: ['a_faire', 'en_cours'] },
      dateEcheance: { $lte: new Date() }
    });

    const topClients = await Client.find()
      .sort({ chiffreAffairesCumul: -1 })
      .limit(5)
      .select('nom prenom chiffreAffairesCumul statut');

    const interactionsParType = await Interaction.aggregate([
      {
        $group: {
          _id: '$type',
          count: { $sum: 1 }
        }
      },
      { $sort: { count: -1 } }
    ]);

    const ventesParMois = await Commande.aggregate([
      {
        $group: {
          _id: {
            annee: { $year: '$createdAt' },
            mois: { $month: '$createdAt' }
          },
          total: { $sum: '$montantTotal' }
        }
      },
      { $sort: { '_id.annee': 1, '_id.mois': 1 } },
      { $limit: 12 }
    ]);

    res.json({
      totalClients,
      totalProspects,
      clientsActifs,
      nouveauxClients,
      commandesEnAttente,
      relancesAFaire,
      topClients,
      interactionsParType,
      ventesParMois
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Interactions d'un client
router.get('/clients/:clientId/interactions', async (req, res) => {
  try {
    const interactions = await Interaction.find({ clientId: req.params.clientId })
      .populate('commandeId', 'montantTotal statut')
      .sort({ dateInteraction: -1 });
    res.json(interactions);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Ajouter interaction
router.post('/clients/:clientId/interactions', async (req, res) => {
  try {
    const interaction = new Interaction({
      clientId: req.params.clientId,
      commandeId: req.body.commandeId,
      type: req.body.type,
      sujet: req.body.sujet,
      contenu: req.body.contenu,
      auteur: req.body.auteur || 'Utilisateur',
      dateInteraction: req.body.dateInteraction || new Date(),
      piecesJointes: req.body.piecesJointes || []
    });

    const saved = await interaction.save();

    await Client.findByIdAndUpdate(req.params.clientId, {
      dernierContactLe: saved.dateInteraction
    });

    res.status(201).json(saved);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Tâches CRM
router.get('/taches', async (req, res) => {
  try {
    const taches = await TacheCRM.find()
      .populate('clientId', 'nom prenom telephone statut')
      .populate('commandeId', 'montantTotal statut')
      .sort({ dateEcheance: 1 });
    res.json(taches);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.post('/taches', async (req, res) => {
  try {
    const tache = new TacheCRM({
      clientId: req.body.clientId,
      commandeId: req.body.commandeId,
      titre: req.body.titre,
      description: req.body.description,
      type: req.body.type,
      dateEcheance: req.body.dateEcheance,
      priorite: req.body.priorite,
      rappelActive: req.body.rappelActive,
      assigneA: req.body.assigneA
    });

    const saved = await tache.save();
    res.status(201).json(saved);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.put('/taches/:id', async (req, res) => {
  try {
    const tache = await TacheCRM.findById(req.params.id);
    if (!tache) return res.status(404).json({ message: 'Tâche non trouvée' });

    Object.assign(tache, req.body);
    const saved = await tache.save();
    res.json(saved);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.delete('/taches/historique/all', async (req, res) => {
  try {
    const result = await TacheCRM.deleteMany({ statut: { $in: ['terminee', 'annulee'] } });
    res.json({ message: 'Historique CRM supprimé', deletedCount: result.deletedCount || 0 });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.delete('/taches/:id', async (req, res) => {
  try {
    const tache = await TacheCRM.findById(req.params.id);
    if (!tache) return res.status(404).json({ message: 'Tâche non trouvée' });
    await tache.deleteOne();
    res.json({ message: 'Tâche supprimée' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
