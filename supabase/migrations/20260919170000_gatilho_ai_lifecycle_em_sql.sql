-- Gatilho de ciclo de vida da OS, agora em SQL puro (19/09/2026).
--
-- O gatilho antigo (trg_ai_so_lifecycle) chamava por HTTP a edge ai-lifecycle-hooks, da 1ª
-- geração do AI Operator, apagada hoje. Ao ler o backup da edge, ficou claro que ela fazia
-- uma coisa que NINGUÉM mais faz: quando o status da OS muda, resolver os alertas de negócio
-- que perderam sentido (OS aguardando cliente, aguardando peças, concluída sem faturar) e
-- abrir na hora o alerta "concluída — faturar". O monitor horário só cria alertas, não fecha.
-- Este gatilho reproduz exatamente a mesma regra, sem HTTP, sem segredo, sem 404.

create or replace function private.ai_so_status_change_hook()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text;
  v_valor text;
begin
  if old.status is not distinct from new.status then
    return new;
  end if;

  -- 1) registro do evento (histórico que a edge antiga mantinha)
  insert into public.ai_lifecycle_events (entity_type, entity_id, entity_number, event_type, old_value, new_value, metadata)
  values ('service_order', new.id, new.service_order_number, 'status_change', old.status, new.status,
          jsonb_build_object('client_id', new.client_id, 'invoicing_status', new.invoicing_status,
                             'grand_total', new.grand_total, 'via', 'trigger_sql'));

  -- 2) alertas que perderam sentido com o novo status
  if new.status in ('approved', 'invoiced', 'cancelled', 'in_progress') then
    update public.ai_business_alerts set resolved_at = now()
     where entity_id = new.id and alert_type = 'os_awaiting_client_long' and resolved_at is null;
  end if;
  if new.status in ('in_progress', 'completed', 'invoiced', 'cancelled') then
    update public.ai_business_alerts set resolved_at = now()
     where entity_id = new.id and alert_type = 'os_awaiting_parts_long' and resolved_at is null;
  end if;
  if new.status in ('invoiced', 'cancelled') then
    update public.ai_business_alerts set resolved_at = now()
     where entity_id = new.id and alert_type = 'os_completed_not_invoiced' and resolved_at is null;
  end if;
  if new.status = 'cancelled' then
    update public.ai_business_alerts set resolved_at = now()
     where entity_id = new.id and resolved_at is null
       and alert_type in ('os_awaiting_client_long', 'os_awaiting_parts_long', 'os_completed_not_invoiced', 'os_no_technician');
  end if;

  -- 3) concluída e ainda não faturada: avisa na hora, sem esperar o monitor
  if new.status = 'completed' and coalesce(new.invoicing_status, 'not_invoiced') = 'not_invoiced'
     and coalesce(new.grand_total, 0) > 0 then
    select coalesce(nullif(c.display_name, ''), c.name) into v_nome from public.clients c where c.id = new.client_id;
    v_valor := replace(replace(replace(to_char(new.grand_total, 'FM999,999,990.00'), ',', '#'), '.', ','), '#', '.');
    insert into public.ai_business_alerts
      (alert_type, severity, title, description, entity_type, entity_id, entity_number, metadata, last_seen_at, resolved_at)
    values
      ('os_completed_not_invoiced', 'warning',
       'OS ' || new.service_order_number || ' concluída — faturar',
       'OS ' || new.service_order_number || ' (' || coalesce(v_nome, '—') || ') acabou de ser concluída. Valor: R$ ' || v_valor || '. Fature para não perder o prazo.',
       'service_order', new.id, new.service_order_number,
       jsonb_build_object('grand_total', new.grand_total, 'triggered_by', 'lifecycle_trigger'),
       now(), null)
    on conflict (alert_type, entity_id) do update
      set title = excluded.title, description = excluded.description, metadata = excluded.metadata,
          last_seen_at = now(), resolved_at = null;
  end if;

  return new;
end;
$$;

revoke all on function private.ai_so_status_change_hook() from public, anon, authenticated;

drop trigger if exists trg_ai_so_lifecycle on public.service_orders;
create trigger trg_ai_so_lifecycle
  after update of status on public.service_orders
  for each row execute function private.ai_so_status_change_hook();

insert into supabase_migrations.schema_migrations (version, name)
values ('20260919170000', 'gatilho_ai_lifecycle_em_sql')
on conflict do nothing;
