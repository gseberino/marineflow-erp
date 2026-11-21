-- "Fechar juntas" — Fase 1: a Fatura FAT-N (agrupa as contas a receber de várias OS JÁ EXECUTADAS do mesmo
-- cliente), o recebimento dela e as travas no banco. 20/11/2026. Pedido do dono: "Construir agora", pequeno,
-- reaproveitando o que existe (plano: D:/IA-HBR/Trabalho/fechar-juntas-f1/PLANO.md).
--
-- Nada de tabela nova:
--   * a fatura é uma linha de public.invoices (vazia até aqui; nenhum código a lia) — o status passa a
--     open/paid/cancelled e ganha quem criou e quando foi desfeita;
--   * as contas continuam cada uma na sua OS: a fatura só preenche receivables.invoice_id (já existia, com FK);
--   * a cobrança aponta para a fatura por collections.invoice_id (coluna nova);
--   * receber é o MESMO caminho de sempre: o Pix (uma linha do Extrato) passa por aplicar_entrada_em_contas (o
--     "Este Pix paga"), o dinheiro por register_payment_and_update_balance (o "Registrar pagamento"); desfazer um
--     recebimento, por desfazer_aplicacao / estornar_pagamento. A conta que vence primeiro recebe primeiro.
--   * número FAT-00001, FAT-00002… por sequência própria (como o recibo das diárias tem a dele): a OS e o
--     orçamento, que dividem o document_number_seq, não pulam número (cartão 1 do plano).
--
-- Travas (gatilhos BEFORE em receivables, payments e collections): conta de fatura aberta ou quitada só muda pelas
-- funções da fatura. Elas marcam a transação (set_config('marineflow.fatura', <id da fatura>, true)) e tiram a
-- marca no fim; fora disso, a tela de Cobranças, o assistente, a conciliação, o Extrato, reabrir/cancelar OS e o
-- histórico recebem a frase pronta. Continua livre: observação, lembrete enviado, nota fiscal, categoria e centro
-- de custo da conta; o envio da cobrança (sent/viewed/overdue, last_auto_sent_at, contato).
--
-- Regras de sobra (dono, 02/10/2026): Pix até R$ 10 a mais = receita (vai para a última conta, como no "Este Pix
-- paga"); entre R$ 10 e R$ 100 é do dono (recusa e diz isso); acima de R$ 100, avaliar (recusa). Falta = recebimento
-- parcial, a fatura continua aberta. Dinheiro a mais: recusa (o resto é troco).
--
-- "Cobrar juntas" (cobrar_juntas_registrar_envio, recriada com o texto de 20270212110000 + o trecho da fatura):
-- no Cobrar juntas (p_os preenchido), contas com saldo que ainda não estão em fatura e cujas OS estão todas
-- executadas viram a fatura (o assistente chega por aqui; a tela cria a fatura antes do envio, para citar o
-- número na mensagem, e aqui só encontra as contas já nela). A cobrança criada de conta de fatura nasce com
-- invoice_id; as abertas que já existiam passam a apontar para ela.

-- 1) A tabela da fatura ---------------------------------------------------------------------------------------
alter table public.invoices drop constraint if exists invoices_status_check;
alter table public.invoices alter column status set default 'open';
alter table public.invoices
  add constraint invoices_status_check check (status = any (array['open'::text, 'paid'::text, 'cancelled'::text]));
alter table public.invoices
  add column if not exists created_by uuid,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_reason text;

comment on table public.invoices is
  'Fatura FAT-N do "Fechar juntas": agrupa contas a receber (receivables.invoice_id) de 2+ OS executadas do mesmo cliente. open = aberta, paid = quitada, cancelled = desfeita. Só as funções fatura_* escrevem.';
comment on column public.invoices.total_amount is 'Soma dos saldos das contas na criação (calculada pelo banco).';

-- Só as funções escrevem na fatura (a RLS admin/financeiro continua valendo para a leitura).
revoke insert, update, delete on public.invoices from anon, authenticated;
revoke select on public.invoices from anon;

create sequence if not exists public.fatura_seq;
revoke all on sequence public.fatura_seq from public, anon, authenticated;

alter table public.collections
  add column if not exists invoice_id uuid references public.invoices(id) on delete restrict;
create index if not exists idx_collections_invoice_id on public.collections (invoice_id) where invoice_id is not null;
comment on column public.collections.invoice_id is 'A fatura (FAT-N) da conta desta cobrança.';

-- 2) Quem pode: administrador ou financeiro, ativo (o usuário logado ou, pelo assistente, quem pediu) ------------
create or replace function public._fatura_autor(p_autor uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v uuid := coalesce(auth.uid(), p_autor);
begin
  if v is null then
    raise exception 'Faça login para mexer na fatura.' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(v) then
    raise exception 'Só administrador ou financeiro mexe em fatura.' using errcode = '42501';
  end if;
  return v;
end $$;

-- 3) Por que estas contas não viram fatura (nulo = viram) ------------------------------------------------------
create or replace function public._fatura_impedimento(p_cliente uuid, p_contas uuid[])
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cli record;
  v_distintas integer;
  v_lidas integer;
  v_lista text;
  v_os integer;
begin
  if p_cliente is null then
    return 'Diga de qual cliente é a fatura.';
  end if;
  if p_contas is null or cardinality(p_contas) = 0 or array_position(p_contas, null) is not null then
    return 'Diga as contas que entram na fatura.';
  end if;
  select c.id, c.name, c.generico into v_cli from public.clients c where c.id = p_cliente;
  if v_cli.id is null then
    return 'Cliente não encontrado.';
  end if;
  if coalesce(v_cli.generico, false) then
    return 'O cadastro ' || coalesce(v_cli.name, 'deste cliente') || ' é genérico, sem CPF/CNPJ: não entra em fatura.';
  end if;
  select count(distinct x) into v_distintas from unnest(p_contas) x;
  if v_distintas > 100 then
    return 'Contas demais numa fatura só (' || v_distintas || ').';
  end if;
  select count(*) into v_lidas from public.receivables x where x.id = any(p_contas);
  if v_lidas <> v_distintas then
    return 'Alguma conta da fatura não existe mais. Recarregue a tela.';
  end if;

  select string_agg(coalesce(nullif(btrim(x.description), ''), 'conta'), ', ' order by x.id) into v_lista
    from public.receivables x where x.id = any(p_contas) and x.client_id is distinct from p_cliente;
  if v_lista is not null then
    return 'Estas contas não são de ' || coalesce(v_cli.name, 'deste cliente') || ': ' || v_lista || '.';
  end if;

  select string_agg(coalesce(nullif(btrim(x.description), ''), 'conta'), ', ' order by x.id) into v_lista
    from public.receivables x where x.id = any(p_contas) and x.service_order_id is null;
  if v_lista is not null then
    return 'Conta sem OS não entra em fatura: ' || v_lista || '.';
  end if;

  -- OS executada = concluída ou faturada, com número de OS (orçamento fora) e não agrupada noutra.
  select string_agg(distinct so.service_order_number || ' (' ||
           case when so.service_order_number not like 'OS-%' then 'é orçamento'
                when so.merged_into_id is not null then 'foi agrupada noutra OS'
                else case so.status
                       when 'draft' then 'rascunho' when 'cancelled' then 'cancelada'
                       when 'in_progress' then 'em execução' when 'awaiting_client' then 'aguardando o cliente'
                       when 'awaiting_parts' then 'aguardando peças' when 'scheduled' then 'agendada'
                       when 'open' then 'aberta' when 'approved' then 'aprovada' when 'reopened' then 'reaberta'
                       else so.status end end || ')', ', ') into v_lista
    from public.receivables x join public.service_orders so on so.id = x.service_order_id
   where x.id = any(p_contas)
     and (so.status not in ('completed', 'invoiced') or so.service_order_number not like 'OS-%'
          or so.merged_into_id is not null);
  if v_lista is not null then
    return 'Só OS já executada (concluída ou faturada) entra em fatura: ' || v_lista || '.';
  end if;

  select string_agg(coalesce(nullif(btrim(x.description), ''), 'conta'), ', ' order by x.id) into v_lista
    from public.receivables x
   where x.id = any(p_contas)
     and (x.status not in ('pending', 'overdue', 'partially_paid') or round(x.amount - coalesce(x.paid_amount, 0), 2) <= 0);
  if v_lista is not null then
    return 'Estas contas não têm saldo em aberto: ' || v_lista || '.';
  end if;

  select string_agg(coalesce(nullif(btrim(x.description), ''), 'conta') || ' (' || f.invoice_number || ')', ', ' order by x.id)
    into v_lista
    from public.receivables x join public.invoices f on f.id = x.invoice_id
   where x.id = any(p_contas) and f.status <> 'cancelled';
  if v_lista is not null then
    return 'Estas contas já estão numa fatura: ' || v_lista || '. Use aquela fatura ou desfaça-a antes.';
  end if;

  select count(distinct x.service_order_id) into v_os from public.receivables x where x.id = any(p_contas);
  if v_os < 2 then
    return 'Uma fatura junta contas de 2 OS ou mais (aqui há ' || v_os || ').';
  end if;
  return null;
end $$;

-- 4) As travas -------------------------------------------------------------------------------------------------
-- A marca da transação: o id da fatura cuja função está rodando ('' ou nulo = nenhuma).
create or replace function public._fatura_marca()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(current_setting('marineflow.fatura', true), '')
$$;

-- Conta a receber.
create or replace function public._fatura_trava_conta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_marca text := public._fatura_marca();
  v_num text;
  v_desc text := coalesce(nullif(btrim(case when tg_op = 'INSERT' then new.description else old.description end), ''), 'a receber');
begin
  if tg_op = 'INSERT' then
    if new.invoice_id is not null and new.invoice_id::text is distinct from v_marca then
      raise exception 'Uma conta só entra numa fatura pela própria fatura (Cobrar juntas, na ficha do cliente).'
        using errcode = '55000';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' and new.invoice_id is distinct from old.invoice_id then
    if (old.invoice_id is not null and new.invoice_id is not null)
       or coalesce(new.invoice_id, old.invoice_id)::text is distinct from v_marca then
      select f.invoice_number into v_num from public.invoices f where f.id = coalesce(old.invoice_id, new.invoice_id);
      raise exception 'A conta "%" só entra ou sai da fatura % pela própria fatura, na ficha do cliente.', v_desc, coalesce(v_num, '')
        using errcode = '55000';
    end if;
    return new;
  end if;

  if old.invoice_id is null or old.invoice_id::text = v_marca then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  select f.invoice_number into v_num from public.invoices f where f.id = old.invoice_id and f.status <> 'cancelled';
  if v_num is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    raise exception 'A conta "%" está na fatura %: não pode ser apagada. Desfaça a fatura na ficha do cliente antes.', v_desc, v_num
      using errcode = '55000';
  end if;
  if (new.amount, new.paid_amount, new.balance_amount, new.status, new.due_date, new.issue_date, new.client_id,
      new.service_order_id, new.bank_transaction_id, new.description, new.is_deposit, new.due_on_completion, new.currency)
     is distinct from
     (old.amount, old.paid_amount, old.balance_amount, old.status, old.due_date, old.issue_date, old.client_id,
      old.service_order_id, old.bank_transaction_id, old.description, old.is_deposit, old.due_on_completion, old.currency) then
    raise exception 'A conta "%" está na fatura %. Receber, estornar, cancelar ou mudar valor e vencimento dela é pela fatura, na ficha do cliente (Receber / Desfazer). Para mexer por fora, desfaça a fatura antes.', v_desc, v_num
      using errcode = '55000';
  end if;
  return new;
end $$;

-- Pagamento de conta a receber.
create or replace function public._fatura_trava_pagamento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_marca text := public._fatura_marca();
  v_conta uuid;
  v_fat uuid;
  v_desc text;
  v_num text;
begin
  for v_conta in
    select distinct x from unnest(array[case when tg_op <> 'INSERT' then old.receivable_id end,
                                        case when tg_op <> 'DELETE' then new.receivable_id end]) x
     where x is not null
  loop
    select r.invoice_id, coalesce(nullif(btrim(r.description), ''), 'a receber') into v_fat, v_desc
      from public.receivables r where r.id = v_conta;
    continue when v_fat is null or v_fat::text = v_marca;
    select f.invoice_number into v_num from public.invoices f where f.id = v_fat and f.status <> 'cancelled';
    continue when v_num is null;
    -- Só observação e comprovante mudaram: livre.
    continue when tg_op = 'UPDATE'
      and (new.receivable_id, new.payable_id, new.amount, new.payment_date, new.payment_method, new.installments,
           new.card_fee_percent, new.net_amount, new.status, new.cancelled_at, new.bank_transaction_id)
          is not distinct from
          (old.receivable_id, old.payable_id, old.amount, old.payment_date, old.payment_method, old.installments,
           old.card_fee_percent, old.net_amount, old.status, old.cancelled_at, old.bank_transaction_id);
    raise exception 'A conta "%" está na fatura %: receber e estornar é pela fatura, na ficha do cliente (o Pix, pelo Extrato › Este Pix paga › "Esta entrada paga a fatura"). Para mexer por fora, desfaça a fatura antes.', v_desc, v_num
      using errcode = '55000';
  end loop;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- Cobrança (collections).
create or replace function public._fatura_trava_cobranca()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_marca text := public._fatura_marca();
  v_da_conta uuid;
  v_fat uuid;
  v_num text;
begin
  -- A fatura da conta desta cobrança (apontar para ela é sempre coerente).
  select r.invoice_id into v_da_conta from public.receivables r
   where r.id = case when tg_op = 'DELETE' then old.receivable_id else new.receivable_id end;

  if tg_op = 'INSERT' then
    if new.invoice_id is not null and new.invoice_id::text is distinct from v_marca
       and new.invoice_id is distinct from v_da_conta then
      raise exception 'Uma cobrança só aponta para a fatura da conta dela.' using errcode = '55000';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' and new.invoice_id is distinct from old.invoice_id then
    if not ((old.invoice_id is null or new.invoice_id is null) and coalesce(new.invoice_id, old.invoice_id)::text = v_marca)
       and not (old.invoice_id is null and new.invoice_id = v_da_conta
                and new.receivable_id is not distinct from old.receivable_id) then
      raise exception 'A cobrança só entra ou sai de uma fatura pela própria fatura, na ficha do cliente.' using errcode = '55000';
    end if;
  end if;

  v_fat := coalesce(old.invoice_id, v_da_conta);
  if tg_op = 'UPDATE' and old.receivable_id is distinct from new.receivable_id and v_fat is null then
    select r.invoice_id into v_fat from public.receivables r where r.id = old.receivable_id;
  end if;
  if v_fat is null or v_fat::text = v_marca then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  select f.invoice_number into v_num from public.invoices f where f.id = v_fat and f.status <> 'cancelled';
  if v_num is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    raise exception 'Esta cobrança é da fatura %: não pode ser apagada. Desfaça a fatura na ficha do cliente antes.', v_num
      using errcode = '55000';
  end if;
  if (new.amount, new.standalone_amount, new.receivable_id, new.service_order_id, new.client_id, new.due_date,
      new.paid_amount, new.paid_at, new.paid_method, new.payment_confirmed_by)
     is distinct from
     (old.amount, old.standalone_amount, old.receivable_id, old.service_order_id, old.client_id, old.due_date,
      old.paid_amount, old.paid_at, old.paid_method, old.payment_confirmed_by)
     or (new.status is distinct from old.status
         and (new.status in ('paid', 'cancelled') or old.status in ('paid', 'cancelled'))) then
    raise exception 'Esta cobrança é da fatura %: dar baixa, cancelar ou mudar valor e vencimento é pela fatura, na ficha do cliente. Para mexer por fora, desfaça a fatura antes.', v_num
      using errcode = '55000';
  end if;
  return new;
end $$;

drop trigger if exists trg_receivables_trava_fatura on public.receivables;
create trigger trg_receivables_trava_fatura
  before insert or update or delete on public.receivables
  for each row execute function public._fatura_trava_conta();

drop trigger if exists trg_payments_trava_fatura on public.payments;
create trigger trg_payments_trava_fatura
  before insert or update or delete on public.payments
  for each row execute function public._fatura_trava_pagamento();

drop trigger if exists trg_collections_trava_fatura on public.collections;
create trigger trg_collections_trava_fatura
  before insert or update or delete on public.collections
  for each row execute function public._fatura_trava_cobranca();

-- 5) Situação da fatura pelo saldo (aberta ↔ quitada) -----------------------------------------------------------
create or replace function public._fatura_saldo(p_fatura uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(round(sum(greatest(x.amount - coalesce(x.paid_amount, 0), 0)), 2), 0)
    from public.receivables x where x.invoice_id = p_fatura and x.status <> 'cancelled'
$$;

-- O que entrou pela fatura: os pagamentos confirmados das contas dela feitos depois de ela nascer.
create or replace function public._fatura_recebido(p_fatura uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(round(sum(p.amount), 2), 0)
    from public.payments p
    join public.receivables x on x.id = p.receivable_id
    join public.invoices f on f.id = x.invoice_id
   where f.id = p_fatura and p.status = 'confirmed' and p.created_at >= f.created_at
$$;

-- 6) Criar ----------------------------------------------------------------------------------------------------
create or replace function public.fatura_criar(
  p_cliente uuid,
  p_contas uuid[],
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := public._fatura_autor(p_autor);
  v_contas uuid[];
  v_exist record;
  v_imp text;
  v_id uuid;
  v_num text;
  v_total numeric;
  v_venc date;
  v_os text[];
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p_contas is null or cardinality(p_contas) = 0 or array_position(p_contas, null) is not null then
    raise exception 'Diga as contas que entram na fatura.' using errcode = '22023';
  end if;
  select array_agg(distinct x order by x) into v_contas from unnest(p_contas) x;

  -- Trava as contas sempre na mesma ordem: dois cliques ao mesmo tempo não criam duas faturas.
  perform 1 from public.receivables x where x.id = any(v_contas) order by x.id for update;

  -- Já existe fatura aberta e estas são exatamente as contas dela que ainda têm saldo: é ela (o 2º envio do
  -- Cobrar juntas usa a mesma, também depois de um recebimento parcial que quitou uma das contas).
  select f.id, f.invoice_number, f.total_amount into v_exist
    from public.invoices f
   where f.client_id = p_cliente and f.status = 'open'
     and (select array_agg(x.id order by x.id) from public.receivables x
           where x.invoice_id = f.id and x.status not in ('paid', 'cancelled')
             and round(x.amount - coalesce(x.paid_amount, 0), 2) > 0) = v_contas
   limit 1;
  if v_exist.id is not null then
    return jsonb_build_object('ok', true, 'criada', false, 'fatura_id', v_exist.id, 'numero', v_exist.invoice_number,
      'total', v_exist.total_amount, 'saldo', public._fatura_saldo(v_exist.id),
      'message', 'Estas contas já são a fatura ' || v_exist.invoice_number || '.');
  end if;

  v_imp := public._fatura_impedimento(p_cliente, v_contas);
  if v_imp is not null then
    raise exception '%', v_imp using errcode = '22023';
  end if;

  select round(sum(x.amount - coalesce(x.paid_amount, 0)), 2), min(x.due_date),
         array_agg(distinct so.service_order_number order by so.service_order_number)
    into v_total, v_venc, v_os
    from public.receivables x join public.service_orders so on so.id = x.service_order_id
   where x.id = any(v_contas);

  -- O número só depois de tudo validado (recusa não gasta número).
  v_num := 'FAT-' || lpad(nextval('public.fatura_seq')::text, 5, '0');
  insert into public.invoices (invoice_number, client_id, service_order_id, issue_date, due_date, subtotal,
                               total_amount, status, notes, created_by)
  values (v_num, p_cliente, null, v_hoje, coalesce(v_venc, v_hoje), v_total, v_total, 'open',
          'OS: ' || array_to_string(v_os, ', '), v_autor)
  returning id into v_id;

  perform set_config('marineflow.fatura', v_id::text, true);
  update public.receivables set invoice_id = v_id where id = any(v_contas);
  update public.collections set invoice_id = v_id
   where receivable_id = any(v_contas) and invoice_id is null and status not in ('paid', 'cancelled');
  perform set_config('marineflow.fatura', '', true);

  return jsonb_build_object('ok', true, 'criada', true, 'fatura_id', v_id, 'numero', v_num, 'total', v_total,
    'saldo', v_total, 'contas', cardinality(v_contas), 'os', to_jsonb(v_os),
    'message', 'Fatura ' || v_num || ' criada: ' || array_to_string(v_os, ', ') || ', ' || public._brl(v_total) || '.');
end $$;

comment on function public.fatura_criar(uuid, uuid[], uuid) is
  'Fechar juntas F1: junta contas a receber em aberto de 2+ OS executadas do mesmo cliente na fatura FAT-N (as contas continuam nas OS). Mesmas contas de uma fatura aberta = devolve ela. Só admin/financeiro.';

-- 7) Desfazer -------------------------------------------------------------------------------------------------
create or replace function public.fatura_desfazer(
  p_fatura uuid,
  p_motivo text default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := public._fatura_autor(p_autor);
  f public.invoices%rowtype;
  v_recebido numeric;
  v_contas integer;
begin
  select * into f from public.invoices where id = p_fatura for update;
  if not found then
    raise exception 'Fatura não encontrada.' using errcode = 'P0002';
  end if;
  if f.status = 'cancelled' then
    raise exception 'A fatura % já foi desfeita.', f.invoice_number using errcode = '22023';
  end if;
  perform 1 from public.receivables x where x.invoice_id = f.id order by x.id for update;
  v_recebido := public._fatura_recebido(f.id);
  if v_recebido > 0.005 then
    raise exception 'Já entrou % pela fatura %: desfaça os recebimentos dela antes (na ficha do cliente).',
      public._brl(v_recebido), f.invoice_number using errcode = '22023';
  end if;

  perform set_config('marineflow.fatura', f.id::text, true);
  update public.collections set invoice_id = null where invoice_id = f.id;
  update public.receivables set invoice_id = null where invoice_id = f.id;
  get diagnostics v_contas = row_count;
  update public.invoices
     set status = 'cancelled', cancelled_at = now(), cancel_reason = nullif(btrim(coalesce(p_motivo, '')), '')
   where id = f.id;
  perform set_config('marineflow.fatura', '', true);

  return jsonb_build_object('ok', true, 'fatura_id', f.id, 'numero', f.invoice_number, 'contas', v_contas,
    'message', 'Fatura ' || f.invoice_number || ' desfeita: as ' || v_contas || ' contas voltaram a ser cobradas cada uma pela sua OS.');
end $$;

comment on function public.fatura_desfazer(uuid, text, uuid) is
  'Fechar juntas F1: desfaz a fatura (só se nada entrou por ela). As contas e cobranças saem da fatura; a linha fica como desfeita.';

-- 8) Receber --------------------------------------------------------------------------------------------------
create or replace function public.fatura_receber(
  p_fatura uuid,
  p_transacao uuid default null,  -- Pix: a linha do Extrato (aplicar_entrada_em_contas)
  p_valor numeric default null,   -- dinheiro: quanto entrou (register_payment_and_update_balance)
  p_data date default null,       -- dinheiro: o dia (padrão: hoje)
  p_motivo text default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c_receita constant numeric := 10;   -- dono, 02/10/2026: até R$ 10 a mais é receita
  c_avaliar constant numeric := 100;  -- acima de R$ 100, avaliar o porquê
  v_autor uuid := public._fatura_autor(p_autor);
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  f public.invoices%rowtype;
  t public.bank_transactions%rowtype;
  v_valor numeric;
  v_saldo numeric;
  v_sobra numeric;
  v_resta numeric;
  v_parte numeric;
  v_data date;
  v_aplic jsonb := '[]'::jsonb;
  v_nota text;
  v_res jsonb;
  v_depois numeric;
  v_status text;
  r record;
  e jsonb;
begin
  select * into f from public.invoices where id = p_fatura for update;
  if not found then
    raise exception 'Fatura não encontrada.' using errcode = 'P0002';
  end if;
  if f.status <> 'open' then
    raise exception 'A fatura % %.', f.invoice_number,
      case f.status when 'paid' then 'já está quitada' else 'foi desfeita' end using errcode = '22023';
  end if;
  if (p_transacao is null) = (p_valor is null) then
    raise exception 'Diga de onde veio o dinheiro: a entrada do Extrato (Pix) ou o valor recebido em dinheiro.'
      using errcode = '22023';
  end if;

  perform 1 from public.receivables x where x.invoice_id = f.id order by x.id for update;
  v_saldo := public._fatura_saldo(f.id);
  if v_saldo <= 0.005 then
    raise exception 'A fatura % não tem saldo a receber.', f.invoice_number using errcode = '22023';
  end if;

  if p_transacao is not null then
    select * into t from public.bank_transactions where id = p_transacao;
    if not found then
      raise exception 'Linha do extrato não encontrada.' using errcode = 'P0002';
    end if;
    -- O que ainda falta aplicar desta entrada (a mesma conta do "Este Pix paga").
    v_valor := round(t.amount - coalesce((select sum(p.amount) from public.payments p
                                           where p.bank_transaction_id = t.id and p.status = 'confirmed'
                                             and p.receivable_id is not null), 0), 2);
    if v_valor <= 0.005 then
      raise exception 'Esta entrada (%) já está toda aplicada.', public._brl(t.amount) using errcode = '22023';
    end if;
    v_data := t.transaction_date;
  else
    v_valor := round(p_valor, 2);
    if v_valor <= 0 then
      raise exception 'Diga quanto foi recebido em dinheiro.' using errcode = '22023';
    end if;
    v_data := coalesce(p_data, v_hoje);
    if v_data > v_hoje then
      raise exception 'O dia do recebimento não pode ser no futuro.' using errcode = '22023';
    end if;
    perform public._recusa_se_mes_fechado(v_data, 'receber esta fatura');
  end if;

  v_sobra := round(v_valor - v_saldo, 2);
  if v_sobra > 0.005 then
    if p_transacao is null then
      raise exception 'Recebido em dinheiro (%) passa do saldo da fatura % (%) em %. Registre só o saldo: o resto é troco.',
        public._brl(v_valor), f.invoice_number, public._brl(v_saldo), public._brl(v_sobra) using errcode = '22023';
    elsif v_sobra > c_avaliar then
      raise exception 'Esta entrada (%) passa do saldo da fatura % (%) em %. Acima de R$ 100 é preciso avaliar o porquê antes: pode ser outra conta do cliente ou crédito dele.',
        public._brl(v_valor), f.invoice_number, public._brl(v_saldo), public._brl(v_sobra) using errcode = '22023';
    elsif v_sobra > c_receita then
      raise exception 'Esta entrada (%) passa do saldo da fatura % (%) em %. Entre R$ 10 e R$ 100 a mais é decisão do dono: pergunte se a sobra é sinal/adiantamento ou se o Pix também paga outra conta.',
        public._brl(v_valor), f.invoice_number, public._brl(v_saldo), public._brl(v_sobra) using errcode = '22023';
    end if;
  end if;

  -- A conta que vence primeiro recebe primeiro.
  v_resta := v_valor;
  for r in
    select x.id, round(x.amount - coalesce(x.paid_amount, 0), 2) as saldo
      from public.receivables x
     where x.invoice_id = f.id and x.status not in ('paid', 'cancelled')
       and round(x.amount - coalesce(x.paid_amount, 0), 2) > 0
     order by x.due_date nulls last, x.id
  loop
    exit when v_resta <= 0.005;
    v_parte := least(v_resta, r.saldo);
    v_aplic := v_aplic || jsonb_build_object('receivable_id', r.id, 'valor', v_parte);
    v_resta := round(v_resta - v_parte, 2);
  end loop;
  -- Pix até R$ 10 a mais: a sobra vai para a última conta (o "Este Pix paga" a lança como receita dela).
  if v_resta > 0.005 then
    v_aplic := jsonb_set(v_aplic, array[(jsonb_array_length(v_aplic) - 1)::text, 'valor'],
                         to_jsonb(round((v_aplic -> -1 ->> 'valor')::numeric + v_resta, 2)));
  end if;

  v_nota := 'Fatura ' || f.invoice_number || coalesce(' · ' || nullif(btrim(coalesce(p_motivo, '')), ''), '');
  perform set_config('marineflow.fatura', f.id::text, true);
  if p_transacao is not null then
    v_res := public.aplicar_entrada_em_contas(p_transacao, v_aplic, v_nota, v_autor);
  else
    for e in select * from jsonb_array_elements(v_aplic) loop
      perform public.register_payment_and_update_balance(
        (e ->> 'receivable_id')::uuid, null, (e ->> 'valor')::numeric, v_data, 'cash', 1, 0,
        (e ->> 'valor')::numeric, v_nota || ': recebido em dinheiro.', v_autor);
    end loop;
  end if;

  v_depois := public._fatura_saldo(f.id);
  v_status := case when v_depois <= 0.005 then 'paid' else 'open' end;
  update public.invoices set status = v_status where id = f.id and status is distinct from v_status;
  perform set_config('marineflow.fatura', '', true);

  return jsonb_build_object('ok', true, 'fatura_id', f.id, 'numero', f.invoice_number, 'recebido', v_valor,
    'saldo', v_depois, 'quitada', v_status = 'paid', 'aplicacoes', v_aplic,
    'message', 'Fatura ' || f.invoice_number || ': ' || public._brl(v_valor)
               || case when p_transacao is null then ' em dinheiro' else ' do Pix de ' || to_char(v_data, 'DD/MM/YYYY') end
               || ' recebidos em ' || jsonb_array_length(v_aplic)
               || case when jsonb_array_length(v_aplic) = 1 then ' conta' else ' contas' end
               || case when v_status = 'paid' then '. Fatura quitada.' else '. Falta ' || public._brl(v_depois) || '.' end);
end $$;

comment on function public.fatura_receber(uuid, uuid, numeric, date, text, uuid) is
  'Fechar juntas F1: recebe a fatura — Pix (p_transacao, pelo aplicar_entrada_em_contas) ou dinheiro (p_valor, pelo register_payment_and_update_balance). A conta que vence primeiro recebe primeiro; Pix até R$ 10 a mais vira receita; mais que isso recusa.';

-- 9) Desfazer um recebimento da fatura -------------------------------------------------------------------------
create or replace function public.fatura_desfazer_recebimento(
  p_pagamento uuid,
  p_motivo text default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := public._fatura_autor(p_autor);
  p public.payments%rowtype;
  f public.invoices%rowtype;
  v_motivo text;
  v_res jsonb;
  v_depois numeric;
  v_status text;
begin
  select * into p from public.payments where id = p_pagamento for update;
  if not found or p.receivable_id is null then
    raise exception 'Pagamento não encontrado.' using errcode = 'P0002';
  end if;
  if p.status <> 'confirmed' then
    raise exception 'Este recebimento já foi desfeito.' using errcode = '22023';
  end if;
  select fa.* into f from public.invoices fa join public.receivables x on x.invoice_id = fa.id
   where x.id = p.receivable_id for update of fa;
  if f.id is null or f.status = 'cancelled' then
    raise exception 'Este pagamento não é de uma fatura.' using errcode = '22023';
  end if;
  if p.created_at < f.created_at then
    raise exception 'Este pagamento é de antes da fatura %: não entrou por ela.', f.invoice_number using errcode = '22023';
  end if;

  v_motivo := coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'Recebimento da fatura ' || f.invoice_number || ' desfeito');
  perform set_config('marineflow.fatura', f.id::text, true);
  if p.bank_transaction_id is not null then
    v_res := public.desfazer_aplicacao(p.id, v_motivo, v_autor);
  else
    v_res := public.estornar_pagamento(p.id, v_motivo, v_autor);
  end if;
  v_depois := public._fatura_saldo(f.id);
  v_status := case when v_depois <= 0.005 then 'paid' else 'open' end;
  update public.invoices set status = v_status where id = f.id and status is distinct from v_status;
  perform set_config('marineflow.fatura', '', true);

  return jsonb_build_object('ok', true, 'fatura_id', f.id, 'numero', f.invoice_number, 'saldo', v_depois,
    'message', coalesce(v_res ->> 'message', 'Recebimento desfeito.') || ' Fatura ' || f.invoice_number
               || ': falta ' || public._brl(v_depois) || '.');
end $$;

comment on function public.fatura_desfazer_recebimento(uuid, text, uuid) is
  'Fechar juntas F1: desfaz um recebimento que entrou pela fatura (desfazer_aplicacao se veio do Extrato, estornar_pagamento se foi dinheiro). A fatura volta a aberta.';

-- 10) Leitura -------------------------------------------------------------------------------------------------
create or replace view public.faturas_resumo
with (security_invoker = on) as
select f.id,
       f.invoice_number as numero,
       f.client_id,
       f.status,
       f.issue_date as emitida_em,
       f.due_date as vencimento,
       f.total_amount as total,
       f.created_at,
       f.cancelled_at,
       f.notes,
       coalesce(c.saldo, 0)::numeric as saldo,
       coalesce(pg.recebido, 0)::numeric as recebido,
       coalesce(c.contas, 0)::integer as contas,
       c.os
  from public.invoices f
  left join lateral (
    select count(*) as contas,
           round(sum(greatest(x.amount - coalesce(x.paid_amount, 0), 0)), 2) as saldo,
           array_agg(distinct so.service_order_number order by so.service_order_number) as os
      from public.receivables x left join public.service_orders so on so.id = x.service_order_id
     where x.invoice_id = f.id and x.status <> 'cancelled'
  ) c on true
  left join lateral (
    select round(sum(p.amount), 2) as recebido
      from public.payments p join public.receivables x on x.id = p.receivable_id
     where x.invoice_id = f.id and p.status = 'confirmed' and p.created_at >= f.created_at
  ) pg on true;

comment on view public.faturas_resumo is
  'Fechar juntas F1: cada fatura com total (saldos na criação), recebido (pagamentos das contas depois da criação), saldo, contas e OS. security_invoker: vale a RLS de invoices/receivables (admin e financeiro).';
revoke all on public.faturas_resumo from public, anon;
grant select on public.faturas_resumo to authenticated, service_role;

-- 11) Cobrar juntas usa a fatura (texto de 20270212110000 + os trechos marcados "Fatura") ------------------------
create or replace function public.cobrar_juntas_registrar_envio(
  p_cliente uuid,
  p_contas uuid[],          -- as contas a receber que entraram na mensagem (com saldo)
  p_os uuid[],              -- as OS escolhidas (Cobrar juntas); NULO = o cliente inteiro ("Enviar extrato")
  p_nota text default null, -- o texto do contato 'whatsapp_sent' no histórico da cobrança
  p_autor uuid default null -- quem pediu, quando a chamada vem do service role (assistente)
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_quem uuid;
  v_cli record;
  v_modelo record;
  v_distintas integer;
  v_lidas integer;
  v_fora text;
  v_extrato constant boolean := p_os is null;
  v_os uuid[];
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_nota text;
  v_id uuid;
  v_criadas uuid[] := '{}';
  v_cobrancas uuid[];
  v_abertas constant text[] := array['pending', 'sent', 'viewed', 'overdue', 'disputed'];
  v_com_saldo uuid[];
  v_faturas text[];
  r record;
begin
  -- 0. Quem pede: administrador ou financeiro, ativo (dono, 20/11/2026: "Só admin e financeiro")
  if v_autor is null then
    raise exception 'Faça login para registrar a cobrança.' using errcode = '42501';
  end if;
  select u.id into v_quem from public.app_users u where u.id = v_autor and coalesce(u.active, true);
  if v_quem is null or not public.is_admin_or_financial(v_autor) then
    raise exception 'Seu cargo não mexe em cobranças.' using errcode = '42501';
  end if;

  -- 1. Entrada
  if p_cliente is null then
    raise exception 'Diga de qual cliente é a cobrança.' using errcode = '22023';
  end if;
  if p_contas is null or cardinality(p_contas) = 0 or array_position(p_contas, null) is not null then
    raise exception 'Diga as contas que entraram na cobrança.' using errcode = '22023';
  end if;
  select count(distinct x) into v_distintas from unnest(p_contas) x;
  if v_distintas > 100 then
    raise exception 'Contas demais numa cobrança só (%).', v_distintas using errcode = '22023';
  end if;

  select c.id, c.name, c.phone, c.whatsapp, c.generico into v_cli from public.clients c where c.id = p_cliente;
  if v_cli.id is null then
    raise exception 'Cliente não encontrado.' using errcode = 'P0002';
  end if;
  if coalesce(v_cli.generico, false) then
    raise exception 'O cadastro % é genérico, sem CPF/CNPJ: não entra em cobrança%.', coalesce(v_cli.name, 'deste cliente'),
      case when v_extrato then '' else ' conjunta' end
      using errcode = '22023';
  end if;

  -- 2. Trava as contas sempre na mesma ordem e confere: existem, são do cliente (o titular) e — no Cobrar
  --    juntas — das OS escolhidas
  perform 1 from public.receivables x where x.id = any(p_contas) order by x.id for update;
  select count(*) into v_lidas from public.receivables x where x.id = any(p_contas);
  if v_lidas <> v_distintas then
    raise exception 'Alguma conta da cobrança não existe mais. Recarregue a tela.' using errcode = 'P0002';
  end if;
  select string_agg(coalesce(nullif(btrim(x.description), ''), 'conta') || coalesce(' (' || so.service_order_number || ')', ''), ', '
                    order by x.id)
    into v_fora
    from public.receivables x
    left join public.service_orders so on so.id = x.service_order_id
   where x.id = any(p_contas)
     and (x.client_id is distinct from p_cliente
          or (not v_extrato
              and (x.service_order_id is null or not (x.service_order_id = any(p_os)))));
  if v_fora is not null then
    if v_extrato then
      raise exception 'Estas contas não são deste cliente: %.', v_fora using errcode = '22023';
    end if;
    raise exception 'Estas contas não são deste cliente ou de uma das OS escolhidas: %.', v_fora using errcode = '22023';
  end if;

  -- Fatura (Fechar juntas F1, 20/11/2026): no Cobrar juntas, as contas com saldo que ainda não estão em fatura
  -- viram a fatura FAT-N quando todas são de OS executada (o assistente chega por aqui; a tela já a criou antes
  -- do envio). Se alguma OS ainda está em execução, a cobrança sai como antes, sem fatura.
  if not v_extrato then
    select array_agg(x.id order by x.id) into v_com_saldo
      from public.receivables x
     where x.id = any(p_contas) and x.status not in ('paid', 'cancelled')
       and round(x.amount - coalesce(x.paid_amount, 0), 2) > 0;
    if v_com_saldo is not null
       and not exists (select 1 from public.receivables x join public.invoices f on f.id = x.invoice_id
                        where x.id = any(v_com_saldo) and f.status <> 'cancelled')
       and public._fatura_impedimento(p_cliente, v_com_saldo) is null then
      perform public.fatura_criar(p_cliente, v_com_saldo, v_quem);
    end if;
  end if;

  -- As OS cujas cobranças "sem conta" recebem o registro: as escolhidas; no extrato, as das contas
  if v_extrato then
    select coalesce(array_agg(distinct x.service_order_id), '{}') into v_os
      from public.receivables x where x.id = any(p_contas) and x.service_order_id is not null;
  else
    v_os := p_os;
  end if;

  -- O modelo de mensagem padrão, como criar_cobranca e a tela escolhem (o padrão, senão o primeiro pelo nome)
  select t.body, t.send_method into v_modelo
    from public.collection_templates t
   order by t.is_default desc nulls last, t.name
   limit 1;
  v_nota := coalesce(nullif(btrim(p_nota), ''),
                     case when v_extrato then 'Extrato do cliente com saldo (Enviar extrato)'
                          else 'Cobrar juntas (várias OS numa mensagem)' end);

  -- 3. Cria a cobrança de cada conta com saldo que não tem nenhuma aberta (pela conta, ou da OS sem conta)
  for r in
    select x.id, x.client_id, x.service_order_id, x.due_date, x.invoice_id,
           round(greatest(coalesce(x.balance_amount, x.amount - coalesce(x.paid_amount, 0)), 0), 2) as saldo
      from public.receivables x
     where x.id = any(p_contas)
       and x.status not in ('paid', 'cancelled')
     order by x.service_order_id nulls last, x.due_date nulls last, x.id
  loop
    continue when r.saldo < 0.01;
    continue when exists (select 1 from public.collections k
                           where k.receivable_id = r.id and k.status = any(v_abertas));
    continue when r.service_order_id is not null
              and exists (select 1 from public.collections k
                           where k.receivable_id is null and k.service_order_id = r.service_order_id
                             and k.status = any(v_abertas));
    insert into public.collections (
      client_id, service_order_id, receivable_id, description, standalone_amount, amount, due_date,
      contact_name, phone, contact_whatsapp, send_method, message_template, auto_rule_enabled, status,
      created_by, notes, invoice_id
    ) values (
      r.client_id, r.service_order_id, r.id, null, null, r.saldo, coalesce(r.due_date, v_hoje),
      v_cli.name, v_cli.phone, coalesce(nullif(btrim(v_cli.whatsapp), ''), v_cli.phone),
      coalesce(v_modelo.send_method, 'text_link'), v_modelo.body, false, 'pending',
      v_quem,
      'Criada junto com o envio do ' || case when v_extrato then '"Enviar extrato"' else '"Cobrar juntas"' end
        || ' em ' || to_char(v_hoje, 'DD/MM/YYYY') || '.',
      r.invoice_id  -- Fatura: a cobrança da conta aponta para a fatura dela
    )
    returning id into v_id;
    v_criadas := v_criadas || v_id;
  end loop;

  -- Fatura: as cobranças abertas que já existiam nas contas de fatura passam a apontar para ela.
  update public.collections k
     set invoice_id = x.invoice_id
    from public.receivables x
   where k.receivable_id = x.id and x.id = any(p_contas) and x.invoice_id is not null
     and k.invoice_id is null and k.status = any(v_abertas);

  -- 4. Registra o envio em todas as abertas das contas (inclusive as recém-criadas) e nas da OS sem conta
  select array_agg(k.id order by k.id) into v_cobrancas
    from public.collections k
   where k.status = any(v_abertas)
     and (k.receivable_id = any(p_contas)
          or (k.receivable_id is null and k.service_order_id = any(v_os)));
  if v_cobrancas is not null then
    insert into public.collection_contacts (collection_id, contact_type, notes, created_by)
    select x, 'whatsapp_sent', v_nota, v_quem from unnest(v_cobrancas) x;
    update public.collections k
       set status = 'sent', last_auto_sent_at = now()
     where k.id = any(v_cobrancas);
  end if;

  select array_agg(distinct f.invoice_number order by f.invoice_number) into v_faturas
    from public.receivables x join public.invoices f on f.id = x.invoice_id
   where x.id = any(p_contas) and f.status <> 'cancelled';

  return jsonb_build_object(
    'criadas', cardinality(v_criadas),
    'registradas', coalesce(cardinality(v_cobrancas), 0),
    'cobrancas_criadas', to_jsonb(v_criadas),
    'faturas', coalesce(to_jsonb(v_faturas), '[]'::jsonb));
end $$;

comment on function public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid) is
  'Cobrar juntas (p_os = as OS escolhidas) ou Enviar extrato com saldo (p_os nulo = o cliente inteiro), depois do envio confirmado: cria a cobrança (collections) das contas que não têm nenhuma aberta e registra o envio (whatsapp_sent + sent + last_auto_sent_at) em todas. No Cobrar juntas de OS executadas, as contas viram a fatura FAT-N (Fechar juntas F1) e as cobranças apontam para ela. Tudo ou nada. Só administrador e financeiro.';

-- 12) Privilégios: as funções de tela pelo logado e pelo service role; as internas e os gatilhos, de ninguém.
--     Anon fora POR NOME (o padrão do Supabase concede) — e provado abaixo.
revoke all on function public._fatura_autor(uuid) from public, anon, authenticated;
revoke all on function public._fatura_impedimento(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public._fatura_marca() from public, anon, authenticated;
revoke all on function public._fatura_saldo(uuid) from public, anon, authenticated;
revoke all on function public._fatura_recebido(uuid) from public, anon, authenticated;
revoke all on function public._fatura_trava_conta() from public, anon, authenticated;
revoke all on function public._fatura_trava_pagamento() from public, anon, authenticated;
revoke all on function public._fatura_trava_cobranca() from public, anon, authenticated;
grant execute on function public._fatura_marca() to service_role;

revoke all on function public.fatura_criar(uuid, uuid[], uuid) from public, anon;
revoke all on function public.fatura_desfazer(uuid, text, uuid) from public, anon;
revoke all on function public.fatura_receber(uuid, uuid, numeric, date, text, uuid) from public, anon;
revoke all on function public.fatura_desfazer_recebimento(uuid, text, uuid) from public, anon;
grant execute on function public.fatura_criar(uuid, uuid[], uuid) to authenticated, service_role;
grant execute on function public.fatura_desfazer(uuid, text, uuid) to authenticated, service_role;
grant execute on function public.fatura_receber(uuid, uuid, numeric, date, text, uuid) to authenticated, service_role;
grant execute on function public.fatura_desfazer_recebimento(uuid, text, uuid) to authenticated, service_role;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.fatura_criar(uuid, uuid[], uuid)',
    'public.fatura_desfazer(uuid, text, uuid)',
    'public.fatura_receber(uuid, uuid, numeric, date, text, uuid)',
    'public.fatura_desfazer_recebimento(uuid, text, uuid)',
    'public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid)'
  ] loop
    if has_function_privilege('anon', f, 'execute')
       or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception 'Privilégios errados em %', f;
    end if;
  end loop;
  foreach f in array array[
    'public._fatura_autor(uuid)', 'public._fatura_impedimento(uuid, uuid[])', 'public._fatura_saldo(uuid)',
    'public._fatura_recebido(uuid)', 'public._fatura_trava_conta()', 'public._fatura_trava_pagamento()',
    'public._fatura_trava_cobranca()'
  ] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'Função interna aberta: %', f;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.invoices', 'select')
     or has_table_privilege('authenticated', 'public.invoices', 'insert')
     or has_table_privilege('authenticated', 'public.invoices', 'update')
     or has_table_privilege('authenticated', 'public.invoices', 'delete')
     or has_table_privilege('anon', 'public.faturas_resumo', 'select') then
    raise exception 'Privilégios errados em invoices / faturas_resumo';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name) values ('20270220100000', 'fechar_juntas_fatura');
