class PieceJointe {
  final String nomFichier;
  final String typeMime;
  final String url;
  final double tailleOctets;

  PieceJointe({
    required this.nomFichier,
    this.typeMime = '',
    this.url = '',
    this.tailleOctets = 0,
  });

  factory PieceJointe.fromJson(Map<String, dynamic> json) {
    return PieceJointe(
      nomFichier: json['nomFichier'] ?? '',
      typeMime: json['typeMime'] ?? '',
      url: json['url'] ?? '',
      tailleOctets: (json['tailleOctets'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'nomFichier': nomFichier,
    'typeMime': typeMime,
    'url': url,
    'tailleOctets': tailleOctets,
  };
}

class Interaction {
  final String? id;
  final String clientId;
  final String? commandeId;
  final String type;
  final String sujet;
  final String contenu;
  final String auteur;
  final DateTime dateInteraction;
  final List<PieceJointe> piecesJointes;

  Interaction({
    this.id,
    required this.clientId,
    this.commandeId,
    required this.type,
    this.sujet = '',
    required this.contenu,
    this.auteur = 'Utilisateur',
    required this.dateInteraction,
    this.piecesJointes = const [],
  });

  factory Interaction.fromJson(Map<String, dynamic> json) {
    return Interaction(
      id: json['_id'],
      clientId: json['clientId'] is String ? json['clientId'] : json['clientId']?['_id'] ?? '',
      commandeId: json['commandeId'] is String ? json['commandeId'] : json['commandeId']?['_id'],
      type: json['type'] ?? 'commentaire',
      sujet: json['sujet'] ?? '',
      contenu: json['contenu'] ?? '',
      auteur: json['auteur'] ?? 'Utilisateur',
      dateInteraction: json['dateInteraction'] != null ? DateTime.parse(json['dateInteraction']) : DateTime.now(),
      piecesJointes: json['piecesJointes'] != null
          ? (json['piecesJointes'] as List).map((p) => PieceJointe.fromJson(p)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'commandeId': commandeId,
    'type': type,
    'sujet': sujet,
    'contenu': contenu,
    'auteur': auteur,
    'dateInteraction': dateInteraction.toIso8601String(),
    'piecesJointes': piecesJointes.map((p) => p.toJson()).toList(),
  };
}
