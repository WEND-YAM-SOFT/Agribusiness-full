const express = require('express');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');

const router = express.Router();

function readStatus(row) {
  return (row?.statut || row?.status || '').toString();
}

function mapInteraction(row, commande = null) {
  return {
    _id: row.id,
    clientId: row.client_id,
    commandeId: commande
      ? { _id: commande.id, montantTotal: Number(commande.montant_total || 0), statut: commande.statut }
      : row.commande_id,
    type: row.type || 'commentaire',
    sujet: row.sujet || '',
    contenu: row.contenu || '',
    auteur: row.auteur || 'Utilisateur',
    dateInteraction: row.date_interaction,
    piecesJointes: Array.isArray(row.pieces_jointes) ? row.pieces_jointes : [],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapTache(row, client = null, commande = null) {
  return {
    _id: row.id,
    clientId: client
      ? {
          _id: client.id,
          nom: client.nom,
          prenom: client.prenom || '',
          telephone: client.telephone || '',
          statut: client.statut || 'prospect',
        }
      : row.client_id,
    commandeId: commande
      ? {
          _id: commande.id,
          montantTotal: Number(commande.montant_total || 0),
          statut: commande.statut,
        }
      : row.commande_id,
    titre: row.titre || '',
    description: row.description || '',
    type: row.type || 'suivi',
    dateEcheance: row.date_echeance,
    statut: row.statut || 'a_faire',
    priorite: row.priorite || 'moyenne',
    rappelActive: row.rappel_active !== false,
    assigneA: row.assigne_a || '',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

router.get('/dashboard', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const clientsRes = await api.from('clients').select('*').eq('company_id', companyId);
    if (clientsRes.error) return res.status(500).json({ message: clientsRes.error.message });
    const clients = clientsRes.data || [];

    const commandesRes = await api.from('commandes').select('*').eq('company_id', companyId);
    if (commandesRes.error) return res.status(500).json({ message: commandesRes.error.message });
    const commandes = commandesRes.data || [];

    const tachesRes = await api.from('crm_taches').select('*').eq('company_id', companyId);
    if (tachesRes.error) return res.status(500).json({ message: tachesRes.error.message });
    const taches = tachesRes.data || [];

    const interactionsRes = await api.from('crm_interactions').select('type').eq('company_id', companyId);
    if (interactionsRes.error) return res.status(500).json({ message: interactionsRes.error.message });
    const interactions = interactionsRes.data || [];

    const debutMois = new Date();
    debutMois.setDate(1);
    debutMois.setHours(0, 0, 0, 0);

    const totalClients = clients.length;
    const totalProspects = clients.filter((c) => readStatus(c) === 'prospect').length;
    const clientsActifs = clients.filter((c) => readStatus(c) === 'actif').length;
    const nouveauxClients = clients.filter((c) => new Date(c.created_at).getTime() >= debutMois.getTime()).length;
    const commandesEnAttente = commandes.filter((c) => readStatus(c) === 'en_attente').length;
    const relancesAFaire = taches.filter((t) => ['a_faire', 'en_cours'].includes(t.statut) && new Date(t.date_echeance).getTime() <= Date.now()).length;

    const topClients = [...clients]
      .sort((a, b) => Number(b.chiffre_affaires_cumul || 0) - Number(a.chiffre_affaires_cumul || 0))
      .slice(0, 5)
      .map((c) => ({
        _id: c.id,
        nom: c.nom,
        prenom: c.prenom || '',
        chiffreAffairesCumul: Number(c.chiffre_affaires_cumul ?? c.chiffreAffairesCumul ?? 0),
        statut: readStatus(c) || 'prospect',
      }));

    const byType = new Map();
    for (const i of interactions) {
      const type = i.type || 'autre';
      byType.set(type, (byType.get(type) || 0) + 1);
    }
    const interactionsParType = [...byType.entries()]
      .map(([type, count]) => ({ _id: type, count }))
      .sort((a, b) => b.count - a.count);

    const byMonth = new Map();
    for (const c of commandes) {
      const d = new Date(c.created_at);
      const y = d.getUTCFullYear();
      const m = d.getUTCMonth() + 1;
      const key = `${y}-${m}`;
      byMonth.set(key, (byMonth.get(key) || 0) + Number(c.montant_total || 0));
    }
    const ventesParMois = [...byMonth.entries()]
      .map(([k, total]) => {
        const [annee, mois] = k.split('-').map(Number);
        return { _id: { annee, mois }, total };
      })
      .sort((a, b) => (a._id.annee - b._id.annee) || (a._id.mois - b._id.mois))
      .slice(-12);

    return res.json({
      totalClients,
      totalProspects,
      clientsActifs,
      nouveauxClients,
      commandesEnAttente,
      relancesAFaire,
      topClients,
      interactionsParType,
      ventesParMois,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/clients/:clientId/interactions', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const interactionsRes = await api
      .from('crm_interactions')
      .select('*')
      .eq('company_id', companyId)
      .eq('client_id', req.params.clientId)
      .order('date_interaction', { ascending: false });

    if (interactionsRes.error) return res.status(500).json({ message: interactionsRes.error.message });

    const commandeIds = [...new Set((interactionsRes.data || []).map((i) => i.commande_id).filter(Boolean))];
    let commandeMap = new Map();
    if (commandeIds.length) {
      const cmd = await api.from('commandes').select('id,montant_total,statut').eq('company_id', companyId).in('id', commandeIds);
      if (!cmd.error) commandeMap = new Map((cmd.data || []).map((c) => [c.id, c]));
    }

    return res.json((interactionsRes.data || []).map((i) => mapInteraction(i, commandeMap.get(i.commande_id))));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/clients/:clientId/interactions', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const payload = {
      company_id: companyId,
      client_id: req.params.clientId,
      commande_id: req.body.commandeId || null,
      type: req.body.type,
      sujet: req.body.sujet || '',
      contenu: req.body.contenu,
      auteur: req.body.auteur || 'Utilisateur',
      date_interaction: req.body.dateInteraction || new Date().toISOString(),
      pieces_jointes: Array.isArray(req.body.piecesJointes) ? req.body.piecesJointes : [],
      updated_at: new Date().toISOString(),
    };

    const saved = await api.from('crm_interactions').insert(payload).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });

    const touchClient = await api
      .from('clients')
      .update({ dernier_contact_le: saved.data.date_interaction, updated_at: new Date().toISOString() })
      .eq('company_id', companyId)
      .eq('id', req.params.clientId);
    if (touchClient.error) return res.status(400).json({ message: touchClient.error.message });

    return res.status(201).json(mapInteraction(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/taches', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const tachesRes = await api.from('crm_taches').select('*').eq('company_id', companyId).order('date_echeance', { ascending: true });
    if (tachesRes.error) return res.status(500).json({ message: tachesRes.error.message });

    const clientIds = [...new Set((tachesRes.data || []).map((t) => t.client_id).filter(Boolean))];
    const commandeIds = [...new Set((tachesRes.data || []).map((t) => t.commande_id).filter(Boolean))];

    let clientMap = new Map();
    if (clientIds.length) {
      const clients = await api.from('clients').select('id,nom,prenom,telephone,statut').eq('company_id', companyId).in('id', clientIds);
      if (!clients.error) clientMap = new Map((clients.data || []).map((c) => [c.id, c]));
    }

    let commandeMap = new Map();
    if (commandeIds.length) {
      const commandes = await api.from('commandes').select('id,montant_total,statut').eq('company_id', companyId).in('id', commandeIds);
      if (!commandes.error) commandeMap = new Map((commandes.data || []).map((c) => [c.id, c]));
    }

    return res.json((tachesRes.data || []).map((t) => mapTache(t, clientMap.get(t.client_id), commandeMap.get(t.commande_id))));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/taches', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const payload = {
      company_id: companyId,
      client_id: req.body.clientId || null,
      commande_id: req.body.commandeId || null,
      titre: req.body.titre,
      description: req.body.description || '',
      type: req.body.type || 'suivi',
      date_echeance: req.body.dateEcheance,
      priorite: req.body.priorite || 'moyenne',
      rappel_active: req.body.rappelActive !== false,
      assigne_a: req.body.assigneA || '',
      statut: req.body.statut || 'a_faire',
      updated_at: new Date().toISOString(),
    };

    const saved = await api.from('crm_taches').insert(payload).select('*').single();
    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.status(201).json(mapTache(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/taches/:id', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const updates = { updated_at: new Date().toISOString() };
    const map = {
      clientId: 'client_id',
      commandeId: 'commande_id',
      titre: 'titre',
      description: 'description',
      type: 'type',
      dateEcheance: 'date_echeance',
      priorite: 'priorite',
      statut: 'statut',
      rappelActive: 'rappel_active',
      assigneA: 'assigne_a',
    };
    for (const [k, dbk] of Object.entries(map)) {
      if (Object.prototype.hasOwnProperty.call(req.body, k)) updates[dbk] = req.body[k];
    }

    const saved = await api
      .from('crm_taches')
      .update(updates)
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .maybeSingle();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    if (!saved.data) return res.status(404).json({ message: 'Tâche non trouvée' });
    return res.json(mapTache(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/taches/historique/all', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const deleted = await api.from('crm_taches').delete().eq('company_id', companyId).in('statut', ['terminee', 'annulee']);
    if (deleted.error) return res.status(500).json({ message: deleted.error.message });
    return res.json({ message: 'Historique CRM supprimé', deletedCount: 0 });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/taches/:id', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const deleted = await api.from('crm_taches').delete().eq('company_id', companyId).eq('id', req.params.id);
    if (deleted.error) return res.status(500).json({ message: deleted.error.message });
    return res.json({ message: 'Tâche supprimée' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
