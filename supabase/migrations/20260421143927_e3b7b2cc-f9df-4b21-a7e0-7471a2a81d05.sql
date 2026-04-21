-- Secure admin check without recursive RLS. Keep existing parameter name to allow CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_users
    WHERE id = _user_id
      AND role = 'admin'
      AND active = true
  );
$$;

-- Helper function for provisioning an app profile shape.
-- This is intentionally created in public schema only; no trigger is attached to reserved auth schemas.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.app_users (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'technician'
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Replace app_users role CHECK constraint with the full role set expected by the app.
DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT tc.constraint_name
  INTO constraint_name
  FROM information_schema.table_constraints tc
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.constraint_schema = tc.constraint_schema
  WHERE tc.table_schema = 'public'
    AND tc.table_name = 'app_users'
    AND tc.constraint_type = 'CHECK'
    AND ccu.column_name = 'role'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.app_users DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

ALTER TABLE public.app_users
ADD CONSTRAINT app_users_role_check
CHECK (role IN ('admin', 'technician', 'financial', 'seller', 'other'));

-- Tighten app_users RLS policies.
DROP POLICY IF EXISTS app_users_select_auth ON public.app_users;
DROP POLICY IF EXISTS app_users_insert_admin ON public.app_users;
DROP POLICY IF EXISTS app_users_update_admin ON public.app_users;
DROP POLICY IF EXISTS app_users_delete_admin ON public.app_users;
DROP POLICY IF EXISTS authenticated_full_access ON public.app_users;
DROP POLICY IF EXISTS select_app_users ON public.app_users;
DROP POLICY IF EXISTS insert_app_users ON public.app_users;
DROP POLICY IF EXISTS update_app_users ON public.app_users;
DROP POLICY IF EXISTS delete_app_users ON public.app_users;
DROP POLICY IF EXISTS manage_app_users ON public.app_users;
DROP POLICY IF EXISTS app_users_select_self_or_admin ON public.app_users;
DROP POLICY IF EXISTS app_users_insert_admin_only ON public.app_users;
DROP POLICY IF EXISTS app_users_update_admin_only ON public.app_users;
DROP POLICY IF EXISTS app_users_delete_admin_only ON public.app_users;

CREATE POLICY app_users_select_self_or_admin
ON public.app_users
FOR SELECT
TO authenticated
USING (auth.uid() = id OR public.is_admin(auth.uid()));

CREATE POLICY app_users_insert_admin_only
ON public.app_users
FOR INSERT
TO authenticated
WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY app_users_update_admin_only
ON public.app_users
FOR UPDATE
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY app_users_delete_admin_only
ON public.app_users
FOR DELETE
TO authenticated
USING (public.is_admin(auth.uid()));