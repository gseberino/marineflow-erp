-- "Agrupar para o cliente" — F2: APROVAR O CONJUNTO. Decisões do dono de 18/11/2026 (plano aprovado "A, pode começar").
--
-- O cliente aprova os documentos do conjunto JUNTOS (pela tela; o link público e o assistente vêm depois). Regras:
--   · documento já ASSINADO nunca é alterado (nem a marca); OS já é aprovada: não muda;
--   · 3A: cada orçamento mantém a PRÓPRIA condição e o PRÓPRIO sinal — o sinal é só do complemento;
--   · 5A: o orçamento complementar aprovado vira OS PRÓPRIA, marcada "complementa OS-X" (nunca entra na OS assinada);
--   · só mesma embarcação (o conjunto já garante); o conjunto continua sem número e sem linha em service_orders.
--
-- Nada novo no funil: a aprovação usa os mesmos passos de hoje.
--   · condição COM sinal → quote_status 'awaiting_deposit' (o mesmo do aceite por texto, orcamento_aceite_com_sinal):
--     o "Receber sinal" de hoje (register_deposit_and_convert / handle_quote_deposit_payment) converte quando o sinal entra;
--   · condição SEM sinal (ou sinal já pago) → quote_status 'approved' + conversão pela porta única
--     (os_transicionar_status → 'approved'), que troca só o prefixo do número (ORÇ-00140 → OS-00140) — a MESMA linha,
--     por isso a marca gravada na aprovação atravessa a conversão.
-- Tudo ou nada: se a porta recusar a conversão de um, nenhum muda e a frase da porta volta.
-- O histórico (trg_historico) grava cada mudança com o autor e o motivo "Aprovado junto com o conjunto …".

-- 1) A marca "complementa OS-X" ---------------------------------------------------------------------------------
alter table public.service_orders
  add column if not exists complementa_os_id uuid references public.service_orders(id) on delete set null;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'service_orders_complementa_outra') then
    alter table public.service_orders
      add constraint service_orders_complementa_outra check (complementa_os_id is null or complementa_os_id <> id);
  end if;
end $$;
create index if not exists service_orders_complementa_idx
  on public.service_orders (complementa_os_id) where complementa_os_id is not null;
comment on column public.service_orders.complementa_os_id is
  'Agrupar para o cliente (F2, decisão 5A): este documento é um orçamento complementar aprovado junto com a OS indicada. Vira OS própria; não entra na OS indicada. Gravado por aprovar_conjunto.';

-- 2) A condição do orçamento tem sinal? SÓ classifica (o valor a cobrar continua na lib única, src/lib/quote-deposit.ts).
--    Parcelas: as do preset (lista), senão as personalizadas (lista) — a mesma resolução de _os_recebiveis_da_conclusao.
--    Sem parcela = a condição padrão (CONDICAO_PADRAO: 50% do serviço + 100% de peças e despesas) = tem sinal.
--    Parcela de sinal = isSignalInstallment (tipo 'aprovacao'; 'entrega'/'prazo' nunca; sem tipo, dia 0). Tem sinal quando
--    alguma dá pelo menos um centavo: (mão de obra·s% + peças·p% + despesas·x%) × discountRatio, como depositAmountFromPcts.
create or replace function public._orcamento_tem_sinal(p_os uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v record;
  v_parc jsonb;
  e jsonb;
  v_lab double precision;
  v_parts double precision;
  v_exp double precision;
  v_sub double precision;
  v_ratio double precision;
  v_tipo text;
  v_d double precision;
  v_s double precision;
  v_p double precision;
  v_x double precision;
  v_val double precision;
begin
  select so.labor_cost_total, so.parts_cost_total, so.operational_cost_total, so.travel_cost_total,
         so.subcontract_cost_total, so.is_travel_billable, so.discount_amount, so.tax_amount,
         so.custom_payment_installments as personalizadas, pc.installments as do_preset
    into v
    from public.service_orders so
    left join public.payment_condition_presets pc on pc.id = so.payment_condition_preset_id
   where so.id = p_os;
  if not found then
    return false;
  end if;

  v_parc := case when jsonb_typeof(v.do_preset) = 'array' then v.do_preset
                 when jsonb_typeof(v.personalizadas) = 'array' then v.personalizadas
                 else null end;

  -- depositBaseFromOrder: deslocamento só quando faturável; nulo = 0.
  v_lab   := coalesce(v.labor_cost_total, 0)::double precision;
  v_parts := coalesce(v.parts_cost_total, 0)::double precision;
  v_exp   := (coalesce(v.operational_cost_total, 0)::double precision
              + case when v.is_travel_billable is distinct from false
                     then coalesce(v.travel_cost_total, 0)::double precision else 0::double precision end)
             + coalesce(v.subcontract_cost_total, 0)::double precision;
  v_sub   := (v_lab + v_parts) + v_exp;
  v_ratio := case when v_sub > 0
                  then ((v_sub - coalesce(v.discount_amount, 0)::double precision) + coalesce(v.tax_amount, 0)::double precision) / v_sub
                  else 1::double precision end;

  if v_parc is null or jsonb_array_length(v_parc) = 0 then
    v_val := ((v_lab * 50 / 100 + v_parts) + v_exp) * v_ratio;
    return v_val <> 'NaN'::double precision and v_val >= 0.005;
  end if;

  for e in select x from jsonb_array_elements(v_parc) t(x) loop
    v_tipo := case when jsonb_typeof(e) = 'object' then e ->> 'tipo' end;
    v_d := public._os_numero_js(coalesce(nullif(e -> 'days_after_approval', 'null'::jsonb), '0'::jsonb));
    if v_tipo = 'aprovacao'
       or (v_tipo is distinct from 'entrega' and v_tipo is distinct from 'prazo' and v_d = 0) then
      v_s := public._os_numero_js(coalesce(nullif(e -> 'services_pct', 'null'::jsonb), nullif(e -> 'percent', 'null'::jsonb), '0'::jsonb));
      v_p := public._os_numero_js(coalesce(nullif(e -> 'parts_pct', 'null'::jsonb), nullif(e -> 'percent', 'null'::jsonb), '0'::jsonb));
      v_x := public._os_numero_js(coalesce(nullif(e -> 'expenses_pct', 'null'::jsonb), '0'::jsonb));
      v_val := ((v_lab * v_s / 100 + v_parts * v_p / 100) + v_exp * v_x / 100) * v_ratio;
      if v_val <> 'NaN'::double precision and v_val >= 0.005 then
        return true;
      end if;
    end if;
  end loop;
  return false;
end $$;

-- 3) A situação de UM documento diante da aprovação do conjunto. 'aprovar' = orçamento pendente e não assinado; o resto
--    não muda: 'assinado' (decisão do dono), 'os' (já é OS), 'aprovado' (já aprovado/aguardando sinal), 'reprovado',
--    'fora' (fundido, sem achar).
create or replace function public._conjunto_situacao_para_aprovar(p_os uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when so.id is null or so.merged_into_id is not null or so.status = 'cancelled' then 'fora'
    when so.signed_at is not null
         or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id) then 'assinado'
    when so.status <> 'draft' or so.converted_to_os_at is not null then 'os'
    when so.quote_status = 'rejected' then 'reprovado'
    when coalesce(so.quote_status, 'draft') in ('draft', 'sent', 'awaiting_approval') then 'aprovar'
    else 'aprovado' end
  from (select 1) um
  left join public.service_orders so on so.id = p_os
$$;

-- 4) Aprovar (ou ensaiar) -----------------------------------------------------------------------------------------------
create or replace function public._conjunto_aprovar(p_conjunto uuid, p_ids uuid[], p_ensaio boolean, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_c public.documento_conjuntos;
  v_nome text;
  v_alvo_id uuid;
  v_alvo_num text;
  v_fora uuid;
  v_via text := case when auth.uid() is not null then 'tela' else 'assistente' end;
  v_ensaio boolean := coalesce(p_ensaio, false);
  r record;
  v_sit text;
  v_acao text;
  v_texto text;
  v_depois text;
  v_porta jsonb;
  v_docs jsonb := '[]'::jsonb;
  v_n_os integer := 0;
  v_n_sinal integer := 0;
begin
  if p_autor is null then
    raise exception 'Faça login para aprovar o conjunto.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode aprovar o conjunto.' using errcode = '42501';
  end if;

  if v_ensaio then
    select c.* into v_c from public.documento_conjuntos c where c.id = p_conjunto;
  else
    select c.* into v_c from public.documento_conjuntos c where c.id = p_conjunto for update;
  end if;
  if v_c.id is null then
    raise exception 'Conjunto não encontrado. Recarregue a tela.' using errcode = 'P0002';
  end if;
  if v_c.desfeito_em is not null then
    raise exception 'Este conjunto foi desfeito. Recarregue a tela.' using errcode = '22023';
  end if;
  if p_ids is not null and array_position(p_ids, null) is not null then
    raise exception 'Escolha os orçamentos a aprovar.' using errcode = '22023';
  end if;
  if p_ids is not null then
    select x into v_fora from unnest(p_ids) x
     where not exists (select 1 from public.documento_conjunto_itens i
                        where i.conjunto_id = p_conjunto and i.service_order_id = x and i.ativo)
     limit 1;
    if v_fora is not null then
      raise exception 'Um documento escolhido não está neste conjunto. Recarregue a tela.' using errcode = '22023';
    end if;
  end if;

  -- Trava os documentos do conjunto (na ordem do id: duas telas ao mesmo tempo não se cruzam).
  if not v_ensaio then
    perform 1 from public.service_orders so
      join public.documento_conjunto_itens i on i.service_order_id = so.id
     where i.conjunto_id = p_conjunto and i.ativo
     order by so.id
       for update of so;
    -- O motivo que o histórico grava em cada mudança desta transação.
    perform set_config('marineflow.historico_motivo',
                       left('Aprovado junto com o conjunto ' || coalesce(public._conjunto_nome(p_conjunto), ''), 200), true);
  end if;
  v_nome := public._conjunto_nome(p_conjunto);

  -- A OS-X (5A): a principal, se for OS; senão a 1ª OS da ordem que não é ela mesma complemento; senão a 1ª OS.
  -- Conjunto só de orçamentos: sem marca (PLANO.md, cartão 1).
  select so.id, so.service_order_number into v_alvo_id, v_alvo_num
    from public.documento_conjunto_itens i
    join public.service_orders so on so.id = i.service_order_id
   where i.conjunto_id = p_conjunto and i.ativo
     and so.status not in ('draft', 'cancelled') and so.merged_into_id is null
   order by (so.id = v_c.principal_id) desc, (so.complementa_os_id is null) desc, i.ordem
   limit 1;

  for r in
    select so.id, so.service_order_number as numero, so.vessel_id, so.client_id
      from public.documento_conjunto_itens i
      join public.service_orders so on so.id = i.service_order_id
     where i.conjunto_id = p_conjunto and i.ativo
     order by i.ordem
  loop
    -- Só mesma embarcação e mesmo cliente (o conjunto já garante; a aprovação confere de novo).
    if r.vessel_id is distinct from v_c.vessel_id or r.client_id is distinct from v_c.client_id then
      raise exception '% não é mais do mesmo cliente e embarcação do conjunto. Desfaça o conjunto.', r.numero
        using errcode = '22023';
    end if;
    v_sit := public._conjunto_situacao_para_aprovar(r.id);
    v_depois := r.numero;
    v_acao := 'nao_muda';
    v_texto := case v_sit
      when 'assinado'  then format('%s já foi assinado: não muda.', r.numero)
      when 'os'        then format('%s já é OS: não muda.', r.numero)
      when 'reprovado' then format('%s está como Reprovado: fica de fora.', r.numero)
      when 'aprovado'  then format('%s já foi aprovado: não muda.', r.numero)
      when 'fora'      then format('%s não pode ser aprovado aqui.', r.numero)
      else null end;

    if v_sit = 'aprovar' and p_ids is not null and not (r.id = any(p_ids)) then
      v_texto := format('%s fica como está (não marcado).', r.numero);
    elsif v_sit = 'aprovar' then
      if public._orcamento_tem_sinal(r.id)
         and not exists (select 1 from public.receivables x
                          where x.service_order_id = r.id and coalesce(x.is_deposit, false)
                            and x.status in ('paid', 'partially_paid')) then
        v_acao := 'aguardar_sinal';
        v_n_sinal := v_n_sinal + 1;
        if not v_ensaio then
          update public.service_orders so
             set quote_status = 'awaiting_deposit',
                 complementa_os_id = coalesce(v_alvo_id, so.complementa_os_id)
           where so.id = r.id;
        end if;
        v_texto := format('%s %s: vira OS própria quando o sinal dele for pago.', r.numero,
                          case when v_ensaio then 'fica aprovado' else 'aprovado' end);
      else
        v_acao := 'virar_os';
        v_n_os := v_n_os + 1;
        v_depois := case when r.numero like 'ORÇ-%' then 'OS-' || substr(r.numero, 5) else r.numero end;
        if not v_ensaio then
          update public.service_orders so
             set quote_status = 'approved',
                 complementa_os_id = coalesce(v_alvo_id, so.complementa_os_id)
           where so.id = r.id;
          v_porta := public.os_transicionar_status(r.id, 'approved', v_via, null, p_autor);
          if not coalesce((v_porta ->> 'ok')::boolean, false) then
            raise exception '%', coalesce(nullif(v_porta ->> 'texto', ''), format('Não converti %s em OS.', r.numero))
              using errcode = '22023';
          end if;
          v_depois := coalesce(nullif(v_porta ->> 'numero', ''),
                               (select so.service_order_number from public.service_orders so where so.id = r.id));
          v_texto := format('%s aprovado e convertido: agora é a %s.', r.numero, v_depois);
        else
          v_texto := format('%s vira a %s agora: a condição dele não tem sinal (ou o sinal já foi pago).', r.numero, v_depois);
        end if;
      end if;
      if v_alvo_id is not null then
        v_texto := v_texto || format(' Complementa a %s.', v_alvo_num);
      end if;
    end if;

    v_docs := v_docs || jsonb_build_object('id', r.id, 'numero', r.numero, 'numero_depois', v_depois,
                                           'situacao', v_sit, 'acao', v_acao, 'texto', v_texto);
  end loop;

  if v_n_os + v_n_sinal = 0 and not v_ensaio then
    raise exception 'Nada a aprovar em %: os documentos já estão aprovados, assinados ou não foram marcados.', v_nome
      using errcode = '22023';
  end if;

  return jsonb_build_object(
    'ok', true,
    'ensaio', v_ensaio,
    'conjunto_id', p_conjunto,
    'nome', public._conjunto_nome(p_conjunto),
    'complementa', case when v_alvo_id is null then null
                        else jsonb_build_object('id', v_alvo_id, 'numero', v_alvo_num) end,
    'aprovados', v_n_os + v_n_sinal,
    'viraram_os', v_n_os,
    'aguardando_sinal', v_n_sinal,
    'documentos', v_docs,
    'conjunto', case when v_ensaio then null else public._conjunto_ler(p_conjunto) end
  );
end $$;

create or replace function public.aprovar_conjunto(p_conjunto uuid, p_ids uuid[] default null, p_ensaio boolean default false,
                                                   p_autor uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._conjunto_aprovar(p_conjunto, p_ids, p_ensaio, coalesce(auth.uid(), p_autor));
end $$;

comment on function public.aprovar_conjunto(uuid, uuid[], boolean, uuid) is
  'Agrupar para o cliente (F2): aprova juntos os orçamentos pendentes do conjunto (p_ids nulo = todos). Assinado, OS e já aprovado não mudam. Com sinal na condição: aguardando sinal (vira OS quando o sinal entra); sem sinal: vira OS agora pela porta. Marca complementa_os_id com a OS do conjunto (5A). p_ensaio = true devolve o plano sem gravar. Só admin/financeiro. Tudo ou nada.';

-- 5) A leitura do conjunto ganha, por documento, a marca e se dá para aprovar (o resto igual à F0) ------------------------
create or replace function public._conjunto_ler(p_conjunto uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id,
    'nome', public._conjunto_nome(c.id),
    'ativo', c.desfeito_em is null,
    'criado_em', c.criado_em,
    'desfeito_em', c.desfeito_em,
    'desfeito_motivo', c.desfeito_motivo,
    'client_id', c.client_id,
    'cliente', (select cl.name from public.clients cl where cl.id = c.client_id),
    'vessel_id', c.vessel_id,
    'embarcacao', (select v.name from public.vessels v where v.id = c.vessel_id),
    'principal_id', c.principal_id,
    'total_geral', coalesce((select sum(coalesce(so.grand_total, 0))
                               from public.documento_conjunto_itens i
                               join public.service_orders so on so.id = i.service_order_id
                              where i.conjunto_id = c.id and (i.ativo or c.desfeito_em is not null)), 0),
    'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', so.id,
               'numero', so.service_order_number,
               'tipo', case when so.status = 'draft' then 'orcamento' else 'os' end,
               'status', so.status,
               'quote_status', so.quote_status,
               'principal', so.id = c.principal_id,
               'ativo', i.ativo,
               'assinado', (so.signed_at is not null
                            or exists (select 1 from public.service_order_signatures g where g.service_order_id = so.id)),
               'grand_total', coalesce(so.grand_total, 0),
               'recebido', coalesce((select sum(coalesce(x.paid_amount, 0)) from public.receivables x
                                      where x.service_order_id = so.id and x.status is distinct from 'cancelled'), 0),
               'sinal_a_pagar', coalesce((select sum(greatest(coalesce(x.amount, 0) - coalesce(x.paid_amount, 0), 0))
                                           from public.receivables x
                                          where x.service_order_id = so.id and coalesce(x.is_deposit, false)
                                            and x.status not in ('paid', 'cancelled')), 0),
               'em_aberto', coalesce((select sum(greatest(coalesce(x.amount, 0) - coalesce(x.paid_amount, 0), 0))
                                       from public.receivables x
                                      where x.service_order_id = so.id and x.status not in ('paid', 'cancelled')), 0),
               -- F2
               'complementa_os_id', so.complementa_os_id,
               'complementa_numero', (select x.service_order_number from public.service_orders x
                                       where x.id = so.complementa_os_id),
               'aprovavel', i.ativo and c.desfeito_em is null
                            and public._conjunto_situacao_para_aprovar(so.id) = 'aprovar'
             ) order by i.ordem)
        from public.documento_conjunto_itens i
        join public.service_orders so on so.id = i.service_order_id
       where i.conjunto_id = c.id and (i.ativo or c.desfeito_em is not null)), '[]'::jsonb)
  )
  from public.documento_conjuntos c
  where c.id = p_conjunto
$$;

-- 6) Privilégios + prova ------------------------------------------------------------------------------------------------
revoke all on function public._orcamento_tem_sinal(uuid) from public, anon, authenticated;
revoke all on function public._conjunto_situacao_para_aprovar(uuid) from public, anon, authenticated;
revoke all on function public._conjunto_aprovar(uuid, uuid[], boolean, uuid) from public, anon, authenticated;
revoke all on function public._conjunto_ler(uuid) from public, anon, authenticated;
revoke all on function public.aprovar_conjunto(uuid, uuid[], boolean, uuid) from public, anon;
grant execute on function public._orcamento_tem_sinal(uuid) to service_role;
grant execute on function public._conjunto_situacao_para_aprovar(uuid) to service_role;
grant execute on function public._conjunto_aprovar(uuid, uuid[], boolean, uuid) to service_role;
grant execute on function public._conjunto_ler(uuid) to service_role;
grant execute on function public.aprovar_conjunto(uuid, uuid[], boolean, uuid) to authenticated, service_role;

do $$
declare
  f text;
begin
  foreach f in array array['public._orcamento_tem_sinal(uuid)', 'public._conjunto_situacao_para_aprovar(uuid)',
                           'public._conjunto_aprovar(uuid, uuid[], boolean, uuid)', 'public._conjunto_ler(uuid)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'Privilégio errado: % aberto para anon/authenticated', f;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.aprovar_conjunto(uuid, uuid[], boolean, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.aprovar_conjunto(uuid, uuid[], boolean, uuid)', 'execute') then
    raise exception 'Privilégio errado na porta aprovar_conjunto';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20270129100000', 'agrupar_para_cliente_aprovar')
on conflict do nothing;
