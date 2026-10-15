-- Agrupar orçamentos pelo assistente: a LEITURA que ele usa antes de propor e o agrupar que REABRE um
-- reprovado só no "sim" (15/10/2026).
--
-- Pedido do dono: "Agrupe os 3 últimos orçamentos do Rodrigo, do motorhome VW Delivery" tem de pedir
-- confirmação e, se um dos últimos estiver reprovado, o assistente pergunta sobre ele (do que se trata, o
-- total, desde quando) e se ele entra, antes de gravar qualquer coisa.
--
-- 1) orcamentos_para_agrupar(embarcação, cliente?, autor?, incluir?) — só leitura — devolve:
--   orcamentos        os orçamentos EM ABERTO da embarcação (e do cliente, se dito) do mais NOVO para o mais
--                     antigo: os 20 mais novos MAIS os de p_incluir (o resumo da confirmação passa os
--                     escolhidos, para conferir também um antigo fora dos 20) — INCLUSIVE os reprovados
--                     (quote_status 'rejected'), que contam nos "N últimos". Cada um com a situação com os
--                     rótulos da tela, se pode entrar no agrupamento e, se não pode, por quê: as mesmas regras e
--                     a mesma ordem de _agrupar_orcamentos_montar (migration 20261015180000). Reprovado traz
--                     reprovado_em (a mudança para 'rejected' no audit_log, gravada pela tela como action
--                     'update' com new_value {"quote_status":"rejected"}; sem ela, null: a data não foi
--                     registrada — a última alteração NÃO é a data da reprovação) e impedimento_se_voltar (o
--                     que o impediria mesmo voltando para Em elaboração: assinado, repasse, vínculos, total).
--   fora_da_lista     os 5 documentos mais recentes da embarcação que NÃO estão em aberto (já agrupado, virou
--                     OS, cancelado): "os N últimos" pula esses, e o assistente avisa o dono.
--   agrupados_ativos  os orçamentos desta embarcação que reúnem outros (agrupamento ativo), com os números
--                     das origens — o que o desagrupar desfaz.
--   Só leitura (stable): não grava nada nem chama função que grava.
--
-- 2) agrupar_orcamentos_reabrindo(orçamentos, reabrir, principal?, total?, autor?) — o "sim" do dono quando
--   ele disse que um reprovado ENTRA: na MESMA transação, os de p_reabrir saem de Reprovado para Em
--   elaboração (com a linha da auditoria) e o agrupamento é feito por _agrupar_orcamentos_montar. Se o
--   agrupar recusar, nada muda — o reprovado continua reprovado. Desagrupar devolve o reaberto como estava
--   antes do pedido: Reprovado (quote_status_antes). Antes do "sim" nada muda de situação.
--
-- Mesmas portas de agrupar_orcamentos: o autor é auth.uid() (tela/painel) e, sem sessão, p_autor (assistente
-- pelo service role); só administrador ou financeiro.
--
-- Depende da assinatura de public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric) e das
-- colunas de orcamento_agrupamento_origens da 20261015180000.

-- 0) Depende da 20261015180000 (merged_into_id, histórico do agrupamento, _orcamento_vinculos_que_prendem, _montar)
do $$
begin
  if to_regclass('public.orcamento_agrupamentos') is null
     or to_regclass('public.orcamento_agrupamento_origens') is null
     or to_regprocedure('public._orcamento_vinculos_que_prendem(uuid)') is null
     or to_regprocedure('public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)') is null then
    raise exception 'Aplique antes a migration 20261015180000_agrupar_orcamentos.';
  end if;
end $$;

-- 1) A leitura -------------------------------------------------------------------------------------------
-- Rascunho de 3 argumentos (nunca aplicado em produção): fora, para não haver duas versões.
drop function if exists public.orcamentos_para_agrupar(uuid, uuid, uuid);

create or replace function public.orcamentos_para_agrupar(
  p_vessel_id uuid,
  p_client_id uuid default null,
  p_autor uuid default null,
  p_incluir uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_barco_id uuid;
  v_barco_nome text;
  v_barco_cliente uuid;
  v_cliente_id uuid;
  v_cliente_nome text;
  v_em_aberto integer;
  v_orcamentos jsonb;
  v_fora jsonb;
  v_agrupados jsonb;
begin
  if v_autor is null then
    raise exception 'Faça login para ver os orçamentos a agrupar.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(v_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar orçamentos.' using errcode = '42501';
  end if;
  if p_vessel_id is null then
    raise exception 'Diga de qual embarcação são os orçamentos.' using errcode = '22023';
  end if;

  select v.id, v.name, v.client_id into v_barco_id, v_barco_nome, v_barco_cliente
    from public.vessels v where v.id = p_vessel_id;
  if v_barco_id is null then
    raise exception 'Embarcação não encontrada.' using errcode = 'P0002';
  end if;
  select c.id, c.name into v_cliente_id, v_cliente_nome
    from public.clients c where c.id = coalesce(p_client_id, v_barco_cliente);
  if p_client_id is not null and v_cliente_id is null then
    raise exception 'Cliente não encontrado.' using errcode = 'P0002';
  end if;

  -- Quantos estão em aberto (a lista mostra os 20 mais novos + os pedidos: o assistente avisa se cortou)
  select count(*) into v_em_aberto
    from public.service_orders so
   where so.vessel_id = p_vessel_id
     and (p_client_id is null or so.client_id = p_client_id)
     and so.status = 'draft'
     and so.converted_to_os_at is null
     and so.merged_into_id is null;

  -- Os orçamentos em aberto, do mais novo para o mais antigo. O motivo segue a ordem de
  -- _agrupar_orcamentos_montar: reprovado, assinado, repasse do cartão, vínculos, total desatualizado.
  select coalesce(jsonb_agg(t.item order by t.criado desc, t.id desc), '[]'::jsonb)
    into v_orcamentos
    from (
      select so.id, so.created_at as criado,
             jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'criado_em', so.created_at,
               'data', to_char(so.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'atualizado_em', so.updated_at,
               'cliente_id', so.client_id,
               'cliente', c.name,
               'total', coalesce(so.grand_total, 0),
               'quote_status', coalesce(so.quote_status, 'draft'),
               -- os rótulos da tela (src/lib/constants.ts, quoteStatusConfig)
               'situacao', case coalesce(so.quote_status, 'draft')
                             when 'draft' then 'Em elaboração'
                             when 'sent' then 'Enviado'
                             when 'awaiting_approval' then 'Aguardando aprovação'
                             when 'approved' then 'Aprovado'
                             when 'awaiting_deposit' then 'Aguardando sinal'
                             when 'rejected' then 'Reprovado'
                             else so.quote_status
                           end,
               'reprovado', coalesce(so.quote_status, '') = 'rejected',
               -- só a data registrada da reprovação; null = não registrada
               'reprovado_em', case when so.quote_status = 'rejected' then rep.quando end,
               'reprovado_em_data', case when so.quote_status = 'rejected' and rep.quando is not null
                                         then to_char(rep.quando at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') end,
               'elegivel', m.motivo is null,
               'motivo', m.motivo,
               'impedimento_se_voltar', case when so.quote_status = 'rejected' then o.outro end,
               'resumo', nullif(left(btrim(regexp_replace(coalesce(so.problem_description, ''), '\s+', ' ', 'g')), 160), ''),
               'tem_deslocamento', (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
                                    or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0),
               'desconto', coalesce(so.discount_amount, 0),
               'imposto', coalesce(so.tax_amount, 0),
               'comissao_pct', coalesce(so.commission_rate, 0),
               'comissionado', nullif(btrim(coalesce(so.commissioned_person, '')), ''),
               'condicao_pagamento', coalesce(pc.label, nullif(btrim(coalesce(so.payment_conditions, '')), '')),
               'reune', ag.origens
             ) as item
        from public.service_orders so
        left join public.clients c on c.id = so.client_id
        left join public.payment_condition_presets pc on pc.id = so.payment_condition_preset_id
        cross join lateral (
          select (so.signed_at is not null
                  or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id)) as assinado,
                 public._orcamento_vinculos_que_prendem(so.id) as vinculos,
                 (select k.grand_total from public.calc_so_totals(so.id) k) as calculado
        ) v
        cross join lateral (
          select case
                   when v.assinado then 'assinado pelo cliente'
                   when coalesce(so.card_fee_passthrough_enabled, false) then 'repassa a taxa do cartão'
                   when coalesce(v.vinculos, '') <> '' then 'ligado a: ' || v.vinculos
                   when abs(coalesce(so.grand_total, 0) - coalesce(v.calculado, 0)) > 0.005 then 'total gravado desatualizado'
                 end as outro
        ) o
        cross join lateral (
          select case when so.quote_status = 'rejected' then 'reprovado pelo cliente (desistência)' else o.outro end as motivo
        ) m
        left join lateral (
          select max(a.changed_at) as quando
            from public.audit_log a
           where a.table_name = 'service_orders'
             and a.record_id = so.id
             and a.action = 'update'
             and a.new_value ->> 'quote_status' = 'rejected'
        ) rep on so.quote_status = 'rejected'
        left join lateral (
          select jsonb_agg(x.numero order by x.ordem) as origens
            from public.orcamento_agrupamentos g
            join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
           where g.agrupado_id = so.id and g.desfeito_em is null
        ) ag on true
       where so.id in (
               (select x.id
                  from public.service_orders x
                 where x.vessel_id = p_vessel_id
                   and (p_client_id is null or x.client_id = p_client_id)
                   and x.status = 'draft'
                   and x.converted_to_os_at is null
                   and x.merged_into_id is null
                 order by x.created_at desc, x.id desc
                 limit 20)
               union
               (select x.id
                  from public.service_orders x
                 where x.id = any(coalesce(p_incluir, '{}'::uuid[]))
                   and x.vessel_id = p_vessel_id
                   and (p_client_id is null or x.client_id = p_client_id)
                   and x.status = 'draft'
                   and x.converted_to_os_at is null
                   and x.merged_into_id is null))
    ) t;

  -- Os mais recentes que NÃO estão em aberto: "os N últimos" pula esses — o dono pode estar contando com eles
  select coalesce(jsonb_agg(t.item order by t.criado desc, t.id desc), '[]'::jsonb)
    into v_fora
    from (
      select so.id, so.created_at as criado,
             jsonb_build_object(
               'numero', so.service_order_number,
               'criado_em', so.created_at,
               'data', to_char(so.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'total', coalesce(so.grand_total, 0),
               'por_que', case
                            when so.merged_into_id is not null
                              then 'já agrupado em ' || coalesce(d.service_order_number, 'outro orçamento')
                            when so.status = 'cancelled' then 'cancelado'
                            -- fora de rascunho é OS (há antigas sem converted_to_os_at: ORÇ-00070, concluída)
                            else 'virou OS'
                          end
             ) as item
        from public.service_orders so
        left join public.service_orders d on d.id = so.merged_into_id
       where so.vessel_id = p_vessel_id
         and (p_client_id is null or so.client_id = p_client_id)
         and not (so.status = 'draft' and so.converted_to_os_at is null and so.merged_into_id is null)
       order by so.created_at desc, so.id desc
       limit 5
    ) t;

  -- Agrupados ainda ativos desta embarcação (o que o desagrupar desfaz)
  select coalesce(jsonb_agg(t.item order by t.quando desc), '[]'::jsonb)
    into v_agrupados
    from (
      select g.criado_em as quando,
             jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'agrupado_em', g.criado_em,
               'data', to_char(g.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
               'total', coalesce(so.grand_total, 0),
               'origens', (select jsonb_agg(x.numero order by x.ordem)
                             from public.orcamento_agrupamento_origens x where x.agrupamento_id = g.id),
               'pode_desagrupar', so.status = 'draft' and so.converted_to_os_at is null and so.merged_into_id is null
                                  and so.signed_at is null
                                  and not exists (select 1 from public.service_order_signatures s where s.service_order_id = so.id)
                                  and public._orcamento_vinculos_que_prendem(so.id) = '',
               'motivo', case
                           when so.merged_into_id is not null then 'foi agrupado de novo em outro orçamento: desagrupe aquele primeiro'
                           when so.status <> 'draft' or so.converted_to_os_at is not null then 'já virou OS ou foi cancelado'
                           when so.signed_at is not null
                                or exists (select 1 from public.service_order_signatures s where s.service_order_id = so.id)
                             then 'assinado pelo cliente'
                           when public._orcamento_vinculos_que_prendem(so.id) <> ''
                             then 'ligado a: ' || public._orcamento_vinculos_que_prendem(so.id)
                         end
             ) as item
        from public.orcamento_agrupamentos g
        join public.service_orders so on so.id = g.agrupado_id
       where g.desfeito_em is null
         and so.vessel_id = p_vessel_id
         and (p_client_id is null or so.client_id = p_client_id)
    ) t;

  return jsonb_build_object(
    'embarcacao', jsonb_build_object('id', v_barco_id, 'nome', v_barco_nome),
    'cliente', case when v_cliente_id is null then null else jsonb_build_object('id', v_cliente_id, 'nome', v_cliente_nome) end,
    'ordem', 'do mais novo para o mais antigo',
    'em_aberto', v_em_aberto,
    'mostrando', jsonb_array_length(v_orcamentos),
    'orcamentos', v_orcamentos,
    'fora_da_lista', v_fora,
    'agrupados_ativos', v_agrupados);
end $$;

comment on function public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[]) is
  'Só leitura. Orçamentos em aberto da embarcação (do mais novo ao mais antigo, inclusive reprovados; os 20 mais novos + p_incluir) com elegibilidade e motivo para agrupar, os documentos recentes fora da lista e os agrupados ativos. Usada pelo assistente (listar_orcamentos_para_agrupar e a confirmação de agrupar_orcamentos). Autor = auth.uid() ou p_autor; só admin/financeiro.';

-- 2) Agrupar reabrindo os reprovados que o dono disse que entram (no "sim") ----------------------------------
-- Interna (recebe o número: o teste passa um fictício e não gasta o document_number_seq).
create or replace function public._agrupar_orcamentos_reabrindo(
  p_ids uuid[],
  p_reabrir uuid[],
  p_base uuid,
  p_numero text,
  p_autor uuid,
  p_total_esperado numeric
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reabrir uuid[];
  v_travados uuid[];
  v_numeros text[];
  v_quem text;
  v_r jsonb;
  r record;
begin
  if p_autor is null then
    raise exception 'Faça login para agrupar orçamentos.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar orçamentos.' using errcode = '42501';
  end if;

  v_reabrir := array(select distinct x from unnest(coalesce(p_reabrir, '{}'::uuid[])) x where x is not null);
  if cardinality(v_reabrir) = 0 then
    return public._agrupar_orcamentos_montar(p_ids, p_base, p_numero, p_autor, p_total_esperado);
  end if;
  if p_ids is null or not (v_reabrir <@ p_ids) then
    raise exception 'O orçamento que volta para Em elaboração precisa estar entre os escolhidos.' using errcode = '22023';
  end if;

  -- Trava os escolhidos na mesma ordem do agrupar (por id) antes de mexer: dois pedidos simultâneos não se travam
  select array_agg(t.id) into v_travados
    from (select so.id from public.service_orders so where so.id = any(p_ids) order by so.id for update) t;

  for r in select so.service_order_number, so.status, so.quote_status, so.converted_to_os_at, so.merged_into_id
             from public.service_orders so where so.id = any(v_reabrir) order by so.created_at, so.id loop
    if r.quote_status is distinct from 'rejected' or r.status <> 'draft'
       or r.converted_to_os_at is not null or r.merged_into_id is not null then
      raise exception '% não está mais como Reprovado em aberto. Nada foi agrupado: peça de novo.', r.service_order_number
        using errcode = '22023';
    end if;
  end loop;
  if (select count(*) from public.service_orders so where so.id = any(v_reabrir)) <> cardinality(v_reabrir) then
    raise exception 'Algum orçamento escolhido não existe mais. Nada foi agrupado.' using errcode = 'P0002';
  end if;

  select u.full_name into v_quem from public.app_users u where u.id = p_autor;
  select array_agg(so.service_order_number order by so.created_at, so.id) into v_numeros
    from public.service_orders so where so.id = any(v_reabrir);

  -- Auditoria como a tela grava a mudança de situação (action 'update', new_value com a situação nova)
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  select 'service_orders', so.id, 'update', coalesce(v_quem, 'sistema'),
         jsonb_build_object('quote_status', 'rejected'), jsonb_build_object('quote_status', 'draft'),
         'Saiu de Reprovado para Em elaboração para entrar no agrupamento (o dono disse que ele entra)'
    from public.service_orders so where so.id = any(v_reabrir);

  update public.service_orders so set quote_status = 'draft' where so.id = any(v_reabrir);

  -- Recusa daqui desfaz o de cima: é a mesma transação
  v_r := public._agrupar_orcamentos_montar(p_ids, p_base, p_numero, p_autor, p_total_esperado);

  -- Desagrupar devolve como estava ANTES do pedido: Reprovado
  update public.orcamento_agrupamento_origens x
     set quote_status_antes = 'rejected'
   where x.agrupamento_id = (v_r ->> 'agrupamento_id')::uuid
     and x.origem_id = any(v_reabrir);

  return v_r || jsonb_build_object('reabertos', to_jsonb(v_numeros));
end $$;

-- Porta pública: na tela/painel vale o usuário da sessão e p_autor é IGNORADO; sem sessão (service role), p_autor.
create or replace function public.agrupar_orcamentos_reabrindo(
  p_orcamentos uuid[],
  p_reabrir uuid[],
  p_base uuid default null,
  p_total_esperado numeric default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._agrupar_orcamentos_reabrindo(p_orcamentos, p_reabrir, p_base, null, coalesce(auth.uid(), p_autor), p_total_esperado);
end $$;

comment on function public.agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, numeric, uuid) is
  'O "sim" do agrupar quando o dono disse que um reprovado entra: numa transação, p_reabrir sai de Reprovado para Em elaboração e o agrupamento é feito (agrupar_orcamentos). Recusa = nada muda. Desagrupar devolve o reaberto como Reprovado. Autor = auth.uid() ou p_autor; só admin/financeiro.';

-- 3) Privilégios + prova -----------------------------------------------------------------------------------
revoke all on function public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[]) from public, anon;
grant execute on function public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[]) to authenticated, service_role;
revoke all on function public._agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, text, uuid, numeric) from public, anon, authenticated;
grant execute on function public._agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, text, uuid, numeric) to service_role;
revoke all on function public.agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, numeric, uuid) from public, anon;
grant execute on function public.agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, numeric, uuid) to authenticated, service_role;

do $$
declare
  v_f text := 'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])';
  v_int text := 'public._agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, text, uuid, numeric)';
  v_pub text := 'public.agrupar_orcamentos_reabrindo(uuid[], uuid[], uuid, numeric, uuid)';
begin
  if has_function_privilege('anon', v_f, 'execute')
     or not has_function_privilege('authenticated', v_f, 'execute')
     or not has_function_privilege('service_role', v_f, 'execute')
     or (select p.provolatile from pg_proc p where p.oid = v_f::regprocedure) <> 's'
     or not (select p.prosecdef from pg_proc p where p.oid = v_f::regprocedure)
     or to_regprocedure('public.orcamentos_para_agrupar(uuid, uuid, uuid)') is not null
     or has_function_privilege('anon', v_int, 'execute')
     or has_function_privilege('authenticated', v_int, 'execute')
     or not has_function_privilege('service_role', v_int, 'execute')
     or has_function_privilege('anon', v_pub, 'execute')
     or not has_function_privilege('authenticated', v_pub, 'execute')
     or not has_function_privilege('service_role', v_pub, 'execute')
  then
    raise exception 'Privilégios errados em orcamentos_para_agrupar / agrupar_orcamentos_reabrindo';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20261015181000', 'agrupar_orcamentos_assistente')
on conflict do nothing;
