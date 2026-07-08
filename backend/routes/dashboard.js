const express = require('express');
const router = express.Router();
const Bande = require('../models/Bande');
const Commande = require('../models/Commande');
const Client = require('../models/Client');
const Depense = require('../models/Depense');
const Stock = require('../models/Stock');
const AppConfig = require('../models/AppConfig');

function getDateFilter(period) {
  const now = new Date();
  const start = new Date(now);

  switch (period) {
    case 'jour':
      start.setHours(0, 0, 0, 0);
      break;
    case 'semaine':
      start.setDate(now.getDate() - 7);
      break;
    case 'mois':
      start.setMonth(now.getMonth() - 1);
      break;
    case 'annee':
      start.setFullYear(now.getFullYear() - 1);
      break;
    default:
      start.setMonth(now.getMonth() - 1);
  }

  return { $gte: start, $lte: now };
}

// Dashboard global KPI
router.get('/global', async (req, res) => {
  try {
    const period = req.query.period || 'mois';
    const bandeId = req.query.bandeId || '';
    const batiment = req.query.batiment || '';
    const dateFilter = getDateFilter(period);
    const commandeFilter = { createdAt: dateFilter };
    const depenseFilter = { date: dateFilter };
    const bandeFilter = {};

    if (batiment) {
      bandeFilter.batiment = batiment;
    }

    if (bandeId) {
      bandeFilter._id = bandeId;
    }

    const bandes = await Bande.find(bandeFilter);
    const bandeIds = bandes.map((b) => b._id);

    if (bandeId) {
      commandeFilter.bande = bandeId;
      depenseFilter.bandeId = bandeId;
    } else if (batiment) {
      commandeFilter.bande = { $in: bandeIds };
      depenseFilter.bandeId = { $in: bandeIds };
    }

    const commandes = await Commande.find(commandeFilter);
    const depenses = await Depense.find(depenseFilter);

    const chiffreAffairesTotal = commandes.reduce((sum, c) => sum + c.montantTotal, 0);
    const depensesTotales = depenses.reduce((sum, d) => sum + d.montant, 0);
    const beneficeNet = chiffreAffairesTotal - depensesTotales;
    const marge = chiffreAffairesTotal > 0 ? (beneficeNet / chiffreAffairesTotal) * 100 : 0;

    const consoAliment = bandes.reduce((total, b) => (
      total + b.suiviJournalier.reduce((s, j) => s + (j.alimentationKg || 0), 0)
    ), 0);

    const effectifInitial = bandes.reduce((sum, b) => sum + (b.nombreInitial || 0), 0);
    const mortaliteTotale = bandes.reduce((sum, b) => sum + (b.mortaliteTotale || 0), 0);
    const tauxMortalite = effectifInitial > 0 ? (mortaliteTotale / effectifInitial) * 100 : 0;

    const clientIds = [...new Set(commandes.map((commande) => String(commande.client)).filter(Boolean))];
    const clientsActifs = bandeId
      ? await Client.countDocuments({ _id: { $in: clientIds }, statut: 'actif' })
      : await Client.countDocuments({ statut: 'actif' });
    const nbCommandes = commandes.length;

    const commandesEnAttente = await Commande.countDocuments({
      ...(bandeId ? { bande: bandeId } : {}),
      statut: 'en_attente'
    });

    const ventesParPeriode = await Commande.aggregate([
      { $match: commandeFilter },
      {
        $group: {
          _id: {
            y: { $year: '$createdAt' },
            m: { $month: '$createdAt' },
            d: { $dayOfMonth: '$createdAt' }
          },
          total: { $sum: '$montantTotal' }
        }
      },
      { $sort: { '_id.y': 1, '_id.m': 1, '_id.d': 1 } },
      { $limit: 60 }
    ]);

    const depensesParPeriode = await Depense.aggregate([
      { $match: depenseFilter },
      {
        $group: {
          _id: {
            y: { $year: '$date' },
            m: { $month: '$date' },
            d: { $dayOfMonth: '$date' }
          },
          total: { $sum: '$montant' }
        }
      },
      { $sort: { '_id.y': 1, '_id.m': 1, '_id.d': 1 } },
      { $limit: 60 }
    ]);

    const stockBas = await Stock.countDocuments({
      $expr: { $lte: ['$quantiteActuelle', '$seuilAlerte'] }
    });

    res.json({
      period,
      bandeId: bandeId || null,
      batiment: batiment || null,
      chiffreAffairesTotal,
      depensesTotales,
      beneficeNet,
      marge,
      consoAliment,
      tauxMortalite,
      clientsActifs,
      nbCommandes,
      commandesEnAttente,
      stockBas,
      ventesParPeriode,
      depensesParPeriode
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Dashboard bande détaillé (croissance, conso, mortalité histogram)
function interpolerValeurCourbe(points, age, key) {
  const valides = points
    .filter((p) => Number(p.age) > 0 && p[key] != null && !Number.isNaN(Number(p[key])))
    .sort((a, b) => Number(a.age) - Number(b.age));

  if (valides.length === 0) return null;
  const exact = valides.find((p) => Number(p.age) === age);
  if (exact) return Number(exact[key]);

  const avant = [...valides].reverse().find((p) => Number(p.age) < age);
  const apres = valides.find((p) => Number(p.age) > age);

  if (avant && apres) {
    const ratio = (age - Number(avant.age)) / (Number(apres.age) - Number(avant.age));
    return Number(avant[key]) + (Number(apres[key]) - Number(avant[key])) * ratio;
  }
  if (avant) return Number(avant[key]);
  if (apres) return Number(apres[key]);
  return null;
}

router.get('/bandes/:id/suivi', async (req, res) => {
  try {
    const bande = await Bande.findById(req.params.id);
    if (!bande) return res.status(404).json({ message: 'Bande non trouvée' });
    const config = await AppConfig.findOne({ key: 'main' });

    const growth = bande.suiviJournalier.map((s, idx) => ({
      age: idx + 1,
      poids: s.poidsMotenG || 0,
      date: s.date
    }));

    const conso = bande.suiviJournalier.map((s, idx) => ({
      age: idx + 1,
      alimentKg: s.alimentationKg || 0,
      cumulKg: bande.suiviJournalier.slice(0, idx + 1).reduce((sum, i) => sum + (i.alimentationKg || 0), 0),
      date: s.date
    }));

    const references = (config && config.referencesTheoriques) || {};
    const refType = references[bande.typeVolaille] || references.autre || { dureeJours: 45, poidsFinalG: 2500, consoTotaleKgParTete: 5.0 };
    const dureeRef = Number(refType.dureeJours || bande.dureeElevageJours || 45);
    const poidsFinalRef = Number(refType.poidsFinalG || bande.objectifPoidsG || 2500);
    const consoTotaleRef = Number(refType.consoTotaleKgParTete || 5.0) * Number(bande.nombreInitial || 0);
    const courbeTheorique = Array.isArray(refType.courbeTheorique) ? refType.courbeTheorique : [];
    const maxAgeCourbe = courbeTheorique.reduce((max, p) => {
      const age = Number(p?.age || 0);
      return age > max ? age : max;
    }, 0);
    const maxAge = Math.max(growth.length, dureeRef, Number(bande.ageJours || 0), maxAgeCourbe);

    const theoriqueGrowth = Array.from({ length: maxAge }, (_, idx) => {
      const age = idx + 1;
      const poidsCourbe = interpolerValeurCourbe(courbeTheorique, age, 'poidsG');
      if (poidsCourbe != null) {
        return { age, poids: Number(poidsCourbe.toFixed(2)) };
      }
      const p = Math.min(age / Math.max(dureeRef, 1), 1);
      return {
        age,
        poids: Number((bande.poidsArriveeG + (poidsFinalRef - bande.poidsArriveeG) * p).toFixed(2))
      };
    });

    const theoriqueConso = [];
    for (let idx = 0; idx < maxAge; idx += 1) {
      const age = idx + 1;
      const cumulCourbe = interpolerValeurCourbe(courbeTheorique, age, 'consoCumuleeKg');
      if (cumulCourbe != null) {
        const prevCourbe = idx === 0 ? 0 : Number(theoriqueConso[idx - 1].cumulKg || 0);
        theoriqueConso.push({
          age,
          alimentKg: Number((cumulCourbe - prevCourbe).toFixed(3)),
          cumulKg: Number(cumulCourbe.toFixed(3))
        });
        continue;
      }
      const p = Math.min(age / Math.max(dureeRef, 1), 1);
      const cumulKg = Number((consoTotaleRef * p).toFixed(3));
      const prev = idx === 0 ? 0 : Number((consoTotaleRef * Math.min(idx / Math.max(dureeRef, 1), 1)).toFixed(3));
      theoriqueConso.push({
        age,
        alimentKg: Number((cumulKg - prev).toFixed(3)),
        cumulKg
      });
    }

    const mortaliteJour = bande.suiviJournalier.map((s, idx) => ({
      age: idx + 1,
      mortalite: s.mortaliteJour || 0,
      date: s.date
    }));

    const mortaliteCumulee = bande.nombreInitial > 0
      ? ((bande.mortaliteTotale / bande.nombreInitial) * 100)
      : 0;

    const recent = bande.suiviJournalier.slice(-3);
    const dailyGains = [];
    for (let i = 1; i < recent.length; i += 1) {
      dailyGains.push((recent[i].poidsMotenG || 0) - (recent[i - 1].poidsMotenG || 0));
    }
    const avgGainPoids = dailyGains.length ? dailyGains.reduce((a, b) => a + b, 0) / dailyGains.length : 0;
    const avgConsoJour = recent.length ? recent.reduce((s, r) => s + (r.alimentationKg || 0), 0) / recent.length : 0;
    const avgMortaliteJour = recent.length ? recent.reduce((s, r) => s + (r.mortaliteJour || 0), 0) / recent.length : 0;

    const currentAge = growth.length;
    const currentPoids = growth.length ? growth[growth.length - 1].poids : (bande.poidsArriveeG || 0);
    const currentConsoCumul = conso.length ? conso[conso.length - 1].cumulKg : 0;
    const forecast7j = Array.from({ length: 7 }, (_, idx) => {
      const day = idx + 1;
      const age = currentAge + day;
      return {
        age,
        poidsProjete: Number((currentPoids + avgGainPoids * day).toFixed(2)),
        consoJourProjeteeKg: Number(avgConsoJour.toFixed(3)),
        consoCumulProjeteeKg: Number((currentConsoCumul + avgConsoJour * day).toFixed(3)),
        mortaliteJourProjetee: Number(avgMortaliteJour.toFixed(2))
      };
    });

    const horizon = forecast7j[forecast7j.length - 1] || null;
    const refHorizonGrowth = horizon ? theoriqueGrowth.find((p) => p.age === horizon.age) : null;
    const refHorizonConso = horizon ? theoriqueConso.find((p) => p.age === horizon.age) : null;
    const ecartPoidsPct = horizon && refHorizonGrowth && refHorizonGrowth.poids > 0
      ? ((horizon.poidsProjete - refHorizonGrowth.poids) / refHorizonGrowth.poids) * 100
      : 0;
    const ecartConsoPct = horizon && refHorizonConso && refHorizonConso.cumulKg > 0
      ? ((horizon.consoCumulProjeteeKg - refHorizonConso.cumulKg) / refHorizonConso.cumulKg) * 100
      : 0;

    const eventsPrevisionnels = [];
    if (horizon && refHorizonGrowth && horizon.poidsProjete < refHorizonGrowth.poids * 0.9) {
      eventsPrevisionnels.push({
        type: 'retard_croissance',
        severite: 'haute',
        message: `Risque de retard de croissance à J+7 (${horizon.poidsProjete.toFixed(0)}g vs ${refHorizonGrowth.poids.toFixed(0)}g attendu)`
      });
    }
    if (horizon && refHorizonConso && horizon.consoCumulProjeteeKg > refHorizonConso.cumulKg * 1.15) {
      eventsPrevisionnels.push({
        type: 'surconsommation',
        severite: 'moyenne',
        message: `Surconsommation probable à J+7 (${horizon.consoCumulProjeteeKg.toFixed(1)}kg vs ${refHorizonConso.cumulKg.toFixed(1)}kg attendu)`
      });
    }
    const mortaliteProj7j = avgMortaliteJour * 7;
    if (bande.nombreInitial > 0 && (mortaliteProj7j / bande.nombreInitial) > 0.02) {
      eventsPrevisionnels.push({
        type: 'risque_mortalite',
        severite: 'haute',
        message: `Mortalité projetée élevée sur 7 jours (${mortaliteProj7j.toFixed(1)} sujets)`
      });
    }

    const performance = {
      effectifInitial: bande.nombreInitial,
      effectifRestant: bande.nombreActuel,
      mortaliteCumulee,
      consommationCumuleeKg: conso.length ? conso[conso.length - 1].cumulKg : 0,
      poidsMoyenFinal: growth.length ? growth[growth.length - 1].poids : 0,
      ecartPoidsTheoriquePct: Number(ecartPoidsPct.toFixed(2)),
      ecartConsoTheoriquePct: Number(ecartConsoPct.toFixed(2))
    };

    res.json({
      bande: {
        id: bande._id,
        nom: bande.nom,
        batiment: bande.batiment,
        statut: bande.statut
      },
      growth,
      theoriqueGrowth,
      conso,
      theoriqueConso,
      mortaliteJour,
      forecast7j,
      eventsPrevisionnels,
      performance,
      vaccins: bande.evenementsSante.filter(e => e.type === 'vaccination'),
      interventions: bande.evenementsSante
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
