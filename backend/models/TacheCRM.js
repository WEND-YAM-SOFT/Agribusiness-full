const mongoose = require('mongoose');

const tacheCRMSchema = new mongoose.Schema({
  clientId: { type: mongoose.Schema.Types.ObjectId, ref: 'Client', default: null },
  commandeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Commande', default: null },
  titre: { type: String, required: true },
  description: { type: String, default: '' },
  type: {
    type: String,
    enum: ['relance', 'rendez_vous', 'appel', 'suivi', 'autre'],
    default: 'suivi'
  },
  dateEcheance: { type: Date, required: true },
  statut: {
    type: String,
    enum: ['a_faire', 'en_cours', 'terminee', 'annulee'],
    default: 'a_faire'
  },
  priorite: {
    type: String,
    enum: ['basse', 'moyenne', 'haute', 'urgente'],
    default: 'moyenne'
  },
  rappelActive: { type: Boolean, default: true },
  assigneA: { type: String, default: '' }
}, { timestamps: true });

module.exports = mongoose.model('TacheCRM', tacheCRMSchema);
