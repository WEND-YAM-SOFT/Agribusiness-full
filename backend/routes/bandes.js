const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Bande = require('../models/Bande');
const Stock = require('../models/Stock');
const { requireRole } = require('../middleware/auth');
const { enregistrerMouvement, extraireNomPrenomUtilisateur } = require('../services/finance_service');

// Obtenir tous les cycles actifs (ouverts)
router.get('/actives', async (req, res) => {
  try {
    const bandes = await Bande.find({ statut: 'ouverte' });
    res.json(bandes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir l'historique des cycles fermés
router.get('/historique', async (req, res) => {
  try {
    const bandes = await Bande.find({ statut: 'fermee' }).sort({ dateFermeture: -1 });
    res.json(bandes);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Performance par batiment
router.get('/performances/batiment', async (req, res) => {
  try {
    const data = await Bande.aggregate([
      {
        $group: {
          _id: '$batiment',
          nbBandes: { $sum: 1 },
          effectifInitial: { $sum: '$nombreInitial' },
          effectifRestant: { $sum: '$nombreActuel' },
          mortalite: { $sum: '$mortaliteTotale' }
        }
      },
      {
        $project: {
          batiment: { $ifNull: ['$_id', 'Non renseigné'] },
          nbBandes: 1,
          effectifInitial: 1,
          effectifRestant: 1,
          mortalite: 1,
          tauxMortalite: {
            $cond: [
              { $gt: ['$effectifInitial', 0] },
              { $multiply: [{ $divide: ['$mortalite', '$effectifInitial'] }, 100] },
              0
            ]
          }
        }
      },
      { $sort: { tauxMortalite: 1 } }
    ]);

    res.json(data);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Comparaison de performances entre cycles
router.get('/comparaison', async (req, res) => {
  try {
    const bandes = await Bande.find().sort({ createdAt: -1 }).limit(20);

    const comparaison = bandes.map((b) => {
      const alimentationTotale = b.suiviJournalier.reduce((s, j) => s + (j.alimentationKg || 0), 0);
      const dernierPoids = b.suiviJournalier.length
        ? b.suiviJournalier[b.suiviJournalier.length - 1].poidsMotenG
        : 0;

      return {
        id: b._id,
        nom: b.nom,
        batiment: b.batiment,
        statut: b.statut,
        ageJours: b.ageJours,
        effectifInitial: b.nombreInitial,
        effectifRestant: b.nombreActuel,
        mortalite: b.mortaliteTotale,
        tauxMortalite: Number(b.tauxMortalite),
        alimentationTotale,
        dernierPoids
      };
    });

    res.json(comparaison);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir un cycle par ID
router.get('/:id', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });
    res.json(bande);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Statistiques d'un cycle
router.get('/:id/stats', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    const suivis = bande.suiviJournalier;
    const dernierSuivi = suivis.length > 0 ? suivis[suivis.length - 1] : null;
    const alimentationTotale = suivis.reduce((sum, s) => sum + s.alimentationKg, 0);
    const eauTotale = suivis.reduce((sum, s) => sum + s.eauLitres, 0);
    const dernierPoids = dernierSuivi ? dernierSuivi.poidsMotenG : 0;
    const gainPoids = dernierPoids - bande.poidsArriveeG;
    const indiceConsommation = dernierPoids > 0 ? ((alimentationTotale * 1000) / (bande.nombreActuel * dernierPoids)).toFixed(2) : 0;

    res.json({
      ageJours: bande.ageJours,
      nombreActuel: bande.nombreActuel,
      mortaliteTotale: bande.mortaliteTotale,
      tauxMortalite: bande.tauxMortalite,
      dernierPoids,
      gainPoids,
      alimentationTotale,
      eauTotale,
      indiceConsommation,
      nombreSuivisJournaliers: suivis.length,
      nombreEvenementsSante: bande.evenementsSante.length
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Ouvrir un nouveau cycle
router.post('/', async (req, res) => {
  const bandesOuvertes = await Bande.countDocuments({ statut: 'ouverte' });
  if (bandesOuvertes >= 2) {
    return res.status(400).json({ message: 'Maximum 2 cycles ouverts en parallèle' });
  }

  const dateOuverture = req.body.dateOuverture ? new Date(req.body.dateOuverture) : new Date();
  if (Number.isNaN(dateOuverture.getTime())) {
    return res.status(400).json({ message: 'Date d\'ouverture invalide' });
  }

  const bande = new Bande({
    nom: req.body.nom,
    dateOuverture,
    typeVolaille: req.body.typeVolaille,
    race: req.body.race,
    fournisseurPoussins: req.body.fournisseurPoussins,
    nombreInitial: req.body.nombreInitial,
    nombreActuel: req.body.nombreInitial,
    poidsArriveeG: req.body.poidsArriveeG,
    objectifPoidsG: req.body.objectifPoidsG,
    dureeElevageJours: req.body.dureeElevageJours,
    batiment: req.body.batiment,
    coutPoussin: req.body.coutPoussin,
    notes: req.body.notes
  });

  try {
    const nouvelleBande = await bande.save();
    res.status(201).json(nouvelleBande);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Mettre à jour un cycle
router.put('/:id', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });
    Object.assign(bande, req.body);
    const bandeMAJ = await bande.save();
    res.json(bandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Fermer un cycle
router.put('/:id/fermer', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });
    bande.statut = 'fermee';
    bande.dateFermeture = new Date();
    const bandeFermee = await bande.save();
    res.json(bandeFermee);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// --- SUIVI JOURNALIER ---

// Ajouter un suivi journalier
router.post('/:id/suivi', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    const alimentationKg = Number(req.body.alimentationKg || 0);
    const alimentationStockId = (req.body.alimentationStockId || '').toString().trim();
    const alimentationType = (req.body.alimentationType || '').toString().trim();
    const mortaliteJour = Number(req.body.mortaliteJour);
    const observations = (req.body.observations || '').toString().trim();
    if (alimentationKg <= 0 || Number.isNaN(mortaliteJour) || mortaliteJour < 0 || observations.length === 0) {
      return res.status(400).json({
        message: 'Les champs obligatoires du suivi sont: alimentationKg, mortaliteJour, observations'
      });
    }
    if (!alimentationStockId) {
      return res.status(400).json({ message: 'Le type d\'alimentation est obligatoire pour le suivi' });
    }
    if (!mongoose.Types.ObjectId.isValid(alimentationStockId)) {
      return res.status(400).json({ message: 'Type d\'alimentation invalide' });
    }

    const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';

    const alimentStock = await Stock.findById(alimentationStockId);
    if (!alimentStock) {
      return res.status(404).json({ message: 'Type d\'alimentation non trouvé en stock' });
    }
    if (alimentStock.categorie !== 'aliment') {
      return res.status(400).json({ message: 'Le stock sélectionné pour l\'alimentation doit être de catégorie aliment' });
    }
    if (alimentStock.quantiteActuelle < alimentationKg) {
      return res.status(400).json({ message: 'Stock insuffisant pour l\'alimentation sélectionnée' });
    }

    const suiviDate = req.body.date ? new Date(req.body.date) : new Date();
    const suivi = {
      date: suiviDate,
      poidsMotenG: req.body.poidsMotenG || 0,
      mortaliteJour,
      alimentationKg,
      alimentationStockId: alimentStock._id,
      alimentationType: alimentationType || alimentStock.nom,
      eauLitres: req.body.eauLitres || 0,
      temperature: req.body.temperature || 0,
      humidite: req.body.humidite || 0,
      observations,
    };

    // Décrémenter le stock d'alimentation
    alimentStock.quantiteActuelle -= alimentationKg;
    alimentStock.mouvements.push({
      date: suiviDate,
      type: 'sortie',
      quantite: alimentationKg,
      utilisateur: auteur,
      bandeId: bande._id,
      motif: `Consommation alimentation - suivi cycle ${bande.nom}`,
    });

    const userName = extraireNomPrenomUtilisateur(req.user);
    const montantAliment = alimentationKg * Number(alimentStock.prixUnitaire || 0);
    if (montantAliment > 0) {
      await enregistrerMouvement({
        nature: 'sortie',
        source: 'stock_sortie',
        quiNom: userName.quiNom,
        quiPrenom: userName.quiPrenom,
        categorie: alimentStock.categorie || 'aliment',
        type: alimentationType || alimentStock.nom,
        montant: montantAliment,
        date: suiviDate,
        commentaire: `Consommation alimentation - cycle ${bande.nom}`,
        referenceType: 'Bande',
        referenceId: bande._id,
        externeCle: `bande:${bande._id}:suivi:${suiviDate.getTime()}:aliment`,
      });
    }

    // Mettre à jour mortalité et nombre actuel
    bande.mortaliteTotale += suivi.mortaliteJour;
    bande.nombreActuel -= suivi.mortaliteJour;
    bande.suiviJournalier.push(suivi);

    await alimentStock.save();
    const bandeMAJ = await bande.save();
    res.status(201).json(bandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Ajouter un relevé de poids (écran dédié)
router.post('/:id/poids', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    const date = req.body.date ? new Date(req.body.date) : new Date();
    const poids = Number(req.body.poidsMotenG || 0);
    if (poids <= 0) {
      return res.status(400).json({ message: 'Le poids moyen doit être supérieur à 0' });
    }

    bande.suiviJournalier.push({
      date,
      poidsMotenG: poids,
      mortaliteJour: 0,
      alimentationKg: 0,
      eauLitres: 0,
      observations: req.body.observations || 'Relevé de poids',
    });

    const bandeMAJ = await bande.save();
    res.status(201).json(bandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Historique des poids
router.get('/:id/poids', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    const poids = (bande.suiviJournalier || [])
      .filter((s) => Number(s.poidsMotenG || 0) > 0)
      .map((s) => ({
        id: s._id,
        date: s.date,
        poidsMotenG: s.poidsMotenG,
        observations: s.observations || '',
      }))
      .sort((a, b) => new Date(b.date) - new Date(a.date));

    res.json(poids);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Ajouter un relevé température/humidité (écran dédié)
router.post('/:id/climat', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    const date = req.body.date ? new Date(req.body.date) : new Date();
    const temperature = Number(req.body.temperature || 0);
    const humidite = Number(req.body.humidite || 0);

    bande.suiviJournalier.push({
      date,
      poidsMotenG: 0,
      mortaliteJour: 0,
      alimentationKg: 0,
      eauLitres: 0,
      temperature,
      humidite,
      observations: req.body.observations || '',
    });

    const bandeMAJ = await bande.save();
    res.status(201).json(bandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Historique température/humidité
router.get('/:id/climat', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    const climat = (bande.suiviJournalier || [])
      .filter((s) => Number(s.temperature || 0) > 0 || Number(s.humidite || 0) > 0)
      .map((s) => ({
        id: s._id,
        date: s.date,
        temperature: s.temperature || 0,
        humidite: s.humidite || 0,
        observations: s.observations || '',
      }))
      .sort((a, b) => new Date(b.date) - new Date(a.date));

    res.json(climat);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir tous les suivis d'un cycle
router.get('/:id/suivis', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });
    res.json(bande.suiviJournalier);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// --- EVENEMENTS SANTE ---

// Ajouter un événement santé (vaccination, traitement...)
router.post('/:id/sante', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    bande.evenementsSante.push({
      type: req.body.type,
      description: req.body.description,
      medicament: req.body.medicament,
      doseParTete: req.body.doseParTete,
      dureeJours: req.body.dureeJours,
      cout: req.body.cout
    });

    const bandeMAJ = await bande.save();
    res.status(201).json(bandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Obtenir les événements santé d'un cycle
router.get('/:id/sante', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });
    res.json(bande.evenementsSante);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// --- EVENEMENTS PREVISIONNELS ---

router.get('/:id/evenements-previsionnels', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });
    const events = (bande.evenementsPrevisionnels || []).sort((a, b) => new Date(a.datePrevue) - new Date(b.datePrevue));
    res.json(events);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.post('/:id/evenements-previsionnels', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    if (!req.body.datePrevue || !req.body.description) {
      return res.status(400).json({ message: 'datePrevue et description sont obligatoires' });
    }

    const prophylaxieStockId = (req.body.prophylaxieStockId || '').toString().trim();
    const prophylaxieType = (req.body.prophylaxieType || '').toString().trim();
    const prophylaxieQuantite = Number(req.body.prophylaxieQuantite || 0);
    if (prophylaxieStockId && !mongoose.Types.ObjectId.isValid(prophylaxieStockId)) {
      return res.status(400).json({ message: 'Type de consommable prophylaxie invalide' });
    }
    if (prophylaxieStockId && prophylaxieQuantite <= 0) {
      return res.status(400).json({ message: 'La quantité prophylaxie doit être supérieure à 0' });
    }
    if (!prophylaxieStockId && prophylaxieQuantite > 0) {
      return res.status(400).json({ message: 'Sélectionne un consommable prophylaxie avant de saisir la quantité' });
    }

    bande.evenementsPrevisionnels.push({
      type: req.body.type,
      datePrevue: req.body.datePrevue,
      description: req.body.description,
      priorite: req.body.priorite,
      commentaires: req.body.commentaires || '',
      prophylaxieStockId: prophylaxieStockId || null,
      prophylaxieType,
      prophylaxieQuantite: prophylaxieStockId ? prophylaxieQuantite : 0,
      statut: 'planifie',
    });

    const bandeMAJ = await bande.save();
    res.status(201).json(bandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.put('/:id/evenements-previsionnels/:eventId/terminer', async (req, res) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ message: 'ID cycle invalide' });
    }
    if (!mongoose.Types.ObjectId.isValid(req.params.eventId)) {
      return res.status(400).json({ message: 'ID événement invalide' });
    }

    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });

    const evt = bande.evenementsPrevisionnels.id(req.params.eventId);
    if (!evt) return res.status(404).json({ message: 'Événement non trouvé dans ce cycle' });
    if (evt.statut === 'termine') {
      return res.status(400).json({ message: 'Cet événement est déjà marqué comme terminé' });
    }

    const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';
    const consommationStockId = (req.body.prophylaxieStockId || evt.prophylaxieStockId || '').toString().trim();
    const consommationType = (req.body.prophylaxieType || evt.prophylaxieType || '').toString().trim();
    const consommationQuantite = Number(req.body.prophylaxieQuantite ?? evt.prophylaxieQuantite ?? 0);

    if (consommationStockId && !mongoose.Types.ObjectId.isValid(consommationStockId)) {
      return res.status(400).json({ message: 'Type de consommable prophylaxie invalide' });
    }
    if (consommationStockId && consommationQuantite <= 0) {
      return res.status(400).json({ message: 'La quantité prophylaxie doit être supérieure à 0' });
    }
    if (!consommationStockId && consommationQuantite > 0) {
      return res.status(400).json({ message: 'Sélectionne un consommable prophylaxie avant de saisir la quantité' });
    }

    if (consommationStockId && consommationQuantite > 0) {
      const prophylaxieStock = await Stock.findById(consommationStockId);
      if (!prophylaxieStock) {
        return res.status(404).json({ message: 'Consommable prophylaxie non trouvé en stock' });
      }
      if (prophylaxieStock.categorie === 'aliment' || prophylaxieStock.categorie === 'materiel') {
        return res.status(400).json({ message: 'Le consommable prophylaxie doit être un produit consommable hors aliment/matériel' });
      }
      if (prophylaxieStock.quantiteActuelle < consommationQuantite) {
        return res.status(400).json({ message: 'Stock insuffisant pour le consommable prophylaxie sélectionné' });
      }

      prophylaxieStock.quantiteActuelle -= consommationQuantite;
      prophylaxieStock.mouvements.push({
        date: req.body.dateRealisation ? new Date(req.body.dateRealisation) : new Date(),
        type: 'sortie',
        quantite: consommationQuantite,
        utilisateur: auteur,
        bandeId: bande._id,
        motif: `Consommable prophylaxie - tâche réalisée (${evt.description})`,
      });

      const userName = extraireNomPrenomUtilisateur(req.user);
      const mouvementDate = req.body.dateRealisation ? new Date(req.body.dateRealisation) : new Date();
      const montantProphylaxie = consommationQuantite * Number(prophylaxieStock.prixUnitaire || 0);
      if (montantProphylaxie > 0) {
        await enregistrerMouvement({
          nature: 'sortie',
          source: 'stock_sortie',
          quiNom: userName.quiNom,
          quiPrenom: userName.quiPrenom,
          categorie: prophylaxieStock.categorie || 'consommable',
          type: consommationType || prophylaxieStock.nom,
          montant: montantProphylaxie,
          date: mouvementDate,
          commentaire: `Consommable prophylaxie - tâche réalisée (${evt.description})`,
          referenceType: 'Bande',
          referenceId: bande._id,
          externeCle: `bande:${bande._id}:event:${evt._id}:prophylaxie`,
        });
      }

      await prophylaxieStock.save();

      evt.prophylaxieStockId = prophylaxieStock._id;
      evt.prophylaxieType = consommationType || prophylaxieStock.nom;
      evt.prophylaxieQuantite = consommationQuantite;
    }

    evt.statut = 'termine';
    evt.dateRealisation = req.body.dateRealisation ? new Date(req.body.dateRealisation) : new Date();
    evt.commentairesRealisation = req.body.commentairesRealisation || '';

    const bandeMAJ = await bande.save();
    res.json(bandeMAJ);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Supprimer un cycle
router.delete('/:id', requireRole('admin'), async (req, res) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ message: 'ID cycle invalide' });
    }

    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Cycle non trouvé' });
    if (bande.statut !== 'fermee') {
      return res.status(400).json({ message: 'Seuls les cycles fermés peuvent être supprimés' });
    }

    await bande.deleteOne();
    res.json({ message: 'Cycle supprimé' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
