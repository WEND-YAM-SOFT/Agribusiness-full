class SuiviJournalier {
  final String? id;
  final DateTime date;
  final double poidsMotenG;
  final int mortaliteJour;
  final double alimentationKg;
  final String alimentationType;
  final String? alimentationStockId;
  final double eauLitres;
  final double temperature;
  final double humidite;
  final String observations;

  SuiviJournalier({
    this.id,
    required this.date,
    this.poidsMotenG = 0,
    this.mortaliteJour = 0,
    this.alimentationKg = 0,
    this.alimentationType = '',
    this.alimentationStockId,
    this.eauLitres = 0,
    this.temperature = 0,
    this.humidite = 0,
    this.observations = '',
  });

  factory SuiviJournalier.fromJson(Map<String, dynamic> json) {
    return SuiviJournalier(
      id: json['_id'],
      date: DateTime.parse(json['date']),
      poidsMotenG: (json['poidsMotenG'] ?? 0).toDouble(),
      mortaliteJour: json['mortaliteJour'] ?? 0,
      alimentationKg: (json['alimentationKg'] ?? 0).toDouble(),
      alimentationType: (json['alimentationType'] ?? '').toString(),
      alimentationStockId: json['alimentationStockId']?.toString(),
      eauLitres: (json['eauLitres'] ?? 0).toDouble(),
      temperature: (json['temperature'] ?? 0).toDouble(),
      humidite: (json['humidite'] ?? 0).toDouble(),
      observations: json['observations'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'poidsMotenG': poidsMotenG,
    'mortaliteJour': mortaliteJour,
    'alimentationKg': alimentationKg,
    'alimentationType': alimentationType,
    'alimentationStockId': alimentationStockId,
    'eauLitres': eauLitres,
    'temperature': temperature,
    'humidite': humidite,
    'observations': observations,
  };
}

class EvenementSante {
  final String? id;
  final DateTime date;
  final String type;
  final String description;
  final String medicament;
  final String doseParTete;
  final int dureeJours;
  final double cout;

  EvenementSante({
    this.id,
    required this.date,
    required this.type,
    required this.description,
    this.medicament = '',
    this.doseParTete = '',
    this.dureeJours = 1,
    this.cout = 0,
  });

  factory EvenementSante.fromJson(Map<String, dynamic> json) {
    return EvenementSante(
      id: json['_id'],
      date: DateTime.parse(json['date']),
      type: json['type'],
      description: json['description'],
      medicament: json['medicament'] ?? '',
      doseParTete: json['doseParTete'] ?? '',
      dureeJours: json['dureeJours'] ?? 1,
      cout: (json['cout'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'description': description,
    'medicament': medicament,
    'doseParTete': doseParTete,
    'dureeJours': dureeJours,
    'cout': cout,
  };
}

class EvenementPrevisionnel {
  final String? id;
  final String type;
  final DateTime datePrevue;
  final String description;
  final String priorite;
  final String commentaires;
  final String? prophylaxieStockId;
  final String prophylaxieType;
  final double prophylaxieQuantite;
  final String statut;
  final DateTime? dateRealisation;
  final String commentairesRealisation;

  EvenementPrevisionnel({
    this.id,
    required this.type,
    required this.datePrevue,
    required this.description,
    this.priorite = 'moyenne',
    this.commentaires = '',
    this.prophylaxieStockId,
    this.prophylaxieType = '',
    this.prophylaxieQuantite = 0,
    this.statut = 'planifie',
    this.dateRealisation,
    this.commentairesRealisation = '',
  });

  factory EvenementPrevisionnel.fromJson(Map<String, dynamic> json) {
    return EvenementPrevisionnel(
      id: json['_id'],
      type: (json['type'] ?? 'intervention_diverse').toString(),
      datePrevue: DateTime.parse(json['datePrevue']),
      description: (json['description'] ?? '').toString(),
      priorite: (json['priorite'] ?? 'moyenne').toString(),
      commentaires: (json['commentaires'] ?? '').toString(),
      prophylaxieStockId: json['prophylaxieStockId']?.toString(),
      prophylaxieType: (json['prophylaxieType'] ?? '').toString(),
      prophylaxieQuantite: (json['prophylaxieQuantite'] ?? 0).toDouble(),
      statut: (json['statut'] ?? 'planifie').toString(),
      dateRealisation: json['dateRealisation'] != null ? DateTime.parse(json['dateRealisation']) : null,
      commentairesRealisation: (json['commentairesRealisation'] ?? '').toString(),
    );
  }
}

class Bande {
  final String? id;
  final String nom;
  final DateTime dateOuverture;
  final DateTime? dateFermeture;
  final String statut;
  final String typeVolaille;
  final String race;
  final String fournisseurPoussins;
  final int nombreInitial;
  final int nombreActuel;
  final int mortaliteTotale;
  final double poidsArriveeG;
  final double objectifPoidsG;
  final int dureeElevageJours;
  final String batiment;
  final double coutPoussin;
  final List<SuiviJournalier> suiviJournalier;
  final List<EvenementSante> evenementsSante;
  final List<EvenementPrevisionnel> evenementsPrevisionnels;
  final String notes;
  final int? ageJours;
  final String? tauxMortalite;

  Bande({
    this.id,
    required this.nom,
    required this.dateOuverture,
    this.dateFermeture,
    this.statut = 'ouverte',
    required this.typeVolaille,
    required this.race,
    this.fournisseurPoussins = '',
    required this.nombreInitial,
    required this.nombreActuel,
    this.mortaliteTotale = 0,
    this.poidsArriveeG = 0,
    this.objectifPoidsG = 0,
    this.dureeElevageJours = 45,
    this.batiment = '',
    this.coutPoussin = 0,
    this.suiviJournalier = const [],
    this.evenementsSante = const [],
    this.evenementsPrevisionnels = const [],
    this.notes = '',
    this.ageJours,
    this.tauxMortalite,
  });

  factory Bande.fromJson(Map<String, dynamic> json) {
    return Bande(
      id: json['_id'],
      nom: json['nom'],
      dateOuverture: DateTime.parse(json['dateOuverture']),
      dateFermeture: json['dateFermeture'] != null ? DateTime.parse(json['dateFermeture']) : null,
      statut: json['statut'],
      typeVolaille: json['typeVolaille'] ?? 'poulet_chair',
      race: json['race'],
      fournisseurPoussins: json['fournisseurPoussins'] ?? '',
      nombreInitial: json['nombreInitial'],
      nombreActuel: json['nombreActuel'],
      mortaliteTotale: json['mortaliteTotale'] ?? 0,
      poidsArriveeG: (json['poidsArriveeG'] ?? 0).toDouble(),
      objectifPoidsG: (json['objectifPoidsG'] ?? 0).toDouble(),
      dureeElevageJours: json['dureeElevageJours'] ?? 45,
      batiment: json['batiment'] ?? '',
      coutPoussin: (json['coutPoussin'] ?? 0).toDouble(),
      suiviJournalier: json['suiviJournalier'] != null
          ? (json['suiviJournalier'] as List).map((s) => SuiviJournalier.fromJson(s)).toList()
          : [],
      evenementsSante: json['evenementsSante'] != null
          ? (json['evenementsSante'] as List).map((e) => EvenementSante.fromJson(e)).toList()
          : [],
        evenementsPrevisionnels: json['evenementsPrevisionnels'] != null
          ? (json['evenementsPrevisionnels'] as List).map((e) => EvenementPrevisionnel.fromJson(e)).toList()
          : [],
      notes: json['notes'] ?? '',
      ageJours: json['ageJours'],
      tauxMortalite: json['tauxMortalite']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'nom': nom,
    'typeVolaille': typeVolaille,
    'race': race,
    'fournisseurPoussins': fournisseurPoussins,
    'nombreInitial': nombreInitial,
    'poidsArriveeG': poidsArriveeG,
    'objectifPoidsG': objectifPoidsG,
    'dureeElevageJours': dureeElevageJours,
    'batiment': batiment,
    'coutPoussin': coutPoussin,
    'notes': notes,
  };
}
