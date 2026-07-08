const mongoose = require('mongoose');

const alerteSchema = new mongoose.Schema({
  titre: { type: String, required: true },
  message: { type: String, required: true },
  type: { 
    type: String, 
    enum: ['vaccination', 'alimentation', 'stock_bas', 'vente', 'medicament', 'autre'], 
    required: true 
  },
  dateEcheance: { type: Date, required: true },
  bandeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Bande', default: null },
  statut: { type: String, enum: ['active', 'faite', 'ignoree'], default: 'active' },
  recurrence: { 
    type: String, 
    enum: ['aucune', 'quotidien', 'hebdomadaire', 'mensuel'], 
    default: 'aucune' 
  },
  priorite: { type: String, enum: ['basse', 'moyenne', 'haute', 'urgente'], default: 'moyenne' }
  ,
  source: { type: String, default: 'todo' },
  automatique: { type: Boolean, default: false }
}, { timestamps: true });

module.exports = mongoose.model('Alerte', alerteSchema);
