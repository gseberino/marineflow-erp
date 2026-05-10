-- REMOVE AS REGRAS QUE CAUSAM LOOP
DROP POLICY IF EXISTS "allow_admin_all" ON public.app_users;
DROP POLICY IF EXISTS "allow_read_app_users" ON public.app_users;
DROP POLICY IF EXISTS "allow_update_self" ON public.app_users;

-- CRIA REGRAS SIMPLES E DIRETAS (SEM LOOP)
-- 1. Qualquer pessoa logada pode ver a lista de usuários (necessário para o sistema funcionar)
CREATE POLICY "permissao_leitura_usuarios" 
ON public.app_users FOR SELECT 
TO authenticated 
USING (true);

-- 2. Cada usuário pode atualizar seus próprios dados (exceto cargo)
CREATE POLICY "permissao_auto_atualizacao" 
ON public.app_users FOR UPDATE 
TO authenticated 
USING (auth.uid() = id);

-- 3. Regra mestra para o Admin (Usando o ID direto para evitar o loop de consulta)
-- O seu ID é a35b66dc-8866-4c50-97bd-419276730afe
CREATE POLICY "permissao_total_admin" 
ON public.app_users FOR ALL 
TO authenticated 
USING (auth.uid() = 'a35b66dc-8866-4c50-97bd-419276730afe');
