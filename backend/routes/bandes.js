const express = require('express');
const crypto = require('crypto');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

function toArray(value) {
  return Array.isArray(value) ? value : [];
}

function getUserLabel(req) {
  return req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';
}

function getUserName(req) {
  const full = (req.user?.nomComplet || req.user?.fullName || '').toString().trim();
  if (full) {
    const parts = full.split(/\s+/).filter(Boolean);
    if (parts.length === 1) return { quiNom: parts[0], quiPrenom: parts[0] };
    return { quiNom: parts.slice(1).join(' '), quiPrenom: parts[0] };
  }
  const email = (req.user?.email || '').toString();
  const local = email.includes('@') ? email.split('@')[0] : email;
  return { quiNom: local || 'Utilisateur', quiPrenom: local || 'Utilisateur' };
}

function isoOrNow(value) {
  const d = value ? new Date(value) : new Date();
  return Number.isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

function mapBandeRow(row) {
  const dateOuverture = row.date_ouverture || new Date().toISOString();
  const dateFermeture = row.date_fermeture || null;
  const fin = dateFermeture ? new Date(dateFermeture) : new Date();
  const debut = new Date(dateOuverture);
  const ageJours = Math.max(0, Math.floor((fin.getTime() - debut.getTime()) / (1000 * 60 * 60 * 24)));

  const nombreInitial = Number(row.nombre_initial || 0);
  const mortaliteTotale = Number(row.mortalite_totale || 0);
  const tauxMortalite = nombreInitial > 0 ? ((mortaliteTotale / nombreInitial) * 100).toFixed(2) : '0.00';

  const suiviJournalier = toArray(row.suivi_journalier).map((s) => ({
    _id: s._id || crypto.randomUUID(),
    date: s.date || new Date().toISOString(),
    poidsMotenG: Number(s.poidsMotenG || 0),
    mortaliteJour: Number(s.mortaliteJour || 0),
    alimentationKg: Number(s.alimentationKg || 0),
    alimentationStockId: s.alimentationStockId || null,
    alimentationType: s.alimentationType || '',
    eauLitres: Number(s.eauLitres || 0),
    temperature: Number(s.temperature || 0),
    humidite: Number(s.humidite || 0),
    observations: s.observations || '',
  }));

  const evenementsSante = toArray(row.evenements_sante).map((e) => ({
    _id: e._id || crypto.randomUUID(),
    date: e.date || new Date().toISOString(),
    type: e.type || 'autre',
    description: e.description || '',
    medicament: e.medicament || '',
    doseParTete: e.doseParTete || '',
    dureeJours: Number(e.dureeJours || 1),
    cout: Number(e.cout || 0),
  }));

  const evenementsPrevisionnels = toArray(row.evenements_previsionnels).map((e) => ({
    _id: e._id || crypto.randomUUID(),
    type: e.type || 'intervention_diverse',
    datePrevue: e.datePrevue || new Date().toISOString(),
    description: e.description || '',
    priorite: e.priorite || 'moyenne',
    commentaires: e.commentaires || '',
    prophylaxieStockId: e.prophylaxieStockId || null,
    prophylaxieType: e.prophylaxieType || '',
    prophylaxieQuantite: Number(e.prophylaxieQuantite || 0),
    statut: e.statut || 'planifie',
    dateRealisation: e.dateRealisation || null,
    commentairesRealisation: e.commentairesRealisation || '',
  }));

  return {
    _id: row.id,
    nom: row.nom,
    dateOuverture,
    dateFermeture,
    statut: row.statut || 'ouverte',
    typeVolaille: row.type_volaille || 'poulet_chair',
    race: row.race || '',
    fournisseurPoussins: row.fournisseur_poussins || '',
    nombreInitial,
    nombreActuel: Number(row.nombre_actuel || 0),
    mortaliteTotale,
    poidsArriveeG: Number(row.poids_arrivee_g || 0),
    objectifPoidsG: Number(row.objectif_poids_g || 0),
    dureeElevageJours: Number(row.duree_elevage_jours || 45),
    batiment: row.batiment || '',
    coutPoussin: Number(row.cout_poussin || 0),
    suiviJournalier,
    evenementsSante,
    evenementsPrevisionnels,
    notes: row.notes || '',
    ageJours,
    tauxMortalite,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getBandeOr404(api, companyId, id, res) {
  const result = await api.from('bandes').select('*').eq('company_id', companyId).eq('id', id).maybeSingle();
  if (result.error) {
    res.status(400).json({ message: result.error.message });
    return null;
  }
  if (!result.data) {
    res.status(404).json({ message: 'Cycle non trouvé' });
    return null;
  }
  return result.data;
}

router.get('/actives', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const result = await api.from('bandes').select('*').eq('company_id', companyId).eq('statut', 'ouverte').order('date_ouverture', { ascending: false });
    if (result.error) return res.status(500).json({ message: result.error.message });
    return res.json((result.data || []).map(mapBandeRow));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/historique', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const result = await api.from('bandes').select('*').eq('company_id', companyId).eq('statut', 'fermee').order('date_fermeture', { ascending: false });
    if (result.error) return res.status(500).json({ message: result.error.message });
    return res.json((result.data || []).map(mapBandeRow));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/performances/batiment', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const result = await api.from('bandes').select('*').eq('company_id', companyId);
    if (result.error) return res.status(500).json({ message: result.error.message });

    const byBatiment = new Map();
    for (const row of result.data || []) {
      const b = mapBandeRow(row);
      const key = b.batiment || 'Non renseigné';
      if (!byBatiment.has(key)) {
        byBatiment.set(key, { batiment: key, nbBandes: 0, effectifInitial: 0, effectifRestant: 0, mortalite: 0 });
      }
      const a = byBatiment.get(key);
      a.nbBandes += 1;
      a.effectifInitial += Number(b.nombreInitial || 0);
      a.effectifRestant += Number(b.nombreActuel || 0);
      a.mortalite += Number(b.mortaliteTotale || 0);
    }

    const data = [...byBatiment.values()].map((x) => ({
      ...x,
      tauxMortalite: x.effectifInitial > 0 ? (x.mortalite / x.effectifInitial) * 100 : 0,
    })).sort((a, b) => a.tauxMortalite - b.tauxMortalite);

    return res.json(data);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/comparaison', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const result = await api.from('bandes').select('*').eq('company_id', companyId).order('created_at', { ascending: false }).limit(20);
    if (result.error) return res.status(500).json({ message: result.error.message });

    const data = (result.data || []).map((row) => {
      const b = mapBandeRow(row);
      const alimentationTotale = b.suiviJournalier.reduce((s, j) => s + Number(j.alimentationKg || 0), 0);
      const dernierPoids = b.suiviJournalier.length ? Number(b.suiviJournalier[b.suiviJournalier.length - 1].poidsMotenG || 0) : 0;
      return {
        id: b._id,
        nom: b.nom,
        batiment: b.batiment,
        statut: b.statut,
        ageJours: b.ageJours,
        effectifInitial: b.nombreInitial,
        effectifRestant: b.nombreActuel,
        mortalite: b.mortaliteTotale,
        tauxMortalite: Number(b.tauxMortalite || 0),
        alimentationTotale,
        dernierPoids,
      };
    });

    return res.json(data);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const row = await getBandeOr404(api, companyId, req.params.id, res);
    if (!row) return undefined;
    return res.json(mapBandeRow(row));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id/stats', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const row = await getBandeOr404(api, companyId, req.params.id, res);
    if (!row) return undefined;

    const b = mapBandeRow(row);
    const suivis = b.suiviJournalier;
    const dernierSuivi = suivis.length ? suivis[suivis.length - 1] : null;
    const alimentationTotale = suivis.reduce((sum, s) => sum + Number(s.alimentationKg || 0), 0);
    const eauTotale = suivis.reduce((sum, s) => sum + Number(s.eauLitres || 0), 0);
    const dernierPoids = dernierSuivi ? Number(dernierSuivi.poidsMotenG || 0) : 0;
    const gainPoids = dernierPoids - Number(b.poidsArriveeG || 0);
    const indiceConsommation = dernierPoids > 0 && Number(b.nombreActuel || 0) > 0
      ? ((alimentationTotale * 1000) / (Number(b.nombreActuel || 0) * dernierPoids)).toFixed(2)
      : 0;

    return res.json({
      ageJours: b.ageJours,
      nombreActuel: b.nombreActuel,
      mortaliteTotale: b.mortaliteTotale,
      tauxMortalite: b.tauxMortalite,
      dernierPoids,
      gainPoids,
      alimentationTotale,
      eauTotale,
      indiceConsommation,
      nombreSuivisJournaliers: suivis.length,
      nombreEvenementsSante: b.evenementsSante.length,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const opened = await api.from('bandes').select('id', { count: 'exact', head: true }).eq('company_id', companyId).eq('statut', 'ouverte');
    if (opened.error) return res.status(400).json({ message: opened.error.message });
    if ((opened.count || 0) >= 2) {
      return res.status(400).json({ message: 'Maximum 2 cycles ouverts en parallèle' });
    }

    const dateOuverture = req.body.dateOuverture ? new Date(req.body.dateOuverture) : new Date();
    if (Number.isNaN(dateOuverture.getTime())) return res.status(400).json({ message: 'Date d\'ouverture invalide' });

    const payload = {
      company_id: companyId,
      nom: req.body.nom,
      date_ouverture: dateOuverture.toISOString(),
      type_volaille: req.body.typeVolaille,
      race: req.body.race,
      fournisseur_poussins: req.body.fournisseurPoussins || '',
      nombre_initial: Number(req.body.nombreInitial || 0),
      nombre_actuel: Number(req.body.nombreInitial || 0),
      poids_arrivee_g: Number(req.body.poidsArriveeG || 0),
      objectif_poids_g: Number(req.body.objectifPoidsG || 0),
      duree_elevage_jours: Number(req.body.dureeElevageJours || 45),
      batiment: req.body.batiment || '',
      cout_poussin: Number(req.body.coutPoussin || 0),
      notes: req.body.notes || '',
      updated_at: new Date().toISOString(),
    };

    const created = await api.from('bandes').insert(payload).select('*').single();
    if (created.error) return res.status(400).json({ message: created.error.message });
    return res.status(201).json(mapBandeRow(created.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const current = await getBandeOr404(api, companyId, req.params.id, res);
    if (!current) return undefined;

    const updates = {
      updated_at: new Date().toISOString(),
    };
    const map = {
      nom: 'nom',
      dateOuverture: 'date_ouverture',
      dateFermeture: 'date_fermeture',
      statut: 'statut',
      typeVolaille: 'type_volaille',
      race: 'race',
      fournisseurPoussins: 'fournisseur_poussins',
      nombreInitial: 'nombre_initial',
      nombreActuel: 'nombre_actuel',
      mortaliteTotale: 'mortalite_totale',
      poidsArriveeG: 'poids_arrivee_g',
      objectifPoidsG: 'objectif_poids_g',
      dureeElevageJours: 'duree_elevage_jours',
      batiment: 'batiment',
      coutPoussin: 'cout_poussin',
      notes: 'notes',
    };

    for (const [k, dbk] of Object.entries(map)) {
      if (Object.prototype.hasOwnProperty.call(req.body, k)) updates[dbk] = req.body[k];
    }

    const saved = await api.from('bandes').update(updates).eq('company_id', companyId).eq('id', req.params.id).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/fermer', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const saved = await api
      .from('bandes')
      .update({ statut: 'fermee', date_fermeture: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .maybeSingle();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    if (!saved.data) return res.status(404).json({ message: 'Cycle non trouvé' });
    return res.json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/:id/suivi', async (req, res) => {
  try {
    const alimentationKg = Number(req.body.alimentationKg || 0);
    const alimentationStockId = (req.body.alimentationStockId || '').toString().trim();
    const alimentationType = (req.body.alimentationType || '').toString().trim();
    const mortaliteJour = Number(req.body.mortaliteJour);
    const observations = (req.body.observations || '').toString().trim();

    if (alimentationKg <= 0 || Number.isNaN(mortaliteJour) || mortaliteJour < 0 || observations.length === 0) {
      return res.status(400).json({ message: 'Les champs obligatoires du suivi sont: alimentationKg, mortaliteJour, observations' });
    }
    if (!alimentationStockId) {
      return res.status(400).json({ message: 'Le type d\'alimentation est obligatoire pour le suivi' });
    }

    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const stockRes = await api.from('stocks').select('*').eq('company_id', companyId).eq('id', alimentationStockId).maybeSingle();
    if (stockRes.error) return res.status(400).json({ message: stockRes.error.message });
    if (!stockRes.data) return res.status(404).json({ message: 'Type d\'alimentation non trouvé en stock' });
    if (stockRes.data.categorie !== 'aliment') return res.status(400).json({ message: 'Le stock sélectionné pour l\'alimentation doit être de catégorie aliment' });
    if (Number(stockRes.data.quantite_actuelle || 0) < alimentationKg) return res.status(400).json({ message: 'Stock insuffisant pour l\'alimentation sélectionnée' });

    const suiviDateIso = isoOrNow(req.body.date);
    const suivi = {
      _id: crypto.randomUUID(),
      date: suiviDateIso,
      poidsMotenG: Number(req.body.poidsMotenG || 0),
      mortaliteJour,
      alimentationKg,
      alimentationStockId,
      alimentationType: alimentationType || stockRes.data.nom || '',
      eauLitres: Number(req.body.eauLitres || 0),
      temperature: Number(req.body.temperature || 0),
      humidite: Number(req.body.humidite || 0),
      observations,
    };

    const suivis = [...bande.suiviJournalier, suivi];
    const newMortalite = Number(bande.mortaliteTotale || 0) + mortaliteJour;
    const newNombreActuel = Math.max(0, Number(bande.nombreActuel || 0) - mortaliteJour);

    const stockMouvements = toArray(stockRes.data.mouvements);
    stockMouvements.push({
      _id: crypto.randomUUID(),
      date: suiviDateIso,
      type: 'sortie',
      quantite: alimentationKg,
      utilisateur: getUserLabel(req),
      bandeId: bande._id,
      motif: `Consommation alimentation - suivi cycle ${bande.nom}`,
      coutUnitaire: Number(stockRes.data.prix_unitaire || 0),
    });

    const stockSave = await api
      .from('stocks')
      .update({
        quantite_actuelle: Number(stockRes.data.quantite_actuelle || 0) - alimentationKg,
        mouvements: stockMouvements,
        updated_at: new Date().toISOString(),
      })
      .eq('company_id', companyId)
      .eq('id', stockRes.data.id);
    if (stockSave.error) return res.status(400).json({ message: stockSave.error.message });

    const movementAmount = alimentationKg * Number(stockRes.data.prix_unitaire || 0);
    if (movementAmount > 0) {
      const userName = getUserName(req);
      const financeSave = await api.from('tresorerie_mouvements').insert({
        company_id: companyId,
        nature: 'sortie',
        source: 'stock_sortie',
        qui_nom: userName.quiNom,
        qui_prenom: userName.quiPrenom,
        categorie: stockRes.data.categorie || 'aliment',
        type: alimentationType || stockRes.data.nom,
        montant: movementAmount,
        date_mouvement: suiviDateIso,
        commentaire: `Consommation alimentation - cycle ${bande.nom}`,
        reference_type: 'Bande',
        reference_id: bande._id,
        externe_cle: `bande:${bande._id}:suivi:${new Date(suiviDateIso).getTime()}:aliment`,
      });
      if (financeSave.error) return res.status(400).json({ message: financeSave.error.message });
    }

    const saved = await api
      .from('bandes')
      .update({
        suivi_journalier: suivis,
        mortalite_totale: newMortalite,
        nombre_actuel: newNombreActuel,
        updated_at: new Date().toISOString(),
      })
      .eq('company_id', companyId)
      .eq('id', bande._id)
      .select('*')
      .single();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/:id/poids', async (req, res) => {
  try {
    const poids = Number(req.body.poidsMotenG || 0);
    if (poids <= 0) return res.status(400).json({ message: 'Le poids moyen doit être supérieur à 0' });

    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const suivis = [...bande.suiviJournalier, {
      _id: crypto.randomUUID(),
      date: isoOrNow(req.body.date),
      poidsMotenG: poids,
      mortaliteJour: 0,
      alimentationKg: 0,
      eauLitres: 0,
      observations: req.body.observations || 'Relevé de poids',
    }];

    const saved = await api.from('bandes').update({ suivi_journalier: suivis, updated_at: new Date().toISOString() }).eq('company_id', companyId).eq('id', bande._id).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/:id/poids', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const poids = bande.suiviJournalier
      .filter((s) => Number(s.poidsMotenG || 0) > 0)
      .map((s) => ({ id: s._id, date: s.date, poidsMotenG: s.poidsMotenG, observations: s.observations || '' }))
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

    return res.json(poids);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/:id/climat', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const suivis = [...bande.suiviJournalier, {
      _id: crypto.randomUUID(),
      date: isoOrNow(req.body.date),
      poidsMotenG: 0,
      mortaliteJour: 0,
      alimentationKg: 0,
      eauLitres: 0,
      temperature: Number(req.body.temperature || 0),
      humidite: Number(req.body.humidite || 0),
      observations: req.body.observations || '',
    }];

    const saved = await api.from('bandes').update({ suivi_journalier: suivis, updated_at: new Date().toISOString() }).eq('company_id', companyId).eq('id', bande._id).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/:id/climat', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const climat = bande.suiviJournalier
      .filter((s) => Number(s.temperature || 0) > 0 || Number(s.humidite || 0) > 0)
      .map((s) => ({ id: s._id, date: s.date, temperature: s.temperature || 0, humidite: s.humidite || 0, observations: s.observations || '' }))
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

    return res.json(climat);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id/suivis', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    return res.json(mapBandeRow(bandeRow).suiviJournalier);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/:id/sante', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const sante = [...bande.evenementsSante, {
      _id: crypto.randomUUID(),
      date: isoOrNow(req.body.date),
      type: req.body.type,
      description: req.body.description,
      medicament: req.body.medicament || '',
      doseParTete: req.body.doseParTete || '',
      dureeJours: Number(req.body.dureeJours || 1),
      cout: Number(req.body.cout || 0),
    }];

    const saved = await api.from('bandes').update({ evenements_sante: sante, updated_at: new Date().toISOString() }).eq('company_id', companyId).eq('id', bande._id).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/:id/sante', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    return res.json(mapBandeRow(bandeRow).evenementsSante);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id/evenements-previsionnels', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const events = mapBandeRow(bandeRow).evenementsPrevisionnels.sort((a, b) => new Date(a.datePrevue).getTime() - new Date(b.datePrevue).getTime());
    return res.json(events);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/:id/evenements-previsionnels', async (req, res) => {
  try {
    if (!req.body.datePrevue || !req.body.description) {
      return res.status(400).json({ message: 'datePrevue et description sont obligatoires' });
    }

    const prophylaxieStockId = (req.body.prophylaxieStockId || '').toString().trim();
    const prophylaxieType = (req.body.prophylaxieType || '').toString().trim();
    const prophylaxieQuantite = Number(req.body.prophylaxieQuantite || 0);

    if (prophylaxieStockId && prophylaxieQuantite <= 0) return res.status(400).json({ message: 'La quantité prophylaxie doit être supérieure à 0' });
    if (!prophylaxieStockId && prophylaxieQuantite > 0) return res.status(400).json({ message: 'Sélectionne un consommable prophylaxie avant de saisir la quantité' });

    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const events = [...bande.evenementsPrevisionnels, {
      _id: crypto.randomUUID(),
      type: req.body.type,
      datePrevue: isoOrNow(req.body.datePrevue),
      description: req.body.description,
      priorite: req.body.priorite || 'moyenne',
      commentaires: req.body.commentaires || '',
      prophylaxieStockId: prophylaxieStockId || null,
      prophylaxieType,
      prophylaxieQuantite: prophylaxieStockId ? prophylaxieQuantite : 0,
      statut: 'planifie',
    }];

    const saved = await api.from('bandes').update({ evenements_previsionnels: events, updated_at: new Date().toISOString() }).eq('company_id', companyId).eq('id', bande._id).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/evenements-previsionnels/:eventId/terminer', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const bandeRow = await getBandeOr404(api, companyId, req.params.id, res);
    if (!bandeRow) return undefined;
    const bande = mapBandeRow(bandeRow);

    const events = [...bande.evenementsPrevisionnels];
    const idx = events.findIndex((e) => String(e._id) === String(req.params.eventId));
    if (idx === -1) return res.status(404).json({ message: 'Événement non trouvé dans ce cycle' });
    if (events[idx].statut === 'termine') return res.status(400).json({ message: 'Cet événement est déjà marqué comme terminé' });

    const consommationStockId = (req.body.prophylaxieStockId || events[idx].prophylaxieStockId || '').toString().trim();
    const consommationType = (req.body.prophylaxieType || events[idx].prophylaxieType || '').toString().trim();
    const consommationQuantite = Number(req.body.prophylaxieQuantite ?? events[idx].prophylaxieQuantite ?? 0);

    if (consommationStockId && consommationQuantite <= 0) return res.status(400).json({ message: 'La quantité prophylaxie doit être supérieure à 0' });
    if (!consommationStockId && consommationQuantite > 0) return res.status(400).json({ message: 'Sélectionne un consommable prophylaxie avant de saisir la quantité' });

    if (consommationStockId && consommationQuantite > 0) {
      const stockRes = await api.from('stocks').select('*').eq('company_id', companyId).eq('id', consommationStockId).maybeSingle();
      if (stockRes.error) return res.status(400).json({ message: stockRes.error.message });
      if (!stockRes.data) return res.status(404).json({ message: 'Consommable prophylaxie non trouvé en stock' });
      if (['aliment', 'materiel'].includes(stockRes.data.categorie)) {
        return res.status(400).json({ message: 'Le consommable prophylaxie doit être un produit consommable hors aliment/matériel' });
      }
      if (Number(stockRes.data.quantite_actuelle || 0) < consommationQuantite) {
        return res.status(400).json({ message: 'Stock insuffisant pour le consommable prophylaxie sélectionné' });
      }

      const dateRealisation = isoOrNow(req.body.dateRealisation);
      const mouvements = toArray(stockRes.data.mouvements);
      mouvements.push({
        _id: crypto.randomUUID(),
        date: dateRealisation,
        type: 'sortie',
        quantite: consommationQuantite,
        utilisateur: getUserLabel(req),
        bandeId: bande._id,
        motif: `Consommable prophylaxie - tâche réalisée (${events[idx].description})`,
        coutUnitaire: Number(stockRes.data.prix_unitaire || 0),
      });

      const saveStock = await api
        .from('stocks')
        .update({
          quantite_actuelle: Number(stockRes.data.quantite_actuelle || 0) - consommationQuantite,
          mouvements,
          updated_at: new Date().toISOString(),
        })
        .eq('company_id', companyId)
        .eq('id', stockRes.data.id);
      if (saveStock.error) return res.status(400).json({ message: saveStock.error.message });

      const montant = consommationQuantite * Number(stockRes.data.prix_unitaire || 0);
      if (montant > 0) {
        const userName = getUserName(req);
        const finance = await api.from('tresorerie_mouvements').insert({
          company_id: companyId,
          nature: 'sortie',
          source: 'stock_sortie',
          qui_nom: userName.quiNom,
          qui_prenom: userName.quiPrenom,
          categorie: stockRes.data.categorie || 'consommable',
          type: consommationType || stockRes.data.nom,
          montant,
          date_mouvement: dateRealisation,
          commentaire: `Consommable prophylaxie - tâche réalisée (${events[idx].description})`,
          reference_type: 'Bande',
          reference_id: bande._id,
          externe_cle: `bande:${bande._id}:event:${events[idx]._id}:prophylaxie`,
        });
        if (finance.error) return res.status(400).json({ message: finance.error.message });
      }

      events[idx].prophylaxieStockId = consommationStockId;
      events[idx].prophylaxieType = consommationType || stockRes.data.nom;
      events[idx].prophylaxieQuantite = consommationQuantite;
    }

    events[idx].statut = 'termine';
    events[idx].dateRealisation = isoOrNow(req.body.dateRealisation);
    events[idx].commentairesRealisation = req.body.commentairesRealisation || '';

    const saved = await api.from('bandes').update({ evenements_previsionnels: events, updated_at: new Date().toISOString() }).eq('company_id', companyId).eq('id', bande._id).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapBandeRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/:id', requireRole('admin'), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const row = await getBandeOr404(api, companyId, req.params.id, res);
    if (!row) return undefined;
    if ((row.statut || 'ouverte') !== 'fermee') {
      return res.status(400).json({ message: 'Seuls les cycles fermés peuvent être supprimés' });
    }

    const deleted = await api.from('bandes').delete().eq('company_id', companyId).eq('id', req.params.id);
    if (deleted.error) return res.status(500).json({ message: deleted.error.message });
    return res.json({ message: 'Cycle supprimé' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
