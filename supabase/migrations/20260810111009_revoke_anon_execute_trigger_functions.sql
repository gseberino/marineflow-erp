-- MF-AUD-025 — funções de GATILHO expostas como RPC ao papel anônimo.
--
-- O advisor de segurança do Supabase apontou três funções `SECURITY DEFINER`
-- chamáveis por `anon` via /rest/v1/rpc/<nome>. As três são funções de trigger:
-- invocadas fora de um trigger elas erram ("can only be called as trigger"), então
-- o risco de execução é baixo. O problema é de SUPERFÍCIE — não deveria existir a
-- porta, e uma delas roda como SECURITY DEFINER.
--
-- Por que escaparam: a migration 20260729120000_revoke_anon_execute_security_definer
-- fez exatamente este trabalho para as funções que existiam à época. Estas três foram
-- criadas depois. É a lição registrada na memória do projeto: em Postgres, criar
-- função concede EXECUTE a PUBLIC por padrão, e revogar de `public` não basta se
-- houver grant nominal — por isso revogamos de `public` E de `anon`.
--
-- Escopo deliberado: `authenticated` NÃO é tocado. Nenhuma delas é chamada pelo
-- frontend (são gatilhos), mas manter `authenticated` como está evita qualquer
-- surpresa e mantém o diff mínimo. O papel que precisa executá-las de fato é o
-- dono da tabela, via trigger, que não passa por GRANT.
--
-- Reversível: GRANT EXECUTE ON FUNCTION ... TO anon;

revoke execute on function public.trg_sync_fiscal_note_items()  from public, anon;
revoke execute on function public.valida_categoria_de_despesa() from public, anon;
revoke execute on function public.valida_recebivel_coerente()   from public, anon;
