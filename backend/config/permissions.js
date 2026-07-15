const KNOWN_ROLES = new Set([
  'admin',
  'gestionnaire_ferme',
  'commercial',
  'technicien',
  'utilisateur',
]);

const ROLE_ALIASES = {
  administrateur: 'admin',
  owner: 'admin',
  manager: 'gestionnaire_ferme',
  gestionnaire: 'gestionnaire_ferme',
  'gestionnaire de ferme': 'gestionnaire_ferme',
  vendeur: 'commercial',
  sales: 'commercial',
  technique: 'technicien',
  technician: 'technicien',
  agent: 'utilisateur',
  viewer: 'technicien',
};

const DEFAULT_ROLE_PERMISSIONS = {
  admin: ['*'],
  gestionnaire_ferme: [
    'clients.read', 'clients.create', 'clients.update', 'clients.delete',
    'commandes.read', 'commandes.create', 'commandes.update', 'commandes.delete',
    'commandes.comment', 'commandes.historique.read',
    'commandes.livraison.create', 'commandes.livraison.update',
    'commandes.status.prepare', 'commandes.status.pay', 'commandes.status.cancel',
    'bandes.read', 'bandes.create', 'bandes.update', 'bandes.close',
    'bandes.suivi.create', 'bandes.mortalite.create', 'bandes.poids.create',
    'bandes.climat.create', 'bandes.sante.create', 'bandes.events.manage',
    'stocks.read', 'stocks.create', 'stocks.update', 'stocks.delete',
    'stocks.mouvement.create', 'stocks.mouvement.delete',
    'achats.request', 'achats.validate',
    'finance.read', 'finance.write', 'finance.delete',
    'crm.read', 'crm.interaction.create',
    'crm.tache.read', 'crm.tache.create', 'crm.tache.update', 'crm.tache.delete', 'crm.historique.purge',
    'alertes.read', 'alertes.create', 'alertes.update', 'alertes.mark_done', 'alertes.delete', 'alertes.historique.purge',
    'reports.full',
    'dashboard.full',
  ],
  commercial: [
    'clients.read', 'clients.create', 'clients.update',
    'commandes.read', 'commandes.create', 'commandes.update',
    'commandes.comment', 'commandes.historique.read',
    'commandes.livraison.create', 'commandes.livraison.update',
    'commandes.status.prepare',
    'bandes.read',
    'finance.read',
    'crm.read', 'crm.interaction.create',
    'crm.tache.read', 'crm.tache.create', 'crm.tache.update',
    'alertes.read', 'alertes.create', 'alertes.update', 'alertes.mark_done',
    'reports.sales',
    'dashboard.sales',
    'achats.request',
  ],
  technicien: [
    'clients.read',
    'commandes.read',
    'bandes.read', 'bandes.suivi.create', 'bandes.mortalite.create',
    'bandes.poids.create', 'bandes.climat.create', 'bandes.sante.create',
    'stocks.read', 'stocks.mouvement.create',
    'crm.read', 'crm.tache.read',
    'alertes.read', 'alertes.mark_done',
    'reports.tech',
    'dashboard.tech',
    'achats.request',
  ],
  utilisateur: [],
};

function normalizeRole(value) {
  const input = (value || '').toString().trim().toLowerCase();
  const mapped = ROLE_ALIASES[input] || input;
  if (KNOWN_ROLES.has(mapped)) return mapped;
  return 'utilisateur';
}

function isAdminRole(role) {
  return normalizeRole(role) === 'admin';
}

function getRolePermissions(role) {
  const normalizedRole = normalizeRole(role);
  return DEFAULT_ROLE_PERMISSIONS[normalizedRole] || [];
}

module.exports = {
  DEFAULT_ROLE_PERMISSIONS,
  normalizeRole,
  isAdminRole,
  getRolePermissions,
};
