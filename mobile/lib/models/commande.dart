class Produit {
  final String nom;
  final int quantite;
  final double prixUnitaire;

  Produit({
    required this.nom,
    required this.quantite,
    required this.prixUnitaire,
  });

  factory Produit.fromJson(Map<String, dynamic> json) {
    return Produit(
      nom: json['nom'],
      quantite: json['quantite'],
      prixUnitaire: (json['prixUnitaire']).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nom': nom,
      'quantite': quantite,
      'prixUnitaire': prixUnitaire,
    };
  }
}

class LivraisonCommande {
  final String? id;
  final DateTime dateLivraisonPrevue;
  final DateTime? dateLivraisonReelle;
  final String statutLivraison;
  final double fraisLivraison;
  final String commentaires;

  LivraisonCommande({
    this.id,
    required this.dateLivraisonPrevue,
    this.dateLivraisonReelle,
    this.statutLivraison = 'planifiee',
    this.fraisLivraison = 0,
    this.commentaires = '',
  });

  factory LivraisonCommande.fromJson(Map<String, dynamic> json) {
    return LivraisonCommande(
      id: json['_id'],
      dateLivraisonPrevue: DateTime.parse(json['dateLivraisonPrevue']),
      dateLivraisonReelle: json['dateLivraisonReelle'] != null
          ? DateTime.parse(json['dateLivraisonReelle'])
          : null,
      statutLivraison: json['statutLivraison'] ?? 'planifiee',
      fraisLivraison: (json['fraisLivraison'] ?? 0).toDouble(),
      commentaires: json['commentaires'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dateLivraisonPrevue': dateLivraisonPrevue.toIso8601String(),
      'dateLivraisonReelle': dateLivraisonReelle?.toIso8601String(),
      'statutLivraison': statutLivraison,
      'fraisLivraison': fraisLivraison,
      'commentaires': commentaires,
    };
  }
}

class Commande {
  final String? id;
  final String clientId;
  final String clientNom;
  final String? bandeId;
  final String bandeNom;
  final List<Produit> produits;
  final double montantTotal;
  final String statut;
  final DateTime? dateLivraison;
  final String notes;
  final DateTime? createdAt;
  final List<LivraisonCommande> livraisons;

  Commande({
    this.id,
    required this.clientId,
    this.clientNom = '',
    this.bandeId,
    this.bandeNom = '',
    required this.produits,
    required this.montantTotal,
    this.statut = 'en_attente',
    this.dateLivraison,
    this.notes = '',
    this.createdAt,
    this.livraisons = const [],
  });

  factory Commande.fromJson(Map<String, dynamic> json) {
    final dynamic clientRaw = json['client'];
    final String clientId = clientRaw is String
        ? clientRaw
        : (clientRaw is Map<String, dynamic>
            ? (clientRaw['_id']?.toString() ?? '')
            : '');
    final String clientNom = clientRaw is Map<String, dynamic>
        ? '${clientRaw['prenom'] ?? ''} ${clientRaw['nom'] ?? ''}'.trim()
        : '';

    final dynamic bandeRaw = json['bande'];
    final String? bandeId = bandeRaw is String
        ? bandeRaw
        : (bandeRaw is Map<String, dynamic> ? bandeRaw['_id']?.toString() : null);
    final String bandeNom = bandeRaw is Map<String, dynamic>
        ? (bandeRaw['nom']?.toString() ?? '')
        : '';

    final List<dynamic> produitsRaw = (json['produits'] as List<dynamic>?) ?? const [];

    return Commande(
      id: json['_id'],
      clientId: clientId,
      clientNom: clientNom,
      bandeId: bandeId,
      bandeNom: bandeNom,
      produits: produitsRaw
          .whereType<Map<String, dynamic>>()
          .map((p) => Produit.fromJson(p))
          .toList(),
      montantTotal: (json['montantTotal']).toDouble(),
      statut: json['statut'],
      dateLivraison: json['dateLivraison'] != null
          ? DateTime.parse(json['dateLivraison'])
          : null,
      notes: json['notes'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
        livraisons: (json['livraisons'] as List<dynamic>? ?? const [])
          .map((l) => LivraisonCommande.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      'bandeId': bandeId,
      'produits': produits.map((p) => p.toJson()).toList(),
      'montantTotal': montantTotal,
      'dateLivraison': dateLivraison?.toIso8601String(),
      'notes': notes,
    };
  }
}
