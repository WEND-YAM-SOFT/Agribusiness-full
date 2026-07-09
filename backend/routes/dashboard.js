const express = require('express');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');

const router = express.Router();

function toArray(value) {
  return Array.isArray(value) ? value : [];
}

function mapBande(row) {
  const dateOuverture = row.date_ouverture || new Date().toISOString();
  const dateFermeture = row.date_fermeture || null;
  const fin = dateFermeture ? new Date(dateFermeture) : new Date();
  const debut = new Date(dateOuverture);
  const ageJours = Math.max(0, Math.floor((fin.getTime() - debut.getTime()) / (1000 * 60 * 60 * 24)));

  const nombreInitial = Number(row.nombre_initial || 0);
  const mortaliteTotale = Number(row.mortalite_totale || 0);
  const tauxMortalite = nombreInitial > 0 ? ((mortaliteTotale / nombreInitial) * 100) : 0;

  return {
    _id: row.id,
    nom: row.nom,
    batiment: row.batiment || '',
    statut: row.statut || 'ouverte',
    dateOuverture,
    dateFermeture,
    ageJours,
    nombreInitial,
    nombreActuel: Number(row.nombre_actuel || 0),
    mortaliteTotale,
    tauxMortalite,
    poidsArriveeG: Number(row.poids_arrivee_g || 0),
    objectifPoidsG: Number(row.objectif_poids_g || 0),
    dureeElevageJours: Number(row.duree_elevage_jours || 45),
    typeVolaille: row.type_volaille || 'autre',
    suiviJournalier: toArray(row.suivi_journalier),
    evenementsSante: toArray(row.evenements_sante),
  };
}

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

  return { start, end: now };
}

function interpolateFromCurve(points, age, key) {
  const valid = points
    .filter((p) => Number(p.age) > 0 && p[key] != null && !Number.isNaN(Number(p[key])))
    .sort((a, b) => Number(a.age) - Number(b.age));

  if (!valid.length) return null;
  const exact = valid.find((p) => Number(p.age) === age);
  if (exact) return Number(exact[key]);

  const before = [...valid].reverse().find((p) => Number(p.age) < age);
  const after = valid.find((p) => Number(p.age) > age);

  if (before && after) {
    const ratio = (age - Number(before.age)) / (Number(after.age) - Number(before.age));
    return Number(before[key]) + (Number(after[key]) - Number(before[key])) * ratio;
  }
  if (before) return Number(before[key]);
  if (after) return Number(after[key]);
  return null;
}

router.get('/global', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const period = req.query.period || 'mois';
    const bandeId = req.query.bandeId || '';
    const batiment = req.query.batiment || '';
    const dateFilter = getDateFilter(period);

    const bandesRes = await api.from('bandes').select('*').eq('company_id', companyId);
    if (bandesRes.error) return res.status(500).json({ message: bandesRes.error.message });
    let bandes = (bandesRes.data || []).map(mapBande);

    if (batiment) bandes = bandes.filter((b) => b.batiment === batiment);
    if (bandeId) bandes = bandes.filter((b) => String(b._id) === String(bandeId));

    const bandeIds = new Set(bandes.map((b) => String(b._id)));

    const cmdRes = await api.from('commandes').select('*').eq('company_id', companyId).gte('created_at', dateFilter.start.toISOString()).lte('created_at', dateFilter.end.toISOString());
    if (cmdRes.error) return res.status(500).json({ message: cmdRes.error.message });

    let commandes = cmdRes.data || [];
    if (bandeId) {
      commandes = commandes.filter((c) => String(c.bande_id || c.bande_snapshot?._id || '') === String(bandeId));
    } else if (batiment) {
      commandes = commandes.filter((c) => bandeIds.has(String(c.bande_id || c.bande_snapshot?._id || '')));
    }

    const tresoRes = await api
      .from('tresorerie_mouvements')
      .select('*')
      .eq('company_id', companyId)
      .gte('date_mouvement', dateFilter.start.toISOString())
      .lte('date_mouvement', dateFilter.end.toISOString());
    if (tresoRes.error) return res.status(500).json({ message: tresoRes.error.message });

    const depenses = (tresoRes.data || []).filter((m) => m.nature === 'sortie');

    const chiffreAffairesTotal = commandes.reduce((sum, c) => sum + Number(c.montant_total || 0), 0);
    const depensesTotales = depenses.reduce((sum, d) => sum + Number(d.montant || 0), 0);
    const beneficeNet = chiffreAffairesTotal - depensesTotales;
    const marge = chiffreAffairesTotal > 0 ? (beneficeNet / chiffreAffairesTotal) * 100 : 0;

    const consoAliment = bandes.reduce((total, b) => (
      total + toArray(b.suiviJournalier).reduce((s, j) => s + Number(j.alimentationKg || 0), 0)
    ), 0);

    const effectifInitial = bandes.reduce((sum, b) => sum + Number(b.nombreInitial || 0), 0);
    const mortaliteTotale = bandes.reduce((sum, b) => sum + Number(b.mortaliteTotale || 0), 0);
    const tauxMortalite = effectifInitial > 0 ? (mortaliteTotale / effectifInitial) * 100 : 0;

    const clientIds = [...new Set(commandes.map((commande) => String(commande.client_id || '')).filter(Boolean))];
    const clientsRes = await api.from('clients').select('id,statut').eq('company_id', companyId);
    if (clientsRes.error) return res.status(500).json({ message: clientsRes.error.message });

    const clients = clientsRes.data || [];
    const clientsActifs = bandeId
      ? clients.filter((c) => clientIds.includes(String(c.id)) && c.statut === 'actif').length
      : clients.filter((c) => c.statut === 'actif').length;

    const nbCommandes = commandes.length;
    const commandesEnAttente = commandes.filter((c) => c.statut === 'en_attente').length;

    const ventesMap = new Map();
    for (const c of commandes) {
      const d = new Date(c.created_at);
      const key = `${d.getUTCFullYear()}-${d.getUTCMonth() + 1}-${d.getUTCDate()}`;
      ventesMap.set(key, (ventesMap.get(key) || 0) + Number(c.montant_total || 0));
    }
    const ventesParPeriode = [...ventesMap.entries()].map(([key, total]) => {
      const [y, m, d] = key.split('-').map(Number);
      return { _id: { y, m, d }, total };
    }).sort((a, b) => (a._id.y - b._id.y) || (a._id.m - b._id.m) || (a._id.d - b._id.d)).slice(-60);

    const depMap = new Map();
    for (const d of depenses) {
      const dt = new Date(d.date_mouvement);
      const key = `${dt.getUTCFullYear()}-${dt.getUTCMonth() + 1}-${dt.getUTCDate()}`;
      depMap.set(key, (depMap.get(key) || 0) + Number(d.montant || 0));
    }
    const depensesParPeriode = [...depMap.entries()].map(([key, total]) => {
      const [y, m, d] = key.split('-').map(Number);
      return { _id: { y, m, d }, total };
    }).sort((a, b) => (a._id.y - b._id.y) || (a._id.m - b._id.m) || (a._id.d - b._id.d)).slice(-60);

    const stocksRes = await api.from('stocks').select('quantite_actuelle,seuil_alerte').eq('company_id', companyId);
    if (stocksRes.error) return res.status(500).json({ message: stocksRes.error.message });
    const stockBas = (stocksRes.data || []).filter((s) => Number(s.quantite_actuelle || 0) <= Number(s.seuil_alerte || 0)).length;

    return res.json({
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
      depensesParPeriode,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/bandes/:id/suivi', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const bandeRes = await api.from('bandes').select('*').eq('company_id', companyId).eq('id', req.params.id).maybeSingle();
    if (bandeRes.error) return res.status(500).json({ message: bandeRes.error.message });
    if (!bandeRes.data) return res.status(404).json({ message: 'Bande non trouvée' });

    const bande = mapBande(bandeRes.data);
    const configRes = await api.from('app_config').select('referencesTheoriques').eq('key', 'main').maybeSingle();
    const references = configRes.error ? {} : (configRes.data?.referencesTheoriques || {});

    const growth = toArray(bande.suiviJournalier).map((s, idx) => ({ age: idx + 1, poids: Number(s.poidsMotenG || 0), date: s.date }));
    const conso = toArray(bande.suiviJournalier).map((s, idx) => ({
      age: idx + 1,
      alimentKg: Number(s.alimentationKg || 0),
      cumulKg: toArray(bande.suiviJournalier).slice(0, idx + 1).reduce((sum, i) => sum + Number(i.alimentationKg || 0), 0),
      date: s.date,
    }));

    const refType = references[bande.typeVolaille] || references.autre || { dureeJours: 45, poidsFinalG: 2500, consoTotaleKgParTete: 5.0 };
    const dureeRef = Number(refType.dureeJours || bande.dureeElevageJours || 45);
    const poidsFinalRef = Number(refType.poidsFinalG || bande.objectifPoidsG || 2500);
    const consoTotaleRef = Number(refType.consoTotaleKgParTete || 5.0) * Number(bande.nombreInitial || 0);
    const courbeTheorique = Array.isArray(refType.courbeTheorique) ? refType.courbeTheorique : [];
    const maxAgeCourbe = courbeTheorique.reduce((max, p) => Math.max(max, Number(p?.age || 0)), 0);
    const maxAge = Math.max(growth.length, dureeRef, Number(bande.ageJours || 0), maxAgeCourbe);

    const theoriqueGrowth = Array.from({ length: maxAge }, (_, idx) => {
      const age = idx + 1;
      const poidsCourbe = interpolateFromCurve(courbeTheorique, age, 'poidsG');
      if (poidsCourbe != null) return { age, poids: Number(poidsCourbe.toFixed(2)) };
      const p = Math.min(age / Math.max(dureeRef, 1), 1);
      return { age, poids: Number((Number(bande.poidsArriveeG || 0) + (poidsFinalRef - Number(bande.poidsArriveeG || 0)) * p).toFixed(2)) };
    });

    const theoriqueConso = [];
    for (let idx = 0; idx < maxAge; idx += 1) {
      const age = idx + 1;
      const cumulCourbe = interpolateFromCurve(courbeTheorique, age, 'consoCumuleeKg');
      if (cumulCourbe != null) {
        const prev = idx === 0 ? 0 : Number(theoriqueConso[idx - 1].cumulKg || 0);
        theoriqueConso.push({ age, alimentKg: Number((cumulCourbe - prev).toFixed(3)), cumulKg: Number(cumulCourbe.toFixed(3)) });
      } else {
        const p = Math.min(age / Math.max(dureeRef, 1), 1);
        const cumulKg = Number((consoTotaleRef * p).toFixed(3));
        const prev = idx === 0 ? 0 : Number((consoTotaleRef * Math.min(idx / Math.max(dureeRef, 1), 1)).toFixed(3));
        theoriqueConso.push({ age, alimentKg: Number((cumulKg - prev).toFixed(3)), cumulKg });
      }
    }

    const mortaliteJour = toArray(bande.suiviJournalier).map((s, idx) => ({ age: idx + 1, mortalite: Number(s.mortaliteJour || 0), date: s.date }));
    const mortaliteCumulee = bande.nombreInitial > 0 ? ((bande.mortaliteTotale / bande.nombreInitial) * 100) : 0;

    const recent = toArray(bande.suiviJournalier).slice(-3);
    const dailyGains = [];
    for (let i = 1; i < recent.length; i += 1) dailyGains.push(Number(recent[i].poidsMotenG || 0) - Number(recent[i - 1].poidsMotenG || 0));
    const avgGainPoids = dailyGains.length ? dailyGains.reduce((a, b) => a + b, 0) / dailyGains.length : 0;
    const avgConsoJour = recent.length ? recent.reduce((s, r) => s + Number(r.alimentationKg || 0), 0) / recent.length : 0;
    const avgMortaliteJour = recent.length ? recent.reduce((s, r) => s + Number(r.mortaliteJour || 0), 0) / recent.length : 0;

    const currentAge = growth.length;
    const currentPoids = growth.length ? growth[growth.length - 1].poids : Number(bande.poidsArriveeG || 0);
    const currentConsoCumul = conso.length ? conso[conso.length - 1].cumulKg : 0;
    const forecast7j = Array.from({ length: 7 }, (_, idx) => {
      const day = idx + 1;
      const age = currentAge + day;
      return {
        age,
        poidsProjete: Number((currentPoids + avgGainPoids * day).toFixed(2)),
        consoJourProjeteeKg: Number(avgConsoJour.toFixed(3)),
        consoCumulProjeteeKg: Number((currentConsoCumul + avgConsoJour * day).toFixed(3)),
        mortaliteJourProjetee: Number(avgMortaliteJour.toFixed(2)),
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
        message: `Risque de retard de croissance à J+7 (${horizon.poidsProjete.toFixed(0)}g vs ${refHorizonGrowth.poids.toFixed(0)}g attendu)`,
      });
    }
    if (horizon && refHorizonConso && horizon.consoCumulProjeteeKg > refHorizonConso.cumulKg * 1.15) {
      eventsPrevisionnels.push({
        type: 'surconsommation',
        severite: 'moyenne',
        message: `Surconsommation probable à J+7 (${horizon.consoCumulProjeteeKg.toFixed(1)}kg vs ${refHorizonConso.cumulKg.toFixed(1)}kg attendu)`,
      });
    }

    const mortaliteProj7j = avgMortaliteJour * 7;
    if (bande.nombreInitial > 0 && (mortaliteProj7j / bande.nombreInitial) > 0.02) {
      eventsPrevisionnels.push({
        type: 'risque_mortalite',
        severite: 'haute',
        message: `Mortalité projetée élevée sur 7 jours (${mortaliteProj7j.toFixed(1)} sujets)`,
      });
    }

    const performance = {
      effectifInitial: bande.nombreInitial,
      effectifRestant: bande.nombreActuel,
      mortaliteCumulee,
      consommationCumuleeKg: conso.length ? conso[conso.length - 1].cumulKg : 0,
      poidsMoyenFinal: growth.length ? growth[growth.length - 1].poids : 0,
      ecartPoidsTheoriquePct: Number(ecartPoidsPct.toFixed(2)),
      ecartConsoTheoriquePct: Number(ecartConsoPct.toFixed(2)),
    };

    return res.json({
      bande: { id: bande._id, nom: bande.nom, batiment: bande.batiment, statut: bande.statut },
      growth,
      theoriqueGrowth,
      conso,
      theoriqueConso,
      mortaliteJour,
      forecast7j,
      eventsPrevisionnels,
      performance,
      vaccins: toArray(bande.evenementsSante).filter((e) => e.type === 'vaccination'),
      interventions: toArray(bande.evenementsSante),
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
