const mongoose = require('mongoose');

const suiviJournalierSchema = new mongoose.Schema({
  date: { type: Date, default: Date.now },
  poidsMotenG: { type: Number, default: 0 },
  mortaliteJour: { type: Number, default: 0 },
  alimentationKg: { type: Number, default: 0 },
  alimentationStockId: { type: mongoose.Schema.Types.ObjectId, ref: 'Stock', default: null },
  alimentationType: { type: String, default: '' },
  eauLitres: { type: Number, default: 0 },
  temperature: { type: Number, default: 0 },
  humidite: { type: Number, default: 0 },
  observations: { type: String, default: '' }
});

const evenementSanteSchema = new mongoose.Schema({
  date: { type: Date, default: Date.now },
  type: { type: String, enum: ['vaccination', 'traitement', 'maladie', 'autre'], required: true },
  description: { type: String, required: true },
  medicament: { type: String, default: '' },
  doseParTete: { type: String, default: '' },
  dureeJours: { type: Number, default: 1 },
  cout: { type: Number, default: 0 }
});

const evenementPrevisionnelSchema = new mongoose.Schema({
  type: {
    type: String,
    enum: ['vaccination', 'traitement', 'controle_sanitaire', 'pesee', 'intervention_diverse'],
    required: true
  },
  datePrevue: { type: Date, required: true },
  description: { type: String, required: true },
  priorite: { type: String, enum: ['basse', 'moyenne', 'haute', 'urgente'], default: 'moyenne' },
  commentaires: { type: String, default: '' },
  prophylaxieStockId: { type: mongoose.Schema.Types.ObjectId, ref: 'Stock', default: null },
  prophylaxieType: { type: String, default: '' },
  prophylaxieQuantite: { type: Number, default: 0 },
  statut: { type: String, enum: ['planifie', 'termine'], default: 'planifie' },
  dateRealisation: { type: Date, default: null },
  commentairesRealisation: { type: String, default: '' }
});

const bandeSchema = new mongoose.Schema({
  nom: { type: String, required: true },
  dateOuverture: { type: Date, default: Date.now },
  dateFermeture: { type: Date, default: null },
  statut: { type: String, enum: ['ouverte', 'fermee'], default: 'ouverte' },
  typeVolaille: { type: String, enum: ['poulet_chair', 'poule_pondeuse', 'dinde', 'canard', 'autre'], required: true },
  race: { type: String, required: true },
  fournisseurPoussins: { type: String, default: '' },
  nombreInitial: { type: Number, required: true },
  nombreActuel: { type: Number, required: true },
  mortaliteTotale: { type: Number, default: 0 },
  poidsArriveeG: { type: Number, default: 0 },
  objectifPoidsG: { type: Number, default: 0 },
  dureeElevageJours: { type: Number, default: 45 },
  batiment: { type: String, default: '' },
  coutPoussin: { type: Number, default: 0 },
  suiviJournalier: [suiviJournalierSchema],
  evenementsSante: [evenementSanteSchema],
  evenementsPrevisionnels: [evenementPrevisionnelSchema],
  alertes: [{
    type: { type: String, enum: ['vaccination', 'alimentation', 'vente', 'autre'] },
    date: Date,
    message: String,
    fait: { type: Boolean, default: false }
  }],
  notes: { type: String, default: '' }
}, { timestamps: true });

// Virtuel: age de la bande en jours
bandeSchema.virtual('ageJours').get(function() {
  const fin = this.dateFermeture || new Date();
  return Math.floor((fin - this.dateOuverture) / (1000 * 60 * 60 * 24));
});

// Virtuel: taux de mortalité
bandeSchema.virtual('tauxMortalite').get(function() {
  const initial = this.nombreInitial || 0;
  const mortalite = this.mortaliteTotale || 0;
  if (initial === 0) return 0;
  return ((mortalite / initial) * 100).toFixed(2);
});

// Virtuel: consommation totale alimentation
bandeSchema.virtual('alimentationTotaleKg').get(function() {
  const suivis = Array.isArray(this.suiviJournalier) ? this.suiviJournalier : [];
  return suivis.reduce((sum, s) => sum + (s.alimentationKg || 0), 0);
});

bandeSchema.set('toJSON', { virtuals: true });

module.exports = mongoose.model('Bande', bandeSchema);
