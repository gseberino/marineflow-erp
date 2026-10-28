-- "Fechar juntas" — Fases 0 e 0b, parte do BANCO. 28/10/2026.
--
-- Três decisões do dono (28/10/2026) e um conserto de defeito que já está em produção:
--
-- 1) Chegada no barco CONTA como início de execução (_os_execucao_iniciada): check_in_at ou check_out_at
--    preenchido entra como "chegada no barco registrada". A mesma função serve ao agrupar (cada origem), ao
--    desagrupar (a agrupada), à leitura os_para_agrupar e à guarda do Cancelar da agrupada; por isso uma OS
--    com chegada registrada não agrupa, e uma agrupada que ganhou chegada não desagrupa (cancela como
--    qualquer outra). O aviso "Já houve chegada no barco registrada em ..." de _agrupar_os_montar
--    (20261028120000) fica inalcançável: a origem com chegada é recusada antes. Casos reais que passam a ser
--    recusados: OS-00032, OS-00033 e OS-00076 (chegada de 22/06 e 08/08, aguardando cliente).
--
-- 2) Cadastro GENÉRICO: clients.generico (boolean, padrão falso). É o cadastro sem CPF/CNPJ que junta
--    clientes diferentes ("Cliente Final"). Um cliente genérico nunca entra em agrupamento nem em cobrança
--    conjunta. Aqui no banco:
--      · _os_impedimento_para_agrupar recusa (vale para agrupar_os/_agrupar_os_montar e para o motivo de
--        os_para_agrupar, que usam a mesma função);
--      · _agrupar_orcamentos_montar recusa (antes de gastar o número) e orcamentos_para_agrupar mostra o
--        motivo. Nada mais muda no orçamento: as duas funções são recriadas com o texto de produção
--        (20261015180000 e 20261028120000, conferidos iguais por pg_get_functiondef em 28/10) e só o trecho
--        do genérico a mais;
--      · "Cobrar juntas" (tela e tool cobrar_juntas) lê a coluna e recusa: não há registro no banco na Fase 0.
--    A migration marca SÓ o cadastro "Cliente Final" sem documento, e só se houver exatamente um candidato
--    (em produção, 28/10: id 510a1f14-202a-49f0-855c-3358758cfb5f, 20 OS/orçamentos). Com zero ou mais de um,
--    não marca nenhum e avisa (raise warning): o dono decide.
--
-- 3) Fase 0b, item 1 — OS com nota viva não pode ser cancelada. Caso real: OS-00102, cancelada com a
--    NFS-e nº 5 autorizada. Gatilho BEFORE UPDATE OF status (indo para 'cancelled') em service_orders, irmão de
--    trg_os_agrupada_guarda_destino: recusa quando há nota com origem direta na OS (issued_fiscal_documents
--    origin_type = 'service_order') autorizada ou em processamento (queued/processing), com a mensagem pronta
--    pedindo cancelar a nota antes. Pega todos os caminhos (menu, seletor de situação, cancel_service_order_cascade,
--    assistente, UPDATE direto). Rascunho de nota (draft) não prende: nunca saiu para a prefeitura/SEFAZ.
--    Enquanto nota_os (Fase 3, spec 5.4) não existir, a cobertura é só a origem direta.
--    Agrupar e desagrupar cancelam OS, mas já recusam OS com nota (draft/queued/processing/authorized) antes
--    de cancelar: continuam iguais (tests/agrupar_os.sql, agrupar_orcamentos.sql e
--    agrupar_orcamentos_assistente.sql verdes com esta migration; tests/fechar_juntas_f0.sql prova os dois).
--
-- Fase 0b, item 3 (reabrir OS: não trazer de volta conta cancelada; guarda "pagamento veio do extrato" na
-- tool) não precisa de banco: o defeito mora nos dois caminhos que reabrem (src/lib/cascade-updates.ts e a
-- tool de service-orders.ts), que fazem UPDATE pelo cliente.

-- 1) Cadastro genérico -------------------------------------------------------------------------------------
alter table public.clients
  add column if not exists generico boolean not null default false;

comment on column public.clients.generico is
  'Cadastro genérico, sem CPF/CNPJ, que junta clientes diferentes (ex.: "Cliente Final"). Nunca entra em agrupamento de OS/orçamentos nem em cobrança conjunta ("Cobrar juntas").';

do $$
declare
  v_qtd integer;
  v_id uuid;
begin
  select count(*), (array_agg(c.id))[1] into v_qtd, v_id
    from public.clients c
   where lower(btrim(c.name)) = 'cliente final'
     and nullif(regexp_replace(coalesce(c.cpf_cnpj, ''), '[^0-9]', '', 'g'), '') is null;
  if v_qtd = 1 then
    update public.clients set generico = true where id = v_id and not generico;
    raise notice 'Cadastro genérico marcado: %', v_id;
  else
    raise warning 'Cadastro "Cliente Final" sem documento: % candidatos. Nenhum foi marcado como genérico; o dono decide qual.', v_qtd;
  end if;
end $$;

-- Nome do cadastro se ele é genérico; nulo = cliente comum (ou sem cliente). security definer: as guardas
-- leem o cadastro sem depender da RLS de quem grava.
create or replace function public._cliente_generico(p_cliente uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select c.name from public.clients c where c.id = p_cliente and c.generico
$$;

-- 2) Chegada no barco conta como execução (texto de 20261028120000 + a linha da chegada) -------------------
create or replace function public._os_execucao_iniciada(p_os uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select concat_ws(', ',
    (select case so.status
              when 'in_progress' then 'está em andamento'
              when 'completed' then 'está concluída'
              when 'invoiced' then 'está faturada'
            end
       from public.service_orders so where so.id = p_os),
    -- Decisão do dono (28/10/2026): a chegada no barco registrada (check-in ou check-out) já é execução.
    case when exists (select 1 from public.service_orders so where so.id = p_os
                       and (so.check_in_at is not null or so.check_out_at is not null))
         then 'chegada no barco registrada' end,
    case when exists (select 1 from public.time_entries x where x.service_order_id = p_os) then 'hora apontada' end,
    case when exists (select 1 from public.service_order_expenses x where x.service_order_id = p_os)
           or exists (select 1 from public.service_orders so where so.id = p_os and coalesce(so.operational_cost_total, 0) <> 0)
         then 'despesa lançada' end,
    case when exists (select 1 from public.service_order_steps x
                       where x.service_order_id = p_os
                         and (x.status <> 'pending' or x.started_at is not null or x.completed_at is not null
                              or coalesce(x.actual_minutes, 0) > 0))
         then 'passo do roteiro já iniciado' end,
    -- A situação de campo do serviço (feito, parcial, só levantar, aguarda peça, não feito) é o técnico
    -- dizendo o que fez na linha: execução, como o passo iniciado.
    case when exists (select 1 from public.service_order_services x
                       where x.service_order_id = p_os
                         and (coalesce(x.field_status, 'a_fazer') <> 'a_fazer' or x.started_at is not null
                              or x.finished_at is not null))
         then 'serviço com situação de campo' end,
    case when exists (select 1 from public.service_order_photos x where x.service_order_id = p_os) then 'foto de campo' end,
    case when exists (select 1 from public.inventory_movements m
                       where m.reference_type = 'service_order' and m.reference_id = p_os
                       group by m.product_id
                      having sum(m.quantity_delta) < 0)
         then 'baixa de estoque' end,
    case when exists (select 1 from public.diarias_reembolsos x where x.os_id = p_os) then 'reembolso de diária' end,
    case when exists (select 1 from public.work_shift_os x where x.service_order_id = p_os)
           or exists (select 1 from public.work_shifts x where x.service_order_id = p_os)
         then 'jornada de técnico ligada' end
  )
$$;

-- 3) Cadastro genérico não agrupa OS (texto de 20261028120000 + o genérico, logo depois de "cancelada") ------
create or replace function public._os_impedimento_para_agrupar(p_os uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.service_orders;
  v_destino text;
  v_motivo text;
  v_calc numeric;
begin
  select so.* into r from public.service_orders so where so.id = p_os;
  if r.id is null then
    return 'OS não encontrada. Recarregue a tela.';
  end if;
  if r.merged_into_id is not null then
    select d.service_order_number into v_destino from public.service_orders d where d.id = r.merged_into_id;
    return format('%s já foi agrupada em %s.', r.service_order_number, coalesce(v_destino, 'outra OS'));
  end if;
  if r.status = 'draft' then
    return format('%s ainda é um orçamento (não virou OS). Para juntar orçamentos, use "Agrupar orçamentos".',
                  r.service_order_number);
  end if;
  if r.status = 'cancelled' then
    return format('%s está cancelada e não pode ser agrupada.', r.service_order_number);
  end if;
  -- Cadastro genérico (sem CPF/CNPJ, junta clientes diferentes): nunca entra em agrupamento (28/10/2026).
  v_motivo := public._cliente_generico(r.client_id);
  if v_motivo is not null then
    return format('O cadastro %s é genérico, sem CPF/CNPJ: a %s não entra em agrupamento. Passe a OS para o cadastro do cliente de verdade antes de agrupar.',
                  v_motivo, r.service_order_number);
  end if;
  v_motivo := public._os_execucao_iniciada(p_os);
  if v_motivo <> '' then
    return format('%s já começou a ser executada (%s). Agrupar só junta OS que ainda não começaram; cada OS executada mantém seu histórico.',
                  r.service_order_number, v_motivo);
  end if;
  if r.status not in ('scheduled', 'open', 'awaiting_parts', 'awaiting_client', 'approved') then
    return format('%s está numa situação que não permite agrupar (%s).', r.service_order_number, r.status);
  end if;
  if coalesce(r.card_fee_passthrough_enabled, false) then
    return format('%s repassa a taxa do cartão ao cliente. Desligue o repasse nela antes de agrupar (dá para ligar de novo na OS nova).',
                  r.service_order_number);
  end if;
  v_motivo := public._os_vinculos_que_impedem(p_os);
  if v_motivo <> '' then
    return format('%s tem %s. Uma OS com nota, fatura ou comissão não entra num agrupamento: resolva isso antes ou deixe-a de fora.',
                  r.service_order_number, v_motivo);
  end if;
  select c.grand_total into v_calc from public.calc_so_totals(r.id) c;
  if abs(coalesce(r.grand_total, 0) - coalesce(v_calc, 0)) > 0.005 then
    return format('O total gravado de %s (%s) está desatualizado (o certo é %s). Abra e salve essa OS antes de agrupar.',
                  r.service_order_number, public._agrupar_orcamentos_reais(r.grand_total), public._agrupar_orcamentos_reais(v_calc));
  end if;
  return null;
end $$;

-- 4) Cadastro genérico não agrupa orçamentos (texto de 20261015180000 + o genérico, antes de numerar) -------
create or replace function public._agrupar_orcamentos_montar(
  p_ids uuid[],
  p_base uuid,
  p_numero text,            -- null = gera ORÇ- pelo document_number_seq DEPOIS de validar tudo
  p_autor uuid,
  p_total_esperado numeric  -- soma dos grand_total que a tela mostrou; null = não confere
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_travados uuid[];
  v_ordem uuid[];
  v_numeros text[];
  v_n integer;
  v_base public.service_orders;
  v_desloc public.service_orders;
  r public.service_orders;
  v_destino text;
  v_bloqueios text;
  v_qtd integer;
  v_lista text;
  v_soma_gravada numeric := 0;
  v_soma_base numeric := 0;
  v_calc_total numeric;
  v_calc_base numeric;
  v_validade integer;
  v_seq text;
  v_numero text;
  v_quem text;
  v_novo uuid;
  v_agrupamento uuid;
  v_novo_servico uuid;
  v_mapa jsonb := '{}'::jsonb;
  v_ts timestamptz := clock_timestamp();
  v_total numeric;
  v_motivo text;
  v_generico text;
  n_servicos integer := 0;
  n_pecas integer := 0;
  n_envios integer := 0;
  t_problema text[]; t_escopo text[]; t_interno text[]; t_instrucoes text[]; t_acesso text[]; t_financeiro text[];
  v_desconto numeric; v_imposto numeric; v_subcontrato numeric; v_horas numeric;
  v_desc_serv numeric; v_desc_pecas numeric;
  s record;
  pc record;
begin
  -- 0. Quem pede (a checagem mora aqui também: _montar nunca roda sem cargo)
  if p_autor is null then
    raise exception 'Faça login para agrupar orçamentos.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode agrupar orçamentos.' using errcode = '42501';
  end if;

  -- 1. Entrada
  if p_ids is null or cardinality(p_ids) = 0 or array_position(p_ids, null) is not null then
    raise exception 'Escolha pelo menos 2 orçamentos para agrupar.' using errcode = '22023';
  end if;
  v_ids := array(select distinct x from unnest(p_ids) x);
  if cardinality(v_ids) <> cardinality(p_ids) then
    raise exception 'O mesmo orçamento foi escolhido duas vezes.' using errcode = '22023';
  end if;
  v_n := cardinality(v_ids);
  if v_n < 2 then
    raise exception 'Escolha pelo menos 2 orçamentos para agrupar.' using errcode = '22023';
  end if;
  if v_n > 10 then
    raise exception 'Agrupe no máximo 10 orçamentos de uma vez.' using errcode = '22023';
  end if;

  -- 2. Trava as origens sempre na mesma ordem (dois agrupamentos simultâneos não se travam; o segundo
  --    espera o primeiro e cai em "já foi agrupado")
  select array_agg(t.id) into v_travados
    from (select so.id from public.service_orders so where so.id = any(v_ids) order by so.id for update) t;
  if coalesce(cardinality(v_travados), 0) <> v_n then
    raise exception 'Algum orçamento escolhido não existe mais. Recarregue a tela.' using errcode = 'P0002';
  end if;

  select array_agg(so.id order by so.created_at, so.id),
         array_agg(so.service_order_number order by so.created_at, so.id)
    into v_ordem, v_numeros
    from public.service_orders so where so.id = any(v_ids);

  -- 3. Principal: contato, marina, prioridade, tipo, condições de pagamento e comissão
  if p_base is not null and not (p_base = any(v_ids)) then
    raise exception 'O orçamento principal precisa estar entre os escolhidos.' using errcode = '22023';
  end if;
  select so.* into v_base from public.service_orders so where so.id = coalesce(p_base, v_ordem[1]);

  -- 4. Cada origem
  for r in select so.* from public.service_orders so where so.id = any(v_ids) order by so.created_at, so.id loop
    if r.merged_into_id is not null then
      select d.service_order_number into v_destino from public.service_orders d where d.id = r.merged_into_id;
      raise exception '% já foi agrupado em %.', r.service_order_number, coalesce(v_destino, 'outro orçamento')
        using errcode = '22023';
    end if;
    if r.status <> 'draft' or r.converted_to_os_at is not null then
      raise exception '% não é mais um orçamento em aberto (já virou OS ou foi cancelado).', r.service_order_number
        using errcode = '22023';
    end if;
    if r.quote_status = 'rejected' then
      raise exception '% está como Reprovado. Volte-o para Em elaboração antes de agrupar, ou deixe-o de fora.', r.service_order_number
        using errcode = '22023';
    end if;
    if r.client_id <> v_base.client_id then
      raise exception 'Só dá para agrupar orçamentos do mesmo cliente (% é de outro cliente).', r.service_order_number
        using errcode = '22023';
    end if;
    if r.vessel_id <> v_base.vessel_id then
      raise exception 'Só dá para agrupar orçamentos da mesma embarcação (% é de outra). Um orçamento tem uma embarcação só.',
        r.service_order_number using errcode = '22023';
    end if;
    -- Cadastro genérico (sem CPF/CNPJ): nunca entra em agrupamento (28/10/2026). Antes do número: não gasta o seq.
    v_generico := public._cliente_generico(r.client_id);
    if v_generico is not null then
      raise exception 'O cadastro % é genérico, sem CPF/CNPJ: o % não entra em agrupamento. Passe o orçamento para o cadastro do cliente de verdade antes de agrupar.',
        v_generico, r.service_order_number using errcode = '22023';
    end if;
    if r.signed_at is not null
       or exists (select 1 from public.service_order_signatures g where g.service_order_id = r.id) then
      raise exception '% já foi assinado pelo cliente e não pode ser agrupado. Converta-o em OS ou deixe-o fora do agrupamento.',
        r.service_order_number using errcode = '22023';
    end if;
    if coalesce(r.card_fee_passthrough_enabled, false) then
      raise exception '% repassa a taxa do cartão ao cliente. Desligue o repasse nele antes de agrupar (dá para ligar de novo no orçamento novo).',
        r.service_order_number using errcode = '22023';
    end if;

    v_bloqueios := public._orcamento_vinculos_que_prendem(r.id);
    if v_bloqueios <> '' then
      raise exception '% está ligado a: %. Resolva isso antes de agrupar.', r.service_order_number, v_bloqueios
        using errcode = '22023';
    end if;

    select c.grand_total, c.base into v_calc_total, v_calc_base from public.calc_so_totals(r.id) c;
    if abs(coalesce(r.grand_total, 0) - coalesce(v_calc_total, 0)) > 0.005 then
      raise exception 'O total gravado de % (%) está desatualizado (o certo é %). Abra e salve esse orçamento antes de agrupar.',
        r.service_order_number, public._agrupar_orcamentos_reais(r.grand_total),
        public._agrupar_orcamentos_reais(v_calc_total) using errcode = '22023';
    end if;
    v_soma_gravada := v_soma_gravada + coalesce(r.grand_total, 0);
    v_soma_base := v_soma_base + coalesce(v_calc_base, 0);
  end loop;

  -- 5. Deslocamento: no máximo um (somar cobraria a viagem duas vezes)
  select count(*), string_agg(so.service_order_number, ', ' order by so.created_at, so.id)
    into v_qtd, v_lista
    from public.service_orders so
   where so.id = any(v_ids)
     and (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
          or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0);
  if v_qtd > 1 then
    raise exception 'Mais de um orçamento tem deslocamento (%). Deixe o deslocamento em um só antes de agrupar, para não cobrar a viagem duas vezes.',
      v_lista using errcode = '22023';
  end if;
  select so.* into v_desloc from public.service_orders so
   where so.id = any(v_ids)
     and (coalesce(so.travel_cost_total, 0) <> 0 or coalesce(so.travel_distance_km, 0) <> 0
          or coalesce(so.travel_hours, 0) <> 0 or coalesce(so.ferry_cost, 0) <> 0)
   limit 1;   -- nenhum: campos nulos -> padrões abaixo

  if p_total_esperado is not null and round(p_total_esperado, 2) <> round(v_soma_gravada, 2) then
    raise exception 'Os orçamentos mudaram desde que a tela abriu (soma agora %). Feche e abra o agrupamento de novo.',
      public._agrupar_orcamentos_reais(v_soma_gravada) using errcode = '22023';
  end if;

  -- 6. Cabeçalho do novo
  select array_agg(so.problem_description order by so.created_at, so.id),
         array_agg(so.extra_notes order by so.created_at, so.id),
         array_agg(so.internal_notes order by so.created_at, so.id),
         array_agg(so.technician_instructions order by so.created_at, so.id),
         array_agg(so.site_access order by so.created_at, so.id),
         array_agg(so.financial_notes order by so.created_at, so.id),
         sum(coalesce(so.discount_amount, 0)), sum(coalesce(so.tax_amount, 0)),
         sum(coalesce(so.subcontract_cost_total, 0)), sum(coalesce(so.estimated_hours, 0)),
         -- Rótulo do desconto em lote no PDF (pct × total da categoria): só copia se for igual em todos
         -- E todos (ou nenhum) tiverem desconto no cabeçalho; senão o detalhe sairia incoerente.
         case when count(distinct so.discount_services_pct) = 1
                   and (bool_and(coalesce(so.discount_amount, 0) > 0) or bool_and(coalesce(so.discount_amount, 0) = 0))
              then max(so.discount_services_pct) else 0 end,
         case when count(distinct so.discount_parts_pct) = 1
                   and (bool_and(coalesce(so.discount_amount, 0) > 0) or bool_and(coalesce(so.discount_amount, 0) = 0))
              then max(so.discount_parts_pct) else 0 end
    into t_problema, t_escopo, t_interno, t_instrucoes, t_acesso, t_financeiro,
         v_desconto, v_imposto, v_subcontrato, v_horas, v_desc_serv, v_desc_pecas
    from public.service_orders so where so.id = any(v_ids);

  select case when s2.value ~ '^\s*\d{1,3}\s*$' and btrim(s2.value)::int between 1 and 365 then btrim(s2.value)::int end
    into v_validade from public.app_settings s2 where s2.key = 'quote_validity_days';
  select u.full_name into v_quem from public.app_users u where u.id = p_autor;

  if p_numero is not null then
    v_numero := p_numero;
  else
    v_seq := public.next_document_number()::text;            -- só depois de tudo validado
    v_numero := 'ORÇ-' || lpad(v_seq, greatest(5, length(v_seq)), '0');
  end if;

  insert into public.service_orders (
    service_order_number, client_id, vessel_id, marina_id, requested_by_contact_id, requested_by_name,
    status, quote_status, priority, service_type, currency,
    problem_description, extra_notes, internal_notes, technician_instructions, site_access, financial_notes,
    hourly_rate, estimated_hours,
    travel_distance_km, travel_cost_per_km, technician_count_for_travel, travel_hours, ferry_cost,
    travel_type, is_travel_billable, travel_cost_total,
    subcontract_cost_total, operational_cost_total, discount_amount, tax_amount,
    discount_services_pct, discount_parts_pct,
    payment_conditions, payment_condition_preset_id, payment_method, payment_method_preferred,
    card_installments, custom_payment_installments, card_fee_passthrough_enabled,
    customer_po_number, customer_buyer_name,
    commission_rate, commissioned_user_id, commissioned_person,
    quote_validity_days, quote_validity_date, created_by
  ) values (
    v_numero, v_base.client_id, v_base.vessel_id, v_base.marina_id, v_base.requested_by_contact_id, v_base.requested_by_name,
    'draft', 'draft', coalesce(v_base.priority, 'normal'), v_base.service_type, coalesce(v_base.currency, 'BRL'),
    coalesce(public._agrupar_orcamentos_juntar(v_numeros, t_problema), 'Orçamento que reúne ' || array_to_string(v_numeros, ', ')),
    public._agrupar_orcamentos_juntar(v_numeros, t_escopo),
    concat_ws(E'\n\n',
      'Reúne ' || array_to_string(v_numeros, ', ') || ' — agrupados em '
        || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ' por ' || coalesce(v_quem, 'sistema')
        || '. Preços mantidos como estavam em cada orçamento. Condições de pagamento e comissão vêm do '
        || v_base.service_order_number || '.',
      public._agrupar_orcamentos_juntar(v_numeros, t_interno)),
    public._agrupar_orcamentos_juntar(v_numeros, t_instrucoes),
    public._agrupar_orcamentos_juntar(v_numeros, t_acesso),
    public._agrupar_orcamentos_juntar(v_numeros, t_financeiro),
    v_base.hourly_rate, v_horas,
    coalesce(v_desloc.travel_distance_km, 0), coalesce(v_desloc.travel_cost_per_km, 0),
    coalesce(v_desloc.technician_count_for_travel, 1), coalesce(v_desloc.travel_hours, 0), coalesce(v_desloc.ferry_cost, 0),
    coalesce(v_desloc.travel_type, 'comercial'), coalesce(v_desloc.is_travel_billable, true), coalesce(v_desloc.travel_cost_total, 0),
    v_subcontrato, 0, v_desconto, v_imposto,
    coalesce(v_desc_serv, 0), coalesce(v_desc_pecas, 0),
    v_base.payment_conditions, v_base.payment_condition_preset_id, v_base.payment_method, v_base.payment_method_preferred,
    coalesce(v_base.card_installments, 1), v_base.custom_payment_installments, false,
    v_base.customer_po_number, v_base.customer_buyer_name,
    coalesce(v_base.commission_rate, 0), v_base.commissioned_user_id, v_base.commissioned_person,
    coalesce(v_validade, 15), null, p_autor
  )
  returning id into v_novo;

  -- 7. Serviços: TODAS as colunas de composição (desconto, sistema/verbo/verbo fiscal, garantia,
  --    instruções). Fora: execução (started/finished/elapsed, field_status). created_at em sequência
  --    explícita: as telas ordenam por created_at e now() empataria tudo.
  for s in
    select x.*, o.ord
      from public.service_order_services x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.created_at nulls first, x.id
  loop
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_services (
      service_order_id, service_id, name_snapshot, description_snapshot, billing_unit_snapshot,
      quantity, unit_price_snapshot, line_total, discount_pct, discount_amount, notes,
      technician_user_id, warranty_days, warranty_months,
      service_system, service_verb, fiscal_verb, technician_instructions, created_at, updated_at
    ) values (
      v_novo, s.service_id, s.name_snapshot, s.description_snapshot, s.billing_unit_snapshot,
      s.quantity, s.unit_price_snapshot, s.line_total, s.discount_pct, s.discount_amount, s.notes,
      s.technician_user_id, s.warranty_days, s.warranty_months,
      s.service_system, s.service_verb, s.fiscal_verb, s.technician_instructions, v_ts, v_ts
    )
    returning id into v_novo_servico;
    v_mapa := v_mapa || jsonb_build_object(s.id::text, v_novo_servico);
    n_servicos := n_servicos + 1;
  end loop;

  -- 8. Peças: idem + source e o vínculo peça->serviço (kit) remapeado para a linha nova
  for pc in
    select x.*, o.ord
      from public.service_order_parts x
      join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = x.service_order_id
     order by o.ord, x.created_at nulls first, x.id
  loop
    v_ts := v_ts + interval '1 millisecond';
    insert into public.service_order_parts (
      service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, currency_snapshot,
      line_total_cost, line_total_sale, discount_pct, discount_amount, notes,
      warranty_days, warranty_months, serial_number, source, service_order_service_id, created_at, updated_at
    ) values (
      v_novo, pc.product_id, pc.quantity, pc.unit_cost_snapshot, pc.unit_sale_snapshot, pc.currency_snapshot,
      pc.line_total_cost, pc.line_total_sale, pc.discount_pct, pc.discount_amount, pc.notes,
      pc.warranty_days, pc.warranty_months, pc.serial_number, pc.source,
      nullif(v_mapa ->> (pc.service_order_service_id::text), '')::uuid, v_ts, v_ts
    );
    n_pecas := n_pecas + 1;
  end loop;

  -- 9. Totais pelo banco + comissão do principal sobre o total novo (mesma fórmula da tela,
  --    financial-section.tsx: taxa × total / 100)
  perform public.recalc_so_totals(v_novo);
  update public.service_orders so
     set commission_amount = case when coalesce(so.commission_rate, 0) > 0
                                  then round(coalesce(so.grand_total, 0) * so.commission_rate / 100, 2) else 0 end
   where so.id = v_novo
  returning so.grand_total into v_total;

  -- 10. Conferência dura: linhas e somas copiadas sem perda => fecha ao centavo (tolerância só para o
  --     arredondamento de cada origem a 2 casas; hoje todos os valores já têm 2 casas)
  if v_total is null or abs(v_total - round(v_soma_base, 2)) > 0.005 * v_n then
    raise exception 'Conferência falhou: o orçamento agrupado deu % e a soma dos originais é %. Nada foi gravado.',
      public._agrupar_orcamentos_reais(v_total), public._agrupar_orcamentos_reais(v_soma_base);
  end if;

  -- 11. Histórico do agrupamento (o "antes" de cada origem, para o desagrupar)
  insert into public.orcamento_agrupamentos (agrupado_id, criado_por) values (v_novo, p_autor)
  returning id into v_agrupamento;
  insert into public.orcamento_agrupamento_origens (
    agrupamento_id, origem_id, ordem, numero, quote_status_antes, share_token_antes,
    cancelled_at_antes, cancellation_reason_antes, grand_total_antes
  )
  select v_agrupamento, so.id, o.ord, so.service_order_number, so.quote_status, so.share_token,
         so.cancelled_at, so.cancellation_reason, so.grand_total
    from public.service_orders so
    join unnest(v_ordem) with ordinality as o(so_id, ord) on o.so_id = so.id;

  -- 12. Auditoria (antes de mudar as origens, para guardar o "antes")
  v_motivo := 'Agrupado em ' || v_numero || ' (reúne ' || array_to_string(v_numeros, ', ') || ')';
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason,
                                triggered_by_table, triggered_by_id)
  select 'service_orders', so.id, 'cancel', coalesce(v_quem, 'sistema'),
         jsonb_build_object('status', so.status, 'quote_status', so.quote_status, 'grand_total', so.grand_total),
         jsonb_build_object('status', 'cancelled', 'quote_status', 'draft', 'merged_into_id', v_novo,
                            'merged_into_number', v_numero, 'link_publico', 'desligado'),
         v_motivo, 'service_orders', v_novo
    from public.service_orders so where so.id = any(v_ids);
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_novo, 'update', coalesce(v_quem, 'sistema'), null,
          jsonb_build_object('agrupa', to_jsonb(v_numeros), 'origens', to_jsonb(v_ordem), 'grand_total', v_total,
                             'principal', v_base.service_order_number),
          'Criado agrupando ' || array_to_string(v_numeros, ', '));

  -- 13. Origens: histórico, link morto, apontando para o novo
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  update public.service_orders so
     set status = 'cancelled',
         quote_status = 'draft',
         cancelled_at = now(),
         cancellation_reason = v_motivo,
         share_token = null,
         merged_into_id = v_novo
   where so.id = any(v_ids);
  perform set_config('marineflow.agrupar_orcamentos', '', true);

  -- 14. Envios agendados com o link antigo
  update public.whatsapp_scheduled_sends w
     set status = 'cancelled', last_error = 'Cancelado: orçamento agrupado em ' || v_numero, updated_at = now()
   where w.service_order_id = any(v_ids) and w.status in ('pending', 'processing');
  get diagnostics n_envios = row_count;

  return jsonb_build_object(
    'service_order_id', v_novo, 'numero', v_numero, 'agrupamento_id', v_agrupamento,
    'origens', to_jsonb(v_numeros), 'principal', v_base.service_order_number,
    'servicos', n_servicos, 'pecas', n_pecas, 'envios_cancelados', n_envios, 'total_geral', v_total,
    'comissao', (select so.commission_amount from public.service_orders so where so.id = v_novo));
end $$;

-- 5) Leitura de orçamentos mostra o motivo do genérico (texto de 20261028120000 + o genérico em o.outro) ----
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
  -- _agrupar_orcamentos_montar: reprovado, cadastro genérico, assinado, repasse do cartão, vínculos, total
  -- desatualizado.
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
                   when coalesce(c.generico, false)
                     then format('o cadastro %s é genérico, sem CPF/CNPJ: não entra em agrupamento', c.name)
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
         and g.tipo = 'orcamento'
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

-- 6) OS com nota viva não é cancelada (Fase 0b, item 1) ------------------------------------------------------
--    Nota viva = origem direta na OS, autorizada ou em processamento. A mensagem diz qual nota e o que fazer.
--    Não respeita o atalho marineflow.agrupar_orcamentos: agrupar/desagrupar já recusam OS com nota antes.
create or replace function public._os_nota_viva_nao_cancela()
returns trigger
language plpgsql
security definer   -- lê as notas sem depender da RLS de quem cancela
set search_path = ''
as $$
declare
  v_notas text;
  v_qtd integer;
  v_processando boolean;
  v_orcamento boolean := old.status = 'draft' and old.converted_to_os_at is null;
begin
  select string_agg('a '
                    || case d.document_type when 'nfse' then 'NFS-e' when 'nfe' then 'NF-e' when 'nfce' then 'NFC-e'
                         else upper(d.document_type) end
                    || case when d.number is not null then ' nº ' || d.number::text else '' end
                    || case when d.status = 'authorized' then ' autorizada' else ' em processamento' end,
                    ', ' order by d.created_at, d.id),
         count(*),
         coalesce(bool_or(d.status <> 'authorized'), false)
    into v_notas, v_qtd, v_processando
    from public.issued_fiscal_documents d
   where d.origin_type = 'service_order'
     and d.origin_id = new.id
     and d.status in ('queued', 'processing', 'authorized');
  if v_qtd = 0 then
    return new;
  end if;
  if v_processando then
    raise exception '% % tem %: espere a nota terminar de processar e, se sair autorizada, cancele-a antes de cancelar %.',
      case when v_orcamento then 'O' else 'A' end, old.service_order_number, v_notas,
      case when v_orcamento then 'o orçamento' else 'a OS' end
      using errcode = '22023';
  end if;
  raise exception '% % tem %: cancele % antes de cancelar % (o cancelamento da nota tem prazo).',
    case when v_orcamento then 'O' else 'A' end, old.service_order_number, v_notas,
    case when v_qtd > 1 then 'as notas' else 'a nota' end,
    case when v_orcamento then 'o orçamento' else 'a OS' end
    using errcode = '22023';
end $$;

drop trigger if exists trg_os_nota_viva_nao_cancela on public.service_orders;
create trigger trg_os_nota_viva_nao_cancela
  before update of status on public.service_orders
  for each row when (new.status = 'cancelled' and old.status is distinct from 'cancelled')
  execute function public._os_nota_viva_nao_cancela();

-- 7) Privilégios + prova ---------------------------------------------------------------------------------------
-- Funções novas: só o dono e o service role. As recriadas guardam os privilégios de antes (create or replace);
-- os revokes abaixo só reafirmam.
revoke all on function public._cliente_generico(uuid) from public, anon, authenticated;
revoke all on function public._os_nota_viva_nao_cancela() from public, anon, authenticated;
grant execute on function public._cliente_generico(uuid) to service_role;
revoke all on function public._os_execucao_iniciada(uuid) from public, anon, authenticated;
revoke all on function public._os_impedimento_para_agrupar(uuid) from public, anon, authenticated;
revoke all on function public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[]) from public, anon;

do $$
declare
  v_f text;
begin
  foreach v_f in array array['public._cliente_generico(uuid)', 'public._os_nota_viva_nao_cancela()',
                             'public._os_execucao_iniciada(uuid)', 'public._os_impedimento_para_agrupar(uuid)',
                             'public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'Privilégios errados em fechar juntas (F0): % executável por anon/authenticated', v_f;
    end if;
  end loop;
  if not has_function_privilege('service_role', 'public._cliente_generico(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)', 'execute')
     or has_function_privilege('anon', 'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])', 'execute')
     or not has_function_privilege('authenticated', 'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])', 'execute')
     or (select p.provolatile from pg_proc p where p.oid = 'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])'::regprocedure) <> 's'
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'public.service_orders'::regclass
                      and t.tgname = 'trg_os_nota_viva_nao_cancela' and t.tgenabled = 'O')
  then
    raise exception 'Privilégios ou gatilho errados em fechar juntas (F0)';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20261028190000', 'fechar_juntas_f0')
on conflict do nothing;
