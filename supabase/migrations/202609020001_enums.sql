create type platform.confidentiality_level as enum ('public', 'internal', 'confidential', 'restricted');
create type platform.record_status as enum ('active', 'inactive', 'archived');
create type platform.work_status as enum ('idea', 'research', 'ready', 'scheduled', 'in_progress', 'blocked', 'review', 'approved', 'completed', 'published', 'archived', 'killed');
create type knowledge.claim_status as enum ('active', 'superseded', 'disputed', 'expired');
create type knowledge.memory_authority as enum ('authoritative_fact', 'decision', 'preference', 'observation', 'assumption', 'temporary_context');
create type knowledge.source_authority as enum ('canonical', 'verified', 'working', 'historical', 'external', 'unverified');
