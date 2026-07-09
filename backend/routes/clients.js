const express = require('express');
const { getAdminClient } = require('../services/supabase');
const { getCompanyIdForUser } = require('../services/company_scope');

const router = express.Router();

function mapClientRow(row) {
  return {
    _id: row.id,
    nom: row.nom,
    prenom: row.prenom || '',
    telephone: row.telephone || '',
    email: row.email || '',
    adresse: row.adresse || '',
    typeClient: row.type_client || 'particulier',
    commentaireActivite: row.commentaire_activite || '',
    entreprise: row.entreprise || '',
    notes: row.notes || '',
    statut: row.statut || 'prospect',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    dernierContactLe: row.dernier_contact_le,
    chiffreAffairesCumul: Number(row.chiffre_affaires_cumul || 0),
  };
}

router.get('/', async (req, res) => {
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

router.get('/recherche', async (req, res) => {
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

router.get('/:id', async (req, res) => {
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

router.post('/', async (req, res) => {
  try {
    const adresse = (req.body.adresse || '').toString().trim();
    const typeClient = (req.body.typeClient || '').toString().trim();
    const commentaireActivite = (req.body.commentaireActivite || '').toString().trim();
    if (!adresse || !typeClient || !commentaireActivite) {
      return res.status(400).json({
        message: 'Les champs obligatoires client sont: adresse, typeClient, commentaireActivite',
      });
    }
    if (!['pro', 'particulier'].includes(typeClient)) {
      return res.status(400).json({ message: 'typeClient invalide (pro ou particulier)' });
    }

    const client = getAdminClient();
    const companyId = await getCompanyIdForUser(client, req.user.id || req.user._id);

    const payload = {
      company_id: companyId,
      nom: req.body.nom,
      prenom: req.body.prenom || '',
      telephone: req.body.telephone || '',
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

    const { data, error } = await client.from('clients').insert(payload).select('*').single();
    if (error) return res.status(400).json({ message: error.message });

    return res.status(201).json(mapClientRow(data));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
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
    if (req.body.telephone !== undefined) updates.telephone = req.body.telephone;
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

router.delete('/:id', async (req, res) => {
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
