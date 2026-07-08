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

dotenv.config({ path: path.join(__dirname, '..', '.env') });

const RUN_TAG = '[seed-demo-2026]';

let seed = 20260706;
function rnd() {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 4294967296;
}

function randInt(min, max) {
  return Math.floor(rnd() * (max - min + 1)) + min;
}

function pick(arr) {
  return arr[randInt(0, arr.length - 1)];
}

function daysAgo(n) {
  const d = new Date();
  d.setHours(12, 0, 0, 0);
  d.setDate(d.getDate() - n);
  return d;
}

function daysAfter(date, n) {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

function money(value) {
  return Math.round(value);
}

function buildBandeProgress(startDate, durationDays, initial, startWeight, targetWeight) {
  const suiviJournalier = [];
  const evenementsSante = [];
  let mortaliteTotale = 0;

  for (let day = 1; day <= durationDays; day += 1) {
    const ageFactor = day / durationDays;
    const poids = startWeight + (targetWeight - startWeight) * ageFactor + randInt(-12, 12);
    const baseFeed = 4 + ageFactor * 20;
    const alimentationKg = Math.max(2, baseFeed + randInt(-1, 2));
    const eauLitres = Math.max(10, alimentationKg * randInt(2, 4));
    const temperature = Math.max(22, 33 - ageFactor * 9 + randInt(-1, 1));
    const humidite = Math.max(45, Math.min(75, 62 + randInt(-6, 6)));

    let mortaliteJour = 0;
    if (day <= 7 && rnd() > 0.7) mortaliteJour = randInt(0, 2);
    if (day > 7 && day <= 21 && rnd() > 0.82) mortaliteJour = randInt(0, 1);
    if (day > 21 && rnd() > 0.9) mortaliteJour = randInt(0, 1);

    mortaliteTotale += mortaliteJour;

    suiviJournalier.push({
      date: daysAfter(startDate, day - 1),
      poidsMotenG: money(poids),
      mortaliteJour,
      alimentationKg: money(alimentationKg),
      eauLitres: money(eauLitres),
      temperature: Number(temperature.toFixed(1)),
      humidite: Number(humidite.toFixed(1)),
      observations: day % 10 === 0 ? 'Controle veterinaire satisfaisant' : ''
    });

    if ([7, 14, 21].includes(day)) {
      evenementsSante.push({
        date: daysAfter(startDate, day - 1),
        type: 'vaccination',
        description: `Vaccination jour ${day}`,
        medicament: day === 7 ? 'Newcastle' : (day === 14 ? 'Gumboro' : 'Rappel mixte'),
        doseParTete: '0.2 ml',
        dureeJours: 1,
        cout: money(initial * 30)
      });
    }

    if (day === 28 || day === 35) {
      evenementsSante.push({
        date: daysAfter(startDate, day - 1),
        type: 'traitement',
        description: 'Traitement preventif antiparasitaire',
        medicament: 'Anticox',
        doseParTete: '1 ml/L eau',
        dureeJours: 3,
        cout: money(initial * 18)
      });
    }
  }

  return {
    suiviJournalier,
    evenementsSante,
    mortaliteTotale,
    nombreActuel: Math.max(0, initial - mortaliteTotale)
  };
}

async function clearPreviousSeedData() {
  const tagRegex = new RegExp(RUN_TAG.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));

  await Promise.all([
    Commande.deleteMany({ notes: tagRegex }),
    Interaction.deleteMany({ contenu: tagRegex }),
    TacheCRM.deleteMany({ description: tagRegex }),
    Depense.deleteMany({ commentaire: tagRegex }),
    Stock.deleteMany({ notes: tagRegex }),
    Alerte.deleteMany({ message: tagRegex }),
    Bande.deleteMany({ notes: tagRegex }),
    Client.deleteMany({ notes: tagRegex })
  ]);
}

function buildClients() {
  const raw = [
    ['Diallo', 'Mamadou'], ['Sow', 'Fatou'], ['Ndiaye', 'Cheikh'], ['Ba', 'Aminata'],
    ['Fall', 'Ibrahima'], ['Ndao', 'Khady'], ['Sy', 'Abdoulaye'], ['Kane', 'Mariama'],
    ['Diop', 'Aissatou'], ['Sarr', 'Ousmane'], ['Cisse', 'Penda'], ['Gueye', 'Moussa'],
    ['Ndour', 'Yacine'], ['Faye', 'Babacar'], ['Seck', 'Awa'], ['Lo', 'Serigne'],
    ['Mbaye', 'Ndeye'], ['Camara', 'Adama'], ['Traore', 'Binta'], ['Konate', 'Issa'],
    ['Coulibaly', 'Aicha'], ['Ouattara', 'Mariam'], ['Keita', 'Salif'], ['Balde', 'Nafissatou']
  ];

  return raw.map((n, i) => {
    const statut = i < 12 ? 'actif' : (i < 20 ? 'prospect' : 'inactif');
    const createdAt = daysAgo(randInt(30, 320));
    return {
      nom: n[0],
      prenom: n[1],
      telephone: `77${randInt(1000000, 9999999)}`,
      email: `${n[1].toLowerCase()}.${n[0].toLowerCase()}@example.com`,
      adresse: `${randInt(1, 200)} Avenue Elevage, Zone ${randInt(1, 9)}`,
      entreprise: i % 3 === 0 ? `Ferme ${n[0]}` : '',
      statut,
      notes: `${RUN_TAG} Client de demonstration pour tests CRM`,
      dernierContactLe: daysAgo(randInt(0, 25)),
      chiffreAffairesCumul: 0,
      historiqueAchats: [],
      createdAt,
      updatedAt: createdAt
    };
  });
}

function buildBandes() {
  const specs = [
    { nom: 'Bande Broiler A1', typeVolaille: 'poulet_chair', race: 'Cobb 500', initial: 2000, days: 42, ouverte: false, batiment: 'Bat A' },
    { nom: 'Bande Broiler A2', typeVolaille: 'poulet_chair', race: 'Ross 308', initial: 1800, days: 38, ouverte: true, batiment: 'Bat A' },
    { nom: 'Bande Pondeuse B1', typeVolaille: 'poule_pondeuse', race: 'Lohmann Brown', initial: 1500, days: 55, ouverte: false, batiment: 'Bat B' },
    { nom: 'Bande Dinde C1', typeVolaille: 'dinde', race: 'Big 6', initial: 900, days: 47, ouverte: false, batiment: 'Bat C' },
    { nom: 'Bande Canard D1', typeVolaille: 'canard', race: 'Pekin', initial: 700, days: 33, ouverte: true, batiment: 'Bat D' },
    { nom: 'Bande Broiler E1', typeVolaille: 'poulet_chair', race: 'Hubbard', initial: 2200, days: 45, ouverte: false, batiment: 'Bat E' }
  ];

  return specs.map((s, idx) => {
    const startDate = daysAgo(210 - idx * 28 - randInt(0, 10));
    const progression = buildBandeProgress(startDate, s.days, s.initial, 42, s.typeVolaille === 'dinde' ? 4200 : 2500);
    const isOpen = s.ouverte;

    return {
      nom: s.nom,
      dateOuverture: startDate,
      dateFermeture: isOpen ? null : daysAfter(startDate, s.days),
      statut: isOpen ? 'ouverte' : 'fermee',
      typeVolaille: s.typeVolaille,
      race: s.race,
      fournisseurPoussins: pick(['AgriChick SA', 'Volailles Plus', 'ProPoussin']),
      nombreInitial: s.initial,
      nombreActuel: progression.nombreActuel,
      mortaliteTotale: progression.mortaliteTotale,
      poidsArriveeG: 42,
      objectifPoidsG: s.typeVolaille === 'dinde' ? 4500 : 2600,
      dureeElevageJours: s.days,
      batiment: s.batiment,
      coutPoussin: s.typeVolaille === 'dinde' ? 1200 : 650,
      suiviJournalier: progression.suiviJournalier,
      evenementsSante: progression.evenementsSante,
      alertes: [
        {
          type: 'vaccination',
          date: daysAfter(startDate, 14),
          message: `Vaccination planifiee bande ${s.nom}`,
          fait: true
        },
        {
          type: 'alimentation',
          date: daysAfter(startDate, Math.max(3, s.days - 2)),
          message: `Verification stock aliment bande ${s.nom}`,
          fait: !isOpen
        }
      ],
      notes: `${RUN_TAG} Bande de demonstration`,
      createdAt: startDate,
      updatedAt: isOpen ? daysAgo(randInt(0, 2)) : daysAfter(startDate, s.days)
    };
  });
}

function buildStocks(bandes) {
  const openBande = bandes.find((b) => b.statut === 'ouverte');
  const openBandeId = openBande ? openBande._id : null;

  const items = [
    ['Aliment demarrage', 'aliment', 'kg', 6200, 1200, 380],
    ['Aliment croissance', 'aliment', 'kg', 4200, 900, 365],
    ['Aliment finition', 'aliment', 'kg', 2100, 700, 355],
    ['Vitamine C', 'vitamine', 'boite', 38, 10, 5200],
    ['Complexe B', 'vitamine', 'boite', 14, 12, 6100],
    ['Antibiotique large spectre', 'medicament', 'flacon', 22, 8, 12800],
    ['Desinfectant sol', 'desinfectant', 'litre', 120, 40, 1800],
    ['Litiere copeaux', 'materiel', 'sac', 95, 30, 2400],
    ['Aiguilles vaccination', 'materiel', 'boite', 8, 10, 4200],
    ['Gants nitrile', 'materiel', 'boite', 16, 6, 3500],
    ['Electrolytes', 'medicament', 'sachet', 45, 12, 1600],
    ['Charbon actif', 'autre', 'sachet', 25, 8, 1900]
  ];

  return items.map((it, i) => {
    const current = it[3] - randInt(0, Math.floor(it[3] * 0.5));
    const movements = [];
    const mCount = randInt(5, 10);
    let simQty = 0;

    for (let m = 0; m < mCount; m += 1) {
      const isEntry = m % 3 !== 0;
      const qte = isEntry ? randInt(20, 400) : randInt(10, 250);
      const mv = {
        date: daysAgo(randInt(0, 120)),
        type: isEntry ? 'entree' : 'sortie',
        quantite: qte,
        bandeId: isEntry ? null : openBandeId,
        motif: isEntry ? 'Approvisionnement fournisseur' : 'Consommation elevage',
        fournisseur: isEntry ? pick(['AgriFeed', 'VetSupply', 'FarmCare']) : '',
        coutUnitaire: it[5]
      };
      movements.push(mv);
      simQty += isEntry ? qte : -qte;
    }

    return {
      nom: it[0],
      categorie: it[1],
      unite: it[2],
      quantiteActuelle: Math.max(0, current),
      seuilAlerte: it[4],
      prixUnitaire: it[5],
      fournisseur: pick(['AgriFeed', 'VetSupply', 'FarmCare', 'BioFarm']),
      emplacement: `Depot ${String.fromCharCode(65 + (i % 4))}`,
      dateExpiration: it[1] === 'aliment' || it[1] === 'medicament' || it[1] === 'vitamine' ? daysAfter(new Date(), randInt(40, 240)) : null,
      mouvements: movements,
      notes: `${RUN_TAG} Stock de demonstration`,
      createdAt: daysAgo(randInt(120, 260)),
      updatedAt: daysAgo(randInt(0, 15))
    };
  });
}

function buildDepenses(bandes) {
  const categories = ['aliment', 'medicament', 'salaire', 'transport', 'energie', 'maintenance', 'autre'];
  const depenses = [];

  for (let day = 180; day >= 0; day -= 2) {
    const count = rnd() > 0.55 ? 2 : 1;
    for (let i = 0; i < count; i += 1) {
      const categorie = pick(categories);
      let base;

      if (categorie === 'aliment') base = randInt(120000, 420000);
      else if (categorie === 'medicament') base = randInt(35000, 140000);
      else if (categorie === 'salaire') base = randInt(90000, 260000);
      else if (categorie === 'transport') base = randInt(25000, 90000);
      else if (categorie === 'energie') base = randInt(40000, 120000);
      else if (categorie === 'maintenance') base = randInt(30000, 100000);
      else base = randInt(15000, 65000);

      const linkedBande = rnd() > 0.3 ? pick(bandes) : null;
      const date = daysAgo(day + randInt(0, 1));

      depenses.push({
        categorie,
        montant: money(base),
        date,
        fournisseur: pick(['AgriFeed', 'VetSupply', 'PowerGrid', 'TransportPro', 'MaintenancePlus']),
        bandeId: linkedBande ? linkedBande._id : null,
        commentaire: `${RUN_TAG} Depense ${categorie} pour exploitation`,
        createdAt: date,
        updatedAt: date
      });
    }
  }

  return depenses;
}

function buildCommandes(clients, bandes) {
  const produitsCatalog = [
    ['Poulet vif standard', 3200],
    ['Poulet pret a cuire', 4200],
    ['Oeufs plaque 30', 2900],
    ['Dinde entiere', 14500],
    ['Canard entier', 9800],
    ['Abats conditionnes', 1800]
  ];

  const commandes = [];

  for (let day = 210; day >= 0; day -= 3) {
    const dateCommande = daysAgo(day);
    const client = pick(clients);
    const linkedBande = rnd() > 0.45 ? pick(bandes) : null;

    const productCount = randInt(1, 3);
    const produits = [];
    let total = 0;

    for (let p = 0; p < productCount; p += 1) {
      const prod = pick(produitsCatalog);
      const quantite = prod[0].includes('Oeufs') ? randInt(20, 200) : randInt(15, 140);
      const prixUnitaire = money(prod[1] * (0.95 + rnd() * 0.2));
      produits.push({ nom: prod[0], quantite, prixUnitaire });
      total += quantite * prixUnitaire;
    }

    let statut;
    if (day <= 7) {
      statut = pick(['en_attente', 'confirmee', 'en_preparation']);
    } else if (day <= 21) {
      statut = pick(['confirmee', 'en_preparation', 'livree']);
    } else {
      statut = rnd() > 0.12 ? 'livree' : 'annulee';
    }

    const dateLivraison = statut === 'livree' ? daysAfter(dateCommande, randInt(1, 4)) : null;

    const historiqueActions = [
      {
        action: 'creation_commande',
        auteur: 'Commercial',
        date: dateCommande,
        details: 'Commande enregistree dans le systeme'
      }
    ];

    if (['confirmee', 'en_preparation', 'livree'].includes(statut)) {
      historiqueActions.push({
        action: 'changement_statut',
        auteur: 'Commercial',
        date: daysAfter(dateCommande, 1),
        details: 'Statut passe a confirmee'
      });
    }
    if (statut === 'en_preparation') {
      historiqueActions.push({
        action: 'changement_statut',
        auteur: 'Logistique',
        date: daysAfter(dateCommande, 2),
        details: 'Mise en preparation'
      });
    }
    if (statut === 'livree') {
      historiqueActions.push({
        action: 'livraison_effectuee',
        auteur: 'Livreur',
        date: dateLivraison,
        details: 'Livraison confirmee par le client'
      });
    }

    const commentaires = rnd() > 0.4
      ? [{ auteur: 'Commercial', message: `${RUN_TAG} Confirmation telephone client`, date: daysAfter(dateCommande, 1) }]
      : [];

    commandes.push({
      client: client._id,
      bande: linkedBande ? linkedBande._id : null,
      produits,
      montantTotal: money(total),
      statut,
      dateLivraison,
      notes: `${RUN_TAG} Commande de demonstration`,
      commentaires,
      historiqueActions,
      createdAt: dateCommande,
      updatedAt: statut === 'livree' && dateLivraison ? dateLivraison : daysAfter(dateCommande, randInt(0, 3))
    });
  }

  return commandes;
}

function buildInteractions(clients, commandesByClient) {
  const types = ['commentaire', 'appel', 'visite', 'email', 'reunion'];
  const interactions = [];

  for (const client of clients) {
    const commandList = commandesByClient.get(String(client._id)) || [];
    const count = randInt(2, 5);

    for (let i = 0; i < count; i += 1) {
      const dateInteraction = daysAgo(randInt(0, 120));
      const linkedCommande = commandList.length > 0 && rnd() > 0.5 ? pick(commandList) : null;
      const type = pick(types);

      interactions.push({
        clientId: client._id,
        commandeId: linkedCommande ? linkedCommande._id : null,
        type,
        sujet: type === 'appel' ? 'Suivi commande' : (type === 'visite' ? 'Visite ferme client' : 'Point commercial'),
        contenu: `${RUN_TAG} Echange ${type} avec le client pour suivi commercial`,
        auteur: pick(['Agent CRM', 'Commercial 1', 'Responsable ventes']),
        dateInteraction,
        piecesJointes: rnd() > 0.8
          ? [{ nomFichier: 'compte_rendu.pdf', typeMime: 'application/pdf', url: '/demo/compte_rendu.pdf', tailleOctets: 124000, ajouteLe: dateInteraction }]
          : [],
        createdAt: dateInteraction,
        updatedAt: dateInteraction
      });
    }
  }

  return interactions;
}

function buildTaches(clients, commandesByClient) {
  const types = ['relance', 'rendez_vous', 'appel', 'suivi'];
  const priorities = ['basse', 'moyenne', 'haute', 'urgente'];
  const statuses = ['a_faire', 'en_cours', 'terminee'];
  const tasks = [];

  for (const client of clients) {
    const commandList = commandesByClient.get(String(client._id)) || [];
    const count = randInt(1, 3);

    for (let i = 0; i < count; i += 1) {
      const type = pick(types);
      const priorite = pick(priorities);
      const statut = pick(statuses);
      const dateEcheance = daysAfter(new Date(), randInt(-10, 25));
      const createdAt = daysAgo(randInt(0, 50));

      tasks.push({
        clientId: client._id,
        commandeId: commandList.length > 0 && rnd() > 0.6 ? pick(commandList)._id : null,
        titre: `${type === 'relance' ? 'Relancer' : 'Suivre'} ${client.nom}`,
        description: `${RUN_TAG} Tache CRM ${type} planifiee`,
        type,
        dateEcheance,
        statut,
        priorite,
        rappelActive: statut !== 'terminee',
        assigneA: pick(['Agent CRM', 'Commercial 1', 'Commercial 2']),
        createdAt,
        updatedAt: createdAt
      });
    }
  }

  return tasks;
}

function buildAlertes(bandes, stocks) {
  const alertes = [];

  for (const bande of bandes) {
    if (bande.statut === 'ouverte') {
      alertes.push({
        titre: `Vaccination a planifier - ${bande.nom}`,
        message: `${RUN_TAG} Rappel vaccination preventive pour bande en cours`,
        type: 'vaccination',
        dateEcheance: daysAfter(new Date(), randInt(1, 5)),
        bandeId: bande._id,
        statut: 'active',
        recurrence: 'aucune',
        priorite: 'haute',
        createdAt: daysAgo(randInt(0, 7)),
        updatedAt: daysAgo(randInt(0, 3))
      });

      alertes.push({
        titre: `Controle alimentation - ${bande.nom}`,
        message: `${RUN_TAG} Verifier consommation aliment de la semaine`,
        type: 'alimentation',
        dateEcheance: daysAfter(new Date(), randInt(-2, 2)),
        bandeId: bande._id,
        statut: rnd() > 0.5 ? 'active' : 'faite',
        recurrence: 'hebdomadaire',
        priorite: 'moyenne',
        createdAt: daysAgo(randInt(2, 15)),
        updatedAt: daysAgo(randInt(0, 3))
      });
    }
  }

  const lowStocks = stocks.filter((s) => s.quantiteActuelle <= s.seuilAlerte + 5);
  for (const s of lowStocks) {
    alertes.push({
      titre: `Stock bas - ${s.nom}`,
      message: `${RUN_TAG} Le stock ${s.nom} est proche du seuil d'alerte`,
      type: 'stock_bas',
      dateEcheance: daysAfter(new Date(), randInt(0, 3)),
      bandeId: null,
      statut: 'active',
      recurrence: 'aucune',
      priorite: 'urgente',
      createdAt: daysAgo(randInt(0, 4)),
      updatedAt: daysAgo(randInt(0, 2))
    });
  }

  return alertes;
}

async function updateClientKpis(clients, commandes) {
  const byClient = new Map();
  for (const c of clients) {
    byClient.set(String(c._id), []);
  }

  for (const cmd of commandes) {
    const key = String(cmd.client);
    if (!byClient.has(key)) byClient.set(key, []);
    byClient.get(key).push(cmd);
  }

  const bulkOps = [];

  for (const client of clients) {
    const list = byClient.get(String(client._id)) || [];
    const delivered = list.filter((c) => c.statut === 'livree');
    const ca = delivered.reduce((sum, c) => sum + c.montantTotal, 0);
    const latestContact = list.length > 0
      ? list.reduce((a, b) => (a.updatedAt > b.updatedAt ? a : b)).updatedAt
      : client.dernierContactLe;

    const historiqueAchats = delivered
      .sort((a, b) => b.createdAt - a.createdAt)
      .slice(0, 12)
      .map((c) => ({ commandeId: c._id, date: c.createdAt, montant: c.montantTotal }));

    bulkOps.push({
      updateOne: {
        filter: { _id: client._id },
        update: {
          $set: {
            chiffreAffairesCumul: ca,
            dernierContactLe: latestContact,
            historiqueAchats,
            statut: ca > 0 ? 'actif' : client.statut
          }
        }
      }
    });
  }

  if (bulkOps.length > 0) {
    await Client.bulkWrite(bulkOps);
  }
}

async function main() {
  if (!process.env.MONGODB_URI) {
    throw new Error('MONGODB_URI is missing in backend/.env');
  }

  await mongoose.connect(process.env.MONGODB_URI);

  try {
    console.log('Seeding demo data...');

    await clearPreviousSeedData();

    const clients = await Client.insertMany(buildClients());
    const bandes = await Bande.insertMany(buildBandes());
    const stocks = await Stock.insertMany(buildStocks(bandes));
    const depenses = await Depense.insertMany(buildDepenses(bandes));

    const commandes = await Commande.insertMany(buildCommandes(clients, bandes));

    const commandesByClient = new Map();
    for (const cmd of commandes) {
      const key = String(cmd.client);
      if (!commandesByClient.has(key)) commandesByClient.set(key, []);
      commandesByClient.get(key).push(cmd);
    }

    const interactions = await Interaction.insertMany(buildInteractions(clients, commandesByClient));
    const taches = await TacheCRM.insertMany(buildTaches(clients, commandesByClient));
    const alertes = await Alerte.insertMany(buildAlertes(bandes, stocks));

    await updateClientKpis(clients, commandes);

    const delivered = commandes.filter((c) => c.statut === 'livree');
    const activeOrders = commandes.filter((c) => ['en_attente', 'confirmee', 'en_preparation'].includes(c.statut));
    const cancelled = commandes.filter((c) => c.statut === 'annulee');

    const totalSales = delivered.reduce((s, c) => s + c.montantTotal, 0);
    const totalExpenses = depenses.reduce((s, d) => s + d.montant, 0);
    const netProfit = totalSales - totalExpenses;

    console.log('Demo data inserted successfully:');
    console.log(`- Clients: ${clients.length}`);
    console.log(`- Bandes: ${bandes.length}`);
    console.log(`- Stocks: ${stocks.length}`);
    console.log(`- Depenses: ${depenses.length}`);
    console.log(`- Commandes total: ${commandes.length}`);
    console.log(`  - Actives: ${activeOrders.length}`);
    console.log(`  - Livrees: ${delivered.length}`);
    console.log(`  - Annulees: ${cancelled.length}`);
    console.log(`- Interactions CRM: ${interactions.length}`);
    console.log(`- Taches CRM: ${taches.length}`);
    console.log(`- Alertes: ${alertes.length}`);
    console.log(`- Ventes (livrees): ${totalSales} FCFA`);
    console.log(`- Depenses: ${totalExpenses} FCFA`);
    console.log(`- Benefice net: ${netProfit} FCFA`);
  } finally {
    await mongoose.connection.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  });
