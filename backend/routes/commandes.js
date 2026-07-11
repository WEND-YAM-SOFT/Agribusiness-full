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

async function insertCommandeCompat(apiClient, payload) {
  let candidate = { ...payload };
  let lastMissingColumn = '';

  for (let i = 0; i < 15; i += 1) {
    const result = await apiClient.from('commandes').insert(candidate).select('*').single();
    if (!result.error) return result;

    const missingColumn = extractMissingColumn(result.error);
    if (!missingColumn) return result;
    lastMissingColumn = missingColumn;

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

function toArray(value) {
  return Array.isArray(value) ? value : [];
}

function mapCommandeRow(row, client) {
  return {
    _id: row.id,
    client: client
      ? {
          _id: client.id,
          nom: client.nom,
          prenom: client.prenom || '',
          telephone: client.telephone || '',
        }
      : row.client_id,
    bande: row.bande_snapshot || row.bande_id || row.band_id || null,
    produits: toArray(row.produits),
    montantTotal: Number(row.montant_total || row.montantTotal || 0),
    statut: row.statut,
    dateLivraison: row.date_livraison || row.dateLivraison,
    notes: row.notes || '',
    commentaires: toArray(row.commentaires || row.comments),
    historiqueActions: toArray(row.historique_actions || row.historiqueActions),
    livraisons: toArray(row.livraisons),
    venteComptabilisee: row.vente_comptabilisee === true,
    dernierMouvementTresorerieId: row.dernier_mouvement_tresorerie_id || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
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

router.get('/', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const cmdRes = await client
      .from('commandes')
      .select('*')
      .eq('company_id', companyId)
      .order('created_at', { ascending: false });

    if (cmdRes.error) return res.status(500).json({ message: cmdRes.error.message });

    const rows = cmdRes.data || [];
    const clientIds = [...new Set(rows.map((r) => r.client_id).filter(Boolean))];
    const clientsMap = await getClientsMap(client, companyId, clientIds);

    return res.json(rows.map((row) => mapCommandeRow(row, clientsMap.get(row.client_id))));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/statut/:statut', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const cmdRes = await client
      .from('commandes')
      .select('*')
      .eq('company_id', companyId)
      .eq('statut', req.params.statut)
      .order('created_at', { ascending: false });

    if (cmdRes.error) return res.status(500).json({ message: cmdRes.error.message });

    const rows = cmdRes.data || [];
    const clientIds = [...new Set(rows.map((r) => r.client_id).filter(Boolean))];
    const clientsMap = await getClientsMap(client, companyId, clientIds);

    return res.json(rows.map((row) => mapCommandeRow(row, clientsMap.get(row.client_id))));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const cmdRes = await client
      .from('commandes')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

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

router.post('/', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const statutInitial = (req.body.statut || 'en_attente').toString();
    const auteur = req.body.auteur || req.user.email || 'Utilisateur';

    let clientSnapshot = null;
    if (req.body.clientId) {
      const linkedClient = await apiClient
        .from('clients')
        .select('id,nom,prenom,telephone,chiffre_affaires_cumul,statut')
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

    const inserted = await insertCommandeCompat(apiClient, payload);
    if (inserted.error) return res.status(400).json({ message: inserted.error.message });

    if (clientSnapshot) {
      const montant = Number(payload.montant_total || 0);
      const updateClient = await apiClient
        .from('clients')
        .update({
          dernier_contact_le: new Date().toISOString(),
          statut: 'actif',
          chiffre_affaires_cumul: Number(clientSnapshot.chiffre_affaires_cumul || 0) + montant,
          updated_at: new Date().toISOString(),
        })
        .eq('id', clientSnapshot.id)
        .eq('company_id', companyId);
      if (updateClient.error) return res.status(400).json({ message: updateClient.error.message });
    }

    return res.status(201).json(mapCommandeRow(inserted.data, clientSnapshot));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/statut', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await apiClient
      .from('commandes')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });

    const nouveauStatut = (req.body.statut || '').toString();
    if (!nouveauStatut) return res.status(400).json({ message: 'Statut obligatoire' });

    const historique = toArray(current.data.historique_actions);
    historique.push({
      action: 'changement_statut',
      auteur: req.body.auteur || req.user.email || 'Utilisateur',
      details: `Nouveau statut: ${nouveauStatut}`,
      date: new Date().toISOString(),
    });

    const saved = await apiClient
      .from('commandes')
      .update({
        statut: nouveauStatut,
        historique_actions: historique,
        updated_at: new Date().toISOString(),
      })
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .single();

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

    return res.json(mapCommandeRow(saved.data, linkedClient));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/:id/livraisons', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    if (!req.body.dateLivraisonPrevue) {
      return res.status(400).json({ message: 'La date de livraison prévue est obligatoire' });
    }

    const current = await apiClient
      .from('commandes')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });

    const livraison = {
      _id: crypto.randomUUID(),
      dateLivraisonPrevue: req.body.dateLivraisonPrevue,
      dateLivraisonReelle: req.body.dateLivraisonReelle || null,
      statutLivraison: req.body.statutLivraison || 'planifiee',
      fraisLivraison: Number(req.body.fraisLivraison || 0),
      commentaires: req.body.commentaires || '',
      utilisateur: req.user?.email || 'Utilisateur',
    };

    const livraisons = toArray(current.data.livraisons);
    livraisons.push(livraison);

    const historique = toArray(current.data.historique_actions);
    historique.push({
      action: 'ajout_livraison',
      auteur: req.user?.email || 'Utilisateur',
      details: `Livraison planifiée (${livraison.statutLivraison})`,
      date: new Date().toISOString(),
    });

    const saved = await apiClient
      .from('commandes')
      .update({ livraisons, historique_actions: historique, updated_at: new Date().toISOString() })
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .single();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/livraisons/:livraisonId', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await apiClient
      .from('commandes')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });

    const livraisons = toArray(current.data.livraisons);
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
      auteur: req.user?.email || 'Utilisateur',
      details: `Livraison mise à jour (${l.statutLivraison})`,
      date: new Date().toISOString(),
    });

    const saved = await apiClient
      .from('commandes')
      .update({ livraisons, historique_actions: historique, updated_at: new Date().toISOString() })
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .single();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/:id/commentaires', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await apiClient
      .from('commandes')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (current.error) return res.status(400).json({ message: current.error.message });
    if (!current.data) return res.status(404).json({ message: 'Commande non trouvée' });

    const commentaires = toArray(current.data.commentaires);
    commentaires.push({
      auteur: req.body.auteur || req.user.email || 'Utilisateur',
      message: req.body.message,
      date: new Date().toISOString(),
    });

    const historique = toArray(current.data.historique_actions);
    historique.push({
      action: 'commentaire',
      auteur: req.body.auteur || req.user.email || 'Utilisateur',
      details: 'Commentaire ajouté',
      date: new Date().toISOString(),
    });

    const saved = await apiClient
      .from('commandes')
      .update({ commentaires, historique_actions: historique, updated_at: new Date().toISOString() })
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .single();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/historique/:id', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const current = await apiClient
      .from('commandes')
      .select('commentaires,historique_actions,created_at,updated_at')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

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

router.put('/:id', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const updates = { updated_at: new Date().toISOString() };
    if (req.body.clientId !== undefined) updates.client_id = req.body.clientId;
    if (req.body.bandeId !== undefined) updates.bande_id = req.body.bandeId;
    if (req.body.produits !== undefined) updates.produits = toArray(req.body.produits);
    if (req.body.montantTotal !== undefined) updates.montant_total = Number(req.body.montantTotal || 0);
    if (req.body.statut !== undefined) updates.statut = req.body.statut;
    if (req.body.dateLivraison !== undefined) updates.date_livraison = req.body.dateLivraison;
    if (req.body.notes !== undefined) updates.notes = req.body.notes;

    const saved = await apiClient
      .from('commandes')
      .update(updates)
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .maybeSingle();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    if (!saved.data) return res.status(404).json({ message: 'Commande non trouvée' });

    return res.json(mapCommandeRow(saved.data, null));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const apiClient = getAdminClient();
    const companyId = await getCompanyIdForUser(apiClient, req.user.id || req.user._id);

    const removed = await apiClient
      .from('commandes')
      .delete()
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('id')
      .maybeSingle();

    if (removed.error) return res.status(500).json({ message: removed.error.message });
    if (!removed.data) return res.status(404).json({ message: 'Commande non trouvée' });

    return res.json({ message: 'Commande supprimée' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
