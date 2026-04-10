CREATE TABLE import_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL CHECK (entity_type IN ('products', 'services', 'clients', 'suppliers')),
  filename text NOT NULL,
  total_rows integer DEFAULT 0,
  imported_rows integer DEFAULT 0,
  skipped_rows integer DEFAULT 0,
  conflict_rows integer DEFAULT 0,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'mapping', 'reviewing', 'completed', 'cancelled')),
  column_mapping jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE import_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_import_sessions ON import_sessions
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);