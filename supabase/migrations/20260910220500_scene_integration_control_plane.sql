-- Shared external-integration control plane for Scene REST and MCP.
-- Reuses system.api_keys. Adds idempotency and request audit records once for all Scene transports.

CREATE TABLE IF NOT EXISTS system.external_idempotency_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  principal_kind text NOT NULL CHECK (principal_kind IN ('api_key','user')),
  principal_id text NOT NULL,
  operation text NOT NULL,
  idempotency_key text NOT NULL,
  request_hash text NOT NULL,
  status text NOT NULL DEFAULT 'started' CHECK (status IN ('started','completed','failed')),
  response_status integer,
  response_body jsonb,
  resource_type text,
  resource_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE (organization_id, principal_kind, principal_id, operation, idempotency_key)
);

CREATE INDEX IF NOT EXISTS external_idempotency_lookup_idx
  ON system.external_idempotency_keys(organization_id,operation,idempotency_key);

CREATE TABLE IF NOT EXISTS system.external_requests (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id uuid REFERENCES platform.organizations(id) ON DELETE SET NULL,
  principal_kind text,
  principal_id text,
  transport text NOT NULL CHECK (transport IN ('rest','mcp','ui','worker')),
  request_id text NOT NULL,
  operation text NOT NULL,
  method text,
  resource_type text,
  resource_id uuid,
  response_status integer,
  duration_ms integer,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS external_requests_org_time_idx ON system.external_requests(organization_id,created_at DESC);
CREATE INDEX IF NOT EXISTS external_requests_request_id_idx ON system.external_requests(request_id);

ALTER TABLE system.external_idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE system.external_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY external_idempotency_admin_read ON system.external_idempotency_keys
  FOR SELECT TO authenticated USING (platform.is_org_admin(organization_id));
CREATE POLICY external_requests_admin_read ON system.external_requests
  FOR SELECT TO authenticated USING (organization_id IS NOT NULL AND platform.is_org_admin(organization_id));

REVOKE INSERT, UPDATE, DELETE ON system.external_idempotency_keys FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON system.external_requests FROM authenticated, anon;

CREATE OR REPLACE FUNCTION system.reserve_external_idempotency(
  p_organization_id uuid,
  p_principal_kind text,
  p_principal_id text,
  p_operation text,
  p_key text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog','system'
AS $$
DECLARE
  v_row system.external_idempotency_keys%ROWTYPE;
BEGIN
  INSERT INTO system.external_idempotency_keys(
    organization_id,principal_kind,principal_id,operation,idempotency_key,request_hash,status
  ) VALUES (
    p_organization_id,p_principal_kind,p_principal_id,p_operation,p_key,p_request_hash,'started'
  )
  ON CONFLICT (organization_id,principal_kind,principal_id,operation,idempotency_key) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object('state','reserved','id',v_row.id);
  END IF;

  SELECT * INTO v_row
  FROM system.external_idempotency_keys
  WHERE organization_id=p_organization_id
    AND principal_kind=p_principal_kind
    AND principal_id=p_principal_id
    AND operation=p_operation
    AND idempotency_key=p_key;

  IF v_row.request_hash <> p_request_hash THEN
    RETURN jsonb_build_object('state','conflict');
  END IF;

  IF v_row.status IN ('completed','failed') AND v_row.response_status IS NOT NULL AND v_row.response_body IS NOT NULL THEN
    RETURN jsonb_build_object('state','replay','status',v_row.response_status,'body',v_row.response_body,'id',v_row.id);
  END IF;

  RETURN jsonb_build_object('state','in_progress','id',v_row.id);
END;
$$;

CREATE OR REPLACE FUNCTION system.complete_external_idempotency(
  p_id uuid,
  p_status integer,
  p_body jsonb,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL,
  p_failed boolean DEFAULT false
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = 'system'
AS $$
  UPDATE system.external_idempotency_keys
  SET status = CASE WHEN p_failed THEN 'failed' ELSE 'completed' END,
      response_status = p_status,
      response_body = p_body,
      resource_type = p_resource_type,
      resource_id = p_resource_id,
      completed_at = now()
  WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION system.record_external_request(
  p_organization_id uuid,
  p_principal_kind text,
  p_principal_id text,
  p_transport text,
  p_request_id text,
  p_operation text,
  p_method text DEFAULT NULL,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL,
  p_response_status integer DEFAULT NULL,
  p_duration_ms integer DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = 'system'
AS $$
  INSERT INTO system.external_requests(
    organization_id,principal_kind,principal_id,transport,request_id,operation,method,resource_type,resource_id,response_status,duration_ms,metadata
  ) VALUES (
    p_organization_id,p_principal_kind,p_principal_id,p_transport,p_request_id,p_operation,p_method,p_resource_type,p_resource_id,p_response_status,p_duration_ms,COALESCE(p_metadata,'{}'::jsonb)
  ) RETURNING id;
$$;

REVOKE ALL ON FUNCTION system.reserve_external_idempotency(uuid,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION system.complete_external_idempotency(uuid,integer,jsonb,text,uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION system.record_external_request(uuid,text,text,text,text,text,text,text,uuid,integer,integer,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION system.reserve_external_idempotency(uuid,text,text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION system.complete_external_idempotency(uuid,integer,jsonb,text,uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION system.record_external_request(uuid,text,text,text,text,text,text,text,uuid,integer,integer,jsonb) TO service_role;

-- Cross-show integrity hardening for information-state references.
DO $$ BEGIN ALTER TABLE story.canon_facts ADD CONSTRAINT canon_facts_id_show_org_unique UNIQUE(id,show_id,organization_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE story.character_knowledge DROP CONSTRAINT IF EXISTS character_knowledge_fact_id_fkey;
ALTER TABLE story.character_knowledge
  ADD CONSTRAINT character_knowledge_fact_same_show_fk
  FOREIGN KEY (fact_id,show_id,organization_id) REFERENCES story.canon_facts(id,show_id,organization_id) ON DELETE CASCADE;

ALTER TABLE story.audience_knowledge DROP CONSTRAINT IF EXISTS audience_knowledge_fact_id_fkey;
ALTER TABLE story.audience_knowledge
  ADD CONSTRAINT audience_knowledge_fact_same_show_fk
  FOREIGN KEY (fact_id,show_id,organization_id) REFERENCES story.canon_facts(id,show_id,organization_id) ON DELETE CASCADE;

ALTER TABLE story.reveals DROP CONSTRAINT IF EXISTS reveals_fact_id_fkey;
ALTER TABLE story.reveals
  ADD CONSTRAINT reveals_fact_same_show_fk
  FOREIGN KEY (fact_id,show_id,organization_id) REFERENCES story.canon_facts(id,show_id,organization_id) ON DELETE CASCADE;

-- Fix audience-only reveal targets. A nullable character cannot participate in a primary key.
ALTER TABLE story.reveal_targets DROP CONSTRAINT IF EXISTS reveal_targets_pkey;
ALTER TABLE story.reveal_targets ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid();
ALTER TABLE story.reveal_targets ALTER COLUMN id SET NOT NULL;
ALTER TABLE story.reveal_targets ADD CONSTRAINT reveal_targets_pkey PRIMARY KEY(id);
CREATE UNIQUE INDEX IF NOT EXISTS reveal_targets_character_unique ON story.reveal_targets(reveal_id,character_id) WHERE character_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS reveal_targets_audience_unique ON story.reveal_targets(reveal_id) WHERE target_audience=true AND character_id IS NULL;
ALTER TABLE story.reveal_targets ALTER COLUMN character_id DROP NOT NULL;
