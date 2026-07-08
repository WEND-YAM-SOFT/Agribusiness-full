const mongoose = require('mongoose');

const depenseSchema = new mongoose.Schema({
  categorie: {
    type: String,
    enum: ['aliment', 'medicament', 'salaire', 'transport', 'energie', 'maintenance', 'autre'],
    required: true
  },
  montant: { type: Number, required: true },
  date: { type: Date, default: Date.now },
  fournisseur: { type: String, default: '' },
  bandeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Bande', default: null },
  commentaire: { type: String, default: '' }
}, { timestamps: true });

module.exports = mongoose.model('Depense', depenseSchema);
