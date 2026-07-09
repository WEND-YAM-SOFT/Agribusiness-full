-- Starter schema for a mono-company phase that can evolve to SaaS multi-company.
-- Run in Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.entreprises (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.entreprises(id) on delete restrict,
  role text not null default 'owner' check (role in ('owner', 'admin', 'agent', 'viewer')),
  full_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  prenom text default '',
  nom text not null,
  telephone text default '',
  email text default '',
  adresse text not null default '',
  type_client text not null default 'particulier',
  commentaire_activite text not null default '',
  entreprise text not null default '',
  notes text not null default '',
  statut text not null default 'prospect',
  dernier_contact_le timestamptz,
  chiffre_affaires_cumul numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.commandes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  client_id uuid references public.clients(id) on delete set null,
  bande_id uuid,
  produits jsonb not null default '[]'::jsonb,
  statut text not null default 'en_attente',
  montant_total numeric(14,2) not null default 0,
  date_livraison timestamptz,
  notes text not null default '',
  commentaires jsonb not null default '[]'::jsonb,
  historique_actions jsonb not null default '[]'::jsonb,
  livraisons jsonb not null default '[]'::jsonb,
  vente_comptabilisee boolean not null default false,
  dernier_mouvement_tresorerie_id text,
  client_snapshot jsonb,
  bande_snapshot jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stocks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  nom text not null,
  categorie text not null,
  unite text not null default 'kg',
  quantite_actuelle numeric(14,3) not null default 0,
  seuil_alerte numeric(14,3) not null default 0,
  prix_unitaire numeric(14,2) not null default 0,
  fournisseur text not null default '',
  emplacement text not null default '',
  date_expiration timestamptz,
  date_creation_stock timestamptz,
  notes text not null default '',
  mouvements jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tresorerie_mouvements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  nature text not null check (nature in ('entree', 'sortie')),
  source text not null,
  qui_nom text not null default '',
  qui_prenom text not null default '',
  categorie text not null default '',
  type text not null default '',
  montant numeric(14,2) not null check (montant >= 0),
  date_mouvement timestamptz not null default now(),
  reference_type text,
  reference_id text,
  externe_cle text,
  commentaire text,
  created_at timestamptz not null default now()
);

create table if not exists public.app_config (
  key text primary key,
  nomApplication text not null default 'AgriBusiness',
  devise text not null default 'FCFA',
  langue text not null default 'fr',
  sessionTimeoutMinutes int not null default 30,
  theme text not null default 'light',
  notificationsEmail boolean not null default false,
  referencesTheoriques jsonb not null default '{}'::jsonb,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  user_email text not null default '',
  action text not null,
  target_type text not null default '',
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  ip text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.password_reset_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  token_hash text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.bandes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  nom text not null,
  date_ouverture timestamptz not null default now(),
  date_fermeture timestamptz,
  statut text not null default 'ouverte',
  type_volaille text not null default 'poulet_chair',
  race text not null default '',
  fournisseur_poussins text not null default '',
  nombre_initial int not null default 0,
  nombre_actuel int not null default 0,
  mortalite_totale int not null default 0,
  poids_arrivee_g numeric(10,2) not null default 0,
  objectif_poids_g numeric(10,2) not null default 0,
  duree_elevage_jours int not null default 45,
  batiment text not null default '',
  cout_poussin numeric(14,2) not null default 0,
  suivi_journalier jsonb not null default '[]'::jsonb,
  evenements_sante jsonb not null default '[]'::jsonb,
  evenements_previsionnels jsonb not null default '[]'::jsonb,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.alertes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  titre text not null,
  message text not null,
  type text not null default 'autre',
  date_echeance timestamptz not null,
  bande_id uuid references public.bandes(id) on delete set null,
  statut text not null default 'active',
  recurrence text not null default 'aucune',
  priorite text not null default 'moyenne',
  source text not null default 'todo',
  automatique boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_interactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  client_id uuid references public.clients(id) on delete cascade,
  commande_id uuid references public.commandes(id) on delete set null,
  type text not null default 'commentaire',
  sujet text not null default '',
  contenu text not null default '',
  auteur text not null default 'Utilisateur',
  date_interaction timestamptz not null default now(),
  pieces_jointes jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_taches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  client_id uuid references public.clients(id) on delete set null,
  commande_id uuid references public.commandes(id) on delete set null,
  titre text not null,
  description text not null default '',
  type text not null default 'suivi',
  date_echeance timestamptz not null,
  statut text not null default 'a_faire',
  priorite text not null default 'moyenne',
  rappel_active boolean not null default true,
  assigne_a text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_company_id on public.profiles(company_id);
create index if not exists idx_clients_company_id on public.clients(company_id);
create index if not exists idx_commandes_company_id on public.commandes(company_id);
create index if not exists idx_stocks_company_id on public.stocks(company_id);
create index if not exists idx_tresorerie_company_id on public.tresorerie_mouvements(company_id);
create index if not exists idx_audit_logs_created_at on public.audit_logs(created_at desc);
create index if not exists idx_prt_token_hash on public.password_reset_tokens(token_hash);
create index if not exists idx_prt_user_id on public.password_reset_tokens(user_id);
create index if not exists idx_bandes_company_id on public.bandes(company_id);
create index if not exists idx_alertes_company_id on public.alertes(company_id);
create index if not exists idx_alertes_date_echeance on public.alertes(date_echeance);
create index if not exists idx_crm_interactions_company_id on public.crm_interactions(company_id);
create index if not exists idx_crm_taches_company_id on public.crm_taches(company_id);
create index if not exists idx_crm_taches_date_echeance on public.crm_taches(date_echeance);

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.commandes enable row level security;
alter table public.stocks enable row level security;
alter table public.tresorerie_mouvements enable row level security;
alter table public.bandes enable row level security;
alter table public.alertes enable row level security;
alter table public.crm_interactions enable row level security;
alter table public.crm_taches enable row level security;

-- Users can only access rows from their own company.
drop policy if exists profiles_select_own_company on public.profiles;
drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_select_self on public.profiles
for select using (
  id = auth.uid()
);
create policy profiles_update_self on public.profiles
for update using (
  id = auth.uid()
) with check (
  id = auth.uid()
);

drop policy if exists clients_all_own_company on public.clients;
create policy clients_all_own_company on public.clients
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists commandes_all_own_company on public.commandes;
create policy commandes_all_own_company on public.commandes
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists stocks_all_own_company on public.stocks;
create policy stocks_all_own_company on public.stocks
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists tresorerie_all_own_company on public.tresorerie_mouvements;
create policy tresorerie_all_own_company on public.tresorerie_mouvements
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists bandes_all_own_company on public.bandes;
create policy bandes_all_own_company on public.bandes
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists alertes_all_own_company on public.alertes;
create policy alertes_all_own_company on public.alertes
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists crm_interactions_all_own_company on public.crm_interactions;
create policy crm_interactions_all_own_company on public.crm_interactions
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists crm_taches_all_own_company on public.crm_taches;
create policy crm_taches_all_own_company on public.crm_taches
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);
