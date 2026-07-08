class Alerte {
  final String? id;
  final String titre;
  final String message;
  final String type;
  final DateTime dateEcheance;
  final String? bandeId;
  final String statut;
  final String recurrence;
  final String priorite;
  final String source;
  final bool automatique;

  Alerte({
    this.id,
    required this.titre,
    required this.message,
    required this.type,
    required this.dateEcheance,
    this.bandeId,
    this.statut = 'active',
    this.recurrence = 'aucune',
    this.priorite = 'moyenne',
    this.source = '',
    this.automatique = false,
  });

  factory Alerte.fromJson(Map<String, dynamic> json) {
    return Alerte(
      id: (json['_id'] ?? json['id'])?.toString(),
      titre: json['titre'],
      message: json['message'],
      type: json['type'],
      dateEcheance: DateTime.parse(json['dateEcheance']),
      bandeId: json['bandeId'] is String ? json['bandeId'] : json['bandeId']?['_id'],
      statut: json['statut'] ?? 'active',
      recurrence: json['recurrence'] ?? 'aucune',
      priorite: json['priorite'] ?? 'moyenne',
      source: json['source'] ?? '',
      automatique: json['automatique'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'titre': titre,
    'message': message,
    'type': type,
    'dateEcheance': dateEcheance.toIso8601String(),
    'bandeId': bandeId,
    'recurrence': recurrence,
    'priorite': priorite,
    'source': source,
    'automatique': automatique,
  };
}
