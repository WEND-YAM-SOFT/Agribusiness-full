const express = require('express');
const crypto = require('crypto');
const { getAdminClient, logAudit } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');
const { requirePermission, requireAnyPermission, hasPermission } = require('../middleware/auth');

const router = express.Router();
const COMMANDES_COMPANY_COLUMNS = ['company_id', 'companyId'];
const ALLOWED_COMMANDE_STATUTS = new Set(['en_attente', 'confirmee', 'en_preparation', 'payee', 'annulee']);

function csvEscape(value) {
  const raw = value == null ? '' : String(value);
  return `"${raw.replace(/"/g, '""')}"`;
}

function toCsv(rows) {
  return rows.map((row) => row.map(csvEscape).join(',')).join('\n');
}

async function safeAudit(client, payload) {
  try {
    await logAudit(client, payload);
  } catch (e) {
    console.warn('commande audit log failed:', e?.message || e);
  }
}

function isCommandeHistorique(row) {
  return ((row?.statut || row?.status || '').toString()) === 'payee';
}

function extractMissingColumn(error) {
  const message = (error?.message || '').toString();
  const patterns = [
    /Could not find the '([^']+)' column/i,
    /column\s+"?([a-zA-Z0-9_]+)"?\s+does not exist/i,
    /column\s+[a-zA-Z0-9_]+\."?([a-zA-Z0-9_]+)"?\s+does not exist/i,
    /could not find column\s+"?([a-zA-Z0-9_]+)"?/i,
  ];

  for (const pattern of patterns) {
    const match = message.match(pattern);
    if (match?.[1]) return match[1];
  }

  return '';
}

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
    const result = await api.from('tresorerie_mouvements').insert(candidate).select('id').maybeSingle();
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
  const prenom = (req.user?.prenom || '').toString().trim();
  const nom = (req.user?.nom || '').toString().trim();
  if (prenom || nom) {
    return {
      quiNom: nom || prenom,
      quiPrenom: prenom || nom,
    };
  }

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

function getActorLabel(req) {
  const prenom = (req.user?.prenom || '').toString().trim();
  const nom = (req.user?.nom || '').toString().trim();
  const full = `${prenom} ${nom}`.trim();
  if (full) return full;

  const profileName = (req.user?.nomComplet || req.user?.fullName || '').toString().trim();
  if (profileName) return profileName;

  const email = (req.user?.email || '').toString().trim();
  if (!email) return 'Utilisateur';
  return email.includes('@') ? email.split('@')[0] : email;
}

function hasStatusPermission(req, statut) {
  if (statut === 'en_preparation' || statut === 'confirmee') {
    return hasPermission(req, 'commandes.status.prepare');
  }
  if (statut === 'payee') {
    return hasPermission(req, 'commandes.status.pay');
  }
  if (statut === 'annulee') {
    return hasPermission(req, 'commandes.status.cancel');
  }
  return false;
}

function computeProduitsTotal(row) {
  const produits = toArray(row?.produits || row?.produit || row?.products || row?.items);
  if (!produits.length) {
    return Number(row?.montant_total || row?.montantTotal || row?.amount_total || 0);
  }

  return produits.reduce((sum, p) => {
    const qte = Number(p?.quantite || p?.qte || 0);
    const prix = Number(p?.prixUnitaire || p?.prix_unitaire || p?.prix || 0);
    return sum + (qte * prix);
  }, 0);
}

function computeFraisLivraisonTotal(row) {
  const livraisons = readLivraisons(row);
  return livraisons.reduce((sum, l) => sum + Number(l?.fraisLivraison || l?.frais_livraison || 0), 0);
}

function readLivraisons(row) {
  return toArray(row?.livraisons || row?.deliveries || row?.delivery || row?.livraison);
}

function computeCommandeBaseTotal(row) {
  const produits = toArray(row?.produits || row?.produit || row?.products || row?.items);
  if (produits.length) return computeProduitsTotal(row);

  const stored = Number(row?.montant_total || row?.montantTotal || row?.amount_total || 0);
  const currentFees = computeFraisLivraisonTotal(row);
  return Math.max(0, stored - currentFees);
}

function computeCommandeTotal(row) {
  return computeCommandeBaseTotal(row) + computeFraisLivraisonTotal(row);
}

async function updateClientAfterCommandeCompat(apiClient, companyId, clientId, montant) {
  let payload = {
    dernier_contact_le: new Date().toISOString(),
    statut: 'actif',
    chiffre_affaires_cumul: Number(montant || 0),
    updated_at: new Date().toISOString(),
  };

  for (let i = 0; i < 8; i += 1) {
    let updateRes = await apiClient
      .from('clients')
      .update(payload)
      .eq('id', clientId)
      .eq('company_id', companyId);

    if (!updateRes.error) return updateRes;

    const missingOnCompany = extractMissingColumn(updateRes.error);
    if (missingOnCompany === 'company_id') {
      updateRes = await apiClient
        .from('clients')
        .update(payload)
        .eq('id', clientId)
        .eq('companyId', companyId);
      if (!updateRes.error) return updateRes;
      const missingWithLegacy = extractMissingColumn(updateRes.error);
      if (missingWithLegacy && missingWithLegacy !== 'companyId') {
        if (
          missingWithLegacy === 'chiffre_affaires_cumul'
          && Object.prototype.hasOwnProperty.call(payload, 'chiffre_affaires_cumul')
          && !Object.prototype.hasOwnProperty.call(payload, 'chiffreAffairesCumul')
        ) {
          payload.chiffreAffairesCumul = payload.chiffre_affaires_cumul;
          delete payload.chiffre_affaires_cumul;
          continue;
        }

        if (Object.prototype.hasOwnProperty.call(payload, missingWithLegacy)) {
          delete payload[missingWithLegacy];
          continue;
        }
      }
      return updateRes;
    }

    if (
      missingOnCompany === 'chiffre_affaires_cumul'
      && Object.prototype.hasOwnProperty.call(payload, 'chiffre_affaires_cumul')
      && !Object.prototype.hasOwnProperty.call(payload, 'chiffreAffairesCumul')
    ) {
      payload.chiffreAffairesCumul = payload.chiffre_affaires_cumul;
      delete payload.chiffre_affaires_cumul;
      continue;
    }

    if (
      missingOnCompany === 'dernier_contact_le'
      && Object.prototype.hasOwnProperty.call(payload, 'dernier_contact_le')
      && !Object.prototype.hasOwnProperty.call(payload, 'dernierContactLe')
    ) {
      payload.dernierContactLe = payload.dernier_contact_le;
      delete payload.dernier_contact_le;
      continue;
    }

    if (
      missingOnCompany === 'statut'
      && Object.prototype.hasOwnProperty.call(payload, 'statut')
      && !Object.prototype.hasOwnProperty.call(payload, 'status')
    ) {
      payload.status = payload.statut;
      delete payload.statut;
      continue;
    }

    if (missingOnCompany && Object.prototype.hasOwnProperty.call(payload, missingOnCompany)) {
      delete payload[missingOnCompany];
      continue;
    }

    return updateRes;
  }

  return { error: { message: 'Mise a jour client post-commande impossible apres fallback' } };
}

async function insertCommandeCompat(apiClient, payload) {
  let candidate = { ...payload };
  let lastMissingColumn = '';

  for (let i = 0; i < 15; i += 1) {
    const result = await apiClient.from('commandes').insert(candidate).select('*').single();
    if (!result.error) return result;

    const missingColumn = extractMissingColumn(result.error);
    if (!missingColumn) return result;
    lastMissingColumn = missingColumn;

    if (
      missingColumn === 'company_id'
      && Object.prototype.hasOwnProperty.call(candidate, 'company_id')
      && !Object.prototype.hasOwnProperty.call(candidate, 'companyId')
    ) {
      candidate.companyId = candidate.company_id;
    }

    if (
      missingColumn === 'bande_id'
      && Object.prototype.hasOwnProperty.call(candidate, 'bande_id')
      && !Object.prototype.hasOwnProperty.call(candidate, 'bandeId')
    ) {
      candidate.bandeId = candidate.bande_id;
    }

    applyCommandeColumnAliases(candidate, missingColumn);

    if (!Object.prototype.hasOwnProperty.call(candidate, missingColumn)) {
      return result;
    }

    delete candidate[missingColumn];
  }

  return {
    data: null,
    error: { message: `Creation commande impossible: schema incompatible apres tentatives de fallback (derniere colonne: ${lastMissingColumn || 'inconnue'})` },
  };
}

async function updateCommandeCompat(apiClient, companyId, commandeId, updateObj, useSingle = true) {
  let candidate = { ...updateObj };
  let lastMissingColumn = '';

  for (let i = 0; i < 15; i += 1) {
    let result = null;
    let hadCompatHit = false;

    for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
      const query = apiClient
        .from('commandes')
        .update(candidate)
        .eq(companyColumn, companyId)
        .eq('id', commandeId)
        .select('*');
      result = useSingle ? await query.single() : await query.maybeSingle();
      if (!result.error) return result;

      const missingCompanyColumn = extractMissingColumn(result.error);
      if (missingCompanyColumn === companyColumn) {
        hadCompatHit = true;
        continue;
      }
      break;
    }

    if (result && !result.error) return result;

    const missingColumn = extractMissingColumn(result?.error);
    if (hadCompatHit && !missingColumn) {
      continue;
    }
    if (!missingColumn) return result;
    lastMissingColumn = missingColumn;

    if (
      missingColumn === 'historique_actions'
      && Object.prototype.hasOwnProperty.call(candidate, 'historique_actions')
      && !Object.prototype.hasOwnProperty.call(candidate, 'historiqueActions')
    ) {
      candidate.historiqueActions = candidate.historique_actions;
    }
    if (
      missingColumn === 'date_livraison'
      && Object.prototype.hasOwnProperty.call(candidate, 'date_livraison')
      && !Object.prototype.hasOwnProperty.call(candidate, 'dateLivraison')
    ) {
      candidate.dateLivraison = candidate.date_livraison;
    }

    applyCommandeColumnAliases(candidate, missingColumn);

    if (!Object.prototype.hasOwnProperty.call(candidate, missingColumn)) {
      return result;
    }

    delete candidate[missingColumn];
  }

  return {
    data: null,
    error: {
      message: `Mise a jour commande impossible: schema incompatible apres fallback (derniere colonne: ${lastMissingColumn || 'inconnue'})`,
    },
  };
}

async function listCommandesCompat(apiClient, companyId, configureQuery) {
  const rowsById = new Map();
  let lastError = null;
  let hadAnySuccess = false;

  for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
    let query = apiClient.from('commandes').select('*').eq(companyColumn, companyId);
    query = configureQuery ? configureQuery(query) : query;
    const result = await query;

    if (result.error) {
      const missing = extractMissingColumn(result.error);
      if (missing === companyColumn) {
        continue;
      }
      lastError = result.error;
      continue;
    }

    hadAnySuccess = true;
    for (const row of result.data || []) {
      if (row?.id) rowsById.set(row.id, row);
    }
  }

  if (!hadAnySuccess && lastError) {
    return { data: null, error: lastError };
  }

  return { data: [...rowsById.values()], error: null };
}

async function getCommandeCompat(apiClient, companyId, commandeId) {
  let lastError = null;
  for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
    const result = await apiClient
      .from('commandes')
      .select('*')
      .eq(companyColumn, companyId)
      .eq('id', commandeId)
      .maybeSingle();

    if (!result.error) return result;

    const missing = extractMissingColumn(result.error);
    if (missing === companyColumn) continue;
    lastError = result.error;
  }

  return { data: null, error: lastError };
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

function applyCommandeColumnAliases(candidate, missingColumn) {
  if (missingColumn === 'produits' && Object.prototype.hasOwnProperty.call(candidate, 'produits')) {
    if (!Object.prototype.hasOwnProperty.call(candidate, 'produit')) candidate.produit = candidate.produits;
    if (!Object.prototype.hasOwnProperty.call(candidate, 'products')) candidate.products = candidate.produits;
    if (!Object.prototype.hasOwnProperty.call(candidate, 'items')) candidate.items = candidate.produits;
  }

  if (missingColumn === 'notes' && Object.prototype.hasOwnProperty.call(candidate, 'notes')) {
    if (!Object.prototype.hasOwnProperty.call(candidate, 'note')) candidate.note = candidate.notes;
    if (!Object.prototype.hasOwnProperty.call(candidate, 'commentaire')) candidate.commentaire = candidate.notes;
    if (!Object.prototype.hasOwnProperty.call(candidate, 'description')) candidate.description = candidate.notes;
  }

  if (missingColumn === 'montant_total' && Object.prototype.hasOwnProperty.call(candidate, 'montant_total')) {
    if (!Object.prototype.hasOwnProperty.call(candidate, 'montantTotal')) candidate.montantTotal = candidate.montant_total;
    if (!Object.prototype.hasOwnProperty.call(candidate, 'amount_total')) candidate.amount_total = candidate.montant_total;
  }

  if (missingColumn === 'livraisons' && Object.prototype.hasOwnProperty.call(candidate, 'livraisons')) {
    if (!Object.prototype.hasOwnProperty.call(candidate, 'deliveries')) candidate.deliveries = candidate.livraisons;
    if (!Object.prototype.hasOwnProperty.call(candidate, 'delivery')) candidate.delivery = candidate.livraisons;
    if (!Object.prototype.hasOwnProperty.call(candidate, 'livraison')) candidate.livraison = candidate.livraisons;
  }
}

function mapCommandeRow(row, client) {
  const snapshotClient = row.client_snapshot
    ? {
        _id: row.client_snapshot._id || row.client_snapshot.id || null,
        nom: row.client_snapshot.nom || '',
        prenom: row.client_snapshot.prenom || '',
        telephone: row.client_snapshot.telephone || '',
      }
    : null;

  return {
    _id: row.id,
    client: client
      ? {
          _id: client.id,
          nom: client.nom,
          prenom: client.prenom || '',
          telephone: client.telephone || '',
        }
      : (snapshotClient || row.client_id),

    bande: row.bande_snapshot || row.bande_id || row.band_id || null,
    produits: toArray(row.produits || row.produit || row.products || row.items),
    montantTotal: computeCommandeTotal(row),
    fraisLivraisonTotal: computeFraisLivraisonTotal(row),
    statut: row.statut,
    dateLivraison: row.date_livraison || row.dateLivraison,
    notes: row.notes || row.note || row.commentaire || row.description || '',
    commentaires: toArray(row.commentaires || row.comments),
    historiqueActions: toArray(row.historique_actions || row.historiqueActions),
    livraisons: readLivraisons(row),
    venteComptabilisee: row.vente_comptabilisee === true,
    dernierMouvementTresorerieId: row.dernier_mouvement_tresorerie_id || null,
    createdAt: row.created_at || row.createdAt,
    updatedAt: row.updated_at || row.updatedAt,
  };
}

async function getClientsMap(client, companyId, clientIds) {
  if (!clientIds.length) return new Map();
  const res = await client
    .from('clients')
    .select('id,nom,prenom,telephone')
    .eq('company_id', companyId)
    .in('id', clientIds);

  if (res.error) throw new Error(res.error.message);
  return new Map((res.data || []).map((c) => [c.id, c]));
}

router.get('/', requirePermission('commandes.read'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const cmdRes = await listCommandesCompat(client, companyId, (query) => query.order('created_at', { ascending: false }));

    if (cmdRes.error) return res.status(500).json({ message: cmdRes.error.message });

    const rows = cmdRes.data || [];
    const clientIds = [...new Set(rows.map((r) => r.client_id).filter(Boolean))];
    const clientsMap = await getClientsMap(client, companyId, clientIds);

    return res.json(rows.map((row) => mapCommandeRow(row, clientsMap.get(row.client_id))));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/statut/:statut', requirePermission('commandes.read'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const cmdRes = await listCommandesCompat(
      client,
      companyId,
      (query) => query.eq('statut', req.params.statut).order('created_at', { ascending: false }),
    );

    if (cmdRes.error) return res.status(500).json({ message: cmdRes.error.message });

    const rows = cmdRes.data || [];
    const clientIds = [...new Set(rows.map((r) => r.client_id).filter(Boolean))];
    const clientsMap = await getClientsMap(client, companyId, clientIds);

    return res.json(rows.map((row) => mapCommandeRow(row, clientsMap.get(row.client_id))));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', requirePermission('commandes.read'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const cmdRes = await getCommandeCompat(client, companyId, req.params.id);

    if (cmdRes.error) return res.status(500).json({ message: cmdRes.error.message });
    if (!cmdRes.data) return res.status(404).json({ message: 'Commande non trouvée' });

    let linkedClient = null;
    if (cmdRes.data.client_id) {
      const cRes = await client
        .from('clients')
        .select('id,nom,prenom,telephone')
        .eq('company_id', companyId)
        .eq('id', cmdRes.data.client_id)
        .maybeSingle();
      if (!cRes.error) linkedClient = cRes.data;
    }

    return res.json(mapCommandeRow(cmdRes.data, linkedClient));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', requirePermission('commandes.create'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const statutInitial = (req.body.statut || 'en_attente').toString();
    const auteur = req.body.auteur || getActorLabel(req);

    let clientSnapshot = null;
    if (req.body.clientId) {
      const linkedClient = await apiClient
        .from('clients')
        .select('id,nom,prenom,telephone')
        .eq('company_id', companyId)
        .eq('id', req.body.clientId)
        .maybeSingle();
      if (linkedClient.error) return res.status(400).json({ message: linkedClient.error.message });
      clientSnapshot = linkedClient.data;
    }

    const payload = {
      company_id: companyId,
      client_id: req.body.clientId || null,
      bande_id: req.body.bandeId || null,
      produits: toArray(req.body.produits),
      montant_total: Number(req.body.montantTotal || 0),
      statut: statutInitial,
      date_livraison: req.body.dateLivraison || null,
      notes: req.body.notes || '',
      commentaires: toArray(req.body.commentaires),
      livraisons: [],
      historique_actions: [
        {
          action: 'creation',
          auteur,
          details: 'Commande créée',
          date: new Date().toISOString(),
        },
      ],
      client_snapshot: clientSnapshot
        ? {
            _id: clientSnapshot.id,
            nom: clientSnapshot.nom,
            prenom: clientSnapshot.prenom,
            telephone: clientSnapshot.telephone,
          }
        : null,
      updated_at: new Date().toISOString(),
    };

    let inserted = await insertCommandeCompat(apiClient, payload);

    if (inserted.error) {
      const msg = (inserted.error.message || '').toString().toLowerCase();
      const shouldRetryWithoutClient = msg.includes('clients.statut')
        || msg.includes('clients.chiffre_affaires_cumul')
        || msg.includes('clients.')
        || msg.includes('trigger');

      if (shouldRetryWithoutClient && payload.client_id) {
        const fallbackPayload = {
          ...payload,
          client_id: null,
        };
        inserted = await insertCommandeCompat(apiClient, fallbackPayload);
      }
    }

    if (inserted.error) return res.status(400).json({ message: inserted.error.message });

    if (clientSnapshot) {
      const montant = Number(payload.montant_total || 0);
      const updateClient = await updateClientAfterCommandeCompat(apiClient, companyId, clientSnapshot.id, montant);
      if (updateClient.error) {
        console.warn('updateClientAfterCommandeCompat failed:', updateClient.error.message);
      }
    }

    await safeAudit(apiClient, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'commande.create',
      targetType: 'Commande',
      targetId: inserted.data.id,
      metadata: {
        before: null,
        after: mapCommandeRow(inserted.data, clientSnapshot),
      },
      ip: '',
    });

    return res.status(201).json(mapCommandeRow(inserted.data, clientSnapshot));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/statut', requireAnyPermission(['commandes.status.prepare', 'commandes.status.pay', 'commandes.status.cancel']), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await getCommandeCompat(apiClient, companyId, req.params.id);

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });

    const nouveauStatut = (req.body.statut || '').toString();
    if (!nouveauStatut) return res.status(400).json({ message: 'Statut obligatoire' });
    if (!ALLOWED_COMMANDE_STATUTS.has(nouveauStatut)) {
      return res.status(400).json({ message: 'Statut commande invalide' });
    }
    if (!hasStatusPermission(req, nouveauStatut)) {
      return res.status(403).json({ message: 'Permission insuffisante pour ce changement de statut' });
    }
    if (isCommandeHistorique(current.data)) {
      return res.status(400).json({ message: 'Cette commande est dans l\'historique et n\'est plus modifiable' });
    }

    const before = mapCommandeRow(current.data, null);

    const historique = toArray(current.data.historique_actions);
    historique.push({
      action: 'changement_statut',
      auteur: req.body.auteur || getActorLabel(req),
      details: `Nouveau statut: ${nouveauStatut}`,
      date: new Date().toISOString(),
    });

    let tresoreriePayload = null;
    if (nouveauStatut === 'payee' && current.data.vente_comptabilisee !== true) {
      const montantCalcule = Number(computeCommandeTotal(current.data) || 0);
      const montantPersisted = Number(current.data.montant_total || current.data.montantTotal || current.data.amount_total || 0);
      const montantGlobalCommande = Math.max(montantCalcule, montantPersisted);
      const userName = getUserName(req);
      tresoreriePayload = {
        company_id: companyId,
        nature: 'entree',
        source: 'vente',
        qui_nom: userName.quiNom,
        qui_prenom: userName.quiPrenom,
        categorie: 'vente',
        type: 'Commande client',
        montant: Number(montantGlobalCommande || 0),
        date_mouvement: new Date().toISOString(),
        commentaire: `Commande ${current.data.id} declarée payee (produits + livraison)`,
        reference_type: 'Commande',
        reference_id: current.data.id,
        externe_cle: `commande:${current.data.id}:payee`,
      };
    }

    let tresorerieSaved = null;
    if (tresoreriePayload && Number(tresoreriePayload.montant || 0) > 0) {
      tresorerieSaved = await insertTresorerieCompat(apiClient, tresoreriePayload);
      if (tresorerieSaved.error) return res.status(400).json({ message: tresorerieSaved.error.message });
    }

    const saved = await updateCommandeCompat(apiClient, companyId, req.params.id, {
      statut: nouveauStatut,
      vente_comptabilisee: nouveauStatut === 'payee' ? true : current.data.vente_comptabilisee === true,
      dernier_mouvement_tresorerie_id: tresorerieSaved?.data?.id || current.data.dernier_mouvement_tresorerie_id || null,
      historique_actions: historique,
      updated_at: new Date().toISOString(),
    });

    if (saved.error) return res.status(400).json({ message: saved.error.message });

    let linkedClient = null;
    if (saved.data.client_id) {
      const clientRes = await apiClient
        .from('clients')
        .select('id,nom,prenom,telephone')
        .eq('company_id', companyId)
        .eq('id', saved.data.client_id)
        .maybeSingle();
      if (!clientRes.error) linkedClient = clientRes.data;
    }

    await safeAudit(apiClient, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'commande.status.update',
      targetType: 'Commande',
      targetId: req.params.id,
      metadata: {
        before,
        after: mapCommandeRow(saved.data, linkedClient),
      },
      ip: '',
    });

    return res.json(mapCommandeRow(saved.data, linkedClient));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/:id/livraisons', requirePermission('commandes.livraison.create'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    if (!req.body.dateLivraisonPrevue) {
      return res.status(400).json({ message: 'La date de livraison prévue est obligatoire' });
    }

    const current = await getCommandeCompat(apiClient, companyId, req.params.id);

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });
    if (isCommandeHistorique(current.data)) {
      return res.status(400).json({ message: 'Cette commande est dans l\'historique et n\'est plus modifiable' });
    }

    const livraison = {
      _id: crypto.randomUUID(),
      dateLivraisonPrevue: req.body.dateLivraisonPrevue,
      dateLivraisonReelle: req.body.dateLivraisonReelle || null,
      statutLivraison: req.body.statutLivraison || 'planifiee',
      fraisLivraison: Number(req.body.fraisLivraison || 0),
      commentaires: req.body.commentaires || '',
      utilisateur: getActorLabel(req),
    };

    const livraisons = readLivraisons(current.data);
    livraisons.push(livraison);

    const historique = toArray(current.data.historique_actions);
    historique.push({
      action: 'ajout_livraison',
      auteur: getActorLabel(req),
      details: `Livraison planifiée (${livraison.statutLivraison})`,
      date: new Date().toISOString(),
    });

    const totalCommande = computeCommandeBaseTotal(current.data) + computeFraisLivraisonTotal({ ...current.data, livraisons });

    const saved = await updateCommandeCompat(apiClient, companyId, req.params.id, {
      livraisons,
      montant_total: totalCommande,
      historique_actions: historique,
      updated_at: new Date().toISOString(),
    });

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/livraisons/:livraisonId', requirePermission('commandes.livraison.update'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await getCommandeCompat(apiClient, companyId, req.params.id);

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });
    if (isCommandeHistorique(current.data)) {
      return res.status(400).json({ message: 'Cette commande est dans l\'historique et n\'est plus modifiable' });
    }

    const livraisons = readLivraisons(current.data);
    const index = livraisons.findIndex((l) => String(l._id) === String(req.params.livraisonId));
    if (index === -1) return res.status(404).json({ message: 'Livraison non trouvée' });

    const l = { ...livraisons[index] };
    if (req.body.dateLivraisonPrevue != null) l.dateLivraisonPrevue = req.body.dateLivraisonPrevue;
    if (req.body.dateLivraisonReelle !== undefined) l.dateLivraisonReelle = req.body.dateLivraisonReelle;
    if (req.body.statutLivraison) l.statutLivraison = req.body.statutLivraison;
    if (req.body.fraisLivraison != null) l.fraisLivraison = Number(req.body.fraisLivraison);
    if (req.body.commentaires != null) l.commentaires = req.body.commentaires;
    livraisons[index] = l;

    const historique = toArray(current.data.historique_actions);
    historique.push({
      action: 'maj_livraison',
      auteur: getActorLabel(req),
      details: `Livraison mise à jour (${l.statutLivraison})`,
      date: new Date().toISOString(),
    });

    const totalCommande = computeCommandeBaseTotal(current.data) + computeFraisLivraisonTotal({ ...current.data, livraisons });

    const saved = await updateCommandeCompat(apiClient, companyId, req.params.id, {
      livraisons,
      montant_total: totalCommande,
      historique_actions: historique,
      updated_at: new Date().toISOString(),
    });

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/:id/commentaires', requirePermission('commandes.comment'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await getCommandeCompat(apiClient, companyId, req.params.id);

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });
    if (isCommandeHistorique(current.data)) {
      return res.status(400).json({ message: 'Cette commande est dans l\'historique et n\'est plus modifiable' });
    }

    const commentaires = toArray(current.data.commentaires);
    commentaires.push({
      auteur: req.body.auteur || getActorLabel(req),
      message: req.body.message,
      date: new Date().toISOString(),
    });

    const historique = toArray(current.data.historique_actions);
    historique.push({
      action: 'commentaire',
      auteur: req.body.auteur || getActorLabel(req),
      details: 'Commentaire ajouté',
      date: new Date().toISOString(),
    });

    const saved = await updateCommandeCompat(apiClient, companyId, req.params.id, {
      commentaires,
      historique_actions: historique,
      updated_at: new Date().toISOString(),
    });

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/historique/export.csv', requirePermission('commandes.historique.read'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    let data = [];
    let lastError = null;
    for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
      const result = await apiClient
        .from('commandes')
        .select('*')
        .eq(companyColumn, companyId)
        .order('updated_at', { ascending: false });

      if (!result.error) {
        data = result.data || [];
        lastError = null;
        break;
      }

      const missing = extractMissingColumn(result.error);
      if (missing === companyColumn) {
        lastError = result.error;
        continue;
      }

      return res.status(500).json({ message: result.error.message });
    }

    if (lastError && !data.length) {
      return res.status(500).json({ message: lastError.message });
    }

    const historiques = data.filter((row) => isCommandeHistorique(row));
    const header = [
      'id', 'client_id', 'bande_id', 'statut', 'montant_total', 'date_livraison', 'nombre_produits', 'nombre_livraisons', 'notes', 'updated_at',
    ];
    const rows = historiques.map((row) => {
      const produits = toArray(row.produits || row.produit || row.products || row.items);
      const livraisons = readLivraisons(row);
      return [
        row.id,
        row.client_id || row.clientId || '',
        row.bande_id || row.bandeId || '',
        row.statut || row.status || '',
        computeCommandeTotal(row),
        row.date_livraison || row.dateLivraison || '',
        produits.length,
        livraisons.length,
        row.notes || '',
        row.updated_at || row.updatedAt || '',
      ];
    });

    const csv = toCsv([header, ...rows]);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="commandes_historique_${new Date().toISOString().slice(0, 10)}.csv"`);
    return res.status(200).send(csv);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/historique/:id', requirePermission('commandes.historique.read'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    let current = null;
    for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
      const resTry = await apiClient
        .from('commandes')
        .select('commentaires,historique_actions,created_at,updated_at')
        .eq(companyColumn, companyId)
        .eq('id', req.params.id)
        .maybeSingle();
      if (!resTry.error) {
        current = resTry;
        break;
      }
      const missing = extractMissingColumn(resTry.error);
      if (missing !== companyColumn) {
        current = resTry;
        break;
      }
    }

    if (!current) return res.status(500).json({ message: 'Commande introuvable (compat)' });

    if (current.error) return res.status(500).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });

    return res.json({
      commentaires: toArray(current.data.commentaires),
      historiqueActions: toArray(current.data.historique_actions),
      createdAt: current.data.created_at,
      updatedAt: current.data.updated_at,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:id', requirePermission('commandes.update'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await getCommandeCompat(apiClient, companyId, req.params.id);
    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });
    if (isCommandeHistorique(current.data)) {
      return res.status(400).json({ message: 'Cette commande est dans l\'historique et n\'est plus modifiable' });
    }

    const before = mapCommandeRow(current.data, null);

    const updates = { updated_at: new Date().toISOString() };
    if (req.body.clientId !== undefined) updates.client_id = req.body.clientId;
    if (req.body.bandeId !== undefined) updates.bande_id = req.body.bandeId;
    if (req.body.produits !== undefined) updates.produits = toArray(req.body.produits);
    if (req.body.montantTotal !== undefined) updates.montant_total = Number(req.body.montantTotal || 0);
    if (req.body.statut !== undefined) {
      if (!ALLOWED_COMMANDE_STATUTS.has(req.body.statut)) {
        return res.status(400).json({ message: 'Statut commande invalide' });
      }
      updates.statut = req.body.statut;
    }
    if (req.body.dateLivraison !== undefined) updates.date_livraison = req.body.dateLivraison;
    if (req.body.notes !== undefined) updates.notes = req.body.notes;

    const saved = await updateCommandeCompat(apiClient, companyId, req.params.id, updates, false);

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    if (!saved.data) return res.status(404).json({ message: 'Commande non trouvée' });

    await safeAudit(apiClient, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'commande.update',
      targetType: 'Commande',
      targetId: req.params.id,
      metadata: {
        before,
        after: mapCommandeRow(saved.data, null),
      },
      ip: '',
    });

    return res.json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/historique/all', requirePermission('commandes.historique.purge'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    let totalDeleted = 0;

    const statusFilters = [
      { column: 'statut', value: 'payee' },
      { column: 'status', value: 'payee' },
    ];

    for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
      const idsSet = new Set();

      for (const filter of statusFilters) {
        const selectRes = await apiClient
          .from('commandes')
          .select('id')
          .eq(companyColumn, companyId)
          .eq(filter.column, filter.value);

        if (selectRes.error) {
          const missing = extractMissingColumn(selectRes.error);
          if (missing === companyColumn || missing === filter.column) continue;
          return res.status(500).json({ message: selectRes.error.message });
        }

        for (const row of (selectRes.data || [])) {
          if (row?.id) idsSet.add(row.id);
        }
      }

      const ids = Array.from(idsSet);
      if (!ids.length) continue;

      const delRes = await apiClient
        .from('commandes')
        .delete()
        .eq(companyColumn, companyId)
        .in('id', ids);

      if (delRes.error) {
        const missing = extractMissingColumn(delRes.error);
        if (missing === companyColumn) continue;
        return res.status(500).json({ message: delRes.error.message });
      }

      totalDeleted += ids.length;
    }

    return res.json({ message: 'Historique des commandes supprimé', deletedCount: totalDeleted });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id', requirePermission('commandes.delete'), async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await getCommandeCompat(apiClient, companyId, req.params.id);
    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });
    if (isCommandeHistorique(current.data)) {
      return res.status(400).json({ message: 'Cette commande est dans l\'historique et n\'est plus modifiable' });
    }

    const before = mapCommandeRow(current.data, null);

    let removed = null;
    for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
      const result = await apiClient
        .from('commandes')
        .delete()
        .eq(companyColumn, companyId)
        .eq('id', req.params.id)
        .select('id')
        .maybeSingle();
      if (!result.error) {
        removed = result;
        break;
      }
      const missing = extractMissingColumn(result.error);
      if (missing !== companyColumn) {
        removed = result;
        break;
      }
    }

    if (!removed) return res.status(500).json({ message: 'Suppression impossible (compat)' });

    if (removed.error) return res.status(500).json({ message: removed.error.message });
    if (!removed.data) return res.status(404).json({ message: 'Commande non trouvée' });

    await safeAudit(apiClient, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'commande.delete',
      targetType: 'Commande',
      targetId: req.params.id,
      metadata: {
        before,
        after: null,
      },
      ip: '',
    });

    return res.json({ message: 'Commande supprimée' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
