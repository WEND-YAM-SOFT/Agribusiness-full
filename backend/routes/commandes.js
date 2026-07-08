const express = require('express');
const router = express.Router();
const Commande = require('../models/Commande');
const Client = require('../models/Client');
const { enregistrerMouvement, extraireNomPrenomUtilisateur } = require('../services/finance_service');

// Obtenir toutes les commandes
router.get('/', async (req, res) => {
  try {
    const commandes = await Commande.find()
      .populate('client', 'nom prenom telephone')
      .populate('bande', 'nom statut')
      .sort({ createdAt: -1 });
    res.json(commandes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir les commandes par statut
router.get('/statut/:statut', async (req, res) => {
  try {
    const commandes = await Commande.find({ statut: req.params.statut })
      .populate('client', 'nom prenom telephone')
      .populate('bande', 'nom statut')
      .sort({ createdAt: -1 });
    res.json(commandes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir une commande par ID
router.get('/:id', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id)
      .populate('client')
      .populate('bande');
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });
    res.json(commande);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Créer une commande
router.post('/', async (req, res) => {
  const statutInitial = (req.body.statut || 'en_attente').toString();
  const commande = new Commande({
    client: req.body.clientId,
    bande: req.body.bandeId,
    produits: req.body.produits,
    montantTotal: req.body.montantTotal,
    statut: statutInitial,
    dateLivraison: req.body.dateLivraison,
    notes: req.body.notes,
    commentaires: req.body.commentaires || [],
    historiqueActions: [{
      action: 'creation',
      auteur: req.body.auteur || 'Utilisateur',
      details: 'Commande créée'
    }]
  });

  try {
    const nouvelleCommande = await commande.save();

    // Ajouter à l'historique du client
    await Client.findByIdAndUpdate(req.body.clientId, {
      $push: {
        historiqueAchats: {
          commandeId: nouvelleCommande._id,
          date: new Date(),
          montant: nouvelleCommande.montantTotal
        }
      },
      $inc: { chiffreAffairesCumul: nouvelleCommande.montantTotal },
      $set: { dernierContactLe: new Date(), statut: 'actif' }
    });

    if (statutInitial === 'payee') {
      const userName = extraireNomPrenomUtilisateur(req.user);
      const mvt = await enregistrerMouvement({
        nature: 'entree',
        source: 'vente',
        quiNom: userName.quiNom,
        quiPrenom: userName.quiPrenom,
        categorie: 'vente',
        type: 'commande_payee',
        montant: Number(nouvelleCommande.montantTotal || 0),
        date: new Date(),
        commentaire: `Vente comptabilisée - commande ${nouvelleCommande._id}`,
        referenceType: 'Commande',
        referenceId: nouvelleCommande._id,
        externeCle: `commande:${nouvelleCommande._id}:vente`,
      });
      if (mvt) {
        nouvelleCommande.venteComptabilisee = true;
        nouvelleCommande.dernierMouvementTresorerieId = mvt._id;
        await nouvelleCommande.save();
      }
    }

    res.status(201).json(nouvelleCommande);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Mettre à jour le statut d'une commande
router.put('/:id/statut', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id);
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });

    const ancienStatut = commande.statut;
    const nouveauStatut = (req.body.statut || '').toString();
    if (!nouveauStatut) {
      return res.status(400).json({ message: 'Statut obligatoire' });
    }

    commande.statut = nouveauStatut;
    commande.historiqueActions.push({
      action: 'changement_statut',
      auteur: req.body.auteur || 'Utilisateur',
      details: `Nouveau statut: ${nouveauStatut}`
    });

    const userName = extraireNomPrenomUtilisateur(req.user);
    if (ancienStatut !== 'payee' && nouveauStatut === 'payee' && !commande.venteComptabilisee) {
      const mvt = await enregistrerMouvement({
        nature: 'entree',
        source: 'vente',
        quiNom: userName.quiNom,
        quiPrenom: userName.quiPrenom,
        categorie: 'vente',
        type: 'commande_payee',
        montant: Number(commande.montantTotal || 0),
        date: new Date(),
        commentaire: `Vente comptabilisée - commande ${commande._id}`,
        referenceType: 'Commande',
        referenceId: commande._id,
        externeCle: `commande:${commande._id}:vente`,
      });
      if (mvt) {
        commande.venteComptabilisee = true;
        commande.dernierMouvementTresorerieId = mvt._id;
      }
    }

    if (ancienStatut === 'payee' && nouveauStatut !== 'payee' && commande.venteComptabilisee) {
      const mvt = await enregistrerMouvement({
        nature: 'sortie',
        source: 'correction',
        quiNom: userName.quiNom,
        quiPrenom: userName.quiPrenom,
        categorie: 'vente',
        type: 'annulation_vente_payee',
        montant: Number(commande.montantTotal || 0),
        date: new Date(),
        commentaire: `Annulation vente payée - commande ${commande._id}`,
        referenceType: 'Commande',
        referenceId: commande._id,
      });
      if (mvt) {
        commande.venteComptabilisee = false;
        commande.dernierMouvementTresorerieId = mvt._id;
      }
    }

    const commandeMAJ = await commande.save();
    res.json(commandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Ajouter une livraison sur une commande
router.post('/:id/livraisons', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id);
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });

    if (!req.body.dateLivraisonPrevue) {
      return res.status(400).json({ message: 'La date de livraison prévue est obligatoire' });
    }

    const livraison = {
      dateLivraisonPrevue: req.body.dateLivraisonPrevue,
      dateLivraisonReelle: req.body.dateLivraisonReelle || null,
      statutLivraison: req.body.statutLivraison || 'planifiee',
      fraisLivraison: Number(req.body.fraisLivraison || 0),
      commentaires: req.body.commentaires || '',
      utilisateur: req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur',
    };

    commande.livraisons.push(livraison);
    commande.historiqueActions.push({
      action: 'ajout_livraison',
      auteur: req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur',
      details: `Livraison planifiée (${livraison.statutLivraison})`,
    });

    const commandeMAJ = await commande.save();
    res.status(201).json(commandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Mettre à jour une livraison d'une commande
router.put('/:id/livraisons/:livraisonId', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id);
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });

    const livraison = commande.livraisons.id(req.params.livraisonId);
    if (!livraison) return res.status(404).json({ message: 'Livraison non trouvée' });

    if (req.body.dateLivraisonPrevue != null) livraison.dateLivraisonPrevue = req.body.dateLivraisonPrevue;
    if (req.body.dateLivraisonReelle !== undefined) livraison.dateLivraisonReelle = req.body.dateLivraisonReelle;
    if (req.body.statutLivraison) livraison.statutLivraison = req.body.statutLivraison;
    if (req.body.fraisLivraison != null) livraison.fraisLivraison = Number(req.body.fraisLivraison);
    if (req.body.commentaires != null) livraison.commentaires = req.body.commentaires;

    commande.historiqueActions.push({
      action: 'maj_livraison',
      auteur: req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur',
      details: `Livraison mise à jour (${livraison.statutLivraison})`,
    });

    const commandeMAJ = await commande.save();
    res.json(commandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Ajouter commentaire sur commande
router.post('/:id/commentaires', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id);
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });

    commande.commentaires.push({
      auteur: req.body.auteur || 'Utilisateur',
      message: req.body.message,
      date: new Date()
    });

    commande.historiqueActions.push({
      action: 'commentaire',
      auteur: req.body.auteur || 'Utilisateur',
      details: 'Commentaire ajouté'
    });

    const saved = await commande.save();
    res.status(201).json(saved);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Historique complet de la commande
router.get('/historique/:id', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id)
      .select('commentaires historiqueActions createdAt updatedAt');
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });
    res.json(commande);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Mettre à jour une commande
router.put('/:id', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id);
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });

    const montantAvant = Number(commande.montantTotal || 0);

    Object.assign(commande, req.body);

    const montantApres = Number(commande.montantTotal || 0);
    if (commande.venteComptabilisee && montantAvant !== montantApres) {
      const diff = montantApres - montantAvant;
      if (diff !== 0) {
        const userName = extraireNomPrenomUtilisateur(req.user);
        const mvt = await enregistrerMouvement({
          nature: diff > 0 ? 'entree' : 'sortie',
          source: 'correction',
          quiNom: userName.quiNom,
          quiPrenom: userName.quiPrenom,
          categorie: 'vente',
          type: 'correction_montant_commande',
          montant: Math.abs(diff),
          date: new Date(),
          commentaire: `Correction montant commande ${commande._id}: ${montantAvant} -> ${montantApres}`,
          referenceType: 'Commande',
          referenceId: commande._id,
        });
        if (mvt) {
          commande.dernierMouvementTresorerieId = mvt._id;
        }
      }
    }

    const commandeMAJ = await commande.save();
    res.json(commandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Supprimer une commande
router.delete('/:id', async (req, res) => {
  try {
    const commande = await Commande.findById(req.params.id);
    if (!commande) return res.status(404).json({ message: 'Commande non trouvée' });

    if (commande.venteComptabilisee) {
      const userName = extraireNomPrenomUtilisateur(req.user);
      await enregistrerMouvement({
        nature: 'sortie',
        source: 'correction',
        quiNom: userName.quiNom,
        quiPrenom: userName.quiPrenom,
        categorie: 'vente',
        type: 'suppression_commande_payee',
        montant: Number(commande.montantTotal || 0),
        date: new Date(),
        commentaire: `Suppression commande payée ${commande._id}`,
        referenceType: 'Commande',
        referenceId: commande._id,
      });
    }

    await commande.deleteOne();
    res.json({ message: 'Commande supprimée' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
