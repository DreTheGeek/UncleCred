-- New organs for Phase 01.
create table platform.universes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references platform.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  premise text,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, code)
);
alter table platform.universes enable row level security;

-- Immutable event ledger. Every meaningful thing becomes a row here. Never updated, never deleted.
create table system.system_events (
  id bigint generated always as identity primary key,
  organization_id uuid,
  event_type text not null,
  subject_table text,
  subject_id uuid,
  actor text not null default 'system',
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index system_events_type_time on system.system_events (event_type, occurred_at desc);
create index system_events_subject on system.system_events (subject_table, subject_id);
alter table system.system_events enable row level security;
create or replace function system.emit_event(p_org uuid, p_type text, p_table text, p_id uuid, p_payload jsonb default '{}'::jsonb, p_actor text default 'system')
returns bigint language sql security definer set search_path = system as $$
  insert into system.system_events (organization_id, event_type, subject_table, subject_id, payload, actor)
  values (p_org, p_type, p_table, p_id, coalesce(p_payload,'{}'::jsonb), p_actor) returning id;
$$;
revoke update, delete on system.system_events from authenticated, anon;

-- API keys per API-STANDARD. Key shown once, hash stored, never logged.
create table system.api_keys (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references platform.organizations(id) on delete cascade,
  name text not null,
  key_prefix text not null,
  key_hash text not null unique,
  scopes text[] not null default '{}',
  created_by uuid,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
create index api_keys_prefix on system.api_keys (key_prefix) where revoked_at is null;
alter table system.api_keys enable row level security;
create or replace function system.validate_api_key(p_raw text)
returns table (id uuid, organization_id uuid, scopes text[]) language plpgsql security definer set search_path = system, extensions as $$
declare h text := encode(extensions.digest(p_raw, 'sha256'), 'hex');
begin
  return query update system.api_keys k set last_used_at = now()
    where k.key_hash = h and k.revoked_at is null
    returning k.id, k.organization_id, k.scopes;
end $$;

-- AI cost ledger, one row per model call. Feeds cost per episode and ROI per character.
create table system.ai_cost_ledger (
  id bigint generated always as identity primary key,
  organization_id uuid,
  provider text not null,
  model text not null,
  purpose text not null,
  episode_id uuid,
  character_code text,
  input_tokens integer,
  output_tokens integer,
  units numeric,
  unit_kind text,
  cost_usd numeric(12,6) not null default 0,
  trace_id text,
  created_at timestamptz not null default now()
);
create index ai_cost_episode on system.ai_cost_ledger (episode_id);
alter table system.ai_cost_ledger enable row level security;

-- Model registry for the GenerationRouter (Phase 02 seeds it).
create table system.ai_models (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_model_id text not null,
  capability text not null,
  model_family text,
  version text,
  supports jsonb not null default '{}'::jsonb,
  limits jsonb not null default '{}'::jsonb,
  cost_unit text,
  estimated_cost numeric(12,6),
  scores jsonb not null default '{}'::jsonb,
  status text not null default 'candidate',
  enabled boolean not null default false,
  last_tested_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, provider_model_id, capability)
);
alter table system.ai_models enable row level security;
