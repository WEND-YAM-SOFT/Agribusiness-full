class MouvementStock {
  final String? id;
  final DateTime date;
  final String type;
  final double quantite;
  final String utilisateur;
  final String motif;
  final double coutUnitaire;

  MouvementStock({
    this.id,
    required this.date,
    required this.type,
    required this.quantite,
    this.utilisateur = '',
    this.motif = '',
    this.coutUnitaire = 0,
  });

  factory MouvementStock.fromJson(Map<String, dynamic> json) {
    return MouvementStock(
      id: json['_id']?.toString(),
      date: DateTime.parse(json['date']),
      type: json['type'] ?? '',
      quantite: (json['quantite'] ?? 0).toDouble(),
      utilisateur: json['utilisateur'] ?? '',
      motif: json['motif'] ?? '',
      coutUnitaire: (json['coutUnitaire'] ?? 0).toDouble(),
    );
  }
}

class Stock {
  final String? id;
  final String nom;
  final String categorie;
  final String unite;
  final double quantiteActuelle;
  final double seuilAlerte;
  final double prixUnitaire;
  final String fournisseur;
  final String emplacement;
  final DateTime? dateExpiration;
  final DateTime? dateCreationStock;
  final bool? enAlerte;
  final String notes;
  final List<MouvementStock> mouvements;

  Stock({
    this.id,
    required this.nom,
    required this.categorie,
    required this.unite,
    this.quantiteActuelle = 0,
    this.seuilAlerte = 0,
    this.prixUnitaire = 0,
    this.fournisseur = '',
    this.emplacement = '',
    this.dateExpiration,
    this.dateCreationStock,
    this.enAlerte,
    this.notes = '',
    this.mouvements = const [],
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      id: json['_id'],
      nom: json['nom'],
      categorie: json['categorie'],
      unite: json['unite'],
      quantiteActuelle: (json['quantiteActuelle'] ?? 0).toDouble(),
      seuilAlerte: (json['seuilAlerte'] ?? 0).toDouble(),
      prixUnitaire: (json['prixUnitaire'] ?? 0).toDouble(),
      fournisseur: json['fournisseur'] ?? '',
      emplacement: json['emplacement'] ?? '',
      dateExpiration: json['dateExpiration'] != null ? DateTime.parse(json['dateExpiration']) : null,
      dateCreationStock: json['dateCreationStock'] != null ? DateTime.parse(json['dateCreationStock']) : null,
      enAlerte: json['enAlerte'],
      notes: json['notes'] ?? '',
      mouvements: (json['mouvements'] as List<dynamic>? ?? const [])
          .map((m) => MouvementStock.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'nom': nom,
    'categorie': categorie,
    'unite': unite,
    'quantiteActuelle': quantiteActuelle,
    'seuilAlerte': seuilAlerte,
    'prixUnitaire': prixUnitaire,
    'fournisseur': fournisseur,
    'emplacement': emplacement,
    'dateExpiration': dateExpiration?.toIso8601String(),
    'notes': notes,
  };
}
