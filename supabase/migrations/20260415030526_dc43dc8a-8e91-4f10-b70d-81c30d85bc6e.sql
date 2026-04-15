
CREATE TABLE vessel_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vessel_id uuid NOT NULL REFERENCES vessels(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role text NOT NULL DEFAULT 'owner',
  phone text,
  email text,
  notes text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE vessel_contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_vessel_contacts ON vessel_contacts
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS requested_by_contact_id uuid
    REFERENCES vessel_contacts(id);
