const express = require('express');
const router = express.Router();
const Stock = require('../models/Stock');
const TresorerieMouvement = require('../models/TresorerieMouvement');
const { enregistrerMouvement, extraireNomPrenomUtilisateur } = require('../services/finance_service');

function buildStockMovementKey(stockId, mouvementId) {
  return `stock:${stockId}:movement:${mouvementId}`;
}

function parseNumberInput(value) {
  if (typeof value === 'number') return value;
  const normalized = (value ?? '').toString().trim().replace(',', '.');
  return Number(normalized);
}

function recalculerQuantite(mouvements = []) {
  const ordonnes = mouvements
    .map((mouvement, index) => ({ mouvement, index }))
    .sort((a, b) => {
      const diff = new Date(a.mouvement.date).getTime() - new Date(b.mouvement.date).getTime();
      if (diff !== 0) return diff;
      return a.index - b.index;
    });

  let quantiteActuelle = 0;
  for (const { mouvement } of ordonnes) {
    if (mouvement.type === 'creation' || mouvement.type === 'ajustement') {
      quantiteActuelle = Number(mouvement.quantite || 0);
    } else if (mouvement.type === 'entree') {
      quantiteActuelle += Number(mouvement.quantite || 0);
    } else if (mouvement.type === 'sortie') {
      quantiteActuelle -= Number(mouvement.quantite || 0);
    }
  }

  return quantiteActuelle;
}

// Obtenir tous les stocks
router.get('/', async (req, res) => {
  try {
    const stocks = await Stock.find().sort({ categorie: 1, nom: 1 });
    res.json(stocks);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Stocks par catégorie
router.get('/categorie/:categorie', async (req, res) => {
  try {
    const stocks = await Stock.find({ categorie: req.params.categorie });
    res.json(stocks);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Stocks en alerte (quantité basse)
router.get('/alertes', async (req, res) => {
  try {
    const stocks = await Stock.find({
      $expr: { $lte: ['$quantiteActuelle', '$seuilAlerte'] }
    });
    res.json(stocks);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir un stock par ID
router.get('/:id', async (req, res) => {
  try {
    const stock = await Stock.findById(req.params.id);
    if (!stock) return res.status(404).json({ message: 'Stock non trouvé' });
    res.json(stock);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Créer un stock
router.post('/', async (req, res) => {
  if (!req.body.date) {
    return res.status(400).json({ message: 'La date est obligatoire' });
  }

  const dateCreation = new Date(req.body.date);
  if (Number.isNaN(dateCreation.getTime())) {
    return res.status(400).json({ message: 'Date invalide' });
  }

  const quantiteInitiale = parseNumberInput(req.body.quantiteActuelle || 0);
  const seuilAlerte = parseNumberInput(req.body.seuilAlerte || 0);
  const prixUnitaire = parseNumberInput(req.body.prixUnitaire || 0);
  if (Number.isNaN(quantiteInitiale) || quantiteInitiale < 0) {
    return res.status(400).json({ message: 'Quantité initiale invalide' });
  }
  if (Number.isNaN(seuilAlerte) || seuilAlerte < 0) {
    return res.status(400).json({ message: 'Seuil d\'alerte invalide' });
  }
  if (Number.isNaN(prixUnitaire) || prixUnitaire < 0) {
    return res.status(400).json({ message: 'Prix unitaire invalide' });
  }
  const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';

  const mouvementCreation = {
    date: dateCreation,
    type: 'creation',
    quantite: quantiteInitiale,
    utilisateur: auteur,
    motif: 'Création du stock',
    fournisseur: req.body.fournisseur || '',
    coutUnitaire: prixUnitaire,
  };

  const stock = new Stock({
    nom: req.body.nom,
    categorie: req.body.categorie,
    unite: req.body.unite,
    quantiteActuelle: quantiteInitiale,
    seuilAlerte,
    prixUnitaire,
    dateCreationStock: dateCreation,
    fournisseur: req.body.fournisseur,
    emplacement: req.body.emplacement,
    dateExpiration: req.body.dateExpiration,
    notes: req.body.notes,
    mouvements: [mouvementCreation]
  });

  try {
    const nouveauStock = await stock.save();
    const coutUnitaire = prixUnitaire;
    const montantAchatInitial = quantiteInitiale * (Number.isNaN(coutUnitaire) ? 0 : coutUnitaire);
    if (montantAchatInitial > 0 && nouveauStock.mouvements[0]?._id) {
      const userName = extraireNomPrenomUtilisateur(req.user);
      await enregistrerMouvement({
        nature: 'sortie',
        source: 'stock_entree',
        quiNom: userName.quiNom,
        quiPrenom: userName.quiPrenom,
        categorie: nouveauStock.categorie || 'stock',
        type: nouveauStock.nom || 'stock',
        montant: montantAchatInitial,
        date: dateCreation,
        commentaire: `Création stock ${nouveauStock.nom}`,
        referenceType: 'Stock',
        referenceId: nouveauStock._id,
        externeCle: buildStockMovementKey(nouveauStock._id, nouveauStock.mouvements[0]._id),
      });
    }
    res.status(201).json(nouveauStock);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Ajouter un mouvement (entrée/sortie)
router.post('/:id/mouvement', async (req, res) => {
  try {
    const stock = await Stock.findById(req.params.id);
    if (!stock) return res.status(404).json({ message: 'Stock non trouvé' });

    if (!req.body.date) {
      return res.status(400).json({ message: 'La date est obligatoire' });
    }

    const dateMouvement = new Date(req.body.date);
    if (Number.isNaN(dateMouvement.getTime())) {
      return res.status(400).json({ message: 'Date invalide' });
    }

    const quantite = parseNumberInput(req.body.quantite);
    if (Number.isNaN(quantite) || quantite < 0) {
      return res.status(400).json({ message: 'Quantité invalide' });
    }

    const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';

    const coutUnitaireSaisi = req.body.coutUnitaire ?? req.body.prixUnitaire;
    const coutUnitaire = parseNumberInput(coutUnitaireSaisi);
    const mouvement = stock.mouvements.create({
      date: req.body.type === 'ajustement' ? new Date() : dateMouvement,
      type: req.body.type,
      quantite,
      utilisateur: auteur,
      bandeId: req.body.bandeId,
      motif: req.body.motif,
      fournisseur: req.body.fournisseur,
      coutUnitaire: Number.isNaN(coutUnitaire) ? stock.prixUnitaire || 0 : coutUnitaire,
    });

    if (mouvement.type === 'sortie') {
      if (stock.quantiteActuelle < mouvement.quantite) {
        return res.status(400).json({ message: 'Stock insuffisant' });
      }
    } else if (mouvement.type !== 'entree' && mouvement.type !== 'ajustement') {
      return res.status(400).json({ message: 'Type de mouvement invalide' });
    }

    stock.mouvements.push(mouvement);
    stock.quantiteActuelle = mouvement.type === 'ajustement'
      ? Number(mouvement.quantite || 0)
      : recalculerQuantite(stock.mouvements);
    if ((mouvement.type === 'entree' || mouvement.type === 'ajustement') && !Number.isNaN(coutUnitaire) && coutUnitaire > 0) {
      stock.prixUnitaire = coutUnitaire;
    }

    if (stock.quantiteActuelle < 0) {
      return res.status(400).json({ message: 'Mouvement invalide: le stock deviendrait négatif' });
    }

    if (mouvement.type === 'entree') {
      const montantEntree = Number(mouvement.quantite || 0) * Number(mouvement.coutUnitaire || 0);
      if (montantEntree > 0) {
        const userName = extraireNomPrenomUtilisateur(req.user);
        await enregistrerMouvement({
          nature: 'sortie',
          source: 'stock_entree',
          quiNom: userName.quiNom,
          quiPrenom: userName.quiPrenom,
          categorie: stock.categorie || 'consommable',
          type: stock.nom || 'stock',
          montant: montantEntree,
          date: mouvement.date,
          commentaire: mouvement.motif || `Entrée stock ${stock.nom}`,
          referenceType: 'Stock',
          referenceId: stock._id,
          externeCle: buildStockMovementKey(stock._id, mouvement._id),
        });
      }
    }

    const stockMAJ = await stock.save();
    res.json(stockMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.delete('/:id/mouvements/:mouvementId', async (req, res) => {
  try {
    const stock = await Stock.findById(req.params.id);
    if (!stock) return res.status(404).json({ message: 'Stock non trouvé' });

    const mouvement = stock.mouvements.id(req.params.mouvementId);
    if (!mouvement) {
      return res.status(404).json({ message: 'Mouvement non trouvé' });
    }

    const mouvementsRestants = stock.mouvements.filter(
      (item) => item._id.toString() !== req.params.mouvementId,
    );
    const nouvelleQuantite = recalculerQuantite(mouvementsRestants);
    if (nouvelleQuantite < 0) {
      return res.status(400).json({ message: 'Suppression impossible: le stock deviendrait négatif' });
    }

    stock.mouvements = mouvementsRestants;
    stock.quantiteActuelle = nouvelleQuantite;
    await stock.save();

    await TresorerieMouvement.deleteMany({
      externeCle: buildStockMovementKey(stock._id, req.params.mouvementId),
    });

    res.json(stock);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.delete('/:id/mouvements', async (req, res) => {
  try {
    const stock = await Stock.findById(req.params.id);
    if (!stock) return res.status(404).json({ message: 'Stock non trouvé' });

    const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';
    const snapshot = stock.mouvements.create({
      date: new Date(),
      type: 'ajustement',
      quantite: Number(stock.quantiteActuelle || 0),
      utilisateur: auteur,
      motif: 'Historique réinitialisé',
      coutUnitaire: Number(stock.prixUnitaire || 0),
    });

    stock.mouvements = [snapshot];
    await stock.save();

    res.json(stock);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Historique des mouvements d'un stock
router.get('/:id/mouvements', async (req, res) => {
  try {
    const stock = await Stock.findById(req.params.id).select('nom unite mouvements');
    if (!stock) return res.status(404).json({ message: 'Stock non trouvé' });

    const mouvements = [...(stock.mouvements || [])]
      .sort((a, b) => new Date(b.date) - new Date(a.date));

    res.json({
      stockId: stock._id,
      nom: stock.nom,
      unite: stock.unite,
      mouvements,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Mettre à jour un stock
router.put('/:id', async (req, res) => {
  try {
    const stock = await Stock.findById(req.params.id);
    if (!stock) return res.status(404).json({ message: 'Stock non trouvé' });
    Object.assign(stock, req.body);
    const stockMAJ = await stock.save();
    res.json(stockMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Supprimer un stock
router.delete('/:id', async (req, res) => {
  try {
    const stock = await Stock.findById(req.params.id);
    if (!stock) return res.status(404).json({ message: 'Stock non trouvé' });
    await stock.deleteOne();
    res.json({ message: 'Stock supprimé' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
