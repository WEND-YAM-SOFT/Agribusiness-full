const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const utilisateurSchema = new mongoose.Schema({
  nom: { type: String, required: true },
  prenom: { type: String, default: '' },
  email: { type: String, required: true, unique: true },
  motDePasse: { type: String, required: true },
  role: { type: String, enum: ['admin', 'utilisateur'], default: 'utilisateur' },
  permissions: [{
    type: String,
    enum: [
      'dashboard:view',
      'bandes:view',
      'bandes:edit',
      'stocks:view',
      'stocks:edit',
      'commandes:view',
      'commandes:edit',
      'crm:view',
      'crm:edit',
      'alertes:view',
      'config:view',
      'users:manage'
    ]
  }],
  telephone: { type: String, default: '' },
  actif: { type: Boolean, default: true },
  derniereConnexionAt: { type: Date, default: null },
  mustChangePassword: { type: Boolean, default: false }
}, { timestamps: true });

// Hash du mot de passe avant sauvegarde
utilisateurSchema.pre('save', async function() {
  if (!this.isModified('motDePasse')) return;
  const salt = await bcrypt.genSalt(10);
  this.motDePasse = await bcrypt.hash(this.motDePasse, salt);
});

// Vérifier mot de passe
utilisateurSchema.methods.verifierMotDePasse = async function(motDePasse) {
  return await bcrypt.compare(motDePasse, this.motDePasse);
};

utilisateurSchema.methods.toPublicJson = function() {
  return {
    id: this._id,
    nom: this.nom,
    prenom: this.prenom,
    email: this.email,
    role: this.role,
    permissions: this.permissions || [],
    telephone: this.telephone,
    actif: this.actif,
    mustChangePassword: this.mustChangePassword,
    createdAt: this.createdAt,
    derniereConnexionAt: this.derniereConnexionAt
  };
};

utilisateurSchema.pre('validate', function() {
  if (this.role === 'admin') {
    this.permissions = [
      'dashboard:view',
      'bandes:view',
      'bandes:edit',
      'stocks:view',
      'stocks:edit',
      'commandes:view',
      'commandes:edit',
      'crm:view',
      'crm:edit',
      'alertes:view',
      'config:view',
      'users:manage'
    ];
  } else if (!this.permissions || this.permissions.length === 0) {
    this.permissions = [
      'dashboard:view',
      'bandes:view',
      'stocks:view',
      'commandes:view',
      'crm:view',
      'alertes:view'
    ];
  }
});

module.exports = mongoose.model('Utilisateur', utilisateurSchema);
