const mongoose = require('mongoose');

const livraisonSchema = new mongoose.Schema({
  dateLivraisonPrevue: { type: Date, required: true },
  dateLivraisonReelle: { type: Date, default: null },
  statutLivraison: {
    type: String,
    enum: ['planifiee', 'en_cours', 'livree', 'annulee'],
    default: 'planifiee',
  },
  fraisLivraison: { type: Number, default: 0 },
  commentaires: { type: String, default: '' },
  utilisateur: { type: String, default: 'Utilisateur' },
}, { timestamps: true });

const commandeSchema = new mongoose.Schema({
  client: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Client',
    required: true
  },
  bande: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Bande',
    default: null
  },
  produits: [{
    nom: { type: String, required: true },
    quantite: { type: Number, required: true },
    prixUnitaire: { type: Number, required: true }
  }],
  montantTotal: {
    type: Number,
    required: true
  },
  statut: {
    type: String,
    enum: ['en_attente', 'confirmee', 'en_preparation', 'livree', 'annulee', 'payee'],
    default: 'en_attente'
  },
  venteComptabilisee: {
    type: Boolean,
    default: false,
  },
  dernierMouvementTresorerieId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'TresorerieMouvement',
    default: null,
  },
  dateLivraison: {
    type: Date,
    default: null
  },
  notes: {
    type: String,
    default: ''
  },
  commentaires: [{
    auteur: { type: String, default: 'Système' },
    message: { type: String, required: true },
    date: { type: Date, default: Date.now }
  }],
  historiqueActions: [{
    action: { type: String, required: true },
    auteur: { type: String, default: 'Système' },
    date: { type: Date, default: Date.now },
    details: { type: String, default: '' }
  }],
  livraisons: [livraisonSchema],
}, { timestamps: true });

module.exports = mongoose.model('Commande', commandeSchema);
