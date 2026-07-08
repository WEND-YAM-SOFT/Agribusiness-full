class TacheCRM {
  final String? id;
  final String clientId;
  final String? commandeId;
  final String titre;
  final String description;
  final String type;
  final DateTime dateEcheance;
  final String statut;
  final String priorite;
  final bool rappelActive;
  final String assigneA;
  final String clientNom;

  TacheCRM({
    this.id,
    required this.clientId,
    this.commandeId,
    required this.titre,
    this.description = '',
    this.type = 'suivi',
    required this.dateEcheance,
    this.statut = 'a_faire',
    this.priorite = 'moyenne',
    this.rappelActive = true,
    this.assigneA = '',
    this.clientNom = '',
  });

  factory TacheCRM.fromJson(Map<String, dynamic> json) {
    return TacheCRM(
      id: json['_id'],
      clientId: json['clientId'] is String ? json['clientId'] : json['clientId']?['_id'] ?? '',
      commandeId: json['commandeId'] is String ? json['commandeId'] : json['commandeId']?['_id'],
      titre: json['titre'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? 'suivi',
      dateEcheance: json['dateEcheance'] != null ? DateTime.parse(json['dateEcheance']) : DateTime.now(),
      statut: json['statut'] ?? 'a_faire',
      priorite: json['priorite'] ?? 'moyenne',
      rappelActive: json['rappelActive'] ?? true,
      assigneA: json['assigneA'] ?? '',
      clientNom: json['clientId'] is Map
          ? '${json['clientId']?['prenom'] ?? ''} ${json['clientId']?['nom'] ?? ''}'.trim()
          : '',
    );
  }

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'commandeId': commandeId,
    'titre': titre,
    'description': description,
    'type': type,
    'dateEcheance': dateEcheance.toIso8601String(),
    'statut': statut,
    'priorite': priorite,
    'rappelActive': rappelActive,
    'assigneA': assigneA,
  };
}
