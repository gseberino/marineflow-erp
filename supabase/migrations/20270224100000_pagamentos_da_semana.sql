-- Pagamentos da semana (etapa 2 do controle financeiro, 24/11/2026): o que pagar, em ordem de prioridade, com o saldo.
--
-- De onde vem: pedido do dono de 21/11/2026 ("não consigo ter controle... controle de prioridade de pagamentos"). Medido
-- em 23/11: R$ 1.476 no banco, R$ 2.850 a pagar já vencidos; a manhã só dizia "vence hoje / amanhã vence" (conta vencida
-- nunca mais aparecia), a revisão da semana só dava a soma, e não existia prioridade em lugar nenhum.
--
-- Decisões do dono (23/11/2026, no chat):
--   1A · ordem pela CONSEQUÊNCIA DO ATRASO, e dentro do grupo o que vence antes:
--        1 = pessoas e impostos (diárias, salários, comissões, impostos);
--        2 = o que corta serviço (telefonia/internet, aluguel, energia, água);
--        3 = fornecedor com boleto ou nota, fatura de cartão, empréstimo (juros, protesto, trava de compra);
--        4 = o resto.
--        A conta que chegou por boleto vem sem categoria: cai no 3 e o grupo fica "a definir" até o dono dizer UMA vez,
--        por fornecedor, onde ele entra (pagamento_prioridades).
--   2A · a lista chega na manhã do 1º dia útil da semana; as vencidas, todo dia útil.
--   3A · só contas a pagar nesta fatia (fatura de cartão e gastos que se repetem ficam para a seguinte).
--   4  · "Pago por <sócio>" (o sócio pagou do bolso; notes 'Reembolso ao sócio…') é a empresa devendo ao sócio: fica em
--        aberto, fora da fila, numa linha à parte.
--
-- Nada aqui paga, baixa ou muda conta: é leitura, mais a preferência de grupo por fornecedor.
-- Chave de desligar o bloco da manhã: app_settings.pagamentos_semana_modo = 'desligado' (ausente = ligado); quem lê é
-- ai-daily-briefing. A ferramenta do assistente (list_payables_due) responde sempre.
--
-- Sem dados.

-- 1. A chave de "quem cobra": o fornecedor cadastrado ou, sem ele, o nome escrito igual (a mesma da baixa pelo boleto) --
create or replace function public._quem_da_conta(p_fornecedor uuid, p_nome text)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(p_fornecedor::text, nullif(lower(btrim(coalesce(p_nome, ''))), ''));
$$;

-- 2. O grupo que o dono definiu para um fornecedor (vale para as contas de agora e as próximas) --------------------
create table if not exists public.pagamento_prioridades (
  quem text primary key,
  nome text not null,
  grupo smallint not null check (grupo between 1 and 4),
  definido_em timestamptz not null default now(),
  definido_por uuid
);
comment on table public.pagamento_prioridades is
  'Grupo de prioridade de pagamento por fornecedor (1 pessoas e impostos, 2 corta serviço, 3 fornecedor/boleto/juros, 4 resto). quem = _quem_da_conta.';

alter table public.pagamento_prioridades enable row level security;
revoke all on table public.pagamento_prioridades from public, anon, authenticated;
grant select, insert, update, delete on table public.pagamento_prioridades to service_role;

-- 3. A lista -----------------------------------------------------------------------------------------------------
-- p_ate nulo = o domingo da semana de p_hoje. Entram as contas em aberto que vencem até p_ate (as já vencidas todas).
create or replace function public.pagamentos_da_semana(p_hoje date default public._hoje_brt(), p_ate date default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with par as (
    select p_hoje as hoje,
           coalesce(p_ate, p_hoje + (7 - extract(isodow from p_hoje)::int)) as ate
  ),
  abertas as (
    select p.id, p.due_date,
           round(coalesce(p.balance_amount, p.amount - coalesce(p.paid_amount, 0)), 2) as valor,
           coalesce(nullif(btrim(s.name), ''), nullif(btrim(p.supplier_name), ''), nullif(btrim(p.description), ''), 'conta') as nome,
           public._quem_da_conta(p.supplier_id, p.supplier_name) as quem,
           p.expense_category as categoria,
           nullif(btrim(coalesce(p.boleto_linha, '')), '') as boleto_linha,
           coalesce(p.notes, '') like 'Reembolso ao sócio%' as reembolso,
           case
             when p.origin in ('folha', 'commission')
               or coalesce(p.expense_category, '') ~* '(di[áa]ria|sal[áa]rio|comiss|imposto)' then 1
             when coalesce(p.expense_category, '') ~* '(telefonia|internet|aluguel|energia|[áa]gua)' then 2
             when p.boleto_linha is not null or p.fiscal_note_id is not null
               or coalesce(p.expense_category, '') ~* '(fatura de cart|empr[ée]stimo)' then 3
             else 4
           end as grupo_da_regra
      from public.payables p
      left join public.suppliers s on s.id = p.supplier_id
     cross join par
     where p.status in ('pending', 'partially_paid', 'overdue')
       and p.due_date <= par.ate
  ),
  contas as (
    select a.*, coalesce(pr.grupo, a.grupo_da_regra)::int as grupo,
           -- sem categoria e sem resposta do dono: o grupo é palpite (pergunta-se uma vez por fornecedor)
           (pr.quem is null and a.quem is not null and nullif(btrim(coalesce(a.categoria, '')), '') is null) as a_definir
      from abertas a
      left join public.pagamento_prioridades pr on pr.quem = a.quem
     where a.valor > 0
  ),
  saldo as (
    select round(sum(u.saldo_do_provedor), 2) as total, min(u.conferido_em) as desde, count(*) as contas
      from public.bank_connections c
     cross join lateral (
       select k.saldo_do_provedor, k.conferido_em
         from public.bank_balance_checks k
        where k.bank_connection_id = c.id and k.saldo_do_provedor is not null
        order by k.conferido_em desc
        limit 1
     ) u
     where c.active and c.provider <> 'caixa'
  )
  select jsonb_build_object(
    'hoje', par.hoje,
    'ate', par.ate,
    'saldo_no_banco', (select total from saldo),
    'saldo_em', (select desde from saldo),
    'contas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'nome', c.nome, 'valor', c.valor, 'vencimento', c.due_date,
               'vencida', c.due_date < par.hoje, 'grupo', c.grupo, 'a_definir', c.a_definir,
               'categoria', c.categoria, 'boleto_linha', c.boleto_linha)
             order by c.grupo, c.due_date, c.valor desc, c.id)
        from contas c where not c.reembolso), '[]'::jsonb),
    'soma', coalesce((select sum(c.valor) from contas c where not c.reembolso), 0),
    'vencido', jsonb_build_object(
      'n', (select count(*) from contas c where not c.reembolso and c.due_date < par.hoje),
      'total', coalesce((select sum(c.valor) from contas c where not c.reembolso and c.due_date < par.hoje), 0)),
    'reembolsos', jsonb_build_object(
      'n', (select count(*) from contas c where c.reembolso),
      'total', coalesce((select sum(c.valor) from contas c where c.reembolso), 0))
  )
  from par;
$$;

-- 4. O dono diz em que grupo um fornecedor entra (a partir de uma conta dele) -------------------------------------
create or replace function public.definir_prioridade_de_pagamento(p_conta uuid, p_grupo int, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quem text;
  v_nome text;
  v_contas int;
begin
  if p_grupo is null or p_grupo not between 1 and 4 then
    raise exception 'Grupo inválido: 1 (pessoas e impostos), 2 (corta serviço), 3 (fornecedor com boleto) ou 4 (o resto).';
  end if;
  select public._quem_da_conta(p.supplier_id, p.supplier_name),
         coalesce(nullif(btrim(s.name), ''), nullif(btrim(p.supplier_name), ''))
    into v_quem, v_nome
    from public.payables p
    left join public.suppliers s on s.id = p.supplier_id
   where p.id = p_conta;
  if not found then raise exception 'Conta a pagar não encontrada.'; end if;
  if v_quem is null then
    raise exception 'Esta conta não tem fornecedor nem nome de quem cobra: não há a quem ligar a prioridade.';
  end if;

  insert into public.pagamento_prioridades (quem, nome, grupo, definido_por)
  values (v_quem, v_nome, p_grupo, p_autor)
  on conflict (quem) do update
     set grupo = excluded.grupo, nome = excluded.nome, definido_em = now(), definido_por = excluded.definido_por;

  select count(*) into v_contas
    from public.payables p
   where p.status in ('pending', 'partially_paid', 'overdue')
     and public._quem_da_conta(p.supplier_id, p.supplier_name) = v_quem;

  return jsonb_build_object('ok', true, 'fornecedor', v_nome, 'grupo', p_grupo, 'contas_em_aberto', v_contas);
end $$;

-- 5. Só o servidor chama (revoke de public não fecha anon: revogar dos três e provar no teste) ---------------------
revoke all on function public._quem_da_conta(uuid, text) from public, anon, authenticated;
revoke all on function public.pagamentos_da_semana(date, date) from public, anon, authenticated;
revoke all on function public.definir_prioridade_de_pagamento(uuid, int, uuid) from public, anon, authenticated;
grant execute on function public._quem_da_conta(uuid, text) to service_role;
grant execute on function public.pagamentos_da_semana(date, date) to service_role;
grant execute on function public.definir_prioridade_de_pagamento(uuid, int, uuid) to service_role;
