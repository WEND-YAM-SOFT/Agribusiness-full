const path = require('path');
const mongoose = require('mongoose');
const dotenv = require('dotenv');

const Client = require('../models/Client');
const Commande = require('../models/Commande');
const Bande = require('../models/Bande');
const Depense = require('../models/Depense');
const Stock = require('../models/Stock');
const Alerte = require('../models/Alerte');
const Interaction = require('../models/Interaction');
const TacheCRM = require('../models/TacheCRM');
const TresorerieMouvement = require('../models/TresorerieMouvement');

dotenv.config({ path: path.join(__dirname, '..', '.env') });

const RUN_TAG = '[seed-demo-2026]';
const escapedRunTag = RUN_TAG.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const tagRegex = new RegExp(escapedRunTag);
const testNameRegex = /^(TEST-|REPRO-NEG-|VERIFY-DATE-|STOCK TEST |STOCK TEST|TEST-CLEAR-|Todo test |CRM test )/i;

async function main() {
  if (!process.env.MONGODB_URI) {
    throw new Error('MONGODB_URI is missing in backend/.env');
  }

  await mongoose.connect(process.env.MONGODB_URI);

  try {
    const fakeStocks = await Stock.find({
      $or: [
        { notes: tagRegex },
        { nom: testNameRegex },
      ],
    }).select('_id nom');

    const fakeStockIds = fakeStocks.map((stock) => stock._id);

    const results = await Promise.all([
      Commande.deleteMany({ notes: tagRegex }),
      Interaction.deleteMany({
        $or: [
          { contenu: tagRegex },
          { sujet: testNameRegex },
        ],
      }),
      TacheCRM.deleteMany({
        $or: [
          { description: tagRegex },
          { titre: testNameRegex },
        ],
      }),
      Depense.deleteMany({ commentaire: tagRegex }),
      Stock.deleteMany({ _id: { $in: fakeStockIds } }),
      Alerte.deleteMany({
        $or: [
          { message: tagRegex },
          { titre: testNameRegex },
        ],
      }),
      Bande.deleteMany({ notes: tagRegex }),
      Client.deleteMany({ notes: tagRegex }),
      TresorerieMouvement.deleteMany({
        $or: [
          { referenceType: 'Stock', referenceId: { $in: fakeStockIds } },
          { commentaire: /^(Création stock TEST-|Entrée stock TEST-|Achat test|virgule|same-day|Création stock REPRO-NEG-|Création stock VERIFY-DATE-|Création stock STOCK TEST )/i },
          { type: testNameRegex },
        ],
      }),
    ]);

    const labels = [
      'commandes',
      'interactions',
      'tachesCRM',
      'depenses',
      'stocks',
      'alertes',
      'bandes',
      'clients',
      'tresorerie',
    ];

    console.log('Données fictives supprimées:');
    labels.forEach((label, index) => {
      console.log(`- ${label}: ${results[index].deletedCount || 0}`);
    });
  } finally {
    await mongoose.connection.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Cleanup failed:', err);
    process.exit(1);
  });