const express = require('express');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');

const router = express.Router();

function readStatus(row) {
  return (row?.statut || row?.status || '').toString();
}

function toArray(value) {
  return Array.isArray(value) ? value : [];
}

function mapAlerteRow(row, bandeMap = new Map()) {
  const bandeId = row.bande_id || null;
  return {
    _id: row.id,
    titre: row.titre,
    message: row.message,
    type: row.type,
    dateEcheance: row.date_echeance,
    bandeId: bandeId && bandeMap.has(bandeId)
      ? { _id: bandeId, nom: bandeMap.get(bandeId) }
      : bandeId,
    statut: row.statut || 'active',
    recurrence: row.recurrence || 'aucune',
    priorite: row.priorite || 'moyenne',
    source: row.source || 'todo',
    automatique: row.automatique === true,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function getPeriodBounds(period) {
  const now = new Date();
  const start = new Date(now);
  const end = new Date(now);

  switch (period) {
    case 'today':
      start.setHours(0, 0, 0, 0);
      end.setHours(23, 59, 59, 999);
      return { start, end };
    case 'week': {
      const day = (now.getDay() + 6) % 7;
      start.setDate(now.getDate() - day);
      start.setHours(0, 0, 0, 0);
      end.setDate(start.getDate() + 6);
      end.setHours(23, 59, 59, 999);
      return { start, end };
    }
    case 'month':
      start.setDate(1);
      start.setHours(0, 0, 0, 0);
      end.setMonth(start.getMonth() + 1, 0);
      end.setHours(23, 59, 59, 999);
      return { start, end };
    default:
      return null;
  }
}

async function getBandeNameMap(api, companyId) {
  const b = await api.from('bandes').select('id,nom').eq('company_id', companyId);
  if (b.error) return new Map();
  return new Map((b.data || []).map((x) => [x.id, x.nom || '']));
}

router.get('/actives', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    let query = api.from('alertes').select('*').eq('company_id', companyId).eq('statut', 'active').eq('automatique', false);
    const period = (req.query.period || 'all').toString().toLowerCase();
    const bounds = getPeriodBounds(period);
    if (bounds) {
      query = query.gte('date_echeance', bounds.start.toISOString()).lte('date_echeance', bounds.end.toISOString());
    }

    const result = await query.order('date_echeance', { ascending: true });
    if (result.error) return res.status(500).json({ message: result.error.message });

    const bandeMap = await getBandeNameMap(api, companyId);
    return res.json((result.data || []).map((row) => mapAlerteRow(row, bandeMap)));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/automatiques', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const maintenant = new Date();
    const alertes = [];

    const stocksRes = await api.from('stocks').select('id,nom,categorie,quantite_actuelle,seuil_alerte,unite').eq('company_id', companyId);
    if (stocksRes.error) return res.status(500).json({ message: stocksRes.error.message });

    for (const s of stocksRes.data || []) {
      const current = Number(s.quantite_actuelle || 0);
      const seuil = Number(s.seuil_alerte || 0);
      if (current > seuil) continue;

      const categorie = (s.categorie || '').toLowerCase();
      const nom = (s.nom || '').toLowerCase();
      const isVaccin = nom.includes('vaccin');
      if (!['aliment', 'medicament'].includes(categorie) && !isVaccin) continue;

      alertes.push({
        id: `stock-${s.id}`,
        titre: `Stock bas: ${s.nom}`,
        message: `Niveau ${current} ${s.unite || ''} (seuil ${seuil} ${s.unite || ''})`,
        type: 'stock_bas',
        priorite: 'haute',
        dateEcheance: maintenant.toISOString(),
        source: 'stock',
        automatique: true,
      });
    }

    const bandesRes = await api.from('bandes').select('id,nom,evenements_sante,evenements_previsionnels,statut').eq('company_id', companyId).eq('statut', 'ouverte');
    if (bandesRes.error) return res.status(500).json({ message: bandesRes.error.message });

    for (const b of bandesRes.data || []) {
      const events = toArray(b.evenements_sante);
      for (const e of events) {
        if (!e.date) continue;
        const d = new Date(e.date);
        if (Number.isNaN(d.getTime()) || d < maintenant) continue;
        const type = (e.type || '').toLowerCase();
        const isSanitary = ['vaccination', 'traitement', 'autre'].includes(type) || (e.description || '').toLowerCase().includes('controle');
        if (!isSanitary) continue;

        alertes.push({
          id: `sanitaire-${b.id}-${e._id || d.getTime()}`,
          titre: `Événement sanitaire: ${b.nom}`,
          message: e.description || 'Événement sanitaire planifié',
          type: 'vaccination',
          priorite: 'moyenne',
          dateEcheance: d.toISOString(),
          source: 'sanitaire',
          automatique: true,
        });
      }

      const planned = toArray(b.evenements_previsionnels);
      for (const p of planned) {
        if (!p.datePrevue || p.statut === 'termine') continue;
        const d = new Date(p.datePrevue);
        if (Number.isNaN(d.getTime())) continue;
        const msToDue = d.getTime() - maintenant.getTime();
        if (msToDue > (2 * 24 * 60 * 60 * 1000)) continue;

        const overdue = msToDue < 0;
        alertes.push({
          id: `prevision-${b.id}-${p._id || d.getTime()}`,
          titre: `${overdue ? 'Événement en retard' : 'Événement prévu'}: ${b.nom}`,
          message: p.description || 'Événement planifié',
          type: p.type || 'autre',
          priorite: p.priorite || (overdue ? 'haute' : 'moyenne'),
          dateEcheance: d.toISOString(),
          source: 'planification',
          automatique: true,
          bandeId: b.id,
          eventId: p._id,
        });
      }
    }

    const commandesRes = await api.from('commandes').select('*').eq('company_id', companyId);
    if (commandesRes.error) return res.status(500).json({ message: commandesRes.error.message });

    const commandes = commandesRes.data || [];
    const commandesApreparer = commandes.filter((c) => ['confirmee', 'en_preparation'].includes(readStatus(c))).length;
    if (commandesApreparer > 0) {
      alertes.push({
        id: 'commercial-prepare',
        titre: 'Commandes à préparer',
        message: `${commandesApreparer} commande(s) à préparer`,
        type: 'vente',
        priorite: 'haute',
        dateEcheance: maintenant.toISOString(),
        source: 'commercial',
        automatique: true,
      });
    }

    const commandesAlivrer = commandes.filter((c) => {
      if (['confirmee', 'en_preparation', 'payee'].includes(readStatus(c))) return true;
      return toArray(c.livraisons || c.deliveries || []).some((l) => ['planifiee', 'en_cours'].includes(l.statutLivraison));
    }).length;

    if (commandesAlivrer > 0) {
      alertes.push({
        id: 'commercial-livraison',
        titre: 'Commandes à livrer',
        message: `${commandesAlivrer} commande(s) à livrer`,
        type: 'vente',
        priorite: 'haute',
        dateEcheance: maintenant.toISOString(),
        source: 'commercial',
        automatique: true,
      });
    }

    const dueDate = new Date(maintenant.getTime() + 2 * 24 * 60 * 60 * 1000).toISOString();
    const tachesRes = await api
      .from('crm_taches')
      .select('id,titre,description,date_echeance,priorite,statut,client_id')
      .eq('company_id', companyId)
      .in('statut', ['a_faire', 'en_cours'])
      .lte('date_echeance', dueDate)
      .order('date_echeance', { ascending: true });
    if (tachesRes.error) return res.status(500).json({ message: tachesRes.error.message });

    let clientMap = new Map();
    const clientIds = [...new Set((tachesRes.data || []).map((t) => t.client_id).filter(Boolean))];
    if (clientIds.length) {
      const clientRes = await api.from('clients').select('id,nom,prenom').eq('company_id', companyId).in('id', clientIds);
      if (!clientRes.error) clientMap = new Map((clientRes.data || []).map((c) => [c.id, c]));
    }

    for (const tache of tachesRes.data || []) {
      const cl = tache.client_id ? clientMap.get(tache.client_id) : null;
      const clientNom = cl ? `${cl.prenom || ''} ${cl.nom || ''}`.trim() : '';
      const overdue = new Date(tache.date_echeance).getTime() < maintenant.getTime();

      alertes.push({
        id: `crm-task-${tache.id}`,
        titre: tache.titre || 'Relance CRM',
        message: [clientNom ? `Client: ${clientNom}` : null, tache.description || null].filter(Boolean).join(' • '),
        type: 'vente',
        priorite: tache.priorite || (overdue ? 'haute' : 'moyenne'),
        dateEcheance: tache.date_echeance,
        source: 'crm_tache',
        automatique: true,
      });
    }

    alertes.sort((a, b) => new Date(a.dateEcheance).getTime() - new Date(b.dateEcheance).getTime());
    return res.json(alertes);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/aujourdhui', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const debut = new Date();
    debut.setHours(0, 0, 0, 0);
    const fin = new Date();
    fin.setHours(23, 59, 59, 999);

    const result = await api
      .from('alertes')
      .select('*')
      .eq('company_id', companyId)
      .eq('statut', 'active')
      .gte('date_echeance', debut.toISOString())
      .lte('date_echeance', fin.toISOString())
      .order('date_echeance', { ascending: true });

    if (result.error) return res.status(500).json({ message: result.error.message });
    const bandeMap = await getBandeNameMap(api, companyId);
    return res.json((result.data || []).map((row) => mapAlerteRow(row, bandeMap)));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/retard', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const nowIso = new Date().toISOString();

    const result = await api
      .from('alertes')
      .select('*')
      .eq('company_id', companyId)
      .eq('statut', 'active')
      .lt('date_echeance', nowIso)
      .order('date_echeance', { ascending: true });

    if (result.error) return res.status(500).json({ message: result.error.message });
    const bandeMap = await getBandeNameMap(api, companyId);
    return res.json((result.data || []).map((row) => mapAlerteRow(row, bandeMap)));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/historique', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const result = await api
      .from('alertes')
      .select('*')
      .eq('company_id', companyId)
      .in('statut', ['faite', 'ignoree'])
      .eq('automatique', false)
      .order('updated_at', { ascending: false })
      .order('date_echeance', { ascending: false });

    if (result.error) return res.status(500).json({ message: result.error.message });
    const bandeMap = await getBandeNameMap(api, companyId);
    return res.json((result.data || []).map((row) => mapAlerteRow(row, bandeMap)));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/automatiques/historique', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const result = await api
      .from('alertes')
      .select('*')
      .eq('company_id', companyId)
      .in('statut', ['faite', 'ignoree'])
      .eq('automatique', true)
      .order('updated_at', { ascending: false })
      .order('date_echeance', { ascending: false });

    if (result.error) return res.status(500).json({ message: result.error.message });
    const bandeMap = await getBandeNameMap(api, companyId);
    return res.json((result.data || []).map((row) => mapAlerteRow(row, bandeMap)));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const payload = {
      company_id: companyId,
      titre: req.body.titre,
      message: req.body.message,
      type: req.body.type,
      date_echeance: req.body.dateEcheance,
      bande_id: req.body.bandeId || null,
      recurrence: req.body.recurrence || 'aucune',
      priorite: req.body.priorite || 'moyenne',
      source: req.body.source || 'todo',
      automatique: req.body.automatique === true,
      statut: req.body.statut || 'active',
      updated_at: new Date().toISOString(),
    };

    const created = await api.from('alertes').insert(payload).select('*').single();
    if (created.error) return res.status(400).json({ message: created.error.message });

    return res.status(201).json(mapAlerteRow(created.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const existing = await api
      .from('alertes')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (existing.error) return res.status(400).json({ message: existing.error.message });
    if (!existing.data) return res.status(404).json({ message: 'Alerte non trouvée' });
    if (existing.data.automatique === true) {
      return res.status(400).json({ message: 'Les alertes automatiques ne sont pas modifiables' });
    }

    const updates = { updated_at: new Date().toISOString() };
    const map = {
      titre: 'titre',
      message: 'message',
      type: 'type',
      dateEcheance: 'date_echeance',
      bandeId: 'bande_id',
      recurrence: 'recurrence',
      priorite: 'priorite',
      source: 'source',
      statut: 'statut',
    };

    for (const [k, dbk] of Object.entries(map)) {
      if (Object.prototype.hasOwnProperty.call(req.body, k)) {
        updates[dbk] = req.body[k];
      }
    }

    const saved = await api
      .from('alertes')
      .update(updates)
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .single();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapAlerteRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/fait', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    if (req.params.id.startsWith('crm-task-')) {
      const tacheId = req.params.id.replace('crm-task-', '');
      const tacheRes = await api.from('crm_taches').select('*').eq('company_id', companyId).eq('id', tacheId).maybeSingle();
      if (tacheRes.error) return res.status(400).json({ message: tacheRes.error.message });
      if (!tacheRes.data) return res.status(404).json({ message: 'Tâche CRM non trouvée' });

      if (tacheRes.data.statut === 'terminee') {
        return res.json({ id: req.params.id, source: 'crm_tache', alreadyDone: true });
      }

      const updated = await api
        .from('crm_taches')
        .update({ statut: 'terminee', updated_at: new Date().toISOString() })
        .eq('company_id', companyId)
        .eq('id', tacheId)
        .select('*')
        .single();

      if (updated.error) return res.status(400).json({ message: updated.error.message });

      const archive = await api
        .from('alertes')
        .insert({
          company_id: companyId,
          titre: tacheRes.data.titre || 'Relance CRM',
          message: tacheRes.data.description || 'Tâche CRM terminée',
          type: 'vente',
          date_echeance: tacheRes.data.date_echeance || new Date().toISOString(),
          statut: 'faite',
          recurrence: 'aucune',
          priorite: tacheRes.data.priorite || 'moyenne',
          source: 'crm_tache',
          automatique: true,
          updated_at: new Date().toISOString(),
        })
        .select('*')
        .single();

      if (archive.error) return res.status(400).json({ message: archive.error.message });
      return res.json({ id: req.params.id, source: 'crm_tache', tache: updated.data });
    }

    if (
      req.params.id.startsWith('stock-') ||
      req.params.id.startsWith('sanitaire-') ||
      req.params.id.startsWith('prevision-') ||
      req.params.id.startsWith('commercial-')
    ) {
      const now = new Date();
      const archive = await api
        .from('alertes')
        .insert({
          company_id: companyId,
          titre: req.body.titre || 'Alerte automatique traitée',
          message: req.body.message || `Alerte ${req.params.id} marquée faite`,
          type: req.body.type || 'autre',
          date_echeance: req.body.dateEcheance ? new Date(req.body.dateEcheance).toISOString() : now.toISOString(),
          statut: 'faite',
          recurrence: 'aucune',
          priorite: req.body.priorite || 'moyenne',
          source: req.body.source || 'automatique',
          automatique: true,
          updated_at: new Date().toISOString(),
        })
        .select('*')
        .single();

      if (archive.error) return res.status(400).json({ message: archive.error.message });
      return res.json({ id: req.params.id, source: 'automatique', archive: mapAlerteRow(archive.data) });
    }

    const updated = await api
      .from('alertes')
      .update({ statut: 'faite', updated_at: new Date().toISOString() })
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .maybeSingle();

    if (updated.error) return res.status(400).json({ message: updated.error.message });
    if (!updated.data) return res.status(404).json({ message: 'Alerte non trouvée' });
    return res.json(mapAlerteRow(updated.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/historique/all', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const deleted = await api
      .from('alertes')
      .delete()
      .eq('company_id', companyId)
      .in('statut', ['faite', 'ignoree']);

    if (deleted.error) return res.status(500).json({ message: deleted.error.message });
    return res.json({ message: 'Historique supprimé', deletedCount: 0 });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const deleted = await api.from('alertes').delete().eq('company_id', companyId).eq('id', req.params.id);
    if (deleted.error) return res.status(500).json({ message: deleted.error.message });
    return res.json({ message: 'Alerte supprimée' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
