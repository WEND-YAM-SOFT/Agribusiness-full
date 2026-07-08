class Client {
  final String? id;
  final String nom;
  final String prenom;
  final String telephone;
  final String email;
  final String adresse;
  final String typeClient;
  final String commentaireActivite;
  final String entreprise;
  final String notes;
  final String statut;
  final DateTime? createdAt;
  final DateTime? dernierContactLe;
  final double chiffreAffairesCumul;

  Client({
    this.id,
    required this.nom,
    required this.prenom,
    required this.telephone,
    this.email = '',
    this.adresse = '',
    this.typeClient = 'particulier',
    this.commentaireActivite = '',
    this.entreprise = '',
    this.notes = '',
    this.statut = 'prospect',
    this.createdAt,
    this.dernierContactLe,
    this.chiffreAffairesCumul = 0,
  });

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['_id'],
      nom: json['nom'],
      prenom: json['prenom'],
      telephone: json['telephone'],
      email: json['email'] ?? '',
      adresse: json['adresse'] ?? '',
      typeClient: (json['typeClient'] ?? 'particulier').toString(),
      commentaireActivite: (json['commentaireActivite'] ?? '').toString(),
      entreprise: json['entreprise'] ?? '',
      notes: json['notes'] ?? '',
      statut: json['statut'] ?? 'prospect',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      dernierContactLe: json['dernierContactLe'] != null ? DateTime.parse(json['dernierContactLe']) : null,
      chiffreAffairesCumul: (json['chiffreAffairesCumul'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nom': nom,
      'prenom': prenom,
      'telephone': telephone,
      'email': email,
      'adresse': adresse,
      'typeClient': typeClient,
      'commentaireActivite': commentaireActivite,
      'entreprise': entreprise,
      'notes': notes,
      'statut': statut,
    };
  }

  String get nomComplet => '$prenom $nom';
}
