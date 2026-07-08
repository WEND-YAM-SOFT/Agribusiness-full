const TresorerieMouvement = require('../models/TresorerieMouvement');

function _safeTrim(value) {
  return (value || '').toString().trim();
}

async function enregistrerMouvement(payload) {
  const montant = Number(payload.montant || 0);
  if (Number.isNaN(montant) || montant <= 0) {
    return null;
  }

  if (payload.externeCle) {
    const existing = await TresorerieMouvement.findOne({ externeCle: payload.externeCle });
    if (existing) return existing;
  }

  const mouvement = new TresorerieMouvement({
    nature: payload.nature,
    source: payload.source,
    quiNom: _safeTrim(payload.quiNom),
    quiPrenom: _safeTrim(payload.quiPrenom),
    categorie: _safeTrim(payload.categorie),
    type: _safeTrim(payload.type),
    montant,
    date: payload.date ? new Date(payload.date) : new Date(),
    commentaire: _safeTrim(payload.commentaire),
    referenceType: _safeTrim(payload.referenceType),
    referenceId: payload.referenceId || null,
    externeCle: _safeTrim(payload.externeCle) || undefined,
  });

  return mouvement.save();
}

function extraireNomPrenomUtilisateur(user) {
  const nomComplet = _safeTrim(user?.nomComplet);
  if (nomComplet) {
    const parts = nomComplet.split(/\s+/);
    return {
      quiPrenom: parts.shift() || 'Utilisateur',
      quiNom: parts.join(' ') || 'Système',
    };
  }

  const prenom = _safeTrim(user?.prenom || user?.firstName || 'Utilisateur');
  const nom = _safeTrim(user?.nom || user?.lastName || 'Système');
  return { quiPrenom: prenom, quiNom: nom };
}

module.exports = {
  enregistrerMouvement,
  extraireNomPrenomUtilisateur,
};
