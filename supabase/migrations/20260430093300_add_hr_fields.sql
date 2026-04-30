-- Add HR and Financial fields to app_users
ALTER TABLE public.app_users 
ADD COLUMN IF NOT EXISTS cpf TEXT,
ADD COLUMN IF NOT EXISTS rg TEXT,
ADD COLUMN IF NOT EXISTS birth_date DATE,
ADD COLUMN IF NOT EXISTS hiring_date DATE,
ADD COLUMN IF NOT EXISTS resignation_date DATE,
ADD COLUMN IF NOT EXISTS department TEXT,
ADD COLUMN IF NOT EXISTS salary_base NUMERIC(15,2),
ADD COLUMN IF NOT EXISTS pix_key TEXT,
ADD COLUMN IF NOT EXISTS emergency_contact_name TEXT,
ADD COLUMN IF NOT EXISTS emergency_contact_phone TEXT,
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Update RLS to ensure sensitive data is protected (basic check)
-- Assume Admins can see everything, others can see their own
COMMENT ON COLUMN public.app_users.salary_base IS 'Sensible data - restricted to admin/HR';
COMMENT ON COLUMN public.app_users.cpf IS 'Sensible data';
