-- 05 · Funções e procedures dos schemas public e private (definição viva + privilégios)
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.

-- ── private.ai_op_is_active(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.ai_op_is_active(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.app_users
    where id = _user_id and active = true
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION private.ai_op_is_active(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION private.ai_op_is_active(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.ai_op_is_active(_user_id uuid) TO service_role;

-- ── private.ai_op_is_admin(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.ai_op_is_admin(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.app_users
    where id = _user_id and role = 'admin' and active = true
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION private.ai_op_is_admin(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION private.ai_op_is_admin(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.ai_op_is_admin(_user_id uuid) TO service_role;

-- ── private.ai_op_is_admin_or_financial(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.ai_op_is_admin_or_financial(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.app_users
    where id = _user_id and role in ('admin','financial') and active = true
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION private.ai_op_is_admin_or_financial(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION private.ai_op_is_admin_or_financial(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.ai_op_is_admin_or_financial(_user_id uuid) TO service_role;

-- ── private.ai_op_is_internal(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.ai_op_is_internal(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.app_users
    where id = _user_id and active = true
      and role in ('admin', 'technician', 'financial', 'seller', 'other')
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION private.ai_op_is_internal(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION private.ai_op_is_internal(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.ai_op_is_internal(_user_id uuid) TO service_role;

-- ── private.ai_so_status_change_hook() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.ai_so_status_change_hook()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;
-- ACL: postgres=X/postgres
GRANT EXECUTE ON FUNCTION private.ai_so_status_change_hook() TO postgres;

-- ── private.devolucao_baixa_estoque() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.devolucao_baixa_estoque()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_chaves      text[];
  v_item        jsonb;
  v_ref_chave   text;
  v_ref_item    int;
  v_pid         uuid;
  v_qtd         numeric;
  v_baixas      jsonb := '{}'::jsonb;  -- produto -> quantidade (soma das linhas do mesmo produto)
  v_sem_produto text[] := '{}';
  v_produto     text;
  v_saldo       numeric;
  v_nota        text;
begin
  if NEW.request_payload->>'purpose' is distinct from '4'
     or NEW.environment is distinct from 'producao'
     or NEW.status is distinct from 'authorized'
     or NEW.stock_settled_at is not null then
    return NEW;
  end if;
  if TG_OP = 'UPDATE' and OLD.status is not distinct from 'authorized' then
    return NEW;
  end if;

  v_nota := 'NF-e ' || coalesce(NEW.series::text, '') || '/' || coalesce(NEW.number::text, '');

  begin
    -- As notas de entrada referenciadas no nível da nota (as duas grafias que o payload já usou).
    select array_agg(distinct k) into v_chaves
      from (
        select regexp_replace(coalesce(r->>'access_key', ''), '\D', '', 'g') as k
          from jsonb_array_elements(coalesce(NEW.request_payload->'referenced_documents', '[]'::jsonb)) r
        union
        select regexp_replace(coalesce(r #>> '{}', ''), '\D', '', 'g')
          from jsonb_array_elements(coalesce(NEW.request_payload->'referenced_access_keys', '[]'::jsonb)) r
      ) x
     where length(k) = 44;

    for v_item in select * from jsonb_array_elements(coalesce(NEW.request_payload->'items', '[]'::jsonb)) loop
      v_qtd := coalesce(nullif(v_item->>'quantity', '')::numeric, 0);
      continue when v_qtd <= 0;

      v_pid := null;
      v_ref_chave := regexp_replace(coalesce(v_item->'referenced_document'->>'access_key', ''), '\D', '', 'g');
      v_ref_item := nullif(v_item->'referenced_document'->>'item', '')::int;

      -- 1) A referência do item: nota de entrada + número do item nela.
      if length(v_ref_chave) = 44 and v_ref_item is not null then
        select coalesce(fni.product_id, fni.matched_product_id) into v_pid
          from fiscal_notes fn
          join fiscal_note_items fni on fni.fiscal_note_id = fn.id
         where fn.nfe_key = v_ref_chave
           and fni.item_index = v_ref_item
         limit 1;
      end if;

      -- 2) O código do fornecedor dentro das notas referenciadas, se apontar para um produto só.
      if v_pid is null and coalesce(v_item->>'code', '') <> '' then
        select (array_agg(distinct coalesce(fni.product_id, fni.matched_product_id)))[1] into v_pid
          from fiscal_notes fn
          join fiscal_note_items fni on fni.fiscal_note_id = fn.id
         where fn.nfe_key = any (
                 coalesce(v_chaves, '{}'::text[])
                 || case when length(v_ref_chave) = 44 then array[v_ref_chave] else '{}'::text[] end)
           and coalesce(fni.c_prod, fni.sku_supplier) = v_item->>'code'
           and coalesce(fni.product_id, fni.matched_product_id) is not null
        having count(distinct coalesce(fni.product_id, fni.matched_product_id)) = 1;
      end if;

      if v_pid is null then
        v_sem_produto := v_sem_produto || coalesce(nullif(v_item->>'name', ''), v_item->>'code', '(sem nome)');
      else
        v_baixas := jsonb_set(v_baixas, array[v_pid::text],
                              to_jsonb(coalesce((v_baixas->>v_pid::text)::numeric, 0) + v_qtd));
      end if;
    end loop;

    for v_produto in select jsonb_object_keys(v_baixas) loop
      insert into inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, notes, adjusted_by)
      values
        (v_produto::uuid, 'fiscal_note_exit', -((v_baixas->>v_produto)::numeric),
         'issued_fiscal_document', NEW.id,
         'Devolução ao fornecedor — ' || v_nota, 'sistema');

      select coalesce(sum(quantity_delta), 0) into v_saldo
        from inventory_movements where product_id = v_produto::uuid;
      if v_saldo < 0 then
        perform public.log_app_error(
          'db', 'Devolução deixou o saldo do produto negativo: o estoque já estava abaixo do real antes dela.',
          'devolucao_baixa_estoque', v_nota, 'warn',
          jsonb_build_object('documento', NEW.id, 'produto', v_produto, 'saldo', v_saldo));
      end if;
    end loop;

    if array_length(v_sem_produto, 1) > 0 then
      perform public.log_app_error(
        'db', 'Devolução autorizada com item sem produto ligado: o estoque desse item não foi baixado (ajuste manual).',
        'devolucao_baixa_estoque', v_nota, 'warn',
        jsonb_build_object('documento', NEW.id, 'itens', to_jsonb(v_sem_produto)));
    end if;

    if v_baixas <> '{}'::jsonb then
      NEW.stock_settled_at := now();
    end if;
  exception when others then
    -- A autorização da nota nunca depende desta baixa.
    begin
      perform public.log_app_error(
        'db', 'Falha ao baixar o estoque da devolução: ' || sqlerrm,
        'devolucao_baixa_estoque', v_nota, 'error',
        jsonb_build_object('documento', NEW.id, 'sqlstate', sqlstate));
    exception when others then
      null;
    end;
  end;

  return NEW;
end;
$function$
;
COMMENT ON FUNCTION private.devolucao_baixa_estoque() IS 'Devolução de compra (finNFe 4) de produção autorizada: baixa fiscal_note_exit por item, produto achado pela nota de entrada referenciada (chave + nItem; senão cProd único). Marca stock_settled_at, o que liga o estorno de reverse_nfe_settlement_on_cancel. Nunca bloqueia a autorização: falha vai para app_error_logs. 04/10/2026.';
-- ACL: postgres=X/postgres
GRANT EXECUTE ON FUNCTION private.devolucao_baixa_estoque() TO postgres;

-- ── private.estoque_autor(p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.estoque_autor(p_autor uuid)
 RETURNS TABLE(id uuid, nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select a.id, coalesce(nullif(btrim(a.full_name), ''), 'sistema')
    from public.app_users a
   where a.id = coalesce(auth.uid(), p_autor)
  union all
  select null::uuid, 'sistema'
   where not exists (select 1 from public.app_users a where a.id = coalesce(auth.uid(), p_autor))
  limit 1;
$function$
;
-- ACL: postgres=X/postgres
GRANT EXECUTE ON FUNCTION private.estoque_autor(p_autor uuid) TO postgres;

-- ── private.estoque_recalcular_saldo() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION private.estoque_recalcular_saldo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ids uuid[];
  v_id uuid;
  v_antes text := coalesce(current_setting('estoque.via_movimento', true), '');
begin
  v_ids := array_remove(array[
    case when tg_op in ('INSERT', 'UPDATE') then new.product_id end,
    case when tg_op in ('UPDATE', 'DELETE') then old.product_id end
  ], null);
  perform set_config('estoque.via_movimento', '1', true);
  foreach v_id in array (select array_agg(distinct x) from unnest(v_ids) x) loop
    update public.products p
       set stock_quantity = coalesce((select sum(m.quantity_delta) from public.inventory_movements m where m.product_id = v_id), 0),
           updated_at = now()
     where p.id = v_id
       and p.stock_quantity is distinct from coalesce((select sum(m.quantity_delta) from public.inventory_movements m where m.product_id = v_id), 0);
  end loop;
  perform set_config('estoque.via_movimento', v_antes, true);
  return null;
end;
$function$
;
-- ACL: postgres=X/postgres
GRANT EXECUTE ON FUNCTION private.estoque_recalcular_saldo() TO postgres;

-- ── private.estoque_recusa_escrita_direta() ── [search_path=public]
CREATE OR REPLACE FUNCTION private.estoque_recusa_escrita_direta()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(current_setting('estoque.via_movimento', true), '') <> '1' then
    raise exception 'O saldo do estoque só muda por movimento (ajuste, entrada, OS, nota). Use "Ajustar estoque"; se a tela estava aberta há muito tempo, recarregue a página.'
      using errcode = 'P0001',
            detail = format('produto %s: saldo %s → %s recusado', new.id, old.stock_quantity, new.stock_quantity);
  end if;
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres
GRANT EXECUTE ON FUNCTION private.estoque_recusa_escrita_direta() TO postgres;

-- ── public._ai_gateway_auth(p_worker_id text, p_token text) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public._ai_gateway_auth(p_worker_id text, p_token text)
 RETURNS ai_gateway_workers
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w public.ai_gateway_workers;
begin
  select * into w
    from public.ai_gateway_workers g
   where g.id = p_worker_id
     and g.enabled
     and g.token_hash = encode(extensions.digest(convert_to(coalesce(p_token, ''), 'UTF8'), 'sha256'), 'hex');
  if not found then
    raise exception 'ai_gateway: worker não autorizado' using errcode = '28000';
  end if;
  return w;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._ai_gateway_auth(p_worker_id text, p_token text) TO postgres;
GRANT EXECUTE ON FUNCTION public._ai_gateway_auth(p_worker_id text, p_token text) TO service_role;

-- ── public._ai_gateway_reap() ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public._ai_gateway_reap()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  n integer;
begin
  with vencidos as (
    select j.id
      from public.ai_jobs j
     where j.status = 'processing'
       and j.lease_expires_at < now()
     for update skip locked
  )
  update public.ai_jobs j set
    status = case
      when j.cancel_requested_at is not null then 'cancelled'
      when j.attempts >= j.max_attempts then 'failed'
      else 'pending' end,
    completed_at = case
      when j.cancel_requested_at is not null or j.attempts >= j.max_attempts then now() end,
    available_at = now() + interval '15 seconds',
    lease_id = null,
    lease_expires_at = null,
    error_code = case when j.cancel_requested_at is not null then 'cancelled' else 'lease_expired' end,
    error = case when j.cancel_requested_at is not null then 'Cancelado.'
                 else 'O worker parou de responder durante a execução (lease vencida).' end
  from vencidos v
  where j.id = v.id;
  get diagnostics n = row_count;

  update public.ai_jobs j set
    status = 'failed',
    completed_at = now(),
    error_code = 'deadline_exceeded',
    error = 'O prazo do job venceu antes de ele começar.'
  where j.status = 'pending'
    and j.deadline_at is not null
    and j.deadline_at < now();

  return n;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._ai_gateway_reap() TO postgres;
GRANT EXECUTE ON FUNCTION public._ai_gateway_reap() TO service_role;

-- ── public._ai_jobs_campainha() ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public._ai_jobs_campainha()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  begin
    if tg_op = 'INSERT' and new.status = 'pending' then
      perform realtime.send('{}'::jsonb, 'wake', 'ai-gateway:wake', false);
    elsif tg_op = 'UPDATE' and new.status = 'processing'
          and new.cancel_requested_at is not null and old.cancel_requested_at is null then
      perform realtime.send(jsonb_build_object('job_id', new.id), 'cancel', 'ai-gateway:wake', false);
    end if;
  exception when others then
    null; -- a campainha é só atalho: o worker também faz polling e heartbeat
  end;
  return null;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._ai_jobs_campainha() TO postgres;
GRANT EXECUTE ON FUNCTION public._ai_jobs_campainha() TO service_role;

-- ── public._ai_jobs_entregar_turno() ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public._ai_jobs_entregar_turno()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (new.metadata->>'tipo' = 'agente_whatsapp'
      or (new.metadata->>'tipo' = 'agente_painel' and coalesce((new.metadata->>'painel_tarde')::boolean, false)))
     and new.status in ('completed', 'failed', 'cancelled')
     and old.status is distinct from new.status then
    begin
      perform net.http_post(
        url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-agent',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select s.value::text from public.app_settings s where s.key = 'cron_worker_secret')),
        body := jsonb_build_object('type', 'entregar_turno_max', 'job_id', new.id),
        timeout_milliseconds := 120000
      );
    exception when others then
      raise warning 'ai_jobs: falha ao pedir a entrega do turno %: %', new.id, sqlerrm;
    end;
  end if;
  return null;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._ai_jobs_entregar_turno() TO postgres;
GRANT EXECUTE ON FUNCTION public._ai_jobs_entregar_turno() TO service_role;

-- ── public._ai_jobs_touch() ── [search_path=""]
CREATE OR REPLACE FUNCTION public._ai_jobs_touch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at := now();
  return new;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._ai_jobs_touch() TO postgres;
GRANT EXECUTE ON FUNCTION public._ai_jobs_touch() TO service_role;

-- ── public._ai_orcamento_tecnico_montar(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid, p_numero text, p_uid uuid) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public._ai_orcamento_tecnico_montar(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid, p_numero text, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  j public.ai_jobs;
  v_orc jsonb;
  v_ja uuid;
  v_so uuid;
  v_validade integer;
  v_notas text;
  it jsonb;
  sv public.services;
  v_qtd numeric;
  v_custo numeric;
  v_venda numeric;
  v_prov boolean;
  v_desc text;
  v_nota text;
  v_prod uuid;
  n_pecas integer := 0;
  n_servicos integer := 0;
  n_pendentes integer := 0;
begin
  select * into j from public.ai_jobs x where x.id = p_job_id for update;
  if not found or j.metadata->>'tipo' is distinct from 'orcamento_tecnico' then
    raise exception 'Pedido de orçamento técnico não encontrado' using errcode = 'P0002';
  end if;
  if j.status <> 'completed' then
    raise exception 'A proposta ainda não está pronta (status %)', j.status using errcode = '22023';
  end if;
  v_orc := j.response->'data'->'orcamentos'->coalesce(p_indice, -1);
  if v_orc is null or jsonb_typeof(v_orc->'itens') is distinct from 'array' then
    raise exception 'O orçamento % não existe nesta proposta', coalesce(p_indice, -1) + 1 using errcode = '22023';
  end if;

  -- O mesmo orçamento da proposta não vira dois rascunhos (duplo clique, aba repetida).
  v_ja := nullif(j.metadata->'rascunhos'->>(p_indice::text), '')::uuid;
  if v_ja is not null and exists (select 1 from public.service_orders so where so.id = v_ja) then
    return jsonb_build_object('service_order_id', v_ja, 'ja_existia', true,
      'numero', (select so.service_order_number from public.service_orders so where so.id = v_ja));
  end if;

  if p_numero is null then
    raise exception 'Número do orçamento ausente' using errcode = '22023';
  end if;
  if not exists (select 1 from public.vessels v where v.id = p_vessel_id and v.client_id = p_client_id) then
    raise exception 'O ativo escolhido não pertence a este cliente' using errcode = '22023';
  end if;

  -- Validade: a configuração da empresa (mesma fonte do formulário e do assistente).
  select case when s.value ~ '^\s*\d{1,3}\s*$' and btrim(s.value)::int between 1 and 365 then btrim(s.value)::int end
    into v_validade from public.app_settings s where s.key = 'quote_validity_days';

  v_notas := left(concat_ws(E'\n',
    'Gerado pelo Orçamento técnico com IA em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
      || coalesce(' (modelo ' || j.model_used || ')', '') || '. Revise antes de enviar ao cliente.',
    'Pedido: ' || left(j.prompt, 600),
    case when jsonb_array_length(coalesce(v_orc->'observacoes_valores_provisorios', '[]'::jsonb)) > 0 then
      E'\nValores provisórios:\n- ' || (select string_agg(x, E'\n- ') from jsonb_array_elements_text(v_orc->'observacoes_valores_provisorios') x) end,
    case when jsonb_array_length(coalesce(j.response->'data'->'perguntas_pendentes', '[]'::jsonb)) > 0 then
      E'\nPerguntas pendentes:\n- ' || (select string_agg(x, E'\n- ') from jsonb_array_elements_text(j.response->'data'->'perguntas_pendentes') x) end,
    case when jsonb_array_length(coalesce(j.response->'data'->'premissas_tecnicas', '[]'::jsonb)) > 0 then
      E'\nPremissas técnicas:\n- ' || (select string_agg(x, E'\n- ') from jsonb_array_elements_text(j.response->'data'->'premissas_tecnicas') x) end
  ), 12000);

  insert into public.service_orders (
    client_id, vessel_id, service_order_number, status, quote_status,
    problem_description, internal_notes, quote_validity_days, created_by
  ) values (
    p_client_id, p_vessel_id, p_numero, 'draft', 'draft',
    left(coalesce(nullif(btrim(v_orc->>'titulo'), ''), 'Orçamento técnico'), 500), v_notas,
    coalesce(v_validade, 15), p_uid
  )
  returning id into v_so;

  for it in select value from jsonb_array_elements(v_orc->'itens') loop
    v_qtd := greatest(coalesce((it->>'quantidade')::numeric, 1), 0.001);
    v_custo := greatest(coalesce((it->>'custo_unitario')::numeric, 0), 0);
    v_venda := greatest(coalesce((it->>'preco_venda_unitario')::numeric, 0), 0);
    v_prov := coalesce((it->>'provisorio')::boolean, false);
    v_desc := left(coalesce(nullif(btrim(it->>'descricao'), ''), 'Item sem descrição'), 300);
    v_nota := left('IA: ' || coalesce(nullif(it->>'origem_do_custo', ''), 'sem origem informada')
                   || coalesce(' (' || nullif(it->>'data_do_custo', '') || ')', '')
                   || case when v_prov then ' — Valor provisório — aguardando cotação do fornecedor' else '' end, 1000);

    -- O id só vale se existir de fato: o modelo pode errar um uuid.
    v_prod := null;
    sv := null;
    if it->>'produto_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select p.id into v_prod from public.products p where p.id = (it->>'produto_id')::uuid;
    end if;
    if v_prod is null and it->>'servico_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select * into sv from public.services s where s.id = (it->>'servico_id')::uuid;
    end if;

    if v_prod is null and sv.id is null and coalesce(it->>'tipo', '') <> 'mao_de_obra' then
      -- Peça sem cadastro: PRODUTO PENDENTE, como o assistente já faz (item físico mora em Peças).
      -- Reaproveita o de mesmo nome para não encher o catálogo de duplicatas.
      select p.id into v_prod from public.products p
       where p.name ilike replace(replace(replace(v_desc, '\', '\\'), '%', '\%'), '_', '\_')
       limit 1;
      if v_prod is null then
        insert into public.products (name, sale_price, unit, notes)
        values (v_desc, round(v_venda, 2), 'UN',
                'Criado pelo Orçamento técnico com IA. Confirmar preço, unidade e NCM.')
        returning id into v_prod;
        n_pendentes := n_pendentes + 1;
      end if;
      v_nota := left(v_nota || ' — produto cadastrado pelo orçamento: completar o cadastro', 1000);
    end if;

    if v_prod is not null then
      insert into public.service_order_parts (
        service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, currency_snapshot,
        line_total_cost, line_total_sale, notes, source
      ) values (
        v_so, v_prod, v_qtd, round(v_custo, 2), round(v_venda, 2), 'BRL',
        round(v_custo * v_qtd, 2), round(v_venda * v_qtd, 2), v_nota, 'ai'
      );
      n_pecas := n_pecas + 1;
    else
      insert into public.service_order_services (
        service_order_id, service_id, name_snapshot, description_snapshot, billing_unit_snapshot,
        quantity, unit_price_snapshot, line_total, notes
      ) values (
        v_so, sv.id, coalesce(sv.name, v_desc), sv.description,
        coalesce(sv.billing_unit, 'unit'), v_qtd, round(v_venda, 2), round(v_venda * v_qtd, 2), v_nota
      );
      n_servicos := n_servicos + 1;
    end if;
  end loop;

  perform public.recalc_so_totals(v_so);

  update public.ai_jobs x
     set metadata = x.metadata || jsonb_build_object('rascunhos',
           coalesce(x.metadata->'rascunhos', '{}'::jsonb) || jsonb_build_object(p_indice::text, v_so))
   where x.id = p_job_id;

  return jsonb_build_object(
    'service_order_id', v_so, 'numero', p_numero, 'ja_existia', false,
    'pecas', n_pecas, 'servicos', n_servicos, 'produtos_pendentes_criados', n_pendentes,
    'total_geral', (select so.grand_total from public.service_orders so where so.id = v_so));
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._ai_orcamento_tecnico_montar(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid, p_numero text, p_uid uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._ai_orcamento_tecnico_montar(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid, p_numero text, p_uid uuid) TO service_role;

-- ── public._anotacao_documento_confere() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._anotacao_documento_confere()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_nome text;
  v_doc text;
begin
  if new.documento is null then
    return new;
  end if;
  select x.nome, x.doc into v_nome, v_doc
    from (
      select f.name as nome, f.cnpj_cpf as doc from public.suppliers f where f.id = new.fornecedor_id
      union all
      select pe.name, pe.document from public.payees pe where pe.id = new.favorecido_id
      union all
      select c.name, c.cpf_cnpj from public.clients c where c.id = new.cliente_id
    ) x
   where public._documento_contradiz(new.documento, x.doc)
   limit 1;
  -- Outra pessoa pagando (ou recebendo) em nome de alguém é caso de tela: a anotação só com o
  -- nome nunca casaria com a linha, que chega com o nome de quem pagou.
  if v_nome is not null then
    raise exception 'O documento % não é o de % (no cadastro: %): o sistema não junta nome e documento diferentes. Se é outra pessoa pagando ou recebendo em nome de %, classifique pela tela do Extrato quando a transação chegar; se o nome estava errado, anote só com o documento.',
      new.documento, v_nome, v_doc, v_nome;
  end if;
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._anotacao_documento_confere() TO postgres;
GRANT EXECUTE ON FUNCTION public._anotacao_documento_confere() TO service_role;

-- ── public._anotacoes_em_disputa(p_anotacao uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._anotacoes_em_disputa(p_anotacao uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select b.id
    from public.anotacoes_do_extrato b
   where b.status = 'aguardando' and b.id <> p_anotacao
     and exists (select 1 from public._candidatas_da_anotacao(b.id) cb
                  where cb in (select ca from public._candidatas_da_anotacao(p_anotacao) ca));
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._anotacoes_em_disputa(p_anotacao uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._anotacoes_em_disputa(p_anotacao uuid) TO service_role;

-- ── public._anotacoes_gemeas_esperando(p_anotacao uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._anotacoes_gemeas_esperando(p_anotacao uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select b.id
    from public.anotacoes_do_extrato a
    cross join lateral public._quem_da_anotacao(a.id) qa
    join public.anotacoes_do_extrato b
      on b.id <> a.id and b.status = 'aguardando'
     and b.sentido = a.sentido and abs(b.valor - a.valor) < 0.01
     and b.data_prevista - case when b.data_exata then 1 else 3 end <= a.data_prevista + case when a.data_exata then 1 else 7 end
     and a.data_prevista - case when a.data_exata then 1 else 3 end <= b.data_prevista + case when b.data_exata then 1 else 7 end
    cross join lateral public._quem_da_anotacao(b.id) qb
   where a.id = p_anotacao
     and not public._documento_contradiz(qa.q_doc, qb.q_doc)
     and not (qa.q_diz_quem and qb.q_diz_quem);
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._anotacoes_gemeas_esperando(p_anotacao uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._anotacoes_gemeas_esperando(p_anotacao uuid) TO service_role;

-- ── public._anotacoes_repetidas_esperando(p_anotacao uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._anotacoes_repetidas_esperando(p_anotacao uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select b.id
    from public.anotacoes_do_extrato a
    cross join lateral public._quem_da_anotacao(a.id) qa
    join public.anotacoes_do_extrato b
      on b.id <> a.id and b.status = 'aguardando'
     and b.sentido = a.sentido and abs(b.valor - a.valor) < 0.01
     and b.data_prevista - case when b.data_exata then 1 else 3 end <= a.data_prevista + case when a.data_exata then 1 else 7 end
     and a.data_prevista - case when a.data_exata then 1 else 3 end <= b.data_prevista + case when b.data_exata then 1 else 7 end
    cross join lateral public._quem_da_anotacao(b.id) qb
   where a.id = p_anotacao
     and qa.q_diz_quem and qb.q_diz_quem
     and not public._documento_contradiz(qa.q_doc, qb.q_doc)
     and (qa.q_fornecedor is not distinct from qb.q_fornecedor or public._mesma_empresa(qa.q_fornecedor, qb.q_fornecedor))
     and qa.q_favorecido is not distinct from qb.q_favorecido
     and qa.q_cliente is not distinct from qb.q_cliente
     -- Sem cadastro dos dois lados: só é a mesma se o nome dito for o mesmo.
     and (qa.q_fornecedor is not null or qa.q_favorecido is not null or qa.q_cliente is not null
          or qa.q_nomes && qb.q_nomes);
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._anotacoes_repetidas_esperando(p_anotacao uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._anotacoes_repetidas_esperando(p_anotacao uuid) TO service_role;

-- ── public._aplicar_anotacao(p_anotacao uuid, p_proposta uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._aplicar_anotacao(p_anotacao uuid, p_proposta uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a public.anotacoes_do_extrato%rowtype;
  v_dre text;
  v_cliente_da_os uuid;
begin
  select * into a from public.anotacoes_do_extrato where id = p_anotacao;
  if a.categoria is not null then
    select dre_group into v_dre from public.financial_categories where name = a.categoria and active limit 1;
  end if;
  if a.sentido = 'credit' and a.os_id is not null then
    select client_id into v_cliente_da_os from public.service_orders where id = a.os_id;
  end if;
  update public.finance_review_queue q set
    suggested_supplier_id = coalesce(a.fornecedor_id, q.suggested_supplier_id),
    suggested_payee_id = coalesce(a.favorecido_id, q.suggested_payee_id),
    suggested_client_id = coalesce(a.cliente_id, v_cliente_da_os, q.suggested_client_id),
    suggested_service_order_id = coalesce(a.os_id, q.suggested_service_order_id),
    suggested_category = coalesce(a.categoria, q.suggested_category),
    dre_group = coalesce(v_dre, q.dre_group),
    suggested_description = coalesce(a.descricao, q.suggested_description),
    confidence = 99,
    reasoning = left('Anotado por você em ' || to_char(a.criada_em at time zone 'America/Sao_Paulo', 'DD/MM')
                     || coalesce(': ' || a.descricao, '') || ' · ' || coalesce(q.reasoning, ''), 2000),
    evidencia = coalesce(q.evidencia, '{}'::jsonb) - 'cadastrar'
                || jsonb_build_object('anotacao', jsonb_strip_nulls(jsonb_build_object('id', a.id, 'os_id', a.os_id))),
    updated_at = now()
  where q.id = p_proposta and q.status = 'pending';
  update public.anotacoes_do_extrato
     set status = 'aplicada', aplicada_em = now(),
         bank_transaction_id = (select bank_transaction_id from public.finance_review_queue where id = p_proposta)
   where id = p_anotacao;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._aplicar_anotacao(p_anotacao uuid, p_proposta uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._aplicar_anotacao(p_anotacao uuid, p_proposta uuid) TO service_role;

-- ── public._aplicar_pro_labore(p_raiz uuid, p_pl numeric, p_ret numeric, p_salario numeric, p_mes date, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._aplicar_pro_labore(p_raiz uuid, p_pl numeric, p_ret numeric, p_salario numeric, p_mes date, p_autor uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.payables%rowtype;
  v_partes uuid[];
  v_total numeric := p_pl + p_ret;
  v_alvo text;
  v_antes jsonb;
  v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
  v_msg text;
begin
  -- Sempre o principal primeiro, depois as partes (a mesma ordem de _juntar_divisao).
  select * into r from public.payables where id = p_raiz for update;
  perform 1 from public.payables where divisao_id = p_raiz and status <> 'cancelled' for update;
  -- Revalida com as linhas travadas.
  if r.id is null or r.status <> 'paid' or r.divisao_id is not null
     or exists (select 1 from public.payables x
                 where (x.id = p_raiz or x.divisao_id = p_raiz) and x.status <> 'cancelled'
                   and (coalesce(x.expense_category, '') not in ('Pró-labore', 'Retirada de sócio')
                        or x.payee_id is distinct from r.payee_id or x.status <> 'paid'))
     or (select sum(x.amount) from public.payables x
          where (x.id = p_raiz or x.divisao_id = p_raiz) and x.status <> 'cancelled') <> v_total then
    return -1;
  end if;
  select coalesce(array_agg(id order by created_at, id), '{}'::uuid[]) into v_partes
    from public.payables where divisao_id = p_raiz and status <> 'cancelled';

  if p_pl > 0 and p_ret > 0 then
    if cardinality(v_partes) = 1 and r.expense_category = 'Pró-labore' and r.amount = p_pl
       and exists (select 1 from public.payables x
                    where x.id = v_partes[1] and x.expense_category = 'Retirada de sócio' and x.amount = p_ret) then
      return 0;
    end if;
  else
    v_alvo := case when p_ret = 0 then 'Pró-labore' else 'Retirada de sócio' end;
    if cardinality(v_partes) = 0 and r.expense_category = v_alvo and r.amount = v_total then
      return 0;
    end if;
  end if;

  v_antes := jsonb_build_object(
    'principal', jsonb_build_object('categoria', r.expense_category, 'valor', r.amount),
    'partes', (select jsonb_agg(jsonb_build_object('id', x.id, 'categoria', x.expense_category, 'valor', x.amount)
                                order by x.created_at, x.id)
                 from public.payables x where x.divisao_id = p_raiz and x.status <> 'cancelled'));

  if p_pl > 0 and p_ret > 0 then
    v_msg := public._brl(p_pl) || ' de pró-labore e ' || public._brl(p_ret) || ' de retirada de sócio';
    update public.payables
       set amount = p_pl, paid_amount = p_pl, balance_amount = 0, expense_category = 'Pró-labore',
           notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] Pró-labore pelo salário mínimo de '
                         || to_char(p_mes, 'MM/YYYY') || ': ' || v_msg || ' (a retirada é a outra parte deste Pix de '
                         || public._brl(v_total) || ').')
     where id = p_raiz;
    if cardinality(v_partes) >= 1 then
      update public.payables
         set amount = p_ret, paid_amount = p_ret, balance_amount = 0, expense_category = 'Retirada de sócio',
             bank_transaction_id = r.bank_transaction_id
       where id = v_partes[1];
      update public.payables
         set status = 'cancelled', bank_transaction_id = null,
             notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] Parte a mais na divisão do pró-labore: juntada à outra.')
       where id = any (v_partes[2:]);
    else
      insert into public.payables (
        description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
        supplier_id, supplier_name, payee_id, bank_transaction_id, origin, payment_method, currency,
        cost_center_id, linked_service_order_id, notes, divisao_id)
      values (
        r.description, r.issue_date, r.due_date, p_ret, p_ret, 0, 'paid', 'Retirada de sócio',
        r.supplier_id, r.supplier_name, r.payee_id, r.bank_transaction_id, r.origin, r.payment_method, r.currency,
        r.cost_center_id, r.linked_service_order_id,
        '[' || v_hoje || '] Parte do Pix de ' || public._brl(v_total) || ': retirada de sócio, o que passou do pró-labore de '
          || public._brl(p_salario) || ' (salário mínimo de ' || to_char(p_mes, 'MM/YYYY') || ').',
        p_raiz);
    end if;
  else
    v_msg := 'o pagamento inteiro (' || public._brl(v_total) || ') como ' || lower(v_alvo);
    update public.payables
       set status = 'cancelled', bank_transaction_id = null,
           notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] Parte juntada de volta: o pagamento inteiro ficou como '
                         || lower(v_alvo) || '.')
     where id = any (v_partes);
    update public.payables
       set amount = v_total, paid_amount = v_total, balance_amount = 0, expense_category = v_alvo,
           notes = case when r.expense_category is distinct from v_alvo or cardinality(v_partes) > 0
                        then btrim(coalesce(notes, '') || ' [' || v_hoje || '] Pró-labore pelo salário mínimo de '
                                   || to_char(p_mes, 'MM/YYYY') || ': ' || v_msg || '.')
                        else notes end
     where id = p_raiz;
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, valor, detalhe, antes, depois)
  values ('separou_pro_labore', p_autor, r.bank_transaction_id, p_raiz, v_total,
          left('Pró-labore pelo salário mínimo (' || to_char(p_mes, 'MM/YYYY') || ', ' || public._brl(p_salario) || '): '
               || v_msg || '.' || case when p_autor is null then ' Rotina automática.' else '' end, 300),
          v_antes,
          jsonb_build_object('pro_labore', p_pl, 'retirada', p_ret));
  return 1;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._aplicar_pro_labore(p_raiz uuid, p_pl numeric, p_ret numeric, p_salario numeric, p_mes date, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._aplicar_pro_labore(p_raiz uuid, p_pl numeric, p_ret numeric, p_salario numeric, p_mes date, p_autor uuid) TO service_role;

-- ── public._app_settings_chaves_do_dono() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._app_settings_chaves_do_dono()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and not public.is_admin(v_uid)
     and ((tg_op <> 'INSERT' and old.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo'))
          or (tg_op <> 'DELETE' and new.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo'))) then
    raise exception 'Só o administrador muda o salário mínimo e a regra do pró-labore.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._app_settings_chaves_do_dono() TO postgres;
GRANT EXECUTE ON FUNCTION public._app_settings_chaves_do_dono() TO service_role;

-- ── public._autor_do_financeiro(p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._autor_do_financeiro(p_autor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v uuid := auth.uid();
begin
  if v is not null then
    if not public.is_admin_or_financial(v) then
      raise exception 'Só administrador ou financeiro pode alterar lançamentos.' using errcode = '42501';
    end if;
    return v;
  end if;
  if p_autor is not null and not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode alterar lançamentos.' using errcode = '42501';
  end if;
  return p_autor;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._autor_do_financeiro(p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._autor_do_financeiro(p_autor uuid) TO service_role;

-- ── public._brl(p_valor numeric) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._brl(p_valor numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select 'R$ ' || translate(to_char(coalesce(p_valor, 0), 'FM999,999,990.00'), ',.', '.,');
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres authenticated=X/postgres
GRANT EXECUTE ON FUNCTION public._brl(p_valor numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public._brl(p_valor numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public._brl(p_valor numeric) TO authenticated;

-- ── public._candidatas_da_anotacao(p_anotacao uuid, p_incluir_anotadas boolean) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._candidatas_da_anotacao(p_anotacao uuid, p_incluir_anotadas boolean DEFAULT false)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select q.id
    from public.anotacoes_do_extrato a
    join public.bank_transactions t on t.transaction_type = a.sentido
     and abs(t.amount - a.valor) < 0.01
     and t.transaction_date between a.data_prevista - case when a.data_exata then 1 else 3 end
                                and a.data_prevista + case when a.data_exata then 1 else 7 end
    join public.finance_review_queue q on q.bank_transaction_id = t.id and q.status = 'pending'
     and q.kind = case when a.sentido = 'debit' then 'create_payable' else 'create_receivable' end
   where a.id = p_anotacao
     and (p_incluir_anotadas or not (coalesce(q.evidencia, '{}'::jsonb) ? 'anotacao'))
     and public._identidade_serve(a.id, t.id, q.suggested_supplier_id, q.suggested_payee_id, q.suggested_client_id);
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._candidatas_da_anotacao(p_anotacao uuid, p_incluir_anotadas boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public._candidatas_da_anotacao(p_anotacao uuid, p_incluir_anotadas boolean) TO service_role;

-- ── public._confere_divisao() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._confere_divisao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op in ('INSERT', 'UPDATE') then
    perform public._confere_divisao_do_grupo(coalesce(new.divisao_id, new.id));
  end if;
  if tg_op = 'DELETE'
     or (tg_op = 'UPDATE' and coalesce(old.divisao_id, old.id) is distinct from coalesce(new.divisao_id, new.id)) then
    perform public._confere_divisao_do_grupo(coalesce(old.divisao_id, old.id));
  end if;
  return null;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._confere_divisao() TO postgres;
GRANT EXECUTE ON FUNCTION public._confere_divisao() TO service_role;

-- ── public._confere_divisao_do_grupo(p_raiz uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._confere_divisao_do_grupo(p_raiz uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_raiz record;
  v_linhas integer;
  v_sem_linha integer;
  v_soma numeric;
  v_linha uuid;
  v_valor_linha numeric;
begin
  if p_raiz is null
     or not exists (select 1 from public.payables where divisao_id = p_raiz and status <> 'cancelled') then
    return;
  end if;
  select id, status, divisao_id into v_raiz from public.payables where id = p_raiz;
  if v_raiz.id is null or v_raiz.status = 'cancelled' or v_raiz.divisao_id is not null then
    raise exception 'Parte de pagamento dividido sem o lançamento principal ativo. Use Desfazer ou Cancelar no lançamento, que tratam as partes juntas.'
      using errcode = 'check_violation';
  end if;
  select count(distinct bank_transaction_id), count(*) filter (where bank_transaction_id is null),
         sum(amount), min(bank_transaction_id::text)::uuid
    into v_linhas, v_sem_linha, v_soma, v_linha
    from public.payables
   where (id = p_raiz or divisao_id = p_raiz) and status <> 'cancelled';
  if v_sem_linha > 0 or v_linhas <> 1 then
    raise exception 'As partes de um pagamento dividido ficam na mesma linha do banco. Use Desfazer ou Cancelar no lançamento, que tratam as partes juntas.'
      using errcode = 'check_violation';
  end if;
  select abs(amount) into v_valor_linha from public.bank_transactions where id = v_linha;
  if v_valor_linha is null or abs(v_soma - v_valor_linha) > 0.005 then
    raise exception 'As partes somam % e o pagamento no banco é de %: um pagamento dividido tem de somar o valor da linha. Use Desfazer ou Cancelar no lançamento, que tratam as partes juntas.',
      public._brl(v_soma), public._brl(v_valor_linha)
      using errcode = 'check_violation';
  end if;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._confere_divisao_do_grupo(p_raiz uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._confere_divisao_do_grupo(p_raiz uuid) TO service_role;

-- ── public._conta_caixa() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._conta_caixa()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id from public.bank_connections where provider = 'caixa' order by created_at limit 1;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._conta_caixa() TO postgres;
GRANT EXECUTE ON FUNCTION public._conta_caixa() TO service_role;

-- ── public._conta_corrente_linhas(p_favorecido_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._conta_corrente_linhas(p_favorecido_id uuid)
 RETURNS TABLE(data date, tipo text, id uuid, jornada text, fracao numeric, valor_diaria numeric, extras numeric, descontos numeric, trabalhado numeric, pago numeric, descricao text, conta text, categoria text, observacao text, os jsonb, criado_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with fav as (
    select id, coalesce(conta_corrente_desde, date '1900-01-01') as desde
      from public.payees where id = p_favorecido_id
  )
  select ws.data, 'dia'::text, ws.id,
         case ws.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
         ws.fracao, ws.valor_diaria, ws.extras, ws.descontos, ws.valor_dia, 0::numeric,
         null::text, null::text, null::text, ws.observacao,
         coalesce((select jsonb_agg(jsonb_build_object('id', so.id, 'numero', so.service_order_number)
                                    order by so.service_order_number)
                     from public.work_shift_os wo
                     join public.service_orders so on so.id = wo.service_order_id
                    where wo.shift_id = ws.id), '[]'::jsonb),
         ws.created_at
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join fav on fav.id = wp.payee_id
   where ws.fracao is not null and ws.data >= fav.desde
  union all
  -- O que ele recebeu: lançamento no nome dele (conta o que foi pago dele) ou pago do bolso do
  -- sócio para ele (conta o valor inteiro — o dinheiro já chegou a ele, o reembolso é do sócio).
  select p.issue_date, 'pagamento'::text, p.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric,
         case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end,
         p.description,
         case when p.payee_id = fav.id
              then coalesce(bc.label, case when p.payment_method = 'cash' then 'Caixa (dinheiro)' end, 'Sem conta ligada')
              else 'Bolso de ' || coalesce(soc.name, 'sócio') end,
         p.expense_category, null::text, '[]'::jsonb, p.created_at
    from public.payables p
    join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
    left join public.payees soc on soc.id = p.payee_id
    left join public.bank_transactions bt on bt.id = p.bank_transaction_id
    left join public.bank_connections bc on bc.id = bt.bank_connection_id
   where p.status <> 'cancelled' and p.issue_date >= fav.desde
     and (case when p.payee_id = fav.id then coalesce(p.paid_amount, 0) else p.amount end) > 0;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._conta_corrente_linhas(p_favorecido_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._conta_corrente_linhas(p_favorecido_id uuid) TO service_role;

-- ── public._dia_curto(p date) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._dia_curto(p date)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select (array['dom','seg','ter','qua','qui','sex','sáb'])[extract(dow from p)::int + 1] || ' ' || to_char(p, 'DD/MM');
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._dia_curto(p date) TO postgres;
GRANT EXECUTE ON FUNCTION public._dia_curto(p date) TO service_role;

-- ── public._divisao_de(p_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._divisao_de(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with raiz as (
    select coalesce(divisao_id, id) as id from public.payables where id = p_id and status <> 'cancelled'
  ), membros as (
    select x.id, x.divisao_id, x.created_at, x.amount, x.expense_category
      from public.payables x, raiz
     where (x.id = raiz.id or x.divisao_id = raiz.id) and x.status <> 'cancelled'
  )
  select case when (select count(*) from membros) > 1 then jsonb_build_object(
    'raiz', (select id from raiz),
    'total', (select sum(amount) from membros),
    'frase', 'Era um Pix dividido ('
             || (select string_agg(coalesce(expense_category, 'sem categoria') || ' ' || public._brl(amount), ' + '
                                   order by divisao_id nulls first, created_at, id) from membros)
             || '): valeu para o pagamento inteiro de ' || public._brl((select sum(amount) from membros)) || '.')
  end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._divisao_de(p_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._divisao_de(p_id uuid) TO service_role;

-- ── public._doc_normalizado(p text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._doc_normalizado(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case length(d) when 13 then lpad(d, 14, '0') when 10 then lpad(d, 11, '0') else d end
    from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._doc_normalizado(p text) TO postgres;
GRANT EXECUTE ON FUNCTION public._doc_normalizado(p text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._doc_normalizado(p text) TO service_role;

-- ── public._documento_contradiz(a text, b text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._documento_contradiz(a text, b text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when length(x) < 11 or length(y) < 11 then false
    when length(x) <> length(y) then true
    when length(x) = 14 then left(x, 8) <> left(y, 8)
    else x <> y
  end
  from (select public._doc_normalizado(a) as x, public._doc_normalizado(b) as y) z;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._documento_contradiz(a text, b text) TO postgres;
GRANT EXECUTE ON FUNCTION public._documento_contradiz(a text, b text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._documento_contradiz(a text, b text) TO service_role;

-- ── public._e_concordancia(p_texto text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._e_concordancia(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    btrim(regexp_replace(
      regexp_replace(translate(lower(coalesce(p_texto, '')), 'áàâãéêíóôõúüç', 'aaaaeeiooouuc'), '[^a-z0-9👍 ]', ' ', 'g'),
      '\s+', ' ', 'g'))
    ~ '^(sim|s|ss|confirmo|confirmado|confirmada|ok|okay|beleza|blz|combinado|certo|perfeito|pode ser|👍)( (sim|confirmo|confirmado|confirmada|ok|obrigado|obrigada|valeu|combinado|perfeito|certo|pode ser|tudo certo|ate la|te espero|estarei la|👍))*$',
    false);
$function$
;
-- ACL: =X/postgres postgres=X/postgres anon=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._e_concordancia(p_texto text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public._e_concordancia(p_texto text) TO postgres;
GRANT EXECUTE ON FUNCTION public._e_concordancia(p_texto text) TO anon;
GRANT EXECUTE ON FUNCTION public._e_concordancia(p_texto text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._e_concordancia(p_texto text) TO service_role;

-- ── public._estado_do_saldo(p_saldo numeric, p_dias numeric, p_pago numeric) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._estado_do_saldo(p_saldo numeric, p_dias numeric, p_pago numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when coalesce(p_dias, 0) = 0 and coalesce(p_pago, 0) > 0.005 then 'semdias'
    when p_saldo > 0.005 then 'deve'
    when p_saldo < -0.005 then 'adiantado'
    else 'quitado' end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._estado_do_saldo(p_saldo numeric, p_dias numeric, p_pago numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public._estado_do_saldo(p_saldo numeric, p_dias numeric, p_pago numeric) TO service_role;

-- ── public._folha_sem_diarista_de_conta_corrente() ── [search_path=public]
CREATE OR REPLACE FUNCTION public._folha_sem_diarista_de_conta_corrente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_nome text;
begin
  select p.name into v_nome
    from public.work_profiles wp join public.payees p on p.id = wp.payee_id
   where wp.id = new.work_profile_id and wp.modo_pagamento = 'diaria' and p.conta_corrente_desde is not null;
  if v_nome is not null then
    raise exception '% é diarista com conta corrente: o que se paga a ele vem do extrato, e a folha criaria a mesma despesa em dobro. Veja o saldo em Financeiro › Diárias.', v_nome
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._folha_sem_diarista_de_conta_corrente() TO postgres;
GRANT EXECUTE ON FUNCTION public._folha_sem_diarista_de_conta_corrente() TO service_role;

-- ── public._hoje_brt() ── [search_path=public]
CREATE OR REPLACE FUNCTION public._hoje_brt()
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$ select (now() at time zone 'America/Sao_Paulo')::date; $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._hoje_brt() TO postgres;
GRANT EXECUTE ON FUNCTION public._hoje_brt() TO authenticated;
GRANT EXECUTE ON FUNCTION public._hoje_brt() TO service_role;

-- ── public._identidade_serve(p_anotacao uuid, p_tx uuid, p_fornecedor uuid, p_favorecido uuid, p_cliente uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._identidade_serve(p_anotacao uuid, p_tx uuid, p_fornecedor uuid, p_favorecido uuid, p_cliente uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((
    select (an.documento is null or public._doc_normalizado(t.counterparty_document) = public._doc_normalizado(an.documento))
       and not public._documento_contradiz(t.counterparty_document, qd.q_doc)
       and case
         when not qd.q_diz_quem then
           p_fornecedor is null and p_favorecido is null and p_cliente is null
           and public._nome_da_linha(t.counterparty_name, t.description) is null
         else
           (case when qd.q_fornecedor is null then p_fornecedor is null
                 else p_fornecedor is null or p_fornecedor = qd.q_fornecedor
                      or public._mesma_empresa(p_fornecedor, qd.q_fornecedor) end)
           and coalesce(p_favorecido, qd.q_favorecido) is not distinct from qd.q_favorecido
           and coalesce(p_cliente, qd.q_cliente) is not distinct from qd.q_cliente
           and (
             public._nome_da_linha(t.counterparty_name, t.description) is null
             -- Documento dos dois lados, sem contradição (mesmo CPF, ou mesma raiz de CNPJ).
             or (length(qd.q_doc) >= 11 and length(public._doc_normalizado(t.counterparty_document)) >= 11)
             or exists (
               select 1 from unnest(qd.q_nomes) n
                where n = public._nome_comparavel(public._nome_da_linha(t.counterparty_name, t.description))
                   or (length(btrim(public._nome_da_linha(t.counterparty_name, t.description))) >= 29
                       and length(public._nome_comparavel(public._nome_da_linha(t.counterparty_name, t.description))) >= 25
                       and n like public._nome_comparavel(public._nome_da_linha(t.counterparty_name, t.description)) || '%')))
       end
      from public.anotacoes_do_extrato an
      cross join lateral public._quem_da_anotacao(an.id) qd
      join public.bank_transactions t on t.id = p_tx
     where an.id = p_anotacao), false);
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._identidade_serve(p_anotacao uuid, p_tx uuid, p_fornecedor uuid, p_favorecido uuid, p_cliente uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._identidade_serve(p_anotacao uuid, p_tx uuid, p_fornecedor uuid, p_favorecido uuid, p_cliente uuid) TO service_role;

-- ── public._janela_tem_linha_anotada(p_anotacao uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._janela_tem_linha_anotada(p_anotacao uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public._candidatas_da_anotacao(p_anotacao, true) c
      join public.finance_review_queue q on q.id = c
     where coalesce(q.evidencia, '{}'::jsonb) ? 'anotacao');
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._janela_tem_linha_anotada(p_anotacao uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._janela_tem_linha_anotada(p_anotacao uuid) TO service_role;

-- ── public._juntar_divisao(p_id uuid, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._juntar_divisao(p_id uuid, p_motivo text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_raiz uuid;
  v_status text;
  v_total numeric;
  v_partes jsonb;
  v_nota text := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] ';
begin
  select coalesce(divisao_id, id), status into v_raiz, v_status from public.payables where id = p_id;
  if v_raiz is null or v_status = 'cancelled' then
    return p_id;
  end if;
  -- Sempre o principal primeiro, depois as partes: a mesma ordem da separação (sem deadlock).
  perform 1 from public.payables where id = v_raiz for update;
  perform 1 from public.payables where divisao_id = v_raiz for update;
  select jsonb_agg(jsonb_build_object('id', id, 'categoria', expense_category, 'valor', amount) order by created_at, id)
    into v_partes
    from public.payables where divisao_id = v_raiz and status <> 'cancelled';
  if v_partes is null then
    return v_raiz;
  end if;
  select sum(amount) into v_total
    from public.payables where (id = v_raiz or divisao_id = v_raiz) and status <> 'cancelled';

  update public.payables
     set status = 'cancelled', bank_transaction_id = null,
         notes = btrim(coalesce(notes, '') || ' ' || v_nota || 'Parte juntada de volta ao pagamento inteiro para '
                       || coalesce(nullif(btrim(p_motivo), ''), 'mexer nele') || '.')
   where divisao_id = v_raiz and status <> 'cancelled';
  update public.payables
     set amount = v_total,
         paid_amount = case when status = 'paid' then v_total else paid_amount end,
         balance_amount = case when status = 'paid' then 0 else greatest(0, v_total - coalesce(paid_amount, 0)) end
   where id = v_raiz;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, valor, detalhe, antes, depois)
  select 'juntou_divisao', p_autor, p.bank_transaction_id, v_raiz, v_total,
         left('As partes do pagamento (pró-labore e retirada de sócio) voltaram a ser um lançamento só, para '
              || coalesce(nullif(btrim(p_motivo), ''), 'mexer nele') || '.', 300),
         jsonb_build_object('partes', v_partes, 'principal', p.expense_category),
         jsonb_build_object('valor', v_total)
    from public.payables p where p.id = v_raiz;
  return v_raiz;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._juntar_divisao(p_id uuid, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._juntar_divisao(p_id uuid, p_motivo text, p_autor uuid) TO service_role;

-- ── public._linha_do_caixa(p_tipo text, p_valor numeric, p_data date, p_descricao text, p_quem text, p_fora_tipo text, p_fora_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._linha_do_caixa(p_tipo text, p_valor numeric, p_data date, p_descricao text, p_quem text, p_fora_tipo text, p_fora_motivo text, p_autor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, provider,
                                        bank_ref_id, bank_connection_id, counterparty_name, reconciled,
                                        dismissed_kind, dismissed_reason, dismissed_at, dismissed_by)
  values (p_data, left(p_descricao, 300), round(p_valor, 2), p_tipo, 'cash', 'caixa',
          'caixa:' || gen_random_uuid(), public._conta_caixa(), p_quem, true,
          p_fora_tipo, p_fora_motivo, case when p_fora_tipo is not null then now() end,
          case when p_fora_tipo is not null then p_autor end)
  returning id into v_id;
  return v_id;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._linha_do_caixa(p_tipo text, p_valor numeric, p_data date, p_descricao text, p_quem text, p_fora_tipo text, p_fora_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._linha_do_caixa(p_tipo text, p_valor numeric, p_data date, p_descricao text, p_quem text, p_fora_tipo text, p_fora_motivo text, p_autor uuid) TO service_role;

-- ── public._loja_da_parcela(p_quem text, p_descricao text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._loja_da_parcela(p_quem text, p_descricao text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select upper(translate(btrim(regexp_replace(
           regexp_replace(coalesce(nullif(btrim(p_quem), ''), p_descricao, ''), '\s*\d{1,2}\s*/\s*\d{1,2}\s*$', ''),
           '\s+', ' ', 'g')),
         'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'));
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._loja_da_parcela(p_quem text, p_descricao text) TO postgres;
GRANT EXECUTE ON FUNCTION public._loja_da_parcela(p_quem text, p_descricao text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._loja_da_parcela(p_quem text, p_descricao text) TO service_role;

-- ── public._mesma_empresa(p_a uuid, p_b uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._mesma_empresa(p_a uuid, p_b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((
    select length(public._doc_normalizado(s1.cnpj_cpf)) = 14
       and left(public._doc_normalizado(s1.cnpj_cpf), 8) = left(public._doc_normalizado(s2.cnpj_cpf), 8)
      from public.suppliers s1, public.suppliers s2
     where s1.id = p_a and s2.id = p_b), false);
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._mesma_empresa(p_a uuid, p_b uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._mesma_empresa(p_a uuid, p_b uuid) TO service_role;

-- ── public._nasceu_do_extrato(p_tipo text, p_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._nasceu_do_extrato(p_tipo text, p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when p_tipo = 'payable' then
      exists (select 1 from public.payables where id = p_id and origin = 'bank_reconciliation')
      or exists (select 1 from public.finance_review_queue where created_payable_id = p_id)
    else
      exists (select 1 from public.finance_review_queue where created_receivable_id = p_id)
  end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._nasceu_do_extrato(p_tipo text, p_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._nasceu_do_extrato(p_tipo text, p_id uuid) TO service_role;

-- ── public._nome_comparavel(p text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._nome_comparavel(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select btrim(regexp_replace(regexp_replace(regexp_replace(
           upper(translate(regexp_replace(coalesce(p, ''), '\([^)]*\)', ' ', 'g'),
             'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
             'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN')),
           '[^A-Z0-9 ]', ' ', 'g'),
           '\m(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\M', ' ', 'g'),
           '\s+', ' ', 'g'));
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._nome_comparavel(p text) TO postgres;
GRANT EXECUTE ON FUNCTION public._nome_comparavel(p text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._nome_comparavel(p text) TO service_role;

-- ── public._nome_da_linha(p_nome text, p_descricao text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._nome_da_linha(p_nome text, p_descricao text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select nullif(btrim(coalesce(nullif(btrim(coalesce(p_nome, '')), ''),
    substring(coalesce(p_descricao, '') from '(?i)^(?:pix|ted|doc|transf\w*)\s+(?:enviad[oa]|recebid[oa]|realizad[oa])\s+(?:para|de|por)\s+(.{3,})$'),
    '')), '');
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._nome_da_linha(p_nome text, p_descricao text) TO postgres;
GRANT EXECUTE ON FUNCTION public._nome_da_linha(p_nome text, p_descricao text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._nome_da_linha(p_nome text, p_descricao text) TO service_role;

-- ── public._pagamento_segue_a_linha() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._pagamento_segue_a_linha()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'UPDATE' and old.reconciled_payment_id is not null
     and old.reconciled_payment_id is distinct from new.reconciled_payment_id then
    update public.payments set bank_transaction_id = null
     where id = old.reconciled_payment_id and bank_transaction_id = new.id;
  end if;
  if new.reconciled_payment_id is not null
     and (tg_op = 'INSERT' or old.reconciled_payment_id is distinct from new.reconciled_payment_id) then
    update public.payments set bank_transaction_id = new.id
     where id = new.reconciled_payment_id and bank_transaction_id is distinct from new.id;
  end if;
  return null;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._pagamento_segue_a_linha() TO postgres;
GRANT EXECUTE ON FUNCTION public._pagamento_segue_a_linha() TO service_role;

-- ── public._pagamentos_que_podem_ser_a_parcela(p_fornecedor uuid, p_valor numeric, p_venc date, p_emissao date) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._pagamentos_que_podem_ser_a_parcela(p_fornecedor uuid, p_valor numeric, p_venc date, p_emissao date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'payable_id', p.id, 'data', p.issue_date, 'valor', p.amount,
           'descricao', left(coalesce(p.description, ''), 120))
           order by abs(p.issue_date - p_venc), p.created_at), '[]'::jsonb)
    from public.payables p
   where p.supplier_id = p_fornecedor
     and p.fiscal_note_id is null
     and p.status <> 'cancelled'
     and p.bank_transaction_id is not null
     and abs(p.amount - p_valor) < 0.01
     and abs(p.issue_date - p_venc) <= 7
     and p.issue_date >= p_emissao - 3;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._pagamentos_que_podem_ser_a_parcela(p_fornecedor uuid, p_valor numeric, p_venc date, p_emissao date) TO postgres;
GRANT EXECUTE ON FUNCTION public._pagamentos_que_podem_ser_a_parcela(p_fornecedor uuid, p_valor numeric, p_venc date, p_emissao date) TO service_role;

-- ── public._proposta_da_anotacao(p_anotacao uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._proposta_da_anotacao(p_anotacao uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when count(*) = 1 then (array_agg(c))[1] end
    from public._candidatas_da_anotacao(p_anotacao) c;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._proposta_da_anotacao(p_anotacao uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._proposta_da_anotacao(p_anotacao uuid) TO service_role;

-- ── public._quem_da_anotacao(p_anotacao uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._quem_da_anotacao(p_anotacao uuid)
 RETURNS TABLE(q_fornecedor uuid, q_favorecido uuid, q_cliente uuid, q_doc text, q_nomes text[], q_diz_quem boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select an.fornecedor_id, an.favorecido_id, cli.id,
         public._doc_normalizado(coalesce(an.documento, f.cnpj_cpf, pe.document, cli.cpf_cnpj)),
         array_remove(array[public._nome_comparavel(f.name), public._nome_comparavel(f.trade_name),
                            public._nome_comparavel(pe.name), public._nome_comparavel(cli.name),
                            -- o nome DITO, quando não há cadastro (06/10/2026)
                            case when an.fornecedor_id is null and an.favorecido_id is null and cli.id is null
                                 then public._nome_comparavel(an.nome) end], ''),
         (an.fornecedor_id is not null or an.favorecido_id is not null or cli.id is not null
          or nullif(btrim(coalesce(an.nome, '')), '') is not null)
    from public.anotacoes_do_extrato an
    left join public.suppliers f on f.id = an.fornecedor_id
    left join public.payees pe on pe.id = an.favorecido_id
    left join public.service_orders so on so.id = an.os_id and an.sentido = 'credit' and an.cliente_id is null
    left join public.clients cli on cli.id = coalesce(an.cliente_id, so.client_id)
   where an.id = p_anotacao;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._quem_da_anotacao(p_anotacao uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._quem_da_anotacao(p_anotacao uuid) TO service_role;

-- ── public._reacomodar_entrada(p_tx uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._reacomodar_entrada(p_tx uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_um uuid;
begin
  if p_tx is null then return false; end if;
  select x.id into v_um
    from public.payments x
   where x.bank_transaction_id = p_tx and x.status = 'confirmed' and x.receivable_id is not null
   order by (x.id = (select t.reconciled_payment_id from public.bank_transactions t where t.id = p_tx)) desc,
            x.created_at
   limit 1;
  if v_um is null then return false; end if;

  update public.bank_transactions set reconciled = true, reconciled_payment_id = v_um where id = p_tx;
  update public.receivables set bank_transaction_id = p_tx
   where id = (select receivable_id from public.payments where id = v_um)
     and bank_transaction_id is null
     and not exists (select 1 from public.receivables where bank_transaction_id = p_tx);
  return true;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._reacomodar_entrada(p_tx uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._reacomodar_entrada(p_tx uuid) TO service_role;

-- ── public._recusa_se_mes_fechado(p_data date, p_o_que text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._recusa_se_mes_fechado(p_data date, p_o_que text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_data is not null and public.periodo_esta_fechado(p_data) then
    raise exception 'O mês % está fechado. Reabra-o em Financeiro › Conciliação › Fechar o mês para %.',
      to_char(p_data, 'MM/YYYY'), p_o_que
      using errcode = 'check_violation';
  end if;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._recusa_se_mes_fechado(p_data date, p_o_que text) TO postgres;
GRANT EXECUTE ON FUNCTION public._recusa_se_mes_fechado(p_data date, p_o_que text) TO service_role;

-- ── public._rotulo_jornada(p_fracao numeric) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._rotulo_jornada(p_fracao numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case p_fracao when 1 then 'dia inteiro' when 0.5 then 'meio período' when 0 then 'faltou' end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._rotulo_jornada(p_fracao numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public._rotulo_jornada(p_fracao numeric) TO service_role;

-- ── public._salario_minimo_em(p_data date) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._salario_minimo_em(p_data date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tabela jsonb;
  v_valor numeric;
begin
  begin
    select value::jsonb into v_tabela from public.app_settings where key = 'salario_minimo';
    -- Só vale a chave do MESMO ano: em janeiro sem o valor novo, a separação avisa em vez de
    -- usar em silêncio o mínimo do ano anterior.
    select (e.value)::numeric into v_valor
      from jsonb_each_text(coalesce(v_tabela, '{}'::jsonb)) e
     where e.key ~ '^\d{4}-\d{2}-\d{2}$' and e.key::date <= p_data
       and left(e.key, 4) = to_char(p_data, 'YYYY')
     order by e.key::date desc
     limit 1;
  exception when others then
    return null;  -- configuração ilegível: a separação avisa e não mexe
  end;
  return round(v_valor, 2);
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._salario_minimo_em(p_data date) TO postgres;
GRANT EXECUTE ON FUNCTION public._salario_minimo_em(p_data date) TO service_role;

-- ── public._situacao_do_saldo(p_valor numeric, p_pago numeric, p_status_atual text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public._situacao_do_saldo(p_valor numeric, p_pago numeric, p_status_atual text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when coalesce(p_pago, 0) > 0 and coalesce(p_pago, 0) >= p_valor - 0.005 then 'paid'
    when coalesce(p_pago, 0) > 0 then 'partially_paid'
    when p_status_atual in ('paid', 'partially_paid') then 'pending'
    else p_status_atual
  end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._situacao_do_saldo(p_valor numeric, p_pago numeric, p_status_atual text) TO postgres;
GRANT EXECUTE ON FUNCTION public._situacao_do_saldo(p_valor numeric, p_pago numeric, p_status_atual text) TO service_role;

-- ── public._socio_com_pro_labore_pelo_minimo(p_payee uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public._socio_com_pro_labore_pelo_minimo(p_payee uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_payee is null then
    return false;
  end if;
  return exists (
    select 1
      from jsonb_array_elements_text(coalesce(
             (select value::jsonb from public.app_settings where key = 'pro_labore_pelo_salario_minimo'), '[]'::jsonb)) e
     where e.value = p_payee::text);
exception when others then
  return false;  -- configuração ilegível não pode travar a correção de lançamentos
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public._socio_com_pro_labore_pelo_minimo(p_payee uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public._socio_com_pro_labore_pelo_minimo(p_payee uuid) TO service_role;

-- ── public.ai_claude_max_disponivel() ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_claude_max_disponivel()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.ai_gateway_workers w
     where w.enabled
       and w.last_seen_at > now() - interval '45 seconds'
       and coalesce((w.estado->'providers'->'claude-local'->>'available')::boolean, false)
  );
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_claude_max_disponivel() TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_claude_max_disponivel() TO service_role;

-- ── public.ai_gateway_claim_job(p_worker_id text, p_token text, p_providers text[], p_lease_seconds integer) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_gateway_claim_job(p_worker_id text, p_token text, p_providers text[] DEFAULT NULL::text[], p_lease_seconds integer DEFAULT 120)
 RETURNS SETOF ai_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w public.ai_gateway_workers;
  v_id uuid;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  update public.ai_gateway_workers set last_seen_at = now() where id = w.id;
  perform public._ai_gateway_reap();

  select j.id into v_id
    from public.ai_jobs j
   where j.status = 'pending'
     and j.available_at <= now()
     and j.source = any (w.allowed_sources)
     and (p_providers is null or j.provider = any (p_providers))
   order by j.priority desc, j.available_at, j.created_at
   for update skip locked
   limit 1;

  if v_id is null then
    return;
  end if;

  return query
  update public.ai_jobs j set
    status = 'processing',
    worker_id = w.id,
    lease_id = gen_random_uuid(),
    lease_expires_at = now() + make_interval(secs => greatest(30, least(coalesce(p_lease_seconds, 120), 900))),
    attempts = j.attempts + 1,
    started_at = now(),
    completed_at = null,
    error = null,
    error_code = null
  where j.id = v_id
  returning j.*;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres anon=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_gateway_claim_job(p_worker_id text, p_token text, p_providers text[], p_lease_seconds integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_gateway_claim_job(p_worker_id text, p_token text, p_providers text[], p_lease_seconds integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_gateway_claim_job(p_worker_id text, p_token text, p_providers text[], p_lease_seconds integer) TO anon;

-- ── public.ai_gateway_complete_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_response jsonb, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_gateway_complete_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_response jsonb, p_provider_used text DEFAULT NULL::text, p_model_used text DEFAULT NULL::text, p_duration_ms integer DEFAULT NULL::integer, p_usage jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w public.ai_gateway_workers;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  if p_response is null or octet_length(p_response::text) > 2000000 then
    raise exception 'ai_gateway: resposta ausente ou maior que 2 MB' using errcode = '22023';
  end if;
  update public.ai_jobs j set
    status = 'completed',
    response = p_response,
    completed_at = now(),
    lease_id = null,
    lease_expires_at = null,
    error = null,
    error_code = null,
    provider_used = left(p_provider_used, 64),
    model_used = left(p_model_used, 128),
    duration_ms = p_duration_ms,
    usage = p_usage
  where j.id = p_job_id
    and j.status = 'processing'
    and j.worker_id = w.id
    and j.lease_id = p_lease_id;
  return found;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres anon=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_gateway_complete_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_response jsonb, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_gateway_complete_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_response jsonb, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_gateway_complete_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_response jsonb, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) TO anon;

-- ── public.ai_gateway_fail_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_error_code text, p_error text, p_retryable boolean, p_retry_after_seconds integer, p_count_attempt boolean, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_gateway_fail_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_error_code text, p_error text, p_retryable boolean DEFAULT false, p_retry_after_seconds integer DEFAULT 0, p_count_attempt boolean DEFAULT true, p_provider_used text DEFAULT NULL::text, p_model_used text DEFAULT NULL::text, p_duration_ms integer DEFAULT NULL::integer, p_usage jsonb DEFAULT NULL::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w public.ai_gateway_workers;
  j public.ai_jobs;
  v_status text;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  select * into j
    from public.ai_jobs x
   where x.id = p_job_id
     and x.status = 'processing'
     and x.worker_id = w.id
     and x.lease_id = p_lease_id
   for update;
  if not found then
    return 'lost';
  end if;

  v_status := case
    when j.cancel_requested_at is not null or p_error_code = 'cancelled' then 'cancelled'
    when coalesce(p_retryable, false)
         and (not coalesce(p_count_attempt, true) or j.attempts < j.max_attempts) then 'pending'
    else 'failed' end;

  update public.ai_jobs x set
    status = v_status,
    attempts = case when v_status = 'pending' and not coalesce(p_count_attempt, true)
                    then greatest(x.attempts - 1, 0) else x.attempts end,
    available_at = case when v_status = 'pending'
                        then now() + make_interval(secs => least(greatest(coalesce(p_retry_after_seconds, 0), 0), 86400))
                        else x.available_at end,
    completed_at = case when v_status = 'pending' then null else now() end,
    lease_id = null,
    lease_expires_at = null,
    error_code = left(coalesce(p_error_code, 'internal'), 64),
    error = left(p_error, 4000),
    provider_used = coalesce(left(p_provider_used, 64), x.provider_used),
    model_used = coalesce(left(p_model_used, 128), x.model_used),
    duration_ms = coalesce(p_duration_ms, x.duration_ms),
    usage = coalesce(p_usage, x.usage)
  where x.id = j.id;

  return v_status;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres anon=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_gateway_fail_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_error_code text, p_error text, p_retryable boolean, p_retry_after_seconds integer, p_count_attempt boolean, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_gateway_fail_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_error_code text, p_error text, p_retryable boolean, p_retry_after_seconds integer, p_count_attempt boolean, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_gateway_fail_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_error_code text, p_error text, p_retryable boolean, p_retry_after_seconds integer, p_count_attempt boolean, p_provider_used text, p_model_used text, p_duration_ms integer, p_usage jsonb) TO anon;

-- ── public.ai_gateway_heartbeat(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_lease_seconds integer) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_gateway_heartbeat(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_lease_seconds integer DEFAULT 120)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w public.ai_gateway_workers;
  v_cancel timestamptz;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  update public.ai_jobs j set
    lease_expires_at = now() + make_interval(secs => greatest(30, least(coalesce(p_lease_seconds, 120), 900)))
  where j.id = p_job_id
    and j.status = 'processing'
    and j.worker_id = w.id
    and j.lease_id = p_lease_id
  returning j.cancel_requested_at into v_cancel;
  if not found then
    return 'lost';
  end if;
  return case when v_cancel is not null then 'cancel' else 'ok' end;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres anon=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_gateway_heartbeat(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_lease_seconds integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_gateway_heartbeat(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_lease_seconds integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_gateway_heartbeat(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_lease_seconds integer) TO anon;

-- ── public.ai_gateway_ping(p_worker_id text, p_token text, p_version text, p_estado jsonb) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_gateway_ping(p_worker_id text, p_token text, p_version text DEFAULT NULL::text, p_estado jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w public.ai_gateway_workers;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  update public.ai_gateway_workers
     set last_seen_at = now(),
         version = coalesce(left(p_version, 64), version),
         estado = case
           when p_estado is not null and jsonb_typeof(p_estado) = 'object' and octet_length(p_estado::text) <= 4000 then p_estado
           else estado end
   where id = w.id;
  return jsonb_build_object(
    'ok', true,
    'worker_id', w.id,
    'allowed_sources', to_jsonb(w.allowed_sources),
    'server_time', now(),
    'pending', (select count(*) from public.ai_jobs j
                 where j.status = 'pending' and j.source = any (w.allowed_sources)),
    'processing', (select count(*) from public.ai_jobs j
                    where j.status = 'processing' and j.worker_id = w.id)
  );
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres anon=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_gateway_ping(p_worker_id text, p_token text, p_version text, p_estado jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_gateway_ping(p_worker_id text, p_token text, p_version text, p_estado jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_gateway_ping(p_worker_id text, p_token text, p_version text, p_estado jsonb) TO anon;

-- ── public.ai_gateway_status() ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_gateway_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Só o administrador vê o status do gateway' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'disponivel', public.ai_claude_max_disponivel(),
    'agora', now(),
    'workers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id,
               'enabled', w.enabled,
               'last_seen_at', w.last_seen_at,
               'version', w.version,
               'providers', w.estado->'providers',
               'ativos', w.estado->'ativos',
               'maximo', w.estado->'max'
             ) order by w.last_seen_at desc nulls last)
        from public.ai_gateway_workers w), '[]'::jsonb),
    'ultimos', coalesce((
      select jsonb_agg(x order by x->>'created_at' desc)
        from (
          select jsonb_build_object(
                   'tipo', j.metadata->>'tipo',
                   'status', j.status,
                   'model_used', j.model_used,
                   'duration_ms', j.duration_ms,
                   'error_code', j.error_code,
                   'created_at', j.created_at
                 ) as x
            from public.ai_jobs j
           where j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel')
           order by j.created_at desc
           limit 8
        ) u), '[]'::jsonb)
  );
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres authenticated=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_gateway_status() TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_gateway_status() TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_gateway_status() TO authenticated;

-- ── public.ai_job_cancel(p_job_id uuid) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_job_cancel(p_job_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  j public.ai_jobs;
begin
  select * into j from public.ai_jobs x where x.id = p_job_id for update;
  if not found or v_uid is null
     or (j.requested_by is distinct from v_uid and not public.is_admin(v_uid)) then
    raise exception 'ai_jobs: job não encontrado' using errcode = 'P0002';
  end if;

  if j.status = 'pending' then
    update public.ai_jobs x set
      status = 'cancelled', cancel_requested_at = now(), completed_at = now(),
      error_code = 'cancelled', error = 'Cancelado antes de começar.'
    where x.id = j.id;
    return 'cancelled';
  elsif j.status = 'processing' then
    update public.ai_jobs x set cancel_requested_at = coalesce(x.cancel_requested_at, now())
    where x.id = j.id;
    return 'cancelling';
  end if;
  return j.status;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres authenticated=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_job_cancel(p_job_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_job_cancel(p_job_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_job_cancel(p_job_id uuid) TO authenticated;

-- ── public.ai_job_marcar_entregue(p_job_id uuid) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_job_marcar_entregue(p_job_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.ai_jobs j
     set metadata = j.metadata || jsonb_build_object('entregue_em', now())
   where j.id = p_job_id
     and j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel')
     and j.status in ('completed', 'failed', 'cancelled')
     and not (j.metadata ? 'entregue_em');
  return found;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_job_marcar_entregue(p_job_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_job_marcar_entregue(p_job_id uuid) TO service_role;

-- ── public.ai_job_painel_desistir(p_job_id uuid) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_job_painel_desistir(p_job_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.ai_jobs j
     set metadata = j.metadata || jsonb_build_object('painel_tarde', true)
   where j.id = p_job_id
     and j.metadata->>'tipo' = 'agente_painel'
     and j.status in ('pending', 'processing');
  return found;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_job_painel_desistir(p_job_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_job_painel_desistir(p_job_id uuid) TO service_role;

-- ── public.ai_job_registrar_ferramenta(p_job_id uuid, p_nome text, p_interrupcao jsonb) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_job_registrar_ferramenta(p_job_id uuid, p_nome text, p_interrupcao jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  atual jsonb;
  novo jsonb;
begin
  select j.metadata into atual
    from public.ai_jobs j
   where j.id = p_job_id and j.status = 'processing'
     and j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel', 'agente_ensaio')
   for update;
  if not found then
    return false;
  end if;

  novo := atual;
  -- A interrupção (pendência/opções) é o que importa: a primeira vence, e nunca fica de fora.
  if p_interrupcao is not null and jsonb_typeof(p_interrupcao) = 'object' and not (atual ? 'interrupcao') then
    novo := novo || jsonb_build_object('interrupcao', p_interrupcao);
  end if;
  -- A lista de ferramentas é diagnóstico: entra só se couber no limite do metadata.
  if octet_length((novo || jsonb_build_object('ferramentas_usadas',
        coalesce(novo->'ferramentas_usadas', '[]'::jsonb) || to_jsonb(left(coalesce(p_nome, ''), 80))))::text) <= 18000 then
    novo := novo || jsonb_build_object('ferramentas_usadas',
              coalesce(novo->'ferramentas_usadas', '[]'::jsonb) || to_jsonb(left(coalesce(p_nome, ''), 80)));
  end if;

  update public.ai_jobs j set metadata = novo where j.id = p_job_id;
  return novo ? 'interrupcao';
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_job_registrar_ferramenta(p_job_id uuid, p_nome text, p_interrupcao jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_job_registrar_ferramenta(p_job_id uuid, p_nome text, p_interrupcao jsonb) TO service_role;

-- ── public.ai_job_submit(p_prompt text, p_model text, p_provider text, p_system_prompt text, p_input jsonb, p_response_format text, p_json_schema jsonb, p_task_profile text, p_priority integer, p_timeout_seconds integer, p_max_attempts integer, p_allow_fallback boolean, p_deadline_at timestamp with time zone, p_metadata jsonb) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_job_submit(p_prompt text, p_model text DEFAULT 'sonnet'::text, p_provider text DEFAULT 'claude-local'::text, p_system_prompt text DEFAULT NULL::text, p_input jsonb DEFAULT NULL::jsonb, p_response_format text DEFAULT 'text'::text, p_json_schema jsonb DEFAULT NULL::jsonb, p_task_profile text DEFAULT 'text'::text, p_priority integer DEFAULT 0, p_timeout_seconds integer DEFAULT 300, p_max_attempts integer DEFAULT 3, p_allow_fallback boolean DEFAULT false, p_deadline_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'ai_jobs: só o administrador do MarineFlow pode criar jobs de IA' using errcode = '42501';
  end if;
  -- trava contra laço no app: um bug não pode encher a fila
  if (select count(*) from public.ai_jobs j
       where j.requested_by = v_uid and j.status in ('pending', 'processing')) >= 50 then
    raise exception 'ai_jobs: já existem 50 jobs abertos deste usuário' using errcode = '54000';
  end if;

  insert into public.ai_jobs (
    source, requested_by, provider, model, system_prompt, prompt, input,
    response_format, json_schema, task_profile, priority, timeout_seconds,
    max_attempts, allow_fallback, deadline_at, metadata
  ) values (
    'marineflow', v_uid,
    coalesce(p_provider, 'claude-local'), coalesce(p_model, 'sonnet'),
    p_system_prompt, p_prompt, p_input,
    coalesce(p_response_format, 'text'), p_json_schema, coalesce(p_task_profile, 'text'),
    coalesce(p_priority, 0), coalesce(p_timeout_seconds, 300),
    coalesce(p_max_attempts, 3), coalesce(p_allow_fallback, false),
    p_deadline_at, coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres authenticated=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_job_submit(p_prompt text, p_model text, p_provider text, p_system_prompt text, p_input jsonb, p_response_format text, p_json_schema jsonb, p_task_profile text, p_priority integer, p_timeout_seconds integer, p_max_attempts integer, p_allow_fallback boolean, p_deadline_at timestamp with time zone, p_metadata jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_job_submit(p_prompt text, p_model text, p_provider text, p_system_prompt text, p_input jsonb, p_response_format text, p_json_schema jsonb, p_task_profile text, p_priority integer, p_timeout_seconds integer, p_max_attempts integer, p_allow_fallback boolean, p_deadline_at timestamp with time zone, p_metadata jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_job_submit(p_prompt text, p_model text, p_provider text, p_system_prompt text, p_input jsonb, p_response_format text, p_json_schema jsonb, p_task_profile text, p_priority integer, p_timeout_seconds integer, p_max_attempts integer, p_allow_fallback boolean, p_deadline_at timestamp with time zone, p_metadata jsonb) TO authenticated;

-- ── public.ai_op_can_approve(_user_id uuid, _action text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.ai_op_can_approve(_user_id uuid, _action text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_active boolean;
begin
  select role, active into v_role, v_active
  from public.app_users where id = _user_id;
  if v_role is null or v_active is not true then return false; end if;

  -- Governança de memória técnica: admin OU technician.
  if _action in ('verify_memory_note', 'reject_memory_note') then
    return v_role in ('admin', 'technician');
  end if;

  -- Macro Ciclo 1 — qualquer outra ação pendente: somente admin.
  return v_role = 'admin';
end;
$function$
;
COMMENT ON FUNCTION public.ai_op_can_approve(_user_id uuid, _action text) IS 'MarineFlow AI Operator — Macro Ciclo 1 restritivo: somente admin aprova ações operacionais; admin/technician validam memória técnica.';
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_op_can_approve(_user_id uuid, _action text) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_op_can_approve(_user_id uuid, _action text) TO service_role;

-- ── public.ai_op_can_reject(_user_id uuid, _pending_action_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.ai_op_can_reject(_user_id uuid, _pending_action_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_active boolean;
  v_requested_by uuid;
  v_action text;
begin
  select role, active into v_role, v_active
  from public.app_users where id = _user_id;
  if v_role is null or v_active is not true then return false; end if;

  select requested_by_user_id, action_name into v_requested_by, v_action
  from public.ai_operator_pending_actions where id = _pending_action_id;
  if v_requested_by is null then return false; end if;

  -- external_seller nunca participa de governança de pending actions do operator.
  if v_role = 'external_seller' then return false; end if;

  -- Memória técnica: aplica a mesma matriz de approve (admin/technician).
  if v_action in ('verify_memory_note', 'reject_memory_note') then
    return v_role in ('admin', 'technician');
  end if;

  -- Demais ações: admin OU o próprio solicitante.
  return v_role = 'admin' or v_requested_by = _user_id;
end;
$function$
;
COMMENT ON FUNCTION public.ai_op_can_reject(_user_id uuid, _pending_action_id uuid) IS 'MarineFlow AI Operator — Macro Ciclo 1: rejeição permitida ao solicitante da ação ou a um admin ativo.';
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_op_can_reject(_user_id uuid, _pending_action_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_op_can_reject(_user_id uuid, _pending_action_id uuid) TO service_role;

-- ── public.ai_op_protect_pending_action() ── [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_op_protect_pending_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- Bloqueia UPDATE em campos imutáveis após criação.
  if TG_OP = 'UPDATE' then
    if NEW.action_name is distinct from OLD.action_name
       or NEW.risk_level is distinct from OLD.risk_level
       or NEW.payload is distinct from OLD.payload
       or NEW.requested_by_user_id is distinct from OLD.requested_by_user_id
       or NEW.session_id is distinct from OLD.session_id
       or NEW.draft_id is distinct from OLD.draft_id
       or NEW.created_at is distinct from OLD.created_at then
      raise exception 'ai_operator_pending_actions: campos imutáveis não podem ser alterados (action_name, risk_level, payload, requested_by, session_id, draft_id, created_at)';
    end if;

    -- Transições válidas:
    --   pending -> approved | rejected | expired
    --   approved -> executed | failed
    if OLD.status = 'pending' and NEW.status not in ('pending', 'approved', 'rejected', 'expired') then
      raise exception 'ai_operator_pending_actions: transição inválida % -> %', OLD.status, NEW.status;
    end if;
    if OLD.status = 'approved' and NEW.status not in ('approved', 'executed', 'failed') then
      raise exception 'ai_operator_pending_actions: transição inválida % -> %', OLD.status, NEW.status;
    end if;
    if OLD.status in ('rejected', 'executed', 'failed', 'expired')
       and NEW.status is distinct from OLD.status then
      raise exception 'ai_operator_pending_actions: estado terminal não pode mudar (% -> %)', OLD.status, NEW.status;
    end if;
  end if;
  return NEW;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_op_protect_pending_action() TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_op_protect_pending_action() TO service_role;

-- ── public.ai_orcamento_tecnico_criar_rascunho(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_orcamento_tecnico_criar_rascunho(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_ja uuid;
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Só o administrador pode criar rascunho a partir da IA' using errcode = '42501';
  end if;
  -- Já criado: devolve o existente sem gastar número.
  select nullif(x.metadata->'rascunhos'->>(p_indice::text), '')::uuid into v_ja
    from public.ai_jobs x where x.id = p_job_id;
  if v_ja is not null and exists (select 1 from public.service_orders so where so.id = v_ja) then
    return public._ai_orcamento_tecnico_montar(p_job_id, p_indice, p_client_id, p_vessel_id, null, v_uid);
  end if;
  return public._ai_orcamento_tecnico_montar(
    p_job_id, p_indice, p_client_id, p_vessel_id,
    'ORÇ-' || lpad(public.next_document_number()::text, 5, '0'), v_uid);
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres authenticated=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_criar_rascunho(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_criar_rascunho(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_criar_rascunho(p_job_id uuid, p_indice integer, p_client_id uuid, p_vessel_id uuid) TO authenticated;

-- ── public.ai_orcamento_tecnico_pacote() ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_orcamento_tecnico_pacote()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with produtos as (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'produto_id', p.id, 'nome', p.name, 'sku', p.sku, 'marca', p.brand,
      'categoria', coalesce(pc.name, p.category), 'unidade', p.unit,
      'custo_cadastro', nullif(p.cost_price, 0), 'venda_cadastro', nullif(p.sale_price, 0),
      'cadastro_atualizado_em', to_char(p.updated_at, 'YYYY-MM-DD'),
      'fornecedor', s.name,
      'ultimo_custo_nf', (select jsonb_build_object('valor', h.new_cost, 'data', to_char(h.created_at, 'YYYY-MM-DD'))
                            from public.product_price_history h
                           where h.product_id = p.id and h.new_cost > 0 order by h.created_at desc limit 1),
      'ultima_compra_oc', (select jsonb_build_object('valor', i.unit_cost, 'data', to_char(i.created_at, 'YYYY-MM-DD'))
                             from public.purchase_order_items i
                            where i.product_id = p.id and i.unit_cost > 0 order by i.created_at desc limit 1),
      'ultimo_orcamento', (select jsonb_strip_nulls(jsonb_build_object('numero', so.service_order_number,
                                    'custo', nullif(sp.unit_cost_snapshot, 0), 'venda', nullif(sp.unit_sale_snapshot, 0),
                                    'data', to_char(sp.created_at, 'YYYY-MM-DD')))
                             from public.service_order_parts sp
                             join public.service_orders so on so.id = sp.service_order_id
                            where sp.product_id = p.id order by sp.created_at desc limit 1)
    )) order by p.name) as v
      from public.products p
      left join public.suppliers s on s.id = p.supplier_id
      left join public.product_categories pc on pc.id = p.product_category_id
     where p.active
  ),
  servicos as (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'servico_id', sv.id, 'nome', sv.name, 'descricao', nullif(left(sv.description, 140), ''),
      'categoria', sv.category, 'unidade_cobranca', sv.billing_unit,
      'preco_padrao', nullif(sv.default_price, 0), 'minutos_padrao', sv.standard_minutes
    )) order by sv.name) as v
      from public.services sv
     where sv.active
  ),
  recentes as (
    select so.* from public.service_orders so
     where exists (select 1 from public.service_order_parts sp where sp.service_order_id = so.id)
     order by so.created_at desc limit 12
  ),
  orcamentos as (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'numero', so.service_order_number, 'data', to_char(so.created_at, 'YYYY-MM-DD'),
      'status', coalesce(so.quote_status, so.status), 'total_geral', so.grand_total,
      'descricao', nullif(left(so.problem_description, 200), ''),
      'pecas', (select jsonb_agg(jsonb_build_object('item', p.name, 'qtd', sp.quantity,
                                                    'custo_unit', sp.unit_cost_snapshot, 'venda_unit', sp.unit_sale_snapshot)
                                 order by sp.created_at)
                  from public.service_order_parts sp join public.products p on p.id = sp.product_id
                 where sp.service_order_id = so.id),
      'servicos', (select jsonb_agg(jsonb_build_object('servico', ss.name_snapshot, 'qtd', ss.quantity,
                                                       'unidade', ss.billing_unit_snapshot, 'preco_unit', ss.unit_price_snapshot)
                                    order by ss.created_at)
                     from public.service_order_services ss where ss.service_order_id = so.id)
    )) order by so.created_at desc) as v
      from recentes so
  ),
  margem as (
    select jsonb_build_object(
      'markup_mediano', round((percentile_cont(0.5) within group (order by sp.unit_sale_snapshot / sp.unit_cost_snapshot))::numeric, 3),
      'markup_p25', round((percentile_cont(0.25) within group (order by sp.unit_sale_snapshot / sp.unit_cost_snapshot))::numeric, 3),
      'markup_p75', round((percentile_cont(0.75) within group (order by sp.unit_sale_snapshot / sp.unit_cost_snapshot))::numeric, 3),
      'linhas_consideradas', count(*),
      'periodo', 'orçamentos e OS dos últimos 12 meses'
    ) as v
      from public.service_order_parts sp
     where sp.unit_cost_snapshot > 0 and sp.unit_sale_snapshot > 0
       and sp.created_at > now() - interval '12 months'
  )
  select jsonb_build_object(
    'data_de_referencia', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'),
    'configuracoes_de_preco', (select jsonb_object_agg(key, value) from public.app_settings
                                where key in ('default_profit_margin', 'default_hourly_rate', 'simples_aliquota', 'default_commission_rate')),
    'margem_praticada', (select v from margem),
    'margem_por_categoria', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                'categoria', c.name, 'margem_pct', c.default_profit_margin,
                                'comissao_pct', c.default_commission_rate, 'comissionavel', c.is_commissionable)) order by c.name)
                               from public.product_categories c where c.active),
    'produtos', coalesce((select v from produtos), '[]'::jsonb),
    'servicos', coalesce((select v from servicos), '[]'::jsonb),
    'orcamentos_recentes', coalesce((select v from orcamentos), '[]'::jsonb)
  );
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_pacote() TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_pacote() TO service_role;

-- ── public.ai_orcamento_tecnico_solicitar(p_pedido text, p_modelo text) ── SECURITY DEFINER [search_path=""]
CREATE OR REPLACE FUNCTION public.ai_orcamento_tecnico_solicitar(p_pedido text, p_modelo text DEFAULT 'opus'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Só o administrador pode pedir orçamento técnico com IA' using errcode = '42501';
  end if;
  if p_pedido is null or char_length(btrim(p_pedido)) < 15 then
    raise exception 'Descreva o serviço com mais detalhes (mínimo de 15 caracteres)' using errcode = '22023';
  end if;
  if coalesce(p_modelo, 'opus') not in ('haiku', 'sonnet', 'opus') then
    raise exception 'Modelo inválido: use sonnet ou opus' using errcode = '22023';
  end if;

  return public.ai_job_submit(
    p_prompt => btrim(p_pedido),
    p_model => coalesce(p_modelo, 'opus'),
    p_system_prompt =>
      'Você é o orçamentista técnico sênior da HBR Systems (sistemas elétricos e eletrônicos de embarcações e motorhomes). '
      || 'Monte o(s) orçamento(s) pedido(s) usando o pacote <dados_de_entrada> (catálogo de produtos e serviços, histórico de custos, orçamentos recentes e regras de preço). Regras inegociáveis: '
      || '(1) use SOMENTE valores presentes nos dados; em cada item cite a origem exata (cadastro, NF, ordem de compra ou número do orçamento) e a data. '
      || '(2) Item do catálogo leva o produto_id ou servico_id EXATAMENTE como está nos dados; item que não está no catálogo leva id null e provisorio=true. '
      || '(3) Custo ou venda ausente não é zero: sem valor exato, use o item mais semelhante, estime com coerência e marque provisorio=true com a observação "Valor provisório — aguardando cotação do fornecedor". '
      || '(4) Siga exatamente o que o pedido incluir ou excluir; não misture itens nem valores entre orçamentos diferentes. '
      || '(5) As contas precisam fechar: total_venda = quantidade × preco_venda_unitario, e o resumo soma os itens. O preco_venda_unitario é o preço FINAL da linha: o sistema não soma imposto nem comissão por cima. '
      || '(6) Margem: se o pedido não definir, use a margem praticada (markup_mediano) e explique; se o preço de venda do cadastro for bem menor que o resultado, aponte isso em perguntas_pendentes. '
      || '(7) Dimensione com critério técnico (bitolas, proteções, normas) e registre as premissas. '
      || '(8) O que faltar para fechar o orçamento vai em perguntas_pendentes — nunca invente. Responda em português do Brasil.',
    p_input => public.ai_orcamento_tecnico_pacote(),
    p_response_format => 'json_schema',
    p_json_schema => jsonb_build_object(
      'type', 'object', 'additionalProperties', false,
      'required', jsonb_build_array('premissas_tecnicas', 'margem_adotada', 'orcamentos', 'perguntas_pendentes'),
      'properties', jsonb_build_object(
        'premissas_tecnicas', jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string')),
        'margem_adotada', jsonb_build_object('type', 'object', 'additionalProperties', false,
          'required', jsonb_build_array('criterio', 'markup'),
          'properties', jsonb_build_object('criterio', jsonb_build_object('type', 'string'), 'markup', jsonb_build_object('type', 'number'))),
        'perguntas_pendentes', jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string')),
        'orcamentos', jsonb_build_object('type', 'array', 'minItems', 1, 'maxItems', 4, 'items', jsonb_build_object(
          'type', 'object', 'additionalProperties', false,
          'required', jsonb_build_array('titulo', 'itens', 'resumo', 'observacoes_valores_provisorios'),
          'properties', jsonb_build_object(
            'titulo', jsonb_build_object('type', 'string'),
            'observacoes_valores_provisorios', jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string')),
            'resumo', jsonb_build_object('type', 'object', 'additionalProperties', false,
              'required', jsonb_build_array('custo_estimado', 'margem_aplicada_pct', 'total_materiais_e_equipamentos', 'total_mao_de_obra', 'total_geral'),
              'properties', jsonb_build_object(
                'custo_estimado', jsonb_build_object('type', 'number'),
                'margem_aplicada_pct', jsonb_build_object('type', 'number'),
                'total_materiais_e_equipamentos', jsonb_build_object('type', 'number'),
                'total_mao_de_obra', jsonb_build_object('type', 'number'),
                'total_geral', jsonb_build_object('type', 'number'))),
            'itens', jsonb_build_object('type', 'array', 'items', jsonb_build_object(
              'type', 'object', 'additionalProperties', false,
              'required', jsonb_build_array('tipo', 'descricao', 'produto_id', 'servico_id', 'quantidade', 'unidade',
                                            'custo_unitario', 'origem_do_custo', 'data_do_custo', 'provisorio',
                                            'preco_venda_unitario', 'total_venda'),
              'properties', jsonb_build_object(
                'tipo', jsonb_build_object('type', 'string', 'enum', jsonb_build_array('equipamento', 'material', 'mao_de_obra')),
                'descricao', jsonb_build_object('type', 'string'),
                'produto_id', jsonb_build_object('type', jsonb_build_array('string', 'null')),
                'servico_id', jsonb_build_object('type', jsonb_build_array('string', 'null')),
                'quantidade', jsonb_build_object('type', 'number'),
                'unidade', jsonb_build_object('type', 'string'),
                'custo_unitario', jsonb_build_object('type', 'number'),
                'origem_do_custo', jsonb_build_object('type', 'string'),
                'data_do_custo', jsonb_build_object('type', jsonb_build_array('string', 'null')),
                'provisorio', jsonb_build_object('type', 'boolean'),
                'preco_venda_unitario', jsonb_build_object('type', 'number'),
                'total_venda', jsonb_build_object('type', 'number'))))))))),
    p_timeout_seconds => 900,
    p_max_attempts => 2,
    p_metadata => jsonb_build_object('tipo', 'orcamento_tecnico', 'versao', 1)
  );
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres authenticated=X/postgres
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_solicitar(p_pedido text, p_modelo text) TO postgres;
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_solicitar(p_pedido text, p_modelo text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ai_orcamento_tecnico_solicitar(p_pedido text, p_modelo text) TO authenticated;

-- ── public.ajustar_ao_valor_do_banco(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.ajustar_ao_valor_do_banco(p_tipo text, p_id uuid, p_motivo text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  r public.receivables%rowtype;
  t public.bank_transactions%rowtype;
  v_pagamento public.payments%rowtype;
  v_pagamentos integer;
  v_outras integer;
  v_banco numeric;
  v_dif numeric;
  v_msg text;
  v_nota text;
begin
  if p_tipo <> 'receivable' then
    raise exception 'O ajuste ao valor do banco vale para conta a receber. Numa conta a pagar, desfaça a aprovação e aprove de novo com o valor certo.';
  end if;

  select * into r from public.receivables where id = p_id for update;
  if not found then raise exception 'Lançamento não encontrado.'; end if;
  if r.status = 'cancelled' then raise exception 'Este lançamento está cancelado.'; end if;
  if r.bank_transaction_id is null then
    raise exception 'Este lançamento não está ligado a nenhuma linha do extrato: não há valor do banco para seguir.';
  end if;
  perform public._recusa_se_mes_fechado(r.issue_date, 'ajustar este lançamento ao valor do banco');

  select * into t from public.bank_transactions where id = r.bank_transaction_id;
  v_banco := abs(t.amount);

  -- A entrada também paga outra conta: o valor dela não é desta conta sozinha (F2, 02/10/2026).
  select count(distinct x.receivable_id) into v_outras
    from public.payments x
   where x.bank_transaction_id = t.id and x.status = 'confirmed'
     and x.receivable_id is not null and x.receivable_id <> r.id;
  if v_outras > 0 then
    raise exception 'Esta entrada de % também paga % outra(s) conta(s): ajustar esta conta ao valor inteiro dela contaria o mesmo dinheiro duas vezes. Para o que sobrou da entrada, use "Este Pix paga…".',
      public._brl(v_banco), v_outras;
  end if;

  -- Só o caso inequívoco: UM pagamento confirmado, e é o que a linha do banco registrou.
  select count(*) into v_pagamentos from public.payments where receivable_id = r.id and status = 'confirmed';
  select * into v_pagamento from public.payments
   where id = t.reconciled_payment_id and receivable_id = r.id and status = 'confirmed';
  if v_pagamentos <> 1 or v_pagamento.id is null then
    raise exception 'Este lançamento tem % pagamento(s) e nem todos vieram desta linha do banco. Confira os pagamentos antes: ajustar aqui apagaria a diferença sem saber de onde ela vem.',
      v_pagamentos;
  end if;

  v_dif := round(v_banco - r.amount, 2);
  if abs(v_dif) < 0.005 and abs(v_pagamento.amount - v_banco) < 0.005 then
    raise exception 'O lançamento já bate com o banco (%).', public._brl(v_banco);
  end if;

  v_msg := case
    when v_dif > 0 then 'Ajustado ao banco: o cliente pagou ' || public._brl(v_dif) || ' a mais; o lançamento passou de '
                        || public._brl(r.amount) || ' para ' || public._brl(v_banco) || '.'
    when v_dif < 0 then 'Ajustado ao banco: ' || public._brl(-v_dif) || ' deixam de ser cobrados (desconto); o lançamento passou de '
                        || public._brl(r.amount) || ' para ' || public._brl(v_banco) || '.'
    else 'Ajustado ao banco: o pagamento passou a ' || public._brl(v_banco) || '.'
  end;
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] ' || v_msg
            || coalesce(' Motivo: ' || nullif(btrim(p_motivo), '') || '.', '');

  -- O líquido acompanha quando era igual ao valor (Pix, transferência); com taxa de cartão ele
  -- é outro número e fica como está.
  update public.payments
     set amount = v_banco,
         net_amount = case when net_amount is null or round(net_amount, 2) = round(amount, 2) then v_banco else net_amount end
   where id = v_pagamento.id;
  update public.receivables
     set amount = v_banco, paid_amount = v_banco, balance_amount = 0, status = 'paid',
         notes = btrim(coalesce(notes, '') || ' ' || v_nota)
   where id = r.id;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, antes, depois)
  values ('ajustou_ao_banco', v_autor, t.id, r.id, v_banco,
          left(coalesce(nullif(btrim(p_motivo), ''), v_msg) || ' · ' || coalesce(r.description, ''), 300),
          jsonb_build_object('amount', r.amount, 'paid_amount', r.paid_amount, 'status', r.status, 'pagamento', v_pagamento.amount),
          jsonb_build_object('amount', v_banco, 'paid_amount', v_banco, 'status', 'paid', 'pagamento', v_banco));

  return jsonb_build_object('ok', true, 'antes', r.amount, 'depois', v_banco, 'diferenca', v_dif, 'message', v_msg);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ajustar_ao_valor_do_banco(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ajustar_ao_valor_do_banco(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ajustar_ao_valor_do_banco(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO service_role;

-- ── public.ajustar_caixa(p_saldo_contado numeric, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.ajustar_caixa(p_saldo_contado numeric, p_motivo text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_atual numeric := public.saldo_do_caixa();
  v_dif numeric;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if p_saldo_contado is null or p_saldo_contado < 0 then raise exception 'Informe quanto dinheiro há no caixa agora.'; end if;
  if v_motivo is null then raise exception 'Diga o motivo do ajuste (ex.: contagem de sexta).'; end if;
  v_dif := round(p_saldo_contado - v_atual, 2);
  if v_dif = 0 then
    insert into public.reconciliation_log (acao, autor, valor, detalhe, antes, depois)
    values ('contou_caixa', v_autor, 0, left('Contagem bateu: ' || v_motivo, 300),
            jsonb_build_object('saldo', v_atual), jsonb_build_object('saldo', p_saldo_contado));
    return jsonb_build_object('ok', true, 'diferenca', 0, 'saldo_do_caixa', v_atual, 'message', 'O Caixa já bate com a contagem.');
  end if;
  perform public._linha_do_caixa(case when v_dif > 0 then 'credit' else 'debit' end, abs(v_dif), public._hoje_brt(),
                                 'Ajuste pela contagem: ' || v_motivo, null, 'ajuste_caixa', 'Ajuste pela contagem: ' || v_motivo, v_autor);
  insert into public.reconciliation_log (acao, autor, valor, detalhe, antes, depois)
  values ('ajustou_caixa', v_autor, v_dif, left('Contagem: ' || v_motivo, 300),
          jsonb_build_object('saldo', v_atual), jsonb_build_object('saldo', p_saldo_contado));
  return jsonb_build_object('ok', true, 'diferenca', v_dif, 'saldo_do_caixa', public.saldo_do_caixa(),
    'message', case when v_dif > 0 then 'Sobrou ' else 'Faltou ' end || public._brl(abs(v_dif))
               || ' em relação ao sistema. Caixa ajustado para ' || public._brl(p_saldo_contado) || '.');
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ajustar_caixa(p_saldo_contado numeric, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ajustar_caixa(p_saldo_contado numeric, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ajustar_caixa(p_saldo_contado numeric, p_motivo text, p_autor uuid) TO service_role;

-- ── public.ajustar_estoque(p_produto uuid, p_nova_quantidade numeric, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.ajustar_estoque(p_produto uuid, p_nova_quantidade numeric, p_motivo text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_atual numeric;
  v_delta numeric;
  v_mov uuid;
  v_autor record;
begin
  if p_nova_quantidade is null or p_nova_quantidade < 0 then
    raise exception 'Informe a quantidade contada (zero ou mais).';
  end if;
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Informe o motivo do ajuste.';
  end if;

  perform 1 from public.products where id = p_produto for update;
  if not found then
    raise exception 'Produto não encontrado.';
  end if;

  select coalesce(sum(quantity_delta), 0) into v_atual
    from public.inventory_movements where product_id = p_produto;
  v_delta := p_nova_quantidade - v_atual;
  if v_delta = 0 then
    return jsonb_build_object('ok', true, 'anterior', v_atual, 'nova', p_nova_quantidade, 'delta', 0);
  end if;

  select * into v_autor from private.estoque_autor(p_autor);
  insert into public.inventory_movements
    (product_id, movement_type, quantity_delta, reference_type, notes, created_by, adjusted_by)
  values
    (p_produto, 'manual_adjustment', v_delta, 'manual_adjustment', btrim(p_motivo), v_autor.id, v_autor.nome)
  returning id into v_mov;

  return jsonb_build_object('ok', true, 'anterior', v_atual, 'nova', p_nova_quantidade,
                            'delta', v_delta, 'movimento_id', v_mov);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ajustar_estoque(p_produto uuid, p_nova_quantidade numeric, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ajustar_estoque(p_produto uuid, p_nova_quantidade numeric, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ajustar_estoque(p_produto uuid, p_nova_quantidade numeric, p_motivo text, p_autor uuid) TO service_role;

-- ── public.anotar_transacao(p_sentido text, p_valor numeric, p_data date, p_documento text, p_nome text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_categoria text, p_os_id uuid, p_descricao text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.anotar_transacao(p_sentido text, p_valor numeric, p_data date DEFAULT NULL::date, p_documento text DEFAULT NULL::text, p_nome text DEFAULT NULL::text, p_fornecedor_id uuid DEFAULT NULL::uuid, p_favorecido_id uuid DEFAULT NULL::uuid, p_cliente_id uuid DEFAULT NULL::uuid, p_categoria text DEFAULT NULL::text, p_os_id uuid DEFAULT NULL::uuid, p_descricao text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_id uuid;
  v_proposta uuid;
  v_candidatas integer;
  v_outros text;
  v_diz_quem boolean;
  v_doc text := nullif(regexp_replace(coalesce(p_documento, ''), '\D', '', 'g'), '');
  v_valor text := translate(to_char(p_valor, 'FM999,999,990.00'), ',.', '.,');
  v_lancada record;
  v_substituidas integer := 0;
  v_aviso text := '';
begin
  if p_sentido not in ('saida', 'entrada') then raise exception 'Sentido inválido: % (saida ou entrada).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  if v_doc is not null and length(v_doc) not in (11, 14) then raise exception 'CPF tem 11 dígitos e CNPJ tem 14.'; end if;
  if p_categoria is null and p_fornecedor_id is null and p_favorecido_id is null and p_cliente_id is null and p_os_id is null then
    raise exception 'Diga o que classificar: fornecedor, favorecido, cliente, categoria ou OS.';
  end if;

  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, documento, nome, fornecedor_id, favorecido_id,
                                           cliente_id, categoria, os_id, descricao, criada_por)
  values (case when p_sentido = 'saida' then 'debit' else 'credit' end, round(p_valor, 2), coalesce(p_data, public._hoje_brt()),
          p_data is not null,
          v_doc, nullif(btrim(coalesce(p_nome, '')), ''), p_fornecedor_id, p_favorecido_id, p_cliente_id,
          nullif(btrim(coalesce(p_categoria, '')), ''), p_os_id, nullif(btrim(coalesce(p_descricao, '')), ''), v_autor)
  returning id into v_id;
  select q_diz_quem into v_diz_quem from public._quem_da_anotacao(v_id);

  -- 0. A mesma coisa dita de novo (mesma pessoa, valor e dias): a nova substitui a anterior.
  update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
         motivo_cancelamento = 'substituída por uma anotação nova igual (mesma pessoa, valor e dias)'
   where id in (select public._anotacoes_repetidas_esperando(v_id));
  get diagnostics v_substituidas = row_count;
  if v_substituidas > 0 then
    v_aviso := 'Troquei a anotação anterior igual (mesma pessoa e valor) por esta. Se eram dois pagamentos diferentes, '
      || 'classifique pela tela quando chegarem. ';
  end if;

  -- 1. Uma linha que PODE ser esta já foi anotada: é repetição ou correção do que foi dito.
  --    Troca se faz pela tela — e nunca na outra linha, por eliminação.
  if public._janela_tem_linha_anotada(v_id) then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = 'a transação já tinha uma anotação; troca se faz pela tela'
     where id = v_id;
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'ja_anotada', true,
      'message', format('A transação de R$ %s desses dias já foi anotada antes. Para trocar o que foi dito, '
        || 'corrija a linha pela tela do Extrato.', v_valor));
  end if;

  -- 2. Já chegou do banco e está na fila? Aplica agora — se for UMA transação só, e se nenhuma
  --    outra anotação sua estiver esperando essa mesma transação.
  v_proposta := public._proposta_da_anotacao(v_id);
  if v_proposta is not null and exists (select 1 from public._anotacoes_em_disputa(v_id)) then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = 'outra anotação esperava a mesma transação; qual é de qual é pergunta'
     where id = v_id or id in (select public._anotacoes_em_disputa(v_id));
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'disputa', true,
      'message', format('Já havia outra anotação sua esperando uma transação de R$ %s nesses dias. Para não trocar uma '
        || 'pela outra, não apliquei nenhuma das duas: classifique pela tela ou me diga o CPF/CNPJ de cada uma.', v_valor));
  end if;
  if v_proposta is not null then
    perform public._aplicar_anotacao(v_id, v_proposta);
    return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', true, 'proposta_id', v_proposta, 'substituidas', v_substituidas,
      'message', v_aviso || 'A transação já tinha chegado do banco: a linha do Extrato foi classificada como você disse. Falta aprovar.');
  end if;

  -- 3. Mais de uma serve: pergunta, e não fica esperando para cair na que sobrar.
  select count(*) into v_candidatas from public._candidatas_da_anotacao(v_id);
  if v_candidatas > 1 then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = format('%s transações do mesmo valor nesses dias', v_candidatas)
     where id = v_id;
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'ambigua', true, 'candidatas', v_candidatas,
      'message', format('Há %s transações de R$ %s nesses dias na fila do Extrato. Não anotei para não errar: '
        || 'diga o dia exato ou o CPF/CNPJ de quem recebeu e eu anoto de novo — ou classifique pela tela.', v_candidatas, v_valor));
  end if;

  -- 4. Já chegou E já virou lançamento — e é ESTA (mesma identidade)? Então é correção.
  select coalesce(p.id, r.id) id, case when p.id is not null then 'payable' else 'receivable' end tipo into v_lancada
    from public.anotacoes_do_extrato a
    join public.bank_transactions t on t.transaction_type = a.sentido
     and abs(t.amount - a.valor) < 0.01
     and t.transaction_date between a.data_prevista - case when a.data_exata then 1 else 3 end
                                and a.data_prevista + case when a.data_exata then 1 else 7 end
    left join public.payables p on p.bank_transaction_id = t.id and p.status <> 'cancelled'
    left join public.receivables r on r.bank_transaction_id = t.id and r.status <> 'cancelled'
   where a.id = v_id
     and coalesce(p.id, r.id) is not null
     and public._identidade_serve(v_id, t.id, p.supplier_id, p.payee_id, r.client_id)
   limit 1;
  if v_lancada.id is not null then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = 'a transação já foi lançada'
     where id = v_id;
    return jsonb_build_object('ok', false, 'ja_lancada', true, 'lancamento_id', v_lancada.id, 'tipo', v_lancada.tipo,
      'message', 'Essa transação já chegou e já foi lançada. Para mudar fornecedor ou categoria, corrija o lançamento.');
  end if;

  -- 5. Outra anotação sua já espera o mesmo dinheiro sem nada que as separe: são DOIS
  --    pagamentos iguais, e quando chegarem não haverá como saber qual é qual. As duas saem.
  if exists (select 1 from public._anotacoes_gemeas_esperando(v_id)) then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = 'duas anotações do mesmo valor nos mesmos dias; diga de novo com o CPF/CNPJ de cada uma'
     where id = v_id or id in (select public._anotacoes_gemeas_esperando(v_id));
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'gemea', true,
      'message', format('Já havia outra anotação sua esperando uma transação de R$ %s nesses dias. Para eu saber qual é '
        || 'qual quando chegarem, cancelei as duas: me diga de novo, com o CPF/CNPJ de quem recebeu cada uma '
        || '(ou classifique pela tela quando chegarem).', v_valor));
  end if;

  -- 6. A transação desses dias que está na fila é de outro: dizer em nome de quem (o cadastro
  --    reconhecido, ou o nome do extrato — nunca o texto genérico do banco).
  select string_agg(distinct coalesce(sf.name, pe.name, cl.name, public._nome_da_linha(t.counterparty_name, t.description)), '; ')
    into v_outros
    from public.anotacoes_do_extrato a
    join public.bank_transactions t on t.transaction_type = a.sentido
     and abs(t.amount - a.valor) < 0.01
     and t.transaction_date between a.data_prevista - case when a.data_exata then 1 else 3 end
                                and a.data_prevista + case when a.data_exata then 1 else 7 end
    join public.finance_review_queue q on q.bank_transaction_id = t.id and q.status = 'pending'
    left join public.suppliers sf on sf.id = q.suggested_supplier_id
    left join public.payees pe on pe.id = q.suggested_payee_id
    left join public.clients cl on cl.id = q.suggested_client_id
   where a.id = v_id;
  if v_outros is not null and not v_diz_quem then
    return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', false, 'outra_contraparte', v_outros, 'falta_quem', true,
      'message', format('Chegou uma transação de R$ %s nesses dias de/para %s. Como você não disse para quem foi, não mexi '
        || 'nela: se é essa, me diga de novo com o nome (ex.: "o Pix de %s do %s é …"). Se não é, deixei anotado para quando a outra chegar.',
        v_valor, left(v_outros, 80), v_valor, split_part(v_outros, ';', 1)));
  end if;
  if v_outros is not null then
    return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', false, 'outra_contraparte', v_outros, 'substituidas', v_substituidas,
      'message', v_aviso || format('A transação de R$ %s desses dias que está na fila é de outro (%s), então não mexi nela. '
        || 'Deixei anotado: quando a que você disse chegar do banco, entra classificada. Se for aquela mesma, classifique pela tela.',
        v_valor, left(v_outros, 120)));
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', false, 'substituidas', v_substituidas,
    'message', v_aviso || 'Anotado. Quando a transação chegar do banco, ela já entra classificada.');
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.anotar_transacao(p_sentido text, p_valor numeric, p_data date, p_documento text, p_nome text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_categoria text, p_os_id uuid, p_descricao text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.anotar_transacao(p_sentido text, p_valor numeric, p_data date, p_documento text, p_nome text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_categoria text, p_os_id uuid, p_descricao text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anotar_transacao(p_sentido text, p_valor numeric, p_data date, p_documento text, p_nome text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_categoria text, p_os_id uuid, p_descricao text, p_autor uuid) TO service_role;

-- ── public.apagar_diaria(p_diaria_id uuid, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.apagar_diaria(p_diaria_id uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v record;
  v_os uuid[];
begin
  if v_autor is null then raise exception 'Diga quem está apagando a diária.'; end if;
  select ws.*, wp.payee_id, p.name as nome into v
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join public.payees p on p.id = wp.payee_id
   where ws.id = p_diaria_id and ws.fracao is not null
   for update of ws;
  if v.id is null then raise exception 'Diária não encontrada (talvez já tenha sido apagada).'; end if;

  select coalesce(array_agg(service_order_id), '{}') into v_os from public.work_shift_os where shift_id = p_diaria_id;
  delete from public.work_shifts where id = p_diaria_id;

  return jsonb_build_object(
    'ok', true,
    'apagado', jsonb_build_object(
      'favorecido_id', v.payee_id, 'data', v.data,
      'jornada', case v.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
      'valor_diaria', v.valor_diaria, 'extras', v.extras, 'descontos', v.descontos,
      'observacao', v.observacao, 'os_ids', to_jsonb(v_os)),
    'message', 'Diária de ' || v.nome || ' em ' || public._dia_curto(v.data) || ' apagada.'
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.apagar_diaria(p_diaria_id uuid, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.apagar_diaria(p_diaria_id uuid, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apagar_diaria(p_diaria_id uuid, p_autor uuid) TO service_role;

-- ── public.aplicar_anotacoes_pendentes() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.aplicar_anotacoes_pendentes()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a record;
  v_proposta uuid;
  v_candidatas integer;
  v_n integer := 0;
begin
  for a in select id from public.anotacoes_do_extrato where status = 'aguardando' order by criada_em loop
    -- Já cancelada nesta mesma varredura (por disputa com outra): pula.
    if (select status from public.anotacoes_do_extrato where id = a.id) <> 'aguardando' then continue; end if;
    select count(*) into v_candidatas from public._candidatas_da_anotacao(a.id);
    if v_candidatas > 1 then
      update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
             motivo_cancelamento = format('chegaram %s transações do mesmo valor; diga qual pela tela ou anote de novo com o CPF/CNPJ', v_candidatas)
       where id = a.id;
      continue;
    end if;
    -- Na janela já há uma linha ANOTADA que podia ser esta (mesma identidade): pode ter sido
    -- dita para aquela mesma transação. Aplicar na que sobrou seria escolher por eliminação.
    if v_candidatas = 1 and public._janela_tem_linha_anotada(a.id) then
      update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
             motivo_cancelamento = 'uma transação desse valor nesses dias já tinha outra anotação; diga qual é pela tela'
       where id = a.id;
      continue;
    end if;
    -- Outra anotação esperando quer a mesma transação: não se escolhe por ordem de chegada.
    if v_candidatas = 1 and exists (select 1 from public._anotacoes_em_disputa(a.id)) then
      update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
             motivo_cancelamento = 'duas anotações esperavam a mesma transação; diga qual é qual pela tela'
       where id = a.id or id in (select public._anotacoes_em_disputa(a.id));
      continue;
    end if;
    v_proposta := public._proposta_da_anotacao(a.id);
    if v_proposta is not null then
      perform public._aplicar_anotacao(a.id, v_proposta);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.aplicar_anotacoes_pendentes() TO postgres;
GRANT EXECUTE ON FUNCTION public.aplicar_anotacoes_pendentes() TO service_role;

-- ── public.aplicar_entrada_em_contas(p_transacao uuid, p_aplicacoes jsonb, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.aplicar_entrada_em_contas(p_transacao uuid, p_aplicacoes jsonb, p_motivo text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_tolerancia constant numeric := 10;  -- dono, 02/10/2026
  v_autor uuid := public._autor_do_financeiro(p_autor);
  t public.bank_transactions%rowtype;
  r public.receivables%rowtype;
  pg public.payments%rowtype;
  v_item jsonb;
  v_ja numeric;
  v_restante numeric;
  v_total numeric := 0;
  v_valor numeric;
  v_saldo numeric;
  v_acrescimo numeric;
  v_desconto numeric;
  v_quitar boolean;
  v_novo_valor numeric;
  v_novo_pago numeric;
  v_metodo text;
  v_pagamento uuid;
  v_primeiro uuid;
  v_dono_da_linha uuid;
  v_varias boolean;
  v_n integer := 0;
  v_feitos jsonb := '[]'::jsonb;
  v_nota text;
  v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
  v_msg text;
begin
  select * into t from public.bank_transactions where id = p_transacao for update;
  if not found then raise exception 'Linha do extrato não encontrada.'; end if;
  if t.transaction_type <> 'credit' then
    raise exception 'Só uma entrada do banco paga contas a receber.';
  end if;
  if t.dismissed_kind is not null then
    raise exception 'Essa entrada está fora da fila (%). Traga-a de volta em Extrato › Fora da fila antes de aplicar.', t.dismissed_kind;
  end if;
  perform public._recusa_se_mes_fechado(t.transaction_date, 'aplicar esta entrada');
  if exists (select 1 from public.payables where bank_transaction_id = t.id and status <> 'cancelled') then
    raise exception 'Essa entrada está ligada a uma conta a pagar. Desfaça aquele vínculo antes.';
  end if;

  if p_aplicacoes is null or jsonb_typeof(p_aplicacoes) <> 'array' or jsonb_array_length(p_aplicacoes) = 0 then
    raise exception 'Escolha ao menos uma conta para esta entrada pagar.';
  end if;
  if (select count(distinct coalesce(e ->> 'receivable_id', 'p:' || (e ->> 'pagamento_id'))) from jsonb_array_elements(p_aplicacoes) e)
     <> jsonb_array_length(p_aplicacoes) then
    raise exception 'A mesma conta apareceu duas vezes.';
  end if;
  if exists (select 1 from jsonb_array_elements(p_aplicacoes) e
              where e ->> 'pagamento_id' is null
                and ((e ->> 'receivable_id') is null or (e ->> 'valor') is null or round((e ->> 'valor')::numeric, 2) <= 0)) then
    raise exception 'Cada conta escolhida precisa de um valor maior que zero.';
  end if;

  select coalesce(sum(p.amount), 0) into v_ja
    from public.payments p
   where p.bank_transaction_id = t.id and p.status = 'confirmed' and p.receivable_id is not null;
  v_restante := round(t.amount - v_ja, 2);
  if v_restante <= 0.005 then
    raise exception 'Esta entrada (%) já está toda aplicada.', public._brl(t.amount);
  end if;

  -- Total: valores novos + pagamentos já lançados que esta entrada passa a explicar.
  select round(coalesce(sum((e ->> 'valor')::numeric) filter (where e ->> 'pagamento_id' is null), 0)
               + coalesce(sum(p.amount) filter (where e ->> 'pagamento_id' is not null), 0), 2)
    into v_total
    from jsonb_array_elements(p_aplicacoes) e
    left join public.payments p on p.id = (e ->> 'pagamento_id')::uuid;
  if v_total > v_restante + 0.005 then
    raise exception 'As contas somam %, mas desta entrada faltam aplicar %.', public._brl(v_total), public._brl(v_restante);
  end if;
  if v_total < v_restante - 0.005 then
    raise exception 'Sobram % desta entrada (de %). Aplique o valor inteiro: guardar a sobra como crédito do cliente chega na próxima etapa.',
      public._brl(v_restante - v_total), public._brl(v_restante);
  end if;

  v_metodo := case
    when coalesce(t.payment_method, '') ilike '%pix%' or coalesce(t.description, '') ilike '%pix%' then 'pix'
    when t.card_last_digits is not null then 'debit_card'
    else 'bank_transfer' end;
  v_varias := jsonb_array_length(p_aplicacoes) > 1 or v_ja > 0;
  select id into v_dono_da_linha from public.receivables where bank_transaction_id = t.id limit 1;

  for v_item in select * from jsonb_array_elements(p_aplicacoes) loop
    if v_item ->> 'pagamento_id' is not null then
      -- Pagamento já lançado à mão: a entrada passa a ser a origem dele.
      select * into pg from public.payments where id = (v_item ->> 'pagamento_id')::uuid for update;
      if not found or pg.receivable_id is null then raise exception 'Pagamento de conta a receber não encontrado.'; end if;
      if pg.status <> 'confirmed' then raise exception 'Esse pagamento foi estornado.'; end if;
      if pg.bank_transaction_id is not null then
        raise exception 'Esse pagamento já está ligado a outra entrada do banco.';
      end if;
      select * into r from public.receivables where id = pg.receivable_id for update;
      if r.status = 'cancelled' then raise exception '"%" está cancelada.', r.description; end if;

      update public.payments set bank_transaction_id = t.id where id = pg.id;
      update public.receivables
         set bank_transaction_id = case when bank_transaction_id is null and v_dono_da_linha is null then t.id
                                        else bank_transaction_id end,
             notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] O pagamento de ' || public._brl(pg.amount)
                     || ' de ' || to_char(pg.payment_date, 'DD/MM/YYYY') || ' veio da entrada de '
                     || to_char(t.transaction_date, 'DD/MM/YYYY') || ' (' || public._brl(t.amount) || ').')
       where id = r.id;
      v_pagamento := pg.id;
      v_valor := pg.amount;
      v_acrescimo := 0;
      v_desconto := 0;
    else
      select * into r from public.receivables where id = (v_item ->> 'receivable_id')::uuid for update;
      if not found then raise exception 'Conta a receber não encontrada.'; end if;
      if r.status not in ('pending', 'overdue', 'partially_paid') then
        raise exception '"%" não está em aberto (%).', r.description,
          case r.status when 'paid' then 'já está paga' when 'cancelled' then 'está cancelada' else r.status end;
      end if;
      perform public._recusa_se_mes_fechado(r.issue_date, 'receber nesta conta');

      v_valor := round((v_item ->> 'valor')::numeric, 2);
      v_quitar := coalesce((v_item ->> 'quitar')::boolean, false);
      v_saldo := round(r.amount - coalesce(r.paid_amount, 0), 2);
      v_acrescimo := 0;
      v_desconto := 0;
      v_novo_valor := r.amount;

      if v_valor > v_saldo + 0.005 then
        v_acrescimo := round(v_valor - v_saldo, 2);
        if v_acrescimo > c_tolerancia then
          raise exception 'Em "%" o valor passa do que falta receber (%) em %. Acima de R$ 10, avalie o porquê antes: pode ser outra conta do cliente ou crédito dele.',
            r.description, public._brl(v_saldo), public._brl(v_acrescimo);
        end if;
        v_novo_valor := r.amount + v_acrescimo;
      end if;
      v_novo_pago := round(coalesce(r.paid_amount, 0) + v_valor, 2);

      if v_quitar and v_novo_valor - v_novo_pago > 0.005 then
        v_desconto := round(v_novo_valor - v_novo_pago, 2);
        if v_desconto > c_tolerancia then
          raise exception 'Em "%" ainda faltariam % — acima de R$ 10 não se quita por desconto sozinho.',
            r.description, public._brl(v_desconto);
        end if;
        v_novo_valor := v_novo_pago;
      end if;

      insert into public.payments (receivable_id, amount, payment_date, payment_method, installments,
                                   card_fee_percent, net_amount, notes, status, bank_transaction_id)
      values (r.id, v_valor, t.transaction_date, v_metodo, 1, 0, v_valor,
              'Conciliado com o extrato de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                || case when v_varias then ' (entrada de ' || public._brl(t.amount) || ' que pagou mais de uma conta).' else '.' end,
              'confirmed', t.id)
      returning id into v_pagamento;

      v_nota := '[' || v_hoje || '] Recebido ' || public._brl(v_valor) || ' da entrada de '
                || to_char(t.transaction_date, 'DD/MM/YYYY') || ' (' || public._brl(t.amount) || ')'
                || case when v_acrescimo > 0 then '; pagou ' || public._brl(v_acrescimo) || ' a mais (receita)' else '' end
                || case when v_desconto > 0 then '; ' || public._brl(v_desconto) || ' deixam de ser cobrados (desconto)' else '' end
                || '.' || coalesce(' Motivo: ' || nullif(btrim(p_motivo), '') || '.', '');

      update public.receivables
         set amount = v_novo_valor,
             paid_amount = v_novo_pago,
             balance_amount = greatest(0, round(v_novo_valor - v_novo_pago, 2)),
             status = public._situacao_do_saldo(v_novo_valor, v_novo_pago, status),
             bank_transaction_id = case when bank_transaction_id is null and v_dono_da_linha is null then t.id
                                        else bank_transaction_id end,
             notes = btrim(coalesce(notes, '') || ' ' || v_nota)
       where id = r.id;
    end if;

    if v_dono_da_linha is null and r.bank_transaction_id is null then
      v_dono_da_linha := r.id;
    end if;
    v_primeiro := coalesce(v_primeiro, v_pagamento);
    v_n := v_n + 1;
    v_feitos := v_feitos || jsonb_build_object(
      'receivable_id', r.id, 'descricao', r.description, 'pagamento', v_pagamento, 'valor', v_valor,
      'ligado', v_item ->> 'pagamento_id' is not null,
      'valor_antes', r.amount, 'acrescimo', v_acrescimo, 'desconto', v_desconto);
  end loop;

  update public.bank_transactions
     set reconciled = true,
         reconciled_payment_id = coalesce(reconciled_payment_id, v_primeiro)
   where id = t.id;
  update public.finance_review_queue
     set status = 'superseded', decision_note = 'Aplicada em ' || v_n || ' conta(s) a receber'
   where bank_transaction_id = t.id and status = 'pending';

  v_msg := 'Entrada de ' || public._brl(t.amount) || ' de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
           || ' aplicada em ' || v_n || case when v_n = 1 then ' conta' else ' contas' end || ': '
           || (select string_agg(f ->> 'descricao' || ' ' || public._brl((f ->> 'valor')::numeric), ', ')
                 from jsonb_array_elements(v_feitos) f) || '.';

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, depois)
  values ('aplicou_pix', v_autor, t.id, case when v_n = 1 then (v_feitos -> 0 ->> 'receivable_id')::uuid end,
          v_total, left(coalesce(nullif(btrim(p_motivo), '') || ' · ', '') || v_msg, 300),
          jsonb_build_object('aplicacoes', v_feitos, 'ja_aplicado_antes', v_ja));

  return jsonb_build_object('ok', true, 'aplicado', v_total, 'contas', v_n, 'aplicacoes', v_feitos, 'message', v_msg);
end;
$function$
;
COMMENT ON FUNCTION public.aplicar_entrada_em_contas(p_transacao uuid, p_aplicacoes jsonb, p_motivo text, p_autor uuid) IS 'Aplica uma entrada do banco em contas a receber. Itens: {receivable_id, valor, quitar?} cria um pagamento; {pagamento_id} faz da entrada a origem de um pagamento já lançado. Tolerância de R$ 10 para mais (receita) e, com quitar, para menos (desconto).';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.aplicar_entrada_em_contas(p_transacao uuid, p_aplicacoes jsonb, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.aplicar_entrada_em_contas(p_transacao uuid, p_aplicacoes jsonb, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aplicar_entrada_em_contas(p_transacao uuid, p_aplicacoes jsonb, p_motivo text, p_autor uuid) TO service_role;

-- ── public.aplicar_reavaliacao_da_fila(p_linhas jsonb) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.aplicar_reavaliacao_da_fila(p_linhas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_n integer;
begin
  update public.finance_review_queue q set
    suggested_category = coalesce(l.suggested_category, q.suggested_category),
    dre_group = coalesce(l.dre_group, q.dre_group),
    suggested_supplier_id = l.suggested_supplier_id,
    suggested_payee_id = l.suggested_payee_id,
    suggested_client_id = l.suggested_client_id,
    -- O motor manda o valor certo: a OS da OC (preservada por ele) ou a do vínculo — ou
    -- nenhuma. O coalesce antigo deixava para sempre uma pergunta "é desta OS?" que não valia.
    suggested_service_order_id = l.suggested_service_order_id,
    applied_rule_id = l.applied_rule_id,
    confidence = coalesce(l.confidence, q.confidence),
    reasoning = coalesce(l.reasoning, q.reasoning),
    evidencia = l.evidencia,
    vinculo_sugerido = l.vinculo_sugerido,
    updated_at = now()
  from jsonb_to_recordset(p_linhas) as l(
    id uuid, suggested_category text, dre_group text, suggested_supplier_id uuid,
    suggested_payee_id uuid, suggested_client_id uuid, suggested_service_order_id uuid,
    applied_rule_id uuid, confidence integer, reasoning text, evidencia jsonb, vinculo_sugerido jsonb)
  where q.id = l.id and q.status = 'pending';
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.aplicar_reavaliacao_da_fila(p_linhas jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.aplicar_reavaliacao_da_fila(p_linhas jsonb) TO service_role;

-- ── public.apply_service_material_kit(p_service_order_id uuid, p_service_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.apply_service_material_kit(p_service_order_id uuid, p_service_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_kit uuid; v_linha uuid; v_criadas integer := 0; v_ja integer := 0;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select material_kit_product_id into v_kit from public.services where id = p_service_id;
  if v_kit is null then
    return jsonb_build_object('ok', false,
      'mensagem', 'Este serviço não tem kit de materiais cadastrado. Cadastre o kit no catálogo (produto do tipo kit) e ligue-o ao serviço.');
  end if;

  -- A linha da OS que corresponde a este serviço: é ela que passa a ser dona
  -- do material, e é por ela que a folha agrupa o material por etapa.
  select id into v_linha
  from public.service_order_services
  where service_order_id = p_service_order_id and service_id = p_service_id
  order by created_at limit 1;

  select count(*) into v_ja
  from public.service_order_parts sop
  join public.product_components pc on pc.component_product_id = sop.product_id
  where sop.service_order_id = p_service_order_id
    and pc.parent_product_id = v_kit and sop.source = 'kit';

  insert into public.service_order_parts
    (service_order_id, service_order_service_id, product_id, quantity,
     unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale, source, notes)
  select p_service_order_id, v_linha, pc.component_product_id, pc.quantity,
         coalesce(p.cost_price, 0), coalesce(p.sale_price, 0),
         coalesce(p.cost_price, 0) * pc.quantity, coalesce(p.sale_price, 0) * pc.quantity,
         'kit', 'Do kit de materiais do serviço'
  from public.product_components pc
  join public.products p on p.id = pc.component_product_id
  where pc.parent_product_id = v_kit
    and not exists (
      select 1 from public.service_order_parts x
      where x.service_order_id = p_service_order_id
        and x.product_id = pc.component_product_id and x.source = 'kit');

  get diagnostics v_criadas = row_count;

  return jsonb_build_object('ok', true, 'linhas_criadas', v_criadas, 'ja_estavam', v_ja,
    'mensagem', case
      when v_criadas = 0 and v_ja > 0 then 'O kit já estava aplicado nesta OS.'
      when v_criadas = 0 then 'O kit não tem componentes cadastrados.'
      else v_criadas || ' item(ns) de material lançado(s).' end);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.apply_service_material_kit(p_service_order_id uuid, p_service_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.apply_service_material_kit(p_service_order_id uuid, p_service_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_service_material_kit(p_service_order_id uuid, p_service_id uuid) TO service_role;

-- ── public.apply_survey_materials(p_survey_id uuid, p_rule_ids uuid[]) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.apply_survey_materials(p_survey_id uuid, p_rule_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_os uuid; v_linha uuid; v_service uuid; v_criadas integer := 0;
  v_selecionadas integer := 0; v_sem_numero integer := 0;
  v_qtd_invalida integer := 0; v_ja_lancadas integer := 0;
  v_motivos text[] := '{}';
  v_mensagem text;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select s.service_order_id, s.service_id into v_os, v_service
  from public.service_surveys s where s.id = p_survey_id;

  if v_os is null then
    return jsonb_build_object('ok', false,
      'mensagem', 'Este levantamento não está ligado a um orçamento ou OS.');
  end if;

  -- A linha do serviço, quando existir: é por ela que a folha impressa agrupa
  -- o material por etapa.
  select id into v_linha from public.service_order_services
  where service_order_id = v_os and service_id = v_service
  order by created_at limit 1;

  -- O que vai ficar de fora, e por quê — contado antes do insert, no mesmo
  -- instantâneo que ele vai ler. Os três filtros são uma partição das linhas
  -- selecionadas: tudo que não entra cai em exatamente um deles.
  select count(*),
         count(*) filter (where m.quantity is null),
         count(*) filter (where m.quantity is not null and m.quantity <= 0),
         count(*) filter (where m.quantity > 0 and exists (
           select 1 from public.service_order_parts x
           where x.service_order_id = v_os
             and x.service_order_service_id is not distinct from v_linha
             and x.product_id = m.product_id
             and x.source = 'survey'))
    into v_selecionadas, v_sem_numero, v_qtd_invalida, v_ja_lancadas
  from public.survey_suggested_materials(p_survey_id) m
  where m.rule_id = any(p_rule_ids);

  insert into public.service_order_parts
    (service_order_id, service_order_service_id, product_id, quantity,
     unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale,
     source, notes)
  select v_os, v_linha, g.product_id, g.quantity,
         g.unit_cost, g.unit_sale,
         g.unit_cost * g.quantity, g.unit_sale * g.quantity,
         'survey',
         g.notes
  from (
    -- Uma linha por PRODUTO: duas regras selecionadas juntas apontando para o mesmo
    -- produto (cabo banco→inversor e inversor→quadro) somam a quantidade, em vez de
    -- passarem as duas pela trava — que lê o instantâneo de antes do insert (lev-09).
    select m.product_id,
           sum(m.quantity)  as quantity,
           max(m.unit_cost) as unit_cost,
           max(m.unit_sale) as unit_sale,
           left(string_agg('Do levantamento: ' || left(m.question, 60) || ' → ' || left(m.answer, 40),
                           ' | ' order by m.question), 500) as notes
    from public.survey_suggested_materials(p_survey_id) m
    where m.rule_id = any(p_rule_ids)
      and m.quantity is not null
      and m.quantity > 0
      -- Não lança duas vezes o mesmo produto NA MESMA LINHA DE SERVIÇO vindo do
      -- levantamento. Dois serviços da mesma OS que precisem do mesmo produto (dois
      -- bancos de bateria) recebem material cada um — antes o segundo ficava sem.
      and not exists (
        select 1 from public.service_order_parts x
        where x.service_order_id = v_os
          and x.service_order_service_id is not distinct from v_linha
          and x.product_id = m.product_id
          and x.source = 'survey')
    group by m.product_id
  ) g;

  get diagnostics v_criadas = row_count;

  if v_sem_numero > 0 then
    v_motivos := v_motivos || (v_sem_numero || ' sem número na resposta — corrija a resposta do levantamento e lance de novo');
  end if;
  if v_qtd_invalida > 0 then
    v_motivos := v_motivos || (v_qtd_invalida || ' com quantidade zero ou negativa');
  end if;
  if v_ja_lancadas > 0 then
    v_motivos := v_motivos || (v_ja_lancadas || ' já estava(m) no orçamento');
  end if;

  if v_criadas > 0 then
    v_mensagem := v_criadas || ' item(ns) lançado(s) a partir do levantamento'
      || case when cardinality(v_motivos) > 0
              then '. Ficaram de fora: ' || array_to_string(v_motivos, '; ') || '.'
              else '.' end;
  elsif v_selecionadas = 0 then
    v_mensagem := 'Nenhuma sugestão selecionada para lançar.';
  else
    v_mensagem := 'Nada foi lançado: ' || array_to_string(v_motivos, '; ') || '.';
  end if;

  return jsonb_build_object('ok', true, 'linhas_criadas', v_criadas,
    'descartadas', jsonb_build_object(
      'sem_numero', v_sem_numero,
      'quantidade_invalida', v_qtd_invalida,
      'ja_lancadas', v_ja_lancadas),
    'mensagem', v_mensagem);
end;
$function$
;
COMMENT ON FUNCTION public.apply_survey_materials(p_survey_id uuid, p_rule_ids uuid[]) IS 'Lança no orçamento apenas as sugestões escolhidas (source=survey). DEFINER
   porque grava — e por isso checa is_external_seller na primeira linha.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.apply_survey_materials(p_survey_id uuid, p_rule_ids uuid[]) TO postgres;
GRANT EXECUTE ON FUNCTION public.apply_survey_materials(p_survey_id uuid, p_rule_ids uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_survey_materials(p_survey_id uuid, p_rule_ids uuid[]) TO service_role;

-- ── public.archive_old_fiscal_drafts(p_days integer) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.archive_old_fiscal_drafts(p_days integer DEFAULT 30)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_count int;
begin
  update public.fiscal_emission_drafts
     set status = 'archived'
   where status = 'draft'
     and updated_at < now() - (p_days || ' days')::interval;
  get diagnostics v_count = row_count;
  return v_count;
end $function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.archive_old_fiscal_drafts(p_days integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.archive_old_fiscal_drafts(p_days integer) TO service_role;

-- ── public.backfill_message_identity(p_limit integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.backfill_message_identity(p_limit integer DEFAULT 2000)
 RETURNS TABLE(linked_clients integer, linked_suppliers integer, linked_leads integer)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clients integer := 0;
  v_suppliers integer := 0;
  v_leads integer := 0;
BEGIN
  WITH alvo AS (
    SELECT m.id, m.phone_normalized
      FROM whatsapp_messages m
     WHERE m.client_id IS NULL AND m.supplier_id IS NULL AND m.lead_id IS NULL
       AND m.phone_normalized IS NOT NULL
     ORDER BY m.occurred_at DESC
     LIMIT p_limit
  ), res AS (
    SELECT a.id, r.kind, r.entity_id
      FROM alvo a
      CROSS JOIN LATERAL public.resolve_contact_identity(a.phone_normalized) r
  ), upd AS (
    UPDATE whatsapp_messages m
       SET client_id   = CASE WHEN res.kind = 'client'   THEN res.entity_id ELSE m.client_id END,
           supplier_id = CASE WHEN res.kind = 'supplier' THEN res.entity_id ELSE m.supplier_id END,
           lead_id     = CASE WHEN res.kind = 'lead'     THEN res.entity_id ELSE m.lead_id END
      FROM res
     WHERE m.id = res.id
    RETURNING res.kind
  )
  SELECT
    count(*) FILTER (WHERE kind = 'client')::integer,
    count(*) FILTER (WHERE kind = 'supplier')::integer,
    count(*) FILTER (WHERE kind = 'lead')::integer
    INTO v_clients, v_suppliers, v_leads
  FROM upd;

  RETURN QUERY SELECT v_clients, v_suppliers, v_leads;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.backfill_message_identity(p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.backfill_message_identity(p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.backfill_message_identity(p_limit integer) TO service_role;

-- ── public.bi_margin_by_category(_since date) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.bi_margin_by_category(_since date DEFAULT NULL::date)
 RETURNS TABLE(category text, revenue numeric, cost numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(pr.category,'(sem categoria)') as category,
         coalesce(sum(p.line_total_sale),0)::numeric,
         coalesce(sum(p.line_total_cost),0)::numeric
  from service_order_parts p
  join service_orders so on so.id = p.service_order_id
  left join products pr on pr.id = p.product_id
  where so.status not in ('draft','cancelled')
    and (_since is null or so.created_at >= _since)
  group by 1
  order by 2 desc nulls last;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.bi_margin_by_category(_since date) TO postgres;
GRANT EXECUTE ON FUNCTION public.bi_margin_by_category(_since date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_margin_by_category(_since date) TO service_role;

-- ── public.bi_revenue_by_brand(_since date, _brand text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.bi_revenue_by_brand(_since date DEFAULT NULL::date, _brand text DEFAULT NULL::text)
 RETURNS TABLE(brand text, revenue numeric, cost numeric, qty numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(pr.brand,'(sem marca)') as brand,
         coalesce(sum(p.line_total_sale),0)::numeric as revenue,
         coalesce(sum(p.line_total_cost),0)::numeric as cost,
         coalesce(sum(p.quantity),0)::numeric as qty
  from service_order_parts p
  join service_orders so on so.id = p.service_order_id
  left join products pr on pr.id = p.product_id
  where so.status not in ('draft','cancelled')
    and (_since is null or so.created_at >= _since)
    and (_brand is null or pr.brand ilike '%'||_brand||'%')
  group by 1
  order by revenue desc nulls last;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.bi_revenue_by_brand(_since date, _brand text) TO postgres;
GRANT EXECUTE ON FUNCTION public.bi_revenue_by_brand(_since date, _brand text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_revenue_by_brand(_since date, _brand text) TO service_role;

-- ── public.bi_top_clients(_since date, _limit integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.bi_top_clients(_since date DEFAULT NULL::date, _limit integer DEFAULT 10)
 RETURNS TABLE(client_id uuid, name text, revenue numeric, os_count bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select so.client_id, c.name,
         coalesce(sum(so.grand_total),0)::numeric as revenue,
         count(*)::bigint as os_count
  from service_orders so
  left join clients c on c.id = so.client_id
  where so.status not in ('draft','cancelled')
    and (_since is null or so.created_at >= _since)
  group by so.client_id, c.name
  order by revenue desc nulls last
  limit greatest(_limit,1);
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.bi_top_clients(_since date, _limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.bi_top_clients(_since date, _limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_top_clients(_since date, _limit integer) TO service_role;

-- ── public.bloqueia_lancamento_em_periodo_fechado() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.bloqueia_lancamento_em_periodo_fechado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.periodo_esta_fechado(NEW.issue_date) THEN
    RAISE EXCEPTION 'O período de % está fechado. Reabra-o para lançar nesta data.',
      to_char(NEW.issue_date, 'MM/YYYY');
  END IF;
  RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.bloqueia_lancamento_em_periodo_fechado() TO postgres;
GRANT EXECUTE ON FUNCTION public.bloqueia_lancamento_em_periodo_fechado() TO service_role;

-- ── public.cadastrar_contraparte(p_tipo text, p_dados jsonb, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.cadastrar_contraparte(p_tipo text, p_dados jsonb, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_doc text := nullif(regexp_replace(coalesce(p_dados ->> 'documento', ''), '\D', '', 'g'), '');
  v_nome text := nullif(btrim(coalesce(p_dados ->> 'nome', '')), '');
  v_id uuid;
  v_ja_existia boolean := false;
  v_categoria text := nullif(btrim(coalesce(p_dados ->> 'categoria', '')), '');
  v_dre text;
  v_atualizadas integer := 0;
  v_evid jsonb;
  v_chave text;
begin
  if p_tipo not in ('fornecedor', 'favorecido', 'cliente') then
    raise exception 'Tipo de cadastro inválido: % (fornecedor, favorecido ou cliente).', p_tipo;
  end if;
  if v_nome is null then raise exception 'Informe o nome.'; end if;
  if v_doc is not null and length(v_doc) not in (11, 14) then
    raise exception 'CPF tem 11 dígitos e CNPJ tem 14; recebi %.', length(v_doc);
  end if;
  if v_categoria is not null then
    select dre_group into v_dre from public.financial_categories where name = v_categoria and type = 'payable' and active;
    if not found then v_categoria := null; end if;
  end if;

  if p_tipo = 'fornecedor' then
    if v_doc is not null then
      select id into v_id from public.suppliers where regexp_replace(coalesce(cnpj_cpf, ''), '\D', '', 'g') = v_doc limit 1;
    end if;
    if v_id is null then
      insert into public.suppliers (name, trade_name, cnpj_cpf, phone, email, postal_code, address_line_1,
                                    address_number, address_complement, neighborhood, city, state, country, notes, active)
      values (v_nome, nullif(p_dados ->> 'nome_fantasia', ''), v_doc, nullif(p_dados ->> 'telefone', ''),
              nullif(p_dados ->> 'email', ''), nullif(p_dados ->> 'cep', ''), nullif(p_dados ->> 'logradouro', ''),
              nullif(p_dados ->> 'numero', ''), nullif(p_dados ->> 'complemento', ''), nullif(p_dados ->> 'bairro', ''),
              nullif(p_dados ->> 'cidade', ''), nullif(p_dados ->> 'uf', ''), 'BR',
              nullif(p_dados ->> 'observacao', ''), true)
      returning id into v_id;
    else
      v_ja_existia := true;
    end if;
  elsif p_tipo = 'favorecido' then
    if v_doc is not null then
      select id into v_id from public.payees where regexp_replace(coalesce(document, ''), '\D', '', 'g') = v_doc limit 1;
    end if;
    if v_id is null then
      insert into public.payees (name, kind, document, default_category, notes, active)
      values (v_nome, coalesce(nullif(p_dados ->> 'tipo_de_favorecido', ''), 'prestador'), v_doc, v_categoria,
              nullif(p_dados ->> 'observacao', ''), true)
      returning id into v_id;
    else
      v_ja_existia := true;
    end if;
  else
    if v_doc is not null then
      select id into v_id from public.clients where regexp_replace(coalesce(cpf_cnpj, ''), '\D', '', 'g') = v_doc limit 1;
    end if;
    if v_id is null then
      insert into public.clients (type, name, display_name, cpf_cnpj, phone, email, postal_code, address_line_1,
                                  address_number, address_complement, neighborhood, city, state, country, notes, active)
      values (case when length(coalesce(v_doc, '')) = 14 then 'company' else 'individual' end,
              v_nome, nullif(p_dados ->> 'nome_fantasia', ''), v_doc, nullif(p_dados ->> 'telefone', ''),
              nullif(p_dados ->> 'email', ''), nullif(p_dados ->> 'cep', ''), nullif(p_dados ->> 'logradouro', ''),
              nullif(p_dados ->> 'numero', ''), nullif(p_dados ->> 'complemento', ''), nullif(p_dados ->> 'bairro', ''),
              nullif(p_dados ->> 'cidade', ''), nullif(p_dados ->> 'uf', ''), 'BR',
              nullif(p_dados ->> 'observacao', ''), true)
      returning id into v_id;
    else
      v_ja_existia := true;
    end if;
  end if;

  -- Toda linha pendente com o mesmo documento passa a apontar para o cadastro.
  if v_doc is not null then
    v_chave := p_tipo;
    v_evid := jsonb_build_object(v_chave, jsonb_build_object(
      'id', v_id, 'nome', v_nome, 'por', 'documento',
      'detalhe', case when length(v_doc) = 14 then 'CNPJ' else 'CPF' end || ' confere com o ' || p_tipo || ' ' || v_nome));
    update public.finance_review_queue q set
      suggested_supplier_id = case when p_tipo = 'fornecedor' then v_id else q.suggested_supplier_id end,
      suggested_payee_id = case when p_tipo = 'favorecido' then v_id else q.suggested_payee_id end,
      suggested_client_id = case when p_tipo = 'cliente' then v_id else q.suggested_client_id end,
      evidencia = (coalesce(q.evidencia, '{}'::jsonb) - 'cadastrar') || v_evid,
      -- A categoria da atividade (CNAE) só entra onde o sistema não sabia nada: "Outras
      -- despesas" sem regra sua. Não passa por cima do que você ou uma regra decidiu.
      suggested_category = case
        when v_categoria is not null and p_tipo in ('fornecedor', 'favorecido') and q.kind = 'create_payable'
             and q.applied_rule_id is null and q.suggested_category = 'Outras despesas'
          then v_categoria else q.suggested_category end,
      dre_group = case
        when v_categoria is not null and p_tipo in ('fornecedor', 'favorecido') and q.kind = 'create_payable'
             and q.applied_rule_id is null and q.suggested_category = 'Outras despesas'
          then coalesce(v_dre, q.dre_group) else q.dre_group end,
      updated_at = now()
    from public.bank_transactions t
    where t.id = q.bank_transaction_id and q.status = 'pending'
      and regexp_replace(coalesce(t.counterparty_document, ''), '\D', '', 'g') = v_doc
      and ((p_tipo = 'cliente' and q.kind = 'create_receivable')
        or (p_tipo in ('fornecedor', 'favorecido') and q.kind = 'create_payable'));
    get diagnostics v_atualizadas = row_count;
  end if;

  insert into public.reconciliation_log (acao, autor, valor, detalhe, antes, depois)
  values ('cadastrou_contraparte', v_autor, null,
          left(case when v_ja_existia then 'Já existia: ' else 'Cadastrou ' end || p_tipo || ' ' || v_nome
               || coalesce(' (' || v_doc || ')', ''), 300),
          null,
          jsonb_build_object('tipo', p_tipo, 'id', v_id, 'documento', v_doc, 'categoria', v_categoria,
                             'linhas_da_fila', v_atualizadas, 'ja_existia', v_ja_existia));

  return jsonb_build_object(
    'ok', true, 'id', v_id, 'ja_existia', v_ja_existia, 'linhas_atualizadas', v_atualizadas,
    'message', case when v_ja_existia then initcap(p_tipo) || ' já estava cadastrado' else initcap(p_tipo) || ' cadastrado' end
      || case when v_atualizadas > 0 then '; ' || v_atualizadas || ' linha(s) do Extrato já apontam para ele.' else '.' end
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.cadastrar_contraparte(p_tipo text, p_dados jsonb, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.cadastrar_contraparte(p_tipo text, p_dados jsonb, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cadastrar_contraparte(p_tipo text, p_dados jsonb, p_autor uuid) TO service_role;

-- ── public.cadastrar_freelancer(p_nome text, p_valor_diaria numeric, p_desde date, p_chave_pix text, p_tipo_chave text, p_documento text, p_telefone text, p_observacao text, p_simular boolean, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.cadastrar_freelancer(p_nome text, p_valor_diaria numeric, p_desde date DEFAULT NULL::date, p_chave_pix text DEFAULT NULL::text, p_tipo_chave text DEFAULT NULL::text, p_documento text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_observacao text DEFAULT NULL::text, p_simular boolean DEFAULT false, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_nome text := nullif(regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g'), '');
  v_desde date := coalesce(p_desde, public._hoje_brt());
  v_doc text := nullif(public._doc_normalizado(p_documento), '');
  v_chave text := nullif(btrim(coalesce(p_chave_pix, '')), '');
  v_tipo text := nullif(lower(btrim(coalesce(p_tipo_chave, ''))), '');
  v_fone text := nullif(public.wa_normalize_phone(p_telefone), '');
  v_obs text := nullif(btrim(coalesce(p_observacao, '')), '');
  v_fav public.payees%rowtype;   -- não "record": sem CPF, v_fav.id é lido antes de qualquer select
  v_perfil_id uuid;
  v_acao text;
  v_regra text;            -- 'criada' | 'ja_existia' | 'sem_cpf'
  v_regra_categoria text;
begin
  -- Simular não grava nada: o assistente monta a confirmação antes de saber quem vai dizer "sim".
  if v_autor is null and not coalesce(p_simular, false) then
    raise exception 'Diga quem está cadastrando o freelancer.';
  end if;
  if v_nome is null then raise exception 'Diga o nome do freelancer.'; end if;
  if p_valor_diaria is null or p_valor_diaria <= 0 then
    raise exception 'Diga o valor da diária de %.', v_nome;
  end if;
  if v_desde > public._hoje_brt() then
    raise exception 'Início no futuro (%): cadastre a partir do primeiro dia trabalhado, ou de hoje.', to_char(v_desde, 'DD/MM/YYYY');
  end if;
  if v_doc is not null and length(v_doc) not in (11, 14) then
    raise exception 'CPF/CNPJ com % dígitos: o CPF tem 11 e o CNPJ 14.', length(v_doc);
  end if;

  -- Chave Pix: o tipo dito, ou deduzido quando o formato não deixa dúvida. Onze dígitos pode ser
  -- CPF ou celular — aí só com o tipo dito (ou quando é o próprio CPF informado).
  if v_chave is null then
    v_tipo := null;
  else
    if v_tipo is null then
      v_tipo := case
        when v_chave like '%@%' then 'email'
        when v_chave ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then 'aleatoria'
        when length(regexp_replace(v_chave, '\D', '', 'g')) = 14 then 'cnpj'
        when v_doc is not null and public._doc_normalizado(v_chave) = v_doc then 'cpf'
      end;
      if v_tipo is null then
        raise exception 'A chave Pix % é CPF ou telefone? Diga o tipo.', v_chave;
      end if;
    end if;
    if v_tipo not in ('cpf', 'cnpj', 'email', 'telefone', 'aleatoria') then
      raise exception 'Tipo de chave Pix inválido: "%". Use cpf, cnpj, email, telefone ou aleatoria.', p_tipo_chave;
    end if;
    if v_tipo = 'email' then
      v_chave := lower(v_chave);
      if v_chave !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
        raise exception 'E-mail da chave Pix inválido: %.', v_chave;
      end if;
    elsif v_tipo in ('cpf', 'cnpj') then
      v_chave := public._doc_normalizado(v_chave);
      if length(v_chave) <> (case v_tipo when 'cpf' then 11 else 14 end) then
        raise exception 'A chave Pix % não tem os dígitos de um %.', p_chave_pix, upper(v_tipo);
      end if;
      -- Chave Pix CPF é o CPF: vale como documento (é o que liga a regra por CPF).
      if v_tipo = 'cpf' and v_doc is null then v_doc := v_chave; end if;
    elsif v_tipo = 'telefone' then
      v_chave := nullif(public.wa_normalize_phone(v_chave), '');
      if v_chave is null then raise exception 'Telefone da chave Pix inválido: %.', p_chave_pix; end if;
      v_chave := '+' || v_chave;
    end if;
  end if;

  -- Quem já existe: pelo CPF/CNPJ; sem achar, pelo MESMO nome.
  if v_doc is not null then
    select * into v_fav from public.payees
     where public._doc_normalizado(document) = v_doc
     order by active desc, created_at limit 1;
  end if;
  if v_fav.id is null then
    select * into v_fav from public.payees
     where lower(extensions.unaccent(regexp_replace(btrim(name), '\s+', ' ', 'g'))) = lower(extensions.unaccent(v_nome))
     order by active desc, created_at limit 1;
    if v_fav.id is not null and v_doc is not null and nullif(public._doc_normalizado(v_fav.document), '') is not null then
      raise exception 'Já existe um favorecido chamado % com outro CPF/CNPJ. Confira o documento, ou cadastre com o nome completo para diferenciar os dois.', v_fav.name;
    end if;
  end if;

  if v_fav.id is not null then
    if not v_fav.active then
      raise exception '% está desativado nos favorecidos: reative o cadastro antes de dar diária a ele.', v_fav.name;
    end if;
    if exists (select 1 from public.work_profiles
                where payee_id = v_fav.id and modo_pagamento = 'diaria'
                  and (vigencia_fim is null or vigencia_fim >= v_desde)) then
      raise exception '% já tem diária cadastrada (veja em Financeiro › Diárias).', v_fav.name;
    end if;
    v_acao := 'diaria_no_cadastro_existente';
  else
    v_acao := 'criado';
  end if;

  if v_doc is null then
    v_regra := 'sem_cpf';
  else
    select set_category into v_regra_categoria from public.finance_rules
     where match_type = 'document' and lower(match_value) = v_doc
       and direction in ('debit', 'any') and status in ('active', 'proposed')
     limit 1;
    v_regra := case when found then 'ja_existia' else 'criada' end;
  end if;

  if coalesce(p_simular, false) then
    return jsonb_build_object(
      'ok', true, 'simulacao', true, 'acao', v_acao,
      'favorecido_id', v_fav.id, 'nome', coalesce(v_fav.name, v_nome),
      'valor_diaria', round(p_valor_diaria, 2), 'desde', v_desde,
      'chave_pix', v_chave, 'tipo_chave', v_tipo, 'tem_documento', v_doc is not null,
      'regra', v_regra, 'regra_categoria', v_regra_categoria);
  end if;

  if v_acao = 'criado' then
    insert into public.payees (name, kind, document, phone, pix_key, pix_key_type, default_category,
                               notes, active, conta_corrente_desde, saldo_anterior)
    values (v_nome, 'prestador', v_doc, v_fone, v_chave, v_tipo, 'Diárias de freelancers',
            v_obs, true, v_desde, 0)
    returning * into v_fav;
  else
    -- Cadastro existente: completa o que falta; a chave Pix dita agora vale (é a que se usa para pagar).
    update public.payees set
      document = coalesce(nullif(document, ''), v_doc),
      phone = coalesce(nullif(phone, ''), v_fone),
      pix_key = coalesce(v_chave, pix_key),
      pix_key_type = case when v_chave is not null then v_tipo else pix_key_type end,
      default_category = 'Diárias de freelancers',
      conta_corrente_desde = coalesce(conta_corrente_desde, v_desde)
    where id = v_fav.id
    returning * into v_fav;
  end if;

  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria,
                                    meia_diaria_ate_horas, vigencia_inicio, observacao)
  values (v_fav.id, 'diarista', 'diaria', round(p_valor_diaria, 2), 4, v_desde,
          'Diária cadastrada em ' || to_char(public._hoje_brt(), 'DD/MM/YYYY') || '. Meia diária até 4h.'
          || coalesce(' ' || v_obs, ''))
  returning id into v_perfil_id;

  if v_regra = 'criada' then
    insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group,
                                      autonomy, origin, status, reasoning, created_by)
    values ('document', v_doc, 'debit', 'Diárias de freelancers', 'custo_direto', 'apply', 'user', 'active',
            'Pix ao CPF de ' || split_part(v_fav.name, ' ', 1) || ' é diária de freelancer (cadastro de '
            || to_char(public._hoje_brt(), 'DD/MM/YYYY') || ').', v_autor)
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'ok', true, 'acao', v_acao,
    'favorecido_id', v_fav.id, 'perfil_id', v_perfil_id, 'nome', v_fav.name,
    'valor_diaria', round(p_valor_diaria, 2), 'desde', v_desde,
    'chave_pix', v_chave, 'tipo_chave', v_tipo, 'regra', v_regra,
    'message', v_fav.name || ' cadastrado: diária de ' || public._brl(round(p_valor_diaria, 2))
      || ' desde ' || public._dia_curto(v_desde) || '.'
      || case v_acao when 'diaria_no_cadastro_existente' then ' Usei o cadastro de favorecido que já existia.' else '' end
      || case v_regra
           when 'criada' then ' Pix para o CPF dele entram sozinhos em Diárias de freelancers.'
           when 'ja_existia' then ' Já havia regra para o CPF dele (' || coalesce(v_regra_categoria, 'sem categoria') || '); mantida.'
           else ' Sem CPF: os Pix para ele vão pedir a sua confirmação na fila do extrato.' end
  );
end;
$function$
;
COMMENT ON FUNCTION public.cadastrar_freelancer(p_nome text, p_valor_diaria numeric, p_desde date, p_chave_pix text, p_tipo_chave text, p_documento text, p_telefone text, p_observacao text, p_simular boolean, p_autor uuid) IS 'Freelancer de diária numa chamada: favorecido + diária + conta corrente + categoria + regra por CPF. p_simular=true só diz o que faria. Usada pelo assistente (tool cadastrar_freelancer).';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.cadastrar_freelancer(p_nome text, p_valor_diaria numeric, p_desde date, p_chave_pix text, p_tipo_chave text, p_documento text, p_telefone text, p_observacao text, p_simular boolean, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.cadastrar_freelancer(p_nome text, p_valor_diaria numeric, p_desde date, p_chave_pix text, p_tipo_chave text, p_documento text, p_telefone text, p_observacao text, p_simular boolean, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cadastrar_freelancer(p_nome text, p_valor_diaria numeric, p_desde date, p_chave_pix text, p_tipo_chave text, p_documento text, p_telefone text, p_observacao text, p_simular boolean, p_autor uuid) TO service_role;

-- ── public.calc_shift_duration() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.calc_shift_duration()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.inicio is not null and new.fim is not null then
    new.duracao_minutos := greatest(
      0,
      (extract(epoch from (new.fim - new.inicio)) / 60)::integer - coalesce(new.intervalo_minutos, 0)
    );
  end if;
  new.updated_at := now();
  return new;
end $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.calc_shift_duration() TO postgres;
GRANT EXECUTE ON FUNCTION public.calc_shift_duration() TO authenticated;
GRANT EXECUTE ON FUNCTION public.calc_shift_duration() TO service_role;

-- ── public.calc_so_totals(so_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.calc_so_totals(so_id uuid)
 RETURNS TABLE(labor_cost_total numeric, parts_cost_total numeric, labor_hours_total numeric, operational_cost_total numeric, travel_billable numeric, subcontract_cost_total numeric, discount_amount numeric, tax_amount numeric, subtotal numeric, base numeric, card_fee_percent numeric, card_fee_amount numeric, grand_total numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_labor numeric; v_parts numeric; v_hours numeric;
  v_operational numeric; v_travel numeric; v_subcontract numeric; v_discount numeric; v_tax numeric;
  v_is_travel_billable boolean; v_card_passthrough_enabled boolean; v_card_installments integer;
  v_fee_percent numeric := 0; v_billable_travel numeric; v_subtotal numeric; v_base numeric;
  v_card_fee_amount numeric; v_grand numeric;
begin
  select coalesce(sum(s.line_total), 0) into v_labor
  from service_order_services s where s.service_order_id = so_id;

  select coalesce(sum(p.line_total_sale), 0) into v_parts
  from service_order_parts p where p.service_order_id = so_id;

  select round(coalesce(sum(t.duration_minutes), 0) / 60.0, 2) into v_hours
  from time_entries t where t.service_order_id = so_id and t.billable;

  select coalesce(so.operational_cost_total, 0), coalesce(so.travel_cost_total, 0),
         coalesce(so.subcontract_cost_total, 0), coalesce(so.discount_amount, 0),
         coalesce(so.tax_amount, 0), so.is_travel_billable,
         so.card_fee_passthrough_enabled, so.card_installments
    into v_operational, v_travel, v_subcontract, v_discount, v_tax,
         v_is_travel_billable, v_card_passthrough_enabled, v_card_installments
  from service_orders so where so.id = so_id;
  if not found then return; end if;

  v_billable_travel := case when v_is_travel_billable is distinct from false then v_travel else 0 end;
  v_subtotal := v_labor + v_parts + v_operational + v_billable_travel + v_subcontract;
  v_base := v_subtotal - v_discount + v_tax;

  if v_card_passthrough_enabled and v_card_installments is not null then
    select f.fee_percent into v_fee_percent
    from card_installment_fees f where f.installments = v_card_installments;
    v_fee_percent := coalesce(v_fee_percent, 0);
  end if;
  -- Gross-up: a taxa é repassada por cima do valor já ajustado (Onda 1C).
  v_card_fee_amount := case when v_fee_percent > 0 and v_fee_percent < 100
    then round(v_base * v_fee_percent / (100 - v_fee_percent), 2) else 0 end;
  v_grand := round(v_base + v_card_fee_amount, 2);

  return query select
    round(v_labor, 2), round(v_parts, 2), v_hours, v_operational, v_billable_travel, v_subcontract,
    v_discount, v_tax, round(v_subtotal, 2), round(v_base, 2), v_fee_percent, v_card_fee_amount, v_grand;
end;
$function$
;
-- ACL: =X/postgres postgres=X/postgres anon=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.calc_so_totals(so_id uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.calc_so_totals(so_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.calc_so_totals(so_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.calc_so_totals(so_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calc_so_totals(so_id uuid) TO service_role;

-- ── public.calc_warranty_expiry() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.calc_warranty_expiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.warranty_months is null or new.warranty_months <= 0 then
    return new;
  end if;

  -- INSERT: sempre calcula. UPDATE: só quando o prazo mudou, ou quando a data
  -- ainda não existe (linha antiga que nunca teve o cálculo aplicado).
  if tg_op = 'INSERT'
     or new.warranty_months is distinct from old.warranty_months
     or new.warranty_expires_at is null then
    new.warranty_expires_at := current_date + (new.warranty_months || ' months')::interval;
  end if;

  return new;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.calc_warranty_expiry() TO postgres;
GRANT EXECUTE ON FUNCTION public.calc_warranty_expiry() TO authenticated;
GRANT EXECUTE ON FUNCTION public.calc_warranty_expiry() TO service_role;

-- ── public.cancel_followup_mission(p_id uuid, p_motivo text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.cancel_followup_mission(p_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_ok integer;
begin
  update public.ai_followup_missions
     set status = 'cancelled', resolucao = coalesce(p_motivo, 'cancelada pelo dono'), resolvida_em = now(),
         proximo_toque_em = null
   where id = p_id and status in ('active','waiting_reply','escalated');
  get diagnostics v_ok = row_count;
  if v_ok > 0 then
    insert into public.ai_followup_events (mission_id, tipo, conteudo, created_by)
    values (p_id, 'cancelled', p_motivo, auth.uid());
  end if;
  return v_ok > 0;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.cancel_followup_mission(p_id uuid, p_motivo text) TO postgres;
GRANT EXECUTE ON FUNCTION public.cancel_followup_mission(p_id uuid, p_motivo text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_followup_mission(p_id uuid, p_motivo text) TO service_role;

-- ── public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_part record;
  v_receivable record;
  v_payment record;
  v_parts_restored int := 0;
  v_receivables_cancelled int := 0;
  v_payments_cancelled int := 0;
  v_collections_cancelled int := 0;
  v_deposit_paid numeric := 0;
  v_now timestamptz := now();
  v_linhas uuid[] := '{}';
  v_linha uuid;
begin
  if not public.stock_model_v2_on() then
    for v_part in
      select id, product_id, quantity, unit_cost_snapshot
      from public.service_order_parts
      where service_order_id = p_service_order_id
    loop
      insert into public.inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
      values
        (v_part.product_id, 'return', v_part.quantity, 'service_order_cancel', p_service_order_id, v_part.unit_cost_snapshot);
      v_parts_restored := v_parts_restored + 1;
    end loop;
  end if;

  for v_receivable in
    select id, status, is_deposit, paid_amount, bank_transaction_id
    from public.receivables
    where service_order_id = p_service_order_id
      and status <> 'cancelled'
  loop
    if v_receivable.is_deposit and coalesce(v_receivable.paid_amount, 0) > 0 then
      v_deposit_paid := v_deposit_paid + v_receivable.paid_amount;
    end if;
    if v_receivable.bank_transaction_id is not null then
      v_linhas := v_linhas || v_receivable.bank_transaction_id;
    end if;

    for v_payment in
      select p.id, p.amount, p.bank_transaction_id,
             (select t.id from public.bank_transactions t where t.reconciled_payment_id = p.id limit 1) as linha_presa
      from public.payments p
      where p.receivable_id = v_receivable.id
        and p.status = 'confirmed'
    loop
      update public.payments
      set status = 'cancelled',
          cancelled_at = v_now,
          cancellation_reason = p_reason
      where id = v_payment.id;

      if v_payment.bank_transaction_id is not null then
        v_linhas := v_linhas || v_payment.bank_transaction_id;
      end if;
      if v_payment.linha_presa is not null then
        v_linhas := v_linhas || v_payment.linha_presa;
      end if;
      v_payments_cancelled := v_payments_cancelled + 1;
    end loop;

    update public.receivables
    set status = 'cancelled',
        balance_amount = 0,
        bank_transaction_id = null
    where id = v_receivable.id;

    v_receivables_cancelled := v_receivables_cancelled + 1;
  end loop;

  -- Cada linha tocada: segue presa a outra conta que ela ainda paga, ou volta para a fila.
  for v_linha in select distinct unnest(v_linhas)
  loop
    if not public._reacomodar_entrada(v_linha) then
      update public.bank_transactions
         set reconciled = false, reconciled_payment_id = null
       where id = v_linha;
    end if;
  end loop;

  update public.collections
  set status = 'cancelled'
  where service_order_id = p_service_order_id
    and status <> 'cancelled';
  get diagnostics v_collections_cancelled = row_count;

  update public.service_orders
  set status = 'cancelled',
      cancelled_at = v_now,
      cancellation_reason = p_reason
  where id = p_service_order_id;

  return json_build_object(
    'success', true,
    'parts_restored', v_parts_restored,
    'receivables_cancelled', v_receivables_cancelled,
    'payments_cancelled', v_payments_cancelled,
    'collections_cancelled', v_collections_cancelled,
    'deposit_paid', v_deposit_paid
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) TO service_role;

-- ── public.cancelar_lancamento(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.cancelar_lancamento(p_tipo text, p_id uuid, p_motivo text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx uuid;
  v_nasceu boolean;
  v_caixa boolean;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_nota text;
  v_destino text := null;
  v_grupo jsonb;
  v_linhas uuid[] := '{}';
  v_linha uuid;
  v_outras_soltas int := 0;
  v_outras_seguem int := 0;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;
  if v_motivo is null or length(v_motivo) < 3 then
    raise exception 'Diga por que o lançamento está sendo cancelado.';
  end if;

  if p_tipo = 'payable' then
    -- Pix dividido (pró-labore + retirada de sócio): as partes voltam a ser um lançamento só e o
    -- cancelamento vale para o pagamento inteiro (28/09/2026).
    v_grupo := public._divisao_de(p_id);
    p_id := public._juntar_divisao(p_id, 'cancelar o lançamento', v_autor);
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Este lançamento já está cancelado.'; end if;
  perform public._recusa_se_mes_fechado((v_antes ->> 'issue_date')::date, 'cancelar este lançamento');

  v_tx := (v_antes ->> 'bank_transaction_id')::uuid;
  v_nasceu := v_tx is not null and public._nasceu_do_extrato(p_tipo, p_id);
  v_caixa := v_tx is not null and exists (
    select 1 from public.bank_transactions t
     where t.id = v_tx and (t.bank_ref_id like 'caixa:%' or t.source_type = 'cash'));
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] Cancelado: ' || v_motivo;

  -- Entradas de onde vieram os pagamentos desta conta a receber (um Pix pode pagar várias contas).
  if p_tipo = 'receivable' then
    select coalesce(array_agg(distinct x.bank_transaction_id), '{}') into v_linhas
      from public.payments x
     where x.receivable_id = p_id and x.status = 'confirmed' and x.bank_transaction_id is not null
       and x.bank_transaction_id is distinct from v_tx;
  end if;

  update public.payments
     set status = 'cancelled', cancelled_at = now(), cancellation_reason = left('Lançamento cancelado: ' || v_motivo, 200)
   where status = 'confirmed'
     and ((p_tipo = 'payable' and payable_id = p_id) or (p_tipo = 'receivable' and receivable_id = p_id));

  if p_tipo = 'payable' then
    update public.payables set status = 'cancelled', bank_transaction_id = null,
           notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
    update public.finance_review_queue set status = 'superseded', decision_note = v_nota
     where created_payable_id = p_id;
  else
    update public.receivables set status = 'cancelled', bank_transaction_id = null,
           notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
    update public.finance_review_queue set status = 'superseded', decision_note = v_nota
     where created_receivable_id = p_id;
  end if;

  if v_tx is not null then
    if v_caixa then
      -- Linha do Caixa: quem a criou foi o lançamento; cancelado ele, o dinheiro não saiu (ou
      -- não entrou). Sai do saldo e não vai para a fila do Extrato.
      update public.bank_transactions set
        reconciled = true, reconciled_payment_id = null,
        dismissed_kind = 'estornada',
        dismissed_reason = left('Lançamento do Caixa cancelado: ' || v_motivo, 300),
        dismissed_at = now(),
        dismissed_by = v_autor
      where id = v_tx;
      v_destino := 'caixa_estornado';
    elsif p_tipo = 'receivable' and public._reacomodar_entrada(v_tx) then
      -- A entrada também paga outra conta: continua conciliada, segurada por ela.
      v_destino := 'outras_contas';
    elsif v_nasceu then
      update public.bank_transactions set
        reconciled = true, reconciled_payment_id = null,
        dismissed_kind = 'manual',
        dismissed_reason = left('Lançamento cancelado: ' || v_motivo, 300),
        dismissed_at = now(),
        dismissed_by = v_autor
      where id = v_tx;
      v_destino := 'fora_da_fila';
    else
      update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
      v_destino := 'fila';
    end if;
  end if;

  -- As outras entradas que pagavam esta conta (sem o vínculo antigo): seguem conciliadas se ainda
  -- pagam outra conta; senão voltam para a fila.
  foreach v_linha in array v_linhas loop
    if public._reacomodar_entrada(v_linha) then
      v_outras_seguem := v_outras_seguem + 1;
    else
      update public.bank_transactions set reconciled = false, reconciled_payment_id = null
       where id = v_linha and dismissed_kind is null;
      v_outras_soltas := v_outras_soltas + 1;
    end if;
  end loop;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'cancelou_lancamento', v_autor, v_tx,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    (v_antes ->> 'amount')::numeric,
    left(v_motivo || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'bank_transaction_id', v_tx, 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('status', 'cancelled', 'linha_do_extrato', v_destino,
                       'outras_entradas', to_jsonb(v_linhas), 'outras_voltaram_a_fila', v_outras_soltas)
  );

  return jsonb_build_object(
    'ok', true,
    'linha_do_extrato', v_destino,
    'message', 'Lançamento cancelado.'
      || case v_destino
           when 'caixa_estornado' then ' O Caixa deixou de contar este valor.'
           when 'fora_da_fila' then ' A linha do extrato foi para "Fora da fila" com o mesmo motivo; de lá ela pode voltar.'
           when 'fila' then ' A linha do extrato voltou para a fila.'
           when 'outras_contas' then ' A linha do extrato continua pagando a(s) outra(s) conta(s).'
           else '' end
      || case when v_outras_soltas > 0 then ' ' || v_outras_soltas || ' entrada(s) do extrato que pagavam esta conta voltaram para a fila.' else '' end
      || case when v_outras_seguem > 0 then ' ' || v_outras_seguem || ' entrada(s) do extrato que pagavam esta conta continuam pagando outras contas.' else '' end
      || coalesce(' ' || (v_grupo ->> 'frase'), '')
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.cancelar_lancamento(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.cancelar_lancamento(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancelar_lancamento(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO service_role;

-- ── public.categoria_e_sensivel(nome text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.categoria_e_sensivel(nome text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.financial_categories
    WHERE name = nome AND type = 'payable' AND sensitive
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.categoria_e_sensivel(nome text) TO postgres;
GRANT EXECUTE ON FUNCTION public.categoria_e_sensivel(nome text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.categoria_e_sensivel(nome text) TO service_role;

-- ── public.checklist_do_mes(p_ano integer, p_mes integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.checklist_do_mes(p_ano integer, p_mes integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_ini date := make_date(p_ano, p_mes, 1);
  v_fim date := (make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date;
  v_itens jsonb := '[]'::jsonb;
  v_n integer;
  v_n_parc integer;
  v_valor numeric;
  v_det text;
begin
  -- 1. Saldo de cada conta confere com o banco (a última conferência).
  select count(*), string_agg(c.label || ' difere ' || public._brl(abs(k.diferenca)), '; ')
    into v_n, v_det
    from public.bank_connections c
    join lateral (select * from public.bank_balance_checks b where b.bank_connection_id = c.id
                   order by b.conferido_em desc limit 1) k on true
   where coalesce(c.active, true) and not k.fecha;
  v_itens := v_itens || jsonb_build_object('chave', 'saldo_confere', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'O saldo de cada conta confere com o banco', 'quantidade', v_n,
    'detalhe', coalesce(v_det, 'Todas as contas conferem na última sincronização.'));

  -- 2. Nada do extrato do mês sem destino (nem lançado, nem casado, nem fora da fila).
  select count(*), coalesce(sum(t.amount), 0) into v_n, v_valor
    from public.bank_transactions_situacao t
   where t.transaction_date between v_ini and v_fim and t.situacao = 'nova'
     and coalesce(t.tx_status, '') <> 'PENDING';
  v_itens := v_itens || jsonb_build_object('chave', 'extrato_tratado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Todo movimento do banco no mês tem destino', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada esperando no Extrato.' else v_n || ' linha(s) esperando no Extrato.' end);

  -- 3. Nenhuma despesa lançada em dobro: uma com banco e outra sem, mesmo valor, mesma
  --    contraparte, até 5 dias. (Duas COM banco são dois pagamentos reais.) Conta em aberto se
  --    compara pelo vencimento; pagamento já ligado a uma nota não é duplicata das parcelas dela;
  --    a parte paga com crédito do fornecedor não passa pelo banco (revisão de 27/09/2026).
  --    E a compra parcelada lançada mais de uma vez (compras_parceladas_em_dobro).
  select count(*) into v_n
    from public.payables a
    join public.payables b on b.id <> a.id
     and a.bank_transaction_id is not null and b.bank_transaction_id is null
     and b.status <> 'cancelled' and abs(a.amount - b.amount) < 0.01
     and abs(a.issue_date - case when b.status in ('pending', 'partially_paid', 'overdue') then b.due_date else b.issue_date end) <= 5
     and not (a.fiscal_note_id is not null and a.fiscal_note_id = b.fiscal_note_id)
     and b.payment_method is distinct from 'credito_fornecedor'
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') = coalesce(b.supplier_id::text, upper(b.supplier_name), '')
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') <> ''
   where a.status <> 'cancelled' and a.issue_date between v_ini and v_fim;
  select count(*), coalesce(sum(d.lancado), 0), string_agg(distinct d.loja, ', ') into v_n_parc, v_valor, v_det
    from public.compras_parceladas_em_dobro d
   where d.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'sem_duplicata', 'bloqueia', true, 'ok', v_n + v_n_parc = 0,
    'titulo', 'Nenhuma despesa lançada em dobro', 'quantidade', v_n + v_n_parc,
    'detalhe', case
      when v_n + v_n_parc = 0 then 'Nenhum par suspeito.'
      else concat_ws(' ',
        case when v_n > 0 then v_n || ' par(es) com o mesmo valor e fornecedor, um pelo banco e outro à mão.' end,
        case when v_n_parc > 0 then v_n_parc || ' lançamento(s) repetem uma compra parcelada já lançada ('
                                     || public._brl(v_valor) || ' a mais: ' || left(v_det, 200)
                                     || ') — marcados como "lançada em dobro" na Conciliação.' end)
    end);

  -- 4. Lançamento casado com o extrato pelo mesmo valor. A compra parcelada casada com UMA
  --    parcela tem a diferença esperada (a compra inteira contra a parcela) e não conta.
  select count(*) into v_n
    from public.conciliacao_lancamentos l
   where l.situacao = 'conciliado' and coalesce(l.diferenca, 0) <> 0 and not l.compra_parcelada
     and coalesce(l.extrato_data, l.issue_date) between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'conciliacao_bate', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Nenhum lançamento com valor diferente do extrato', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todos batem (compra parcelada casada com uma parcela não conta).' else v_n || ' lançamento(s) difere(m) do banco — veja a Conciliação.' end);

  -- 5. Toda DESPESA tem categoria (sem ela o valor some do resultado). Recebimento sem categoria
  --    entra no DRE como Receita (useLancamentosDRE), então não trava o mês: os sinais de orçamento
  --    e as parcelas de NF-e nascem sem categoria, e agosto/2026 travava por 7 deles (27/09/2026).
  select count(*) into v_n from public.payables
   where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category is null;
  v_itens := v_itens || jsonb_build_object('chave', 'tudo_categorizado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Toda despesa tem categoria', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Nenhuma despesa sem categoria (recebimento sem categoria entra como Receita).'
                    else v_n || ' despesa(s) sem categoria não entram no DRE.' end);

  -- 6. Aviso: pago sem nenhum rastro no banco (ou no caixa).
  select count(*) into v_n from public.conciliacao_lancamentos l
   where l.situacao = 'sem_extrato' and l.status = 'paid' and l.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'pago_sem_banco', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pagos com rastro no banco ou no caixa', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todo pagamento tem rastro.' else v_n || ' lançamento(s) pago(s) sem linha do banco — confira na Conciliação.' end);

  -- 7. Aviso: "Outras despesas" costuma esconder o que merecia categoria própria.
  select count(*), coalesce(sum(amount), 0) into v_n, v_valor from public.payables
   where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category = 'Outras despesas';
  v_itens := v_itens || jsonb_build_object('chave', 'outras_despesas', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pouco em "Outras despesas"', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada em "Outras despesas".' else v_n || ' lançamento(s), ' || public._brl(v_valor) || ', em "Outras despesas".' end);

  return jsonb_build_object(
    'ano', p_ano, 'mes', p_mes,
    'pronto', not exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'bloqueia')::boolean and not (i ->> 'ok')::boolean),
    'itens', v_itens
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.checklist_do_mes(p_ano integer, p_mes integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.checklist_do_mes(p_ano integer, p_mes integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.checklist_do_mes(p_ano integer, p_mes integer) TO service_role;

-- ── public.classify_free_text_materials(p_textos text[]) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.classify_free_text_materials(p_textos text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- Classifica em LOTE, para a tela não fazer uma chamada por item. Devolve
  -- {texto: true|false}. A regra vive só em free_text_is_material — o front
  -- consome, não reimplementa: já temos a mesma conta de necessidade escrita em
  -- TypeScript, Deno e SQL, e não vale criar mais uma divergência possível.
  select coalesce(jsonb_object_agg(t, public.free_text_is_material(t)), '{}'::jsonb)
  from (select distinct unnest(coalesce(p_textos, '{}'::text[])) as t) s
  where t is not null;
$function$
;
COMMENT ON FUNCTION public.classify_free_text_materials(p_textos text[]) IS 'Classifica varios textos livres de uma vez (material x mao de obra). Existe para a tela nao reimplementar a regra em TypeScript.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.classify_free_text_materials(p_textos text[]) TO postgres;
GRANT EXECUTE ON FUNCTION public.classify_free_text_materials(p_textos text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.classify_free_text_materials(p_textos text[]) TO service_role;

-- ── public.classify_service_text(p_texto text) ── [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.classify_service_text(p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare k text; v text; s text;
begin
  k := regexp_replace(lower(unaccent(coalesce(p_texto,''))), '\s+', ' ', 'g');
  k := regexp_replace(k, '^(servico de |servico |ct - )', '');

  v := case
    when k ~ '(instala|instaca)'                              then 'instalacao'
    when k ~ '(substitui|subtitui|troca)'                     then 'substituicao'
    when k ~ '(reparo|repara|conserto|restaur|recondicion|correcao)' then 'reparo'
    when k ~ '(diagnost|analise|avalia|inspec|vistoria|teste|verifica)' then 'diagnostico'
    when k ~ '(manuten|revisao|limpeza|higieni|desincrust)'    then 'manutencao'
    when k ~ '(remocao|remover|desmontagem|retirada)'          then 'remocao'
    when k ~ '(configura|parametriz|programa|atualiza)'        then 'configuracao'
    when k ~ '(adequa|adapta|modifica|melhoria|upgrade|otimiza|desenvolvimento|confeccao|montagem|ajuste|realocacao|reajuste)' then 'adequacao'
    -- projeto e consultoria vêm ANTES de logística: "assessoria de projeto" é
    -- trabalho de prancheta, não deslocamento. Sem esta linha, sete serviços
    -- caíam em logística e herdavam o roteiro de quem viaja.
    when k ~ '(projeto|assessoria|consultoria|memorial|laudo)' then 'projeto'
    when k ~ '(frete|deslocamento|visita|hora tecnica|mao de obra)' then 'logistica'
    else null end;

  s := case
    when k ~ '(gas|glp|fogao|aquecedor|boiler|cooktop)'        then 'gas'
    when k ~ '(geladeira|geleira|ar condicionado|ar-condicionado|climatiz|freezer|condicionador|evaporador|chiller)' then 'refrigeracao'
    when k ~ '(agua|hidraulic|bomba d|mangueira|registro|chuveiro|torneira|pia|esgoto|caixa d|pvc|vazamento|escapamento|waterlock|misturador|calafetacao|box)' then 'hidraulico'
    when k ~ '(220v|110v|tomada de cais|quadro ac|ats|transferencia automatica|estabilizador|shore power|gerador)' then 'eletrico_ac'
    when k ~ '(bateria|litio|lifepo|inversor|dc-dc|dc/dc|fusivel|barramento|alternador|usina|victron|mppt|solar|fotovoltaic|12v|24v|shunt|isolador galvanico|carregador|conversor|painel eletric|chave de bateria|cabo eletric|terminal|instalacao eletrica)' then 'eletrico_dc'
    -- radar/plotter/nmea/ais: vocabulário náutico que faltava. "radar" não casa
    -- com "radio", e era o caso de duas OS reais.
    when k ~ '(gps|multimidia|multimedia|radio|radar|plotter|nmea|ais|antena|starlink|camera|transducer|display|sensor|alarme|som|alto falante|subwoofer|roteador|monitor|painel de instrumento|vhf|sonda|piloto automatico)' then 'eletronico'
    when k ~ '(guincho|fechadura|amortecedor|corredica|dobradica|suporte|rodado|pneu|roda|slide|esteira|parafus|manipulo|pedaleira|plataforma|passarela)' then 'mecanico'
    when k ~ '(teto|parede|piso|isolacao termica|acabamento|movel|armario|gaveta)' then 'estrutural'
    when k ~ '(luz|led|spot|farol|iluminacao)'                 then 'eletrico_dc'
    else null end;

  return jsonb_build_object('verbo', v, 'sistema', s,
    'confianca', case when v is not null and s is not null then 0.9
                      when v is not null or s is not null then 0.5 else 0 end);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.classify_service_text(p_texto text) TO postgres;
GRANT EXECUTE ON FUNCTION public.classify_service_text(p_texto text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.classify_service_text(p_texto text) TO service_role;

-- ── public.compose_route_for_service(p_service_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.compose_route_for_service(p_service_id uuid)
 RETURNS TABLE(seq integer, block text, title text, detail text, kind text, mode text, standard_minutes integer, is_killer boolean, requires_photo boolean, requires_measure text, measure_unit text, origem_bloco text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_verb text;
  v_sys text;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select service_verb, service_system into v_verb, v_sys
  from public.services where id = p_service_id;

  return query
  with partes as (
    select b.*, case b.block_role when 'abertura' then 1 when 'corpo' then 2 else 3 end as ordem_bloco
    from public.service_step_blocks b
    where b.active
      and ((b.block_role in ('abertura','fechamento') and b.applies_to_system = v_sys)
        or (b.block_role = 'corpo' and b.applies_to_verb = v_verb))
  )
  select
    (row_number() over (order by p.ordem_bloco, p.seq))::integer,
    case p.block_role when 'abertura' then 'Preparação'
                      when 'corpo' then 'Execução'
                      else 'Fechamento' end,
    p.title, p.detail, p.kind, p.mode, p.standard_minutes, p.is_killer,
    p.requires_photo, p.requires_measure, p.measure_unit,
    p.block_role || ' · ' || coalesce(p.applies_to_system, p.applies_to_verb)
  from partes p
  order by p.ordem_bloco, p.seq;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.compose_route_for_service(p_service_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.compose_route_for_service(p_service_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compose_route_for_service(p_service_id uuid) TO service_role;

-- ── public.compose_survey_for_axes(p_system text, p_verb text, p_mode text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.compose_survey_for_axes(p_system text DEFAULT NULL::text, p_verb text DEFAULT NULL::text, p_mode text DEFAULT 'local'::text)
 RETURNS TABLE(id uuid, seq integer, question text, help_text text, answer_type text, options jsonb, price_impact text, ask_remotely boolean, origem text, expected_unit text, min_expected numeric, max_expected numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
begin
  if p_system is null and p_verb is null then
    return;
  end if;

  return query
  select t.id, t.seq, t.question, t.help_text, t.answer_type, t.options,
         t.price_impact, t.ask_remotely,
         case when t.applies_to_system is not null then 'sistema' else 'verbo' end,
         t.expected_unit, t.min_expected, t.max_expected
  from public.service_survey_templates t
  where t.active
    and (p_mode <> 'remoto' or t.ask_remotely)
    and (
         (p_system is not null and t.applies_to_system = p_system)
      or (p_verb   is not null and t.applies_to_verb   = p_verb)
    )
  order by case t.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
           t.seq
  limit 9;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.compose_survey_for_axes(p_system text, p_verb text, p_mode text) TO postgres;
GRANT EXECUTE ON FUNCTION public.compose_survey_for_axes(p_system text, p_verb text, p_mode text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compose_survey_for_axes(p_system text, p_verb text, p_mode text) TO service_role;

-- ── public.compose_survey_for_order(p_service_order_id uuid, p_mode text, p_limit integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.compose_survey_for_order(p_service_order_id uuid, p_mode text DEFAULT 'local'::text, p_limit integer DEFAULT 12)
 RETURNS TABLE(id uuid, seq integer, question text, help_text text, answer_type text, options jsonb, price_impact text, ask_remotely boolean, origem text, expected_unit text, min_expected numeric, max_expected numeric, eixo text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  return query
  with eixos as (
    -- O sistema da LINHA ganha do sistema do catálogo: é ele que o técnico
    -- escolheu para esta visita. O do catálogo entra quando a linha não diz.
    select distinct
      coalesce(sos.service_system, s.service_system) as sistema,
      s.service_verb as verbo
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
  ),
  candidatas as (
    select t.*, coalesce(t.applies_to_system, t.applies_to_verb) as eixo_da_pergunta
    from public.service_survey_templates t
    where t.active
      and t.service_id is null
      and (p_mode <> 'remoto' or t.ask_remotely)
      and exists (
        select 1 from eixos e
        where (t.applies_to_system is not null and t.applies_to_system = e.sistema)
           or (t.applies_to_verb   is not null and t.applies_to_verb   = e.verbo)
      )
  ),
  ordenadas as (
    select c.*,
      -- Posição dentro do próprio eixo, por impacto no preço.
      row_number() over (
        partition by c.eixo_da_pergunta
        order by case c.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
                 c.seq
      ) as posicao_no_eixo
    from candidatas c
  )
  select o.id, o.seq, o.question, o.help_text, o.answer_type, o.options,
         o.price_impact, o.ask_remotely,
         case when o.applies_to_system is not null then 'sistema' else 'verbo' end,
         o.expected_unit, o.min_expected, o.max_expected,
         o.eixo_da_pergunta
  from ordenadas o
  -- Rodízio: todas as primeiras de cada eixo, depois todas as segundas.
  order by o.posicao_no_eixo,
           case o.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
           o.eixo_da_pergunta, o.seq
  limit greatest(coalesce(p_limit, 12), 1);
end;
$function$
;
COMMENT ON FUNCTION public.compose_survey_for_order(p_service_order_id uuid, p_mode text, p_limit integer) IS 'Questionário de uma ORDEM inteira, a partir dos sistemas e verbos de todas as
   suas linhas. É o que permite levantar numa visita de avaliação, onde o
   serviço é genérico ("diagnóstico no local") e quem diz o que será avaliado é
   o técnico, marcando o sistema em cada linha. Rodízio entre eixos para que
   nenhum sistema da visita fique sem pergunta.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.compose_survey_for_order(p_service_order_id uuid, p_mode text, p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.compose_survey_for_order(p_service_order_id uuid, p_mode text, p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compose_survey_for_order(p_service_order_id uuid, p_mode text, p_limit integer) TO service_role;

-- ── public.compose_survey_for_service(p_service_id uuid, p_mode text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.compose_survey_for_service(p_service_id uuid, p_mode text DEFAULT 'local'::text)
 RETURNS TABLE(id uuid, seq integer, question text, help_text text, answer_type text, options jsonb, price_impact text, ask_remotely boolean, origem text, expected_unit text, min_expected numeric, max_expected numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare v_verb text; v_sys text; v_proprias integer;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select service_verb, service_system into v_verb, v_sys
  from public.services where services.id = p_service_id;

  select count(*) into v_proprias
  from public.service_survey_templates t
  where t.service_id = p_service_id and t.active;

  return query
  select t.id, t.seq, t.question, t.help_text, t.answer_type, t.options,
         t.price_impact, t.ask_remotely,
         case when t.service_id is not null then 'serviço'
              when t.applies_to_system is not null then 'sistema'
              else 'verbo' end,
         t.expected_unit, t.min_expected, t.max_expected
  from public.service_survey_templates t
  where t.active
    and (p_mode <> 'remoto' or t.ask_remotely)
    and (
      (v_proprias > 0 and t.service_id = p_service_id)
      or (v_proprias = 0 and (
            (t.applies_to_system is not null and t.applies_to_system = v_sys)
         or (t.applies_to_verb   is not null and t.applies_to_verb   = v_verb)))
    )
  order by case t.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
           t.seq
  limit 9;  -- teto do P16: mais que nove perguntas ninguém responde em campo
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.compose_survey_for_service(p_service_id uuid, p_mode text) TO postgres;
GRANT EXECUTE ON FUNCTION public.compose_survey_for_service(p_service_id uuid, p_mode text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compose_survey_for_service(p_service_id uuid, p_mode text) TO service_role;

-- ── public.compute_next_run(_from timestamp with time zone, _recurrence_type text, _days_of_week integer[], _day_of_month integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.compute_next_run(_from timestamp with time zone, _recurrence_type text, _days_of_week integer[], _day_of_month integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  base timestamptz := _from + interval '1 minute';
  candidate timestamptz;
  i int;
  dow int;
BEGIN
  IF _recurrence_type = 'once' THEN
    RETURN NULL;
  ELSIF _recurrence_type = 'daily' THEN
    RETURN _from + interval '1 day';
  ELSIF _recurrence_type = 'weekly' THEN
    IF _days_of_week IS NULL OR array_length(_days_of_week, 1) = 0 THEN
      RETURN base + interval '7 days';
    END IF;
    FOR i IN 0..7 LOOP
      candidate := base + (i || ' days')::interval;
      dow := EXTRACT(DOW FROM candidate)::int;
      IF dow = ANY(_days_of_week) THEN
        RETURN candidate;
      END IF;
    END LOOP;
    RETURN base + interval '7 days';
  ELSIF _recurrence_type = 'monthly' THEN
    candidate := base + interval '1 month';
    IF _day_of_month IS NOT NULL THEN
      candidate := date_trunc('month', candidate) + ((_day_of_month - 1) || ' days')::interval
                   + (EXTRACT(HOUR FROM _from) || ' hours')::interval
                   + (EXTRACT(MINUTE FROM _from) || ' minutes')::interval;
    END IF;
    RETURN candidate;
  END IF;
  RETURN NULL;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.compute_next_run(_from timestamp with time zone, _recurrence_type text, _days_of_week integer[], _day_of_month integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.compute_next_run(_from timestamp with time zone, _recurrence_type text, _days_of_week integer[], _day_of_month integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compute_next_run(_from timestamp with time zone, _recurrence_type text, _days_of_week integer[], _day_of_month integer) TO service_role;

-- ── public.compute_product_fiscal_complete() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.compute_product_fiscal_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  ncm_digits  text := regexp_replace(coalesce(new.ncm, ''),  '\D', '', 'g');
  cfop_digits text := regexp_replace(coalesce(new.cfop, ''), '\D', '', 'g');
  ok boolean;
begin
  ok := length(ncm_digits) = 8 and length(cfop_digits) = 4;
  if new.use_global_fiscal is false then
    ok := ok
      and (new.csosn is not null and new.csosn <> '')
      and (new.fiscal_origin is not null);
  end if;
  new.fiscal_complete := ok;
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.compute_product_fiscal_complete() TO postgres;
GRANT EXECUTE ON FUNCTION public.compute_product_fiscal_complete() TO service_role;

-- ── public.compute_purchase_needs(p_so_id uuid, p_parts jsonb, p_free jsonb, p_avail jsonb, p_on_order jsonb) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.compute_purchase_needs(p_so_id uuid, p_parts jsonb, p_free jsonb, p_avail jsonb, p_on_order jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
with
avail as (
  select e->>'id' as product_id,
         greatest(0, coalesce((e->>'stock_quantity')::numeric, 0)
                   - coalesce((e->>'reserved_quantity')::numeric, 0)) as total_available
  from jsonb_array_elements(coalesce(p_avail, '[]'::jsonb)) e
),
on_order as (
  select e->>'product_id' as product_id,
         sum(greatest(0, coalesce((e->>'quantity')::numeric, 0)
                       - coalesce((e->>'received_qty')::numeric, 0))) as total_on_order
  from jsonb_array_elements(coalesce(p_on_order, '[]'::jsonb)) e
  group by 1
),
parts as (
  select e->>'id' as id, e->>'product_id' as product_id,
         coalesce((e->>'quantity')::numeric, 0) as required,
         coalesce((e->>'unit_cost_snapshot')::numeric, 0) as unit_cost,
         coalesce(e->>'product_name', 'Produto') as description,
         e->>'product_unit' as unit, ord as seq
  from jsonb_array_elements(coalesce(p_parts, '[]'::jsonb)) with ordinality as t(e, ord)
),
parts_ctx as (
  select pt.*, coalesce(a.total_available, 0) as total_available,
         coalesce(o.total_on_order, 0) as total_on_order,
         coalesce(sum(pt.required) over (partition by pt.product_id order by pt.seq
           rows between unbounded preceding and 1 preceding), 0) as required_before
  from parts pt
  left join avail a on a.product_id = pt.product_id
  left join on_order o on o.product_id = pt.product_id
),
parts_stock as (
  select pc.*, greatest(0, least(pc.required, greatest(0, pc.total_available - pc.required_before))) as available
  from parts_ctx pc
),
parts_gap as (select ps.*, greatest(0, ps.required - ps.available) as after_stock from parts_stock ps),
parts_gap_ctx as (
  select pg.*, coalesce(sum(pg.after_stock) over (partition by pg.product_id order by pg.seq
    rows between unbounded preceding and 1 preceding), 0) as after_before
  from parts_gap pg
),
parts_final as (
  select pgc.*, greatest(0, least(pgc.after_stock, greatest(0, pgc.total_on_order - pgc.after_before))) as on_order_qty
  from parts_gap_ctx pgc
),
parts_out as (
  select pf.id as source_id, 'part'::text as origin, pf.product_id, pf.description, pf.unit,
         pf.required, pf.available, pf.on_order_qty as on_order,
         greatest(0, pf.after_stock - pf.on_order_qty) as shortage, pf.unit_cost, pf.seq, 0 as grp
  from parts_final pf
),
free_out as (
  select e->>'id' as source_id, 'free_text'::text as origin, null::text as product_id,
         e->>'name_snapshot' as description, null::text as unit,
         coalesce((e->>'quantity')::numeric, 0) as required,
         0::numeric as available, 0::numeric as on_order,
         coalesce((e->>'quantity')::numeric, 0) as shortage,
         coalesce((e->>'unit_price_snapshot')::numeric, 0) as unit_cost,
         ord as seq, 1 as grp
  from jsonb_array_elements(coalesce(p_free, '[]'::jsonb)) with ordinality as t(e, ord)
  where (e->>'service_id') is null
    and e->>'billing_unit_snapshot' = 'unit'
    and coalesce((e->>'quantity')::numeric, 0) > 0
    -- Mão de obra digitada como texto livre não é compra: "Instalação do
    -- Carregador" e "Cabo 16mm²" chegam idênticos ao banco, e sem isto os dois
    -- apareciam na mesma lista de cotação.
    and public.free_text_is_material(e->>'name_snapshot')
),
ranked as (
  select o.*, case
      when o.origin = 'free_text' then 'uncatalogued'
      when o.shortage = 0 and o.required - o.available = 0 then 'ok'
      when o.shortage = 0 then 'on_order'
      when o.available > 0 then 'partial' else 'missing' end as status,
    case
      when o.origin = 'free_text' then 2
      when o.shortage = 0 and o.required - o.available = 0 then 4
      when o.shortage = 0 then 3
      when o.available > 0 then 1 else 0 end as rank
  from (select * from parts_out union all select * from free_out) o
),
item as (
  select r.*, jsonb_build_object(
    'sourceId', r.source_id, 'origin', r.origin, 'productId', r.product_id,
    'description', r.description, 'unit', r.unit, 'required', r.required,
    'available', r.available, 'onOrder', r.on_order, 'shortage', r.shortage,
    'status', r.status, 'unitCost', r.unit_cost) as js
  from ranked r
)
select jsonb_build_object(
  'serviceOrderId', p_so_id,
  'items',        coalesce((select jsonb_agg(js order by grp, seq) from item), '[]'::jsonb),
  'shortages',    coalesce((select jsonb_agg(js order by rank, shortage desc) from item where shortage > 0), '[]'::jsonb),
  'shortageCount',(select count(*) from item where shortage > 0),
  'estimatedCost',coalesce((select sum(shortage * unit_cost) from item where shortage > 0), 0),
  'needsPurchase',exists (select 1 from item where shortage > 0)
);
$function$
;
COMMENT ON FUNCTION public.compute_purchase_needs(p_so_id uuid, p_parts jsonb, p_free jsonb, p_avail jsonb, p_on_order jsonb) IS 'Calculo puro da necessidade de compra (sem I/O). Espelha computePurchaseNeeds de src/lib/purchase-needs.ts. A ordem dos arrays decide quem consome o estoque primeiro.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.compute_purchase_needs(p_so_id uuid, p_parts jsonb, p_free jsonb, p_avail jsonb, p_on_order jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.compute_purchase_needs(p_so_id uuid, p_parts jsonb, p_free jsonb, p_avail jsonb, p_on_order jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compute_purchase_needs(p_so_id uuid, p_parts jsonb, p_free jsonb, p_avail jsonb, p_on_order jsonb) TO service_role;

-- ── public.conciliar_lancamento(p_tipo text, p_id uuid, p_transacao uuid, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.conciliar_lancamento(p_tipo text, p_id uuid, p_transacao uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx public.bank_transactions%rowtype;
  v_aberto boolean;
  v_saldo numeric;
  v_valor_pago numeric := 0;
  v_pago numeric;
  v_pagamento uuid := null;
  v_pagamento_existente uuid := null;
  v_metodo text;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;

  if p_tipo = 'payable' then
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Lançamento cancelado não se concilia.'; end if;
  if v_antes ->> 'bank_transaction_id' is not null then
    raise exception 'Este lançamento já está casado com outra linha do extrato. Desfaça o vínculo antes.';
  end if;

  select * into v_tx from public.bank_transactions where id = p_transacao for update;
  if v_tx.id is null then raise exception 'Linha do extrato não encontrada.'; end if;
  if (p_tipo = 'payable' and v_tx.transaction_type <> 'debit')
     or (p_tipo = 'receivable' and v_tx.transaction_type <> 'credit') then
    raise exception 'Conta a pagar só casa com saída do banco; conta a receber, só com entrada.';
  end if;
  if v_tx.dismissed_kind is not null then
    raise exception 'Essa linha do extrato está fora da fila (%). Traga-a de volta antes de casar.', v_tx.dismissed_kind;
  end if;
  if exists (select 1 from public.payables where bank_transaction_id = p_transacao)
     or exists (select 1 from public.receivables where bank_transaction_id = p_transacao) then
    raise exception 'Essa linha do extrato já está vinculada a outro lançamento.';
  end if;
  -- Um Pix pode pagar várias contas (F2, 02/10/2026): entrada que já paga alguma conta não se
  -- casa de novo aqui — o que sobrou dela se aplica em "Este Pix paga…".
  if exists (select 1 from public.payments where bank_transaction_id = p_transacao and status = 'confirmed') then
    raise exception 'Essa linha do extrato já paga outra(s) conta(s). Para aplicar o que sobrou dela, use "Este Pix paga…".';
  end if;

  v_pago := coalesce((v_antes ->> 'paid_amount')::numeric, 0);
  v_aberto := v_antes ->> 'status' in ('pending', 'overdue', 'partially_paid');

  if v_aberto then
    perform public._recusa_se_mes_fechado(v_tx.transaction_date, 'registrar pagamento nesta data');
    v_saldo := coalesce((v_antes ->> 'balance_amount')::numeric, (v_antes ->> 'amount')::numeric - v_pago);
    v_valor_pago := round(least(v_saldo, v_tx.amount), 2);
    if v_valor_pago > 0 then
      v_metodo := case
        when coalesce(v_tx.payment_method, '') ilike '%pix%' or coalesce(v_tx.description, '') ilike '%pix%' then 'pix'
        when v_tx.card_last_digits is not null then 'debit_card'
        else 'bank_transfer' end;
      insert into public.payments (payable_id, receivable_id, amount, payment_date, payment_method,
                                   installments, card_fee_percent, net_amount, notes, status)
      values (
        case when p_tipo = 'payable' then p_id end,
        case when p_tipo = 'receivable' then p_id end,
        v_valor_pago, v_tx.transaction_date, v_metodo, 1, 0, v_valor_pago,
        'Conciliado com o extrato de ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY'),
        'confirmed'
      ) returning id into v_pagamento;
      v_pago := v_pago + v_valor_pago;
    end if;
  else
    -- Já pago: qual pagamento esta linha do extrato é? O de valor mais próximo, ainda sem
    -- linha do extrato, dentro de 2% (tarifa de maquininha costuma ficar abaixo disso).
    -- Pagamento que já veio de outra entrada fica de fora (o gatilho trocaria a origem dele).
    select p.id into v_pagamento_existente
      from public.payments p
     where p.status = 'confirmed'
       and ((p_tipo = 'payable' and p.payable_id = p_id) or (p_tipo = 'receivable' and p.receivable_id = p_id))
       and not exists (select 1 from public.bank_transactions t where t.reconciled_payment_id = p.id)
       and p.bank_transaction_id is null
       and abs(p.amount - v_tx.amount) <= greatest(0.01, p.amount * 0.02)
     order by abs(p.amount - v_tx.amount), abs(p.payment_date - v_tx.transaction_date)
     limit 1;
  end if;

  if p_tipo = 'payable' then
    update public.payables set bank_transaction_id = p_transacao,
           paid_amount = v_pago,
           balance_amount = greatest(0, amount - v_pago),
           status = public._situacao_do_saldo(amount, v_pago, status)
     where id = p_id;
  else
    update public.receivables set bank_transaction_id = p_transacao,
           paid_amount = v_pago,
           balance_amount = greatest(0, amount - v_pago),
           status = public._situacao_do_saldo(amount, v_pago, status)
     where id = p_id;
  end if;

  update public.bank_transactions
     set reconciled = true, reconciled_payment_id = coalesce(v_pagamento, v_pagamento_existente)
   where id = p_transacao;
  update public.finance_review_queue
     set status = 'superseded', decision_note = 'Casada com um lançamento que já existia'
   where bank_transaction_id = p_transacao and status = 'pending';

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'conciliou', v_autor, p_transacao,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    v_tx.amount,
    left(coalesce(v_antes ->> 'description', '') || ' ↔ ' || coalesce(v_tx.counterparty_name, v_tx.description, '')
         || ' de ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY'), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('bank_transaction_id', p_transacao, 'pagamento_registrado', v_pagamento,
                       'pagamento_existente', v_pagamento_existente, 'valor_pago', v_valor_pago)
  );

  return jsonb_build_object(
    'ok', true,
    'pagamento_registrado', v_pagamento is not null,
    'valor_pago', v_valor_pago,
    'message', case
      when v_pagamento is not null
        then 'Conciliado. Pagamento de ' || public._brl(v_valor_pago) || ' registrado em ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY') || '.'
      when v_pagamento_existente is not null
        then 'Conciliado com o pagamento que já estava lançado — nenhuma receita nova foi criada.'
      else 'Conciliado.' end
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.conciliar_lancamento(p_tipo text, p_id uuid, p_transacao uuid, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.conciliar_lancamento(p_tipo text, p_id uuid, p_transacao uuid, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.conciliar_lancamento(p_tipo text, p_id uuid, p_transacao uuid, p_autor uuid) TO service_role;

-- ── public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb, p_purchase_order_id uuid) ── SECURITY DEFINER [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid DEFAULT NULL::uuid, p_manual_mappings jsonb DEFAULT '[]'::jsonb, p_purchase_order_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_status      text;
  v_items       jsonb;
  v_total       numeric;
  v_nfe_number  text;
  v_issuer_name text;
  v_xml         text;
  v_issue_ts    timestamptz;
  v_issued_ts   timestamptz;
  v_item        RECORD;
  v_match       RECORD;
  v_manual      uuid;
  v_forcar      boolean;
  v_product_id  uuid;
  v_reason      text;
  v_created     int := 0;
  v_moved       int := 0;
  v_payable_id  uuid;
  v_margin      numeric;
  v_cat_id      uuid;
  v_old_cost    numeric;
  v_sale        numeric;
  v_detail      jsonb := '[]'::jsonb;
  v_prazo       int;
  -- Parcelas
  v_emissao_real   date;
  v_emissao        date;
  v_a_vista        boolean := false;
  v_desc_base      text;
  v_dup            RECORD;
  v_n_dups         int := 0;
  v_soma_dups      numeric := 0;
  v_parcela        int := 0;
  v_credito        numeric := 0;
  v_credito_dentro boolean := false;
  v_credito_fora   boolean := false;
  v_credito_usado  boolean := false;
  v_venc           date;
  v_cand           jsonb;
  v_ids            uuid[] := '{}';
  v_parcelas       jsonb := '[]'::jsonb;
  c_obs_credito    constant text := 'Paga com crédito do fornecedor (carta de crédito), como a nota informa: não sai do banco.';
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status, items, total_amount, nfe_number, issuer_name, xml_content, issue_date, issued_at
    INTO v_status, v_items, v_total, v_nfe_number, v_issuer_name, v_xml, v_issue_ts, v_issued_ts
    FROM fiscal_notes WHERE id = p_note_id
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Esta nota já foi processada ou cancelada (status: %).', v_status;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, description text, quantity numeric, unit_price numeric
  ) LOOP
    IF v_item.quantity IS NULL OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Item % (%): quantidade ausente ou inválida no XML. Confira o arquivo.',
        coalesce(v_item.index, 0), coalesce(v_item.description, 'sem descrição');
    END IF;
    IF v_item.unit_price IS NULL OR v_item.unit_price < 0 THEN
      RAISE EXCEPTION 'Item % (%): valor unitário ausente ou inválido no XML.',
        coalesce(v_item.index, 0), coalesce(v_item.description, 'sem descrição');
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, sku_supplier text, description text, ncm text, unit text,
    quantity numeric, unit_price numeric, total_price numeric,
    barcode text, origin text
  ) LOOP
    v_manual := NULL; v_forcar := false;
    SELECT (val->>'internal_product_id')::uuid, coalesce((val->>'force_new')::boolean, false)
      INTO v_manual, v_forcar
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
      LIMIT 1;

    IF v_forcar THEN
      v_product_id := NULL; v_reason := 'novo';
    ELSE
      SELECT * INTO v_match FROM match_nfe_item(
        p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);
      v_product_id := v_match.product_id;
      v_reason     := v_match.match_reason;
    END IF;

    IF v_product_id IS NULL THEN
      SELECT id, coalesce(default_profit_margin, 30) INTO v_cat_id, v_margin
        FROM product_categories WHERE lower(name) = 'importados' AND active LIMIT 1;
      v_margin := coalesce(v_margin, 30);

      INSERT INTO products (
        name, sku, barcode, category, product_category_id, unit,
        cost_price, sale_price, stock_quantity, ncm, fiscal_origin,
        supplier_id, active, fiscal_complete
      ) VALUES (
        v_item.description,
        v_item.sku_supplier,
        v_item.barcode,
        'Importados',
        v_cat_id,
        coalesce(nullif(btrim(v_item.unit), ''), 'UN'),
        v_item.unit_price,
        round(v_item.unit_price * (1 + v_margin / 100), 2),
        0,
        regexp_replace(coalesce(v_item.ncm, ''), '\D', '', 'g'),
        coalesce(nullif(regexp_replace(coalesce(v_item.origin, ''), '\D', '', 'g'), '')::int, 0),
        p_supplier_id,
        true,
        false
      ) RETURNING id INTO v_product_id;
      v_created := v_created + 1;
    ELSE
      UPDATE products
         SET barcode = coalesce(barcode, nullif(v_item.barcode, '')),
             supplier_id = coalesce(supplier_id, p_supplier_id),
             updated_at = now()
       WHERE id = v_product_id;
    END IF;

    IF p_supplier_id IS NOT NULL AND coalesce(v_item.sku_supplier, '') <> '' THEN
      INSERT INTO supplier_product_mappings (supplier_id, supplier_sku, supplier_description, internal_product_id)
      VALUES (p_supplier_id, v_item.sku_supplier, v_item.description, v_product_id)
      ON CONFLICT (supplier_id, supplier_sku) DO UPDATE
        SET supplier_description = EXCLUDED.supplier_description,
            internal_product_id  = EXCLUDED.internal_product_id,
            updated_at = now();
    END IF;

    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta, unit_cost_snapshot,
      reference_type, reference_id, notes
    ) VALUES (
      v_product_id, 'purchase', v_item.quantity, v_item.unit_price,
      'import', p_note_id, 'Entrada via NF-e ' || coalesce(v_nfe_number, '')
    );
    v_moved := v_moved + 1;

    SELECT cost_price, sale_price INTO v_old_cost, v_sale FROM products WHERE id = v_product_id;
    SELECT coalesce(default_profit_margin, 30) INTO v_margin
      FROM product_categories pc
      JOIN products p ON p.id = v_product_id
      WHERE pc.id = p.product_category_id OR lower(pc.name) = lower(p.category)
      LIMIT 1;
    v_margin := coalesce(v_margin, 30);
    IF v_item.unit_price > coalesce(v_old_cost, 0)
       OR coalesce(v_sale, 0) < v_item.unit_price * (1 + v_margin / 100) THEN
      INSERT INTO price_update_suggestions (
        product_id, fiscal_note_id, current_sale_price, suggested_sale_price, margin_percent
      ) VALUES (
        v_product_id, p_note_id, v_sale,
        round(v_item.unit_price * (1 + v_margin / 100), 2), v_margin
      );
    END IF;

    UPDATE products
       SET cost_price = v_item.unit_price,
           last_stock_entry_at = now(),
           updated_at = now()
     WHERE id = v_product_id;

    v_detail := v_detail || jsonb_build_object(
      'sku_supplier', v_item.sku_supplier,
      'description',  v_item.description,
      'product_id',   v_product_id,
      'match_reason', v_reason,
      'quantity',     v_item.quantity
    );
  END LOOP;

  IF p_supplier_id IS NOT NULL THEN
    SELECT nullif(regexp_replace(coalesce(payment_terms, ''), '\D', '', 'g'), '')::int
      INTO v_prazo FROM suppliers WHERE id = p_supplier_id;
    IF v_prazo IS NULL OR v_prazo <= 0 OR v_prazo > 365 THEN v_prazo := 28; END IF;

    -- A data da NOTA: o dia local que o próprio XML diz; sem ele, o gravado, no fuso de São Paulo.
    v_emissao_real := coalesce(
      nullif(substring(coalesce(v_xml, '') from '<dhEmi>(\d{4}-\d{2}-\d{2})'), '')::date,
      nullif(substring(coalesce(v_xml, '') from '<dEmi>(\d{4}-\d{2}-\d{2})'), '')::date,
      (v_issued_ts AT TIME ZONE 'America/Sao_Paulo')::date,
      (v_issue_ts AT TIME ZONE 'America/Sao_Paulo')::date,
      now()::date);
    -- A competência: nota de mês já FECHADO entra no mês de hoje — o fechado não muda sem motivo,
    -- e a mercadoria não pode ficar fora do estoque porque a trava recusaria a conta. A data real
    -- continua valendo para os vencimentos e para achar o pagamento no banco.
    v_emissao := v_emissao_real;
    IF public.periodo_esta_fechado(v_emissao) THEN
      v_emissao := now()::date;
    END IF;
    v_desc_base := 'Compra ref. NF-e ' || coalesce(v_nfe_number, '') || ' - ' || coalesce(v_issuer_name, '');

    -- Quanto a nota diz ter sido pago com crédito do fornecedor.
    SELECT coalesce(sum(nullif(substring(b[1] from '<vPag>([0-9.]+)</vPag>'), '')::numeric), 0)
      INTO v_credito
      FROM regexp_matches(coalesce(v_xml, ''), '<detPag>(.*?)</detPag>', 'g') AS b
     WHERE substring(b[1] from '<tPag>(\d+)</tPag>') IN ('19', '21')
        OR (substring(b[1] from '<tPag>(\d+)</tPag>') = '99'
            AND translate(upper(coalesce(substring(b[1] from '<xPag>([^<]*)</xPag>'), '')),
                          'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC')
                ~ '(CARTA DE CREDITO|CREDITO (DE|DO|DA|EM|NA) (CLIENTE|LOJA|FORNECEDOR|DEVOLUCAO)|CREDITO LOJA|VALE CREDITO)'
            AND translate(upper(coalesce(substring(b[1] from '<xPag>([^<]*)</xPag>'), '')),
                          'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC')
                !~ '(CARTAO|CREDIARIO)');

    -- Pago na hora (à vista, ou por Pix/débito/transferência/cartão): sem parcela, vence na emissão.
    SELECT exists (
      SELECT 1 FROM regexp_matches(coalesce(v_xml, ''), '<detPag>(.*?)</detPag>', 'g') AS b
       WHERE substring(b[1] from '<indPag>(\d)</indPag>') = '0'
          OR substring(b[1] from '<tPag>(\d+)</tPag>') IN ('01', '03', '04', '17', '18', '20'))
      INTO v_a_vista;

    SELECT count(*), coalesce(sum(nullif(substring(d[1] from '<vDup>([0-9.]+)</vDup>'), '')::numeric), 0)
      INTO v_n_dups, v_soma_dups
      FROM regexp_matches(coalesce(v_xml, ''), '<dup>(.*?)</dup>', 'g') AS d;

    -- Onde está o crédito: DENTRO das parcelas (a soma delas é o total) ou FORA delas.
    IF v_credito > 0 THEN
      v_credito_dentro := v_n_dups > 0 AND abs(v_soma_dups - v_total) < 0.05;
      v_credito_fora := NOT v_credito_dentro AND abs(v_soma_dups + v_credito - v_total) < 0.05;
    END IF;

    -- Crédito FORA das parcelas (ou a nota inteira paga com crédito): uma conta paga, à parte.
    IF v_credito_fora THEN
      INSERT INTO payables (
        supplier_id, supplier_name, amount, paid_amount, balance_amount, description,
        issue_date, due_date, status, expense_category, origin, fiscal_note_id, payment_method, notes
      ) VALUES (
        p_supplier_id, v_issuer_name, v_credito, v_credito, 0,
        v_desc_base || CASE WHEN v_n_dups > 0 THEN ' (parte paga com crédito)' ELSE '' END,
        v_emissao, v_emissao_real, 'paid', 'Compras de mercadorias', 'fiscal_note', p_note_id,
        'credito_fornecedor', c_obs_credito
      ) RETURNING id INTO v_payable_id;
      v_credito_usado := true;
      v_ids := v_ids || v_payable_id;
      v_parcelas := v_parcelas || jsonb_build_object('parcela', 0, 'valor', v_credito, 'vencimento', v_emissao_real,
        'payable_id', v_payable_id, 'como', 'credito_do_fornecedor', 'candidatos', '[]'::jsonb);
    END IF;

    IF v_n_dups > 0 THEN
      FOR v_dup IN
        SELECT substring(d[1] from '<nDup>([^<]*)</nDup>') AS numero,
               nullif(substring(d[1] from '<dVenc>(\d{4}-\d{2}-\d{2})</dVenc>'), '')::date AS venc,
               nullif(substring(d[1] from '<vDup>([0-9.]+)</vDup>'), '')::numeric AS valor
          FROM regexp_matches(v_xml, '<dup>(.*?)</dup>', 'g') AS d
         ORDER BY 2 NULLS LAST, 1
      LOOP
        v_parcela := v_parcela + 1;
        CONTINUE WHEN v_dup.valor IS NULL OR v_dup.valor <= 0;

        IF v_credito_dentro AND NOT v_credito_usado AND abs(v_dup.valor - v_credito) < 0.01 THEN
          -- A parcela que a própria nota diz ter sido paga com crédito do fornecedor.
          INSERT INTO payables (
            supplier_id, supplier_name, amount, paid_amount, balance_amount, description,
            issue_date, due_date, status, expense_category, origin, fiscal_note_id, payment_method, notes
          ) VALUES (
            p_supplier_id, v_issuer_name, v_dup.valor, v_dup.valor, 0,
            v_desc_base || ' (parcela ' || v_parcela || '/' || v_n_dups || ')',
            v_emissao, coalesce(v_dup.venc, v_emissao_real), 'paid', 'Compras de mercadorias', 'fiscal_note', p_note_id,
            'credito_fornecedor', c_obs_credito
          ) RETURNING id INTO v_payable_id;
          v_credito_usado := true;
          v_parcelas := v_parcelas || jsonb_build_object('parcela', v_parcela, 'valor', v_dup.valor,
            'vencimento', v_dup.venc, 'payable_id', v_payable_id, 'como', 'credito_do_fornecedor',
            'candidatos', '[]'::jsonb);
        ELSE
          v_venc := coalesce(v_dup.venc, v_emissao_real + v_prazo);
          v_cand := public._pagamentos_que_podem_ser_a_parcela(p_supplier_id, v_dup.valor, v_venc, v_emissao_real);
          INSERT INTO payables (
            supplier_id, supplier_name, amount, balance_amount, description,
            issue_date, due_date, status, expense_category, origin, fiscal_note_id, notes
          ) VALUES (
            p_supplier_id, v_issuer_name, v_dup.valor, v_dup.valor,
            v_desc_base || ' (parcela ' || v_parcela || '/' || v_n_dups || ')',
            v_emissao, v_venc, 'pending', 'Compras de mercadorias', 'fiscal_note', p_note_id,
            CASE WHEN jsonb_array_length(v_cand) > 0
              THEN 'Pode já ter sido paga: há pagamento de mesmo valor a este fornecedor, lançado pelo Extrato. Confirme na importação da nota.'
            END
          ) RETURNING id INTO v_payable_id;
          v_parcelas := v_parcelas || jsonb_build_object('parcela', v_parcela, 'valor', v_dup.valor,
            'vencimento', v_venc, 'payable_id', v_payable_id, 'como', 'a_pagar', 'candidatos', v_cand);
        END IF;
        v_ids := v_ids || v_payable_id;
      END LOOP;
    ELSIF NOT v_credito_fora THEN
      -- Sem parcelas na nota: uma conta com o total — à vista vence na emissão; a prazo, no prazo
      -- do fornecedor a partir da emissão.
      v_venc := CASE WHEN v_a_vista THEN v_emissao_real ELSE v_emissao_real + v_prazo END;
      v_cand := public._pagamentos_que_podem_ser_a_parcela(p_supplier_id, v_total, v_emissao_real, v_emissao_real);
      INSERT INTO payables (
        supplier_id, supplier_name, amount, balance_amount, description,
        issue_date, due_date, status, expense_category, origin, fiscal_note_id, notes
      ) VALUES (
        p_supplier_id, v_issuer_name, v_total, v_total, v_desc_base,
        v_emissao, v_venc, 'pending', 'Compras de mercadorias', 'fiscal_note', p_note_id,
        CASE WHEN jsonb_array_length(v_cand) > 0
          THEN 'Pode já ter sido paga: há pagamento de mesmo valor a este fornecedor, lançado pelo Extrato. Confirme na importação da nota.'
        END
      ) RETURNING id INTO v_payable_id;
      v_ids := v_ids || v_payable_id;
      v_parcelas := v_parcelas || jsonb_build_object('parcela', 1, 'valor', v_total, 'vencimento', v_venc,
        'payable_id', v_payable_id, 'como', 'a_pagar', 'candidatos', v_cand);
    END IF;

    -- Crédito que não bate com nada: as parcelas ficam como estão, e a primeira conta leva o aviso.
    IF v_credito > 0 AND NOT v_credito_usado AND array_length(v_ids, 1) > 0 THEN
      UPDATE payables
         SET notes = btrim(coalesce(notes, '') || ' A nota informa R$ '
                     || replace(to_char(v_credito, 'FM999999990.00'), '.', ',')
                     || ' pagos com crédito do fornecedor, e o valor não bate com as parcelas: confira.')
       WHERE id = v_ids[1];
    END IF;

    v_payable_id := v_ids[1];
  END IF;

  UPDATE fiscal_notes
     SET status = 'confirmed',
         confirmed_at = now(),
         supplier_id = coalesce(p_supplier_id, supplier_id),
         purchase_order_id = coalesce(p_purchase_order_id, purchase_order_id),
         import_result = jsonb_build_object(
           'items', v_detail, 'products_created', v_created,
           'movements', v_moved, 'payable_id', v_payable_id,
           'payable_ids', to_jsonb(v_ids), 'parcelas', v_parcelas,
           'credito_sem_par', v_credito > 0 AND NOT v_credito_usado, 'at', now()
         ),
         updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true,
    'products_created', v_created,
    'movements_created', v_moved,
    'payable_id', v_payable_id,
    'payable_ids', to_jsonb(v_ids),
    'parcelas', v_parcelas,
    'credito_sem_par', v_credito > 0 AND NOT v_credito_usado,
    'items', v_detail
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb, p_purchase_order_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb, p_purchase_order_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb, p_purchase_order_id uuid) TO service_role;

-- ── public.conta_corrente_freelancer(p_favorecido_id uuid, p_de date, p_ate date, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.conta_corrente_freelancer(p_favorecido_id uuid, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_de date;
  v_ate date;
  v_anterior numeric;
  v_linhas jsonb;
  v_dias numeric;
  v_trab numeric;
  v_pago numeric;
  v_final numeric;
  v_dias_tudo numeric;
  v_pago_tudo numeric;
begin
  select id, name, conta_corrente_desde, saldo_anterior into v_fav
    from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  v_de := greatest(coalesce(p_de, v_fav.conta_corrente_desde, date '1900-01-01'),
                   coalesce(v_fav.conta_corrente_desde, date '1900-01-01'));
  v_ate := coalesce(p_ate, date '9999-12-31');
  if v_ate < v_de then raise exception 'Período invertido: % a %.', v_de, v_ate; end if;

  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= least(v_ate, public._hoje_brt())
   order by vigencia_inicio desc limit 1;

  select v_fav.saldo_anterior + coalesce(sum(l.trabalhado - l.pago), 0) into v_anterior
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data < v_de;

  with l as (
    select * from public._conta_corrente_linhas(p_favorecido_id) where data between v_de and v_ate
  ), o as (
    select l.*, v_anterior + sum(l.trabalhado - l.pago) over (
             order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id
             rows between unbounded preceding and current row) as saldo,
           row_number() over (order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id) as ordem
      from l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'data', o.data, 'tipo', o.tipo, 'id', o.id, 'jornada', o.jornada, 'fracao', o.fracao,
           'valor_diaria', o.valor_diaria, 'extras', o.extras, 'descontos', o.descontos,
           'trabalhado', o.trabalhado, 'pago', o.pago, 'descricao', o.descricao, 'conta', o.conta,
           'categoria', o.categoria, 'observacao', o.observacao, 'os', o.os, 'saldo', round(o.saldo, 2))
           order by o.ordem), '[]'::jsonb),
         coalesce(sum(o.fracao) filter (where o.tipo = 'dia'), 0),
         coalesce(sum(o.trabalhado), 0),
         coalesce(sum(o.pago), 0)
    into v_linhas, v_dias, v_trab, v_pago
    from o;

  v_final := v_anterior + v_trab - v_pago;

  select coalesce(sum(l.fracao) filter (where l.tipo = 'dia'), 0), coalesce(sum(l.pago), 0)
    into v_dias_tudo, v_pago_tudo
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data <= v_ate;

  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name,
                                     'desde', v_fav.conta_corrente_desde, 'saldo_inicial', v_fav.saldo_anterior,
                                     'diaria', v_perfil.valor_diaria),
    'de', case when v_de = date '1900-01-01' then null else v_de end,
    'ate', case when v_ate = date '9999-12-31' then null else v_ate end,
    'saldo_anterior', round(v_anterior, 2),
    'linhas', v_linhas,
    'dias', v_dias,
    'trabalhado', round(v_trab, 2),
    'pago', round(v_pago, 2),
    'saldo_final', round(v_final, 2),
    'estado', public._estado_do_saldo(v_final, v_dias_tudo, v_pago_tudo)
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.conta_corrente_freelancer(p_favorecido_id uuid, p_de date, p_ate date, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.conta_corrente_freelancer(p_favorecido_id uuid, p_de date, p_ate date, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.conta_corrente_freelancer(p_favorecido_id uuid, p_de date, p_ate date, p_autor uuid) TO service_role;

-- ── public.convert_external_quote_to_so(_quote_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.convert_external_quote_to_so(_quote_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  q public.external_quotes%ROWTYPE;
  l public.external_quote_leads%ROWTYPE;
  v_client_id uuid;
  v_vessel_id uuid;
  v_so_id uuid;
  v_so_number text;
BEGIN
  IF NOT is_admin_or_financial(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas Admin/Financeiro podem converter orçamentos.';
  END IF;

  SELECT * INTO q FROM public.external_quotes WHERE id = _quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
  IF q.status = 'converted' THEN RAISE EXCEPTION 'Orçamento já convertido (OS %).', q.converted_service_order_id; END IF;
  IF q.status NOT IN ('approved','submitted') THEN RAISE EXCEPTION 'Orçamento precisa estar aprovado.'; END IF;

  v_client_id := q.client_id;
  IF v_client_id IS NULL AND q.lead_id IS NOT NULL THEN
    SELECT * INTO l FROM public.external_quote_leads WHERE id = q.lead_id;
    IF l.promoted_client_id IS NOT NULL THEN
      v_client_id := l.promoted_client_id;
    ELSE
      INSERT INTO public.clients (
        type, full_name_or_company_name, cpf_cnpj, phone, whatsapp, email,
        address_line_1, address_line_2, city, state, postal_code, country, notes
      ) VALUES (
        l.type, l.full_name_or_company_name, l.cpf_cnpj, l.phone, l.whatsapp, l.email,
        l.address_line_1, l.address_line_2, l.city, l.state, l.postal_code, l.country,
        COALESCE(l.notes,'') || E'\n[Promovido de lead externo]'
      ) RETURNING id INTO v_client_id;

      UPDATE public.external_quote_leads
      SET promoted_client_id = v_client_id, promoted_at = now()
      WHERE id = l.id;
    END IF;
  END IF;

  IF v_client_id IS NULL THEN RAISE EXCEPTION 'Não foi possível resolver o cliente.'; END IF;

  v_vessel_id := q.vessel_id;
  IF v_vessel_id IS NULL AND q.lead_id IS NOT NULL AND l.boat_name IS NOT NULL THEN
    INSERT INTO public.vessels (
      client_id, boat_name, manufacturer, model, year, length_feet, current_marina_name_snapshot
    ) VALUES (
      v_client_id, l.boat_name, COALESCE(l.boat_manufacturer,''), COALESCE(l.boat_model,''),
      l.boat_year, COALESCE(l.boat_length_feet,0), l.marina_name
    ) RETURNING id INTO v_vessel_id;
  END IF;

  IF v_vessel_id IS NULL THEN RAISE EXCEPTION 'Embarcação obrigatória para criar OS.'; END IF;

  v_so_number := 'OS-' || to_char(now(),'YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);

  INSERT INTO public.service_orders (
    service_order_number, client_id, vessel_id, marina_id, status, priority,
    service_type, problem_description, initial_findings, customer_visible_report,
    internal_notes, hourly_rate, estimated_hours, labor_cost_total,
    travel_distance_km, travel_cost_per_km, travel_cost_total,
    parts_cost_total, subcontract_cost_total, discount_amount, tax_amount,
    grand_total, currency, quote_validity_days, quote_validity_date,
    payment_conditions, created_by
  ) VALUES (
    v_so_number, v_client_id, v_vessel_id, q.marina_id, 'approved', 'normal',
    q.service_type, q.problem_description, q.initial_findings, q.customer_visible_report,
    COALESCE(q.internal_notes,'') || E'\n[Convertido do orçamento externo ' || q.quote_number || ']',
    q.hourly_rate, q.estimated_hours, q.labor_cost_total,
    q.travel_distance_km, q.travel_cost_per_km, q.travel_cost_total,
    q.parts_cost_total, q.subcontract_cost_total, q.discount_amount, q.tax_amount,
    q.grand_total, q.currency, q.quote_validity_days, q.quote_validity_date,
    q.payment_conditions, auth.uid()
  ) RETURNING id INTO v_so_id;

  INSERT INTO public.service_order_parts (
    service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
    currency_snapshot, line_total_cost, line_total_sale, warranty_days, notes
  )
  SELECT v_so_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
         currency_snapshot, line_total_cost, line_total_sale, warranty_days, notes
  FROM public.external_quote_parts WHERE external_quote_id = q.id AND product_id IS NOT NULL;

  INSERT INTO public.service_order_services (
    service_order_id, service_id, service_name_snapshot, description_snapshot,
    billing_unit_snapshot, quantity, unit_price_snapshot, line_total, warranty_days, notes
  )
  SELECT v_so_id, service_id, service_name_snapshot, description_snapshot,
         billing_unit_snapshot, quantity, unit_price_snapshot, line_total, warranty_days, notes
  FROM public.external_quote_services WHERE external_quote_id = q.id;

  UPDATE public.external_quotes
  SET status = 'converted',
      converted_service_order_id = v_so_id,
      converted_at = now(),
      client_id = v_client_id,
      vessel_id = v_vessel_id,
      reviewed_by = COALESCE(reviewed_by, auth.uid()),
      reviewed_at = COALESCE(reviewed_at, now())
  WHERE id = q.id;

  INSERT INTO public.audit_log (table_name, record_id, action, new_value, reason, triggered_by_table, triggered_by_id, changed_by)
  VALUES ('service_orders', v_so_id, 'lead_converted',
          jsonb_build_object('service_order_number', v_so_number, 'external_quote_id', q.id, 'client_id', v_client_id, 'vessel_id', v_vessel_id),
          'Convertido do orçamento externo ' || q.quote_number,
          'external_quotes', q.id, COALESCE(auth.uid()::text,'system'));

  RETURN v_so_id;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.convert_external_quote_to_so(_quote_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.convert_external_quote_to_so(_quote_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.convert_external_quote_to_so(_quote_id uuid) TO service_role;

-- ── public.corrigir_lancamento(p_tipo text, p_id uuid, p_campos jsonb, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.corrigir_lancamento(p_tipo text, p_id uuid, p_campos jsonb, p_motivo text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_permitidos text[];
  v_chave text;
  v_valor_novo jsonb;
  v_novo jsonb := '{}'::jsonb;
  v_era jsonb := '{}'::jsonb;
  v_alterados text[] := array[]::text[];
  v_valor numeric;
  v_pago numeric;
  v_status text;
  v_data_antes date;
  v_data_nova date;
  v_categoria_antes text;
  v_categoria_nova text;
  v_tabela text;
  v_aplicar jsonb;
  v_sets text;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;
  if p_campos is null or jsonb_typeof(p_campos) <> 'object' then
    raise exception 'Informe o que corrigir.';
  end if;

  if p_tipo = 'payable' then
    v_permitidos := array['description', 'notes', 'expense_category', 'supplier_id', 'payee_id',
      'linked_service_order_id', 'cost_center_id', 'issue_date', 'due_date', 'amount'];
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    v_permitidos := array['description', 'notes', 'category', 'client_id', 'service_order_id',
      'cost_center_id', 'issue_date', 'due_date', 'amount'];
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;

  if v_antes is null then
    raise exception 'Lançamento não encontrado.';
  end if;
  if v_antes->>'status' = 'cancelled' then
    raise exception 'Este lançamento está cancelado. Se o cancelamento foi engano, lance de novo.';
  end if;

  -- Só entra o que muda de verdade. Texto vazio vale como "limpar".
  for v_chave in select jsonb_object_keys(p_campos) loop
    if not v_chave = any (v_permitidos) then
      raise exception 'O campo "%" não se corrige por aqui.', v_chave;
    end if;
    v_valor_novo := p_campos -> v_chave;
    if jsonb_typeof(v_valor_novo) = 'string' and btrim(v_valor_novo #>> '{}') = '' then
      v_valor_novo := 'null'::jsonb;
    end if;
    if coalesce(v_antes -> v_chave, 'null'::jsonb) is distinct from v_valor_novo then
      v_novo := v_novo || jsonb_build_object(v_chave, v_valor_novo);
      v_era := v_era || jsonb_build_object(v_chave, coalesce(v_antes -> v_chave, 'null'::jsonb));
      v_alterados := v_alterados || v_chave;
    end if;
  end loop;

  if array_length(v_alterados, 1) is null then
    return jsonb_build_object('ok', true, 'alterados', '[]'::jsonb, 'message', 'Nada mudou: os valores informados já eram os atuais.');
  end if;

  -- Pix dividido (pró-labore + retirada de sócio, 28/09/2026): as partes descrevem o MESMO
  -- pagamento; mudar quem recebeu, a data, a OS ou o centro numa parte só as desencontraria.
  if p_tipo = 'payable'
     and (v_antes ->> 'divisao_id' is not null
          or exists (select 1 from public.payables x where x.divisao_id = p_id and x.status <> 'cancelled'))
     and exists (select 1 from unnest(v_alterados) c where c not in ('notes', 'expense_category', 'description')) then
    raise exception 'Este pagamento está dividido em partes (pró-labore e retirada de sócio). Para mudar %, desfaça a aprovação e lance de novo: a rotina refaz a divisão no mesmo dia (06h20 e 15h20).',
      array_to_string(array(
        select case c when 'payee_id' then 'o favorecido' when 'supplier_id' then 'o fornecedor'
                      when 'linked_service_order_id' then 'a OS' when 'cost_center_id' then 'o centro de custo'
                      when 'issue_date' then 'a data' when 'due_date' then 'o vencimento' when 'amount' then 'o valor'
                      else c end
          from unnest(v_alterados) c where c not in ('notes', 'expense_category', 'description')), ', ')
      using errcode = 'check_violation';
  end if;
  -- Sócio com pró-labore pelo salário mínimo: a separação entre pró-labore e retirada é da regra
  -- (a rotina refaria a troca no dia seguinte). Outra categoria (gasto pessoal, por exemplo) pode.
  if p_tipo = 'payable' and v_novo ? 'expense_category'
     and v_antes ->> 'bank_transaction_id' is not null
     and public._socio_com_pro_labore_pelo_minimo((v_antes ->> 'payee_id')::uuid)
     and coalesce(v_antes ->> 'expense_category', '') in ('Pró-labore', 'Retirada de sócio')
     and coalesce(v_novo ->> 'expense_category', '') in ('Pró-labore', 'Retirada de sócio') then
    raise exception 'A separação entre pró-labore e retirada de sócio é automática: pró-labore é o salário mínimo do mês e o que passa dele é retirada. Para outra categoria (gasto pessoal, por exemplo), pode trocar.'
      using errcode = 'check_violation';
  end if;

  -- Campos que não podem ficar vazios.
  if v_novo ? 'description' and v_novo -> 'description' = 'null'::jsonb then
    raise exception 'A descrição não pode ficar vazia.';
  end if;
  if v_novo ? 'issue_date' and v_novo -> 'issue_date' = 'null'::jsonb then
    raise exception 'A data do lançamento não pode ficar vazia.';
  end if;
  if v_novo ? 'due_date' and v_novo -> 'due_date' = 'null'::jsonb then
    raise exception 'O vencimento não pode ficar vazio.';
  end if;
  if v_novo ? 'client_id' and v_novo -> 'client_id' = 'null'::jsonb then
    raise exception 'Conta a receber precisa de cliente.';
  end if;

  -- Referências: erro legível em vez de "violates foreign key constraint".
  if v_novo ->> 'supplier_id' is not null
     and not exists (select 1 from public.suppliers where id = (v_novo ->> 'supplier_id')::uuid) then
    raise exception 'Fornecedor não encontrado no cadastro.';
  end if;
  if v_novo ->> 'payee_id' is not null
     and not exists (select 1 from public.payees where id = (v_novo ->> 'payee_id')::uuid) then
    raise exception 'Favorecido não encontrado no cadastro.';
  end if;
  if v_novo ->> 'client_id' is not null
     and not exists (select 1 from public.clients where id = (v_novo ->> 'client_id')::uuid) then
    raise exception 'Cliente não encontrado no cadastro.';
  end if;
  if coalesce(v_novo ->> 'linked_service_order_id', v_novo ->> 'service_order_id') is not null
     and not exists (select 1 from public.service_orders
                      where id = coalesce(v_novo ->> 'linked_service_order_id', v_novo ->> 'service_order_id')::uuid) then
    raise exception 'OS não encontrada.';
  end if;
  if v_novo ->> 'cost_center_id' is not null
     and not exists (select 1 from public.cost_centers where id = (v_novo ->> 'cost_center_id')::uuid) then
    raise exception 'Centro de custo não encontrado.';
  end if;

  -- Categoria sensível: a mesma regra da RLS — só o administrador vê e mexe.
  if p_tipo = 'payable' and v_autor is not null and not public.is_admin(v_autor) then
    v_categoria_antes := v_antes ->> 'expense_category';
    v_categoria_nova := coalesce(v_novo ->> 'expense_category', v_categoria_antes);
    if (v_categoria_antes is not null and public.categoria_e_sensivel(v_categoria_antes))
       or (v_categoria_nova is not null and public.categoria_e_sensivel(v_categoria_nova)) then
      raise exception 'Categoria restrita: só o administrador altera este lançamento.' using errcode = '42501';
    end if;
  end if;

  -- Mês fechado. Anotação pura (só observação) passa: não muda número nenhum.
  if v_alterados <> array['notes'] then
    v_data_antes := (v_antes ->> 'issue_date')::date;
    v_data_nova := coalesce((v_novo ->> 'issue_date')::date, v_data_antes);
    perform public._recusa_se_mes_fechado(v_data_antes, 'corrigir este lançamento');
    perform public._recusa_se_mes_fechado(v_data_nova, 'mover o lançamento para esta data');
  end if;

  -- Valor.
  v_valor := (v_antes ->> 'amount')::numeric;
  v_pago := coalesce((v_antes ->> 'paid_amount')::numeric, 0);
  v_status := v_antes ->> 'status';
  if v_novo ? 'amount' then
    if v_antes ->> 'bank_transaction_id' is not null then
      raise exception 'O valor deste lançamento veio do extrato do banco (%) e não muda à mão. Se o lançamento está errado, desfaça a aprovação.',
        public._brl((v_antes ->> 'amount')::numeric);
    end if;
    if v_novo -> 'amount' = 'null'::jsonb or (v_novo ->> 'amount')::numeric <= 0 then
      raise exception 'O valor precisa ser maior que zero.';
    end if;
    v_valor := round((v_novo ->> 'amount')::numeric, 2);
    if v_valor < v_pago - 0.005 then
      raise exception 'O novo valor (%) é menor que o já pago (%). Estorne o pagamento antes.',
        public._brl(v_valor), public._brl(v_pago);
    end if;
    v_status := public._situacao_do_saldo(v_valor, v_pago, v_status);
  end if;

  -- Grava SÓ as colunas que mudaram. Um UPDATE que regrava tudo dispara os gatilhos de
  -- coerência de colunas que ninguém tocou — e um recebível antigo com data torta ficaria
  -- impossível de corrigir até na descrição.
  v_aplicar := v_novo;
  if v_novo ? 'amount' then
    v_aplicar := v_aplicar || jsonb_build_object(
      'amount', v_valor, 'balance_amount', greatest(0, v_valor - v_pago), 'status', v_status);
  end if;
  v_tabela := case when p_tipo = 'payable' then 'payables' else 'receivables' end;
  select string_agg(format('%I = (x.r).%I', k, k), ', ') into v_sets
    from jsonb_object_keys(v_aplicar) as k;
  execute format(
    'update public.%I t set %s from (select jsonb_populate_record(null::public.%I, $1) as r) x where t.id = $2',
    v_tabela, v_sets, v_tabela)
  using v_aplicar, p_id;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'corrigiu_lancamento', v_autor,
    (v_antes ->> 'bank_transaction_id')::uuid,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    v_valor,
    left(coalesce(nullif(btrim(p_motivo), ''), 'Corrigiu ' || array_to_string(v_alterados, ', ')) || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    v_era,
    v_novo
  );

  return jsonb_build_object(
    'ok', true,
    'alterados', to_jsonb(v_alterados),
    'antes', v_era,
    'depois', v_novo,
    'message', 'Lançamento corrigido: ' || array_to_string(v_alterados, ', ')
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.corrigir_lancamento(p_tipo text, p_id uuid, p_campos jsonb, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.corrigir_lancamento(p_tipo text, p_id uuid, p_campos jsonb, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.corrigir_lancamento(p_tipo text, p_id uuid, p_campos jsonb, p_motivo text, p_autor uuid) TO service_role;

-- ── public.count_purchase_shortages(p_so_ids uuid[]) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.count_purchase_shortages(p_so_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_object_agg(
           t.so_id,
           (public.get_os_purchase_needs(t.so_id)->>'shortageCount')::int
         ), '{}'::jsonb)
  from (select distinct unnest(coalesce(p_so_ids, '{}'::uuid[])) as so_id) t
  where (public.get_os_purchase_needs(t.so_id)->>'shortageCount')::int > 0;
$function$
;
COMMENT ON FUNCTION public.count_purchase_shortages(p_so_ids uuid[]) IS 'Quantos itens faltam comprar, por OS, em lote. Fonte unica da regra: o motor R16 consome em vez de reimplementar a formula em Deno.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.count_purchase_shortages(p_so_ids uuid[]) TO postgres;
GRANT EXECUTE ON FUNCTION public.count_purchase_shortages(p_so_ids uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_purchase_shortages(p_so_ids uuid[]) TO service_role;

-- ── public.create_followup_mission(p_origem_tipo text, p_origem_id uuid, p_objetivo text, p_prazo_final timestamp with time zone, p_contraparte_tipo text, p_contraparte_id uuid, p_phone text, p_label text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.create_followup_mission(p_origem_tipo text, p_origem_id uuid, p_objetivo text, p_prazo_final timestamp with time zone DEFAULT NULL::timestamp with time zone, p_contraparte_tipo text DEFAULT NULL::text, p_contraparte_id uuid DEFAULT NULL::uuid, p_phone text DEFAULT NULL::text, p_label text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_tipo text := p_contraparte_tipo;
  v_id uuid := p_contraparte_id;
  v_cli uuid; v_so uuid; v_loop uuid;
  v_tipo_loop text; v_id_loop uuid;
  v_criterio text := 'manual';
  v_raw_db text; v_label_db text; v_optout boolean := false;
  v_raw text; v_phone text; v_label text;
  v_max integer; v_prox timestamptz; v_missao uuid;
begin
  if public.is_external_seller(auth.uid()) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if coalesce(trim(p_objetivo), '') = '' then
    raise exception 'Diga o que a IA deve acompanhar (objetivo da missão).';
  end if;

  -- A origem diz como o ERP prova que resolveu, e sugere a contraparte quando o chamador
  -- não a informou.
  if p_origem_tipo = 'quote' then
    select so.id, so.client_id into v_so, v_cli from public.service_orders so where so.id = p_origem_id;
    if v_so is null then raise exception 'Orçamento não encontrado.'; end if;
    v_criterio := 'quote_decided';
    if v_tipo is null then v_tipo := 'client'; v_id := v_cli; end if;
  elsif p_origem_tipo = 'agenda_task' then
    select t.client_id,
           case when t.related_entity_type = 'service_order' then t.related_entity_id end
      into v_cli, v_so
    from public.agenda_tasks t where t.id = p_origem_id;
    if not found then raise exception 'Tarefa não encontrada.'; end if;
    v_criterio := 'task_done';
    if v_tipo is null and v_cli is not null then v_tipo := 'client'; v_id := v_cli; end if;
  elsif p_origem_tipo = 'open_loop' then
    select l.entity_type, l.entity_id, l.service_order_id into v_tipo_loop, v_id_loop, v_so
    from public.entity_open_loops l where l.id = p_origem_id;
    if not found then raise exception 'Fio solto não encontrado.'; end if;
    v_loop := p_origem_id;
    v_criterio := 'open_loop_resolved';
    if v_tipo is null then v_tipo := v_tipo_loop; v_id := v_id_loop; end if;
  elsif p_origem_tipo = 'manual' then
    null;
  else
    raise exception 'Origem inválida: %', p_origem_tipo;
  end if;

  if v_tipo = 'client' and v_id is not null then
    select coalesce(nullif(c.whatsapp, ''), c.phone), coalesce(nullif(c.display_name, ''), c.name), coalesce(c.opt_out_whatsapp, false)
      into v_raw_db, v_label_db, v_optout
    from public.clients c where c.id = v_id;
  elsif v_tipo = 'supplier' and v_id is not null then
    select s.phone, coalesce(nullif(s.display_name, ''), nullif(s.trade_name, ''), s.name), coalesce(s.opt_out_whatsapp, false)
      into v_raw_db, v_label_db, v_optout
    from public.suppliers s where s.id = v_id;
  end if;
  if v_tipo is null then v_tipo := 'lead'; end if;

  v_raw := coalesce(nullif(trim(p_phone), ''), v_raw_db);
  v_label := coalesce(nullif(trim(p_label), ''), v_label_db, v_raw);
  if v_optout then
    raise exception 'Este contato pediu para não receber mensagens (opt-out) — a IA não vai cobrá-lo.';
  end if;
  v_phone := public.wa_normalize_phone(v_raw);
  if coalesce(v_phone, '') = '' then
    raise exception 'Contato sem telefone válido para WhatsApp.';
  end if;

  -- Decisão do dono (30/08): fornecedor atrasado é rotina (3 toques); cliente cobrado demais
  -- é venda perdida (2).
  v_max := case when v_tipo = 'supplier' then 3 else 2 end;
  -- Cadência contada para trás do prazo (D-7); sem prazo, começa agora — quem está parado
  -- já está atrasado.
  v_prox := case when p_prazo_final is null then now()
                 else greatest(now(), p_prazo_final - interval '7 days') end;

  begin
    insert into public.ai_followup_missions
      (objetivo, contraparte_tipo, contraparte_id, contraparte_phone, contraparte_label,
       origem_tipo, origem_id, service_order_id, open_loop_id, criterio_erp, prazo_final,
       max_toques, proximo_toque_em, criada_por)
    values
      (trim(p_objetivo), v_tipo, v_id, v_phone, v_label,
       p_origem_tipo, p_origem_id, v_so, v_loop, v_criterio, p_prazo_final,
       v_max, v_prox, auth.uid())
    returning id into v_missao;
  exception when unique_violation then
    raise exception 'Já existe uma missão ativa para este contato — a IA acompanha um assunto de cada vez com cada pessoa.';
  end;

  insert into public.ai_followup_events (mission_id, tipo, conteudo, created_by)
  values (v_missao, 'created', trim(p_objetivo), auth.uid());

  return v_missao;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.create_followup_mission(p_origem_tipo text, p_origem_id uuid, p_objetivo text, p_prazo_final timestamp with time zone, p_contraparte_tipo text, p_contraparte_id uuid, p_phone text, p_label text) TO postgres;
GRANT EXECUTE ON FUNCTION public.create_followup_mission(p_origem_tipo text, p_origem_id uuid, p_objetivo text, p_prazo_final timestamp with time zone, p_contraparte_tipo text, p_contraparte_id uuid, p_phone text, p_label text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_followup_mission(p_origem_tipo text, p_origem_id uuid, p_objetivo text, p_prazo_final timestamp with time zone, p_contraparte_tipo text, p_contraparte_id uuid, p_phone text, p_label text) TO service_role;

-- ── public.create_service_cases_on_complete() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.create_service_cases_on_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_criados integer;
begin
  if new.status not in ('completed','invoiced') then return new; end if;
  if old.status in ('completed','invoiced') then return new; end if;

  insert into public.service_cases (
    service_order_id, service_id, vessel_id, client_id, marina_id, asset_type,
    features, planned_minutes, actual_minutes, materials_cost, parts_used,
    variance_pct, outcome, usable, unusable_reason)
  select
    new.id,
    sos.service_id,
    new.vessel_id,
    new.client_id,
    new.marina_id,
    v.asset_type,
    -- O que descreve a execução para a busca por semelhança depois.
    jsonb_build_object(
      'servico',  sos.name_snapshot,
      'sistema',  coalesce(sos.service_system, s.service_system),
      'verbo',    s.service_verb,
      'passos',   (select count(*) from public.service_order_steps st
                    where st.service_order_service_id = sos.id),
      'travas',   (select count(*) from public.service_order_steps st
                    where st.service_order_service_id = sos.id and st.blocked_reason_code is not null),
      'nao_se_aplica', (select count(*) from public.service_order_steps st
                    where st.service_order_service_id = sos.id and st.status = 'not_applicable')),
    nullif((select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
             where st.service_order_service_id = sos.id), 0),
    nullif(coalesce(sos.elapsed_minutes, 0), 0),
    (select coalesce(sum(p.line_total_cost), 0) from public.service_order_parts p
      where p.service_order_service_id = sos.id),
    (select coalesce(jsonb_agg(jsonb_build_object(
              'produto', pr.name, 'qtd', p.quantity)), '[]'::jsonb)
       from public.service_order_parts p
       join public.products pr on pr.id = p.product_id
      where p.service_order_service_id = sos.id),
    case when coalesce(sos.elapsed_minutes,0) > 0
          and (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                where st.service_order_service_id = sos.id) > 0
         then round(100.0 * (sos.elapsed_minutes -
              (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                where st.service_order_service_id = sos.id))
              / (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                  where st.service_order_service_id = sos.id), 1)
         else null end,
    -- Faixa de tolerância: convenção de negócio, ajustável. Fora de ±10% do
    -- previsto, o caso é sinal de que a estimativa precisa mudar.
    case when coalesce(sos.elapsed_minutes,0) = 0 then null
         when (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                where st.service_order_service_id = sos.id) = 0 then null
         when sos.elapsed_minutes >
              1.1 * (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                      where st.service_order_service_id = sos.id) then 'estourou'
         when sos.elapsed_minutes <
              0.9 * (select sum(coalesce(st.standard_minutes,0)) from public.service_order_steps st
                      where st.service_order_service_id = sos.id) then 'sobrou'
         else 'dentro' end,
    -- Sem tempo real não há o que aprender com este caso.
    coalesce(sos.elapsed_minutes, 0) > 0,
    case when coalesce(sos.elapsed_minutes, 0) > 0 then null
         else 'Concluída sem hora apontada — não serve para estimar tempo.' end
  from public.service_order_services sos
  join public.services s on s.id = sos.service_id
  left join public.vessels v on v.id = new.vessel_id
  where sos.service_order_id = new.id
    and sos.service_id is not null
    -- Reabrir e concluir de novo não duplica o caso.
    and not exists (select 1 from public.service_cases c
                    where c.service_order_id = new.id and c.service_id = sos.service_id);

  get diagnostics v_criados = row_count;
  if v_criados > 0 then
    raise notice 'OS %: % caso(s) registrado(s).', new.service_order_number, v_criados;
  end if;

  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.create_service_cases_on_complete() TO postgres;
GRANT EXECUTE ON FUNCTION public.create_service_cases_on_complete() TO service_role;

-- ── public.dc_cable_min_mm2_by_drop(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.dc_cable_min_mm2_by_drop(p_amps numeric, p_one_way_meters numeric, p_volts numeric DEFAULT 12, p_max_drop_pct numeric DEFAULT 3)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_amps is null or p_one_way_meters is null
      or p_amps <= 0 or p_one_way_meters <= 0
      or coalesce(p_volts,0) <= 0 or coalesce(p_max_drop_pct,0) <= 0
    then null
    else round(
      (10.75 * p_amps * (p_one_way_meters * 2 * 3.28084))
      / (p_volts * (p_max_drop_pct / 100.0))
      / 1973.53, 2)
  end;
$function$
;
COMMENT ON FUNCTION public.dc_cable_min_mm2_by_drop(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric) IS 'Seção mínima em mm² para respeitar a queda de tensão (fórmula de circular
   mils, cobre, K=10.75). O comprimento é de UMA VIA: a função dobra, porque a
   corrente percorre ida e volta. NÃO considera ampacidade — o cabo final é o
   MAIOR entre este resultado e o da tabela de ampacidade.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.dc_cable_min_mm2_by_drop(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.dc_cable_min_mm2_by_drop(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dc_cable_min_mm2_by_drop(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric) TO service_role;

-- ── public.dc_cable_product_for(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_engine_space boolean, p_bundle_size integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.dc_cable_product_for(p_amps numeric, p_one_way_meters numeric, p_volts numeric DEFAULT 12, p_max_drop_pct numeric DEFAULT 3, p_engine_space boolean DEFAULT false, p_bundle_size integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_drop numeric; v_n integer := coalesce(p_bundle_size, 1);
  v_prod record; v_candidatos integer;
begin
  v_drop := public.dc_cable_min_mm2_by_drop(p_amps, p_one_way_meters, p_volts, p_max_drop_pct);

  if v_drop is null then
    return jsonb_build_object('produto', null, 'pronto', false,
      'motivo', 'Faltam corrente ou comprimento para dimensionar.');
  end if;

  select count(*) into v_candidatos from public.products p
  where p.active and p.conductor_mm2 is not null and p.conductor_insulation_c is not null;

  if v_candidatos = 0 then
    return jsonb_build_object('produto', null, 'pronto', false,
      'motivo', 'Nenhum cabo do catálogo tem seção E isolação declaradas. '
             || 'Sem a isolação não dá para saber quanta corrente o cabo admite.');
  end if;

  select p.id, p.name, p.conductor_mm2, p.conductor_insulation_c, p.sale_price, p.unit
    into v_prod
  from public.products p
  join public.dc_ampacity_ratings r
    on r.mm2 = p.conductor_mm2 and r.insulation_c = p.conductor_insulation_c
  where p.active
    and p.conductor_mm2 is not null
    and p.conductor_insulation_c is not null
    and p.conductor_mm2 >= v_drop
    and case
          when v_n > 1 and p_engine_space then r.amps_bundled_engine
          when v_n > 1                    then r.amps_bundled
          when p_engine_space             then r.amps_free_air_engine
          else r.amps_free_air
        end >= p_amps
  order by p.conductor_mm2, coalesce(p.sale_price, 1e9)
  limit 1;

  if v_prod.id is null then
    return jsonb_build_object('produto', null, 'pronto', false,
      'motivo', 'Nenhum cabo do catálogo atende ' || p_amps || ' A com '
             || v_drop || ' mm² de mínimo por queda de tensão, nesta condição de '
             || 'instalação. Cadastre a seção maior ou divida o circuito.');
  end if;

  return jsonb_build_object(
    'produto', jsonb_build_object(
      'id', v_prod.id, 'nome', v_prod.name, 'mm2', v_prod.conductor_mm2,
      'isolacao_c', v_prod.conductor_insulation_c,
      'preco_por_metro', v_prod.sale_price, 'unidade', v_prod.unit),
    -- Acima de três condutores a folha da norma não cobre; o cabo escolhido é
    -- piso, não resposta. Mesmo critério do dc_cable_sizing.
    'pronto', v_n <= 3,
    'mm2_por_queda_de_tensao', v_drop,
    'motivo', case when v_n > 3 then
      'São ' || v_n || ' condutores no feixe e a norma cobre até três: este cabo '
      || 'é o piso, e falta a correção adicional.' end);
end;
$function$
;
COMMENT ON FUNCTION public.dc_cable_product_for(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_engine_space boolean, p_bundle_size integer) IS 'O cabo do catálogo que atende este circuito pelos dois critérios da ABYC,
   lendo a ampacidade na isolação DECLARADA de cada cabo. Devolve produto nulo
   com motivo quando nenhum serve — nunca o mais próximo.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.dc_cable_product_for(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_engine_space boolean, p_bundle_size integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.dc_cable_product_for(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_engine_space boolean, p_bundle_size integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dc_cable_product_for(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_engine_space boolean, p_bundle_size integer) TO service_role;

-- ── public.dc_cable_sizing(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_insulation_c integer, p_engine_space boolean, p_bundle_size integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.dc_cable_sizing(p_amps numeric, p_one_way_meters numeric, p_volts numeric DEFAULT 12, p_max_drop_pct numeric DEFAULT 3, p_insulation_c integer DEFAULT 90, p_engine_space boolean DEFAULT false, p_bundle_size integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_drop numeric; v_amp numeric; v_tem_tabela boolean;
  v_faltando text[] := '{}'; v_n integer := coalesce(p_bundle_size, 1);
  v_coluna text; v_acima_de_tres boolean; v_pronto boolean;
begin
  v_drop := public.dc_cable_min_mm2_by_drop(p_amps, p_one_way_meters, p_volts, p_max_drop_pct);

  if p_amps is null or p_amps <= 0 then
    -- O ::text é o conserto. Sem ele, esta linha derruba a função inteira.
    v_faltando := v_faltando || 'corrente máxima do circuito (A)'::text;
  end if;
  if p_one_way_meters is null or p_one_way_meters <= 0 then
    v_faltando := v_faltando || 'comprimento do trecho (m)'::text;
  end if;

  select exists (select 1 from public.dc_ampacity_ratings where insulation_c = p_insulation_c)
    into v_tem_tabela;

  v_acima_de_tres := v_n > 3;
  v_coluna := case
    when v_n > 1 and p_engine_space then 'feixe, casa de máquinas'
    when v_n > 1                    then 'feixe'
    when p_engine_space             then 'ao ar livre, casa de máquinas'
    else 'ao ar livre' end;

  if v_tem_tabela and p_amps is not null and p_amps > 0 then
    select min(r.mm2) into v_amp
    from public.dc_ampacity_ratings r
    where r.insulation_c = p_insulation_c
      and case
            when v_n > 1 and p_engine_space then r.amps_bundled_engine
            when v_n > 1                    then r.amps_bundled
            when p_engine_space             then r.amps_free_air_engine
            else r.amps_free_air
          end >= p_amps;
  end if;

  v_pronto := v_drop is not null and v_amp is not null and not v_acima_de_tres;

  return jsonb_build_object(
    'pronto', v_pronto,
    'mm2_por_queda_de_tensao', v_drop,
    'mm2_por_ampacidade', v_amp,
    -- Só existe quando os DOIS critérios existem. Sem isso não há mínimo: há
    -- metade de uma conta, e ela não vira número.
    'mm2_minimo', case when v_drop is not null and v_amp is not null
                       then greatest(v_drop, v_amp) end,
    'criterio_que_manda', case
      when v_drop is null or v_amp is null then null
      when v_drop >= v_amp then 'queda de tensão'
      else 'ampacidade' end,
    'faltando', to_jsonb(v_faltando),
    'ampacidade_cadastrada', v_tem_tabela,
    'coluna_da_norma', v_coluna,
    'aviso', case
      when not v_tem_tabela then
        'Não há ampacidade cadastrada para isolação de ' || p_insulation_c ||
        ' °C. Só a queda de tensão foi calculada, e a ABYC exige os dois critérios.'
      when array_length(v_faltando, 1) > 0 then
        'Faltam dados para dimensionar: ' || array_to_string(v_faltando, ', ') || '.'
      when v_acima_de_tres then
        'São ' || v_n || ' condutores no mesmo feixe. As Tabelas VI-A e VI-B cobrem '
        'até TRÊS; acima disso a norma exige correção adicional que não está '
        'cadastrada aqui. O valor abaixo usou a coluna de feixe SEM essa correção '
        '— trate como piso, não como resposta.'
      when v_amp is null then
        'Nenhuma bitola cadastrada atende ' || p_amps || ' A na condição "' ||
        v_coluna || '" a ' || p_insulation_c || ' °C. Reveja a corrente, a '
        'condição de instalação, ou divida o circuito.'
      else null end,
    'premissas', jsonb_build_object(
      'tensao_v', p_volts, 'queda_max_pct', p_max_drop_pct,
      'isolacao_c', p_insulation_c, 'casa_de_maquinas', p_engine_space,
      'condutores_no_feixe', v_n,
      'tabela_da_norma', case when v_n > 1 then 'VI-B' else 'VI-A' end,
      'comprimento_considerado', 'ida e volta (o dobro do trecho informado)')
  );
end;
$function$
;
COMMENT ON FUNCTION public.dc_cable_sizing(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_insulation_c integer, p_engine_space boolean, p_bundle_size integer) IS 'Bitola minima de cabo CC pelos DOIS criterios da ABYC E-11 (queda de tensao e ampacidade). Quando falta corrente ou comprimento, devolve o que falta em "faltando" -- antes de 31/08/2026 esse caminho levantava "malformed array literal" porque text[] || literal resolvia como array_cat; o cast ::text corrige.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.dc_cable_sizing(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_insulation_c integer, p_engine_space boolean, p_bundle_size integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.dc_cable_sizing(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_insulation_c integer, p_engine_space boolean, p_bundle_size integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dc_cable_sizing(p_amps numeric, p_one_way_meters numeric, p_volts numeric, p_max_drop_pct numeric, p_insulation_c integer, p_engine_space boolean, p_bundle_size integer) TO service_role;

-- ── public.deduct_stock_on_os_complete() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.deduct_stock_on_os_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    INSERT INTO inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id, notes, unit_cost_snapshot)
    SELECT sop.product_id, 'service_order_usage', -sop.quantity, 'service_order', NEW.id,
           'Baixa automática ao concluir OS ' || NEW.service_order_number, sop.unit_cost_snapshot
    FROM service_order_parts sop WHERE sop.service_order_id = NEW.id AND sop.product_id IS NOT NULL;
  END IF;
  RETURN NEW;
END; $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.deduct_stock_on_os_complete() TO postgres;
GRANT EXECUTE ON FUNCTION public.deduct_stock_on_os_complete() TO authenticated;
GRANT EXECUTE ON FUNCTION public.deduct_stock_on_os_complete() TO service_role;

-- ── public.desfazer_aplicacao(p_pagamento uuid, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.desfazer_aplicacao(p_pagamento uuid, p_motivo text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  p public.payments%rowtype;
  r public.receivables%rowtype;
  t public.bank_transactions%rowtype;
  v_aplic jsonb;
  v_ligado boolean;
  v_valor_original numeric;
  v_novo_pago numeric;
  v_continua boolean;
  v_msg text;
  v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
begin
  select * into p from public.payments where id = p_pagamento for update;
  if not found or p.receivable_id is null then raise exception 'Pagamento de conta a receber não encontrado.'; end if;
  if p.status <> 'confirmed' then raise exception 'Este pagamento já foi estornado.'; end if;
  if p.bank_transaction_id is null then
    raise exception 'Este pagamento não veio de uma entrada do banco. Para estorná-lo, use o histórico de pagamentos da conta.';
  end if;
  select * into r from public.receivables where id = p.receivable_id for update;
  select * into t from public.bank_transactions where id = p.bank_transaction_id for update;
  perform public._recusa_se_mes_fechado(p.payment_date, 'desfazer esta aplicação');

  select a into v_aplic
    from public.reconciliation_log l, jsonb_array_elements(l.depois -> 'aplicacoes') a
   where l.acao = 'aplicou_pix' and l.bank_transaction_id = t.id and (a ->> 'pagamento')::uuid = p.id
   order by l.ocorrido_em desc limit 1;
  -- Sem registro da aplicação (pagamento ligado à entrada por outro caminho), vale a observação:
  -- o que a conciliação criou começa com "Concilia…"; o resto foi lançado à mão.
  v_ligado := case when v_aplic is not null then coalesce((v_aplic ->> 'ligado')::boolean, false)
                   else coalesce(p.notes, '') not ilike 'concilia%' end;

  if v_ligado then
    -- Era um pagamento lançado à mão: continua valendo, só deixa de vir desta entrada.
    update public.payments set bank_transaction_id = null where id = p.id;
    update public.receivables
       set bank_transaction_id = case when bank_transaction_id = t.id then null else bank_transaction_id end,
           notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] O pagamento de ' || public._brl(p.amount)
                   || ' deixou de vir da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                   || coalesce(': ' || nullif(btrim(p_motivo), ''), '') || '.')
     where id = r.id;
    v_valor_original := r.amount;
    v_novo_pago := r.paid_amount;
  else
    -- Pagamento criado pela aplicação: estorna, e o acréscimo ou o desconto dela voltam.
    v_valor_original := case when v_aplic is not null
                               and (coalesce((v_aplic ->> 'acrescimo')::numeric, 0) > 0 or coalesce((v_aplic ->> 'desconto')::numeric, 0) > 0)
                             then r.amount - coalesce((v_aplic ->> 'acrescimo')::numeric, 0) + coalesce((v_aplic ->> 'desconto')::numeric, 0)
                             else r.amount end;
    update public.payments
       set status = 'cancelled', cancelled_at = now(),
           cancellation_reason = left('Aplicação desfeita' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
     where id = p.id;
    v_novo_pago := greatest(0, round(coalesce(r.paid_amount, 0) - p.amount, 2));
    update public.receivables
       set amount = v_valor_original,
           paid_amount = v_novo_pago,
           balance_amount = greatest(0, round(v_valor_original - v_novo_pago, 2)),
           status = public._situacao_do_saldo(v_valor_original, v_novo_pago, status),
           bank_transaction_id = case
             when bank_transaction_id = t.id and not exists (
                    select 1 from public.payments x
                     where x.receivable_id = r.id and x.bank_transaction_id = t.id and x.status = 'confirmed')
             then null else bank_transaction_id end,
           notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] Aplicação de ' || public._brl(p.amount)
                   || ' da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY') || ' desfeita'
                   || coalesce(': ' || nullif(btrim(p_motivo), ''), '') || '.')
     where id = r.id;
  end if;

  v_continua := public._reacomodar_entrada(t.id);
  if not v_continua then
    update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = t.id;
  end if;

  v_msg := case when v_ligado
                then 'O pagamento de ' || public._brl(p.amount) || ' de "' || r.description
                     || '" continua valendo, mas deixou de vir da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                else 'Aplicação desfeita: ' || public._brl(p.amount) || ' da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                     || ' voltaram a faltar em "' || r.description || '"' end
           || case when v_continua then '; o resto da entrada continua aplicado nas outras contas.'
                   else '; a entrada voltou para a fila do Extrato.' end;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, antes, depois)
  values ('desfez_aplicacao', v_autor, t.id, r.id, p.amount,
          left(coalesce(nullif(btrim(p_motivo), '') || ' · ', '') || v_msg, 300),
          jsonb_build_object('pagamento', p.id, 'ligado', v_ligado, 'amount', r.amount, 'paid_amount', r.paid_amount, 'status', r.status),
          jsonb_build_object('amount', v_valor_original, 'paid_amount', v_novo_pago));

  return jsonb_build_object('ok', true, 'entrada_livre', not v_continua, 'message', v_msg);
end;
$function$
;
COMMENT ON FUNCTION public.desfazer_aplicacao(p_pagamento uuid, p_motivo text, p_autor uuid) IS 'Desfaz uma aplicação de entrada do banco: estorna o pagamento criado por ela (devolvendo saldo, acréscimo e desconto) ou, se era pagamento já lançado, só o desliga; solta a entrada quando nada mais dela fica aplicado.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.desfazer_aplicacao(p_pagamento uuid, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.desfazer_aplicacao(p_pagamento uuid, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.desfazer_aplicacao(p_pagamento uuid, p_motivo text, p_autor uuid) TO service_role;

-- ── public.desfazer_aprovacao(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.desfazer_aprovacao(p_tipo text, p_id uuid, p_motivo text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx uuid;
  v_nasceu boolean;
  v_pagamento_id uuid;
  v_pagamento_valor numeric;
  v_pago numeric;
  v_voltaram int := 0;
  v_acao text;
  v_nota text;
  v_msg text;
  v_grupo jsonb;
  v_continua boolean := false;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;

  if p_tipo = 'payable' then
    -- Pix dividido (pró-labore + retirada de sócio): as partes voltam a ser um lançamento só e o
    -- resto segue como sempre, sobre o principal (28/09/2026).
    v_grupo := public._divisao_de(p_id);
    p_id := public._juntar_divisao(p_id, 'desfazer a aprovação', v_autor);
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Este lançamento já está cancelado.'; end if;

  v_tx := (v_antes ->> 'bank_transaction_id')::uuid;
  if v_tx is null then
    raise exception 'Este lançamento não está ligado a nenhuma linha do extrato, então não há aprovação a desfazer. Para tirá-lo do resultado, cancele-o.';
  end if;
  perform public._recusa_se_mes_fechado((v_antes ->> 'issue_date')::date, 'desfazer esta aprovação');

  v_nasceu := public._nasceu_do_extrato(p_tipo, p_id);
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] ';

  if v_nasceu then
    -- A receita que nasceu da entrada é a entrada inteira; se a entrada também paga outra conta,
    -- desfazer aqui devolveria à fila um dinheiro que continua aplicado (02/10/2026).
    if p_tipo = 'receivable' and exists (
         select 1 from public.payments x
          where x.bank_transaction_id = v_tx and x.status = 'confirmed' and x.receivable_id <> p_id) then
      raise exception 'Esta entrada do extrato também paga outra(s) conta(s). Desfaça aquelas aplicações antes de desfazer esta aprovação.';
    end if;
    v_acao := 'desfez_aprovacao';
    v_nota := v_nota || 'Aprovação desfeita' || coalesce(': ' || nullif(btrim(p_motivo), ''), '') || '.';

    update public.payments
       set status = 'cancelled', cancelled_at = now(), cancellation_reason = left('Aprovação desfeita' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
     where status = 'confirmed'
       and ((p_tipo = 'payable' and payable_id = p_id) or (p_tipo = 'receivable' and receivable_id = p_id));

    if p_tipo = 'payable' then
      update public.payables set status = 'cancelled', bank_transaction_id = null,
             notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
      update public.finance_review_queue
         set status = 'pending', decided_by = null, decided_at = null, created_payable_id = null,
             decision_note = v_nota
       where created_payable_id = p_id;
    else
      update public.receivables set status = 'cancelled', bank_transaction_id = null,
             notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
      update public.finance_review_queue
         set status = 'pending', decided_by = null, decided_at = null, created_receivable_id = null,
             decision_note = v_nota
       where created_receivable_id = p_id;
    end if;
    get diagnostics v_voltaram = row_count;

    update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
    v_msg := 'Aprovação desfeita: o lançamento foi cancelado e a linha do extrato voltou para a fila.';
  else
    v_acao := 'desconciliou';
    v_pago := coalesce((v_antes ->> 'paid_amount')::numeric, 0);

    if p_tipo = 'payable' then
      -- O pagamento que o CASAMENTO registrou sai junto. Pagamento lançado à mão e só depois
      -- ligado ao extrato continua valendo — medido em 25/09/2026: das 49 linhas do extrato
      -- com pagamento ligado, parte foi criada pela conciliação ("Conciliação automática…",
      -- "Conciliado com o extrato…") e parte pelo dono, semanas antes do casamento. Estornar
      -- o segundo tipo desfaria um recebimento que aconteceu.
      select p.id, p.amount into v_pagamento_id, v_pagamento_valor
        from public.bank_transactions t join public.payments p on p.id = t.reconciled_payment_id
       where t.id = v_tx and p.status = 'confirmed'
         and coalesce(p.notes, '') ilike 'concilia%'
         and p.payable_id = p_id;
      if v_pagamento_id is not null then
        update public.payments
           set status = 'cancelled', cancelled_at = now(),
               cancellation_reason = left('Vínculo com o extrato desfeito' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
         where id = v_pagamento_id;
        v_pago := greatest(0, v_pago - v_pagamento_valor);
      end if;
      update public.payables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
      update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
    else
      -- Conta a receber: os pagamentos dela que vieram desta entrada pelo casamento ("Concilia…")
      -- são estornados; os lançados à mão continuam valendo e só deixam de vir dela. A entrada
      -- só volta para a fila se não pagar mais nenhuma conta (um Pix para várias contas, F2).
      select (array_agg(p.id order by p.created_at))[1], coalesce(sum(p.amount), 0)
        into v_pagamento_id, v_pagamento_valor
        from public.payments p
       where p.receivable_id = p_id and p.status = 'confirmed'
         and coalesce(p.notes, '') ilike 'concilia%'
         and (p.bank_transaction_id = v_tx
              or p.id = (select t.reconciled_payment_id from public.bank_transactions t where t.id = v_tx));
      if v_pagamento_id is not null then
        update public.payments
           set status = 'cancelled', cancelled_at = now(),
               cancellation_reason = left('Vínculo com o extrato desfeito' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
         where receivable_id = p_id and status = 'confirmed'
           and coalesce(notes, '') ilike 'concilia%'
           and (bank_transaction_id = v_tx
                or id = (select t.reconciled_payment_id from public.bank_transactions t where t.id = v_tx));
        v_pago := greatest(0, v_pago - v_pagamento_valor);
      end if;
      update public.payments set bank_transaction_id = null
       where receivable_id = p_id and status = 'confirmed' and bank_transaction_id = v_tx;

      update public.receivables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
      v_continua := public._reacomodar_entrada(v_tx);
      if not v_continua then
        update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
      end if;
    end if;

    v_msg := 'Vínculo desfeito: o lançamento continua valendo e '
      || case when v_continua then 'a linha do extrato continua pagando a(s) outra(s) conta(s).'
              else 'a linha do extrato voltou para a fila.' end
      || case when v_pagamento_id is not null then ' O pagamento que o casamento tinha registrado foi estornado.'
              when v_pago > 0 then ' O pagamento registrado à mão continua valendo.'
              else '' end;
  end if;

  if v_grupo is not null then
    v_msg := v_msg || ' ' || (v_grupo ->> 'frase');
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    v_acao, v_autor, v_tx,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    (v_antes ->> 'amount')::numeric,
    left(coalesce(nullif(btrim(p_motivo), ''), v_msg) || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'bank_transaction_id', v_tx, 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('status', case when v_nasceu then 'cancelled' else null end, 'bank_transaction_id', null,
                       'proposta_voltou', v_voltaram > 0, 'pagamento_estornado', v_pagamento_id,
                       'entrada_continua_em_outras_contas', v_continua)
  );

  return jsonb_build_object('ok', true, 'acao', v_acao, 'proposta_voltou', v_voltaram > 0, 'message', v_msg);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.desfazer_aprovacao(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.desfazer_aprovacao(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.desfazer_aprovacao(p_tipo text, p_id uuid, p_motivo text, p_autor uuid) TO service_role;

-- ── public.detect_so_change_after_signature() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.detect_so_change_after_signature()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.signed_at IS NOT NULL
     AND NEW.requires_resignature = false
     AND (
       NEW.problem_description IS DISTINCT FROM OLD.problem_description OR
       NEW.diagnosis IS DISTINCT FROM OLD.diagnosis OR
       NEW.solution_applied IS DISTINCT FROM OLD.solution_applied OR
       NEW.customer_visible_report IS DISTINCT FROM OLD.customer_visible_report OR
       NEW.payment_conditions IS DISTINCT FROM OLD.payment_conditions OR
       NEW.extra_notes IS DISTINCT FROM OLD.extra_notes OR
       NEW.grand_total IS DISTINCT FROM OLD.grand_total OR
       NEW.labor_cost_total IS DISTINCT FROM OLD.labor_cost_total OR
       NEW.parts_cost_total IS DISTINCT FROM OLD.parts_cost_total OR
       NEW.travel_cost_total IS DISTINCT FROM OLD.travel_cost_total OR
       NEW.discount_amount IS DISTINCT FROM OLD.discount_amount OR
       NEW.tax_amount IS DISTINCT FROM OLD.tax_amount OR
       NEW.operational_cost_total IS DISTINCT FROM OLD.operational_cost_total OR
       NEW.quote_validity_date IS DISTINCT FROM OLD.quote_validity_date
     )
  THEN
    NEW.requires_resignature := true;
    NEW.resignature_requested_at := now();

    -- supersede assinaturas anteriores
    UPDATE public.service_order_signatures
    SET superseded_at = now(),
        superseded_reason = 'OS alterada após assinatura'
    WHERE service_order_id = NEW.id
      AND superseded_at IS NULL;
  END IF;
  RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.detect_so_change_after_signature() TO postgres;
GRANT EXECUTE ON FUNCTION public.detect_so_change_after_signature() TO authenticated;
GRANT EXECUTE ON FUNCTION public.detect_so_change_after_signature() TO service_role;

-- ── public.dre_cobertura(p_ano integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.dre_cobertura(p_ano integer)
 RETURNS TABLE(mes integer, receita_lancada numeric, entrada_banco numeric, despesa_lancada numeric, saida_banco numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with meses as (select generate_series(1, 12) m),
  rec as (
    select extract(month from issue_date)::int m, sum(amount) total
      from public.receivables
     where extract(year from issue_date) = p_ano
       and coalesce(status, '') <> 'cancelled'
     group by 1
  ),
  pag as (
    select extract(month from issue_date)::int m, sum(amount) total
      from public.payables
     where extract(year from issue_date) = p_ano
     group by 1
  ),
  banco as (
    select extract(month from transaction_date)::int m,
           sum(amount) filter (where transaction_type = 'credit') entradas,
           sum(amount) filter (where transaction_type = 'debit') saidas
      from public.bank_transactions
     where extract(year from transaction_date) = p_ano
       and coalesce(source_type, 'bank') = 'bank'
       and coalesce(tx_status, '') <> 'PENDING'
     group by 1
  )
  select meses.m,
         coalesce(rec.total, 0)::numeric,
         coalesce(banco.entradas, 0)::numeric,
         coalesce(pag.total, 0)::numeric,
         coalesce(banco.saidas, 0)::numeric
    from meses
    left join rec on rec.m = meses.m
    left join pag on pag.m = meses.m
    left join banco on banco.m = meses.m
   order by meses.m;
$function$
;
COMMENT ON FUNCTION public.dre_cobertura(p_ano integer) IS 'Por mês do ano: receita e despesa lançadas (por issue_date, base do DRE) contra entradas e saídas do banco (por transaction_date, conta corrente efetivada). Serve ao selo de confiabilidade do DRE.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.dre_cobertura(p_ano integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.dre_cobertura(p_ano integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dre_cobertura(p_ano integer) TO service_role;

-- ── public.entrada_de_estoque(p_produto uuid, p_quantidade numeric, p_custo numeric, p_notas text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.entrada_de_estoque(p_produto uuid, p_quantidade numeric, p_custo numeric DEFAULT NULL::numeric, p_notas text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_atual numeric;
  v_mov uuid;
  v_autor record;
begin
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'A quantidade da entrada precisa ser maior que zero.';
  end if;

  perform 1 from public.products where id = p_produto for update;
  if not found then
    raise exception 'Produto não encontrado.';
  end if;

  select coalesce(sum(quantity_delta), 0) into v_atual
    from public.inventory_movements where product_id = p_produto;

  select * into v_autor from private.estoque_autor(p_autor);
  insert into public.inventory_movements
    (product_id, movement_type, quantity_delta, unit_cost_snapshot, reference_type, notes, created_by, adjusted_by)
  values
    (p_produto, 'purchase', p_quantidade, p_custo, 'manual_entry', nullif(btrim(coalesce(p_notas, '')), ''),
     v_autor.id, v_autor.nome)
  returning id into v_mov;

  update public.products set last_stock_entry_at = now() where id = p_produto;

  return jsonb_build_object('ok', true, 'anterior', v_atual, 'nova', v_atual + p_quantidade,
                            'movimento_id', v_mov);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.entrada_de_estoque(p_produto uuid, p_quantidade numeric, p_custo numeric, p_notas text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.entrada_de_estoque(p_produto uuid, p_quantidade numeric, p_custo numeric, p_notas text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.entrada_de_estoque(p_produto uuid, p_quantidade numeric, p_custo numeric, p_notas text, p_autor uuid) TO service_role;

-- ── public.estimate_from_cases(p_service_id uuid, p_min_casos integer) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.estimate_from_cases(p_service_id uuid, p_min_casos integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n integer; v_p50 numeric; v_p80 numeric; v_casos jsonb;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select count(*),
         percentile_cont(0.5) within group (order by actual_minutes),
         percentile_cont(0.8) within group (order by actual_minutes)
    into v_n, v_p50, v_p80
  from public.service_cases
  where service_id = p_service_id and usable and actual_minutes > 0;

  if v_n < p_min_casos then
    return jsonb_build_object('tem_base', false, 'casos', v_n,
      'mensagem', 'Sem base suficiente: ' || v_n || ' execução(ões) registrada(s), mínimo ' || p_min_casos ||
                  '. Use o tempo padrão do roteiro e trate a estimativa como provisória.');
  end if;

  -- NOVO-lev-30: o limit fica na SUBCONSULTA — depois do jsonb_agg ele limitava a linha
  -- agregada (uma só), e a folha recebia todas as execuções numa linha.
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', x.os, 'minutos', x.minutos, 'quando', x.quando)
         order by x.quando desc), '[]'::jsonb) into v_casos
  from (
    select so.service_order_number as os, c.actual_minutes as minutos, c.created_at::date as quando,
           c.created_at
    from public.service_cases c
    left join public.service_orders so on so.id = c.service_order_id
    where c.service_id = p_service_id and c.usable and c.actual_minutes > 0
    order by c.created_at desc
    limit 5
  ) x;

  return jsonb_build_object('tem_base', true, 'casos', v_n,
    'p50_min', round(v_p50), 'p80_min', round(v_p80),
    'contingencia_pct', least(30, greatest(5, round(((v_p80 - v_p50) / nullif(v_p50,0)) * 100))),
    'baseado_em', v_casos);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.estimate_from_cases(p_service_id uuid, p_min_casos integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.estimate_from_cases(p_service_id uuid, p_min_casos integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.estimate_from_cases(p_service_id uuid, p_min_casos integer) TO service_role;

-- ── public.estoque_saldos_divergentes() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.estoque_saldos_divergentes()
 RETURNS TABLE(product_id uuid, name text, sku text, saldo numeric, soma numeric, diferenca numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select p.id, p.name, p.sku, p.stock_quantity,
         coalesce(m.soma, 0) as soma,
         p.stock_quantity - coalesce(m.soma, 0) as diferenca
    from public.products p
    left join (select product_id, sum(quantity_delta) soma from public.inventory_movements group by product_id) m on m.product_id = p.id
   where p.stock_quantity is distinct from coalesce(m.soma, 0)
   order by abs(p.stock_quantity - coalesce(m.soma, 0)) desc;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.estoque_saldos_divergentes() TO postgres;
GRANT EXECUTE ON FUNCTION public.estoque_saldos_divergentes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.estoque_saldos_divergentes() TO service_role;

-- ── public.extrato_da_conta(p_conexao uuid, p_de date, p_ate date) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.extrato_da_conta(p_conexao uuid, p_de date, p_ate date)
 RETURNS TABLE(id uuid, data date, descricao text, contraparte text, documento text, tipo text, valor numeric, saldo_apos numeric, situacao text, pendente boolean, lancamento_tipo text, lancamento_id uuid, lancamento_descricao text, categoria text, quem text, tipo_fora text, motivo_fora text, proposta_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with base as (
    select c.saldo_base from public.bank_connections c where c.id = p_conexao
  ),
  mov as (
    select t.*,
           (coalesce(t.tx_status, '') <> 'PENDING' and coalesce(t.dismissed_kind, '') not in ('duplicata', 'estornada')) as conta_no_saldo,
           case when t.transaction_type = 'credit' then t.amount else -t.amount end as com_sinal
      from public.bank_transactions_situacao t
     where t.bank_connection_id = p_conexao
       and coalesce(t.source_type, 'bank') in ('bank', 'cash')
  ),
  acumulado as (
    select m.*,
           sum(case when m.conta_no_saldo then m.com_sinal else 0 end)
             over (order by m.transaction_date, m.created_at, m.id rows unbounded preceding) as soma_ate_aqui
      from mov m
  )
  select a.id, a.transaction_date, a.description,
         coalesce(a.counterparty_name, a.merchant_name), a.counterparty_document, a.transaction_type,
         a.com_sinal,
         case when (select saldo_base from base) is null then null
              else round((select saldo_base from base) + a.soma_ate_aqui, 2) end,
         a.situacao, coalesce(a.tx_status, '') = 'PENDING',
         case when p.id is not null then 'payable' when r.id is not null then 'receivable' end,
         coalesce(p.id, r.id),
         coalesce(p.description, r.description),
         coalesce(p.expense_category, r.category),
         coalesce(s.name, pe.name, cl.name, p.supplier_name),
         a.dismissed_kind, a.dismissed_reason,
         q.id
    from acumulado a
    -- Uma linha do extrato é UMA linha aqui, mesmo com o Pix dividido em partes (pró-labore +
    -- retirada de sócio, 28/09/2026): mostra o lançamento principal e as categorias das partes.
    left join lateral (
      select p0.id, p0.description, p0.supplier_id, p0.payee_id, p0.supplier_name,
             (select string_agg(x.expense_category, ' + ' order by x.divisao_id nulls first, x.created_at, x.id)
                from public.payables x
               where x.bank_transaction_id = a.id and x.status <> 'cancelled') as expense_category
        from public.payables p0
       where p0.bank_transaction_id = a.id and p0.status <> 'cancelled'
       order by p0.divisao_id nulls first, p0.created_at, p0.id
       limit 1
    ) p on true
    left join public.receivables r on r.bank_transaction_id = a.id and r.status <> 'cancelled'
    left join public.suppliers s on s.id = p.supplier_id
    left join public.payees pe on pe.id = p.payee_id
    left join public.clients cl on cl.id = r.client_id
    left join lateral (
      select fq.id from public.finance_review_queue fq
       where fq.bank_transaction_id = a.id and fq.status = 'pending'
       order by fq.created_at desc limit 1
    ) q on true
   where a.transaction_date between p_de and p_ate
   order by a.transaction_date desc, a.created_at desc, a.id desc;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.extrato_da_conta(p_conexao uuid, p_de date, p_ate date) TO postgres;
GRANT EXECUTE ON FUNCTION public.extrato_da_conta(p_conexao uuid, p_de date, p_ate date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.extrato_da_conta(p_conexao uuid, p_de date, p_ate date) TO service_role;

-- ── public.fechar_mes(p_ano integer, p_mes integer, p_motivo text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.fechar_mes(p_ano integer, p_mes integer, p_motivo text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_check jsonb;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_existente record;
begin
  if v_autor is not null and not public.is_admin(v_autor) then
    raise exception 'Só o administrador fecha o mês.' using errcode = '42501';
  end if;
  if p_mes not between 1 and 12 then raise exception 'Mês inválido: %', p_mes; end if;

  select * into v_existente from public.periodos_fechados where ano = p_ano and mes = p_mes;
  if v_existente.id is not null and v_existente.reaberto_em is null then
    raise exception 'O mês %/% já está fechado.', lpad(p_mes::text, 2, '0'), p_ano;
  end if;

  v_check := public.checklist_do_mes(p_ano, p_mes);
  if not (v_check ->> 'pronto')::boolean and (v_motivo is null or length(v_motivo) < 10) then
    raise exception 'O mês ainda não está pronto. Resolva os itens pendentes ou escreva o motivo de fechar assim mesmo.';
  end if;

  if v_existente.id is not null then
    update public.periodos_fechados
       set fechado_em = now(), fechado_por = v_autor, reaberto_em = null, reaberto_por = null
     where id = v_existente.id;
  else
    insert into public.periodos_fechados (ano, mes, fechado_em, fechado_por) values (p_ano, p_mes, now(), v_autor);
  end if;

  insert into public.reconciliation_log (acao, autor, detalhe, antes, depois)
  values ('fechou_periodo', v_autor,
          left(lpad(p_mes::text, 2, '0') || '/' || p_ano
               || case when (v_check ->> 'pronto')::boolean then ' — verificação completa'
                       else ' — fechado com pendência: ' || v_motivo end, 300),
          null, v_check);

  return jsonb_build_object('ok', true, 'pronto', (v_check ->> 'pronto')::boolean,
    'message', 'Mês ' || lpad(p_mes::text, 2, '0') || '/' || p_ano || ' fechado.'
      || case when (v_check ->> 'pronto')::boolean then '' else ' Pendências registradas na trilha com o seu motivo.' end);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.fechar_mes(p_ano integer, p_mes integer, p_motivo text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fechar_mes(p_ano integer, p_mes integer, p_motivo text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fechar_mes(p_ano integer, p_mes integer, p_motivo text, p_autor uuid) TO service_role;

-- ── public.followup_registrar_resposta(p_phone text, p_body text, p_message_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.followup_registrar_resposta(p_phone text, p_body text, p_message_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_missao uuid;
begin
  select id into v_missao
  from public.ai_followup_missions
  where contraparte_phone = public.wa_normalize_phone(p_phone)
    and status in ('active','waiting_reply')
  limit 1;
  if v_missao is null then return null; end if;

  insert into public.ai_followup_events (mission_id, tipo, conteudo, whatsapp_message_id)
  values (v_missao, 'reply', left(coalesce(p_body, ''), 2000), p_message_id);
  update public.ai_followup_missions
     set status = 'waiting_reply', proximo_toque_em = null
   where id = v_missao;
  return v_missao;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.followup_registrar_resposta(p_phone text, p_body text, p_message_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.followup_registrar_resposta(p_phone text, p_body text, p_message_id uuid) TO service_role;

-- ── public.frase_legivel(p_texto text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.frase_legivel(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_texto is null or p_texto = '' then p_texto
    when p_texto <> upper(p_texto) then p_texto          -- já tem caixa mista
    else upper(left(lower(p_texto), 1)) || substr(lower(p_texto), 2)
  end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.frase_legivel(p_texto text) TO postgres;
GRANT EXECUTE ON FUNCTION public.frase_legivel(p_texto text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.frase_legivel(p_texto text) TO service_role;

-- ── public.free_text_is_material(p_texto text) ── [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.free_text_is_material(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  -- Item de texto livre da OS: MATERIAL (compra-se) ou MÃO DE OBRA (não se compra)?
  -- Os dois chegam idênticos ao banco — service_id nulo e billing_unit 'unit' —, e
  -- sem esta separação a tela sugeria cotar "Instalação do Carregador" ao lado de
  -- "Cabo 16mm²".
  --
  -- 1º) Só substantivos GENÉRICOS de material têm precedência sobre o verbo, e a
  --     lista é curta de propósito: nome de produto (cabo, roda, fusível) aparece
  --     tanto em material quanto em serviço — "Rodados de Alumínio - Remoção,
  --     Transporte e Reinstalação" é mão de obra. Só "material/insumo/kit/peça"
  --     declaram por si que a linha é coisa, não trabalho.
  -- 2º) Sem esse prefixo, quem decide é o verbo: verbo reconhecido ⇒ serviço.
  -- 3º) Sem verbo e sem prefixo ⇒ material (é o caso de "Cabo elétrico 16mm²",
  --     "Fusível ANL/MIDI"): a linha nomeia uma coisa e nada indica trabalho.
  select case
    when unaccent(lower(coalesce(p_texto, ''))) ~
         '^\s*(materiais|material|insumos?|kit|pecas?|produtos?|componentes?|conjunto)\M'
      then true
    when (public.classify_service_text(p_texto)->>'verbo') is not null
      then false
    else true
  end;
$function$
;
COMMENT ON FUNCTION public.free_text_is_material(p_texto text) IS 'Item de texto livre da OS e MATERIAL (comprave) ou mao de obra? Substantivo GENERICO de material no inicio (material/insumo/kit/peca) tem precedencia sobre o verbo; nome de produto nao entra na lista porque aparece tambem em servico.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.free_text_is_material(p_texto text) TO postgres;
GRANT EXECUTE ON FUNCTION public.free_text_is_material(p_texto text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.free_text_is_material(p_texto text) TO service_role;

-- ── public.generate_service_order_steps(p_service_order_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.generate_service_order_steps(p_service_order_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_created integer := 0;
  v_batch integer := 0;
  v_seq integer;
  v_bloco integer;
  r_line record;
  r_sys record;
  v_tem_template boolean;
  v_key text;
  v_rotulo text;
  v_escopo text;
  v_qtd integer;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão para gerar roteiro' using errcode = '42501';
  end if;

  if not exists (select 1 from public.service_orders where id = p_service_order_id) then
    raise exception 'Ordem de serviço % não encontrada', p_service_order_id;
  end if;

  select coalesce(max(seq), 0) into v_seq
  from public.service_order_steps where service_order_id = p_service_order_id;

  select count(distinct coalesce(block_key, block)) into v_bloco
  from public.service_order_steps where service_order_id = p_service_order_id;

  -- ── Fase A: aberturas ────────────────────────────────────────────────────
  -- `left join services` porque a linha avulsa não tem serviço: a classificação
  -- vem dela mesma.
  for r_sys in
    select distinct coalesce(sos.service_system, s.service_system) as sistema
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    join public.service_systems ss on ss.slug = coalesce(sos.service_system, s.service_system)
    left join public.service_verbs sv on sv.slug = coalesce(sos.service_verb, s.service_verb)
    where sos.service_order_id = p_service_order_id
      and ss.is_physical
      and coalesce(sv.intervem_no_sistema, true)
      and not exists (select 1 from public.service_order_steps st
                      where st.service_order_service_id = sos.id)
      and not exists (select 1 from public.service_step_templates t
                      where t.service_id = sos.service_id and t.active)
    order by 1
  loop
    v_key := 'abertura:' || r_sys.sistema;
    continue when exists (select 1 from public.service_order_steps st
                          where st.service_order_id = p_service_order_id and st.block_key = v_key);

    select count(*), string_agg(public.frase_legivel(sos.name_snapshot), ', ' order by sos.created_at)
      into v_qtd, v_escopo
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    left join public.service_verbs sv on sv.slug = coalesce(sos.service_verb, s.service_verb)
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_system, s.service_system) = r_sys.sistema
      and coalesce(sv.intervem_no_sistema, true);

    v_bloco := v_bloco + 1;
    v_rotulo := v_bloco || ' · Antes de mexer — ' || public.service_system_label(r_sys.sistema);

    insert into public.service_order_steps (
      service_order_id, service_order_service_id, template_id, seq, block, block_key, block_note,
      title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
      requires_measure, measure_unit, origin)
    select
      p_service_order_id, null, null, v_seq + row_number() over (order by b.seq),
      v_rotulo, v_key,
      case when v_qtd > 1
           then 'Vale para os ' || v_qtd || ' serviços desta OS: ' || v_escopo || '.'
           else 'Vale para: ' || v_escopo || '.' end,
      b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
      b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
    from public.service_step_blocks b
    where b.active and b.block_role = 'abertura' and b.applies_to_system = r_sys.sistema;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- ── Fase B: o corpo de cada linha ────────────────────────────────────────
  -- A condição `service_id is not null` saiu: agora basta a linha ter verbo,
  -- próprio ou herdado do catálogo.
  for r_line in
    select sos.id as line_id, sos.service_id, sos.name_snapshot,
           coalesce(sos.service_verb, s.service_verb) as verbo_efetivo
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_verb, s.service_verb) is not null
      and not exists (select 1 from public.service_order_steps st
                      where st.service_order_service_id = sos.id)
    order by sos.created_at
  loop
    select exists (select 1 from public.service_step_templates t
                   where t.service_id = r_line.service_id and t.active) into v_tem_template;

    v_bloco := v_bloco + 1;
    v_key := 'linha:' || r_line.line_id;
    v_rotulo := v_bloco || ' · ' || public.frase_legivel(r_line.name_snapshot);

    if v_tem_template then
      insert into public.service_order_steps (
        service_order_id, service_order_service_id, template_id, seq, block, block_key,
        title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
        requires_measure, measure_unit, origin)
      select
        p_service_order_id, r_line.line_id, t.id, v_seq + row_number() over (order by t.seq),
        v_rotulo, v_key,
        t.title, t.detail, t.kind, t.mode, t.standard_minutes, t.is_killer,
        t.requires_photo, t.requires_measure, t.measure_unit, 'template'
      from public.service_step_templates t
      where t.service_id = r_line.service_id
        and t.active
        and t.version = (select max(version) from public.service_step_templates
                         where service_id = r_line.service_id and active);
    else
      insert into public.service_order_steps (
        service_order_id, service_order_service_id, template_id, seq, block, block_key,
        title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
        requires_measure, measure_unit, origin)
      select
        p_service_order_id, r_line.line_id, null, v_seq + row_number() over (order by b.seq),
        v_rotulo, v_key,
        b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
        b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
      from public.service_step_blocks b
      where b.active and b.block_role = 'corpo' and b.applies_to_verb = r_line.verbo_efetivo;
    end if;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;
    if v_batch = 0 then v_bloco := v_bloco - 1; end if;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- ── Fase C: fechamentos ──────────────────────────────────────────────────
  for r_sys in
    select distinct replace(st.block_key, 'abertura:', '') as sistema
    from public.service_order_steps st
    where st.service_order_id = p_service_order_id and st.block_key like 'abertura:%'
    order by 1
  loop
    v_key := 'fechamento:' || r_sys.sistema;
    continue when exists (select 1 from public.service_order_steps st
                          where st.service_order_id = p_service_order_id and st.block_key = v_key);

    select count(*) into v_qtd
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    left join public.service_verbs sv on sv.slug = coalesce(sos.service_verb, s.service_verb)
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_system, s.service_system) = r_sys.sistema
      and coalesce(sv.intervem_no_sistema, true);

    v_bloco := v_bloco + 1;
    v_rotulo := v_bloco || ' · Antes de entregar — ' || public.service_system_label(r_sys.sistema);

    insert into public.service_order_steps (
      service_order_id, service_order_service_id, template_id, seq, block, block_key, block_note,
      title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
      requires_measure, measure_unit, origin)
    select
      p_service_order_id, null, null, v_seq + row_number() over (order by b.seq),
      v_rotulo, v_key,
      case when v_qtd > 1
           then 'Fecha os ' || v_qtd || ' serviços de ' ||
                lower(public.service_system_label(r_sys.sistema)) || ' desta OS.'
           else 'Fecha o serviço de ' ||
                lower(public.service_system_label(r_sys.sistema)) || ' desta OS.' end,
      b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
      b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
    from public.service_step_blocks b
    where b.active and b.block_role = 'fechamento' and b.applies_to_system = r_sys.sistema;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  return v_created;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.generate_service_order_steps(p_service_order_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.generate_service_order_steps(p_service_order_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_service_order_steps(p_service_order_id uuid) TO service_role;

-- ── public.get_agenda_conflicts(p_user_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_exclude_task uuid, p_exclude_so uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.get_agenda_conflicts(p_user_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_exclude_task uuid DEFAULT NULL::uuid, p_exclude_so uuid DEFAULT NULL::uuid)
 RETURNS TABLE(source text, ref_id uuid, label text, starts_at timestamp with time zone, ends_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT 'task'::text, t.id, t.title, t.scheduled_start_at, t.scheduled_end_at
    FROM agenda_tasks t
   WHERE t.assignee_user_id = p_user_id
     AND t.kind = 'appointment'
     AND t.status IN ('pending','in_progress')
     AND t.id IS DISTINCT FROM p_exclude_task
     AND t.scheduled_start_at IS NOT NULL AND t.scheduled_end_at IS NOT NULL
     AND tstzrange(t.scheduled_start_at, t.scheduled_end_at) && tstzrange(p_start, p_end)
  UNION ALL
  SELECT 'service_order'::text, so.id, so.service_order_number, so.scheduled_start_at, so.scheduled_end_at
    FROM service_orders so
    JOIN service_order_technicians sot ON sot.service_order_id = so.id
   WHERE sot.user_id = p_user_id
     AND so.status <> 'cancelled'
     AND so.id IS DISTINCT FROM p_exclude_so
     AND so.scheduled_start_at IS NOT NULL AND so.scheduled_end_at IS NOT NULL
     AND tstzrange(so.scheduled_start_at, so.scheduled_end_at) && tstzrange(p_start, p_end);
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.get_agenda_conflicts(p_user_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_exclude_task uuid, p_exclude_so uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.get_agenda_conflicts(p_user_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_exclude_task uuid, p_exclude_so uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_agenda_conflicts(p_user_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_exclude_task uuid, p_exclude_so uuid) TO service_role;

-- ── public.get_entity_open_loops(p_entity_type text, p_entity_id uuid, p_limit integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.get_entity_open_loops(p_entity_type text, p_entity_id uuid, p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, kind text, source text, title text, detail text, due_at timestamp with time zone, priority text, service_order_id uuid, service_order_number text, mentions integer, evidence text, opened_at timestamp with time zone, last_seen_at timestamp with time zone, atrasado boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT l.id, l.kind, l.source, l.title, l.detail, l.due_at, l.priority,
         l.service_order_id, so.service_order_number, l.mentions, l.evidence,
         l.opened_at, l.last_seen_at,
         (l.due_at IS NOT NULL AND l.due_at < now()) AS atrasado
    FROM entity_open_loops l
    LEFT JOIN service_orders so ON so.id = l.service_order_id
   WHERE l.entity_type = p_entity_type
     AND l.entity_id = p_entity_id
     AND l.status = 'open'
   ORDER BY
     (l.due_at IS NOT NULL AND l.due_at < now()) DESC,
     CASE l.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END,
     l.due_at NULLS LAST,
     l.last_seen_at DESC
   LIMIT coalesce(p_limit, 20);
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.get_entity_open_loops(p_entity_type text, p_entity_id uuid, p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.get_entity_open_loops(p_entity_type text, p_entity_id uuid, p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_entity_open_loops(p_entity_type text, p_entity_id uuid, p_limit integer) TO service_role;

-- ── public.get_open_loops(p_direction text, p_limit integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.get_open_loops(p_direction text DEFAULT 'ours'::text, p_limit integer DEFAULT 100)
 RETURNS TABLE(id uuid, entity_type text, entity_id uuid, entity_name text, kind text, source text, direction text, title text, detail text, due_at timestamp with time zone, priority text, service_order_id uuid, service_order_number text, mentions integer, evidence text, opened_at timestamp with time zone, last_seen_at timestamp with time zone, atrasado boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT
    l.id, l.entity_type, l.entity_id,
    coalesce(c.name, s.name, '—') AS entity_name,
    l.kind, l.source, l.direction, l.title, l.detail,
    l.due_at, l.priority, l.service_order_id,
    so.service_order_number, l.mentions, l.evidence,
    l.opened_at, l.last_seen_at,
    (l.due_at IS NOT NULL AND l.due_at < now()) AS atrasado
  FROM entity_open_loops l
  LEFT JOIN clients   c  ON l.entity_type = 'client'   AND c.id = l.entity_id
  LEFT JOIN suppliers s  ON l.entity_type = 'supplier' AND s.id = l.entity_id
  LEFT JOIN service_orders so ON so.id = l.service_order_id
  WHERE l.status = 'open'
    AND (p_direction IS NULL OR l.direction = p_direction)
  ORDER BY
    (l.due_at IS NOT NULL AND l.due_at < now()) DESC,
    CASE l.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END,
    l.due_at NULLS LAST,
    l.opened_at
  LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.get_open_loops(p_direction text, p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.get_open_loops(p_direction text, p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_open_loops(p_direction text, p_limit integer) TO service_role;

-- ── public.get_os_purchase_needs(p_so_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.get_os_purchase_needs(p_so_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select public.compute_purchase_needs(
    p_so_id,
    coalesce((select jsonb_agg(jsonb_build_object(
        'id', sop.id, 'product_id', sop.product_id, 'quantity', sop.quantity,
        'unit_cost_snapshot', sop.unit_cost_snapshot,
        'product_name', p.name, 'product_unit', p.unit)
        order by sop.created_at, sop.id)
      from service_order_parts sop
      left join products p on p.id = sop.product_id
      where sop.service_order_id = p_so_id), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'service_id', s.service_id, 'name_snapshot', s.name_snapshot,
        'billing_unit_snapshot', s.billing_unit_snapshot, 'quantity', s.quantity,
        'unit_price_snapshot', s.unit_price_snapshot)
        order by s.created_at, s.id)
      from service_order_services s
      where s.service_order_id = p_so_id), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'id', pa.id, 'stock_quantity', pa.stock_quantity, 'reserved_quantity', pa.reserved_quantity))
      from product_availability pa
      where pa.id in (select sop.product_id from service_order_parts sop
                      where sop.service_order_id = p_so_id)), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'product_id', poi.product_id, 'quantity', poi.quantity, 'received_qty', poi.received_qty))
      from purchase_order_items poi
      join purchase_orders po on po.id = poi.purchase_order_id
      where po.status in ('draft', 'sent', 'partial')
        and poi.product_id in (select sop.product_id from service_order_parts sop
                               where sop.service_order_id = p_so_id)), '[]'::jsonb)
  );
$function$
;
COMMENT ON FUNCTION public.get_os_purchase_needs(p_so_id uuid) IS 'Necessidade LIQUIDA de compra de uma OS (falta = necessario - disponivel - ja pedido). Espelha src/lib/purchase-needs.ts; e a via do agente de IA. Ordem deterministica por (created_at, id).';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.get_os_purchase_needs(p_so_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.get_os_purchase_needs(p_so_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_os_purchase_needs(p_so_id uuid) TO service_role;

-- ── public.get_promo_candidates(p_limit integer) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.get_promo_candidates(p_limit integer DEFAULT 10)
 RETURNS TABLE(product_id uuid, name text, sku text, image_url text, sale_price numeric, cost_price numeric, margin_pct numeric, stock_quantity numeric, reserved_quantity numeric, available numeric, last_sold_at timestamp with time zone, days_since_sold integer, has_image boolean, score numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with sold as (
    select sop.product_id, max(so.created_at) as last_sold_at
    from service_order_parts sop
    join service_orders so on so.id = sop.service_order_id
    group by sop.product_id
  )
  select
    p.id, p.name, p.sku, p.image_url,
    p.sale_price, p.cost_price,
    case when coalesce(p.cost_price,0) > 0
         then round((p.sale_price - p.cost_price) / p.cost_price * 100, 1) else null end as margin_pct,
    p.stock_quantity, p.reserved_quantity,
    (p.stock_quantity - coalesce(p.reserved_quantity,0)) as available,
    s.last_sold_at,
    case when s.last_sold_at is not null then extract(day from now() - s.last_sold_at)::int else null end as days_since_sold,
    (p.image_url is not null and p.image_url <> '') as has_image,
    (
      least((p.stock_quantity - coalesce(p.reserved_quantity,0)), 10) * 1.0
      + coalesce(case when coalesce(p.cost_price,0) > 0
                 then least((p.sale_price - p.cost_price) / nullif(p.cost_price,0) * 100, 100) else 0 end, 0) * 0.1
      + case when (p.image_url is not null and p.image_url <> '') then 5 else 0 end
      + case when s.last_sold_at is null or s.last_sold_at < now() - interval '60 days' then 3 else 0 end
    ) as score
  from products p
  left join sold s on s.product_id = p.id
  where p.active
    and p.is_equipment is true
    and p.vende_isolado
    and (p.stock_quantity - coalesce(p.reserved_quantity,0)) > 0
  order by score desc
  limit greatest(1, least(p_limit, 50));
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.get_promo_candidates(p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.get_promo_candidates(p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_promo_candidates(p_limit integer) TO service_role;

-- ── public.gravar_fechamento_de_folha(p_de date, p_ate date, p_descricao text, p_linhas jsonb, p_ator uuid, p_vencimento date) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.gravar_fechamento_de_folha(p_de date, p_ate date, p_descricao text, p_linhas jsonb, p_ator uuid DEFAULT NULL::uuid, p_vencimento date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ator        uuid;
  v_periodo_id  uuid;
  v_linha       jsonb;
  v_payable_id  uuid;
  v_perfil      record;
  v_categoria   text;
  v_nome        text;
  v_bruto       numeric;
  v_liquido     numeric;
  v_retencoes   numeric;
  v_turnos      uuid[];
  v_venc        date := coalesce(p_vencimento, p_ate + 5);
  v_geradas     int := 0;
  v_puladas     int := 0;
  v_total       numeric := 0;
  v_resultado   jsonb := '[]'::jsonb;
begin
  -- Quem está autenticado MANDA; `p_ator` só vale quando não há sessão — que é o caso do canal
  -- WhatsApp, onde a Edge Function roda com service-role e `auth.uid()` é nulo. Assim um usuário
  -- comum não escapa do próprio uid passando o UUID de um admin, e o canal continua funcionando.
  v_ator := coalesce(auth.uid(), p_ator);
  if not public.pode_ver_folha(v_ator) then
    raise exception 'Sem permissão para fechar folha.' using errcode = '42501';
  end if;

  if p_ate < p_de then
    raise exception 'Período inválido: fim (%) anterior ao início (%).', p_ate, p_de using errcode = '22007';
  end if;

  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    raise exception 'Nada a fechar: nenhuma linha apurada no período.' using errcode = '22023';
  end if;

  insert into public.payroll_periods (de, ate, descricao, status, fechado_por, fechado_em)
  values (p_de, p_ate, p_descricao, 'fechado', v_ator, now())
  returning id into v_periodo_id;

  for v_linha in select * from jsonb_array_elements(p_linhas)
  loop
    v_bruto     := coalesce((v_linha->>'valor_bruto')::numeric, 0);
    v_retencoes := coalesce((v_linha->>'retencoes')::numeric, 0);
    v_liquido   := round(v_bruto - v_retencoes, 2);

    select wp.payee_id, wp.app_user_id, wp.tipo_vinculo
      into v_perfil
      from public.work_profiles wp
     where wp.id = (v_linha->>'work_profile_id')::uuid;
    if not found then
      raise exception 'Perfil de pagamento % não existe.', v_linha->>'work_profile_id' using errcode = '23503';
    end if;

    v_nome := coalesce(
      v_linha->>'nome',
      (select p.name from public.payees   p where p.id = v_perfil.payee_id),
      (select u.full_name from public.app_users u where u.id = v_perfil.app_user_id),
      'equipe');

    -- Categoria vem do VÍNCULO, não de texto livre: é o que mantém o DRE legível depois. Todas já
    -- existem no histórico de `payables` — nenhuma categoria nova é inventada aqui.
    v_categoria := case v_perfil.tipo_vinculo
                     when 'socio' then 'Pró-labore'
                     -- CLT é salário, não pró-labore (separação de 26/09/2026).
                     when 'clt'   then 'Salários e encargos'
                     else 'Serviços de terceiros'
                   end;

    -- Linha zerada não vira conta a pagar de R$ 0,00 para alguém conferir depois.
    if v_liquido <= 0 then
      v_puladas := v_puladas + 1;
      continue;
    end if;

    insert into public.payables (
      description, issue_date, due_date, amount, balance_amount, status,
      expense_category, origin, payee_id, supplier_name, notes
    ) values (
      format('Folha %s a %s — %s', to_char(p_de,'DD/MM'), to_char(p_ate,'DD/MM/YYYY'), v_nome),
      current_date, v_venc, v_liquido, v_liquido, 'pending',
      v_categoria, 'folha', v_perfil.payee_id, v_nome,
      format('Fechamento de folha. Bruto R$ %s, retenções R$ %s. Memória de cálculo na linha da folha.',
             to_char(v_bruto,'FM999G999D00'), to_char(v_retencoes,'FM999G999D00'))
    ) returning id into v_payable_id;

    insert into public.payroll_lines (
      payroll_period_id, work_profile_id,
      horas_normais, horas_extras, horas_noturnas, horas_domingo,
      diarias_inteiras, diarias_meias,
      valor_normais, valor_extras, valor_noturnas, valor_domingo,
      valor_diarias, valor_mensal, valor_comissoes, valor_dsr,
      descontos, valor_bruto, retencoes, valor_liquido,
      nfse_numero, nfse_valor, detalhamento, payable_id, observacao
    ) values (
      v_periodo_id, (v_linha->>'work_profile_id')::uuid,
      coalesce((v_linha->>'horas_normais')::numeric, 0),   coalesce((v_linha->>'horas_extras')::numeric, 0),
      coalesce((v_linha->>'horas_noturnas')::numeric, 0),  coalesce((v_linha->>'horas_domingo')::numeric, 0),
      coalesce((v_linha->>'diarias_inteiras')::numeric, 0),coalesce((v_linha->>'diarias_meias')::numeric, 0),
      coalesce((v_linha->>'valor_normais')::numeric, 0),   coalesce((v_linha->>'valor_extras')::numeric, 0),
      coalesce((v_linha->>'valor_noturnas')::numeric, 0),  coalesce((v_linha->>'valor_domingo')::numeric, 0),
      coalesce((v_linha->>'valor_diarias')::numeric, 0),   coalesce((v_linha->>'valor_mensal')::numeric, 0),
      coalesce((v_linha->>'valor_comissoes')::numeric, 0), coalesce((v_linha->>'valor_dsr')::numeric, 0),
      coalesce((v_linha->>'descontos')::numeric, 0),       v_bruto, v_retencoes, v_liquido,
      v_linha->>'nfse_numero', (v_linha->>'nfse_valor')::numeric,
      v_linha->'detalhamento', v_payable_id, v_linha->>'observacao'
    );

    -- Turnos viram 'pago' — é o que impede o mesmo dia de entrar num segundo fechamento. Só sobem
    -- os que a linha declarou e que estavam aprovados: turno de outra pessoa não é tocado, e turno
    -- em rascunho não é pago sem alguém ter aprovado.
    v_turnos := coalesce(
      (select array_agg(t.x::uuid)
         from jsonb_array_elements_text(coalesce(v_linha->'turno_ids','[]'::jsonb)) as t(x)),
      '{}'::uuid[]);
    if array_length(v_turnos, 1) is not null then
      update public.work_shifts
         set status = 'pago', updated_at = now()
       where id = any(v_turnos) and status = 'aprovado';
    end if;

    v_geradas := v_geradas + 1;
    v_total   := v_total + v_liquido;
    v_resultado := v_resultado || jsonb_build_object(
      'nome', v_nome, 'liquido', v_liquido, 'categoria', v_categoria, 'payable_id', v_payable_id);
  end loop;

  if v_geradas = 0 then
    raise exception 'Nenhuma linha com valor a pagar no período — nada foi fechado.' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'periodo_id', v_periodo_id,
    'de', p_de, 'ate', p_ate,
    'vencimento', v_venc,
    'pessoas', v_geradas,
    'linhas_zeradas_puladas', v_puladas,
    'total_liquido', v_total,
    'linhas', v_resultado
  );
end;
$function$
;
COMMENT ON FUNCTION public.gravar_fechamento_de_folha(p_de date, p_ate date, p_descricao text, p_linhas jsonb, p_ator uuid, p_vencimento date) IS 'Fecha um periodo de folha de forma atomica: cria o periodo, grava as linhas ja apuradas, gera uma conta a pagar por pessoa (origin=folha, ligada ao payee, categoria pelo tipo de vinculo) e marca os turnos aprovados como pagos. NAO calcula nada: a regra vive em _shared/payroll/calculo.ts e as linhas chegam prontas. Exige pode_ver_folha() do usuario autenticado, ou de p_ator quando nao ha sessao (canal WhatsApp).';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.gravar_fechamento_de_folha(p_de date, p_ate date, p_descricao text, p_linhas jsonb, p_ator uuid, p_vencimento date) TO postgres;
GRANT EXECUTE ON FUNCTION public.gravar_fechamento_de_folha(p_de date, p_ate date, p_descricao text, p_linhas jsonb, p_ator uuid, p_vencimento date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gravar_fechamento_de_folha(p_de date, p_ate date, p_descricao text, p_linhas jsonb, p_ator uuid, p_vencimento date) TO service_role;

-- ── public.handle_new_user() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

-- ── public.handle_quote_deposit_payment() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.handle_quote_deposit_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Only fire when status moves TO paid/partially_paid
  if new.service_order_id is not null
     and new.status in ('paid', 'partially_paid')
     and (old.status is distinct from new.status) then

    update public.service_orders
    set
      converted_to_os_at = now(),
      status             = 'approved',
      quote_status       = 'approved'
    where id                  = new.service_order_id
      and converted_to_os_at  is null
      and quote_status         = 'awaiting_deposit';

    -- Sinal pago numa OS já convertida (Extrato, "Este Pix paga…"): só o estado do orçamento.
    if new.is_deposit then
      update public.service_orders
         set quote_status = 'approved'
       where id = new.service_order_id
         and converted_to_os_at is not null
         and quote_status = 'awaiting_deposit';
    end if;

  end if;
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.handle_quote_deposit_payment() TO postgres;
GRANT EXECUTE ON FUNCTION public.handle_quote_deposit_payment() TO service_role;

-- ── public.increment_finance_rule_usage(rule_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.increment_finance_rule_usage(rule_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE public.finance_rules
  SET times_applied = times_applied + 1, last_applied_at = now()
  WHERE id = rule_id;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.increment_finance_rule_usage(rule_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.increment_finance_rule_usage(rule_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_finance_rule_usage(rule_id uuid) TO service_role;

-- ── public.is_admin(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_users
    WHERE id = _user_id
      AND role = 'admin'
      AND active = true
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.is_admin(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.is_admin(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin(_user_id uuid) TO service_role;

-- ── public.is_admin_or_financial(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.is_admin_or_financial(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role IN ('admin','financial') AND active = true
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.is_admin_or_financial(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.is_admin_or_financial(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin_or_financial(_user_id uuid) TO service_role;

-- ── public.is_external_seller(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.is_external_seller(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role = 'external_seller' AND active = true
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.is_external_seller(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.is_external_seller(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_external_seller(_user_id uuid) TO service_role;

-- ── public.is_technician(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.is_technician(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role = 'technician' AND active = true
  );
$function$
;
COMMENT ON FUNCTION public.is_technician(_user_id uuid) IS 'Verdadeiro para usuário ativo de cargo técnico. Usada nas políticas do financeiro (decisão do dono, 09/08/2026).';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.is_technician(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.is_technician(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_technician(_user_id uuid) TO service_role;

-- ── public.lancar_no_caixa(p_sentido text, p_valor numeric, p_descricao text, p_data date, p_categoria text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_os_id uuid, p_pago_por text, p_socio_id uuid, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.lancar_no_caixa(p_sentido text, p_valor numeric, p_descricao text, p_data date DEFAULT NULL::date, p_categoria text DEFAULT NULL::text, p_fornecedor_id uuid DEFAULT NULL::uuid, p_favorecido_id uuid DEFAULT NULL::uuid, p_cliente_id uuid DEFAULT NULL::uuid, p_os_id uuid DEFAULT NULL::uuid, p_pago_por text DEFAULT 'caixa'::text, p_socio_id uuid DEFAULT NULL::uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_data date := coalesce(p_data, public._hoje_brt());
  v_desc text := nullif(btrim(coalesce(p_descricao, '')), '');
  v_cat text;
  v_quem text;
  v_tx uuid;
  v_id uuid;
  v_socio text;
begin
  if p_sentido not in ('saida', 'entrada') then raise exception 'Sentido inválido: % (saida ou entrada).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  if v_desc is null then raise exception 'Diga o que foi (ex.: almoço da equipe).'; end if;
  if p_pago_por not in ('caixa', 'socio') then raise exception 'Pago por: caixa ou socio.'; end if;
  if v_data > public._hoje_brt() + 1 then raise exception 'Data no futuro: para algo que ainda vai acontecer, use conta a pagar.'; end if;
  perform public._recusa_se_mes_fechado(v_data, 'lançar nesta data');

  v_quem := coalesce(
    (select name from public.suppliers where id = p_fornecedor_id),
    (select name from public.payees where id = p_favorecido_id),
    (select name from public.clients where id = p_cliente_id));

  if p_sentido = 'saida' then
    -- Categoria: a informada; senão a padrão do favorecido; senão "Outras despesas".
    v_cat := coalesce(nullif(btrim(coalesce(p_categoria, '')), ''),
                      (select default_category from public.payees where id = p_favorecido_id),
                      'Outras despesas');

    if p_pago_por = 'socio' then
      if p_socio_id is null then raise exception 'Diga qual sócio pagou, para o reembolso ficar no nome dele.'; end if;
      select name into v_socio from public.payees where id = p_socio_id;
      if v_socio is null then raise exception 'Sócio não encontrado entre os favorecidos.'; end if;
      -- A despesa existe (entra no resultado) e a empresa DEVE ao sócio: conta a pagar em
      -- aberto no nome dele. Nada sai do Caixa. Quem recebeu vai em beneficiario_id (28/09/2026).
      insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                   expense_category, supplier_id, payee_id, beneficiario_id, linked_service_order_id, origin, notes)
      values (left('Pago por ' || v_socio || ': ' || v_desc, 200), v_data, v_data, round(p_valor, 2), 0, round(p_valor, 2), 'pending',
              v_cat, p_fornecedor_id, p_socio_id, p_favorecido_id, p_os_id, 'manual',
              'Reembolso ao sócio — pago do bolso' || coalesce(' para ' || v_quem, '') || '.')
      returning id into v_id;
    else
      v_tx := public._linha_do_caixa('debit', p_valor, v_data, v_desc, coalesce(v_quem, v_desc), null, null, v_autor);
      insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                   expense_category, supplier_id, payee_id, supplier_name, linked_service_order_id,
                                   origin, payment_method, bank_transaction_id)
      values (left(v_desc, 200), v_data, v_data, round(p_valor, 2), round(p_valor, 2), 0, 'paid',
              v_cat, p_fornecedor_id, p_favorecido_id, case when p_fornecedor_id is null then v_quem end, p_os_id,
              'manual', 'cash', v_tx)
      returning id into v_id;
    end if;
  else
    if p_cliente_id is null then raise exception 'Dinheiro que entra precisa de cliente: de quem veio?'; end if;
    if p_pago_por <> 'caixa' then raise exception 'Entrada em dinheiro vai para o Caixa.'; end if;
    v_cat := coalesce(nullif(btrim(coalesce(p_categoria, '')), ''), 'Serviços prestados');
    v_tx := public._linha_do_caixa('credit', p_valor, v_data, v_desc, v_quem, null, null, v_autor);
    insert into public.receivables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                    category, client_id, service_order_id, payment_method, bank_transaction_id)
    values (left(v_desc, 200), v_data, v_data, round(p_valor, 2), round(p_valor, 2), 0, 'paid',
            v_cat, p_cliente_id, p_os_id, 'cash', v_tx)
    returning id into v_id;
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values ('lancou_no_caixa', v_autor, v_tx,
          case when p_sentido = 'saida' then v_id end, case when p_sentido = 'entrada' then v_id end,
          round(p_valor, 2),
          left(case when p_pago_por = 'socio' then 'Pago do bolso de ' || v_socio || ': ' else '' end || v_desc || coalesce(' · ' || v_quem, ''), 300),
          null, jsonb_build_object('sentido', p_sentido, 'categoria', v_cat, 'pago_por', p_pago_por, 'data', v_data));

  return jsonb_build_object(
    'ok', true,
    'lancamento_id', v_id,
    'tipo', case when p_sentido = 'saida' then 'payable' else 'receivable' end,
    'categoria', v_cat,
    'saldo_do_caixa', public.saldo_do_caixa(),
    'message', case
      when p_pago_por = 'socio' then 'Lançado ' || public._brl(p_valor) || ' em ' || v_cat || ', pago por ' || v_socio || ' — fica como reembolso a pagar a ele.'
      when p_sentido = 'saida' then 'Lançado ' || public._brl(p_valor) || ' em ' || v_cat || ', pago em dinheiro. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.'
        || case when public.saldo_do_caixa() < 0 then ' Atenção: o Caixa ficou negativo — falta registrar o dinheiro que entrou nele (saldo inicial pela contagem, ou o saque do banco).' else '' end
      else 'Entrada de ' || public._brl(p_valor) || ' em dinheiro lançada. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.' end
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.lancar_no_caixa(p_sentido text, p_valor numeric, p_descricao text, p_data date, p_categoria text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_os_id uuid, p_pago_por text, p_socio_id uuid, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.lancar_no_caixa(p_sentido text, p_valor numeric, p_descricao text, p_data date, p_categoria text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_os_id uuid, p_pago_por text, p_socio_id uuid, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lancar_no_caixa(p_sentido text, p_valor numeric, p_descricao text, p_data date, p_categoria text, p_fornecedor_id uuid, p_favorecido_id uuid, p_cliente_id uuid, p_os_id uuid, p_pago_por text, p_socio_id uuid, p_autor uuid) TO service_role;

-- ── public.ligar_parcela_ao_pagamento(p_parcela uuid, p_pagamento uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.ligar_parcela_ao_pagamento(p_parcela uuid, p_pagamento uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_parc   public.payables%rowtype;
  v_pag    public.payables%rowtype;
  v_numero text;
  v_qual   text;
begin
  if auth.uid() is not null and not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  select * into v_parc from public.payables where id = p_parcela for update;
  select * into v_pag from public.payables where id = p_pagamento for update;
  if v_parc.id is null or v_pag.id is null then
    raise exception 'Parcela ou pagamento não encontrado — nada foi ligado.';
  end if;
  if v_parc.origin <> 'fiscal_note' or v_parc.fiscal_note_id is null or v_parc.status <> 'pending'
     or coalesce(v_parc.paid_amount, 0) > 0 then
    raise exception 'Esta parcela não está mais a pagar — nada foi ligado.';
  end if;
  if v_pag.bank_transaction_id is null or v_pag.fiscal_note_id is not null or v_pag.status = 'cancelled' then
    raise exception 'Este pagamento não está livre para ser ligado a uma nota — nada foi ligado.';
  end if;
  if v_pag.supplier_id is distinct from v_parc.supplier_id or abs(v_pag.amount - v_parc.amount) >= 0.01 then
    raise exception 'Fornecedor ou valor diferentes — não é a mesma parcela. Nada foi ligado.';
  end if;

  select nfe_number into v_numero from public.fiscal_notes where id = v_parc.fiscal_note_id;
  v_qual := coalesce(substring(v_parc.description from '\((parcela [0-9]+/[0-9]+)\)'), 'à vista');

  update public.payables
     set fiscal_note_id = v_parc.fiscal_note_id,
         notes = btrim(coalesce(notes, '') || ' [NF-e ' || coalesce(v_numero, '') || ', ' || v_qual
                 || ': paga por este pagamento]'),
         updated_at = now()
   where id = p_pagamento;
  delete from public.payables where id = p_parcela;

  insert into public.reconciliation_log (acao, autor, payable_id, bank_transaction_id, valor, detalhe)
  values ('ligou_parcela_da_nota', auth.uid(), p_pagamento, v_pag.bank_transaction_id, v_pag.amount,
          left('NF-e ' || coalesce(v_numero, '') || ', ' || v_qual || ': o pagamento lançado pelo Extrato é esta parcela '
               || '(confirmado na importação da nota); a parcela a pagar que a importação criou saiu.', 300));

  return jsonb_build_object('ok', true, 'pagamento', p_pagamento, 'nota', v_parc.fiscal_note_id);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.ligar_parcela_ao_pagamento(p_parcela uuid, p_pagamento uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.ligar_parcela_ao_pagamento(p_parcela uuid, p_pagamento uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ligar_parcela_ao_pagamento(p_parcela uuid, p_pagamento uuid) TO service_role;

-- ── public.lines_missing_system(p_service_order_id uuid) ── [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.lines_missing_system(p_service_order_id uuid)
 RETURNS TABLE(line_id uuid, service_name text, service_verb text, sistema_atual text, sistema_sugerido text, verbo_sugerido text, origem_sistema text, origem_verbo text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  with base as (
    select
      sos.id,
      sos.name_snapshot,
      coalesce(sos.service_verb, s.service_verb) as verbo_atual,
      coalesce(sos.service_system, s.service_system) as sistema_gravado,
      sos.service_id,
      -- o que o texto da própria linha diz
      (select ss.slug from public.service_systems ss
        where ss.slug = (public.classify_service_text(sos.name_snapshot)->>'sistema')
          and ss.is_physical and ss.active) as sis_da_linha,
      (select sv.slug from public.service_verbs sv
        where sv.slug = (public.classify_service_text(sos.name_snapshot)->>'verbo')
          and sv.active) as verbo_da_linha,
      -- e o que o contexto da OS sugere, como segunda opção
      (select sug.sistema from public.suggest_system_for_line(sos.id) sug) as sis_da_os
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and (
        (sos.service_system is null and s.service_system is null)
        or (sos.service_verb is null and s.service_verb is null)
      )
      and not exists (select 1 from public.service_step_templates t
                      where t.service_id = sos.service_id and t.active)
  )
  select
    id, name_snapshot, verbo_atual,
    sistema_gravado,
    coalesce(sis_da_linha, sis_da_os),
    verbo_da_linha,
    case when sis_da_linha is not null then 'linha'
         when sis_da_os is not null then 'os'
         else null end,
    case when verbo_da_linha is not null then 'linha' else null end
  from base;
$function$
;
COMMENT ON FUNCTION public.lines_missing_system(p_service_order_id uuid) IS 'Linhas da ordem em que falta pelo menos um dos dois eixos de classificação.
   Devolve o que está GRAVADO (sistema_atual, service_verb) e, à parte, o
   PALPITE (sistema_sugerido, verbo_sugerido) com a procedência de cada um — a
   tela precisa saber a diferença para não oferecer um palpite por cima de uma
   classificação que já existe.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.lines_missing_system(p_service_order_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.lines_missing_system(p_service_order_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lines_missing_system(p_service_order_id uuid) TO service_role;

-- ── public.linhas_do_checklist(p_ano integer, p_mes integer, p_chave text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.linhas_do_checklist(p_ano integer, p_mes integer, p_chave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_ini date := make_date(p_ano, p_mes, 1);
  v_fim date := (make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date;
  v jsonb;
begin
  if p_chave = 'saldo_confere' then
    select jsonb_agg(jsonb_build_object(
             'tipo', 'conta', 'id', c.id, 'data', (k.conferido_em at time zone 'America/Sao_Paulo')::date,
             'valor', k.diferenca, 'descricao', c.label, 'quem', null,
             'detalhe', 'O saldo calculado difere do banco em ' || public._brl(abs(k.diferenca)) || '.') order by c.label)
      into v
      from public.bank_connections c
      join lateral (select * from public.bank_balance_checks b where b.bank_connection_id = c.id
                     order by b.conferido_em desc limit 1) k on true
     where coalesce(c.active, true) and not k.fecha;

  elsif p_chave = 'extrato_tratado' then
    select jsonb_agg(x.linha order by x.data, x.valor desc) into v from (
      select t.transaction_date as data, t.amount as valor,
             jsonb_build_object(
               'tipo', 'extrato', 'id', t.id, 'data', t.transaction_date,
               'valor', case when t.transaction_type = 'debit' then -t.amount else t.amount end,
               'descricao', coalesce(t.description, 'Sem descrição'),
               'quem', coalesce(t.counterparty_name, t.merchant_name),
               'detalhe', case when t.transaction_type = 'debit' then 'Saída esperando destino no Extrato.' else 'Entrada esperando destino no Extrato.' end) as linha
        from public.bank_transactions_situacao t
       where t.transaction_date between v_ini and v_fim and t.situacao = 'nova'
         and coalesce(t.tx_status, '') <> 'PENDING'
       order by t.transaction_date, t.amount desc
       limit 200) x;

  elsif p_chave = 'sem_duplicata' then
    select jsonb_agg(jsonb_build_object(
             'tipo', 'payable', 'id', b.id, 'data', b.issue_date, 'valor', -b.amount,
             'descricao', coalesce(b.description, b.supplier_name, 'Sem descrição'),
             'quem', coalesce(b.supplier_name, ''),
             'detalhe', 'Lançada à mão; igual a uma pelo banco de ' || to_char(a.issue_date, 'DD/MM') || ' (' || coalesce(a.description, '') || ').')
             order by b.issue_date)
      into v
      from public.payables a
      join public.payables b on b.id <> a.id
       and a.bank_transaction_id is not null and b.bank_transaction_id is null
       and b.status <> 'cancelled' and abs(a.amount - b.amount) < 0.01
       and abs(a.issue_date - b.issue_date) <= 5
       and coalesce(a.supplier_id::text, upper(a.supplier_name), '') = coalesce(b.supplier_id::text, upper(b.supplier_name), '')
       and coalesce(a.supplier_id::text, upper(a.supplier_name), '') <> ''
     where a.status <> 'cancelled' and a.issue_date between v_ini and v_fim;

  elsif p_chave in ('conciliacao_bate', 'pago_sem_banco') then
    select jsonb_agg(jsonb_build_object(
             'tipo', l.lado, 'id', l.id, 'data', coalesce(l.extrato_data, l.issue_date),
             'valor', case when l.lado = 'payable' then -l.amount else l.amount end,
             'descricao', coalesce(l.description, 'Sem descrição'), 'quem', l.contraparte,
             'detalhe', case when p_chave = 'conciliacao_bate'
                             then 'O banco mostra ' || public._brl(l.extrato_valor) || '; a diferença é ' || public._brl(abs(l.diferenca)) || '.'
                             else 'Pago, mas sem linha do banco nem do caixa.' end)
             order by coalesce(l.extrato_data, l.issue_date))
      into v
      from public.conciliacao_lancamentos l
     where case when p_chave = 'conciliacao_bate'
                then l.situacao = 'conciliado' and coalesce(l.diferenca, 0) <> 0 and not l.compra_parcelada
                     and coalesce(l.extrato_data, l.issue_date) between v_ini and v_fim
                else l.situacao = 'sem_extrato' and l.status = 'paid' and l.issue_date between v_ini and v_fim end;

  elsif p_chave = 'tudo_categorizado' then
    select jsonb_agg(x.linha order by x.data) into v from (
      select p.issue_date as data, jsonb_build_object('tipo', 'payable', 'id', p.id, 'data', p.issue_date, 'valor', -p.amount,
               'descricao', coalesce(p.description, 'Sem descrição'), 'quem', p.supplier_name, 'detalhe', 'Despesa sem categoria.') as linha
        from public.payables p
       where p.status <> 'cancelled' and p.issue_date between v_ini and v_fim and p.expense_category is null) x;

  elsif p_chave = 'outras_despesas' then
    select jsonb_agg(jsonb_build_object(
             'tipo', 'payable', 'id', p.id, 'data', p.issue_date, 'valor', -p.amount,
             'descricao', coalesce(p.description, 'Sem descrição'), 'quem', p.supplier_name,
             'detalhe', 'Em "Outras despesas": merece uma categoria própria?') order by p.issue_date)
      into v
      from public.payables p
     where p.status <> 'cancelled' and p.issue_date between v_ini and v_fim and p.expense_category = 'Outras despesas';

  else
    raise exception 'Item do "Mês pronto?" desconhecido: %', p_chave;
  end if;

  return coalesce(v, '[]'::jsonb);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.linhas_do_checklist(p_ano integer, p_mes integer, p_chave text) TO postgres;
GRANT EXECUTE ON FUNCTION public.linhas_do_checklist(p_ano integer, p_mes integer, p_chave text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.linhas_do_checklist(p_ano integer, p_mes integer, p_chave text) TO service_role;

-- ── public.log_app_error(p_source text, p_message text, p_context text, p_action text, p_level text, p_details jsonb) ── SECURITY DEFINER [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.log_app_error(p_source text, p_message text, p_context text DEFAULT NULL::text, p_action text DEFAULT NULL::text, p_level text DEFAULT 'error'::text, p_details jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_fp    text;
  v_id    uuid;
  v_msg   text;
  v_email text;
BEGIN
  IF coalesce(btrim(p_message), '') = '' THEN
    RETURN NULL;  -- nada a registrar; nunca falhar o fluxo do usuário por causa do log
  END IF;

  -- Mensagem limitada: pilhas gigantes vão em details, não no agrupamento.
  v_msg := left(btrim(p_message), 2000);

  -- Impressão digital sem os números variáveis (ids, horários), senão cada
  -- ocorrência do MESMO erro viraria um grupo novo.
  v_fp := md5(
    coalesce(p_source, '') || '|' || coalesce(p_context, '') || '|' ||
    regexp_replace(lower(left(v_msg, 500)), '[0-9a-f]{8}-[0-9a-f-]{27}|\d+', '#', 'g')
  );

  SELECT email INTO v_email FROM app_users WHERE id = auth.uid();

  INSERT INTO app_error_logs (
    fingerprint, source, level, context, action, message, details, user_id, user_email
  ) VALUES (
    v_fp, p_source,
    CASE WHEN p_level IN ('error', 'warn') THEN p_level ELSE 'error' END,
    left(p_context, 200), left(p_action, 200), v_msg, p_details, auth.uid(), v_email
  )
  ON CONFLICT (fingerprint) WHERE resolved_at IS NULL DO UPDATE
    SET occurrences  = app_error_logs.occurrences + 1,
        last_seen_at = now(),
        message      = EXCLUDED.message,
        details      = coalesce(EXCLUDED.details, app_error_logs.details),
        action       = coalesce(EXCLUDED.action, app_error_logs.action),
        user_id      = coalesce(EXCLUDED.user_id, app_error_logs.user_id),
        user_email   = coalesce(EXCLUDED.user_email, app_error_logs.user_email)
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION WHEN others THEN
  -- Um log que quebra a operação seria pior que não ter log.
  RETURN NULL;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.log_app_error(p_source text, p_message text, p_context text, p_action text, p_level text, p_details jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.log_app_error(p_source text, p_message text, p_context text, p_action text, p_level text, p_details jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_app_error(p_source text, p_message text, p_context text, p_action text, p_level text, p_details jsonb) TO service_role;

-- ── public.log_product_cost_change() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.log_product_cost_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF (OLD.cost_price IS DISTINCT FROM NEW.cost_price) THEN
        INSERT INTO product_price_history (product_id, old_cost, new_cost)
        VALUES (NEW.id, OLD.cost_price, NEW.cost_price);
    END IF;
    RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.log_product_cost_change() TO postgres;
GRANT EXECUTE ON FUNCTION public.log_product_cost_change() TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_product_cost_change() TO service_role;

-- ── public.log_step_time_entry() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.log_step_time_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tecnico uuid;
begin
  -- Só quando o passo FICA pronto com tempo apontado. Reabrir e concluir de
  -- novo atualiza o registro existente em vez de criar outro.
  if new.status <> 'done' or coalesce(new.actual_minutes, 0) <= 0 then
    return new;
  end if;
  if old.status = 'done' and coalesce(old.actual_minutes, 0) = coalesce(new.actual_minutes, 0) then
    return new;
  end if;

  -- technician_user_id é NOT NULL: quem executou o passo, senão o técnico da
  -- OS, senão quem está marcando. Sem nenhum dos três, é melhor não gravar do
  -- que gravar hora no nome de alguém que não trabalhou.
  v_tecnico := coalesce(
    new.assigned_user_id,
    (select sot.user_id from public.service_order_technicians sot
      where sot.service_order_id = new.service_order_id
      order by sot.created_at limit 1),
    auth.uid());

  if v_tecnico is null then
    return new;
  end if;

  if exists (select 1 from public.time_entries where step_id = new.id) then
    update public.time_entries set
      duration_minutes = new.actual_minutes,
      started_at = coalesce(new.started_at, started_at),
      ended_at = coalesce(new.completed_at, now()),
      updated_at = now()
    where step_id = new.id;
  else
    insert into public.time_entries (
      service_order_id, technician_user_id, started_at, ended_at,
      duration_minutes, billable, step_id, notes)
    values (
      new.service_order_id, v_tecnico,
      coalesce(new.started_at, new.completed_at, now()),
      coalesce(new.completed_at, now()),
      new.actual_minutes, true, new.id,
      'Passo do roteiro: ' || new.title);
  end if;

  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.log_step_time_entry() TO postgres;
GRANT EXECUTE ON FUNCTION public.log_step_time_entry() TO service_role;

-- ── public.match_nfe_item(p_supplier_id uuid, p_barcode text, p_sku_supplier text, p_description text, p_manual_product_id uuid) ── SECURITY DEFINER [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.match_nfe_item(p_supplier_id uuid, p_barcode text, p_sku_supplier text, p_description text, p_manual_product_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(product_id uuid, match_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  IF p_manual_product_id IS NOT NULL THEN
    RETURN QUERY SELECT p_manual_product_id, 'manual'::text;
    RETURN;
  END IF;

  IF coalesce(p_barcode, '') <> '' THEN
    SELECT id INTO v_id FROM products
      WHERE barcode = p_barcode AND active ORDER BY created_at LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'barcode'::text;
      RETURN;
    END IF;
  END IF;

  IF p_supplier_id IS NOT NULL AND coalesce(p_sku_supplier, '') <> '' THEN
    SELECT m.internal_product_id INTO v_id FROM supplier_product_mappings m
      JOIN products p ON p.id = m.internal_product_id AND p.active
      WHERE m.supplier_id = p_supplier_id AND m.supplier_sku = p_sku_supplier
      LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'de_para'::text;
      RETURN;
    END IF;
  END IF;

  IF coalesce(p_sku_supplier, '') <> '' THEN
    SELECT id INTO v_id FROM products
      WHERE sku = p_sku_supplier AND active ORDER BY created_at LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'sku'::text;
      RETURN;
    END IF;
  END IF;

  IF coalesce(p_description, '') <> '' THEN
    SELECT id INTO v_id FROM products
      WHERE active
        AND normalize_product_text(name) = normalize_product_text(p_description)
      ORDER BY created_at LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN QUERY SELECT v_id, 'descricao'::text;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT NULL::uuid, 'novo'::text;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.match_nfe_item(p_supplier_id uuid, p_barcode text, p_sku_supplier text, p_description text, p_manual_product_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.match_nfe_item(p_supplier_id uuid, p_barcode text, p_sku_supplier text, p_description text, p_manual_product_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.match_nfe_item(p_supplier_id uuid, p_barcode text, p_sku_supplier text, p_description text, p_manual_product_id uuid) TO service_role;

-- ── public.mover_caixa(p_sentido text, p_valor numeric, p_data date, p_transacao_banco uuid, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.mover_caixa(p_sentido text, p_valor numeric, p_data date DEFAULT NULL::date, p_transacao_banco uuid DEFAULT NULL::uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_data date := coalesce(p_data, public._hoje_brt());
  v_banco public.bank_transactions%rowtype;
  v_rotulo text;
begin
  if p_sentido not in ('saque', 'deposito') then raise exception 'Sentido inválido: % (saque ou deposito).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  perform public._recusa_se_mes_fechado(v_data, 'lançar nesta data');
  v_rotulo := case when p_sentido = 'saque' then 'Saque do banco para o Caixa' else 'Depósito do Caixa no banco' end;

  if p_transacao_banco is not null then
    select * into v_banco from public.bank_transactions where id = p_transacao_banco for update;
    if v_banco.id is null then raise exception 'Linha do banco não encontrada.'; end if;
    if (p_sentido = 'saque' and v_banco.transaction_type <> 'debit') or (p_sentido = 'deposito' and v_banco.transaction_type <> 'credit') then
      raise exception 'Saque é saída do banco; depósito é entrada no banco.';
    end if;
    if abs(v_banco.amount - p_valor) > 0.01 then raise exception 'O valor da linha do banco (%) não é o informado.', public._brl(v_banco.amount); end if;
    if exists (select 1 from public.payables where bank_transaction_id = p_transacao_banco)
       or exists (select 1 from public.receivables where bank_transaction_id = p_transacao_banco) then
      raise exception 'Essa linha do banco já virou lançamento. Desfaça antes.';
    end if;
    update public.bank_transactions set reconciled = true, dismissed_kind = 'transferencia', dismissed_reason = v_rotulo,
           dismissed_at = now(), dismissed_by = v_autor where id = p_transacao_banco;
    update public.finance_review_queue set status = 'superseded', decision_note = v_rotulo
     where bank_transaction_id = p_transacao_banco and status = 'pending';
    v_data := v_banco.transaction_date;
  end if;

  perform public._linha_do_caixa(case when p_sentido = 'saque' then 'credit' else 'debit' end, p_valor, v_data, v_rotulo, null,
                                 'transferencia', v_rotulo, v_autor);

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, valor, detalhe)
  values ('moveu_caixa', v_autor, p_transacao_banco, round(p_valor, 2), v_rotulo);

  return jsonb_build_object('ok', true, 'saldo_do_caixa', public.saldo_do_caixa(),
    'message', v_rotulo || ': ' || public._brl(p_valor) || '. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.');
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.mover_caixa(p_sentido text, p_valor numeric, p_data date, p_transacao_banco uuid, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.mover_caixa(p_sentido text, p_valor numeric, p_data date, p_transacao_banco uuid, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mover_caixa(p_sentido text, p_valor numeric, p_data date, p_transacao_banco uuid, p_autor uuid) TO service_role;

-- ── public.next_document_number() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.next_document_number()
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT nextval('document_number_seq');
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.next_document_number() TO postgres;
GRANT EXECUTE ON FUNCTION public.next_document_number() TO authenticated;
GRANT EXECUTE ON FUNCTION public.next_document_number() TO service_role;

-- ── public.next_fiscal_number(p_document_type text, p_series integer, p_environment text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.next_fiscal_number(p_document_type text, p_series integer DEFAULT 1, p_environment text DEFAULT 'homologacao'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_next int;
BEGIN
  INSERT INTO fiscal_document_sequences (document_type, series, environment, last_number, updated_at)
  VALUES (p_document_type, p_series, p_environment, 1, now())
  ON CONFLICT (document_type, series, environment)
  DO UPDATE SET last_number = fiscal_document_sequences.last_number + 1,
                updated_at  = now()
  RETURNING last_number INTO v_next;
  RETURN v_next;
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.next_fiscal_number(p_document_type text, p_series integer, p_environment text) TO postgres;
GRANT EXECUTE ON FUNCTION public.next_fiscal_number(p_document_type text, p_series integer, p_environment text) TO service_role;

-- ── public.normalize_alias(_s text) ── [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.normalize_alias(_s text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select trim(regexp_replace(lower(unaccent(coalesce(_s, ''))), '\s+', ' ', 'g'));
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.normalize_alias(_s text) TO postgres;
GRANT EXECUTE ON FUNCTION public.normalize_alias(_s text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_alias(_s text) TO service_role;

-- ── public.normalize_product_text(t text) ── [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.normalize_product_text(t text)
 RETURNS text
 LANGUAGE sql
 STABLE PARALLEL SAFE
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT btrim(regexp_replace(upper(extensions.unaccent(coalesce(t, ''))), '[^A-Z0-9]+', ' ', 'g'));
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.normalize_product_text(t text) TO postgres;
GRANT EXECUTE ON FUNCTION public.normalize_product_text(t text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_product_text(t text) TO service_role;

-- ── public.orcamento_aprovado_ao_converter() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.orcamento_aprovado_ao_converter()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.quote_status = 'awaiting_deposit'
     and new.converted_to_os_at is not null
     and old.converted_to_os_at is null
     and exists (
       select 1 from public.receivables r
        where r.service_order_id = new.id and r.is_deposit and r.status in ('paid', 'partially_paid')
     )
  then
    new.quote_status := 'approved';
  end if;
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.orcamento_aprovado_ao_converter() TO postgres;
GRANT EXECUTE ON FUNCTION public.orcamento_aprovado_ao_converter() TO service_role;

-- ── public.parse_answer_number(p_answer text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.parse_answer_number(p_answer text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare v_limpo text; v_num numeric;
begin
  if p_answer is null then return null; end if;
  -- Primeiro número da resposta, aceitando vírgula decimal.
  v_limpo := substring(replace(p_answer, ',', '.') from '(\d+\.?\d*)');
  if v_limpo is null then return null; end if;
  begin
    v_num := v_limpo::numeric;
  exception when others then
    return null;
  end;
  return v_num;
end;
$function$
;
COMMENT ON FUNCTION public.parse_answer_number(p_answer text) IS 'Extrai o número de uma resposta digitada em campo ("14,5 m" → 14.5).
   Devolve null quando não há número — o motor trata isso como "não dá para
   calcular", nunca como zero.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.parse_answer_number(p_answer text) TO postgres;
GRANT EXECUTE ON FUNCTION public.parse_answer_number(p_answer text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.parse_answer_number(p_answer text) TO service_role;

-- ── public.parse_valor_ptbr(p_texto text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.parse_valor_ptbr(p_texto text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare v text;
begin
  v := regexp_replace(coalesce(p_texto, ''), '[^0-9.,]', '', 'g');
  if v = '' then return null; end if;
  if position(',' in v) > 0 then
    -- vírgula presente: ponto é milhar, vírgula é decimal
    v := replace(replace(v, '.', ''), ',', '.');
  elsif v ~ '^\d{1,3}(\.\d{3})+$' then
    -- só pontos em grupos de 3: milhar pt-BR ('1.500' = 1500)
    v := replace(v, '.', '');
  end if;
  if v !~ '^\d+(\.\d+)?$' then return null; end if;
  return v::numeric;
exception when others then
  return null;
end;
$function$
;
COMMENT ON FUNCTION public.parse_valor_ptbr(p_texto text) IS 'Número pt-BR a partir de texto livre (R$, milhar com ponto, decimal com vírgula). NULL se não der — nunca exceção.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.parse_valor_ptbr(p_texto text) TO postgres;
GRANT EXECUTE ON FUNCTION public.parse_valor_ptbr(p_texto text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.parse_valor_ptbr(p_texto text) TO service_role;

-- ── public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_os record;
  v_fone text;
  v_teste boolean;
  v_fone_teste text;
  v_destino text;
  v_nome text;
  v_quando text;
  v_msg text;
begin
  if v_autor is not null and not exists (
    select 1 from public.app_users u where u.id = v_autor and u.active and u.role in ('admin', 'financial', 'seller')) then
    raise exception 'Sem permissão para falar com o cliente pelo WhatsApp.' using errcode = '42501';
  end if;

  select s.id, s.service_order_number, s.status, s.scheduled_start_at,
         c.name as cliente, c.phone, c.whatsapp, c.opt_out_whatsapp, v.name as barco
    into v_os
    from public.service_orders s
    left join public.clients c on c.id = s.client_id
    left join public.vessels v on v.id = s.vessel_id
   where s.id = p_os;
  if v_os.id is null then raise exception 'OS não encontrada.'; end if;
  if v_os.status <> 'scheduled' or v_os.scheduled_start_at is null then
    raise exception 'A OS % não está agendada.', v_os.service_order_number;
  end if;
  if v_os.scheduled_start_at < now() then
    raise exception 'O atendimento da OS % já passou.', v_os.service_order_number;
  end if;
  if coalesce(v_os.opt_out_whatsapp, false) then
    raise exception 'Este cliente pediu para não receber WhatsApp: confirme por telefone.';
  end if;
  v_fone := regexp_replace(coalesce(nullif(v_os.whatsapp, ''), v_os.phone, ''), '\D', '', 'g');
  if length(v_fone) < 10 then raise exception 'Cliente sem telefone cadastrado.'; end if;
  if length(v_fone) in (10, 11) then v_fone := '55' || v_fone; end if;

  v_teste := coalesce((select value::text from public.app_settings where key = 'wa_test_mode'), 'false') in ('true', '"true"');
  v_fone_teste := regexp_replace(coalesce((select value::text from public.app_settings where key = 'wa_test_number'), ''), '\D', '', 'g');
  if v_teste and v_fone_teste = '' then raise exception 'Modo de teste ligado sem número de teste configurado.'; end if;
  v_destino := case when v_teste then v_fone_teste else v_fone end;

  v_nome := coalesce(nullif(split_part(btrim(coalesce(v_os.cliente, '')), ' ', 1), ''), '');
  v_quando := (array['domingo','segunda','terça','quarta','quinta','sexta','sábado'])[extract(dow from v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::int + 1]
    || ' (' || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM') || ') às '
    || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'HH24"h"MI');
  v_msg := 'Olá' || case when v_nome <> '' then ', ' || initcap(v_nome) else '' end || '! Aqui é da HBR Marine. '
    || 'Confirmando o atendimento' || coalesce(' no ' || nullif(v_os.barco, ''), '') || ' ' || v_quando || '. '
    || 'Pode responder SIM para confirmar? Se precisar remarcar, é só avisar por aqui. 👍';

  insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority)
  values (v_destino, v_msg, 'agenda-confirmacao', v_os.id, 3);

  update public.service_orders
     set client_confirmation_requested_at = now(), client_confirmed_at = null, client_confirmed_for = null
   where id = v_os.id;

  return jsonb_build_object('ok', true, 'teste', v_teste, 'mensagem', v_msg,
    'message', case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    else 'Pedido de confirmação enviado a ' || coalesce(v_os.cliente, 'o cliente') || '. Quando ele responder SIM, a OS fica confirmada.' end);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid) TO service_role;

-- ── public.periodo_esta_fechado(p_data date) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.periodo_esta_fechado(p_data date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.periodos_fechados
     WHERE ano = EXTRACT(YEAR FROM p_data)::int
       AND mes = EXTRACT(MONTH FROM p_data)::int
       AND reaberto_em IS NULL
  );
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.periodo_esta_fechado(p_data date) TO postgres;
GRANT EXECUTE ON FUNCTION public.periodo_esta_fechado(p_data date) TO service_role;

-- ── public.pode_ver_folha(_user_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.pode_ver_folha(_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.app_users u
    where u.id = _user_id and u.active and u.role in ('admin','financial')
  );
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.pode_ver_folha(_user_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.pode_ver_folha(_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pode_ver_folha(_user_id uuid) TO service_role;

-- ── public.preview_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb) ── SECURITY DEFINER [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.preview_nfe_import(p_note_id uuid, p_supplier_id uuid DEFAULT NULL::uuid, p_manual_mappings jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_items   jsonb;
  v_status  text;
  v_total   numeric;
  v_prod    numeric;
  v_ipi     numeric;
  v_desc    numeric;
  v_frete   numeric;
  v_seg     numeric;
  v_outro   numeric;
  v_item    RECORD;
  v_match   RECORD;
  v_manual  uuid;
  v_forcar  boolean;
  v_reason  text;
  v_pid     uuid;
  v_pname   text;
  v_psku    text;
  v_punit   text;
  v_pncm    text;
  v_pcost   numeric;
  v_pstock  numeric;
  v_out     jsonb := '[]'::jsonb;
  v_soma    numeric := 0;
  v_esperado numeric;
BEGIN
  SELECT items, status, total_amount,
         total_products, tax_ipi, total_discount, total_freight, total_insurance, total_other
    INTO v_items, v_status, v_total,
         v_prod, v_ipi, v_desc, v_frete, v_seg, v_outro
    FROM fiscal_notes WHERE id = p_note_id;
  IF v_items IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, sku_supplier text, description text, ncm text, unit text,
    quantity numeric, unit_price numeric, total_price numeric, barcode text
  ) LOOP
    v_manual := NULL; v_forcar := false;
    SELECT (val->>'internal_product_id')::uuid, coalesce((val->>'force_new')::boolean, false)
      INTO v_manual, v_forcar
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
      LIMIT 1;

    IF v_forcar THEN
      v_pid := NULL; v_reason := 'novo';
    ELSE
      SELECT * INTO v_match FROM match_nfe_item(
        p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);
      v_pid := v_match.product_id; v_reason := v_match.match_reason;
    END IF;

    v_pname := NULL; v_psku := NULL; v_punit := NULL;
    v_pncm := NULL; v_pcost := NULL; v_pstock := NULL;
    IF v_pid IS NOT NULL THEN
      SELECT name, sku, unit, ncm, cost_price, stock_quantity
        INTO v_pname, v_psku, v_punit, v_pncm, v_pcost, v_pstock
        FROM products WHERE id = v_pid;
    END IF;

    v_soma := v_soma + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);

    v_out := v_out || jsonb_build_object(
      'index',         v_item.index,
      'sku_supplier',  v_item.sku_supplier,
      'description',   v_item.description,
      'barcode',       v_item.barcode,
      'quantity',      v_item.quantity,
      'unit_price',    v_item.unit_price,
      'total_price',   v_item.total_price,
      'match_reason',  v_reason,
      'product_id',    v_pid,
      'product_name',  v_pname,
      'product_sku',   v_psku,
      'product_unit',  v_punit,
      'product_ncm',   v_pncm,
      'current_cost',  v_pcost,
      'current_stock', v_pstock,
      'cost_changed',  (v_pcost IS NOT NULL
                         AND round(v_pcost, 2) <> round(coalesce(v_item.unit_price, 0), 2)),
      'unit_changed',  (v_punit IS NOT NULL AND coalesce(v_item.unit, '') <> ''
                         AND upper(btrim(v_punit)) <> upper(btrim(v_item.unit))),
      'ncm_changed',   (coalesce(v_pncm, '') <> '' AND coalesce(v_item.ncm, '') <> ''
                         AND regexp_replace(v_pncm, '\D', '', 'g')
                             <> regexp_replace(v_item.ncm, '\D', '', 'g'))
    );
  END LOOP;

  v_esperado := round(v_soma, 2)
              + coalesce(v_ipi, 0) + coalesce(v_frete, 0)
              + coalesce(v_seg, 0) + coalesce(v_outro, 0)
              - coalesce(v_desc, 0);

  RETURN jsonb_build_object(
    'status',        v_status,
    'already_done',  (v_status <> 'pending'),
    'items',         v_out,
    'items_sum',     round(v_soma, 2),
    'note_total',    round(coalesce(v_total, 0), 2),
    'total_products', v_prod,
    'total_ipi',      coalesce(v_ipi, 0),
    'total_discount', coalesce(v_desc, 0),
    'total_freight',  coalesce(v_frete, 0),
    'total_insurance', coalesce(v_seg, 0),
    'total_other',    coalesce(v_outro, 0),
    'expected_total', round(v_esperado, 2),
    'total_matches', (abs(round(v_esperado, 2) - round(coalesce(v_total, 0), 2)) <= 0.01)
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.preview_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.preview_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb) TO service_role;

-- ── public.previous_survey_answers(p_vessel_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.previous_survey_answers(p_vessel_id uuid)
 RETURNS TABLE(template_id uuid, question text, answer text, answered_at timestamp with time zone, service_order_number text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- distinct on (template_id) + order by answered_at desc = a resposta MAIS
  -- RECENTE de cada pergunta. Respostas antigas do mesmo item ficam de fora:
  -- oferecer três versões da mesma coisa transferiria a decisão para quem só
  -- queria uma dica.
  select distinct on (a.template_id)
    a.template_id,
    a.question_snapshot,
    a.answer_value,
    a.answered_at,
    so.service_order_number
  from public.service_survey_answers a
  join public.service_surveys s on s.id = a.survey_id
  left join public.service_orders so on so.id = s.service_order_id
  where s.vessel_id = p_vessel_id
    and s.status = 'closed'
    and a.template_id is not null
    and a.answer_value is not null
    and a.skipped_reason is null
  order by a.template_id, a.answered_at desc nulls last;
$function$
;
COMMENT ON FUNCTION public.previous_survey_answers(p_vessel_id uuid) IS 'Última resposta de cada pergunta já levantada NESTE ativo, de levantamentos
   fechados. Serve para não perguntar de novo o que não muda — com a data à
   vista, porque quem decide se ainda vale é quem está no local.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.previous_survey_answers(p_vessel_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.previous_survey_answers(p_vessel_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.previous_survey_answers(p_vessel_id uuid) TO service_role;

-- ── public.produce_composed_product(p_parent uuid, p_qty numeric) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.produce_composed_product(p_parent uuid, p_qty numeric DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_type text;
  r record;
  v_falta jsonb := '[]'::jsonb;
  v_consumido jsonb := '[]'::jsonb;
begin
  if p_qty is null or p_qty <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Quantidade deve ser maior que zero.');
  end if;

  select product_type into v_type from products where id = p_parent;
  if v_type is null then
    return jsonb_build_object('ok', false, 'error', 'Produto não encontrado.');
  end if;
  if v_type not in ('composto', 'kit') then
    return jsonb_build_object('ok', false, 'error', 'Produto não é composto/kit — não tem receita para produzir.');
  end if;
  if not exists (select 1 from product_components where parent_product_id = p_parent) then
    return jsonb_build_object('ok', false, 'error', 'Produto composto sem componentes cadastrados.');
  end if;

  -- 1) Checa disponibilidade de TODOS os componentes (disponível = físico − reservado).
  for r in
    select pc.component_product_id, pc.quantity as need_per, c.name,
           c.stock_quantity, coalesce(c.reserved_quantity, 0) as reserved
    from product_components pc
    join products c on c.id = pc.component_product_id
    where pc.parent_product_id = p_parent
  loop
    if (r.stock_quantity - r.reserved) < (r.need_per * p_qty) then
      v_falta := v_falta || jsonb_build_object(
        'produto', r.name, 'necessario', r.need_per * p_qty, 'disponivel', r.stock_quantity - r.reserved);
    end if;
  end loop;
  if jsonb_array_length(v_falta) > 0 then
    return jsonb_build_object('ok', false, 'error', 'Estoque insuficiente de componentes.', 'faltantes', v_falta);
  end if;

  -- 2) Consome os componentes + registra o movimento.
  for r in
    select pc.component_product_id, pc.quantity as need_per, c.name, c.cost_price
    from product_components pc
    join products c on c.id = pc.component_product_id
    where pc.parent_product_id = p_parent
  loop
    insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, unit_cost_snapshot, notes)
      values (r.component_product_id, 'manual_remove_stock', -(r.need_per * p_qty), 'production', r.cost_price,
              'Consumo em produção de composto/kit');
    v_consumido := v_consumido || jsonb_build_object('produto', r.name, 'consumido', r.need_per * p_qty);
  end loop;

  -- 3) Credita o produto acabado.
  insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, notes)
    values (p_parent, 'manual_add_stock', p_qty, 'production', 'Produção de composto/kit');

  return jsonb_build_object(
    'ok', true, 'produzido', p_qty, 'consumidos', v_consumido,
    'novo_estoque_pai', (select coalesce(sum(quantity_delta), 0) from inventory_movements where product_id = p_parent));
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.produce_composed_product(p_parent uuid, p_qty numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.produce_composed_product(p_parent uuid, p_qty numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.produce_composed_product(p_parent uuid, p_qty numeric) TO service_role;

-- ── public.prune_app_error_logs(p_days integer) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.prune_app_error_logs(p_days integer DEFAULT 90)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n int;
BEGIN
  DELETE FROM app_error_logs WHERE last_seen_at < now() - (p_days || ' days')::interval;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.prune_app_error_logs(p_days integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.prune_app_error_logs(p_days integer) TO service_role;

-- ── public.raiz_do_cnpj_da_empresa() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.raiz_do_cnpj_da_empresa()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select nullif(left(regexp_replace(coalesce((select cnpj from public.company_fiscal_settings limit 1), ''), '\D', '', 'g'), 8), '');
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.raiz_do_cnpj_da_empresa() TO postgres;
GRANT EXECUTE ON FUNCTION public.raiz_do_cnpj_da_empresa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.raiz_do_cnpj_da_empresa() TO service_role;

-- ── public.recalc_po_total(p_po_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.recalc_po_total(p_po_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE purchase_orders
  SET total_amount = (
    SELECT COALESCE(SUM(quantity * unit_cost), 0)
    FROM purchase_order_items
    WHERE purchase_order_id = p_po_id
  )
  WHERE id = p_po_id;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.recalc_po_total(p_po_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.recalc_po_total(p_po_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalc_po_total(p_po_id uuid) TO service_role;

-- ── public.recalc_so_totals(so_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.recalc_so_totals(so_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
  r record;
begin
  select status into v_status from service_orders where id = so_id;
  if not found or v_status = 'cancelled' then
    return;
  end if;

  select * into r from public.calc_so_totals(so_id);
  if r.grand_total is null then return; end if;

  update service_orders
  set labor_cost_total  = r.labor_cost_total,
      parts_cost_total  = r.parts_cost_total,
      labor_hours_total = r.labor_hours_total,
      card_fee_amount   = r.card_fee_amount,
      grand_total       = r.grand_total
  where id = so_id;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.recalc_so_totals(so_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.recalc_so_totals(so_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalc_so_totals(so_id uuid) TO service_role;

-- ── public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer DEFAULT 30)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_item        jsonb;
  v_poi         record;
  v_new_rcv     numeric;
  v_po          record;
  v_all_done    boolean := true;
  v_any_done    boolean := false;
  v_new_status  text;
  v_payable_id  uuid;
  v_total       numeric;
BEGIN
  -- Process each item
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    SELECT * INTO v_poi
      FROM public.purchase_order_items
     WHERE id = (v_item->>'po_item_id')::uuid
       FOR UPDATE;

    IF NOT FOUND THEN CONTINUE; END IF;

    v_new_rcv := COALESCE(v_poi.received_qty, 0) + (v_item->>'received_qty')::numeric;
    v_new_rcv := LEAST(v_new_rcv, v_poi.quantity); -- cap at ordered qty

    -- Update received_qty on item
    UPDATE public.purchase_order_items
       SET received_qty = v_new_rcv
     WHERE id = v_poi.id;

    -- O saldo sobe pelo movimento abaixo (fase E); aqui só a data da última entrada.
    UPDATE public.products
       SET last_stock_entry_at = NOW()
     WHERE id = v_poi.product_id;

    -- Inventory movement
    INSERT INTO public.inventory_movements
      (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
    VALUES
      (v_poi.product_id, 'purchase', (v_item->>'received_qty')::numeric,
       'purchase_order', p_po_id, v_poi.unit_cost);

    v_any_done := true;
    IF v_new_rcv < v_poi.quantity THEN v_all_done := false; END IF;
  END LOOP;

  -- Determine new PO status
  SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id;
  -- Check if ALL items across the entire PO are fully received
  SELECT bool_and(received_qty >= quantity)
    INTO v_all_done
    FROM public.purchase_order_items
   WHERE purchase_order_id = p_po_id;

  v_new_status := CASE
    WHEN v_all_done THEN 'received'
    WHEN v_any_done THEN 'partial'
    ELSE v_po.status
  END;

  -- Create payable when fully received and no payable yet
  IF v_new_status = 'received' AND v_po.payable_id IS NULL AND v_po.supplier_id IS NOT NULL THEN
    SELECT COALESCE(SUM(received_qty * unit_cost), 0)
      INTO v_total
      FROM public.purchase_order_items
     WHERE purchase_order_id = p_po_id;

    INSERT INTO public.payables
      (supplier_id, description, amount, balance_amount, paid_amount,
       issue_date, due_date, status, origin)
    VALUES
      (v_po.supplier_id,
       'Recebimento ' || v_po.po_number,
       v_total, v_total, 0,
       CURRENT_DATE, CURRENT_DATE + p_due_days,
       'pending', 'purchase_order')
    RETURNING id INTO v_payable_id;

    UPDATE public.purchase_orders
       SET status     = v_new_status,
           payable_id = v_payable_id,
           received_date = CURRENT_DATE
     WHERE id = p_po_id;
  ELSE
    UPDATE public.purchase_orders
       SET status = v_new_status,
           received_date = CASE WHEN v_new_status = 'received' THEN CURRENT_DATE ELSE received_date END
     WHERE id = p_po_id;
  END IF;

  RETURN json_build_object(
    'status',      v_new_status,
    'payable_id',  v_payable_id,
    'all_received', v_all_done
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer) TO service_role;

-- ── public.recompute_product_cost(_parent uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.recompute_product_cost(_parent uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  total numeric;
begin
  select coalesce(sum(pc.quantity * coalesce(c.cost_price, 0)), 0)
    into total
  from public.product_components pc
  join public.products c on c.id = pc.component_product_id
  where pc.parent_product_id = _parent;

  update public.products
     set cost_price = total
   where id = _parent
     and product_type in ('kit', 'composto');
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.recompute_product_cost(_parent uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.recompute_product_cost(_parent uuid) TO service_role;

-- ── public.recompute_product_reservations(_product uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.recompute_product_reservations(_product uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.products p
     set reserved_quantity = coalesce((
       select sum(sop.quantity)
       from public.service_order_parts sop
       join public.service_orders so on so.id = sop.service_order_id
       where sop.product_id = p.id
         and so.status in ('approved','scheduled','in_progress','awaiting_parts','awaiting_client','reopened')
     ), 0)
   where p.id = _product;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.recompute_product_reservations(_product uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.recompute_product_reservations(_product uuid) TO service_role;

-- ── public.reconcile_stock_to_v2() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.reconcile_stock_to_v2()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  raise exception 'Migração única para o modelo v2, já feita. O saldo agora só muda por movimento (fase E, 30/09/2026).';
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.reconcile_stock_to_v2() TO postgres;
GRANT EXECUTE ON FUNCTION public.reconcile_stock_to_v2() TO service_role;

-- ── public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text DEFAULT NULL::text, p_service_order_id uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_priority text DEFAULT 'normal'::text, p_evidence text DEFAULT NULL::text, p_evidence_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source_message_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(loop_id uuid, criado boolean)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_new boolean;
BEGIN
  INSERT INTO entity_open_loops (
    entity_type, entity_id, loop_key, source, kind, title, detail,
    service_order_id, due_at, priority, evidence, evidence_at, source_message_id, last_seen_at
  )
  VALUES (
    p_entity_type, p_entity_id, p_loop_key, 'conversation', p_kind, p_title, p_detail,
    p_service_order_id, p_due_at, coalesce(p_priority, 'normal'),
    p_evidence, p_evidence_at, p_source_message_id, now()
  )
  ON CONFLICT (entity_type, entity_id, loop_key) WHERE status = 'open'
  DO UPDATE SET
    mentions          = entity_open_loops.mentions + 1,
    last_seen_at      = now(),
    evidence          = coalesce(EXCLUDED.evidence, entity_open_loops.evidence),
    evidence_at       = coalesce(EXCLUDED.evidence_at, entity_open_loops.evidence_at),
    source_message_id = coalesce(EXCLUDED.source_message_id, entity_open_loops.source_message_id),
    due_at            = coalesce(EXCLUDED.due_at, entity_open_loops.due_at),
    service_order_id  = coalesce(EXCLUDED.service_order_id, entity_open_loops.service_order_id),
    updated_at        = now()
  RETURNING id, (xmax = 0) INTO v_id, v_new;

  RETURN QUERY SELECT v_id, v_new;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) TO service_role;

-- ── public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid, p_direction text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text DEFAULT NULL::text, p_service_order_id uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_priority text DEFAULT 'normal'::text, p_evidence text DEFAULT NULL::text, p_evidence_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source_message_id uuid DEFAULT NULL::uuid, p_direction text DEFAULT 'ours'::text)
 RETURNS TABLE(loop_id uuid, criado boolean)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_new boolean;
BEGIN
  INSERT INTO entity_open_loops (
    entity_type, entity_id, loop_key, source, kind, title, detail,
    service_order_id, due_at, priority, evidence, evidence_at, source_message_id,
    direction, last_seen_at
  )
  VALUES (
    p_entity_type, p_entity_id, p_loop_key, 'conversation', p_kind, p_title, p_detail,
    p_service_order_id, p_due_at, coalesce(p_priority, 'normal'),
    p_evidence, p_evidence_at, p_source_message_id,
    case when p_direction in ('ours','theirs') then p_direction else 'ours' end,
    now()
  )
  ON CONFLICT (entity_type, entity_id, loop_key) WHERE status = 'open'
  DO UPDATE SET
    mentions          = entity_open_loops.mentions + 1,
    last_seen_at      = now(),
    evidence          = coalesce(EXCLUDED.evidence, entity_open_loops.evidence),
    evidence_at       = coalesce(EXCLUDED.evidence_at, entity_open_loops.evidence_at),
    source_message_id = coalesce(EXCLUDED.source_message_id, entity_open_loops.source_message_id),
    due_at            = coalesce(EXCLUDED.due_at, entity_open_loops.due_at),
    service_order_id  = coalesce(EXCLUDED.service_order_id, entity_open_loops.service_order_id),
    updated_at        = now()
  RETURNING id, (xmax = 0) INTO v_id, v_new;

  RETURN QUERY SELECT v_id, v_new;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid, p_direction text) TO postgres;
GRANT EXECUTE ON FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid, p_direction text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_conversation_loop(p_entity_type text, p_entity_id uuid, p_loop_key text, p_kind text, p_title text, p_detail text, p_service_order_id uuid, p_due_at timestamp with time zone, p_priority text, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid, p_direction text) TO service_role;

-- ── public.refresh_entity_open_loops() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.refresh_entity_open_loops()
 RETURNS TABLE(abertos integer, fechados integer)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_open integer := 0;
  v_closed integer := 0;
  v_n integer := 0;
BEGIN
  WITH ins AS (
    INSERT INTO entity_open_loops (
      entity_type, entity_id, loop_key, source, kind, title, detail,
      ref_table, ref_id, service_order_id, due_at, priority, last_seen_at
    )
    SELECT f.entity_type, f.entity_id, f.loop_key, 'erp', f.kind, f.title, f.detail,
           f.ref_table, f.ref_id, f.service_order_id, f.due_at, f.priority, now()
      FROM erp_open_loop_facts f
    ON CONFLICT (entity_type, entity_id, loop_key) WHERE status = 'open'
    DO UPDATE SET
      title            = EXCLUDED.title,
      detail           = EXCLUDED.detail,
      due_at           = EXCLUDED.due_at,
      priority         = EXCLUDED.priority,
      service_order_id = EXCLUDED.service_order_id,
      last_seen_at     = now(),
      updated_at       = now()
    RETURNING (xmax = 0) AS inserido
  )
  SELECT count(*) FILTER (WHERE inserido)::integer INTO v_open FROM ins;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'erp:fato encerrado', updated_at = now()
   WHERE l.source = 'erp' AND l.status = 'open'
     AND NOT EXISTS (
       SELECT 1 FROM erp_open_loop_facts f
        WHERE f.entity_type = l.entity_type AND f.entity_id = l.entity_id
          AND f.loop_key = l.loop_key);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'tarefa concluída', updated_at = now()
    FROM agenda_tasks t
   WHERE l.task_id = t.id AND l.source = 'conversation' AND l.status = 'open'
     AND t.status IN ('done', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'tarefa concluída', updated_at = now()
    FROM agenda_suggestions s
    JOIN agenda_tasks t ON t.id = s.created_task_id
   WHERE s.open_loop_id = l.id AND l.source = 'conversation' AND l.status = 'open'
     AND t.status IN ('done', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'OS encerrada', updated_at = now()
    FROM service_orders so
   WHERE l.service_order_id = so.id AND l.source = 'conversation' AND l.status = 'open'
     AND so.status IN ('completed', 'invoiced', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'expirado por inatividade', updated_at = now()
   WHERE l.source = 'conversation' AND l.status = 'open'
     AND l.last_seen_at < now() - interval '45 days';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  RETURN QUERY SELECT v_open, v_closed;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.refresh_entity_open_loops() TO postgres;
GRANT EXECUTE ON FUNCTION public.refresh_entity_open_loops() TO authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_entity_open_loops() TO service_role;

-- ── public.register_deposit_and_convert(p_service_order_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_card_fee_percent numeric, p_notes text, p_balance_installments jsonb, p_create_collections boolean) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.register_deposit_and_convert(p_service_order_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_card_fee_percent numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_balance_installments jsonb DEFAULT NULL::jsonb, p_create_collections boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_receivable_id UUID;
  v_payment_id    UUID;
  v_net_amount    NUMERIC;
  v_so_number     TEXT;
  v_client_id     UUID;
  v_client_name   TEXT;
  v_client_phone  TEXT;
  v_client_wa     TEXT;
  v_inst          JSONB;
  v_bal_id        UUID;
  v_bal_count     INT := 0;
  v_existing_bal  INT;
BEGIN
  -- Técnico não registra sinal nem converte orçamento (chamada sem usuário = sistema).
  IF auth.uid() IS NOT NULL AND EXISTS (SELECT 1 FROM public.app_users WHERE id = auth.uid() AND role = 'technician') THEN
    RAISE EXCEPTION 'Técnico não registra sinal nem converte orçamento.' USING ERRCODE = '42501';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Valor do sinal deve ser maior que zero';
  END IF;

  SELECT so.service_order_number, so.client_id, c.name, c.phone, c.whatsapp
  INTO v_so_number, v_client_id, v_client_name, v_client_phone, v_client_wa
  FROM public.service_orders so
  LEFT JOIN public.clients c ON c.id = so.client_id
  WHERE so.id = p_service_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordem de serviço não encontrada: %', p_service_order_id;
  END IF;

  v_net_amount := p_amount - (p_amount * COALESCE(p_card_fee_percent, 0) / 100.0);

  INSERT INTO public.receivables (
    service_order_id, client_id, description, issue_date, due_date,
    amount, balance_amount, paid_amount, status, is_deposit
  ) VALUES (
    p_service_order_id, v_client_id, 'Sinal — ' || COALESCE(v_so_number, ''),
    p_payment_date, p_payment_date, p_amount, 0, p_amount, 'paid', true
  ) RETURNING id INTO v_receivable_id;

  INSERT INTO public.payments (
    receivable_id, amount, payment_date, payment_method,
    card_fee_percent, net_amount, notes, status
  ) VALUES (
    v_receivable_id, p_amount, p_payment_date, p_payment_method,
    COALESCE(p_card_fee_percent, 0), v_net_amount, p_notes, 'confirmed'
  ) RETURNING id INTO v_payment_id;

  SELECT COUNT(*) INTO v_existing_bal
  FROM public.receivables
  WHERE service_order_id = p_service_order_id AND NOT is_deposit AND status <> 'cancelled';

  IF v_existing_bal = 0
     AND p_balance_installments IS NOT NULL
     AND jsonb_typeof(p_balance_installments) = 'array' THEN
    FOR v_inst IN SELECT * FROM jsonb_array_elements(p_balance_installments) LOOP
      IF COALESCE((v_inst->>'amount')::numeric, 0) > 0 THEN
        INSERT INTO public.receivables (
          service_order_id, client_id, description, issue_date, due_date,
          amount, balance_amount, paid_amount, status, is_deposit, reminder_sent_at, due_on_completion
        ) VALUES (
          p_service_order_id, v_client_id,
          COALESCE(v_inst->>'description', 'Saldo — ' || COALESCE(v_so_number, '')),
          p_payment_date, (v_inst->>'due_date')::date,
          (v_inst->>'amount')::numeric, (v_inst->>'amount')::numeric, 0, 'pending', false,
          now(), COALESCE((v_inst->>'due_on_completion')::boolean, false)
        ) RETURNING id INTO v_bal_id;
        v_bal_count := v_bal_count + 1;

        IF p_create_collections THEN
          INSERT INTO public.collections (
            service_order_id, receivable_id, client_id, amount, due_date, status,
            description, contact_name, phone, contact_whatsapp, auto_rule_enabled
          ) VALUES (
            p_service_order_id, v_bal_id, v_client_id, (v_inst->>'amount')::numeric,
            (v_inst->>'due_date')::date, 'pending',
            COALESCE(v_inst->>'description', 'Saldo'), v_client_name, v_client_phone, v_client_wa, false
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  UPDATE public.service_orders
  SET
    status = CASE WHEN status = 'draft' THEN 'open' ELSE status END,
    converted_to_os_at = CASE WHEN status = 'draft' AND converted_to_os_at IS NULL THEN NOW() ELSE converted_to_os_at END,
    service_order_number = CASE
      WHEN status = 'draft' AND service_order_number LIKE 'ORÇ-%'
        THEN REPLACE(service_order_number, 'ORÇ-', 'OS-')
      ELSE service_order_number
    END
  WHERE id = p_service_order_id;

  RETURN json_build_object(
    'receivable_id',       v_receivable_id,
    'payment_id',          v_payment_id,
    'net_amount',          v_net_amount,
    'balance_receivables', v_bal_count
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.register_deposit_and_convert(p_service_order_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_card_fee_percent numeric, p_notes text, p_balance_installments jsonb, p_create_collections boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.register_deposit_and_convert(p_service_order_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_card_fee_percent numeric, p_notes text, p_balance_installments jsonb, p_create_collections boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_deposit_and_convert(p_service_order_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_card_fee_percent numeric, p_notes text, p_balance_installments jsonb, p_create_collections boolean) TO service_role;

-- ── public.register_payment_and_update_balance(p_receivable_id uuid, p_payable_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_installments integer, p_card_fee_percent numeric, p_net_amount numeric, p_notes text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.register_payment_and_update_balance(p_receivable_id uuid, p_payable_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_installments integer, p_card_fee_percent numeric, p_net_amount numeric, p_notes text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_payment_id      UUID;
  v_total_paid      NUMERIC;
  v_original_amount NUMERIC;
  v_new_balance     NUMERIC;
  v_new_status      TEXT;
  v_table_name      TEXT;
  v_parent_id       UUID;
BEGIN
  -- Autorização: apenas admin ou financial
  IF NOT public.is_admin_or_financial(auth.uid()) THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores e financeiro podem registrar pagamentos';
  END IF;

  -- Validação de valor positivo
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'O valor do pagamento deve ser maior que zero (recebido: %)', p_amount;
  END IF;

  IF p_card_fee_percent IS NOT NULL AND (p_card_fee_percent < 0 OR p_card_fee_percent > 100) THEN
    RAISE EXCEPTION 'Percentual de taxa de cartão inválido: %', p_card_fee_percent;
  END IF;

  INSERT INTO public.payments (
    receivable_id, payable_id, amount, payment_date, payment_method,
    installments, card_fee_percent, net_amount, notes, status
  ) VALUES (
    p_receivable_id, p_payable_id, p_amount, p_payment_date, p_payment_method,
    p_installments, p_card_fee_percent, p_net_amount, p_notes, 'confirmed'
  ) RETURNING id INTO v_payment_id;

  IF p_receivable_id IS NOT NULL THEN
    v_table_name := 'receivables';
    v_parent_id  := p_receivable_id;
  ELSIF p_payable_id IS NOT NULL THEN
    v_table_name := 'payables';
    v_parent_id  := p_payable_id;
  ELSE
    RAISE EXCEPTION 'Deve fornecer receivable_id ou payable_id';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM public.payments
  WHERE (receivable_id = p_receivable_id OR payable_id = p_payable_id)
    AND status = 'confirmed';

  IF v_table_name = 'receivables' THEN
    SELECT amount INTO v_original_amount FROM public.receivables WHERE id = v_parent_id FOR UPDATE;
  ELSE
    SELECT amount INTO v_original_amount FROM public.payables WHERE id = v_parent_id FOR UPDATE;
  END IF;

  v_new_balance := GREATEST(0, v_original_amount - v_total_paid);

  IF v_total_paid >= v_original_amount THEN
    v_new_status := 'paid';
  ELSIF v_total_paid > 0 THEN
    v_new_status := 'partially_paid';
  ELSE
    v_new_status := 'pending';
  END IF;

  IF v_table_name = 'receivables' THEN
    UPDATE public.receivables SET paid_amount=v_total_paid, balance_amount=v_new_balance, status=v_new_status WHERE id=v_parent_id;
  ELSE
    UPDATE public.payables SET paid_amount=v_total_paid, balance_amount=v_new_balance, status=v_new_status WHERE id=v_parent_id;
  END IF;

  RETURN json_build_object('payment_id',v_payment_id,'total_paid',v_total_paid,'balance_amount',v_new_balance,'status',v_new_status);
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.register_payment_and_update_balance(p_receivable_id uuid, p_payable_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_installments integer, p_card_fee_percent numeric, p_net_amount numeric, p_notes text) TO postgres;
GRANT EXECUTE ON FUNCTION public.register_payment_and_update_balance(p_receivable_id uuid, p_payable_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_installments integer, p_card_fee_percent numeric, p_net_amount numeric, p_notes text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_payment_and_update_balance(p_receivable_id uuid, p_payable_id uuid, p_amount numeric, p_payment_date date, p_payment_method text, p_installments integer, p_card_fee_percent numeric, p_net_amount numeric, p_notes text) TO service_role;

-- ── public.registrar_confirmacao_do_cliente(p_phone text, p_body text, p_message_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.registrar_confirmacao_do_cliente(p_phone text, p_body text, p_message_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_os record;
  v_n int;
  v_quando text;
begin
  if length(v_fone) < 8 or not public._e_concordancia(p_body) then
    return jsonb_build_object('confirmou', false);
  end if;

  -- OS agendada, com pedido de confirmação nas últimas 72 h e ainda sem resposta, deste cliente.
  select count(*) into v_n
    from public.service_orders s join public.clients c on c.id = s.client_id
   where s.status = 'scheduled' and s.scheduled_start_at > now() - interval '2 hours'
     and s.client_confirmation_requested_at > now() - interval '72 hours'
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);
  if v_n = 0 then return jsonb_build_object('confirmou', false); end if;

  if v_n > 1 then
    -- Duas OS esperando: "sim" não diz qual. Avisa o dono em vez de adivinhar.
    insert into public.app_notifications (user_id, type, title, body, navigate_to)
    select u.id, 'agendamento_confirmado', 'Cliente respondeu SIM, mas há ' || v_n || ' OS esperando confirmação',
           'Confira com o cliente qual atendimento ele confirmou.', '/agenda'
      from public.app_users u where u.role = 'admin' and u.active;
    return jsonb_build_object('confirmou', false, 'ambigua', v_n);
  end if;

  select s.id, s.service_order_number, s.scheduled_start_at, c.name as cliente into v_os
    from public.service_orders s join public.clients c on c.id = s.client_id
   where s.status = 'scheduled' and s.scheduled_start_at > now() - interval '2 hours'
     and s.client_confirmation_requested_at > now() - interval '72 hours'
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);

  update public.service_orders
     set client_confirmed_at = now(), client_confirmed_for = v_os.scheduled_start_at
   where id = v_os.id;

  v_quando := to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24"h"MI');
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'agendamento_confirmado', coalesce(v_os.cliente, 'Cliente') || ' confirmou o atendimento',
         'OS ' || v_os.service_order_number || ', ' || v_quando || ' — respondeu "' || left(btrim(p_body), 40) || '" pelo WhatsApp.',
         '/v2/service-orders/' || v_os.id
    from public.app_users u where u.role = 'admin' and u.active;

  return jsonb_build_object('confirmou', true, 'os', v_os.service_order_number);
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.registrar_confirmacao_do_cliente(p_phone text, p_body text, p_message_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.registrar_confirmacao_do_cliente(p_phone text, p_body text, p_message_id uuid) TO service_role;

-- ── public.registrar_diaria(p_favorecido_id uuid, p_data date, p_jornada text, p_os_ids uuid[], p_observacao text, p_extras numeric, p_descontos numeric, p_valor_diaria numeric, p_origem text, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.registrar_diaria(p_favorecido_id uuid, p_data date, p_jornada text, p_os_ids uuid[] DEFAULT NULL::uuid[], p_observacao text DEFAULT NULL::text, p_extras numeric DEFAULT NULL::numeric, p_descontos numeric DEFAULT NULL::numeric, p_valor_diaria numeric DEFAULT NULL::numeric, p_origem text DEFAULT 'painel'::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_antes record;
  v_depois record;
  v_fracao numeric;
  v_tipo text;
  v_id uuid;
  v_acao text;
  v_os_antes text[];
  v_os_depois text[];
  v_resumo text;
begin
  if v_autor is null then raise exception 'Diga quem está registrando a diária.'; end if;
  if p_data is null then raise exception 'Informe a data do dia trabalhado.'; end if;
  if p_data > public._hoje_brt() then raise exception 'Data no futuro (%): registre a diária no dia trabalhado ou depois.', to_char(p_data, 'DD/MM/YYYY'); end if;
  v_fracao := case lower(btrim(coalesce(p_jornada, ''))) when 'inteiro' then 1 when 'meio' then 0.5 when 'faltou' then 0 end;
  if v_fracao is null then raise exception 'Jornada inválida: "%". Use inteiro, meio ou faltou.', p_jornada; end if;
  v_tipo := case when v_fracao = 0 then 'falta' else 'diaria' end;
  if coalesce(p_origem, '') not in ('whatsapp', 'painel', 'agente', 'importado') then raise exception 'Origem inválida: %.', p_origem; end if;
  if coalesce(p_extras, 0) < 0 or coalesce(p_descontos, 0) < 0 then raise exception 'Extras e descontos não podem ser negativos.'; end if;
  if p_valor_diaria is not null and p_valor_diaria <= 0 then raise exception 'O valor da diária precisa ser maior que zero.'; end if;

  select id, name into v_fav from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  -- O perfil vigente NA DATA do dia (não o de hoje): a diária de agosto é a de agosto.
  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= p_data and (vigencia_fim is null or vigencia_fim >= p_data)
   order by vigencia_inicio desc limit 1;
  if v_perfil.id is null then
    raise exception '% não tem diária cadastrada em %: cadastre o valor da diária antes.', v_fav.name, to_char(p_data, 'DD/MM/YYYY');
  end if;

  if p_os_ids is not null and exists (
       select 1 from unnest(p_os_ids) o(id) where not exists (select 1 from public.service_orders so where so.id = o.id)) then
    raise exception 'Uma das OS informadas não existe.';
  end if;

  select ws.* into v_antes
    from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = p_favorecido_id and ws.data = p_data and ws.fracao is not null
   for update of ws;

  select coalesce(array_agg(so.service_order_number order by so.service_order_number), '{}') into v_os_antes
    from public.work_shift_os wo join public.service_orders so on so.id = wo.service_order_id
   where wo.shift_id = v_antes.id;

  if v_antes.id is null then
    insert into public.work_shifts (work_profile_id, data, tipo, origem, status, observacao, registrado_por,
                                    aprovado_por, aprovado_em, fracao, valor_diaria, extras, descontos)
    values (v_perfil.id, p_data, v_tipo, p_origem, 'aprovado', nullif(btrim(coalesce(p_observacao, '')), ''), v_autor,
            v_autor, now(), v_fracao, round(coalesce(p_valor_diaria, v_perfil.valor_diaria), 2),
            round(coalesce(p_extras, 0), 2), round(coalesce(p_descontos, 0), 2))
    returning id into v_id;
    v_acao := 'criado';
  else
    v_id := v_antes.id;
    update public.work_shifts set
      tipo = v_tipo,
      fracao = v_fracao,
      valor_diaria = round(coalesce(p_valor_diaria, valor_diaria), 2),
      extras = round(coalesce(p_extras, extras), 2),
      descontos = round(coalesce(p_descontos, descontos), 2),
      observacao = case when p_observacao is null then observacao else nullif(btrim(p_observacao), '') end,
      status = 'aprovado', aprovado_por = v_autor, aprovado_em = now()
    where id = v_id;
    v_acao := 'atualizado';
  end if;

  if p_os_ids is not null then
    delete from public.work_shift_os where shift_id = v_id and not (service_order_id = any (p_os_ids));
    insert into public.work_shift_os (shift_id, service_order_id)
    select v_id, x.os from (select distinct unnest(p_os_ids) as os) x
    on conflict do nothing;
  end if;

  select ws.* into v_depois from public.work_shifts ws where ws.id = v_id;
  select coalesce(array_agg(so.service_order_number order by so.service_order_number), '{}') into v_os_depois
    from public.work_shift_os wo join public.service_orders so on so.id = wo.service_order_id
   where wo.shift_id = v_id;

  if v_acao = 'atualizado'
     and v_antes.fracao = v_depois.fracao and v_antes.valor_dia = v_depois.valor_dia
     and v_antes.observacao is not distinct from v_depois.observacao and v_os_antes = v_os_depois then
    v_acao := 'sem_mudanca';
  end if;

  v_resumo := v_fav.name || ' · ' || public._dia_curto(p_data) || ' · ' || public._rotulo_jornada(v_depois.fracao)
              || ' · ' || public._brl(v_depois.valor_dia)
              || case when cardinality(v_os_depois) > 0 then ' · OS ' || array_to_string(v_os_depois, ', ') else '' end;

  return jsonb_build_object(
    'ok', true,
    'acao', v_acao,
    'diaria_id', v_id,
    'favorecido_id', v_fav.id,
    'favorecido', v_fav.name,
    'data', p_data,
    'jornada', case v_depois.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
    'valor_diaria', v_depois.valor_diaria,
    'valor_dia', v_depois.valor_dia,
    'os', to_jsonb(v_os_depois),
    'antes', case when v_antes.id is null then null else jsonb_build_object(
               'jornada', case v_antes.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
               'valor_dia', v_antes.valor_dia, 'os', to_jsonb(v_os_antes)) end,
    'message', v_resumo || case v_acao
      when 'criado' then ' — registrado.'
      when 'sem_mudanca' then ' — já estava assim.'
      else ' — atualizado (era ' || public._rotulo_jornada(v_antes.fracao) || ', ' || public._brl(v_antes.valor_dia) || ').' end
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.registrar_diaria(p_favorecido_id uuid, p_data date, p_jornada text, p_os_ids uuid[], p_observacao text, p_extras numeric, p_descontos numeric, p_valor_diaria numeric, p_origem text, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.registrar_diaria(p_favorecido_id uuid, p_data date, p_jornada text, p_os_ids uuid[], p_observacao text, p_extras numeric, p_descontos numeric, p_valor_diaria numeric, p_origem text, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_diaria(p_favorecido_id uuid, p_data date, p_jornada text, p_os_ids uuid[], p_observacao text, p_extras numeric, p_descontos numeric, p_valor_diaria numeric, p_origem text, p_autor uuid) TO service_role;

-- ── public.registrar_pagamento_da_receita_do_extrato(p_receivable_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.registrar_pagamento_da_receita_do_extrato(p_receivable_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.receivables%rowtype;
  t public.bank_transactions%rowtype;
  v_pagamento uuid;
begin
  select * into r from public.receivables where id = p_receivable_id for update;
  if not found or r.status = 'cancelled' or r.bank_transaction_id is null or coalesce(r.paid_amount, 0) <= 0 then
    return null;
  end if;
  -- Já tem pagamento confirmado: nada a registrar (pode ser chamada de novo sem efeito).
  if exists (select 1 from public.payments where receivable_id = r.id and status = 'confirmed') then
    return null;
  end if;
  select * into t from public.bank_transactions where id = r.bank_transaction_id;
  if t.id is null or t.transaction_type <> 'credit' then return null; end if;

  insert into public.payments (receivable_id, amount, payment_date, payment_method, installments,
                               card_fee_percent, net_amount, notes, status, bank_transaction_id)
  values (r.id, r.paid_amount, t.transaction_date,
          case when coalesce(t.payment_method, '') ilike '%pix%' or coalesce(t.description, '') ilike '%pix%' then 'pix'
               when t.card_last_digits is not null then 'debit_card'
               else 'bank_transfer' end,
          1, 0, r.paid_amount,
          'Conciliado com o extrato de ' || to_char(t.transaction_date, 'DD/MM/YYYY') || ' (a receita nasceu desta linha do banco).',
          'confirmed', t.id)
  returning id into v_pagamento;

  update public.bank_transactions set reconciled_payment_id = v_pagamento
   where id = t.id and reconciled_payment_id is null;
  return v_pagamento;
end;
$function$
;
COMMENT ON FUNCTION public.registrar_pagamento_da_receita_do_extrato(p_receivable_id uuid) IS 'Registra o pagamento de uma receita que nasceu de uma entrada do extrato (conta paga ligada à linha, sem pagamento). Idempotente.';
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.registrar_pagamento_da_receita_do_extrato(p_receivable_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.registrar_pagamento_da_receita_do_extrato(p_receivable_id uuid) TO service_role;

-- ── public.registrar_sinal_pelo_extrato(p_orcamento uuid, p_transacao uuid, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.registrar_sinal_pelo_extrato(p_orcamento uuid, p_transacao uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_os record;
  v_tx public.bank_transactions%rowtype;
  v_r json;
  v_metodo text;
begin
  select id, service_order_number, status, quote_status into v_os
    from public.service_orders where id = p_orcamento for update;
  if v_os.id is null then raise exception 'Orçamento não encontrado.'; end if;
  if v_os.status = 'cancelled' then raise exception 'O orçamento % está cancelado.', v_os.service_order_number; end if;
  if exists (select 1 from public.receivables where service_order_id = p_orcamento and is_deposit and status = 'paid') then
    raise exception 'O sinal do % já está lançado. Case a linha do extrato com ele em vez de lançar de novo.', v_os.service_order_number;
  end if;

  select * into v_tx from public.bank_transactions where id = p_transacao for update;
  if v_tx.id is null then raise exception 'Linha do extrato não encontrada.'; end if;
  if v_tx.transaction_type <> 'credit' then raise exception 'Sinal é dinheiro entrando: escolha uma entrada do extrato.'; end if;
  if v_tx.dismissed_kind is not null then
    raise exception 'Essa linha do extrato está fora da fila (%). Traga-a de volta antes.', v_tx.dismissed_kind;
  end if;
  if exists (select 1 from public.receivables where bank_transaction_id = p_transacao)
     or exists (select 1 from public.payables where bank_transaction_id = p_transacao) then
    raise exception 'Essa linha do extrato já está vinculada a outro lançamento.';
  end if;
  perform public._recusa_se_mes_fechado(v_tx.transaction_date, 'registrar o sinal nesta data');

  v_metodo := case
    when coalesce(v_tx.payment_method, '') ilike '%pix%' or coalesce(v_tx.description, '') ilike '%pix%' then 'pix'
    else 'bank_transfer' end;

  v_r := public.register_deposit_and_convert(
    p_orcamento, v_tx.amount, v_tx.transaction_date, v_metodo, 0,
    'Sinal identificado no extrato de ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY'));

  update public.receivables set bank_transaction_id = p_transacao where id = (v_r ->> 'receivable_id')::uuid;
  update public.bank_transactions
     set reconciled = true, reconciled_payment_id = (v_r ->> 'payment_id')::uuid
   where id = p_transacao;
  update public.finance_review_queue
     set status = 'approved', decided_by = v_autor, decided_at = now(),
         created_receivable_id = (v_r ->> 'receivable_id')::uuid,
         decision_note = 'Sinal do ' || v_os.service_order_number
   where bank_transaction_id = p_transacao and status = 'pending';

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, antes, depois)
  values ('aprovou_proposta', v_autor, p_transacao, (v_r ->> 'receivable_id')::uuid, v_tx.amount,
          left('Sinal do ' || v_os.service_order_number || ' · ' || coalesce(v_tx.counterparty_name, v_tx.description, ''), 300),
          jsonb_build_object('orcamento', v_os.service_order_number, 'status', v_os.status, 'quote_status', v_os.quote_status),
          jsonb_build_object('sinal', v_r));

  return jsonb_build_object(
    'ok', true,
    'receivable_id', v_r ->> 'receivable_id',
    'message', 'Sinal de ' || public._brl(v_tx.amount) || ' registrado; o orçamento virou a '
      || (select service_order_number from public.service_orders where id = p_orcamento) || '.'
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.registrar_sinal_pelo_extrato(p_orcamento uuid, p_transacao uuid, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.registrar_sinal_pelo_extrato(p_orcamento uuid, p_transacao uuid, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_sinal_pelo_extrato(p_orcamento uuid, p_transacao uuid, p_autor uuid) TO service_role;

-- ── public.related_materials(p_service_order_id uuid, p_min_juntos integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.related_materials(p_service_order_id uuid, p_min_juntos integer DEFAULT 3)
 RETURNS TABLE(product_id uuid, product_name text, unit text, sale_price numeric, por_causa_de text, juntos integer, de_total integer, pct integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with na_os as (
    select distinct sop.product_id
    from public.service_order_parts sop
    where sop.service_order_id = p_service_order_id
  ),
  -- Onde mais cada item desta ordem já apareceu. A ordem ATUAL fica de fora
  -- das duas contagens: o que interessa é "nas outras vezes que você usou
  -- isto", e incluir a de agora inflaria o denominador sem informar nada.
  ordens_com as (
    select n.product_id as base, sop.service_order_id
    from na_os n
    join public.service_order_parts sop on sop.product_id = n.product_id
    where sop.service_order_id <> p_service_order_id
  ),
  total_base as (
    select base, count(distinct service_order_id)::integer as de_total
    from ordens_com group by base
  ),
  companheiros as (
    select o.base, x.product_id as sugerido,
           count(distinct x.service_order_id)::integer as juntos
    from ordens_com o
    join public.service_order_parts x
      on x.service_order_id = o.service_order_id and x.product_id <> o.base
    where not exists (select 1 from na_os n where n.product_id = x.product_id)
    group by o.base, x.product_id
  ),
  -- distinct on (sugerido): um produto pode ser puxado por vários itens da
  -- ordem. Mostrar o mesmo material três vezes, uma por origem, transformaria
  -- a lista num quebra-cabeça — fica o vínculo mais forte.
  melhor_vinculo as (
    select distinct on (c.sugerido)
      p.id as product_id, p.name as product_name, p.unit,
      coalesce(p.sale_price, 0) as sale_price,
      base.name as por_causa_de,
      c.juntos, t.de_total,
      round(100.0 * c.juntos / nullif(t.de_total, 0))::integer as pct
    from companheiros c
    join total_base t on t.base = c.base
    join public.products p on p.id = c.sugerido
    join public.products base on base.id = c.base
    where c.juntos >= p_min_juntos
      and p.active
    order by c.sugerido, pct desc, c.juntos desc
  )
  -- NOVO-lev-29: o distinct on obriga a ordenar por id; a ordem que a tela precisa
  -- (mais forte primeiro) e o teto (8) entram aqui, por fora.
  select mv.product_id, mv.product_name, mv.unit, mv.sale_price, mv.por_causa_de,
         mv.juntos, mv.de_total, mv.pct
  from melhor_vinculo mv
  order by mv.pct desc, mv.juntos desc, mv.product_name
  limit 8;
$function$
;
COMMENT ON FUNCTION public.related_materials(p_service_order_id uuid, p_min_juntos integer) IS 'Material que costuma acompanhar o que já está na ordem, medido no histórico
   da casa. Traz a evidência (juntos/de_total/pct) porque é ela que se julga —
   sugestão sem contagem é palpite. Mínimo padrão de 3 ocorrências.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.related_materials(p_service_order_id uuid, p_min_juntos integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.related_materials(p_service_order_id uuid, p_min_juntos integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.related_materials(p_service_order_id uuid, p_min_juntos integer) TO service_role;

-- ── public.remember_reconciliation(p_statement_key text, p_client_id uuid, p_candidate_kind text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.remember_reconciliation(p_statement_key text, p_client_id uuid, p_candidate_kind text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_statement_key IS NULL OR length(trim(p_statement_key)) < 3 OR p_client_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.reconciliation_memory (statement_key, client_id, candidate_kind)
  VALUES (trim(p_statement_key), p_client_id, p_candidate_kind)
  ON CONFLICT (statement_key, client_id) DO UPDATE
    SET hits = public.reconciliation_memory.hits + 1,
        last_seen_at = now(),
        candidate_kind = COALESCE(EXCLUDED.candidate_kind, public.reconciliation_memory.candidate_kind);
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.remember_reconciliation(p_statement_key text, p_client_id uuid, p_candidate_kind text) TO postgres;
GRANT EXECUTE ON FUNCTION public.remember_reconciliation(p_statement_key text, p_client_id uuid, p_candidate_kind text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remember_reconciliation(p_statement_key text, p_client_id uuid, p_candidate_kind text) TO service_role;

-- ── public.resolve_contact_identity(p_phone text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.resolve_contact_identity(p_phone text)
 RETURNS TABLE(kind text, entity_id uuid, entity_name text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  WITH k AS (
    SELECT right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 8) AS key8
  )
  SELECT x.kind, x.entity_id, x.entity_name FROM (
    SELECT 'client'::text, c.id, c.name, 1 AS prio
      FROM clients c, k
     WHERE length(k.key8) = 8
       AND (right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 8) = k.key8
         OR right(regexp_replace(coalesce(c.whatsapp, ''), '\D', '', 'g'), 8) = k.key8)
    UNION ALL
    SELECT 'supplier'::text, s.id, s.name, 2
      FROM suppliers s, k
     WHERE length(k.key8) = 8
       AND right(regexp_replace(coalesce(s.phone, ''), '\D', '', 'g'), 8) = k.key8
    UNION ALL
    SELECT 'lead'::text, l.id, l.name, 3
      FROM external_quote_leads l, k
     WHERE length(k.key8) = 8
       AND (right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 8) = k.key8
         OR right(regexp_replace(coalesce(l.whatsapp, ''), '\D', '', 'g'), 8) = k.key8)
  ) x(kind, entity_id, entity_name, prio)
  ORDER BY x.prio
  LIMIT 1;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.resolve_contact_identity(p_phone text) TO postgres;
GRANT EXECUTE ON FUNCTION public.resolve_contact_identity(p_phone text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_contact_identity(p_phone text) TO service_role;

-- ── public.resolve_practiced_price(p_product_id uuid, p_client_id uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.resolve_practiced_price(p_product_id uuid, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(price numeric, source text, ref_date timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;
begin
  if p_client_id is not null then
    select sop.unit_sale_snapshot as price, so.created_at as ref_date
      into r
    from service_order_parts sop
    join service_orders so on so.id = sop.service_order_id
    where sop.product_id = p_product_id
      and so.client_id = p_client_id
      and sop.unit_sale_snapshot is not null
      and sop.unit_sale_snapshot > 0
    order by so.created_at desc
    limit 1;
    if found then
      return query select r.price, 'último praticado a este cliente'::text, r.ref_date;
      return;
    end if;
  end if;

  select sop.unit_sale_snapshot as price, so.created_at as ref_date
    into r
  from service_order_parts sop
  join service_orders so on so.id = sop.service_order_id
  where sop.product_id = p_product_id
    and sop.unit_sale_snapshot is not null
    and sop.unit_sale_snapshot > 0
  order by so.created_at desc
  limit 1;
  if found then
    return query select r.price, 'último praticado (outro cliente)'::text, r.ref_date;
    return;
  end if;

  select p.sale_price as price into r from products p where p.id = p_product_id;
  return query select coalesce(r.price, 0)::numeric, 'catálogo'::text, null::timestamptz;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.resolve_practiced_price(p_product_id uuid, p_client_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.resolve_practiced_price(p_product_id uuid, p_client_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_practiced_price(p_product_id uuid, p_client_id uuid) TO service_role;

-- ── public.resolve_service_fiscal(p_service_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.resolve_service_fiscal(p_service_id uuid)
 RETURNS TABLE(national_tax_code text, service_code text, cnae text, iss_rate numeric, iss_withheld boolean, code_source text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select
    coalesce(s.national_tax_code, f.default_national_tax_code),
    coalesce(s.service_code,      f.default_service_code),
    coalesce(s.cnae,              f.default_cnae),
    coalesce(s.iss_rate,          f.default_iss_rate),
    coalesce(s.iss_withheld,      f.default_iss_withheld, false),
    case
      when s.national_tax_code is not null            then 'proprio'
      when f.default_national_tax_code is not null    then 'verbo'
      else 'nenhum'
    end
  from public.services s
  left join public.service_fiscal_verbs f on f.verb_slug = s.fiscal_verb
  where s.id = p_service_id;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.resolve_service_fiscal(p_service_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.resolve_service_fiscal(p_service_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_service_fiscal(p_service_id uuid) TO service_role;

-- ── public.resumo_freelancers(p_de date, p_ate date, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.resumo_freelancers(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_ate date := coalesce(p_ate, date '9999-12-31');
  v_pessoas jsonb := '[]'::jsonb;
  f record;
  c jsonb;
  v_ultimo date;
begin
  for f in
    select distinct p.id, p.name
      from public.payees p
      join public.work_profiles wp on wp.payee_id = p.id and wp.modo_pagamento = 'diaria'
     where p.active
     order by p.name
  loop
    c := public.conta_corrente_freelancer(f.id, p_de, p_ate, p_autor);
    select max(l.data) into v_ultimo
      from public._conta_corrente_linhas(f.id) l
     where l.tipo = 'pagamento' and l.data <= v_ate
       and l.data >= coalesce(p_de, date '1900-01-01');
    v_pessoas := v_pessoas || jsonb_build_object(
      'id', f.id, 'nome', f.name,
      'diaria', c -> 'favorecido' -> 'diaria',
      'desde', c -> 'favorecido' -> 'desde',
      'dias', c -> 'dias', 'trabalhado', c -> 'trabalhado', 'pago', c -> 'pago',
      'ultimo_pagamento', v_ultimo,
      'saldo_final', c -> 'saldo_final', 'estado', c -> 'estado');
  end loop;

  return jsonb_build_object(
    'pessoas', v_pessoas,
    'trabalhado', coalesce((select sum((x ->> 'trabalhado')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'pago', coalesce((select sum((x ->> 'pago')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'dias', coalesce((select sum((x ->> 'dias')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'deve', coalesce((select sum(greatest((x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0),
    'adiantado', coalesce((select sum(greatest(-(x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0)
  );
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.resumo_freelancers(p_de date, p_ate date, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.resumo_freelancers(p_de date, p_ate date, p_autor uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resumo_freelancers(p_de date, p_ate date, p_autor uuid) TO service_role;

-- ── public.reverse_nfe_settlement_on_cancel() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.reverse_nfe_settlement_on_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
BEGIN
  -- Só age na transição para 'cancelled', quando houve lançamento e ainda não
  -- foi revertido (idempotente).
  IF NEW.status = 'cancelled'
     AND OLD.status IS DISTINCT FROM 'cancelled'
     AND NEW.stock_settled_at IS NOT NULL
     AND NEW.stock_reversed_at IS NULL THEN

    -- 1) Cancela os recebíveis NÃO PAGOS desta nota (paid_amount = 0).
    UPDATE receivables
       SET status = 'cancelled', updated_at = now()
     WHERE issued_fiscal_document_id = NEW.id
       AND status <> 'paid'
       AND COALESCE(paid_amount, 0) = 0;

    -- 2) Estorna a baixa de estoque: para cada baixa 'fiscal_note_exit' desta
    --    nota, repõe a quantidade e registra um movimento compensatório.
    FOR r IN
      SELECT product_id, quantity_delta
        FROM inventory_movements
       WHERE reference_type = 'issued_fiscal_document'
         AND reference_id = NEW.id
         AND movement_type = 'fiscal_note_exit'
    LOOP
      INSERT INTO inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, notes)
      VALUES
        (r.product_id, 'fiscal_note_cancel_reversal', -r.quantity_delta,
         'issued_fiscal_document', NEW.id,
         'Estorno de estoque — NF-e ' || COALESCE(NEW.series::text,'') || '/'
           || COALESCE(NEW.number::text,'') || ' cancelada');
    END LOOP;

    NEW.stock_reversed_at := now();
  END IF;

  RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.reverse_nfe_settlement_on_cancel() TO postgres;
GRANT EXECUTE ON FUNCTION public.reverse_nfe_settlement_on_cancel() TO service_role;

-- ── public.revert_nfe_import(p_note_id uuid) ── SECURITY DEFINER [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.revert_nfe_import(p_note_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_status     text;
  v_mov        RECORD;
  v_undone     int := 0;
  v_payable    int := 0;
  v_desligadas int := 0;
  v_pago       numeric;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status INTO v_status FROM fiscal_notes WHERE id = p_note_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só é possível desfazer uma importação confirmada (status: %).', v_status;
  END IF;

  -- Parcela criada pela importação e já paga de verdade: desfazer apagaria o registro do
  -- pagamento, e reimportar criaria a parcela de novo.
  SELECT coalesce(sum(paid_amount), 0) INTO v_pago
    FROM payables
   WHERE fiscal_note_id = p_note_id AND origin = 'fiscal_note' AND status <> 'cancelled'
     AND coalesce(paid_amount, 0) > 0
     AND payment_method IS DISTINCT FROM 'credito_fornecedor';
  IF v_pago > 0 THEN
    RAISE EXCEPTION 'Esta nota tem parcela já paga (R$ %). Desfaça o pagamento antes de desfazer a importação.',
      replace(to_char(v_pago, 'FM999999990.00'), '.', ',');
  END IF;

  -- O saldo volta sozinho: apagar os movimentos dispara o recálculo pela soma (fase E).
  SELECT count(*) INTO v_undone FROM inventory_movements
   WHERE reference_type = 'import' AND reference_id = p_note_id;

  DELETE FROM inventory_movements WHERE reference_type = 'import' AND reference_id = p_note_id;

  -- O que a importação criou: a pagar (sem pagamento) e a parcela paga com crédito do fornecedor.
  -- Conta cancelada fica (é trilha de uma decisão), só deixa de apontar para a nota.
  DELETE FROM payables
   WHERE fiscal_note_id = p_note_id AND origin = 'fiscal_note' AND status <> 'cancelled'
     AND (coalesce(paid_amount, 0) = 0 OR payment_method = 'credito_fornecedor');
  GET DIAGNOSTICS v_payable = ROW_COUNT;

  -- O que foi só ligado (o pagamento que já tinha saído pelo banco) e o que foi cancelado voltam a
  -- ficar sem nota — senão a reimportação não reconheceria o pagamento e criaria a parcela de novo.
  UPDATE payables
     SET fiscal_note_id = NULL,
         notes = nullif(btrim(regexp_replace(coalesce(notes, ''), '\s*\[NF-e [^]]*\]', '', 'g')), ''),
         updated_at = now()
   WHERE fiscal_note_id = p_note_id AND (origin <> 'fiscal_note' OR status = 'cancelled');
  GET DIAGNOSTICS v_desligadas = ROW_COUNT;

  DELETE FROM price_update_suggestions WHERE fiscal_note_id = p_note_id;

  UPDATE fiscal_notes
     SET status = 'pending', confirmed_at = NULL, import_result = NULL, updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true, 'movements_reverted', v_undone, 'payables_removed', v_payable,
    'payables_desligadas', v_desligadas
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.revert_nfe_import(p_note_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.revert_nfe_import(p_note_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revert_nfe_import(p_note_id uuid) TO service_role;

-- ── public.rollup_step_time_to_service_line() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.rollup_step_time_to_service_line()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_line uuid := coalesce(new.service_order_service_id, old.service_order_service_id);
  v_total integer;
  v_first timestamptz;
  v_last timestamptz;
  v_pendentes integer;
begin
  if v_line is null then
    return coalesce(new, old);
  end if;

  select coalesce(sum(coalesce(actual_minutes, 0)), 0)::integer,
         min(started_at),
         max(completed_at),
         count(*) filter (where status not in ('done','not_applicable'))
    into v_total, v_first, v_last, v_pendentes
  from public.service_order_steps
  where service_order_service_id = v_line;

  -- Roteiro sem tempo apontado não tem o que dizer sobre a linha.
  if v_total <= 0 then
    return coalesce(new, old);
  end if;

  update public.service_order_services sos
  set elapsed_minutes = v_total,
      started_at = coalesce(sos.started_at, v_first),
      finished_at = case when v_pendentes = 0 then v_last else sos.finished_at end
  where sos.id = v_line
    and (sos.elapsed_minutes is distinct from v_total
      or sos.started_at is distinct from coalesce(sos.started_at, v_first)
      or (v_pendentes = 0 and sos.finished_at is distinct from v_last));

  return coalesce(new, old);
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.rollup_step_time_to_service_line() TO postgres;
GRANT EXECUTE ON FUNCTION public.rollup_step_time_to_service_line() TO service_role;

-- ── public.saldo_do_caixa() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.saldo_do_caixa()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select round(coalesce(c.saldo_base, 0) + coalesce(sum(case when t.transaction_type = 'credit' then t.amount else -t.amount end), 0), 2)
    from public.bank_connections c
    left join public.bank_transactions t
      on t.bank_connection_id = c.id and coalesce(t.tx_status, '') <> 'PENDING'
     and coalesce(t.dismissed_kind, '') not in ('duplicata', 'estornada')
   where c.id = public._conta_caixa()
   group by c.saldo_base;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.saldo_do_caixa() TO postgres;
GRANT EXECUTE ON FUNCTION public.saldo_do_caixa() TO service_role;

-- ── public.search_products_trgm(_term text, _lim integer) ── [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.search_products_trgm(_term text, _lim integer DEFAULT 20)
 RETURNS TABLE(id uuid, name text, sku text, brand text, sale_price numeric, cost_price numeric, sim real)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select p.id, p.name, p.sku, p.brand, p.sale_price, p.cost_price,
         word_similarity(unaccent(_term), unaccent(coalesce(p.name, ''))) as sim
  from products p
  where p.active
    and (
      word_similarity(unaccent(_term), unaccent(coalesce(p.name, ''))) >= 0.3
      or unaccent(coalesce(p.name, '')) ilike '%' || unaccent(_term) || '%'
      or coalesce(p.sku, '') ilike '%' || _term || '%'
    )
  order by sim desc
  limit greatest(1, least(coalesce(_lim, 20), 40));
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.search_products_trgm(_term text, _lim integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.search_products_trgm(_term text, _lim integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_products_trgm(_term text, _lim integer) TO service_role;

-- ── public.seguranca_da_via(p_service_order_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.seguranca_da_via(p_service_order_id uuid)
 RETURNS TABLE(papel text, sistema text, bloco text, escopo text, identificado_por text, seq integer, title text, detail text, kind text, is_killer boolean, requires_photo boolean, requires_measure text, measure_unit text, mode text, standard_minutes numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with linhas as (
    select sos.id, sos.name_snapshot, sos.created_at,
           coalesce(sos.service_system, s.service_system) as gravado,
           coalesce(sos.service_verb, s.service_verb) as verbo
      from public.service_order_services sos
      left join public.services s on s.id = sos.service_id
     where sos.service_order_id = p_service_order_id
  ),
  classificadas as (
    select l.*,
           coalesce(l.gravado,
                    (select ss.slug from public.service_systems ss
                      where ss.slug = (public.classify_service_text(l.name_snapshot)->>'sistema')
                        and ss.is_physical and ss.active)) as sistema,
           case when l.gravado is not null then 'cadastro' else 'texto da linha' end as por
      from linhas l
  ),
  sistemas as (
    select c.sistema,
           min(c.por) as por,  -- 'cadastro' < 'texto da linha': basta uma linha cadastrada
           string_agg(public.frase_legivel(c.name_snapshot), ', ' order by c.created_at) as escopo,
           count(*) as qtd
      from classificadas c
      join public.service_systems ss on ss.slug = c.sistema and ss.is_physical
      left join public.service_verbs sv on sv.slug = c.verbo
     where coalesce(sv.intervem_no_sistema, true)
     group by c.sistema
  )
  select b.block_role::text,
         x.sistema,
         case b.block_role when 'abertura' then 'Antes de mexer — ' else 'Antes de entregar — ' end
           || public.service_system_label(x.sistema),
         case when x.qtd > 1 then 'Vale para os ' || x.qtd || ' serviços desta OS: ' || x.escopo || '.'
              else 'Vale para: ' || x.escopo || '.' end,
         x.por,
         b.seq::integer, b.title::text, b.detail::text, b.kind::text, b.is_killer, b.requires_photo,
         b.requires_measure::text, b.measure_unit::text, b.mode::text, b.standard_minutes::numeric
    from sistemas x
    join public.service_step_blocks b
      on b.active and b.applies_to_system = x.sistema and b.block_role in ('abertura', 'fechamento')
   order by (b.block_role = 'fechamento'), x.sistema, b.seq;
$function$
;
COMMENT ON FUNCTION public.seguranca_da_via(p_service_order_id uuid) IS 'Só leitura: os blocos de segurança (abertura e fechamento) de cada sistema da OS, como generate_service_order_steps gravaria, para a via do técnico imprimir sem roteiro. Sistema do cadastro ou, na falta, do texto da linha. 05/10/2026.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.seguranca_da_via(p_service_order_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.seguranca_da_via(p_service_order_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seguranca_da_via(p_service_order_id uuid) TO service_role;

-- ── public.separar_pro_labore(p_de date, p_ate date, p_autor uuid) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.separar_pro_labore(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ate date := coalesce(p_ate, v_hoje);
  v_de date;
  v_socio record;
  v_mes date;
  v_salario numeric;
  v_restante numeric;
  g record;
  v_pl numeric;
  v_ret numeric;
  v_n integer;
  v_mudou integer := 0;
  v_adotados integer := 0;
  v_fechados integer := 0;
  v_meses jsonb := '[]'::jsonb;
  v_avisos text[] := array[]::text[];
  v_mes_pago numeric;
  v_mes_pl numeric;
  v_mes_ret numeric;
  v_mes_div integer;
  v_mes_mudou integer;
  v_pl_fora numeric;
  v_gastos numeric;
  v_unico boolean;
begin
  -- Há um sócio só na regra? Então o gasto pessoal lançado sem favorecido é dele. Com mais de um,
  -- só conta o gasto que tem o favorecido do sócio.
  v_unico := (select count(*) from public.payees p
               where p.kind = 'socio' and public._socio_com_pro_labore_pelo_minimo(p.id)) = 1;

  for v_socio in
    select p.id, p.name, regexp_replace(coalesce(p.document, ''), '\D', '', 'g') as doc
      from public.payees p
     where p.kind = 'socio' and public._socio_com_pro_labore_pelo_minimo(p.id)
     order by p.name
  loop
    -- Pagamento ao CPF do sócio sem o favorecido ligado (ex.: veio por uma regra de fornecedor).
    if length(v_socio.doc) in (11, 14) then
      with adotados as (
        update public.payables p
           set payee_id = v_socio.id
          from public.bank_transactions bt
         where bt.id = p.bank_transaction_id and p.payee_id is null and p.status = 'paid'
           and p.expense_category in ('Pró-labore', 'Retirada de sócio')
           and regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g') = v_socio.doc
           and not public.periodo_esta_fechado(p.issue_date)
        returning p.id, p.amount, p.bank_transaction_id)
      insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, valor, detalhe)
      select 'identificou_socio', v_autor, a.bank_transaction_id, a.id, a.amount,
             'Pagamento ao CPF de ' || v_socio.name || ' ligado ao favorecido dele (documento igual identifica).'
               || case when v_autor is null then ' Rotina automática.' else '' end
        from adotados a;
      get diagnostics v_n = row_count;
      v_adotados := v_adotados + v_n;
    end if;

    v_de := date_trunc('month', coalesce(p_de,
              (select min(p.issue_date) from public.payables p
                where p.payee_id = v_socio.id and p.status = 'paid'
                  and p.expense_category in ('Pró-labore', 'Retirada de sócio')),
              v_hoje))::date;
    if v_ate < v_de then
      continue;
    end if;

    v_mes := v_de;
    while v_mes <= v_ate loop
      v_salario := public._salario_minimo_em(v_mes);
      if public.periodo_esta_fechado(v_mes) then
        v_fechados := v_fechados + 1;
      elsif v_salario is null or v_salario <= 0 then
        -- Só avisa se o sócio tem pagamento no mês (sem pagamento, não há o que separar).
        if exists (select 1 from public.payables p
                    where p.payee_id = v_socio.id and p.status = 'paid'
                      and p.expense_category in ('Pró-labore', 'Retirada de sócio')
                      and p.issue_date >= v_mes and p.issue_date < (v_mes + interval '1 month')::date) then
          v_avisos := v_avisos || ('Falta o salário mínimo de ' || extract(year from v_mes)::int
                                   || ' em Configurações (chave salario_minimo, "' || extract(year from v_mes)::int
                                   || '-01-01": valor): o pró-labore de ' || to_char(v_mes, 'MM/YYYY') || ' ficou como estava.');
        end if;
      else
        -- Pró-labore que já está num pagamento fora da regra (uma parte trocada à mão para outra
        -- categoria, por exemplo) conta no limite do mês: o mês nunca passa do salário mínimo.
        select coalesce(sum(x.amount), 0) into v_pl_fora
          from public.payables x
         where x.payee_id = v_socio.id and x.status = 'paid' and x.expense_category = 'Pró-labore'
           and x.issue_date >= v_mes and x.issue_date < (v_mes + interval '1 month')::date
           and exists (
             select 1 from public.payables y
              where (y.id = coalesce(x.divisao_id, x.id) or y.divisao_id = coalesce(x.divisao_id, x.id))
                and y.status <> 'cancelled'
                and (coalesce(y.expense_category, '') not in ('Pró-labore', 'Retirada de sócio')
                     or y.payee_id is distinct from v_socio.id or y.status <> 'paid'));
        -- Gasto pessoal que a empresa pagou desconta do pró-labore do mês (decisão do dono,
        -- 29/09/2026: "são gastos pessoais meus, que deverão ser evitados"). Conta antes dos Pix:
        -- o que sobra do salário mínimo é o pró-labore dos Pix, e o resto é retirada. O gasto
        -- fica com a categoria dele; só muda quanto dos Pix é pró-labore.
        select coalesce(sum(x.amount), 0) into v_gastos
          from public.payables x
         where x.status = 'paid' and x.expense_category = 'Gasto Pessoal Sócio - Descontar PL'
           and x.issue_date >= v_mes and x.issue_date < (v_mes + interval '1 month')::date
           and (x.payee_id = v_socio.id or (x.payee_id is null and v_unico));
        if v_gastos > greatest(0, v_salario - v_pl_fora) then
          v_avisos := v_avisos || ('Os gastos pessoais de ' || v_socio.name || ' em ' || to_char(v_mes, 'MM/YYYY')
                                   || ' (' || public._brl(v_gastos) || ') passam do salário mínimo do mês ('
                                   || public._brl(v_salario) || '): todos os Pix do mês ficaram como retirada.');
        end if;
        v_restante := greatest(0, v_salario - v_pl_fora - v_gastos);
        v_mes_pago := 0; v_mes_pl := 0; v_mes_ret := 0; v_mes_div := 0; v_mes_mudou := 0;
        for g in
          select r.id,
                 r.bank_transaction_id,
                 abs(bt.amount) as valor_linha,
                 (select sum(x.amount) from public.payables x
                   where (x.id = r.id or x.divisao_id = r.id) and x.status <> 'cancelled') as total,
                 exists (select 1 from public.payments pm where pm.payable_id = r.id and pm.status = 'confirmed') as tem_pagamento
            from public.payables r
            left join public.bank_transactions bt on bt.id = r.bank_transaction_id
           where r.payee_id = v_socio.id and r.divisao_id is null and r.status = 'paid'
             and r.issue_date >= v_mes and r.issue_date < (v_mes + interval '1 month')::date
             -- O pagamento inteiro é do sócio, pago, e só pró-labore/retirada. Outra categoria numa
             -- parte (gasto pessoal, por exemplo) é decisão à mão: fica como está.
             and not exists (
               select 1 from public.payables x
                where (x.id = r.id or x.divisao_id = r.id) and x.status <> 'cancelled'
                  and (coalesce(x.expense_category, '') not in ('Pró-labore', 'Retirada de sócio')
                       or x.payee_id is distinct from v_socio.id or x.status <> 'paid'))
           order by r.issue_date, bt.transaction_date nulls last, bt.created_at nulls last, r.created_at, r.id
        loop
          -- Divide só o Pix comum: ligado ao banco, com a soma igual ao valor da linha e sem
          -- pagamento registrado à parte. Compra parcelada e afins vão inteiras.
          if g.bank_transaction_id is not null and not g.tem_pagamento and abs(g.total - g.valor_linha) <= 0.005 then
            v_pl := least(v_restante, g.total);
          else
            v_pl := case when g.total <= v_restante then g.total else 0 end;
          end if;
          v_ret := g.total - v_pl;
          -- Cada pagamento num bloco próprio: se um der erro (categoria desativada, mês fechado no
          -- meio), ele fica como estava e os outros seguem. A conferência das partes roda aqui
          -- dentro, e não só no fim da transação, para o erro cair neste bloco.
          begin
            v_n := public._aplicar_pro_labore(g.id, v_pl, v_ret, v_salario, v_mes, v_autor);
            if v_n < 0 then
              raise exception 'o lançamento mudou durante a separação; fica para a próxima rodada';
            end if;
            set constraints public.payables_divisao_confere immediate;
            set constraints public.payables_divisao_confere deferred;
            v_mes_mudou := v_mes_mudou + v_n;
          exception when others then
            v_avisos := v_avisos || ('Não consegui separar o pagamento de ' || public._brl(g.total) || ' de '
                                     || v_socio.name || ' (' || to_char(v_mes, 'MM/YYYY') || ', lançamento ' || g.id
                                     || '): ' || sqlerrm || '. Ficou como estava.');
            -- Ficou como estava: o pró-labore que ele já tem conta no limite do mês.
            select coalesce(sum(x.amount) filter (where x.expense_category = 'Pró-labore'), 0),
                   coalesce(sum(x.amount) filter (where x.expense_category = 'Retirada de sócio'), 0)
              into v_pl, v_ret
              from public.payables x
             where (x.id = g.id or x.divisao_id = g.id) and x.status <> 'cancelled';
          end;
          v_restante := greatest(0, v_restante - v_pl);
          v_mes_pago := v_mes_pago + g.total;
          v_mes_pl := v_mes_pl + v_pl;
          v_mes_ret := v_mes_ret + v_ret;
          if v_pl > 0 and v_ret > 0 then
            v_mes_div := v_mes_div + 1;
          end if;
        end loop;
        v_mudou := v_mudou + v_mes_mudou;
        if v_mes_pago > 0 or v_pl_fora > 0 or v_gastos > 0 then
          v_meses := v_meses || jsonb_build_object(
            'socio', v_socio.name, 'mes', to_char(v_mes, 'YYYY-MM'), 'salario_minimo', v_salario,
            'pago', v_mes_pago, 'pro_labore', v_mes_pl + v_pl_fora, 'retirada', v_mes_ret,
            'pro_labore_fora_da_regra', v_pl_fora, 'gastos_pessoais', v_gastos,
            'divididos', v_mes_div, 'mudados', v_mes_mudou,
            'faltou_para_o_minimo', greatest(0, v_salario - v_mes_pl - v_pl_fora - v_gastos));
        end if;
      end if;
      v_mes := (v_mes + interval '1 month')::date;
    end loop;
  end loop;

  if cardinality(v_avisos) > 0 then
    -- source só aceita frontend/edge/db; quem avisa vai no contexto.
    perform public.log_app_error('db', array_to_string(v_avisos, ' | '), 'separar_pro_labore',
                                 case when v_autor is null then 'rotina' else 'manual' end, 'warn',
                                 jsonb_build_object('avisos', to_jsonb(v_avisos)));
  end if;
  return jsonb_build_object('ok', true, 'ate', v_ate, 'lancamentos_mudados', v_mudou,
                            'favorecido_pelo_documento', v_adotados, 'meses_fechados', v_fechados,
                            'meses', v_meses, 'avisos', to_jsonb(v_avisos));
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.separar_pro_labore(p_de date, p_ate date, p_autor uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.separar_pro_labore(p_de date, p_ate date, p_autor uuid) TO service_role;

-- ── public.service_system_label(p_system text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.service_system_label(p_system text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select coalesce(ss.short_name, ss.name) from public.service_systems ss where ss.slug = p_system),
    p_system);
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.service_system_label(p_system text) TO postgres;
GRANT EXECUTE ON FUNCTION public.service_system_label(p_system text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_system_label(p_system text) TO service_role;

-- ── public.set_ai_agent_memory_updated_at() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.set_ai_agent_memory_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.set_ai_agent_memory_updated_at() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_ai_agent_memory_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_ai_agent_memory_updated_at() TO service_role;

-- ── public.set_ai_agent_tasks_updated_at() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.set_ai_agent_tasks_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.set_ai_agent_tasks_updated_at() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_ai_agent_tasks_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_ai_agent_tasks_updated_at() TO service_role;

-- ── public.set_ai_inbound_sessions_updated_at() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.set_ai_inbound_sessions_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.set_ai_inbound_sessions_updated_at() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_ai_inbound_sessions_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_ai_inbound_sessions_updated_at() TO service_role;

-- ── public.set_ai_workflows_updated_at() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.set_ai_workflows_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.set_ai_workflows_updated_at() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_ai_workflows_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_ai_workflows_updated_at() TO service_role;

-- ── public.set_fiscal_next_number(p_document_type text, p_series integer, p_environment text, p_next_number integer) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.set_fiscal_next_number(p_document_type text, p_series integer, p_environment text, p_next_number integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_max_authorized int;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_next_number < 1 THEN RAISE EXCEPTION 'O próximo número deve ser >= 1.'; END IF;
  IF p_environment NOT IN ('homologacao','producao') THEN RAISE EXCEPTION 'Ambiente inválido.'; END IF;
  SELECT MAX(number) INTO v_max_authorized FROM issued_fiscal_documents
    WHERE document_type=p_document_type AND series=p_series AND environment=p_environment AND status='authorized';
  IF v_max_authorized IS NOT NULL AND p_next_number <= v_max_authorized THEN
    RAISE EXCEPTION 'Já existe NF-e autorizada com número % nessa série/ambiente. Use um número maior que %.', v_max_authorized, v_max_authorized;
  END IF;
  INSERT INTO fiscal_document_sequences (document_type, series, environment, last_number, updated_at)
    VALUES (p_document_type, p_series, p_environment, p_next_number - 1, now())
    ON CONFLICT (document_type, series, environment) DO UPDATE SET last_number = p_next_number - 1, updated_at = now();
  RETURN p_next_number;
END; $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.set_fiscal_next_number(p_document_type text, p_series integer, p_environment text, p_next_number integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.set_fiscal_next_number(p_document_type text, p_series integer, p_environment text, p_next_number integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_fiscal_next_number(p_document_type text, p_series integer, p_environment text, p_next_number integer) TO service_role;

-- ── public.set_line_classification(p_line_id uuid, p_system text, p_verb text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.set_line_classification(p_line_id uuid, p_system text, p_verb text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  update public.service_order_services
  set service_system = nullif(p_system, ''),
      service_verb  = nullif(p_verb, ''),
      updated_at = now()
  where id = p_line_id;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.set_line_classification(p_line_id uuid, p_system text, p_verb text) TO postgres;
GRANT EXECUTE ON FUNCTION public.set_line_classification(p_line_id uuid, p_system text, p_verb text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_line_classification(p_line_id uuid, p_system text, p_verb text) TO service_role;

-- ── public.set_updated_at_now() ── [search_path=""]
CREATE OR REPLACE FUNCTION public.set_updated_at_now()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = pg_catalog.now();
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.set_updated_at_now() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_updated_at_now() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_updated_at_now() TO service_role;

-- ── public.settle_nfe_stock_and_receivable(p_document_id uuid, p_installments jsonb) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.settle_nfe_stock_and_receivable(p_document_id uuid, p_installments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_doc          issued_fiscal_documents;
  v_item         jsonb;
  v_pid          uuid;
  v_qty          numeric;
  v_total        numeric := 0;
  v_pay_method   text;
  v_receivable   uuid;
  v_first_recv   uuid := NULL;
  v_stock_items  int := 0;
  v_n            int;
  v_idx          int := 0;
  v_desc         text;
  v_data_nota    date;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_doc FROM issued_fiscal_documents WHERE id = p_document_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Documento não encontrado.'; END IF;
  IF v_doc.status <> 'authorized' THEN
    RAISE EXCEPTION 'A nota precisa estar autorizada para lançar estoque/recebível.';
  END IF;
  IF v_doc.origin_type <> 'manual' THEN
    RAISE EXCEPTION 'Apenas notas avulsas — as vindas de OS já baixam estoque e geram financeiro pelo fluxo da OS.';
  END IF;
  IF v_doc.stock_settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'Esta nota já teve estoque e recebível lançados.';
  END IF;
  IF v_doc.client_id IS NULL THEN
    RAISE EXCEPTION 'A nota não tem cliente vinculado (necessário para gerar o recebível).';
  END IF;

  -- Baixa de estoque: só itens com product_id.
  IF v_doc.source_items IS NOT NULL THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_doc.source_items) LOOP
      v_pid := NULLIF(v_item->>'product_id','')::uuid;
      v_qty := COALESCE((v_item->>'quantity')::numeric, 0);
      IF v_pid IS NOT NULL AND v_qty > 0 THEN
        INSERT INTO inventory_movements
          (product_id, movement_type, quantity_delta, reference_type, reference_id, notes, created_by)
        VALUES
          (v_pid, 'fiscal_note_exit', -v_qty, 'issued_fiscal_document', p_document_id,
           'Baixa por NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
           auth.uid());
        v_stock_items := v_stock_items + 1;
      END IF;
    END LOOP;
  END IF;

  -- ── O VALOR DA NOTA (vNF), e não a forma de pagamento declarada ───────────
  SELECT round(sum(round((i->>'quantity')::numeric * (i->>'unit_price')::numeric, 2)
                   - COALESCE((i->>'discount')::numeric, 0)
                   + COALESCE((i->>'other_expenses')::numeric, 0)
                   + COALESCE((i->'returned_ipi'->>'value')::numeric, 0)), 2)
    INTO v_total
    FROM jsonb_array_elements(COALESCE(v_doc.request_payload->'items', '[]'::jsonb)) i;

  -- NFS-e não tem itens: o líquido é o que o tomador deve. Último recurso, o pagamento
  -- declarado — que só sobra para nota sem item nenhum.
  v_total := COALESCE(
    NULLIF(v_total, 0),
    (v_doc.request_payload->'amounts'->>'net_amount')::numeric,
    (v_doc.request_payload->'amounts'->>'service_amount')::numeric,
    (v_doc.request_payload->'payments'->0->>'amount')::numeric,
    0);

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Não foi possível calcular o valor desta nota — um recebível de R$ 0,00 não seria cobrável.';
  END IF;

  v_pay_method := v_doc.request_payload->'payments'->0->>'method';

  -- ── A DATA DA NOTA, e não a de hoje ───────────────────────────────────────
  -- Mesma ordem de confiabilidade da tela: carimbo da SEFAZ (já com fuso), evento de
  -- autorização da NFS-e, a coluna, e por fim a criação da linha.
  v_data_nota := (COALESCE(
      (v_doc.provider_status->'sefaz'->>'authorized_at')::timestamptz,
      CASE WHEN v_doc.provider_status->'latest_event'->>'status' = 'authorized'
           THEN (v_doc.provider_status->'latest_event'->>'created_at')::timestamptz END,
      v_doc.authorized_at,
      v_doc.created_at
    ) AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_installments IS NULL OR jsonb_typeof(p_installments) <> 'array' OR jsonb_array_length(p_installments) = 0 THEN
    -- À vista: um recebível, emitido e vencendo na data da nota.
    INSERT INTO receivables
      (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
    VALUES
      (v_doc.client_id,
       'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
       v_data_nota, v_data_nota, v_total, v_total, 'pending', v_pay_method,
       'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
    RETURNING id INTO v_receivable;
    v_first_recv := v_receivable;
    v_n := 1;
  ELSE
    -- Parcelado: um recebível por parcela, com os valores e vencimentos que vieram --
    -- que são os da própria nota, salvo se o gestor os alterou de propósito na tela.
    v_n := jsonb_array_length(p_installments);
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_installments) LOOP
      v_idx := v_idx + 1;
      v_desc := 'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,'')
                || ' (parcela ' || v_idx || '/' || v_n || ')';
      INSERT INTO receivables
        (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
      VALUES
        (v_doc.client_id, v_desc, v_data_nota,
         (v_item->>'due_date')::date,
         (v_item->>'amount')::numeric, (v_item->>'amount')::numeric,
         'pending', COALESCE(NULLIF(v_item->>'method',''), v_pay_method),
         'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
      RETURNING id INTO v_receivable;
      IF v_first_recv IS NULL THEN v_first_recv := v_receivable; END IF;
    END LOOP;
  END IF;

  UPDATE issued_fiscal_documents
     SET stock_settled_at = now(), receivable_id = v_first_recv, updated_at = now()
   WHERE id = p_document_id;

  RETURN jsonb_build_object(
    'ok', true, 'receivable_id', v_first_recv, 'stock_items', v_stock_items,
    'amount', v_total, 'installments', v_n, 'issue_date', v_data_nota
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.settle_nfe_stock_and_receivable(p_document_id uuid, p_installments jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.settle_nfe_stock_and_receivable(p_document_id uuid, p_installments jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.settle_nfe_stock_and_receivable(p_document_id uuid, p_installments jsonb) TO service_role;

-- ── public.share_token_da_requisicao() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.share_token_da_requisicao()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select nullif(current_setting('request.headers', true)::json ->> 'x-share-token', '');
$function$
;
COMMENT ON FUNCTION public.share_token_da_requisicao() IS 'Token do link público apresentado no cabeçalho x-share-token. NULL quando ausente, o que faz as políticas anônimas negarem por omissão.';
-- ACL: =X/postgres postgres=X/postgres anon=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.share_token_da_requisicao() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.share_token_da_requisicao() TO postgres;
GRANT EXECUTE ON FUNCTION public.share_token_da_requisicao() TO anon;
GRANT EXECUTE ON FUNCTION public.share_token_da_requisicao() TO authenticated;
GRANT EXECUTE ON FUNCTION public.share_token_da_requisicao() TO service_role;

-- ── public.should_survey_service(p_service_id uuid, p_client_id uuid, p_vessel_id uuid, p_valor numeric) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.should_survey_service(p_service_id uuid, p_client_id uuid DEFAULT NULL::uuid, p_vessel_id uuid DEFAULT NULL::uuid, p_valor numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_forcado boolean; v_casos integer; v_min integer; v_max integer;
  v_disp numeric; v_cliente_novo boolean := false;
  -- NOVO-lev-32: sem cast cru — texto malformado cai no padrão em vez de derrubar o painel.
  v_limiar numeric := coalesce(
    public.parse_valor_ptbr((select value from public.app_settings where key = 'survey_valor_limiar')), 3000);
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select coalesce(requires_survey, false) into v_forcado from public.services where id = p_service_id;

  select count(*), min(actual_minutes), max(actual_minutes) into v_casos, v_min, v_max
  from public.service_cases
  where service_id = p_service_id and usable and actual_minutes > 0;

  if v_casos >= 2 and v_min > 0 then
    v_disp := round(((v_max - v_min)::numeric / v_min) * 100, 0);
  end if;

  if p_client_id is not null then
    select not exists (
      select 1 from public.service_orders
      where client_id = p_client_id and status in ('completed','invoiced')
    ) into v_cliente_novo;
  end if;

  return jsonb_build_object(
    'precisa', (coalesce(v_forcado,false) or coalesce(v_disp,0) > 30 or v_casos = 0
                or coalesce(p_valor,0) >= v_limiar or v_cliente_novo),
    'motivos', (
      select coalesce(jsonb_agg(m), '[]'::jsonb) from (
        select 'Serviço marcado como sempre exigindo levantamento' as m where coalesce(v_forcado,false)
        union all
        select 'Execuções anteriores variaram ' || v_disp || '% entre si' where coalesce(v_disp,0) > 30
        union all
        select 'Nenhuma execução registrada deste serviço' where v_casos = 0
        union all
        select 'Valor de ' || to_char(p_valor,'FM999G999D00') || ' acima do limiar de ' || to_char(v_limiar,'FM999G999D00')
          where coalesce(p_valor,0) >= v_limiar
        union all
        select 'Cliente ainda sem serviço concluído' where v_cliente_novo
      ) t),
    'casos_conhecidos', v_casos,
    'dispersao_pct', v_disp);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.should_survey_service(p_service_id uuid, p_client_id uuid, p_vessel_id uuid, p_valor numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.should_survey_service(p_service_id uuid, p_client_id uuid, p_vessel_id uuid, p_valor numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.should_survey_service(p_service_id uuid, p_client_id uuid, p_vessel_id uuid, p_valor numeric) TO service_role;

-- ── public.so_expense_add(p_so_id uuid, p_category text, p_description text, p_amount numeric, p_expense_date date, p_paid_by text, p_billable boolean, p_supplier_id uuid, p_notes text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.so_expense_add(p_so_id uuid, p_category text, p_description text, p_amount numeric, p_expense_date date DEFAULT NULL::date, p_paid_by text DEFAULT 'company'::text, p_billable boolean DEFAULT true, p_supplier_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_total numeric;
begin
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Valor da despesa deve ser maior que zero.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from service_orders where id = p_so_id) then
    raise exception 'Ordem de serviço não encontrada.' using errcode = 'no_data_found';
  end if;

  insert into service_order_expenses (
    service_order_id, category, description, amount, expense_date,
    paid_by, billable_to_client, supplier_id, notes, created_by
  ) values (
    p_so_id, p_category, p_description, p_amount, coalesce(p_expense_date, current_date),
    coalesce(p_paid_by, 'company'), coalesce(p_billable, true), p_supplier_id, p_notes, auth.uid()
  ) returning id into v_id;

  perform public.so_recalc_operational_cost(p_so_id);
  select grand_total into v_total from service_orders where id = p_so_id;
  return jsonb_build_object('id', v_id, 'grand_total', v_total);
end;
$function$
;
COMMENT ON FUNCTION public.so_expense_add(p_so_id uuid, p_category text, p_description text, p_amount numeric, p_expense_date date, p_paid_by text, p_billable boolean, p_supplier_id uuid, p_notes text) IS 'Lanca despesa na OS e recalcula o total. Existe porque recalc_so_totals LE operational_cost_total em vez de soma-lo das despesas — inserir sem recalcular deixaria o valor cobrado do cliente errado.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.so_expense_add(p_so_id uuid, p_category text, p_description text, p_amount numeric, p_expense_date date, p_paid_by text, p_billable boolean, p_supplier_id uuid, p_notes text) TO postgres;
GRANT EXECUTE ON FUNCTION public.so_expense_add(p_so_id uuid, p_category text, p_description text, p_amount numeric, p_expense_date date, p_paid_by text, p_billable boolean, p_supplier_id uuid, p_notes text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.so_expense_add(p_so_id uuid, p_category text, p_description text, p_amount numeric, p_expense_date date, p_paid_by text, p_billable boolean, p_supplier_id uuid, p_notes text) TO service_role;

-- ── public.so_expense_remove(p_expense_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.so_expense_remove(p_expense_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_so uuid;
  v_total numeric;
begin
  select service_order_id into v_so from service_order_expenses where id = p_expense_id;
  if v_so is null then
    raise exception 'Despesa não encontrada.' using errcode = 'no_data_found';
  end if;
  delete from service_order_expenses where id = p_expense_id;
  perform public.so_recalc_operational_cost(v_so);
  select grand_total into v_total from service_orders where id = v_so;
  return jsonb_build_object('service_order_id', v_so, 'grand_total', v_total);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.so_expense_remove(p_expense_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.so_expense_remove(p_expense_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.so_expense_remove(p_expense_id uuid) TO service_role;

-- ── public.so_recalc_operational_cost(p_so_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.so_recalc_operational_cost(p_so_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_op numeric;
begin
  select coalesce(sum(amount), 0) into v_op
  from service_order_expenses
  where service_order_id = p_so_id and billable_to_client is distinct from false;

  update service_orders
     set operational_cost_total = round(v_op, 2)
   where id = p_so_id;

  perform public.recalc_so_totals(p_so_id);
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.so_recalc_operational_cost(p_so_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.so_recalc_operational_cost(p_so_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.so_recalc_operational_cost(p_so_id uuid) TO service_role;

-- ── public.so_time_entry_add(p_so_id uuid, p_minutes integer, p_technician uuid, p_started_at timestamp with time zone, p_billable boolean, p_notes text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.so_time_entry_add(p_so_id uuid, p_minutes integer, p_technician uuid DEFAULT NULL::uuid, p_started_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_billable boolean DEFAULT true, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_tech uuid;
  v_inicio timestamptz;
begin
  if coalesce(p_minutes, 0) <= 0 then
    raise exception 'Duração deve ser maior que zero.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from service_orders where id = p_so_id) then
    raise exception 'Ordem de serviço não encontrada.' using errcode = 'no_data_found';
  end if;

  v_tech := coalesce(p_technician, auth.uid());
  if v_tech is null then
    raise exception 'Informe o técnico do apontamento.' using errcode = 'check_violation';
  end if;

  v_inicio := coalesce(p_started_at, now() - make_interval(mins => p_minutes));

  insert into time_entries (
    service_order_id, technician_user_id, started_at, ended_at,
    duration_minutes, billable, notes
  ) values (
    p_so_id, v_tech, v_inicio, v_inicio + make_interval(mins => p_minutes),
    p_minutes, coalesce(p_billable, true), p_notes
  ) returning id into v_id;

  perform public.recalc_so_totals(p_so_id);
  return jsonb_build_object('id', v_id, 'minutos', p_minutes);
end;
$function$
;
COMMENT ON FUNCTION public.so_time_entry_add(p_so_id uuid, p_minutes integer, p_technician uuid, p_started_at timestamp with time zone, p_billable boolean, p_notes text) IS 'Aponta hora na OS e recalcula o total. Sem started_at, conta para tras a partir de agora — e como se aponta hora na pratica.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.so_time_entry_add(p_so_id uuid, p_minutes integer, p_technician uuid, p_started_at timestamp with time zone, p_billable boolean, p_notes text) TO postgres;
GRANT EXECUTE ON FUNCTION public.so_time_entry_add(p_so_id uuid, p_minutes integer, p_technician uuid, p_started_at timestamp with time zone, p_billable boolean, p_notes text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.so_time_entry_add(p_so_id uuid, p_minutes integer, p_technician uuid, p_started_at timestamp with time zone, p_billable boolean, p_notes text) TO service_role;

-- ── public.soma_transacoes_conexao(p_conexao uuid, p_ate date) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.soma_transacoes_conexao(p_conexao uuid, p_ate date)
 RETURNS TABLE(soma numeric, quantidade bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(case when t.transaction_type = 'credit' then t.amount else -t.amount end), 0)::numeric as soma,
         count(*) as quantidade
    from public.bank_transactions t
   where t.bank_connection_id = p_conexao
     and coalesce(t.source_type, 'bank') = 'bank'
     and coalesce(t.tx_status, '') <> 'PENDING'
     and coalesce(t.dismissed_kind, '') <> 'duplicata'
     and t.transaction_date <= p_ate;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.soma_transacoes_conexao(p_conexao uuid, p_ate date) TO postgres;
GRANT EXECUTE ON FUNCTION public.soma_transacoes_conexao(p_conexao uuid, p_ate date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.soma_transacoes_conexao(p_conexao uuid, p_ate date) TO service_role;

-- ── public.stock_model_v2_on() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.stock_model_v2_on()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select lower(value) = 'on' from app_settings where key = 'stock_model_v2'), false);
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.stock_model_v2_on() TO postgres;
GRANT EXECUTE ON FUNCTION public.stock_model_v2_on() TO service_role;

-- ── public.suggest_nfe_service_orders(p_note_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.suggest_nfe_service_orders(p_note_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
with itens as (
  select i.id as item_id,
         coalesce(i.matched_product_id, i.product_id) as product_id,
         coalesce(i.q_com, i.quantity, 0) as qtd
  from fiscal_note_items i
  where i.fiscal_note_id = p_note_id
),
candidatas as (
  select it.item_id,
         so.id   as service_order_id,
         so.service_order_number as os,
         so.created_at,
         sum(sop.quantity) as qtd_na_os,
         row_number() over (partition by it.item_id order by so.created_at asc) as posicao
  from itens it
  join service_order_parts sop on sop.product_id = it.product_id
  join service_orders so       on so.id = sop.service_order_id
  where it.product_id is not null
    and so.status in ('approved', 'scheduled', 'in_progress', 'awaiting_parts')
  group by it.item_id, so.id, so.service_order_number, so.created_at
)
select coalesce(jsonb_object_agg(
         c.item_id,
         jsonb_build_object(
           'service_order_id', c.service_order_id,
           'os', c.os,
           'quantidade_na_os', c.qtd_na_os,
           'motivo', 'esta peça está reservada para esta OS, que aguarda material'
         )
       ), '{}'::jsonb)
from candidatas c
where c.posicao = 1;
$function$
;
COMMENT ON FUNCTION public.suggest_nfe_service_orders(p_note_id uuid) IS 'Sugere, por item da nota, a OS que esta esperando aquela peca (mais antiga primeiro). So sugere — nao grava.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.suggest_nfe_service_orders(p_note_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.suggest_nfe_service_orders(p_note_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suggest_nfe_service_orders(p_note_id uuid) TO service_role;

-- ── public.suggest_service_orders_for_products(p_product_ids uuid[]) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.suggest_service_orders_for_products(p_product_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
with candidatas as (
  select sop.product_id,
         so.id                   as service_order_id,
         so.service_order_number as os,
         so.status,
         so.created_at,
         sum(sop.quantity)       as qtd_na_os,
         row_number() over (partition by sop.product_id order by so.created_at asc) as posicao,
         count(*)    over (partition by sop.product_id) as concorrentes
  from unnest(coalesce(p_product_ids, '{}'::uuid[])) as pid(product_id)
  join service_order_parts sop on sop.product_id = pid.product_id
  join service_orders so       on so.id = sop.service_order_id
  where so.status in ('approved', 'scheduled', 'in_progress', 'awaiting_parts')
  group by sop.product_id, so.id, so.service_order_number, so.status, so.created_at
)
select coalesce(jsonb_object_agg(
         c.product_id,
         jsonb_build_object(
           'service_order_id', c.service_order_id,
           'os',               c.os,
           'status',           c.status,
           'quantidade_na_os', c.qtd_na_os,
           'outras',           greatest(c.concorrentes - 1, 0)
         )
       ), '{}'::jsonb)
from candidatas c
where c.posicao = 1;
$function$
;
COMMENT ON FUNCTION public.suggest_service_orders_for_products(p_product_ids uuid[]) IS 'Para cada produto, a OS que aguarda aquela peca (mais antiga primeiro). Serve a tela de conferencia da NF-e, ANTES da confirmacao — diferente de suggest_nfe_service_orders, que depende de fiscal_note_items ja gravada. So sugere.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.suggest_service_orders_for_products(p_product_ids uuid[]) TO postgres;
GRANT EXECUTE ON FUNCTION public.suggest_service_orders_for_products(p_product_ids uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suggest_service_orders_for_products(p_product_ids uuid[]) TO service_role;

-- ── public.suggest_system_for_line(p_line_id uuid) ── [search_path=public, extensions]
CREATE OR REPLACE FUNCTION public.suggest_system_for_line(p_line_id uuid)
 RETURNS TABLE(sistema text, motivo text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  with linha as (
    select sos.id, sos.service_order_id, so.problem_description
    from public.service_order_services sos
    join public.service_orders so on so.id = sos.service_order_id
    where sos.id = p_line_id
  ),
  pelo_texto as (
    select ss.slug as sis, 'pelo problema relatado nesta OS' as motivo
    from linha l
    join public.service_systems ss
      on ss.slug = (public.classify_service_text(l.problem_description)->>'sistema')
    where ss.is_physical and ss.active
  ),
  pelas_irmas as (
    select ss.slug as sis,
           'as outras linhas desta OS são de ' || coalesce(ss.short_name, ss.name) as motivo
    from linha l
    join public.service_order_services sos
      on sos.service_order_id = l.service_order_id and sos.id <> l.id
    join public.services s on s.id = sos.service_id
    join public.service_systems ss
      on ss.slug = coalesce(sos.service_system, s.service_system)
    where ss.is_physical and ss.active
    group by ss.slug, ss.short_name, ss.name
    order by count(*) desc, ss.slug
    limit 1
  )
  select sis, motivo from pelo_texto
  union all
  select sis, motivo from pelas_irmas where not exists (select 1 from pelo_texto)
  limit 1;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.suggest_system_for_line(p_line_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.suggest_system_for_line(p_line_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suggest_system_for_line(p_line_id uuid) TO service_role;

-- ── public.survey_cable_sizing(p_survey_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.survey_cable_sizing(p_survey_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v jsonb; v_amps numeric; v_len numeric; v_volts numeric := 12;
  v_drop numeric := 3; v_engine boolean := false; v_bundle integer := 1;
  v_txt text; v_trechos integer := 0; v_menor numeric;
  v_aviso text; v_ambiguas text;
  v_tensao_lida boolean := false; v_crit_lida boolean := false;
  v_engine_lido boolean := false; v_feixe_lido boolean := false;
  v_presumido jsonb := '{}'::jsonb;
begin
  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))
    into v_amps
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'corrente' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;

  select max(coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))),
         min(coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))),
         count(*)
    into v_len, v_menor, v_trechos
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'comprimento' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null);

  select a.answer_value into v_txt
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'tensao' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  v_tensao_lida := found;
  if v_txt is not null then v_volts := coalesce(public.parse_answer_number(v_txt), 12); end if;

  v_txt := null;
  select a.answer_value into v_txt
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'criticidade' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  v_crit_lida := found;
  if v_txt is not null and v_txt ilike '%não crítico%' then v_drop := 10; end if;

  select lower(trim(a.answer_value)) in ('sim','s','true') into v_engine
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'casa_maquinas' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  v_engine_lido := found;

  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value), 1)::integer
    into v_bundle
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'feixe' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;
  v_feixe_lido := found;

  select string_agg(s.rotulo, ' · ') into v_ambiguas
  from (
    select array_to_string(t.affects, '/') || ' ("' || left(a.answer_value, 70)
           || case when length(a.answer_value) > 70 then '…' else '' end || '")' as rotulo
    from public.service_survey_answers a
    join public.service_survey_templates t on t.id = a.template_id
    where a.survey_id = p_survey_id
      and a.skipped_reason is null
      and a.answer_value is not null
      and a.numeric_value is null
      and t.affects && array['corrente','comprimento','tensao','feixe']
      and (select count(*) from regexp_matches(a.answer_value, '\d+[.,]?\d*', 'g')) > 1
  ) s;

  v := public.dc_cable_sizing(v_amps, v_len, v_volts, v_drop, 90,
                              coalesce(v_engine, false), coalesce(v_bundle, 1));

  if coalesce(v_trechos, 0) > 1 then
    v_aviso := 'Foram medidos ' || v_trechos || ' trechos (do menor ' || v_menor
            || ' m ao maior ' || v_len || ' m). A conta usou o MAIS LONGO, que é o '
            || 'único que não subdimensiona nenhum dos dois — mas cada percurso é '
            || 'um circuito e pede o seu próprio cabo. Confira se um cabo só atende.';
  end if;

  if v_ambiguas is not null then
    v_aviso := concat_ws(' ', v_aviso,
      'ATENÇÃO — resposta com mais de um número, e a conta usou o PRIMEIRO: '
      || v_ambiguas || '. Se forem trechos ou circuitos diferentes, responda cada '
      || 'um na sua pergunta; o número que sustenta esta bitola pode ser o errado.');
  end if;

  if not v_tensao_lida then v_presumido := v_presumido || jsonb_build_object('tensao_v', v_volts); end if;
  if not v_crit_lida then v_presumido := v_presumido || jsonb_build_object('queda_max_pct', v_drop); end if;
  if not v_engine_lido then v_presumido := v_presumido || jsonb_build_object('casa_de_maquinas', coalesce(v_engine, false)); end if;
  if not v_feixe_lido then v_presumido := v_presumido || jsonb_build_object('condutores_no_feixe', coalesce(v_bundle, 1)); end if;

  if (not v_engine_lido) or (not v_feixe_lido) then
    v_aviso := concat_ws(' ', v_aviso,
      'Casa de máquinas e/ou nº de condutores no feixe NÃO foram respondidos no '
      || 'levantamento — a conta usou a condição mais permissiva da norma, que erra '
      || 'PARA MENOS. Responda essas perguntas antes de fechar a bitola.');
  end if;

  if v_aviso is not null then
    v := jsonb_set(v, '{aviso}',
           to_jsonb(concat_ws(' ', nullif(v->>'aviso', ''), v_aviso)));
  end if;
  if v_ambiguas is not null or (not v_engine_lido) or (not v_feixe_lido) then
    v := jsonb_set(v, '{pronto}', 'false'::jsonb);
  end if;

  return v || jsonb_build_object(
    'trechos_medidos', coalesce(v_trechos, 0),
    'respostas_ambiguas', v_ambiguas,
    'presumido', v_presumido,
    'lido_do_levantamento', jsonb_build_object(
      'corrente_a', v_amps, 'trecho_m', v_len,
      'trecho_criterio', case when coalesce(v_trechos,0) > 1
                              then 'o mais longo de ' || v_trechos || ' medidos'
                              else 'único trecho medido' end,
      'tensao_v', case when v_tensao_lida then v_volts end,
      'queda_max_pct', case when v_crit_lida then v_drop end,
      'casa_de_maquinas', case when v_engine_lido then coalesce(v_engine, false) end,
      'condutores_no_feixe', case when v_feixe_lido then coalesce(v_bundle, 1) end));
end;
$function$
;
COMMENT ON FUNCTION public.survey_cable_sizing(p_survey_id uuid) IS 'Dimensiona o cabo a partir das respostas do levantamento. Com mais de um
   trecho medido usa o MAIS LONGO; quando a resposta que alimenta a conta traz
   mais de um número, avisa e derruba `pronto` — bitola calculada sobre número
   ambíguo não é resultado fechado. Dimensionar um cabo POR TRECHO continua
   sendo o destino (NOVO-lev-36).';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.survey_cable_sizing(p_survey_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.survey_cable_sizing(p_survey_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.survey_cable_sizing(p_survey_id uuid) TO service_role;

-- ── public.survey_question_catalog() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.survey_question_catalog()
 RETURNS TABLE(id uuid, eixo text, tipo_eixo text, question text, answer_type text, options jsonb, price_impact text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select t.id,
         coalesce(t.applies_to_system, t.applies_to_verb),
         case when t.applies_to_system is not null then 'sistema' else 'verbo' end,
         t.question, t.answer_type, t.options, t.price_impact
  from public.service_survey_templates t
  where t.active
    and t.service_id is null          -- as de serviço específico não compõem por eixo
    and coalesce(t.applies_to_system, t.applies_to_verb) is not null
  order by case t.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end, t.seq;
$function$
;
COMMENT ON FUNCTION public.survey_question_catalog() IS 'Catálogo enxuto das perguntas por eixo, para caber num prompt de análise de
   descrição. A IA escolhe entre estas — não inventa pergunta nova.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.survey_question_catalog() TO postgres;
GRANT EXECUTE ON FUNCTION public.survey_question_catalog() TO authenticated;
GRANT EXECUTE ON FUNCTION public.survey_question_catalog() TO service_role;

-- ── public.survey_suggested_materials(p_survey_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.survey_suggested_materials(p_survey_id uuid)
 RETURNS TABLE(rule_id uuid, product_id uuid, product_name text, unit text, question text, answer text, quantity numeric, unit_sale numeric, unit_cost numeric, line_total numeric, rationale text, alerta text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with sizing as (
    select public.survey_cable_sizing(p_survey_id) as s
  ),
  escolha as (
    select public.dc_cable_product_for(
             (s->'lido_do_levantamento'->>'corrente_a')::numeric,
             (s->'lido_do_levantamento'->>'trecho_m')::numeric,
             (s->'lido_do_levantamento'->>'tensao_v')::numeric,
             (s->'lido_do_levantamento'->>'queda_max_pct')::numeric,
             (s->'lido_do_levantamento'->>'casa_de_maquinas')::boolean,
             (s->'lido_do_levantamento'->>'condutores_no_feixe')::integer) as e
    from sizing
  ),
  respondidas as (
    select a.template_id, a.answer_value,
           public.parse_answer_number(a.answer_value) as numero
    from public.service_survey_answers a
    where a.survey_id = p_survey_id
      and a.answer_value is not null
      and a.skipped_reason is null
  ),
  casadas as (
    select r.*, q.answer_value, q.numero, t.question as pergunta
    from respondidas q
    join public.survey_material_rules r on r.template_id = q.template_id and r.active
    join public.service_survey_templates t on t.id = r.template_id
    where case r.condition_type
      when 'sempre' then true
      when 'igual'  then lower(trim(q.answer_value)) = lower(trim(r.match_value))
      when 'contem' then q.answer_value ilike '%' || r.match_value || '%'
      when 'sim'    then lower(trim(q.answer_value)) in ('sim', 's', 'true')
      when 'nao'    then lower(trim(q.answer_value)) in ('não', 'nao', 'n', 'false')
      when 'faixa'  then q.numero is not null
                        and (r.min_value is null or q.numero >= r.min_value)
                        and (r.max_value is null or q.numero < r.max_value)
      else false
    end
  ),
  quantificadas as (
    select c.*,
      case c.qty_mode
        when 'fixa' then c.qty_fixed
        else case when c.numero is null then null else c.numero * c.qty_factor end
      end * (1 + c.qty_slack_pct / 100.0) as bruta
    from casadas c
  ),
  -- Qual produto vale para esta linha, e por que ele pode não existir.
  alvo as (
    select q.*,
      case when q.product_pick = 'cabo_por_dimensionamento'
           then ((select e->'produto'->>'id' from escolha))::uuid
           else q.product_id end as pid,
      case when q.product_pick = 'cabo_por_dimensionamento'
           then (select e->>'motivo' from escolha) end as motivo_cabo
    from quantificadas q
  ),
  contas as (
    select a.*,
      case when a.product_pick = 'cabo_por_dimensionamento' and a.pid is null then null
           when a.qty_round = 'cima' then ceil(a.bruta)
           when a.qty_round = 'meio' then ceil(a.bruta * 2) / 2
           else round(a.bruta, 2) end as qtd
    from alvo a
  )
  select
    c.id as rule_id,
    coalesce(c.pid, c.product_id) as product_id,
    case when c.product_pick = 'cabo_por_dimensionamento' and c.pid is null
         then 'Cabo — não foi possível escolher'
         else p.name end as product_name,
    p.unit,
    c.pergunta,
    c.answer_value,
    c.qtd as quantity,
    coalesce(p.sale_price, 0) as unit_sale,
    coalesce(p.cost_price, 0) as unit_cost,
    case when c.qtd is null then null
         else round(coalesce(p.sale_price, 0) * c.qtd, 2) end as line_total,
    c.rationale,
    nullif(concat_ws(' · ',
      c.motivo_cabo,
      case when c.product_pick = 'cabo_por_dimensionamento' and c.pid is not null
        then 'bitola escolhida pelo dimensionamento (ABYC E-11), não pela regra' end,
      case when c.bruta is null and c.pid is not null
        then 'a resposta não tem número — confira a quantidade' end,
      case when c.qty_mode <> 'fixa'
             and (select count(*) from regexp_matches(c.answer_value, '\d+[.,]?\d*', 'g')) > 1
        then 'a resposta tem mais de um número: usei o primeiro ('
             || trim(to_char(c.numero, 'FM999999.99')) || ') — confira se falta somar os outros' end,
      case when c.qty_mode = 'proporcional' and p.id is not null
             and lower(coalesce(p.unit, '')) not in ('m', 'mt', 'metro', 'metros')
        then 'a regra calcula metros mas o produto é vendido em "' || coalesce(p.unit, '—') || '"' end,
      case when p.id is not null and coalesce(p.cost_price, 0) = 0
        then 'produto sem custo cadastrado: a margem desta linha não é calculável' end,
      case when p.id is not null and coalesce(p.sale_price, 0) = 0
        then 'produto sem preço de venda' end
    ), '') as alerta
  from contas c
  left join public.products p on p.id = coalesce(c.pid, c.product_id)
  order by 3;
$function$
;
COMMENT ON FUNCTION public.survey_suggested_materials(p_survey_id uuid) IS 'O material que as respostas deste levantamento implicam. Só calcula — não
   grava. A regra em modo "cabo_por_dimensionamento" tem o produto escolhido por
   dc_cable_product_for(); quando nenhum cabo atende, a linha vem sem quantidade
   e com o motivo no alerta, e por isso não pode ser lançada.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.survey_suggested_materials(p_survey_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.survey_suggested_materials(p_survey_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.survey_suggested_materials(p_survey_id uuid) TO service_role;

-- ── public.sync_balance_due_on_completion() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.sync_balance_due_on_completion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_due date := COALESCE(NEW.check_out_at::date, CURRENT_DATE);
BEGIN
  UPDATE public.receivables
  SET due_date = v_due
  WHERE service_order_id = NEW.id
    AND due_on_completion = true
    AND status NOT IN ('paid', 'cancelled');

  UPDATE public.collections c
  SET due_date = v_due
  FROM public.receivables r
  WHERE c.receivable_id = r.id
    AND r.service_order_id = NEW.id
    AND r.due_on_completion = true
    AND c.status = 'pending';

  RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.sync_balance_due_on_completion() TO postgres;
GRANT EXECUTE ON FUNCTION public.sync_balance_due_on_completion() TO service_role;

-- ── public.sync_collection_from_receivable() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.sync_collection_from_receivable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Só age quando status muda para 'paid'
  IF NEW.status = 'paid' AND (OLD.status IS DISTINCT FROM 'paid') THEN
    UPDATE public.collections
    SET
      status      = 'paid',
      paid_at     = NOW(),
      paid_amount = NEW.paid_amount,
      payment_confirmed_by = 'auto'
    WHERE receivable_id = NEW.id
      AND status NOT IN ('paid', 'cancelled');
  END IF;
  RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.sync_collection_from_receivable() TO postgres;
GRANT EXECUTE ON FUNCTION public.sync_collection_from_receivable() TO service_role;

-- ── public.sync_commission_on_so_complete() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.sync_commission_on_so_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed') THEN
    IF (NEW.commission_amount IS NOT NULL
        AND NEW.commission_amount > 0
        AND NEW.commissioned_user_id IS NOT NULL) THEN
      INSERT INTO public.commissions (
        service_order_id, user_id, amount, base_value, percentage, status
      ) VALUES (
        NEW.id, NEW.commissioned_user_id, NEW.commission_amount,
        NEW.grand_total, NEW.commission_rate, 'pending'
      )
      ON CONFLICT (service_order_id, user_id) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.sync_commission_on_so_complete() TO postgres;
GRANT EXECUTE ON FUNCTION public.sync_commission_on_so_complete() TO service_role;

-- ── public.sync_fiscal_note_items(p_note_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.sync_fiscal_note_items(p_note_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_inseridos integer := 0;
  v_vinculos  jsonb   := '{}'::jsonb;
begin
  -- Guarda as decisões já tomadas ("esta peça é da OS-00051") antes de reconstruir.
  select coalesce(jsonb_object_agg(item_index::text, service_order_id), '{}'::jsonb)
    into v_vinculos
  from fiscal_note_items
  where fiscal_note_id = p_note_id and service_order_id is not null;

  delete from fiscal_note_items where fiscal_note_id = p_note_id;

  with fiscais as (
    select (e.value->>'index')::int                       as item_index,
           nullif(e.value->>'sku_supplier', '')           as sku_supplier,
           e.value->>'description'                        as description,
           nullif(e.value->>'ncm', '')                    as ncm,
           nullif(e.value->>'cfop', '')                   as cfop,
           nullif(e.value->>'unit', '')                   as unit,
           coalesce((e.value->>'quantity')::numeric, 0)   as quantity,
           coalesce((e.value->>'unit_price')::numeric, 0) as unit_price,
           coalesce((e.value->>'total_price')::numeric, 0) as total_price
    from fiscal_notes n
    cross join lateral jsonb_array_elements(coalesce(n.items, '[]'::jsonb)) e
    where n.id = p_note_id
  ),
  casados as (
    select nullif(e.value->>'sku_supplier', '') as sku_supplier,
           e.value->>'description'              as description,
           (e.value->>'product_id')::uuid       as product_id
    from fiscal_notes n
    cross join lateral jsonb_array_elements(coalesce(n.import_result->'items', '[]'::jsonb)) e
    where n.id = p_note_id
      and nullif(e.value->>'product_id', '') is not null
  )
  insert into fiscal_note_items (
    fiscal_note_id, item_index, description, sku_supplier, ncm, cfop, unit,
    quantity, unit_price, total_price, product_id, matched_product_id,
    x_prod, q_com, v_un_com, v_prod, processed, service_order_id
  )
  select p_note_id, f.item_index, f.description, f.sku_supplier, f.ncm, f.cfop, f.unit,
         f.quantity, f.unit_price, f.total_price, c.product_id, c.product_id,
         f.description, f.quantity, f.unit_price, f.total_price, true,
         nullif(v_vinculos->>f.item_index::text, '')::uuid
  from fiscais f
  left join lateral (
    select c.product_id from casados c
    where (f.sku_supplier is not null and c.sku_supplier = f.sku_supplier)
       or (f.sku_supplier is null and c.description = f.description)
    limit 1
  ) c on true;

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$function$
;
COMMENT ON FUNCTION public.sync_fiscal_note_items(p_note_id uuid) IS 'Reconstroi fiscal_note_items a partir de fiscal_notes.items + import_result.items. Idempotente; preserva o vinculo com OS num jsonb local (sem tabela temporaria, que exigia DELETE irrestrito e quebrava a confirmacao).';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.sync_fiscal_note_items(p_note_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.sync_fiscal_note_items(p_note_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_fiscal_note_items(p_note_id uuid) TO service_role;

-- ── public.sync_service_order_payment_status() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.sync_service_order_payment_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_service_order_id UUID;
  v_total_amount     NUMERIC;
  v_total_paid       NUMERIC;
  v_new_status       TEXT;
BEGIN
  v_service_order_id := COALESCE(
    CASE WHEN TG_OP = 'DELETE' THEN OLD.service_order_id ELSE NEW.service_order_id END,
    OLD.service_order_id
  );

  -- Nada a fazer se não há OS vinculada
  IF v_service_order_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Agrega todos os receivables não-cancelados desta OS
  SELECT
    COALESCE(SUM(amount), 0),
    COALESCE(SUM(paid_amount), 0)
  INTO v_total_amount, v_total_paid
  FROM public.receivables
  WHERE service_order_id = v_service_order_id
    AND status != 'cancelled';

  -- Calcula novo payment_status
  IF v_total_amount = 0 THEN
    v_new_status := 'unpaid';
  ELSIF v_total_paid >= v_total_amount THEN
    v_new_status := 'paid';
  ELSIF v_total_paid > 0 THEN
    v_new_status := 'partially_paid';
  ELSE
    v_new_status := 'unpaid';
  END IF;

  -- Atualiza apenas se mudou (evita UPDATE desnecessário e possíveis loops)
  UPDATE public.service_orders
  SET payment_status = v_new_status
  WHERE id = v_service_order_id
    AND payment_status IS DISTINCT FROM v_new_status;

  RETURN COALESCE(NEW, OLD);
END;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.sync_service_order_payment_status() TO postgres;
GRANT EXECUTE ON FUNCTION public.sync_service_order_payment_status() TO service_role;

-- ── public.touch_fiscal_emission_draft() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.touch_fiscal_emission_draft()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.touch_fiscal_emission_draft() TO postgres;
GRANT EXECUTE ON FUNCTION public.touch_fiscal_emission_draft() TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_fiscal_emission_draft() TO service_role;

-- ── public.touch_open_loop(p_loop_id uuid, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.touch_open_loop(p_loop_id uuid, p_evidence text DEFAULT NULL::text, p_evidence_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source_message_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  UPDATE entity_open_loops
     SET mentions          = mentions + 1,
         last_seen_at      = now(),
         evidence          = coalesce(p_evidence, evidence),
         evidence_at       = coalesce(p_evidence_at, evidence_at),
         source_message_id = coalesce(p_source_message_id, source_message_id),
         updated_at        = now()
   WHERE id = p_loop_id AND status = 'open'
  RETURNING mentions;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.touch_open_loop(p_loop_id uuid, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.touch_open_loop(p_loop_id uuid, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_open_loop(p_loop_id uuid, p_evidence text, p_evidence_at timestamp with time zone, p_source_message_id uuid) TO service_role;

-- ── public.touch_updated_at() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at := now(); return new; end $function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.touch_updated_at() TO postgres;
GRANT EXECUTE ON FUNCTION public.touch_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_updated_at() TO service_role;

-- ── public.trg_parts_reservation() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.trg_parts_reservation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public.stock_model_v2_on() then
    if tg_op = 'UPDATE' and new.product_id is distinct from old.product_id then
      perform public.recompute_product_reservations(old.product_id);
    end if;
    perform public.recompute_product_reservations(coalesce(new.product_id, old.product_id));
  end if;
  return coalesce(new, old);
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.trg_parts_reservation() TO postgres;
GRANT EXECUTE ON FUNCTION public.trg_parts_reservation() TO service_role;

-- ── public.trg_poi_recalc_total() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.trg_poi_recalc_total()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM recalc_po_total(OLD.purchase_order_id);
  ELSE
    PERFORM recalc_po_total(NEW.purchase_order_id);
  END IF;
  RETURN NULL;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.trg_poi_recalc_total() TO postgres;
GRANT EXECUTE ON FUNCTION public.trg_poi_recalc_total() TO authenticated;
GRANT EXECUTE ON FUNCTION public.trg_poi_recalc_total() TO service_role;

-- ── public.trg_product_components_rollup() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.trg_product_components_rollup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.recompute_product_cost(coalesce(new.parent_product_id, old.parent_product_id));
  return coalesce(new, old);
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.trg_product_components_rollup() TO postgres;
GRANT EXECUTE ON FUNCTION public.trg_product_components_rollup() TO service_role;

-- ── public.trg_so_status_stock() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.trg_so_status_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;
  saldo_novo numeric;
  was_consumed boolean := old.status in ('completed','invoiced');
  is_consumed  boolean := new.status in ('completed','invoiced');
begin
  if not public.stock_model_v2_on() then return new; end if;

  if new.status is distinct from old.status then

    -- Entra em CONSUMIDO: baixa física, uma baixa por peça.
    if is_consumed and not was_consumed then
      for r in select product_id, quantity, unit_cost_snapshot
                 from public.service_order_parts
                where service_order_id = new.id loop
        select coalesce(sum(m.quantity_delta), 0) - r.quantity into saldo_novo
          from public.inventory_movements m
         where m.product_id = r.product_id;

        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id,
          unit_cost_snapshot, notes)
        values (r.product_id, 'service_order_usage', -r.quantity, 'service_order', new.id,
                r.unit_cost_snapshot,
                case when saldo_novo < 0
                     then 'ALERTA: saldo ficou negativo (' || saldo_novo
                          || '). A entrada desta peça nunca foi lancada.'
                     else null end);
      end loop;

    -- Sai de CONSUMIDO: devolve SOMENTE o que tem baixa registrada e ainda não
    -- revertida (SAP: estorno com referência; BC: uma reversão por entrada).
    elsif was_consumed and not is_consumed then
      for r in
        select m.id, m.product_id, m.quantity_delta, m.unit_cost_snapshot
          from public.inventory_movements m
         where m.reference_type = 'service_order'
           and m.reference_id = new.id
           and m.movement_type in ('service_order_usage','service_usage')
           and m.quantity_delta < 0
           and not exists (select 1 from public.inventory_movements e where e.reverses_movement_id = m.id)
      loop
        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id,
          unit_cost_snapshot, reverses_movement_id, notes)
        values (r.product_id, 'return', -r.quantity_delta, 'service_order', new.id,
                r.unit_cost_snapshot, r.id,
                'Estorno da baixa ' || r.id || ' (saida de ' || old.status || ' para ' || new.status || ')');
      end loop;
    end if;

    for r in select distinct product_id from public.service_order_parts where service_order_id = new.id loop
      perform public.recompute_product_reservations(r.product_id);
    end loop;
  end if;

  return new;
end;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.trg_so_status_stock() TO postgres;
GRANT EXECUTE ON FUNCTION public.trg_so_status_stock() TO service_role;

-- ── public.trg_sync_fiscal_note_items() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.trg_sync_fiscal_note_items()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.confirmed_at is not null
     and (old.confirmed_at is null or new.items is distinct from old.items
          or new.import_result is distinct from old.import_result) then
    perform public.sync_fiscal_note_items(new.id);
  end if;
  return new;
end;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.trg_sync_fiscal_note_items() TO postgres;
GRANT EXECUTE ON FUNCTION public.trg_sync_fiscal_note_items() TO authenticated;
GRANT EXECUTE ON FUNCTION public.trg_sync_fiscal_note_items() TO service_role;

-- ── public.update_updated_at_column() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role;

-- ── public.valida_categoria_de_despesa() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.valida_categoria_de_despesa()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_canonico text;
begin
  if new.expense_category is null or new.expense_category = '' then
    return new;
  end if;

  if exists (
    select 1 from public.financial_categories
    where name = new.expense_category and type = 'payable' and active
  ) then
    return new;
  end if;

  select name into v_canonico
  from public.financial_categories
  where lower(name) = lower(new.expense_category) and type = 'payable' and active
  limit 1;

  if v_canonico is not null then
    new.expense_category := v_canonico;
    return new;
  end if;

  raise exception
    'Categoria "%" não existe no plano de contas. Crie-a antes de usar, senão o valor some do resultado.',
    new.expense_category
    using errcode = 'check_violation';
end;
$function$
;
COMMENT ON FUNCTION public.valida_categoria_de_despesa() IS 'Exige que expense_category exista no plano de contas, mas normaliza diferenca de MAIUSCULA/minuscula para o nome canonico — uma letra de diferenca chegou a bloquear a entrada de mercadoria inteira em 04/08/2026.';
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.valida_categoria_de_despesa() TO postgres;
GRANT EXECUTE ON FUNCTION public.valida_categoria_de_despesa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.valida_categoria_de_despesa() TO service_role;

-- ── public.valida_recebivel_coerente() ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.valida_recebivel_coerente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Recebível sem valor não é cobrança. Serviço de cortesia é decisão legítima; o que não
  -- pode é virar uma linha que ninguém consegue baixar nem cobrar.
  IF NEW.amount IS NOT NULL AND NEW.amount <= 0 AND coalesce(NEW.status, '') <> 'cancelled' THEN
    RAISE EXCEPTION
      'Recebível precisa de valor maior que zero. Serviço sem cobrança não gera conta a receber.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Vencimento anterior à emissão só faz sentido quando quem manda é a entrega: aí a data
  -- é referência, não prazo. Fora disso, é engano — e nasce vencido.
  IF NEW.due_date IS NOT NULL AND NEW.issue_date IS NOT NULL
     AND NEW.due_date < NEW.issue_date
     AND NOT coalesce(NEW.due_on_completion, false) THEN
    RAISE EXCEPTION
      'Vencimento (%) é anterior à emissão (%). Se o saldo vence na entrega, marque "vence na conclusão" em vez de datar para trás.',
      NEW.due_date, NEW.issue_date
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.valida_recebivel_coerente() TO postgres;
GRANT EXECUTE ON FUNCTION public.valida_recebivel_coerente() TO authenticated;
GRANT EXECUTE ON FUNCTION public.valida_recebivel_coerente() TO service_role;

-- ── public.wa_extract_body_text(p jsonb) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.wa_extract_body_text(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p IS NULL THEN RETURN '[mensagem não reconhecida]'; END IF;
  IF jsonb_typeof(p->'text') = 'string' THEN RETURN p->>'text'; END IF;
  IF p->'text'->>'message' IS NOT NULL THEN RETURN p->'text'->>'message'; END IF;
  IF jsonb_typeof(p->'message') = 'string' THEN RETURN p->>'message'; END IF;
  IF p->'message'->>'conversation' IS NOT NULL THEN RETURN p->'message'->>'conversation'; END IF;
  IF p->'message'->'extendedTextMessage'->>'text' IS NOT NULL THEN RETURN p->'message'->'extendedTextMessage'->>'text'; END IF;
  IF p->>'body' IS NOT NULL THEN RETURN p->>'body'; END IF;
  IF p->>'caption' IS NOT NULL THEN RETURN p->>'caption'; END IF;
  IF p ? 'image' THEN RETURN COALESCE(p->'image'->>'caption', '[imagem]'); END IF;
  IF p ? 'audio' THEN RETURN '[áudio]'; END IF;
  IF p ? 'video' THEN RETURN COALESCE(p->'video'->>'caption', '[vídeo]'); END IF;
  IF p ? 'document' THEN RETURN COALESCE(p->'document'->>'caption', '[documento] ' || COALESCE(p->'document'->>'fileName', '')); END IF;
  IF p ? 'sticker' THEN RETURN '[sticker]'; END IF;
  IF p ? 'reaction' THEN RETURN '[reação] ' || COALESCE(p->'reaction'->>'value', ''); END IF;
  IF p ? 'poll' OR p ? 'pollCreation' THEN RETURN '[enquete]'; END IF;
  IF p ? 'listResponseMessage' OR p->'message' ? 'listResponseMessage' THEN RETURN COALESCE(p->'listResponseMessage'->'singleSelectReply'->>'selectedRowId', '[resposta de lista]'); END IF;
  IF p ? 'buttonsResponseMessage' OR p->'message' ? 'buttonsResponseMessage' THEN RETURN COALESCE(p->'buttonsResponseMessage'->>'selectedDisplayText', '[resposta de botão]'); END IF;
  IF p ? 'location' THEN RETURN '[localização] ' || COALESCE(p->'location'->>'latitude', '') || ',' || COALESCE(p->'location'->>'longitude', ''); END IF;
  IF p ? 'contact' OR p ? 'contacts' OR p ? 'contactsArrayMessage' THEN RETURN '[contato] ' || COALESCE(p->'contact'->>'displayName', ''); END IF;
  RETURN '[mensagem não reconhecida]';
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.wa_extract_body_text(p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.wa_extract_body_text(p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wa_extract_body_text(p jsonb) TO service_role;

-- ── public.wa_extract_message_type(p jsonb) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.wa_extract_message_type(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p IS NULL THEN RETURN 'other'; END IF;
  IF jsonb_typeof(p->'text') = 'string' OR p->'text'->>'message' IS NOT NULL
     OR jsonb_typeof(p->'message') = 'string' OR p->'message'->>'conversation' IS NOT NULL
     OR p->'message'->'extendedTextMessage'->>'text' IS NOT NULL
     OR p->>'body' IS NOT NULL OR p->>'caption' IS NOT NULL THEN RETURN 'text'; END IF;
  IF p ? 'image' THEN RETURN 'image'; END IF;
  IF p ? 'audio' THEN RETURN 'audio'; END IF;
  IF p ? 'video' THEN RETURN 'video'; END IF;
  IF p ? 'document' THEN RETURN 'document'; END IF;
  IF p ? 'sticker' THEN RETURN 'sticker'; END IF;
  IF p ? 'reaction' THEN RETURN 'reaction'; END IF;
  IF p ? 'poll' OR p ? 'pollCreation' THEN RETURN 'poll'; END IF;
  IF p ? 'listResponseMessage' OR p->'message' ? 'listResponseMessage' THEN RETURN 'list_response'; END IF;
  IF p ? 'buttonsResponseMessage' OR p->'message' ? 'buttonsResponseMessage' THEN RETURN 'button_response'; END IF;
  IF p ? 'location' THEN RETURN 'location'; END IF;
  IF p ? 'contact' OR p ? 'contacts' OR p ? 'contactsArrayMessage' THEN RETURN 'contact'; END IF;
  RETURN 'other';
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.wa_extract_message_type(p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.wa_extract_message_type(p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wa_extract_message_type(p jsonb) TO service_role;

-- ── public.wa_normalize_phone(raw text) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.wa_normalize_phone(raw text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  s text;
  d text;
  ddd text;
  rest text;
BEGIN
  IF raw IS NULL OR raw = '' THEN RETURN ''; END IF;
  s := split_part(raw, '@', 1);
  d := regexp_replace(s, '\D', '', 'g');
  IF d = '' THEN RETURN ''; END IF;
  IF length(d) > 14 THEN RETURN ''; END IF;
  IF left(d, 2) = '00' THEN d := substring(d from 3); END IF;
  IF length(d) = 12 AND left(d, 2) = '55' THEN
    ddd := substring(d from 3 for 2);
    rest := substring(d from 5);
    IF rest ~ '^[6-8]' THEN
      d := '55' || ddd || '9' || rest;
    END IF;
  END IF;
  IF length(d) BETWEEN 12 AND 14 THEN RETURN d; END IF;
  IF length(d) IN (10, 11) THEN RETURN '55' || d; END IF;
  RETURN d;
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.wa_normalize_phone(raw text) TO postgres;
GRANT EXECUTE ON FUNCTION public.wa_normalize_phone(raw text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wa_normalize_phone(raw text) TO service_role;

-- ── public.whatsapp_esperando_resposta(_since timestamp with time zone, _limit integer) ── [search_path=""]
CREATE OR REPLACE FUNCTION public.whatsapp_esperando_resposta(_since timestamp with time zone DEFAULT NULL::timestamp with time zone, _limit integer DEFAULT 30)
 RETURNS TABLE(phone text, contato text, categoria text, encerrada boolean, last_inbound_at timestamp with time zone, last_outbound_at timestamp with time zone, unread_count integer, last_body text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with agg as (
    select m.phone_normalized as phone,
           max(m.occurred_at) filter (where m.direction = 'inbound')  as last_in,
           max(m.occurred_at) filter (where m.direction = 'outbound') as last_out,
           bool_or(m.supplier_id is not null) as tem_fornecedor
      from public.whatsapp_messages m
     where (_since is null or m.occurred_at >= _since)
       and coalesce(m.is_broadcast, false) = false
     group by m.phone_normalized
  ),
  pendentes as (
    select * from agg where last_in is not null and (last_out is null or last_in > last_out)
  ),
  enriquecido as (
    select p.*,
      (select mm.client_id from public.whatsapp_messages mm
        where mm.phone_normalized = p.phone order by mm.occurred_at desc limit 1) as client_id,
      (select mm.body from public.whatsapp_messages mm
        where mm.phone_normalized = p.phone and mm.direction = 'inbound' order by mm.occurred_at desc limit 1) as last_body
    from pendentes p
    where not exists (select 1 from public.app_users u where u.phone_normalized = p.phone and u.ai_whatsapp_enabled = true)
  )
  select
    e.phone,
    coalesce(nullif(c.name, ''), nullif(cf.name, ''), nullif(l.name, ''), e.phone) as contato,
    case
      when c.id is not null or l.linked_client_id is not null or cf.id is not null then 'cliente'
      when e.tem_fornecedor or exists (
        select 1 from public.suppliers s
         where length(regexp_replace(coalesce(s.phone, ''), '\D', '', 'g')) >= 8
           and right(regexp_replace(s.phone, '\D', '', 'g'), 8) = right(e.phone, 8)
      ) then 'fornecedor'
      else 'contato'
    end as categoria,
    coalesce(e.last_body ~* '^\s*(ok+|okay|blz|beleza|valeu|vlw|obrigad[oa]s?|brigad[oa]|show|top|perfeito|combinado|certo|fechado|t[aá] ?bom|tudo bem|de nada|abra[cç]o|👍+|🙏+|👌+|✅+|😊+|🤝+)[\s!.,]*$', false) as encerrada,
    e.last_in as last_inbound_at,
    e.last_out as last_outbound_at,
    coalesce(l.unread_count, 0)::int as unread_count,
    e.last_body
  from enriquecido e
  left join public.clients c on c.id = e.client_id
  left join public.whatsapp_leads l on l.phone_normalized = e.phone
  -- Cliente reconhecido pelo telefone do cadastro, mesmo sem a conversa ligada à ficha.
  left join lateral (
    select cl.id, cl.name from public.clients cl
     where length(regexp_replace(coalesce(cl.whatsapp, cl.phone, ''), '\D', '', 'g')) >= 8
       and right(regexp_replace(coalesce(cl.whatsapp, cl.phone), '\D', '', 'g'), 8) = right(e.phone, 8)
     limit 1
  ) cf on c.id is null
  where l.muted_at is null
  order by
    case when c.id is not null or l.linked_client_id is not null or cf.id is not null then 0 else 1 end,
    e.last_in desc
  limit _limit;
$function$
;
-- ACL: postgres=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.whatsapp_esperando_resposta(_since timestamp with time zone, _limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.whatsapp_esperando_resposta(_since timestamp with time zone, _limit integer) TO service_role;

-- ── public.whatsapp_pending_inbox(_since timestamp with time zone, _limit integer) ── [search_path=public]
CREATE OR REPLACE FUNCTION public.whatsapp_pending_inbox(_since timestamp with time zone DEFAULT NULL::timestamp with time zone, _limit integer DEFAULT 15)
 RETURNS TABLE(phone text, contato text, is_client boolean, last_inbound_at timestamp with time zone, last_outbound_at timestamp with time zone, unread_count integer, last_body text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with agg as (
    select
      m.phone_normalized as phone,
      max(m.occurred_at) filter (where m.direction = 'inbound')  as last_in,
      max(m.occurred_at) filter (where m.direction = 'outbound') as last_out
    from whatsapp_messages m
    where (_since is null or m.occurred_at >= _since)
      and coalesce(m.is_broadcast, false) = false
    group by m.phone_normalized
  ),
  pending as (
    select * from agg
    where last_in is not null and (last_out is null or last_in > last_out)
  ),
  enriched as (
    select
      p.phone, p.last_in, p.last_out,
      (select mm.client_id from whatsapp_messages mm
         where mm.phone_normalized = p.phone order by mm.occurred_at desc limit 1) as client_id,
      (select mm.body from whatsapp_messages mm
         where mm.phone_normalized = p.phone and mm.direction = 'inbound'
         order by mm.occurred_at desc limit 1) as last_body
    from pending p
    where not exists (
      select 1 from app_users u
      where u.phone_normalized = p.phone and u.ai_whatsapp_enabled = true
    )
  )
  select
    e.phone,
    coalesce(nullif(c.name, ''), nullif(l.name, ''), e.phone) as contato,
    (c.id is not null or l.linked_client_id is not null) as is_client,
    e.last_in as last_inbound_at,
    e.last_out as last_outbound_at,
    coalesce(l.unread_count, 0)::int as unread_count,
    e.last_body
  from enriched e
  left join clients c on c.id = e.client_id
  left join whatsapp_leads l on l.phone_normalized = e.phone
  where l.muted_at is null          -- exclui contatos silenciados
  order by e.last_in desc
  limit _limit;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.whatsapp_pending_inbox(_since timestamp with time zone, _limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.whatsapp_pending_inbox(_since timestamp with time zone, _limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.whatsapp_pending_inbox(_since timestamp with time zone, _limit integer) TO service_role;

-- ── public.whatsapp_send_queue_idempotencia() ── [search_path=public]
CREATE OR REPLACE FUNCTION public.whatsapp_send_queue_idempotencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  -- Origem automática sem chave explícita: chave por origem + telefone + dia local + corpo.
  if new.dedupe_key is null
     and new.source is not null
     and new.source not in ('manual', 'ai_agent') then
    new.dedupe_key := new.source || ':' || coalesce(new.phone_normalized, '') || ':'
      || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD') || ':'
      || md5(coalesce(new.message, ''));
  end if;

  if new.dedupe_key is not null
     and exists (select 1 from public.whatsapp_send_queue q where q.dedupe_key = new.dedupe_key) then
    -- Repetida: descarta em silêncio (o insert devolve zero linhas para esta entrada).
    -- Duas inserções simultâneas da mesma chave escapam deste exists; o índice único
    -- barra a segunda com 23505, que é o comportamento certo para uma corrida.
    return null;
  end if;

  return new;
end;
$function$
;
-- ACL: =X/postgres postgres=X/postgres anon=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.whatsapp_send_queue_idempotencia() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.whatsapp_send_queue_idempotencia() TO postgres;
GRANT EXECUTE ON FUNCTION public.whatsapp_send_queue_idempotencia() TO anon;
GRANT EXECUTE ON FUNCTION public.whatsapp_send_queue_idempotencia() TO authenticated;
GRANT EXECUTE ON FUNCTION public.whatsapp_send_queue_idempotencia() TO service_role;

