const mongoose = require('mongoose');

const mouvementStockSchema = new mongoose.Schema({
  date: { type: Date, required: true },
  type: { type: String, enum: ['entree', 'sortie', 'ajustement', 'creation'], required: true },
  quantite: { type: Number, required: true },
  utilisateur: { type: String, required: true },
  bandeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Bande', default: null },
  motif: { type: String, default: '' },
  fournisseur: { type: String, default: '' },
  coutUnitaire: { type: Number, default: 0 }
});

const stockSchema = new mongoose.Schema({
  nom: { type: String, required: true },
  categorie: { 
    type: String, 
    enum: ['aliment', 'medicament', 'vitamine', 'desinfectant', 'materiel', 'autre'], 
    required: true 
  },
  unite: { type: String, required: true }, // kg, litres, boîtes, sachets...
  quantiteActuelle: { type: Number, default: 0 },
  seuilAlerte: { type: Number, default: 0 },
  prixUnitaire: { type: Number, default: 0 },
  dateCreationStock: { type: Date, required: true },
  fournisseur: { type: String, default: '' },
  emplacement: { type: String, default: '' },
  dateExpiration: { type: Date, default: null },
  mouvements: [mouvementStockSchema],
  notes: { type: String, default: '' }
}, { timestamps: true });

// Virtuel: stock en alerte
stockSchema.virtual('enAlerte').get(function() {
  return this.quantiteActuelle <= this.seuilAlerte;
});

// Virtuel: valeur totale du stock
stockSchema.virtual('valeurTotale').get(function() {
  return this.quantiteActuelle * this.prixUnitaire;
});

stockSchema.set('toJSON', { virtuals: true });

module.exports = mongoose.model('Stock', stockSchema);
