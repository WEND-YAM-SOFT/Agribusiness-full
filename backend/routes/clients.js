const express = require('express');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');
const { requirePermission } = require('../middleware/auth');

const router = express.Router();

function normalizeInternationalPhone(value) {
  const input = String(value || '').trim();
  if (!input) return '';

  const match = input.match(/^\+(\d{1,4})\s*(.*)$/);
  if (!match) return null;

  const countryCode = `+${match[1]}`;
  const localDigits = (match[2] || '').replace(/\D/g, '');
  if (localDigits.length < 6) return null;

  const grouped = localDigits.match(/.{1,2}/g) || [];
  return `${countryCode} ${grouped.join(' ')}`.trim();
}

function extractMissingColumn(error) {
  const message = (error?.message || '').toString();
  const match = message.match(/Could not find the '([^']+)' column/i);
  return match?.[1] || '';
}

async function insertClientCompat(client, payload) {
  let candidate = { ...payload };
  let lastMissingColumn = '';

  for (let i = 0; i < 15; i += 1) {
    const result = await client.from('clients').insert(candidate).select('*').single();
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
    error: { message: `Creation client impossible: schema incompatible apres tentatives de fallback (derniere colonne: ${lastMissingColumn || 'inconnue'})` },
  };
}

function mapClientRow(row) {
  return {
    _id: row.id,
    nom: row.nom,
    prenom: row.prenom || '',
    telephone: row.telephone || '',
    email: row.email || '',
    adresse: row.adresse || row.address || '',
    typeClient: row.type_client || row.typeClient || 'particulier',
    commentaireActivite: row.commentaire_activite || row.commentaireActivite || '',
    entreprise: row.entreprise || row.company || '',
    notes: row.notes || '',
    statut: row.statut || row.status || 'prospect',
    createdAt: row.created_at || row.createdAt,
    updatedAt: row.updated_at || row.updatedAt,
    dernierContactLe: row.dernier_contact_le || row.dernierContactLe,
    chiffreAffairesCumul: Number(row.chiffre_affaires_cumul || row.chiffreAffairesCumul || 0),
  };
}

router.get('/', requirePermission('clients.read'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    let query = client.from('clients').select('*').eq('company_id', companyId).order('nom', { ascending: true });

    const statut = (req.query.statut || '').toString().trim();
    if (statut) {
      query = query.eq('statut', statut);
    }

    const { data, error } = await query;
    if (error) return res.status(500).json({ message: error.message });

    const q = (req.query.q || '').toString().trim().toLowerCase();
    let rows = data || [];
    if (q) {
      rows = rows.filter((row) => {
        const fields = [
          row.nom,
          row.prenom,
          row.telephone,
          row.entreprise,
          row.adresse,
          row.commentaire_activite,
        ];
        return fields.some((v) => (v || '').toString().toLowerCase().includes(q));
      });
    }

    return res.json(rows.map(mapClientRow));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/recherche', requirePermission('clients.read'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const { data, error } = await client
      .from('clients')
      .select('*')
      .eq('company_id', companyId)
      .order('nom', { ascending: true });

    if (error) return res.status(500).json({ message: error.message });

    const q = (req.query.q || '').toString().trim().toLowerCase();
    const rows = (data || []).filter((row) => {
      const fields = [
        row.nom,
        row.prenom,
        row.telephone,
        row.entreprise,
        row.adresse,
        row.commentaire_activite,
      ];
      return fields.some((v) => (v || '').toString().toLowerCase().includes(q));
    });

    return res.json(rows.map(mapClientRow));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', requirePermission('clients.read'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const { data, error } = await client
      .from('clients')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (error) return res.status(500).json({ message: error.message });
    if (!data) return res.status(404).json({ message: 'Client non trouvé' });

    return res.json(mapClientRow(data));
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', requirePermission('clients.create'), async (req, res) => {
  try {
    const nom = (req.body.nom || '').toString().trim();
    const prenom = (req.body.prenom || '').toString().trim();
    const telephone = normalizeInternationalPhone(req.body.telephone || '');
    if (!nom || !prenom || !telephone) {
      return res.status(400).json({ message: 'Les champs obligatoires client sont: nom, prenom, telephone' });
    }

    const adresse = (req.body.adresse || '').toString().trim() || 'Non renseignée';
    const rawTypeClient = (req.body.typeClient || req.body.type_client || '').toString().trim().toLowerCase();
    const typeClient = rawTypeClient === 'professionnel' ? 'pro' : (rawTypeClient || 'particulier');
    const commentaireActivite = (req.body.commentaireActivite || req.body.commentaire_activite || '').toString().trim() || 'RAS';

    if (!['pro', 'particulier'].includes(typeClient)) {
      return res.status(400).json({ message: 'typeClient invalide (pro ou particulier)' });
    }

    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const payload = {
      company_id: companyId,
      nom,
      prenom,
      telephone,
      email: req.body.email || '',
      adresse,
      type_client: typeClient,
      commentaire_activite: commentaireActivite,
      entreprise: req.body.entreprise || '',
      statut: req.body.statut || 'prospect',
      notes: req.body.notes || '',
      dernier_contact_le: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await insertClientCompat(client, payload);
    if (error) return res.status(400).json({ message: error.message });

    return res.status(201).json(mapClientRow(data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id', requirePermission('clients.update'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const existing = await client
      .from('clients')
      .select('*')
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .maybeSingle();

    if (existing.error) return res.status(400).json({ message: existing.error.message });
    if (!existing.data) return res.status(404).json({ message: 'Client non trouvé' });

    if (req.body.typeClient && !['pro', 'particulier'].includes(req.body.typeClient)) {
      return res.status(400).json({ message: 'typeClient invalide (pro ou particulier)' });
    }

    const updates = {
      updated_at: new Date().toISOString(),
    };

    if (req.body.nom !== undefined) updates.nom = req.body.nom;
    if (req.body.prenom !== undefined) updates.prenom = req.body.prenom;
    if (req.body.telephone !== undefined) {
      const telephone = normalizeInternationalPhone(req.body.telephone);
      if (!telephone) return res.status(400).json({ message: 'Téléphone invalide. Format attendu: +221 77 12 34 56' });
      updates.telephone = telephone;
    }
    if (req.body.email !== undefined) updates.email = req.body.email;
    if (req.body.entreprise !== undefined) updates.entreprise = req.body.entreprise;
    if (req.body.notes !== undefined) updates.notes = req.body.notes;
    if (req.body.statut !== undefined) updates.statut = req.body.statut;

    if (req.body.adresse !== undefined) {
      const adresse = req.body.adresse.toString().trim();
      if (!adresse) return res.status(400).json({ message: 'Adresse obligatoire' });
      updates.adresse = adresse;
    }

    if (req.body.commentaireActivite !== undefined) {
      const commentaire = req.body.commentaireActivite.toString().trim();
      if (!commentaire) return res.status(400).json({ message: 'Commentaire activité obligatoire' });
      updates.commentaire_activite = commentaire;
    }

    if (req.body.typeClient !== undefined) {
      updates.type_client = req.body.typeClient;
    }

    const saved = await client
      .from('clients')
      .update(updates)
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('*')
      .single();

    if (saved.error) return res.status(400).json({ message: saved.error.message });
    return res.json(mapClientRow(saved.data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/:id', requirePermission('clients.delete'), async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const removed = await client
      .from('clients')
      .delete()
      .eq('company_id', companyId)
      .eq('id', req.params.id)
      .select('id')
      .maybeSingle();

    if (removed.error) return res.status(500).json({ message: removed.error.message });
    if (!removed.data) return res.status(404).json({ message: 'Client non trouvé' });

    return res.json({ message: 'Client supprimé' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
