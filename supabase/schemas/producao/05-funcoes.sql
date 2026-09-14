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

-- ── private.ai_so_status_change_hook() ── SECURITY DEFINER [search_path=public, private]
CREATE OR REPLACE FUNCTION private.ai_so_status_change_hook()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_secret text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret
  FROM app_settings
  WHERE key = 'cron_worker_secret'
  LIMIT 1;

  PERFORM net.http_post(
    url                  := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-lifecycle-hooks',
    headers              := jsonb_build_object(
      'Content-Type',      'application/json',
      'x-trigger-secret',  COALESCE(v_secret, '')
    ),
    body                 := jsonb_build_object(
      'service_order_id',      NEW.id::text,
      'service_order_number',  NEW.service_order_number,
      'old_status',            OLD.status,
      'new_status',            NEW.status,
      'client_id',             NEW.client_id::text,
      'invoicing_status',      NEW.invoicing_status,
      'grand_total',           NEW.grand_total
    ),
    timeout_milliseconds := 8000
  );

  RETURN NEW;
END;
$function$
;
-- private.ai_so_status_change_hook(): ACL padrão (sem grants explícitos)

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
             and x.product_id = m.product_id
             and x.source = 'survey'))
    into v_selecionadas, v_sem_numero, v_qtd_invalida, v_ja_lancadas
  from public.survey_suggested_materials(p_survey_id) m
  where m.rule_id = any(p_rule_ids);

  insert into public.service_order_parts
    (service_order_id, service_order_service_id, product_id, quantity,
     unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale,
     source, notes)
  select v_os, v_linha, m.product_id, m.quantity,
         m.unit_cost, m.unit_sale,
         m.unit_cost * m.quantity, m.unit_sale * m.quantity,
         'survey',
         'Do levantamento: ' || left(m.question, 60) || ' → ' || left(m.answer, 40)
  from public.survey_suggested_materials(p_survey_id) m
  where m.rule_id = any(p_rule_ids)
    and m.quantity is not null
    and m.quantity > 0
    -- Não lança duas vezes o mesmo produto vindo do mesmo levantamento.
    and not exists (
      select 1 from public.service_order_parts x
      where x.service_order_id = v_os
        and x.product_id = m.product_id
        and x.source = 'survey');

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

-- ── public.calc_shift_duration() ──
CREATE OR REPLACE FUNCTION public.calc_shift_duration()
 RETURNS trigger
 LANGUAGE plpgsql
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

-- ── public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) ── SECURITY DEFINER [search_path=public]
CREATE OR REPLACE FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_part RECORD;
  v_receivable RECORD;
  v_payment RECORD;
  v_parts_restored INT := 0;
  v_receivables_cancelled INT := 0;
  v_payments_cancelled INT := 0;
  v_collections_cancelled INT := 0;
  v_deposit_paid NUMERIC := 0;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF NOT public.stock_model_v2_on() THEN
    FOR v_part IN
      SELECT id, product_id, quantity, unit_cost_snapshot
      FROM public.service_order_parts
      WHERE service_order_id = p_service_order_id
    LOOP
      UPDATE public.products
      SET stock_quantity = stock_quantity + v_part.quantity
      WHERE id = v_part.product_id;

      INSERT INTO public.inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
      VALUES
        (v_part.product_id, 'return', v_part.quantity, 'service_order_cancel', p_service_order_id, v_part.unit_cost_snapshot);

      v_parts_restored := v_parts_restored + 1;
    END LOOP;
  END IF;

  FOR v_receivable IN
    SELECT id, status, is_deposit, paid_amount
    FROM public.receivables
    WHERE service_order_id = p_service_order_id
      AND status <> 'cancelled'
  LOOP
    IF v_receivable.is_deposit AND COALESCE(v_receivable.paid_amount, 0) > 0 THEN
      v_deposit_paid := v_deposit_paid + v_receivable.paid_amount;
    END IF;

    FOR v_payment IN
      SELECT id, amount
      FROM public.payments
      WHERE receivable_id = v_receivable.id
        AND status = 'confirmed'
    LOOP
      UPDATE public.payments
      SET status = 'cancelled',
          cancelled_at = v_now,
          cancellation_reason = p_reason
      WHERE id = v_payment.id;

      UPDATE public.bank_transactions
      SET reconciled = FALSE,
          reconciled_payment_id = NULL
      WHERE reconciled_payment_id = v_payment.id;

      v_payments_cancelled := v_payments_cancelled + 1;
    END LOOP;

    UPDATE public.receivables
    SET status = 'cancelled',
        balance_amount = 0
    WHERE id = v_receivable.id;

    v_receivables_cancelled := v_receivables_cancelled + 1;
  END LOOP;

  UPDATE public.collections
  SET status = 'cancelled'
  WHERE service_order_id = p_service_order_id
    AND status <> 'cancelled';
  GET DIAGNOSTICS v_collections_cancelled = ROW_COUNT;

  UPDATE public.service_orders
  SET status = 'cancelled',
      cancelled_at = v_now,
      cancellation_reason = p_reason
  WHERE id = p_service_order_id;

  RETURN json_build_object(
    'success', TRUE,
    'parts_restored', v_parts_restored,
    'receivables_cancelled', v_receivables_cancelled,
    'payments_cancelled', v_payments_cancelled,
    'collections_cancelled', v_collections_cancelled,
    'deposit_paid', v_deposit_paid
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text) TO service_role;

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
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status, items, total_amount, nfe_number, issuer_name
    INTO v_status, v_items, v_total, v_nfe_number, v_issuer_name
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
           stock_quantity = coalesce(stock_quantity, 0) + v_item.quantity,
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

    INSERT INTO payables (
      supplier_id, supplier_name, amount, balance_amount, description,
      issue_date, due_date, status, expense_category, origin, fiscal_note_id
    ) VALUES (
      p_supplier_id, v_issuer_name, v_total, v_total,
      'Compra ref. NF-e ' || coalesce(v_nfe_number, '') || ' - ' || coalesce(v_issuer_name, ''),
      now()::date, (now() + (v_prazo || ' days')::interval)::date,
      'pending', 'Compras de Mercadorias', 'fiscal_note', p_note_id
    ) RETURNING id INTO v_payable_id;
  END IF;

  UPDATE fiscal_notes
     SET status = 'confirmed',
         confirmed_at = now(),
         supplier_id = coalesce(p_supplier_id, supplier_id),
         purchase_order_id = coalesce(p_purchase_order_id, purchase_order_id),
         import_result = jsonb_build_object(
           'items', v_detail, 'products_created', v_created,
           'movements', v_moved, 'payable_id', v_payable_id, 'at', now()
         ),
         updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true,
    'products_created', v_created,
    'movements_created', v_moved,
    'payable_id', v_payable_id,
    'items', v_detail
  );
END;
$function$
;
-- ACL: postgres=X/postgres authenticated=X/postgres service_role=X/postgres
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb, p_purchase_order_id uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb, p_purchase_order_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid, p_manual_mappings jsonb, p_purchase_order_id uuid) TO service_role;

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
    UPDATE products p
    SET stock_quantity = GREATEST(0, p.stock_quantity - sop.quantity)
    FROM service_order_parts sop
    WHERE sop.service_order_id = NEW.id AND sop.product_id = p.id;
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
                     when 'socio' then 'Pró-labore e retirada'
                     when 'clt'   then 'Pró-labore e retirada'
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
BEGIN
  -- Only fire when status moves TO paid/partially_paid
  IF NEW.service_order_id IS NOT NULL
     AND NEW.status IN ('paid', 'partially_paid')
     AND (OLD.status IS DISTINCT FROM NEW.status) THEN

    UPDATE public.service_orders
    SET
      converted_to_os_at = NOW(),
      status             = 'approved',
      quote_status       = 'approved'
    WHERE id                  = NEW.service_order_id
      AND converted_to_os_at  IS NULL
      AND quote_status         = 'awaiting_deposit';

  END IF;
  RETURN NEW;
END;
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
    update products set stock_quantity = stock_quantity - (r.need_per * p_qty) where id = r.component_product_id;
    insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, unit_cost_snapshot, notes)
      values (r.component_product_id, 'manual_remove_stock', -(r.need_per * p_qty), 'production', r.cost_price,
              'Consumo em produção de composto/kit');
    v_consumido := v_consumido || jsonb_build_object('produto', r.name, 'consumido', r.need_per * p_qty);
  end loop;

  -- 3) Credita o produto acabado.
  update products set stock_quantity = stock_quantity + p_qty where id = p_parent;
  insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, notes)
    values (p_parent, 'manual_add_stock', p_qty, 'production', 'Produção de composto/kit');

  return jsonb_build_object(
    'ok', true, 'produzido', p_qty, 'consumidos', v_consumido,
    'novo_estoque_pai', (select stock_quantity from products where id = p_parent));
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
  v_labor numeric;
  v_parts numeric;
  v_operational numeric;
  v_travel numeric;
  v_subcontract numeric;
  v_discount numeric;
  v_tax numeric;
  v_is_travel_billable boolean;
  v_card_passthrough_enabled boolean;
  v_card_installments integer;
  v_fee_percent numeric;
  v_billable_travel numeric;
  v_subtotal numeric;
  v_base numeric;
  v_card_fee_amount numeric;
  v_grand_total numeric;
begin
  select status into v_status from service_orders where id = so_id;
  if not found or v_status = 'cancelled' then
    return;
  end if;

  select coalesce(sum(line_total), 0) into v_labor
  from service_order_services where service_order_id = so_id;

  select coalesce(sum(line_total_sale), 0) into v_parts
  from service_order_parts where service_order_id = so_id;

  select
    coalesce(operational_cost_total, 0),
    coalesce(travel_cost_total, 0),
    coalesce(subcontract_cost_total, 0),
    coalesce(discount_amount, 0),
    coalesce(tax_amount, 0),
    is_travel_billable,
    card_fee_passthrough_enabled,
    card_installments
  into
    v_operational, v_travel, v_subcontract, v_discount, v_tax,
    v_is_travel_billable, v_card_passthrough_enabled, v_card_installments
  from service_orders where id = so_id;

  v_billable_travel := case when v_is_travel_billable is distinct from false then v_travel else 0 end;
  v_subtotal := v_labor + v_parts + v_operational + v_billable_travel + v_subcontract;
  v_base := v_subtotal - v_discount + v_tax;

  v_fee_percent := 0;
  if v_card_passthrough_enabled and v_card_installments is not null then
    select fee_percent into v_fee_percent
    from card_installment_fees where installments = v_card_installments;
    v_fee_percent := coalesce(v_fee_percent, 0);
  end if;

  v_card_fee_amount := case when v_fee_percent > 0
    then round(v_base * v_fee_percent / (100 - v_fee_percent), 2)
    else 0
  end;

  v_grand_total := v_base + v_card_fee_amount;

  update service_orders
  set labor_cost_total = v_labor,
      parts_cost_total = v_parts,
      card_fee_amount = v_card_fee_amount,
      grand_total = v_grand_total
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

    -- Increment stock
    UPDATE public.products
       SET stock_quantity   = COALESCE(stock_quantity, 0) + (v_item->>'received_qty')::numeric,
           last_stock_entry_at = NOW()
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
declare r record;
begin
  -- Devolve ao físico o que o modelo antigo baixou de OS NÃO consumidas e NÃO canceladas
  -- (consumidas mantêm a baixa; canceladas já tiveram estorno no modelo antigo).
  for r in
    select sop.product_id, sum(sop.quantity) q
    from public.service_order_parts sop
    join public.service_orders so on so.id = sop.service_order_id
    where so.status in ('draft','open','pending','approved','scheduled','in_progress','awaiting_parts','awaiting_client','reopened')
    group by sop.product_id
  loop
    update public.products set stock_quantity = stock_quantity + r.q where id = r.product_id;
  end loop;
  for r in select id from public.products loop
    perform public.recompute_product_reservations(r.id);
  end loop;
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
      -- quantity_delta é negativo (baixa); subtrair o negativo repõe o estoque.
      UPDATE products
         SET stock_quantity = stock_quantity - r.quantity_delta, updated_at = now()
       WHERE id = r.product_id;

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
  v_status  text;
  v_mov     RECORD;
  v_undone  int := 0;
  v_payable int := 0;
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

  FOR v_mov IN
    SELECT product_id, quantity_delta FROM inventory_movements
     WHERE reference_type = 'import' AND reference_id = p_note_id
  LOOP
    UPDATE products
       SET stock_quantity = coalesce(stock_quantity, 0) - v_mov.quantity_delta,
           updated_at = now()
     WHERE id = v_mov.product_id;
    v_undone := v_undone + 1;
  END LOOP;

  DELETE FROM inventory_movements WHERE reference_type = 'import' AND reference_id = p_note_id;

  DELETE FROM payables
   WHERE fiscal_note_id = p_note_id AND coalesce(paid_amount, 0) = 0;
  GET DIAGNOSTICS v_payable = ROW_COUNT;

  DELETE FROM price_update_suggestions WHERE fiscal_note_id = p_note_id;

  UPDATE fiscal_notes
     SET status = 'pending', confirmed_at = NULL, import_result = NULL, updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true, 'movements_reverted', v_undone, 'payables_removed', v_payable
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
        UPDATE products
           SET stock_quantity = GREATEST(0, stock_quantity - v_qty), updated_at = now()
         WHERE id = v_pid;
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

  v_total := COALESCE((v_doc.request_payload->'payments'->0->>'amount')::numeric, 0);
  v_pay_method := v_doc.request_payload->'payments'->0->>'method';

  IF p_installments IS NULL OR jsonb_typeof(p_installments) <> 'array' OR jsonb_array_length(p_installments) = 0 THEN
    -- À vista: um recebível vencendo hoje.
    INSERT INTO receivables
      (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
    VALUES
      (v_doc.client_id,
       'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
       CURRENT_DATE, CURRENT_DATE, v_total, v_total, 'pending', v_pay_method,
       'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
    RETURNING id INTO v_receivable;
    v_first_recv := v_receivable;
    v_n := 1;
  ELSE
    -- Parcelado: um recebível por parcela.
    v_n := jsonb_array_length(p_installments);
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_installments) LOOP
      v_idx := v_idx + 1;
      v_desc := 'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,'')
                || ' (parcela ' || v_idx || '/' || v_n || ')';
      INSERT INTO receivables
        (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
      VALUES
        (v_doc.client_id, v_desc, CURRENT_DATE,
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
    'amount', v_total, 'installments', v_n
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

-- ── public.touch_updated_at() ──
CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
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
        update public.products
           set stock_quantity = stock_quantity - r.quantity
         where id = r.product_id
        returning stock_quantity into saldo_novo;

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
        update public.products
           set stock_quantity = stock_quantity + (-r.quantity_delta)
         where id = r.product_id;
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

