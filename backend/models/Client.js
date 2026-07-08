const mongoose = require('mongoose');

const clientSchema = new mongoose.Schema({
  nom: {
    type: String,
    required: true
  },
  prenom: {
    type: String,
    required: true
  },
  telephone: {
    type: String,
    required: true
  },
  email: {
    type: String,
    default: ''
  },
  adresse: {
    type: String,
    required: true,
    trim: true
  },
  typeClient: {
    type: String,
    enum: ['pro', 'particulier'],
    required: true,
    default: 'particulier'
  },
  commentaireActivite: {
    type: String,
    required: true,
    trim: true,
    default: ''
  },
  entreprise: {
    type: String,
    default: ''
  },
  statut: {
    type: String,
    enum: ['prospect', 'actif', 'inactif'],
    default: 'prospect'
  },
  notes: {
    type: String,
    default: ''
  },
  dernierContactLe: {
    type: Date,
    default: null
  },
  chiffreAffairesCumul: {
    type: Number,
    default: 0
  },
  historiqueAchats: [{
    commandeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Commande' },
    date: Date,
    montant: Number
  }]
}, { timestamps: true });

module.exports = mongoose.model('Client', clientSchema);
