const express = require('express');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');

const router = express.Router();

function mapMouvement(row) {
  return {
    _id: row.id,
    nature: row.nature,
    source: row.source,
    quiNom: row.qui_nom || '',
    quiPrenom: row.qui_prenom || '',
    categorie: row.categorie || '',
    type: row.type || '',
    montant: Number(row.montant || 0),
    date: row.date_mouvement,
    commentaire: row.commentaire || '',
    referenceType: row.reference_type || null,
    referenceId: row.reference_id || null,
    externeCle: row.externe_cle || null,
    createdAt: row.created_at,
  };
}

function inWeekdays(rowDate, weekdays) {
  if (!weekdays.length) return true;
  const d = new Date(rowDate);
  const jsDay = d.getDay();
  const iso = jsDay === 0 ? 7 : jsDay;
  return weekdays.includes(iso);
}

router.get('/mouvements', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const limit = Math.min(Math.max(Number(req.query.limit || 200), 1), 1000);
    const source = (req.query.source || '').toString().trim();
    const sourcesRaw = (req.query.sources || '').toString().trim();
    const period = (req.query.period || '').toString().trim().toLowerCase();
    const year = Number((req.query.year || '').toString().trim());
    const month = Number((req.query.month || '').toString().trim());
    const dateFromRaw = (req.query.dateFrom || '').toString().trim();
    const dateToRaw = (req.query.dateTo || '').toString().trim();
    const weekdays = (req.query.weekdays || '')
      .toString()
      .split(',')
      .map((w) => Number(w.trim()))
      .filter((w) => !Number.isNaN(w) && w >= 1 && w <= 7);

    let fromDate = null;
    let toDate = null;
    const now = new Date();

    if (period === 'semaine' || period === 'mois' || period === 'annee') {
      if (period === 'semaine') {
        const start = new Date(now);
        const day = start.getDay();
        const diffToMonday = day === 0 ? 6 : day - 1;
        start.setDate(start.getDate() - diffToMonday);
        start.setHours(0, 0, 0, 0);
        fromDate = start;
      } else if (period === 'mois') {
        fromDate = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0);
      } else {
        fromDate = new Date(now.getFullYear(), 0, 1, 0, 0, 0, 0);
      }
    }

    if (!Number.isNaN(year) && year >= 2000 && year <= 2100) {
      if (!Number.isNaN(month) && month >= 1 && month <= 12) {
        fromDate = new Date(year, month - 1, 1, 0, 0, 0, 0);
        toDate = new Date(year, month, 0, 23, 59, 59, 999);
      } else {
        fromDate = new Date(year, 0, 1, 0, 0, 0, 0);
        toDate = new Date(year, 11, 31, 23, 59, 59, 999);
      }
    }

    if (dateFromRaw) {
      const dateFrom = new Date(dateFromRaw);
      if (!Number.isNaN(dateFrom.getTime())) {
        dateFrom.setHours(0, 0, 0, 0);
        fromDate = dateFrom;
      }
    }

    if (dateToRaw) {
      const dateTo = new Date(dateToRaw);
      if (!Number.isNaN(dateTo.getTime())) {
        dateTo.setHours(23, 59, 59, 999);
        toDate = dateTo;
      }
    }

    let query = api
      .from('tresorerie_mouvements')
      .select('*')
      .eq('company_id', companyId)
      .order('date_mouvement', { ascending: false })
      .order('created_at', { ascending: false });

    if (fromDate) query = query.gte('date_mouvement', fromDate.toISOString());
    if (toDate) query = query.lte('date_mouvement', toDate.toISOString());

    if (sourcesRaw) {
      const sourceList = sourcesRaw.split(',').map((s) => s.trim()).filter(Boolean);
      if (sourceList.length > 0) query = query.in('source', sourceList);
    } else if (source) {
      query = query.eq('source', source);
    }

    query = query.limit(limit);

    const { data, error } = await query;
    if (error) return res.status(500).json({ message: error.message });

    const filtered = (data || []).filter((row) => inWeekdays(row.date_mouvement, weekdays));
    return res.json(filtered.map(mapMouvement));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/solde', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const { data, error } = await api
      .from('tresorerie_mouvements')
      .select('nature,montant')
      .eq('company_id', companyId);

    if (error) return res.status(500).json({ message: error.message });

    let totalEntrees = 0;
    let totalSorties = 0;
    for (const row of data || []) {
      const montant = Number(row.montant || 0);
      if (row.nature === 'entree') totalEntrees += montant;
      if (row.nature === 'sortie') totalSorties += montant;
    }

    return res.json({
      totalEntrees,
      totalSorties,
      soldeCaisse: totalEntrees - totalSorties,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/depenses', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const quiNom = (req.body.quiNom || '').toString().trim();
    const quiPrenom = (req.body.quiPrenom || '').toString().trim();
    const categorie = (req.body.categorie || '').toString().trim();
    const type = (req.body.type || '').toString().trim();
    const montant = Number(req.body.montant || 0);
    const commentaire = (req.body.commentaire || '').toString().trim();
    const date = req.body.date ? new Date(req.body.date) : new Date();

    if (!quiNom || !quiPrenom || !categorie || !type || montant <= 0 || Number.isNaN(date.getTime())) {
      return res.status(400).json({
        message: 'Champs obligatoires: quiNom, quiPrenom, categorie, type, montant (>0), date valide',
      });
    }

    const { data, error } = await api
      .from('tresorerie_mouvements')
      .insert({
        company_id: companyId,
        nature: 'sortie',
        source: 'depense',
        qui_nom: quiNom,
        qui_prenom: quiPrenom,
        categorie,
        type,
        montant,
        date_mouvement: date.toISOString(),
        commentaire,
        reference_type: 'manuel',
      })
      .select('*')
      .single();

    if (error) return res.status(400).json({ message: error.message });
    return res.status(201).json(mapMouvement(data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/approvisionnements', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const quiNom = (req.body.quiNom || '').toString().trim();
    const quiPrenom = (req.body.quiPrenom || '').toString().trim();
    const montant = Number(req.body.montant || 0);
    const commentaire = (req.body.commentaire || '').toString().trim();
    const date = req.body.date ? new Date(req.body.date) : new Date();

    if (!quiNom || !quiPrenom || montant <= 0 || Number.isNaN(date.getTime())) {
      return res.status(400).json({
        message: 'Champs obligatoires: quiNom, quiPrenom, montant (>0), date valide',
      });
    }

    const { data, error } = await api
      .from('tresorerie_mouvements')
      .insert({
        company_id: companyId,
        nature: 'entree',
        source: 'approvisionnement',
        qui_nom: quiNom,
        qui_prenom: quiPrenom,
        categorie: 'caisse',
        type: 'approvisionnement',
        montant,
        date_mouvement: date.toISOString(),
        commentaire,
        reference_type: 'manuel',
      })
      .select('*')
      .single();

    if (error) return res.status(400).json({ message: error.message });
    return res.status(201).json(mapMouvement(data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/mouvements', async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const deleted = await api
      .from('tresorerie_mouvements')
      .delete()
      .eq('company_id', companyId);

    if (deleted.error) return res.status(500).json({ message: deleted.error.message });
    return res.json({ message: 'Historique des mouvements supprimé', deletedCount: 0 });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
