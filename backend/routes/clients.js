const express = require('express');
const router = express.Router();
const Client = require('../models/Client');

// Obtenir tous les clients
router.get('/', async (req, res) => {
  try {
    const { statut, q } = req.query;
    const filter = {};

    if (statut) filter.statut = statut;
    if (q) {
      filter.$or = [
        { nom: { $regex: q, $options: 'i' } },
        { prenom: { $regex: q, $options: 'i' } },
        { telephone: { $regex: q, $options: 'i' } },
        { entreprise: { $regex: q, $options: 'i' } },
        { adresse: { $regex: q, $options: 'i' } },
        { commentaireActivite: { $regex: q, $options: 'i' } }
      ];
    }

    const clients = await Client.find(filter).sort({ nom: 1 });
    res.json(clients);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Rechercher des clients
router.get('/recherche', async (req, res) => {
  try {
    const { q } = req.query;
    const clients = await Client.find({
      $or: [
        { nom: { $regex: q, $options: 'i' } },
        { prenom: { $regex: q, $options: 'i' } },
        { telephone: { $regex: q, $options: 'i' } },
        { entreprise: { $regex: q, $options: 'i' } },
        { adresse: { $regex: q, $options: 'i' } },
        { commentaireActivite: { $regex: q, $options: 'i' } }
      ]
    });
    res.json(clients);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir un client par ID (avec historique)
router.get('/:id', async (req, res) => {
  try {
    const client = await Client.findById(req.params.id).populate('historiqueAchats.commandeId');
    if (!client) return res.status(404).json({ message: 'Client non trouvé' });
    res.json(client);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Créer un client
router.post('/', async (req, res) => {
  const adresse = (req.body.adresse || '').toString().trim();
  const typeClient = (req.body.typeClient || '').toString().trim();
  const commentaireActivite = (req.body.commentaireActivite || '').toString().trim();
  if (!adresse || !typeClient || !commentaireActivite) {
    return res.status(400).json({
      message: 'Les champs obligatoires client sont: adresse, typeClient, commentaireActivite'
    });
  }
  if (!['pro', 'particulier'].includes(typeClient)) {
    return res.status(400).json({ message: 'typeClient invalide (pro ou particulier)' });
  }

  const client = new Client({
    nom: req.body.nom,
    prenom: req.body.prenom,
    telephone: req.body.telephone,
    email: req.body.email,
    adresse,
    typeClient,
    commentaireActivite,
    entreprise: req.body.entreprise,
    statut: req.body.statut,
    notes: req.body.notes
  });

  try {
    const nouveauClient = await client.save();
    res.status(201).json(nouveauClient);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Mettre à jour un client
router.put('/:id', async (req, res) => {
  try {
    const client = await Client.findById(req.params.id);
    if (!client) return res.status(404).json({ message: 'Client non trouvé' });

    if (req.body.typeClient && !['pro', 'particulier'].includes(req.body.typeClient)) {
      return res.status(400).json({ message: 'typeClient invalide (pro ou particulier)' });
    }

    const payload = { ...req.body };
    if (payload.adresse !== undefined && payload.adresse.toString().trim().length === 0) {
      return res.status(400).json({ message: 'Adresse obligatoire' });
    }
    if (payload.commentaireActivite !== undefined && payload.commentaireActivite.toString().trim().length === 0) {
      return res.status(400).json({ message: 'Commentaire activité obligatoire' });
    }

    if (payload.adresse !== undefined) payload.adresse = payload.adresse.toString().trim();
    if (payload.commentaireActivite !== undefined) payload.commentaireActivite = payload.commentaireActivite.toString().trim();

    Object.assign(client, payload);
    const clientMAJ = await client.save();
    res.json(clientMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Supprimer un client
router.delete('/:id', async (req, res) => {
  try {
    const client = await Client.findById(req.params.id);
    if (!client) return res.status(404).json({ message: 'Client non trouvé' });
    await client.deleteOne();
    res.json({ message: 'Client supprimé' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
