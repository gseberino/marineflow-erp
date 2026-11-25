-- Assinatura Claude pela PESSOA do assinante, e não pelo cargo (pacote 1 do assistente, S5, 24/11/2026).
--
-- NÃO APLICADA. Este arquivo existe para revisão: aplicar é do dono, com OK nomeado.
--
-- Por que existe: a assinatura Claude é de uso individual. Até aqui o servidor mandava pelo Claude da assinatura qualquer
-- administrador; um administrador inativo que fosse reativado entraria na fila, e a única trava seria a lista do programa
-- do PC. Com a chave abaixo o servidor confere a pessoa, pelo mesmo critério do PC (quem pediu: ai_jobs.requested_by).
--
-- GRAVA DADO: uma linha em app_settings, a chave 'ai_max_assinantes', com o id do único administrador ativo. Nenhuma
-- tabela, função, view, policy ou cron. app_settings não é tabela quente: um insert, sem trava longa.
--
--   · Exige EXATAMENTE 1 administrador ativo (em 24/11/2026: 1 ativo e 2 inativos). Com 0 ou com 2 ou mais, a migration
--     PARA sem gravar nada: quem é o assinante passa a ser decisão à mão, não desta migration.
--   · Sem "on conflict": se a chave já existir, TEM de dar erro (ela não é regravada calada).
--   · Nenhum id está escrito aqui: ele sai do cadastro na hora.
--
-- O que muda para quem usa: nada para o dono (em 90 dias, todos os pedidos ao Claude da assinatura foram dele). Os
-- outros administradores deixam de ir pela assinatura mesmo se forem reativados.
--
-- Como o código lê (supabase/functions/_shared/ai/max/claude-max.ts): chave AUSENTE = regra antiga (cargo admin), com
-- aviso no log, e por isso o deploy das funções pode sair antes desta migration; chave presente = só quem está na lista;
-- chave presente e vazia = ninguém.
--
-- Desfazer: delete from public.app_settings where key = 'ai_max_assinantes';   (o código volta à regra do cargo)
--
-- Aplicar (CLAUDE.md do repositório, regra 1: dois passos, e a versão se registra à mão):
--   npx supabase db query --linked -f supabase/migrations/20270301130000_assinatura_max_por_pessoa.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name) values ('20270301130000', 'assinatura_max_por_pessoa');"
-- Prova (depois de aplicar, ou antes, como ensaio): supabase/tests/assinatura_max_por_pessoa.sql.

do $$
declare
  n int;
  ids text;
begin
  select count(*), string_agg(id::text, ',') into n, ids
    from public.app_users
   where role = 'admin' and active;
  if n <> 1 then
    raise exception 'esperava 1 administrador ativo (o assinante), achei %: decida a lista à mão', n;
  end if;
  insert into public.app_settings (key, value, description)
  values ('ai_max_assinantes', ids,
          'Quem pode usar a assinatura Claude (uso individual). Lista de app_users.id. Mesmo critério do gateway (CLAUDE_LOCAL_ALLOWED_REQUESTERS).');
end $$;
