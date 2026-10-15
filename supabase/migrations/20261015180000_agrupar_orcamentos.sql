-- Agrupar orçamentos (e desagrupar).
--
-- Caso real: o cliente aprova vários orçamentos juntos e pede UM orçamento atualizado. Hoje cada um vira
-- uma OS separada (12 pares do mesmo cliente convertidos com menos de 24 h entre si) ou o agrupamento é
-- feito à mão ("ORÇ-00090 — consolidado em ORÇ-00091").
--
-- agrupar_orcamentos: N orçamentos abertos do MESMO cliente e da MESMA embarcação viram UM orçamento novo
-- (ORÇ, rascunho, validade nova), numa transação só. Preços: os de cada orçamento (snapshot da linha).
-- Condição de pagamento, contato e comissão vêm do orçamento PRINCIPAL; a comissão é recalculada sobre o
-- total novo. Total do novo = soma dos originais, conferido ao centavo no fim (senão nada é gravado).
-- Os originais NÃO são apagados: ficam cancelados como histórico, com o link público desligado
-- (share_token nulo: o cliente não assina a versão velha) e apontando para o novo (merged_into_id).
-- Nada de dinheiro, nota, compra, despesa ou assinatura pode estar preso aos originais: a função recusa.
--
-- desagrupar_orcamentos: desfaz enquanto o agrupado ainda é um orçamento em aberto (não virou OS, não foi
-- assinado, sem dinheiro/nota ligados). Os originais voltam exatamente como estavam (situação, link e os
-- envios agendados que o agrupar cancelou, se a hora deles não passou); o agrupado fica cancelado como
-- histórico e não pode ser reaberto. O que foi editado no agrupado NÃO volta para os originais.
-- Enquanto dá para desagrupar, cancelar o agrupado pelo caminho normal é recusado (desagrupe primeiro);
-- depois de virar OS ou ser assinado, ele cancela como qualquer outro e os originais ficam como histórico.
--
-- Auditoria usa ações que já existem ('cancel', 'reopen', 'update'); a lista de ações não muda.

-- 1) Vínculo origem -> agrupado ---------------------------------------------------------------------------
alter table public.service_orders
  add column if not exists merged_into_id uuid
  constraint service_orders_merged_into_id_fkey references public.service_orders(id) on delete restrict;

comment on column public.service_orders.merged_into_id is
  'Só nas origens de um agrupamento ativo: o orçamento que as reúne (agrupar_orcamentos). Gravado e limpo só por agrupar_orcamentos / desagrupar_orcamentos.';

create index if not exists service_orders_merged_into_id_idx
  on public.service_orders (merged_into_id) where merged_into_id is not null;

-- 2) Histórico do agrupamento (guarda o "antes" de cada origem para o desagrupar) --------------------------
create table if not exists public.orcamento_agrupamentos (
  id uuid primary key default gen_random_uuid(),
  agrupado_id uuid not null
    constraint orcamento_agrupamentos_agrupado_id_fkey references public.service_orders(id) on delete restrict,
  criado_por uuid,
  criado_em timestamptz not null default now(),
  desfeito_em timestamptz,
  desfeito_por uuid
);

comment on table public.orcamento_agrupamentos is
  'Cada agrupamento de orçamentos (agrupar_orcamentos). desfeito_em preenchido = desagrupado. Escrita só pelas funções.';

create unique index if not exists orcamento_agrupamentos_ativo_uidx
  on public.orcamento_agrupamentos (agrupado_id) where desfeito_em is null;

create table if not exists public.orcamento_agrupamento_origens (
  agrupamento_id uuid not null
    constraint orcamento_agrupamento_origens_agrupamento_id_fkey references public.orcamento_agrupamentos(id) on delete cascade,
  origem_id uuid not null
    constraint orcamento_agrupamento_origens_origem_id_fkey references public.service_orders(id) on delete cascade,
  ordem integer not null,
  numero text not null,
  quote_status_antes text,
  share_token_antes uuid,
  cancelled_at_antes timestamptz,
  cancellation_reason_antes text,
  grand_total_antes numeric,
  primary key (agrupamento_id, origem_id)
);

create index if not exists orcamento_agrupamento_origens_origem_idx on public.orcamento_agrupamento_origens (origem_id);

alter table public.orcamento_agrupamentos enable row level security;
alter table public.orcamento_agrupamento_origens enable row level security;

drop policy if exists orcamento_agrupamentos_select on public.orcamento_agrupamentos;
drop policy if exists orcamento_agrupamento_origens_select on public.orcamento_agrupamento_origens;
-- (select auth.uid()): avaliado uma vez por consulta, não linha a linha (padrão rls_auth_uid_uma_vez_por_consulta)
create policy orcamento_agrupamentos_select on public.orcamento_agrupamentos
  for select to authenticated using ((select auth.uid()) is not null);
create policy orcamento_agrupamento_origens_select on public.orcamento_agrupamento_origens
  for select to authenticated using ((select auth.uid()) is not null);

revoke all on public.orcamento_agrupamentos from public, anon, authenticated;
revoke all on public.orcamento_agrupamento_origens from public, anon, authenticated;
grant select on public.orcamento_agrupamentos to authenticated;
grant select on public.orcamento_agrupamento_origens to authenticated;
grant all on public.orcamento_agrupamentos to service_role;
grant all on public.orcamento_agrupamento_origens to service_role;

-- 3) Guarda: ninguém nasce agrupado; só as funções ligam/desligam a marca; origem agrupada não muda de
--    situação, link, cliente ou embarcação, nem é apagada (formulário velho com autosave manda status='draft';
--    assinatura/conversão tardias). O sinal tardio não muda nenhuma dessas colunas na origem cancelada: quem
--    o barra é a guarda 3c, no recebível. A RLS deixa qualquer usuário logado gravar a coluna: só o gatilho
--    garante a regra.
create or replace function public._orcamento_agrupado_guarda()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_destino text;
  v_liberado boolean := coalesce(current_setting('marineflow.agrupar_orcamentos', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    -- O "Duplicar" (tela e assistente) copia o cabeçalho com spread: a cópia nasceria travada.
    new.merged_into_id := null;
    return new;
  end if;

  if v_liberado then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'UPDATE' and new.merged_into_id is distinct from old.merged_into_id then
    raise exception 'Só as funções Agrupar/Desagrupar orçamentos mudam o vínculo de agrupamento.'
      using errcode = '42501';
  end if;

  -- Daqui em diante OLD é origem de um agrupamento ativo: histórico.
  select d.service_order_number into v_destino from public.service_orders d where d.id = old.merged_into_id;
  if tg_op = 'DELETE' then
    raise exception 'Este orçamento foi agrupado em % e fica guardado como histórico: não pode ser apagado.',
      coalesce(v_destino, 'outro orçamento') using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     or new.quote_status is distinct from old.quote_status
     or new.share_token is distinct from old.share_token
     or new.converted_to_os_at is distinct from old.converted_to_os_at
     or new.signed_at is distinct from old.signed_at
     or new.client_id is distinct from old.client_id
     or new.vessel_id is distinct from old.vessel_id then
    raise exception 'Este orçamento foi agrupado em % e não pode mais mudar de situação, link, cliente ou embarcação. Para mexer nele, desagrupe %.',
      coalesce(v_destino, 'outro orçamento'), coalesce(v_destino, 'o agrupado') using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_orcamento_agrupado_guarda_ins on public.service_orders;
drop trigger if exists trg_orcamento_agrupado_guarda_upd on public.service_orders;
drop trigger if exists trg_orcamento_agrupado_guarda_del on public.service_orders;

create trigger trg_orcamento_agrupado_guarda_ins
  before insert on public.service_orders
  for each row when (new.merged_into_id is not null)
  execute function public._orcamento_agrupado_guarda();

create trigger trg_orcamento_agrupado_guarda_upd
  before update on public.service_orders
  for each row when (old.merged_into_id is not null or new.merged_into_id is not null)
  execute function public._orcamento_agrupado_guarda();

create trigger trg_orcamento_agrupado_guarda_del
  before delete on public.service_orders
  for each row when (old.merged_into_id is not null)
  execute function public._orcamento_agrupado_guarda();

-- 3b) Guarda do AGRUPADO.
--   · Cancelar pelo caminho normal (menu Cancelar, seletor de status, cancel_service_order_cascade,
--     assistente) ENQUANTO ele ainda pode ser desagrupado (rascunho, não convertido, não assinado) deixaria
--     os originais cancelados para sempre, porque o desagrupar exige o agrupado em aberto: recusado,
--     desagrupe primeiro. Depois de virar OS ou ser assinado o desagrupar já não é possível: cancelar segue
--     o caminho normal (a OS cancela como qualquer outra) e os originais ficam como histórico.
--   · Reabrir um agrupado JÁ DESAGRUPADO (aba velha com autosave mandando status='draft', seletor de status)
--     faria o mesmo serviço valer duas vezes — ele e os originais, que voltaram: recusado, fica histórico.
--   security definer: só LÊ o histórico e as assinaturas; o resultado não pode depender da RLS de quem
--   grava (técnico, anon de link público), nem quebrar por falta de SELECT nessas tabelas.
create or replace function public._orcamento_agrupado_guarda_destino()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_origens text;
begin
  if coalesce(current_setting('marineflow.agrupar_orcamentos', true), '') = 'on' then
    return new;
  end if;

  if new.status = 'cancelled' then
    -- O WHEN já garante: saindo de rascunho, não convertido, sem signed_at. Falta a assinatura gravada
    -- só na tabela (a mesma regra do desagrupar).
    if exists (select 1 from public.service_order_signatures s where s.service_order_id = new.id) then
      return new;
    end if;
    select string_agg(x.numero, ', ' order by x.ordem) into v_origens
      from public.orcamento_agrupamentos g
      join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
     where g.agrupado_id = new.id and g.desfeito_em is null;
    if v_origens is not null then
      raise exception 'Este orçamento reúne %. Para cancelá-lo, use "Desagrupar" primeiro: os originais voltam a valer e depois você decide o que fazer com eles.',
        v_origens using errcode = '42501';
    end if;
    return new;
  end if;

  -- Saindo de cancelado: agrupado já desfeito não volta
  select string_agg(x.numero, ', ' order by x.ordem) into v_origens
    from public.orcamento_agrupamentos g
    join public.orcamento_agrupamento_origens x on x.agrupamento_id = g.id
   where g.agrupado_id = old.id and g.desfeito_em is not null;
  if v_origens is not null then
    raise exception 'Este orçamento foi desagrupado (os originais % voltaram a valer) e fica como histórico: não pode ser reaberto. Para juntar de novo, agrupe os originais.',
      v_origens using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_orcamento_agrupado_guarda_destino on public.service_orders;
create trigger trg_orcamento_agrupado_guarda_destino
  before update of status on public.service_orders
  for each row when (
    (new.status = 'cancelled' and old.status = 'draft' and old.converted_to_os_at is null and old.signed_at is null)
    or (old.status = 'cancelled' and new.status is distinct from 'cancelled'))
  execute function public._orcamento_agrupado_guarda_destino();

-- 3c) Dinheiro numa ORIGEM agrupada. O sinal tardio (register_deposit_and_convert, approve_quote_full,
--     conciliação do assistente com tipo quote_deposit) não muda nenhuma coluna travada da origem cancelada
--     — o status só vira 'open' a partir de rascunho —, então a guarda 3 não o vê e o dinheiro ficaria preso
--     no histórico. O recebível é o primeiro registro que esses caminhos gravam: recusar aqui desfaz o resto
--     (pagamento, parcelas, cobranças) na mesma transação, e a mensagem diz onde lançar.
create or replace function public._orcamento_agrupado_sem_dinheiro()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_destino text;
begin
  if tg_op = 'UPDATE' then
    -- Só mudar o vínculo conta; editar um recebível antigo que já era da origem (ex.: cancelado) passa.
    if new.service_order_id is not distinct from old.service_order_id then
      return new;
    end if;
  end if;
  select d.service_order_number into v_destino
    from public.service_orders o
    join public.service_orders d on d.id = o.merged_into_id
   where o.id = new.service_order_id;
  if v_destino is not null then
    raise exception 'Este orçamento foi agrupado em %: lance o sinal ou o recebimento no %.', v_destino, v_destino
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_receivables_origem_agrupada on public.receivables;
create trigger trg_receivables_origem_agrupada
  before insert or update of service_order_id on public.receivables
  for each row when (new.service_order_id is not null)
  execute function public._orcamento_agrupado_sem_dinheiro();

-- 4) Texto: igual em todos -> uma vez; diferentes -> um bloco por orçamento, com o número -------------------
create or replace function public._agrupar_orcamentos_juntar(p_numeros text[], p_textos text[])
returns text
language sql
immutable
set search_path = ''
as $$
  with t as (
    select u.numero, nullif(btrim(u.texto), '') as texto, u.i
      from unnest(p_numeros, p_textos) with ordinality as u(numero, texto, i)
  )
  select case (select count(distinct t.texto) from t)
           when 0 then null
           when 1 then (select t.texto from t where t.texto is not null order by t.i limit 1)
           else (select string_agg('[' || t.numero || ']' || E'\n' || t.texto, E'\n\n' order by t.i)
                   from t where t.texto is not null)
         end
$$;

-- 4b) Valor em reais para as mensagens que a tela mostra como estão: 1400 -> 'R$ 1.400,00' -----------------
create or replace function public._agrupar_orcamentos_reais(p_valor numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'R$ ' || translate(to_char(round(coalesce(p_valor, 0), 2), 'FM999,999,999,990.00'), ',.', '.,')
$$;

-- 5) O que prende um orçamento (dinheiro, nota, compra, despesa). Vazio = livre. -----------------------------
create or replace function public._orcamento_vinculos_que_prendem(p_os uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select concat_ws(', ',
    case when exists (select 1 from public.receivables x where x.service_order_id = p_os and x.status is distinct from 'cancelled') then 'conta a receber/sinal' end,
    case when exists (select 1 from public.collections x where x.service_order_id = p_os and x.status is distinct from 'cancelled') then 'cobrança' end,
    case when exists (select 1 from public.bank_charges x where x.service_order_id = p_os and coalesce(x.status, '') not in ('cancelled', 'failed')) then 'boleto/Pix de cobrança' end,
    case when exists (select 1 from public.bank_transactions x where x.reconciled_service_order_id = p_os) then 'lançamento do extrato conciliado' end,
    case when exists (select 1 from public.invoices x where x.service_order_id = p_os) then 'fatura' end,
    case when exists (select 1 from public.commissions x where x.service_order_id = p_os) then 'comissão lançada' end,
    case when exists (select 1 from public.comprovantes x where x.destino_os_id = p_os) then 'comprovante' end,
    case when exists (select 1 from public.payables x where x.linked_service_order_id = p_os and x.status is distinct from 'cancelled') then 'conta a pagar ligada' end,
    case when exists (select 1 from public.issued_fiscal_documents x where x.origin_type = 'service_order' and x.origin_id = p_os
                        and x.status in ('draft', 'queued', 'processing', 'authorized')) then 'nota fiscal emitida' end,
    case when exists (select 1 from public.fiscal_note_items x where x.service_order_id = p_os) then 'item de nota de entrada' end,
    case when exists (select 1 from public.purchase_orders x where x.service_order_id = p_os and x.status is distinct from 'cancelled') then 'pedido de compra' end,
    case when exists (select 1 from public.quote_requests x where x.service_order_id = p_os and x.status is distinct from 'cancelled') then 'cotação a fornecedor' end,
    case when exists (select 1 from public.diarias_reembolsos x where x.os_id = p_os) then 'reembolso de diária' end,
    case when exists (select 1 from public.anotacoes_do_extrato x where x.os_id = p_os) then 'anotação do extrato' end,
    case when exists (select 1 from public.finance_review_queue x where x.suggested_service_order_id = p_os and x.status = 'pending') then 'sugestão de conciliação pendente' end,
    case when exists (select 1 from public.service_order_expenses x where x.service_order_id = p_os)
           or exists (select 1 from public.service_orders so where so.id = p_os and coalesce(so.operational_cost_total, 0) <> 0)
         then 'despesas/custo operacional' end
  )
$$;

-- 6) Montagem (recebe o número: o teste passa um fictício e não gasta o document_number_seq) ----------------
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

-- 7) Desmontagem: os originais voltam como estavam; o agrupado fica cancelado como histórico ---------------
create or replace function public._desagrupar_orcamentos_desfazer(p_agrupado uuid, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ag public.service_orders;
  v_grupo public.orcamento_agrupamentos;
  v_destino text;
  v_bloqueios text;
  v_quem text;
  v_numeros text[];
  v_ids uuid[];
  v_qtd integer;
  v_motivo text;
  n_envios integer := 0;
  n_reativados integer := 0;
  o record;
begin
  if p_autor is null then
    raise exception 'Faça login para desagrupar orçamentos.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode desagrupar orçamentos.' using errcode = '42501';
  end if;
  if p_agrupado is null then
    raise exception 'Escolha o orçamento agrupado.' using errcode = '22023';
  end if;

  select so.* into v_ag from public.service_orders so where so.id = p_agrupado for update;
  if v_ag.id is null then
    raise exception 'Orçamento não encontrado. Recarregue a tela.' using errcode = 'P0002';
  end if;

  select g.* into v_grupo from public.orcamento_agrupamentos g
   where g.agrupado_id = p_agrupado and g.desfeito_em is null
   for update;
  if v_grupo.id is null then
    raise exception '% não é um orçamento agrupado (ou já foi desagrupado).', v_ag.service_order_number
      using errcode = '22023';
  end if;

  -- O agrupado precisa ainda ser um orçamento em aberto, sem nada preso a ele
  if v_ag.merged_into_id is not null then
    select d.service_order_number into v_destino from public.service_orders d where d.id = v_ag.merged_into_id;
    raise exception '% foi agrupado de novo em %. Desagrupe % primeiro.',
      v_ag.service_order_number, coalesce(v_destino, 'outro orçamento'), coalesce(v_destino, 'esse')
      using errcode = '22023';
  end if;
  if v_ag.status <> 'draft' or v_ag.converted_to_os_at is not null then
    raise exception '% não é mais um orçamento em aberto (já virou OS ou foi cancelado): não dá mais para desagrupar.',
      v_ag.service_order_number using errcode = '22023';
  end if;
  if v_ag.signed_at is not null
     or exists (select 1 from public.service_order_signatures g where g.service_order_id = v_ag.id) then
    raise exception '% já foi assinado pelo cliente: não dá para desagrupar.', v_ag.service_order_number
      using errcode = '22023';
  end if;
  v_bloqueios := public._orcamento_vinculos_que_prendem(v_ag.id);
  if v_bloqueios <> '' then
    raise exception '% está ligado a: %. Resolva isso antes de desagrupar.', v_ag.service_order_number, v_bloqueios
      using errcode = '22023';
  end if;

  -- Trava as origens (mesma ordem do agrupar) e confere que seguem presas a este agrupado
  select array_agg(t.id) into v_ids
    from (select so.id from public.service_orders so
            join public.orcamento_agrupamento_origens x on x.origem_id = so.id and x.agrupamento_id = v_grupo.id
           order by so.id for update of so) t;
  select count(*) into v_qtd from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  if coalesce(cardinality(v_ids), 0) <> v_qtd or v_qtd = 0 then
    raise exception 'Algum orçamento original deste agrupamento não existe mais. Nada foi desfeito.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.service_orders so where so.id = any(v_ids)
              and (so.merged_into_id is distinct from v_ag.id or so.status <> 'cancelled')) then
    raise exception 'Os originais de % não estão mais como o agrupamento deixou. Nada foi desfeito.',
      v_ag.service_order_number using errcode = '22023';
  end if;

  select array_agg(x.numero order by x.ordem) into v_numeros
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  select u.full_name into v_quem from public.app_users u where u.id = p_autor;
  v_motivo := 'Desagrupado em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
           || ' por ' || coalesce(v_quem, 'sistema') || ': voltou a ser ' || array_to_string(v_numeros, ', ');

  -- Auditoria antes de mexer (guarda o "antes")
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason,
                                triggered_by_table, triggered_by_id)
  select 'service_orders', x.origem_id, 'reopen', coalesce(v_quem, 'sistema'),
         jsonb_build_object('status', 'cancelled', 'merged_into_id', v_ag.id, 'merged_into_number', v_ag.service_order_number),
         jsonb_build_object('status', 'draft', 'quote_status', x.quote_status_antes, 'link_publico', 'religado'),
         'Desagrupado de ' || v_ag.service_order_number, 'service_orders', v_ag.id
    from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', v_ag.id, 'cancel', coalesce(v_quem, 'sistema'),
          jsonb_build_object('status', v_ag.status, 'quote_status', v_ag.quote_status, 'grand_total', v_ag.grand_total),
          jsonb_build_object('status', 'cancelled', 'desagrupado', to_jsonb(v_numeros), 'link_publico', 'desligado'),
          v_motivo);

  -- Origens: voltam como estavam (situação, link, cancelamento)
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  for o in select x.* from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id order by x.ordem loop
    update public.service_orders so
       set status = 'draft',
           quote_status = o.quote_status_antes,
           cancelled_at = o.cancelled_at_antes,
           cancellation_reason = o.cancellation_reason_antes,
           share_token = coalesce(o.share_token_antes, gen_random_uuid()),
           merged_into_id = null
     where so.id = o.origem_id;
  end loop;
  -- Agrupado: cancelado como histórico, link desligado (a guarda do agrupado deixa passar só aqui)
  update public.service_orders so
     set status = 'cancelled',
         cancelled_at = now(),
         cancellation_reason = v_motivo,
         share_token = null
   where so.id = v_ag.id;
  perform set_config('marineflow.agrupar_orcamentos', '', true);

  -- Totais das origens pelo banco (alguém pode ter mexido numa linha enquanto estavam canceladas)
  for o in select x.origem_id from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id loop
    perform public.recalc_so_totals(o.origem_id);
  end loop;

  -- Envios agendados das origens que o agrupar cancelou voltam (o link deles voltou), se a hora ainda não
  -- passou. O número do agrupado não muda enquanto o desagrupar é possível: o texto casa exatamente.
  update public.whatsapp_scheduled_sends w
     set status = 'pending', last_error = null, updated_at = now()
   where w.service_order_id = any(v_ids) and w.status = 'cancelled'
     and w.last_error = 'Cancelado: orçamento agrupado em ' || v_ag.service_order_number
     and w.next_run_at > now();
  get diagnostics n_reativados = row_count;

  update public.whatsapp_scheduled_sends w
     set status = 'cancelled', last_error = 'Cancelado: orçamento desagrupado', updated_at = now()
   where w.service_order_id = v_ag.id and w.status in ('pending', 'processing');
  get diagnostics n_envios = row_count;

  update public.orcamento_agrupamentos g
     set desfeito_em = now(), desfeito_por = p_autor
   where g.id = v_grupo.id;

  return jsonb_build_object(
    'agrupado_id', v_ag.id, 'agrupado', v_ag.service_order_number,
    'origens', to_jsonb(v_numeros), 'origens_ids', (select to_jsonb(array_agg(x.origem_id order by x.ordem))
                                                      from public.orcamento_agrupamento_origens x where x.agrupamento_id = v_grupo.id),
    'envios_cancelados', n_envios, 'envios_reativados', n_reativados);
end $$;

-- 8) Portas públicas: só resolvem o autor --------------------------------------------------------------------
-- Na tela vale o usuário da sessão e p_autor é IGNORADO (ninguém se passa por outro).
-- Sem sessão só chega o service role (anon/public não executam): vale p_autor (assistente).
create or replace function public.agrupar_orcamentos(
  p_orcamentos uuid[],
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
  return public._agrupar_orcamentos_montar(p_orcamentos, p_base, null, coalesce(auth.uid(), p_autor), p_total_esperado);
end $$;

create or replace function public.desagrupar_orcamentos(
  p_agrupado uuid,
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._desagrupar_orcamentos_desfazer(p_agrupado, coalesce(auth.uid(), p_autor));
end $$;

-- 9) Privilégios + prova ---------------------------------------------------------------------------------------
revoke all on function public._orcamento_agrupado_guarda() from public, anon, authenticated;
revoke all on function public._orcamento_agrupado_guarda_destino() from public, anon, authenticated;
revoke all on function public._orcamento_agrupado_sem_dinheiro() from public, anon, authenticated;
revoke all on function public._agrupar_orcamentos_juntar(text[], text[]) from public, anon, authenticated;
revoke all on function public._agrupar_orcamentos_reais(numeric) from public, anon, authenticated;
revoke all on function public._orcamento_vinculos_que_prendem(uuid) from public, anon, authenticated;
revoke all on function public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public._desagrupar_orcamentos_desfazer(uuid, uuid) from public, anon, authenticated;
revoke all on function public.agrupar_orcamentos(uuid[], uuid, numeric, uuid) from public, anon;
revoke all on function public.desagrupar_orcamentos(uuid, uuid) from public, anon;
grant execute on function public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric) to service_role;
grant execute on function public._desagrupar_orcamentos_desfazer(uuid, uuid) to service_role;
grant execute on function public.agrupar_orcamentos(uuid[], uuid, numeric, uuid) to authenticated, service_role;
grant execute on function public.desagrupar_orcamentos(uuid, uuid) to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.agrupar_orcamentos(uuid[], uuid, numeric, uuid)', 'execute')
     or has_function_privilege('anon', 'public.desagrupar_orcamentos(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)', 'execute')
     or has_function_privilege('authenticated', 'public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)', 'execute')
     or has_function_privilege('anon', 'public._desagrupar_orcamentos_desfazer(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public._desagrupar_orcamentos_desfazer(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public._orcamento_vinculos_que_prendem(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public._orcamento_vinculos_que_prendem(uuid)', 'execute')
     or has_function_privilege('anon', 'public._agrupar_orcamentos_juntar(text[], text[])', 'execute')
     or has_function_privilege('anon', 'public._agrupar_orcamentos_reais(numeric)', 'execute')
     or has_function_privilege('authenticated', 'public._orcamento_agrupado_sem_dinheiro()', 'execute')
     or not has_function_privilege('authenticated', 'public.agrupar_orcamentos(uuid[], uuid, numeric, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.desagrupar_orcamentos(uuid, uuid)', 'execute')
     or has_column_privilege('anon', 'public.service_orders', 'merged_into_id', 'select')
     or has_table_privilege('anon', 'public.orcamento_agrupamentos', 'select')
     or has_table_privilege('anon', 'public.orcamento_agrupamento_origens', 'select')
     or has_table_privilege('authenticated', 'public.orcamento_agrupamentos', 'insert')
     or has_table_privilege('authenticated', 'public.orcamento_agrupamento_origens', 'update')
  then
    raise exception 'Privilégios errados em agrupar/desagrupar orçamentos';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20261015180000', 'agrupar_orcamentos')
on conflict do nothing;
