const express = require('express');
const crypto = require('crypto');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');

const router = express.Router();

function extractMissingColumn(error) {
  const message = (error?.message || '').toString();
  const match = message.match(/Could not find the '([^']+)' column/i);
  return match?.[1] || '';
}

const STOCK_COLUMN_ALIASES = {
  company_id: 'companyId',
  quantite_actuelle: 'quantiteActuelle',
  seuil_alerte: 'seuilAlerte',
  prix_unitaire: 'prixUnitaire',
  date_creation_stock: 'dateCreationStock',
  date_expiration: 'dateExpiration',
  mouvements: 'mouvement',
  updated_at: 'updatedAt',
  created_at: 'createdAt',
};

function toLegacyTresoreriePayload(payload) {
  const mapped = { ...payload };
  if (Object.prototype.hasOwnProperty.call(mapped, 'company_id')) {
    mapped.companyId = mapped.company_id;
    delete mapped.company_id;
  }
  if (Object.prototype.hasOwnProperty.call(mapped, 'qui_nom')) {
    mapped.quiNom = mapped.qui_nom;
    delete mapped.qui_nom;
  }
  if (Object.prototype.hasOwnProperty.call(mapped, 'qui_prenom')) {
    mapped.quiPrenom = mapped.qui_prenom;
    delete mapped.qui_prenom;
  }
  if (Object.prototype.hasOwnProperty.call(mapped, 'date_mouvement')) {
    mapped.date = mapped.date_mouvement;
    delete mapped.date_mouvement;
  }
  if (Object.prototype.hasOwnProperty.call(mapped, 'reference_type')) {
    mapped.referenceType = mapped.reference_type;
    delete mapped.reference_type;
  }
  if (Object.prototype.hasOwnProperty.call(mapped, 'reference_id')) {
    mapped.referenceId = mapped.reference_id;
    delete mapped.reference_id;
  }
  if (Object.prototype.hasOwnProperty.call(mapped, 'externe_cle')) {
    mapped.externeCle = mapped.externe_cle;
    delete mapped.externe_cle;
  }
  return mapped;
}

function withCategoryHint(payload) {
  const cloned = { ...payload };
  const categoryHint = (cloned.categorie || '').toString().trim();
  if (!categoryHint) return cloned;
  const originalComment = (cloned.commentaire || '').toString().trim();
  cloned.commentaire = `[Categorie: ${categoryHint}]${originalComment ? ` ${originalComment}` : ''}`;
  return cloned;
}

async function insertTresorerieCompat(api, payload) {
  let candidate = { ...payload };
  let legacyAttempted = false;

  for (let i = 0; i < 6; i += 1) {
    const result = await api.from('tresorerie_mouvements').insert(candidate);
    if (!result.error) return result;

    const missingColumn = extractMissingColumn(result.error);
    if (!missingColumn) return result;

    if (!legacyAttempted && missingColumn.includes('_')) {
      candidate = toLegacyTresoreriePayload(candidate);
      legacyAttempted = true;
      continue;
    }

    if (!Object.prototype.hasOwnProperty.call(candidate, missingColumn)) {
      return result;
    }

    if (missingColumn === 'categorie') {
      candidate = withCategoryHint(candidate);
    }

    delete candidate[missingColumn];
  }

  return {
    data: null,
    error: { message: 'Insertion tresorerie impossible: schema incompatible apres tentatives de fallback' },
  };
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

async function insertStockCompat(client, payload) {
  let candidate = { ...payload };
  let lastMissingColumn = '';

  for (let i = 0; i < 20; i += 1) {
    const result = await client.from('stocks').insert(candidate).select('*').single();
    if (!result.error) return result;

    const missingColumn = extractMissingColumn(result.error);
    if (!missingColumn) return result;
    lastMissingColumn = missingColumn;

    const alias = STOCK_COLUMN_ALIASES[missingColumn];
    if (alias && Object.prototype.hasOwnProperty.call(candidate, missingColumn) && !Object.prototype.hasOwnProperty.call(candidate, alias)) {
      candidate[alias] = candidate[missingColumn];
    }

    if (!Object.prototype.hasOwnProperty.call(candidate, missingColumn)) {
      return result;
    }

    delete candidate[missingColumn];
  }

  return {
    data: null,
    error: { message: `Creation stock impossible: schema incompatible apres tentatives de fallback (derniere colonne: ${lastMissingColumn || 'inconnue'})` },
  };
}

async function updateStockCompat(client, updateObj, companyId, stockId) {
  let candidate = { ...updateObj };
  let lastMissingColumn = '';

  for (let i = 0; i < 15; i += 1) {
    const result = await client
      .from('stocks')
      .update(candidate)
      .eq('company_id', companyId)
      .eq('id', stockId)
      .select('*')
      .single();
    if (!result.error) return result;

    const missingColumn = extractMissingColumn(result.error);
    if (!missingColumn) return result;
    lastMissingColumn = missingColumn;

    const alias = STOCK_COLUMN_ALIASES[missingColumn];
    if (alias && Object.prototype.hasOwnProperty.call(candidate, missingColumn) && !Object.prototype.hasOwnProperty.call(candidate, alias)) {
      candidate[alias] = candidate[missingColumn];
    }

    if (!Object.prototype.hasOwnProperty.call(candidate, missingColumn)) {
      return result;
    }

    delete candidate[missingColumn];
  }

  return {
    data: null,
    error: { message: `Update stock impossible: schema incompatible apres tentatives de fallback (derniere colonne: ${lastMissingColumn || 'inconnue'})` },
  };
}

function parseNumberInput(value) {
  if (typeof value === 'number') return value;
  const normalized = (value ?? '').toString().trim().replace(',', '.');
  return Number(normalized);
}

function toArray(value) {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

function readStockMouvements(row) {
  return toArray(row?.mouvements ?? row?.mouvement ?? row?.movements ?? []);
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

function mapStockRow(row) {
  const quantiteActuelle = Number(row.quantite_actuelle ?? row.quantiteActuelle ?? 0);
  const seuilAlerte = Number(row.seuil_alerte ?? row.seuilAlerte ?? 0);
  return {
    _id: row.id,
    nom: row.nom,
    categorie: row.categorie,
    unite: row.unite,
    quantiteActuelle,
    seuilAlerte,
    prixUnitaire: Number(row.prix_unitaire ?? row.prixUnitaire ?? 0),
    fournisseur: row.fournisseur || '',
    emplacement: row.emplacement || '',
    dateExpiration: row.date_expiration || row.dateExpiration || null,
    dateCreationStock: row.date_creation_stock || row.dateCreationStock || null,
    notes: row.notes || '',
    enAlerte: quantiteActuelle <= seuilAlerte,
    mouvements: readStockMouvements(row),
    createdAt: row.created_at || row.createdAt || null,
    updatedAt: row.updated_at || row.updatedAt || null,
  };
}

router.get('/', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const result = await client
      .from('stocks')
      .select('*')
      .eq('company_id', companyId)
      .order('categorie', { ascending: true })
      .order('nom', { ascending: true });

    if (result.error) return res.status(500).json({ message: result.error.message });
    return res.json((result.data || []).map(mapStockRow));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/categorie/:categorie', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const result = await client
      .from('stocks')
      .select('*')
      .eq('company_id', companyId)
      .eq('categorie', req.params.categorie)
      .order('nom', { ascending: true });

    if (result.error) return res.status(500).json({ message: result.error.message });
    return res.json((result.data || []).map(mapStockRow));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/alertes', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const result = await client.from('stocks').select('*').eq('company_id', companyId);
    if (result.error) return res.status(500).json({ message: result.error.message });

    const rows = (result.data || []).filter((s) => Number(s.quantite_actuelle || 0) <= Number(s.seuil_alerte || 0));
    return res.json(rows.map(mapStockRow));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const result = await client
      .from('stocks')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (result.error) return res.status(500).json({ message: result.error.message });
    if (!result.data) return res.status(404).json({ message: 'Stock non trouvé' });

    return res.json(mapStockRow(result.data));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
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

    if (Number.isNaN(quantiteInitiale) || quantiteInitiale < 0) return res.status(400).json({ message: 'Quantité initiale invalide' });
    if (Number.isNaN(seuilAlerte) || seuilAlerte < 0) return res.status(400).json({ message: "Seuil d'alerte invalide" });
    if (Number.isNaN(prixUnitaire) || prixUnitaire < 0) return res.status(400).json({ message: 'Prix unitaire invalide' });

    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);
    const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';

    const mouvementCreation = {
      _id: crypto.randomUUID(),
      date: dateCreation.toISOString(),
      type: 'creation',
      quantite: quantiteInitiale,
      utilisateur: auteur,
      motif: 'Création du stock',
      fournisseur: req.body.fournisseur || '',
      coutUnitaire: prixUnitaire,
    };

    const payload = {
      company_id: companyId,
      nom: req.body.nom,
      categorie: req.body.categorie,
      unite: req.body.unite,
      quantite_actuelle: quantiteInitiale,
      seuil_alerte: seuilAlerte,
      prix_unitaire: prixUnitaire,
      date_creation_stock: dateCreation.toISOString(),
      fournisseur: req.body.fournisseur || '',
      emplacement: req.body.emplacement || '',
      date_expiration: req.body.dateExpiration || null,
      notes: req.body.notes || '',
      mouvements: [mouvementCreation],
      updated_at: new Date().toISOString(),
    };

    const created = await insertStockCompat(client, payload);
    if (created.error) return res.status(400).json({ message: created.error.message });

    return res.status(201).json(mapStockRow(created.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/:id/mouvement', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const stockRes = await client
      .from('stocks')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (stockRes.error) return res.status(400).json({ message: stockRes.error.message });
    if (!stockRes.data) return res.status(404).json({ message: 'Stock non trouvé' });

    if (!req.body.date) return res.status(400).json({ message: 'La date est obligatoire' });
    const dateMouvement = new Date(req.body.date);
    if (Number.isNaN(dateMouvement.getTime())) return res.status(400).json({ message: 'Date invalide' });

    const quantite = parseNumberInput(req.body.quantite);
    if (Number.isNaN(quantite) || quantite < 0) return res.status(400).json({ message: 'Quantité invalide' });

    const mouvements = readStockMouvements(stockRes.data);
    const type = req.body.type;
    if (!['entree', 'sortie', 'ajustement'].includes(type)) {
      return res.status(400).json({ message: 'Type de mouvement invalide' });
    }

    const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';
    const coutUnitaireSaisi = req.body.coutUnitaire ?? req.body.prixUnitaire;
    const coutUnitaire = parseNumberInput(coutUnitaireSaisi);

    const mouvement = {
      _id: crypto.randomUUID(),
      date: type === 'ajustement' ? new Date().toISOString() : dateMouvement.toISOString(),
      type,
      quantite,
      utilisateur: auteur,
      bandeId: req.body.bandeId || null,
      motif: req.body.motif || '',
      fournisseur: req.body.fournisseur || '',
      coutUnitaire: Number.isNaN(coutUnitaire) ? Number(stockRes.data.prix_unitaire || 0) : coutUnitaire,
    };

    mouvements.push(mouvement);
    let quantiteActuelle;
    
    if (type === 'ajustement') {
      quantiteActuelle = Number(quantite || 0);
    } else if (mouvements.length === 1) {
      // When mouvements column is missing (production fallback), use current stock quantity
      const quantiteActuelleStock = Number(stockRes.data.quantite_actuelle ?? stockRes.data.quantiteActuelle ?? 0);
      if (type === 'entree') {
        quantiteActuelle = quantiteActuelleStock + Number(quantite || 0);
      } else if (type === 'sortie') {
        quantiteActuelle = quantiteActuelleStock - Number(quantite || 0);
      }
    } else {
      quantiteActuelle = recalculerQuantite(mouvements);
    }
    
    if (quantiteActuelle < 0) {
      return res.status(400).json({ message: 'Mouvement invalide: le stock deviendrait négatif' });
    }

    const updates = {
      mouvements,
      quantite_actuelle: quantiteActuelle,
      updated_at: new Date().toISOString(),
    };
    if ((type === 'entree' || type === 'ajustement') && !Number.isNaN(coutUnitaire) && coutUnitaire > 0) {
      updates.prix_unitaire = coutUnitaire;
    }

    const saved = await updateStockCompat(client, updates, companyId, req.params.id);
    if (saved.error) return res.status(400).json({ message: saved.error.message });

    const prevQty = Number(stockRes.data.quantite_actuelle ?? stockRes.data.quantiteActuelle ?? 0);
    const nextQty = Number(saved.data.quantite_actuelle ?? saved.data.quantiteActuelle ?? prevQty);
    const delta = nextQty - prevQty;
    const unitPrice = Number(saved.data.prix_unitaire ?? saved.data.prixUnitaire ?? stockRes.data.prix_unitaire ?? 0);
    const movementAmount = Math.abs(delta) * unitPrice;
    if (movementAmount > 0 && type !== 'ajustement' ? true : delta !== 0) {
      const userName = getUserName(req);
      let nature = 'sortie';
      let source = 'stock_entree';
      let label = 'Approvisionnement stock';

      if (type === 'sortie') {
        nature = 'entree';
        source = 'stock_sortie';
        label = 'Sortie stock valorisee';
      } else if (type === 'ajustement') {
        if (delta < 0) {
          nature = 'entree';
          source = 'stock_ajustement_sortie';
          label = 'Ajustement stock (diminution)';
        } else {
          nature = 'sortie';
          source = 'stock_ajustement_entree';
          label = 'Ajustement stock (augmentation)';
        }
      }

      const financeSave = await insertTresorerieCompat(client, {
        company_id: companyId,
        nature,
        source,
        qui_nom: userName.quiNom,
        qui_prenom: userName.quiPrenom,
        categorie: saved.data.categorie || stockRes.data.categorie || 'stock',
        type: saved.data.nom || stockRes.data.nom || 'Stock',
        montant: movementAmount,
        date_mouvement: new Date().toISOString(),
        commentaire: `${label} - ${saved.data.nom || stockRes.data.nom || 'Stock'}`,
        reference_type: 'Stock',
        reference_id: req.params.id,
        externe_cle: `stock:${req.params.id}:mouvement:${mouvement._id}`,
      });
      if (financeSave.error) return res.status(400).json({ message: financeSave.error.message });
    }

    return res.json(mapStockRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/:id/mouvements/:mouvementId', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const stockRes = await client
      .from('stocks')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (stockRes.error) return res.status(400).json({ message: stockRes.error.message });
    if (!stockRes.data) return res.status(404).json({ message: 'Stock non trouvé' });

    const mouvements = readStockMouvements(stockRes.data);
    const mouvement = mouvements.find((m) => String(m._id) === String(req.params.mouvementId));
    if (!mouvement) return res.status(404).json({ message: 'Mouvement non trouvé' });

    const mouvementsRestants = mouvements.filter((m) => String(m._id) !== String(req.params.mouvementId));
    const nouvelleQuantite = recalculerQuantite(mouvementsRestants);
    if (nouvelleQuantite < 0) {
      return res.status(400).json({ message: 'Suppression impossible: le stock deviendrait négatif' });
    }

    const saved = await updateStockCompat(client, {
      mouvements: mouvementsRestants,
      quantite_actuelle: nouvelleQuantite,
      updated_at: new Date().toISOString(),
    }, companyId, req.params.id);

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapStockRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/:id/mouvements', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const stockRes = await client
      .from('stocks')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (stockRes.error) return res.status(400).json({ message: stockRes.error.message });
    if (!stockRes.data) return res.status(404).json({ message: 'Stock non trouvé' });

    const auteur = req.user?.email || req.user?.nomComplet || req.user?.nom || 'Utilisateur';
    const snapshot = {
      _id: crypto.randomUUID(),
      date: new Date().toISOString(),
      type: 'ajustement',
      quantite: Number(stockRes.data.quantite_actuelle || 0),
      utilisateur: auteur,
      motif: 'Historique réinitialisé',
      coutUnitaire: Number(stockRes.data.prix_unitaire || 0),
    };

    const saved = await updateStockCompat(client, {
      mouvements: [snapshot],
      updated_at: new Date().toISOString(),
    }, companyId, req.params.id);

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapStockRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/:id/mouvements', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const stockRes = await client
      .from('stocks')
      .select('id,nom,unite,mouvements')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (stockRes.error) return res.status(500).json({ message: stockRes.error.message });
    if (!stockRes.data) return res.status(404).json({ message: 'Stock non trouvé' });

    const mouvements = readStockMouvements(stockRes.data).sort((a, b) => new Date(b.date) - new Date(a.date));

    return res.json({
      stockId: stockRes.data.id,
      nom: stockRes.data.nom,
      unite: stockRes.data.unite,
      mouvements,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const updates = { updated_at: new Date().toISOString() };

    if (req.body.nom !== undefined) updates.nom = req.body.nom;
    if (req.body.categorie !== undefined) updates.categorie = req.body.categorie;
    if (req.body.unite !== undefined) updates.unite = req.body.unite;
    if (req.body.quantiteActuelle !== undefined) updates.quantite_actuelle = Number(req.body.quantiteActuelle || 0);
    if (req.body.seuilAlerte !== undefined) updates.seuil_alerte = Number(req.body.seuilAlerte || 0);
    if (req.body.prixUnitaire !== undefined) updates.prix_unitaire = Number(req.body.prixUnitaire || 0);
    if (req.body.fournisseur !== undefined) updates.fournisseur = req.body.fournisseur;
    if (req.body.emplacement !== undefined) updates.emplacement = req.body.emplacement;
    if (req.body.dateExpiration !== undefined) updates.date_expiration = req.body.dateExpiration;
    if (req.body.notes !== undefined) updates.notes = req.body.notes;

    const saved = await client
      .from('stocks')
      .update(updates)
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .maybeSingle();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    if (!saved.data) return res.status(404).json({ message: 'Stock non trouvé' });

    return res.json(mapStockRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const removed = await client
      .from('stocks')
      .delete()
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('id')
      .maybeSingle();

    if (removed.error) return res.status(500).json({ message: removed.error.message });
    if (!removed.data) return res.status(404).json({ message: 'Stock non trouvé' });

    return res.json({ message: 'Stock supprimé' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
