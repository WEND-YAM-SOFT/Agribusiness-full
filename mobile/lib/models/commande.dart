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
    final rawQte = json['quantite'] ?? json['qte'] ?? 0;
    final rawPrix = json['prixUnitaire'] ?? json['prix_unitaire'] ?? json['prix'] ?? 0;
    return Produit(
      nom: (json['nom'] ?? json['designation'] ?? '').toString(),
      quantite: rawQte is num ? rawQte.toInt() : int.tryParse(rawQte.toString()) ?? 0,
      prixUnitaire: rawPrix is num ? rawPrix.toDouble() : double.tryParse(rawPrix.toString()) ?? 0,
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
    final rawFrais = json['fraisLivraison'] ?? json['frais_livraison'] ?? 0;
    return LivraisonCommande(
      id: (json['_id'] ?? json['id'])?.toString(),
      dateLivraisonPrevue: DateTime.tryParse((json['dateLivraisonPrevue'] ?? json['date_livraison_prevue'] ?? DateTime.now().toIso8601String()).toString()) ?? DateTime.now(),
      dateLivraisonReelle: json['dateLivraisonReelle'] != null
          ? DateTime.tryParse(json['dateLivraisonReelle'].toString())
          : (json['date_livraison_reelle'] != null
              ? DateTime.tryParse(json['date_livraison_reelle'].toString())
              : null),
      statutLivraison: (json['statutLivraison'] ?? json['statut_livraison'] ?? 'planifiee').toString(),
      fraisLivraison: rawFrais is num ? rawFrais.toDouble() : double.tryParse(rawFrais.toString()) ?? 0,
      commentaires: (json['commentaires'] ?? json['commentaire'] ?? '').toString(),
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
            ? (clientRaw['_id']?.toString() ?? clientRaw['id']?.toString() ?? '')
            : (json['clientId']?.toString() ?? json['client_id']?.toString() ?? ''));
    final String clientNom = clientRaw is Map<String, dynamic>
        ? '${clientRaw['prenom'] ?? ''} ${clientRaw['nom'] ?? ''}'.trim()
        : (json['clientNom'] ?? json['client_nom'] ?? '').toString();

    final dynamic bandeRaw = json['bande'];
    final String? bandeId = bandeRaw is String
        ? bandeRaw
        : (bandeRaw is Map<String, dynamic>
            ? bandeRaw['_id']?.toString()
            : (json['bandeId'] ?? json['bande_id'])?.toString());
    final String bandeNom = bandeRaw is Map<String, dynamic>
        ? (bandeRaw['nom']?.toString() ?? '')
        : (json['bandeNom'] ?? json['bande_nom'] ?? '').toString();

    final List<dynamic> produitsRaw = (json['produits'] as List<dynamic>?) ?? const [];
    final rawMontant = json['montantTotal'] ?? json['montant_total'] ?? 0;

    return Commande(
      id: (json['_id'] ?? json['id'])?.toString(),
      clientId: clientId,
      clientNom: clientNom,
      bandeId: bandeId,
      bandeNom: bandeNom,
      produits: produitsRaw
          .whereType<Map<String, dynamic>>()
          .map((p) => Produit.fromJson(p))
          .toList(),
      montantTotal: rawMontant is num ? rawMontant.toDouble() : double.tryParse(rawMontant.toString()) ?? 0,
      statut: (json['statut'] ?? json['status'] ?? 'en_attente').toString(),
      dateLivraison: json['dateLivraison'] != null
          ? DateTime.tryParse(json['dateLivraison'].toString())
          : (json['date_livraison'] != null ? DateTime.tryParse(json['date_livraison'].toString()) : null),
      notes: (json['notes'] ?? '').toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null),
      livraisons: (json['livraisons'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LivraisonCommande.fromJson)
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
