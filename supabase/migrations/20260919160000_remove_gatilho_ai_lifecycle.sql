-- Gatilho órfão (19/09/2026). trg_ai_so_lifecycle chamava, a cada mudança de status de OS, a edge
-- ai-lifecycle-hooks (1ª geração do AI Operator, maio/junho de 2026), que foi apagada hoje por
-- órfã: sem pasta no repositório, sem invocação nos logs, substituída pelo agente atual, pelo
-- motor de tarefas (task-automations) e pelos gatilhos trg_create_service_cases /
-- trg_sync_* que vivem na própria tabela. Depois da exclusão, cada mudança de status virou um
-- 404 em net._http_response (3 registrados às 23:09 de 19/09, no cancelamento de 3 rascunhos).
-- Sem a edge, o gatilho só gera ruído e uma requisição HTTP por atualização.

drop trigger if exists trg_ai_so_lifecycle on public.service_orders;
drop function if exists private.ai_so_status_change_hook();

insert into supabase_migrations.schema_migrations (version, name)
values ('20260919160000', 'remove_gatilho_ai_lifecycle')
on conflict do nothing;
