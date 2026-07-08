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
  prenom text,
  nom text not null,
  telephone text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.commandes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  client_id uuid references public.clients(id) on delete set null,
  statut text not null default 'en_attente',
  montant_total numeric(14,2) not null default 0,
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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tresorerie_mouvements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.entreprises(id) on delete restrict,
  nature text not null check (nature in ('entree', 'sortie')),
  source text not null,
  montant numeric(14,2) not null check (montant >= 0),
  date_mouvement timestamptz not null default now(),
  commentaire text,
  created_at timestamptz not null default now()
);

create index if not exists idx_profiles_company_id on public.profiles(company_id);
create index if not exists idx_clients_company_id on public.clients(company_id);
create index if not exists idx_commandes_company_id on public.commandes(company_id);
create index if not exists idx_stocks_company_id on public.stocks(company_id);
create index if not exists idx_tresorerie_company_id on public.tresorerie_mouvements(company_id);

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.commandes enable row level security;
alter table public.stocks enable row level security;
alter table public.tresorerie_mouvements enable row level security;

-- Users can only access rows from their own company.
create policy if not exists profiles_select_own_company on public.profiles
for select using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

create policy if not exists clients_all_own_company on public.clients
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

create policy if not exists commandes_all_own_company on public.commandes
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

create policy if not exists stocks_all_own_company on public.stocks
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

create policy if not exists tresorerie_all_own_company on public.tresorerie_mouvements
for all using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
) with check (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);
