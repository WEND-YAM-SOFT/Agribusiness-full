const mongoose = require('mongoose');

const pieceJointeSchema = new mongoose.Schema({
  nomFichier: { type: String, required: true },
  typeMime: { type: String, default: '' },
  url: { type: String, default: '' },
  tailleOctets: { type: Number, default: 0 },
  ajouteLe: { type: Date, default: Date.now }
}, { _id: false });

const interactionSchema = new mongoose.Schema({
  clientId: { type: mongoose.Schema.Types.ObjectId, ref: 'Client', required: true },
  commandeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Commande', default: null },
  type: {
    type: String,
    enum: ['commentaire', 'appel', 'visite', 'email', 'reunion', 'autre'],
    required: true
  },
  sujet: { type: String, default: '' },
  contenu: { type: String, required: true },
  auteur: { type: String, default: 'Système' },
  dateInteraction: { type: Date, default: Date.now },
  piecesJointes: [pieceJointeSchema]
}, { timestamps: true });

module.exports = mongoose.model('Interaction', interactionSchema);
