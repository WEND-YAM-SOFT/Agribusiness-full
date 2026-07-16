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
    String pick(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
      return '';
    }

    return Client(
      id: pick(['_id', 'id']),
      nom: pick(['nom']),
      prenom: pick(['prenom']),
      telephone: pick(['telephone']),
      email: pick(['email']),
      adresse: pick([
        'adresse',
        'address',
        'adresse_complete',
        'adresseComplete',
        'adresse_client',
        'adresseClient',
        'address_client',
        'addressClient',
        'adresse_postale',
        'adressePostale',
        'localisation',
      ]),
      typeClient: pick(['typeClient', 'type_client']).isEmpty ? 'particulier' : pick(['typeClient', 'type_client']),
      commentaireActivite: pick([
        'commentaireActivite',
        'commentaire_activite',
        'commentaire',
        'comment',
        'activite_entreprise',
        'activiteEntreprise',
        'activite',
        'activite_client',
        'activiteClient',
        'activity',
        'activite_principale',
        'activitePrincipale',
        'secteur_activite',
        'secteurActivite',
        'categorie_activite',
        'categorieActivite',
        'activity_comment',
        'company_activity',
        'notes',
      ]),
      entreprise: pick(['entreprise', 'company', 'societe', 'societe_nom']),
      notes: pick(['notes']),
      statut: pick(['statut', 'status']).isEmpty ? 'prospect' : pick(['statut', 'status']),
      createdAt: pick(['createdAt', 'created_at']).isNotEmpty ? DateTime.parse(pick(['createdAt', 'created_at'])) : null,
      dernierContactLe: pick(['dernierContactLe', 'dernier_contact_le']).isNotEmpty
          ? DateTime.parse(pick(['dernierContactLe', 'dernier_contact_le']))
          : null,
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
