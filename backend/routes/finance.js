const express = require('express');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');
const { requirePermission } = require('../middleware/auth');

const router = express.Router();
const COMMANDES_COMPANY_COLUMNS = ['company_id', 'companyId'];

function csvEscape(value) {
  const raw = value == null ? '' : String(value);
  return `"${raw.replace(/"/g, '""')}"`;
}

function toCsv(rows) {
  return rows.map((row) => row.map(csvEscape).join(',')).join('\n');
}

function isMissingCategorieColumnError(error) {
  const message = (error?.message || '').toString().toLowerCase();
  return message.includes("could not find the 'categorie' column")
    || (message.includes('categorie') && message.includes('schema cache'));
}

function extractMissingColumn(error) {
  const message = (error?.message || '').toString();
  const match = message.match(/Could not find the '([^']+)' column/i);
  return match?.[1] || '';
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
    const result = await api
      .from('tresorerie_mouvements')
      .insert(candidate)
      .select('*')
      .single();

    if (!result.error) {
      if (result.data) {
        result.data = { ...result.data, categorie: result.data.categorie || candidate.categorie || '' };
      }
      return result;
    }

    const missingColumn = extractMissingColumn(result.error);
    if (!missingColumn) {
      return result;
    }

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

function mapMouvement(row) {
  return {
    _id: row.id,
    nature: row.nature,
    source: row.source,
    quiNom: row.qui_nom || row.quiNom || '',
    quiPrenom: row.qui_prenom || row.quiPrenom || '',
    categorie: row.categorie || row.category || '',
    type: row.type || '',
    montant: Number(row.montant || 0),
    date: row.date_mouvement || row.date,
    commentaire: row.commentaire || '',
    referenceType: row.reference_type || row.referenceType || null,
    referenceId: row.reference_id || row.referenceId || null,
    externeCle: row.externe_cle || row.externeCle || null,
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

function normalizeMonthKey(value) {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

function shiftMonth(date, offset) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1, 0, 0, 0, 0));
  d.setUTCMonth(d.getUTCMonth() + offset);
  return d;
}

function toIsoDate(value) {
  const d = value ? new Date(value) : null;
  if (!d || Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function isPaidCommande(row) {
  const status = (row?.statut || row?.status || '').toString().toLowerCase();
  return status === 'payee';
}

async function fetchCommandesCompat(api, companyId) {
  let lastError = null;
  for (const companyColumn of COMMANDES_COMPANY_COLUMNS) {
    const result = await api
      .from('commandes')
      .select('*')
      .eq(companyColumn, companyId);

    if (!result.error) {
      return { data: result.data || [], error: null };
    }

    const missing = extractMissingColumn(result.error);
    if (missing === companyColumn) {
      lastError = result.error;
      continue;
    }

    return { data: [], error: result.error };
  }

  return { data: [], error: lastError };
}

router.get('/rapprochement', requirePermission('finance.read'), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const dateFrom = toIsoDate(req.query.dateFrom);
    const dateTo = toIsoDate(req.query.dateTo);

    let query = api
      .from('tresorerie_mouvements')
      .select('*')
      .eq('company_id', companyId)
      .order('date_mouvement', { ascending: false });

    if (dateFrom) query = query.gte('date_mouvement', dateFrom);
    if (dateTo) query = query.lte('date_mouvement', dateTo);

    const mouvementsRes = await query.limit(5000);
    if (mouvementsRes.error) return res.status(500).json({ message: mouvementsRes.error.message });

    let caisseNet = 0;
    let banqueNet = 0;
    let nonClassesNet = 0;
    let totalEntrees = 0;
    let totalSorties = 0;
    let nonClassesCount = 0;

    for (const row of mouvementsRes.data || []) {
      const montant = Number(row.montant || 0);
      const sign = row.nature === 'sortie' ? -1 : 1;
      const categorie = (row.categorie || row.category || '').toString().toLowerCase();
      const source = (row.source || '').toString().toLowerCase();
      const cible = `${categorie} ${source}`;

      if (sign > 0) totalEntrees += montant;
      else totalSorties += montant;

      if (cible.includes('caisse')) {
        caisseNet += sign * montant;
      } else if (cible.includes('banque') || cible.includes('bank')) {
        banqueNet += sign * montant;
      } else {
        nonClassesNet += sign * montant;
        nonClassesCount += 1;
      }
    }

    const netGlobal = totalEntrees - totalSorties;
    const ecart = netGlobal - (caisseNet + banqueNet + nonClassesNet);

    return res.json({
      totalEntrees,
      totalSorties,
      netGlobal,
      caisseNet,
      banqueNet,
      nonClassesNet,
      nonClassesCount,
      ecart,
      dateFrom,
      dateTo,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/budget-previsionnel', requirePermission('finance.read'), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const horizonMonths = Math.min(Math.max(Number(req.query.months || 6), 1), 24);

    const historyFrom = shiftMonth(new Date(), -12).toISOString();
    const mouvRes = await api
      .from('tresorerie_mouvements')
      .select('nature,montant,date_mouvement')
      .eq('company_id', companyId)
      .gte('date_mouvement', historyFrom)
      .order('date_mouvement', { ascending: true });

    if (mouvRes.error) return res.status(500).json({ message: mouvRes.error.message });

    const byMonth = new Map();
    for (const row of mouvRes.data || []) {
      const key = normalizeMonthKey(row.date_mouvement);
      if (!key) continue;
      const current = byMonth.get(key) || { entrees: 0, sorties: 0 };
      const montant = Number(row.montant || 0);
      if (row.nature === 'entree') current.entrees += montant;
      else if (row.nature === 'sortie') current.sorties += montant;
      byMonth.set(key, current);
    }

    const months = Array.from(byMonth.values());
    const avgEntrees = months.length ? months.reduce((s, m) => s + m.entrees, 0) / months.length : 0;
    const avgSorties = months.length ? months.reduce((s, m) => s + m.sorties, 0) / months.length : 0;

    const nowMonth = new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), 1));
    const projection = [];
    for (let i = 1; i <= horizonMonths; i += 1) {
      const d = shiftMonth(nowMonth, i);
      projection.push({
        mois: `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`,
        entreesPrevues: Number(avgEntrees.toFixed(2)),
        sortiesPrevues: Number(avgSorties.toFixed(2)),
        netPrevu: Number((avgEntrees - avgSorties).toFixed(2)),
      });
    }

    return res.json({
      moisAnalyses: months.length,
      moyenneEntrees: Number(avgEntrees.toFixed(2)),
      moyenneSorties: Number(avgSorties.toFixed(2)),
      projection,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/marge-par-bande', requirePermission('finance.read'), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const bandesRes = await api
      .from('bandes')
      .select('id,nom,statut,date_ouverture,date_fermeture')
      .eq('company_id', companyId)
      .order('date_ouverture', { ascending: false })
      .limit(200);
    if (bandesRes.error) return res.status(500).json({ message: bandesRes.error.message });

    const commandesRes = await fetchCommandesCompat(api, companyId);
    if (commandesRes.error) return res.status(500).json({ message: commandesRes.error.message });

    const mouvRes = await api
      .from('tresorerie_mouvements')
      .select('nature,montant,reference_type,reference_id,commentaire')
      .eq('company_id', companyId)
      .limit(8000);
    if (mouvRes.error) return res.status(500).json({ message: mouvRes.error.message });

    const revenusByBande = new Map();
    for (const row of commandesRes.data || []) {
      if (!isPaidCommande(row)) continue;
      const bandeId = row.bande_id || row.bandeId;
      if (!bandeId) continue;
      const amount = Number(row.montant_total || row.montantTotal || row.amount_total || 0);
      revenusByBande.set(String(bandeId), (revenusByBande.get(String(bandeId)) || 0) + amount);
    }

    const depensesByBande = new Map();
    for (const row of mouvRes.data || []) {
      if (row.nature !== 'sortie') continue;
      const refType = (row.reference_type || '').toString().toLowerCase();
      const refId = row.reference_id ? String(row.reference_id) : null;
      if (refType === 'bande' && refId) {
        depensesByBande.set(refId, (depensesByBande.get(refId) || 0) + Number(row.montant || 0));
      }
    }

    const marges = (bandesRes.data || []).map((b) => {
      const id = String(b.id);
      const revenus = Number(revenusByBande.get(id) || 0);
      const depenses = Number(depensesByBande.get(id) || 0);
      const marge = revenus - depenses;
      const taux = revenus > 0 ? (marge / revenus) * 100 : 0;
      return {
        bandeId: b.id,
        bandeNom: b.nom || '',
        statut: b.statut || 'ouverte',
        dateOuverture: b.date_ouverture || null,
        dateFermeture: b.date_fermeture || null,
        revenus: Number(revenus.toFixed(2)),
        depenses: Number(depenses.toFixed(2)),
        marge: Number(marge.toFixed(2)),
        tauxMarge: Number(taux.toFixed(2)),
      };
    });

    return res.json(marges);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/projection-tresorerie', requirePermission('finance.read'), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);
    const horizonMonths = Math.min(Math.max(Number(req.query.months || 6), 1), 24);

    const allMouvRes = await api
      .from('tresorerie_mouvements')
      .select('nature,montant,date_mouvement')
      .eq('company_id', companyId)
      .order('date_mouvement', { ascending: true })
      .limit(15000);
    if (allMouvRes.error) return res.status(500).json({ message: allMouvRes.error.message });

    let soldeActuel = 0;
    for (const row of allMouvRes.data || []) {
      const montant = Number(row.montant || 0);
      soldeActuel += row.nature === 'sortie' ? -montant : montant;
    }

    const recentFrom = shiftMonth(new Date(), -6).toISOString();
    const recent = (allMouvRes.data || []).filter((row) => {
      const t = new Date(row.date_mouvement).getTime();
      return !Number.isNaN(t) && t >= new Date(recentFrom).getTime();
    });

    const monthly = new Map();
    for (const row of recent) {
      const key = normalizeMonthKey(row.date_mouvement);
      if (!key) continue;
      const current = monthly.get(key) || { net: 0 };
      const montant = Number(row.montant || 0);
      current.net += row.nature === 'sortie' ? -montant : montant;
      monthly.set(key, current);
    }

    const values = Array.from(monthly.values()).map((m) => m.net);
    const netMoyenMensuel = values.length ? values.reduce((s, v) => s + v, 0) / values.length : 0;

    const nowMonth = new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), 1));
    let soldeProjete = soldeActuel;
    const projection = [];
    for (let i = 1; i <= horizonMonths; i += 1) {
      const d = shiftMonth(nowMonth, i);
      soldeProjete += netMoyenMensuel;
      projection.push({
        mois: `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`,
        variationPrevue: Number(netMoyenMensuel.toFixed(2)),
        soldeProjete: Number(soldeProjete.toFixed(2)),
      });
    }

    return res.json({
      soldeActuel: Number(soldeActuel.toFixed(2)),
      netMoyenMensuel: Number(netMoyenMensuel.toFixed(2)),
      projection,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/mouvements', requirePermission('finance.read'), async (req, res) => {
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

router.get('/mouvements/export.csv', requirePermission('finance.read'), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

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

    const { data, error } = await query.limit(5000);
    if (error) return res.status(500).json({ message: error.message });

    const filtered = (data || []).filter((row) => inWeekdays(row.date_mouvement, weekdays)).map(mapMouvement);
    const header = [
      'id', 'nature', 'source', 'qui_nom', 'qui_prenom', 'categorie', 'type', 'montant', 'date', 'commentaire', 'reference_type', 'reference_id', 'created_at',
    ];
    const rows = filtered.map((m) => [
      m._id,
      m.nature,
      m.source,
      m.quiNom,
      m.quiPrenom,
      m.categorie,
      m.type,
      m.montant,
      m.date,
      m.commentaire,
      m.referenceType,
      m.referenceId,
      m.createdAt,
    ]);

    const csv = toCsv([header, ...rows]);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="finance_mouvements_${new Date().toISOString().slice(0, 10)}.csv"`);
    return res.status(200).send(csv);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/solde', requirePermission('finance.read'), async (req, res) => {
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

router.post('/depenses', requirePermission('finance.write'), async (req, res) => {
  try {
    const api = getAdminClient();
    const companyId = await getCompanyIdForUser(api, req.user.id || req.user._id);

    const quiNom = (req.body.quiNom || '').toString().trim();
    const quiPrenom = (req.body.quiPrenom || '').toString().trim();
    const categorie = (req.body.categorie || '').toString().trim();
    const type = (req.body.type || '').toString().trim();
    const montant = Number(req.body.montant || 0);
    const commentaire = (req.body.commentaire || '').toString().trim();
    const bandeId = (req.body.bandeId || '').toString().trim();
    const date = req.body.date ? new Date(req.body.date) : new Date();

    if (!quiNom || !quiPrenom || !categorie || !type || montant <= 0 || Number.isNaN(date.getTime())) {
      return res.status(400).json({
        message: 'Champs obligatoires: quiNom, quiPrenom, categorie, type, montant (>0), date valide',
      });
    }

    let linkedBande = null;
    if (bandeId) {
      const bandeRes = await api
        .from('bandes')
        .select('id,nom')
        .eq('company_id', companyId)
        .eq('id', bandeId)
        .maybeSingle();

      if (bandeRes.error) return res.status(400).json({ message: bandeRes.error.message });
      if (!bandeRes.data) return res.status(400).json({ message: 'Bande non trouvée' });
      linkedBande = bandeRes.data;
    }

    const { data, error } = await insertTresorerieCompat(api, {
      company_id: companyId,
      nature: 'sortie',
      source: 'depense',
      qui_nom: quiNom,
      qui_prenom: quiPrenom,
      categorie,
      type,
      montant,
      date_mouvement: date.toISOString(),
      commentaire: linkedBande ? `[Bande: ${linkedBande.nom}]${commentaire ? ` ${commentaire}` : ''}` : commentaire,
      reference_type: linkedBande ? 'Bande' : 'manuel',
      reference_id: linkedBande ? linkedBande.id : null,
    });

    if (error) return res.status(400).json({ message: error.message });
    return res.status(201).json(mapMouvement(data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/approvisionnements', requirePermission('finance.write'), async (req, res) => {
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

    const { data, error } = await insertTresorerieCompat(api, {
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
    });

    if (error) return res.status(400).json({ message: error.message });
    return res.status(201).json(mapMouvement(data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/mouvements', requirePermission('finance.delete'), async (req, res) => {
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
