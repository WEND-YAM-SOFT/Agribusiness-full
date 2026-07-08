const mongoose = require('mongoose');

const tresorerieMouvementSchema = new mongoose.Schema({
  nature: {
    type: String,
    enum: ['entree', 'sortie'],
    required: true,
  },
  source: {
    type: String,
    enum: ['approvisionnement', 'depense', 'vente', 'stock_entree', 'stock_sortie', 'correction'],
    required: true,
  },
  quiNom: { type: String, default: '' },
  quiPrenom: { type: String, default: '' },
  categorie: { type: String, default: '' },
  type: { type: String, default: '' },
  montant: { type: Number, required: true, min: 0 },
  date: { type: Date, required: true },
  commentaire: { type: String, default: '' },
  referenceType: { type: String, default: '' },
  referenceId: { type: mongoose.Schema.Types.ObjectId, default: null },
  externeCle: { type: String, default: undefined },
}, { timestamps: true });

tresorerieMouvementSchema.index({ date: -1 });
tresorerieMouvementSchema.index({ externeCle: 1 }, { unique: true, sparse: true });

module.exports = mongoose.model('TresorerieMouvement', tresorerieMouvementSchema);
