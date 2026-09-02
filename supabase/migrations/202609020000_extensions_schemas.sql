-- FDS Phase 01. Extensions and the schema split.
create extension if not exists vector with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pgmq;
create extension if not exists pg_cron;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists platform;
create schema if not exists studio;
create schema if not exists production;
create schema if not exists publishing;
create schema if not exists intelligence;
create schema if not exists research;
create schema if not exists knowledge;
create schema if not exists system;
grant usage on schema platform,studio,production,publishing,intelligence,research,knowledge,system to authenticated, service_role;
