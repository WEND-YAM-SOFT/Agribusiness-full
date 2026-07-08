const mongoose = require('mongoose');

const appConfigSchema = new mongoose.Schema({
  key: { type: String, unique: true, required: true },
  nomApplication: { type: String, default: 'AgriBusiness' },
  devise: { type: String, default: 'FCFA' },
  langue: { type: String, default: 'fr' },
  sessionTimeoutMinutes: { type: Number, default: 30 },
  theme: { type: String, default: 'light' },
  notificationsEmail: { type: Boolean, default: false },
  referencesTheoriques: {
    type: mongoose.Schema.Types.Mixed,
    default: {
      poulet_chair: { dureeJours: 42, poidsFinalG: 2500, consoTotaleKgParTete: 4.2, courbeTheorique: [] },
      poule_pondeuse: { dureeJours: 140, poidsFinalG: 1800, consoTotaleKgParTete: 14.0, courbeTheorique: [] },
      dinde: { dureeJours: 90, poidsFinalG: 7000, consoTotaleKgParTete: 18.0, courbeTheorique: [] },
      canard: { dureeJours: 50, poidsFinalG: 3200, consoTotaleKgParTete: 6.0, courbeTheorique: [] },
      autre: { dureeJours: 45, poidsFinalG: 2500, consoTotaleKgParTete: 5.0, courbeTheorique: [] }
    }
  },
  notes: { type: String, default: '' }
}, { timestamps: true });

module.exports = mongoose.model('AppConfig', appConfigSchema);
