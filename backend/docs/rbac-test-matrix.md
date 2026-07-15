# RBAC Test Matrix

This matrix validates role-based access for major API endpoints.
Expected status: 200/201 for allowed, 403 for forbidden.

## Roles
- admin
- gestionnaire_ferme
- commercial
- technicien

## Clients
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/clients | clients.read | Allow | Allow | Allow | Allow |
| POST /api/clients | clients.create | Allow | Allow | Allow | Deny |
| PUT /api/clients/:id | clients.update | Allow | Allow | Allow | Deny |
| DELETE /api/clients/:id | clients.delete | Allow | Deny | Deny | Deny |

## Commandes
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/commandes | commandes.read | Allow | Allow | Allow | Allow |
| POST /api/commandes | commandes.create | Allow | Allow | Allow | Deny |
| PUT /api/commandes/:id | commandes.update | Allow | Allow | Allow | Deny |
| PUT /api/commandes/:id/statut (confirmee/en_preparation) | commandes.status.prepare | Allow | Allow | Allow | Deny |
| PUT /api/commandes/:id/statut (payee) | commandes.status.pay | Allow | Allow | Deny | Deny |
| PUT /api/commandes/:id/statut (annulee) | commandes.status.cancel | Allow | Allow | Deny | Deny |
| DELETE /api/commandes/historique/all | commandes.historique.purge | Allow | Deny | Deny | Deny |

## Bandes
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/bandes/actives | bandes.read | Allow | Allow | Allow | Allow |
| POST /api/bandes | bandes.create | Allow | Allow | Deny | Deny |
| PUT /api/bandes/:id/fermer | bandes.close | Allow | Allow | Deny | Deny |
| POST /api/bandes/:id/suivi | bandes.suivi.create | Allow | Allow | Deny | Allow |
| POST /api/bandes/:id/mortalite | bandes.mortalite.create | Allow | Allow | Deny | Allow |
| POST /api/bandes/:id/poids | bandes.poids.create | Allow | Allow | Deny | Allow |

## Stocks
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/stocks | stocks.read | Allow | Allow | Deny | Allow |
| POST /api/stocks | stocks.create | Allow | Allow | Deny | Deny |
| POST /api/stocks/:id/mouvement | stocks.mouvement.create | Allow | Allow | Deny | Allow |
| DELETE /api/stocks/:id/mouvements/:mouvementId | stocks.mouvement.delete | Allow | Allow | Deny | Deny |

## Finance
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/finance/mouvements | finance.read | Allow | Allow | Allow | Deny |
| POST /api/finance/depenses | finance.write | Allow | Allow | Deny | Deny |
| DELETE /api/finance/mouvements | finance.delete | Allow | Allow | Deny | Deny |

## CRM
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/crm/dashboard | crm.read | Allow | Allow | Allow | Allow |
| POST /api/crm/clients/:clientId/interactions | crm.interaction.create | Allow | Allow | Allow | Deny |
| GET /api/crm/taches | crm.tache.read | Allow | Allow | Allow | Allow |
| POST /api/crm/taches | crm.tache.create | Allow | Allow | Allow | Deny |
| PUT /api/crm/taches/:id | crm.tache.update | Allow | Allow | Allow | Deny |
| DELETE /api/crm/taches/:id | crm.tache.delete | Allow | Allow | Deny | Deny |
| DELETE /api/crm/taches/historique/all | crm.historique.purge | Allow | Allow | Deny | Deny |

## Alertes
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/alertes/actives | alertes.read | Allow | Allow | Allow | Allow |
| POST /api/alertes | alertes.create | Allow | Allow | Allow | Deny |
| PUT /api/alertes/:id | alertes.update | Allow | Allow | Allow | Deny |
| PUT /api/alertes/:id/fait | alertes.mark_done | Allow | Allow | Allow | Allow |
| DELETE /api/alertes/:id | alertes.delete | Allow | Allow | Deny | Deny |
| DELETE /api/alertes/historique/all | alertes.historique.purge | Allow | Allow | Deny | Deny |

## Dashboard and Reports
| Endpoint | Permission | admin | gestionnaire_ferme | commercial | technicien |
|---|---|---|---|---|---|
| GET /api/dashboard/global | dashboard.sales or dashboard.tech or dashboard.full | Allow | Allow | Allow | Allow |
| GET /api/reports/global.pdf | reports.sales or reports.tech or reports.full | Allow | Allow | Allow | Allow |

## Migration Commands
- Preview: npm run roles:migrate:preview
- Apply: npm run roles:migrate
- Apply with fallback: node scripts/migrate_roles_permissions.js --fallback-role commercial
- Apply without auth metadata sync: node scripts/migrate_roles_permissions.js --no-sync-auth-metadata
