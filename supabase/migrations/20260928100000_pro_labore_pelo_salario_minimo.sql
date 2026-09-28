-- Pró-labore pelo salário mínimo: o Pix ao sócio pode ser DIVIDIDO em pró-labore + retirada de sócio
-- na mesma linha do banco (28/09/2026, com o "pode fazer" do dono).
--
-- Regra do dono (27/09/2026): "pró-labore é valor do salário mínimo, sempre atualizando". Em cada mês,
-- os pagamentos ao sócio, na ordem do extrato, completam o salário mínimo como "Pró-labore"; o que
-- passa é "Retirada de sócio" (lucro, fora do resultado). Em quase todo mês UM Pix atravessa o limite
-- e cada linha do banco aceitava um lançamento só.
--
-- Desenho (mapeamento de 28/09): o Pix que atravessa vira duas PARTES (payables) na mesma linha,
-- ligadas por divisao_id. Quem soma por categoria (DRE, Despesas, Favorecidos, assistente) fica certo
-- sem mudar. O que supunha "uma linha = um lançamento" passa a olhar o grupo:
--   · a trava de uma linha por lançamento vira uma constraint de exclusão com o MESMO nome: partes do
--     mesmo grupo convivem; lançamento avulso numa linha dividida continua barrado;
--   · desfazer / cancelar juntam as partes antes e seguem como sempre;
--   · corrigir não desencontra as partes (favorecido, data, OS só no pagamento inteiro);
--   · a diferença da Conciliação ("Mês pronto?", item 4) é a soma do grupo contra a linha;
--   · o Extrato com saldo mostra uma linha só por linha do banco.
-- Quem decide o que é pró-labore é a função separar_pro_labore (rotina 2x ao dia, todos os meses
-- abertos). Da revisão independente de 28/09: a regra automática que lançava o Pix do sócio no
-- fornecedor desativado pausa e o CPF sai desse cadastro duplicado; pagamento ao CPF do sócio sem o
-- favorecido é ligado a ele pelo documento; o salário mínimo tem de ser do próprio ano; cada
-- pagamento se separa num bloco próprio (um erro não para os outros) e os avisos vão para
-- app_error_logs; desfazer e cancelar dizem que a ação valeu para o Pix inteiro.

-- ── 1. A parte e a trava ───────────────────────────────────────────────────────────────────────
-- Apagar o principal apaga as partes (inclusive as canceladas, que só guardam a história).
alter table public.payables add column if not exists divisao_id uuid
  references public.payables(id) on delete cascade;
comment on column public.payables.divisao_id is
  'Parte de um pagamento dividido (ex.: pró-labore + retirada de sócio no mesmo Pix): aponta para o lançamento principal do grupo, que fica com divisao_id nulo. As partes somam o valor da linha do banco.';
create index if not exists idx_payables_divisao on public.payables (divisao_id) where divisao_id is not null;

-- Era UNIQUE (bank_transaction_id) WHERE bank_transaction_id IS NOT NULL. O nome continua o mesmo:
-- a tela e o motor traduzem o erro pelo nome ("uma_por_transacao"). Rodar de novo não faz nada.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'payables_uma_por_transacao' and conrelid = 'public.payables'::regclass and contype = 'x') then
    drop index if exists public.payables_uma_por_transacao;
    alter table public.payables add constraint payables_uma_por_transacao
      exclude using gist (bank_transaction_id with =, (coalesce(divisao_id, id)) with <>)
      where (bank_transaction_id is not null);
  end if;
end $$;

-- ── 2. Conferência na hora de gravar: as partes ficam na mesma linha e somam o valor dela ─────────
create or replace function public._confere_divisao_do_grupo(p_raiz uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
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
$$;

create or replace function public._confere_divisao()
returns trigger
language plpgsql security definer
set search_path = public
as $$
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
$$;

drop trigger if exists payables_divisao_confere on public.payables;
create constraint trigger payables_divisao_confere
  after insert or update of amount, status, divisao_id, bank_transaction_id or delete on public.payables
  deferrable initially deferred
  for each row execute function public._confere_divisao();

-- ── 3. Juntar as partes de volta (antes de desfazer ou cancelar) ─────────────────────────────────
-- Devolve o id do lançamento principal. Lançamento que não é de um grupo (ou já cancelado) volta
-- como veio: desfazer e cancelar seguem exatamente como antes.
create or replace function public._juntar_divisao(p_id uuid, p_motivo text, p_autor uuid default null)
returns uuid
language plpgsql security definer
set search_path = public
as $$
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
$$;

-- ── 4. Salário mínimo e quem segue a regra ─────────────────────────────────────────────────────
insert into public.app_settings (key, value, description)
values
  ('salario_minimo', '{"2025-01-01": 1518.00, "2026-01-01": 1621.00}',
   'Salário mínimo nacional por data de vigência (R$ 1.518,00 em 2025, Decreto 12.342/2024; R$ 1.621,00 em 2026, Decreto 12.797/2025). Todo ano entra uma chave nova ("AAAA-01-01": valor). É o pró-labore mensal dos sócios da regra (pro_labore_pelo_salario_minimo).')
on conflict (key) do nothing;
insert into public.app_settings (key, value, description)
select 'pro_labore_pelo_salario_minimo', coalesce(jsonb_agg(p.id)::text, '[]'),
       'Sócios (favorecidos) cujo pró-labore é o salário mínimo do mês; o que passar é retirada de sócio. Regra do dono em 27/09/2026. Lista de ids de payees; lista vazia desliga a separação.'
  from public.payees p
 where p.name = 'Gustavo Seberino da Silva' and p.kind = 'socio'
on conflict (key) do nothing;

create or replace function public._salario_minimo_em(p_data date)
returns numeric
language plpgsql stable security definer
set search_path = public
as $$
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
$$;

create or replace function public._socio_com_pro_labore_pelo_minimo(p_payee uuid)
returns boolean
language plpgsql stable security definer
set search_path = public
as $$
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
$$;

-- O grupo de um lançamento dividido, para as mensagens de desfazer e cancelar dizerem que a ação
-- vale para o Pix inteiro. Nulo quando o lançamento não é de um grupo.
create or replace function public._divisao_de(p_id uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
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
$$;

-- Só o administrador muda o salário mínimo e quem segue a regra (a política geral de app_settings
-- deixa o perfil financeiro mexer, e essas duas chaves mudam o DRE de categorias sensíveis).
create or replace function public._app_settings_chaves_do_dono()
returns trigger
language plpgsql security definer
set search_path = public
as $$
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
$$;
drop trigger if exists app_settings_chaves_do_dono on public.app_settings;
create trigger app_settings_chaves_do_dono
  before insert or update or delete on public.app_settings
  for each row execute function public._app_settings_chaves_do_dono();

-- ── Cadastros do sócio (OK do dono em 27/09: "para os próximos Pix caírem no lugar certo") ──────
-- A regra automática do fornecedor "GUSTAVO SEBERINO" (desativado em 28/09) lançava o Pix do sócio
-- nele, sem o favorecido; e o motor ainda acharia esse fornecedor pelo CPF. A regra pausa, o CPF
-- sai do cadastro duplicado (fica só no favorecido) e o favorecido ganha a categoria padrão.
update public.finance_rules
   set status = 'paused',
       note = btrim(coalesce(note, '') || ' [28/09/2026] Pausada: lançava o Pix do sócio no fornecedor "GUSTAVO SEBERINO", desativado com o OK do dono. O sócio é o favorecido Gustavo Seberino da Silva.')
 where id = '5323b4c8-8c1e-4a05-841c-ba16f06c3899' and status = 'active';
update public.suppliers
   set cnpj_cpf = null,
       notes = btrim(coalesce(notes, '') || ' [28/09/2026] CPF retirado (o do sócio, 104.162.949-44): este cadastro duplicava o favorecido Gustavo Seberino da Silva e fazia o motor lançar o Pix dele aqui. O CPF fica só no favorecido.')
 where id = 'bd723ce9-a171-4ffe-b4ee-8011df3672b6' and not coalesce(active, true)
   and regexp_replace(coalesce(cnpj_cpf, ''), '\D', '', 'g') = '10416294944';
update public.payees set default_category = 'Pró-labore'
 where id = 'ea2cdf81-15d1-4054-84d2-ca2944531fc8' and default_category is null;
update public.financial_categories
   set description = 'Retirada de lucro do sócio: o que passa do pró-labore (o salário mínimo do mês) e gasto pessoal pago pela conta da empresa. Não entra no resultado operacional.'
 where name = 'Retirada de sócio' and type = 'payable';

-- ── 5. Desfazer a aprovação: junta as partes antes (o resto é o de 25/09/2026) ─────────────────────
CREATE OR REPLACE FUNCTION "public"."desfazer_aprovacao"("p_tipo" "text", "p_id" "uuid", "p_motivo" "text" DEFAULT NULL::"text", "p_autor" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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

    -- O pagamento que o CASAMENTO registrou sai junto. Pagamento lançado à mão e só depois
    -- ligado ao extrato continua valendo — medido em 25/09/2026: das 49 linhas do extrato
    -- com pagamento ligado, parte foi criada pela conciliação ("Conciliação automática…",
    -- "Conciliado com o extrato…") e parte pelo dono, semanas antes do casamento. Estornar
    -- o segundo tipo desfaria um recebimento que aconteceu.
    select p.id, p.amount into v_pagamento_id, v_pagamento_valor
      from public.bank_transactions t join public.payments p on p.id = t.reconciled_payment_id
     where t.id = v_tx and p.status = 'confirmed'
       and coalesce(p.notes, '') ilike 'concilia%'
       and ((p_tipo = 'payable' and p.payable_id = p_id) or (p_tipo = 'receivable' and p.receivable_id = p_id));
    if v_pagamento_id is not null then
      update public.payments
         set status = 'cancelled', cancelled_at = now(),
             cancellation_reason = left('Vínculo com o extrato desfeito' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
       where id = v_pagamento_id;
      v_pago := greatest(0, v_pago - v_pagamento_valor);
    end if;

    if p_tipo = 'payable' then
      update public.payables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
    else
      update public.receivables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
    end if;
    update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
    v_msg := 'Vínculo desfeito: o lançamento continua valendo e a linha do extrato voltou para a fila.'
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
                       'proposta_voltou', v_voltaram > 0, 'pagamento_estornado', v_pagamento_id)
  );

  return jsonb_build_object('ok', true, 'acao', v_acao, 'proposta_voltou', v_voltaram > 0, 'message', v_msg);
end;
$$;


-- ── 6. Cancelar: junta as partes antes (o resto é o de 26/09/2026) ─────────────────────────────────
CREATE OR REPLACE FUNCTION "public"."cancelar_lancamento"("p_tipo" "text", "p_id" "uuid", "p_motivo" "text", "p_autor" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'cancelou_lancamento', v_autor, v_tx,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    (v_antes ->> 'amount')::numeric,
    left(v_motivo || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'bank_transaction_id', v_tx, 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('status', 'cancelled', 'linha_do_extrato', v_destino)
  );

  return jsonb_build_object(
    'ok', true,
    'linha_do_extrato', v_destino,
    'message', 'Lançamento cancelado.'
      || case v_destino
           when 'caixa_estornado' then ' O Caixa deixou de contar este valor.'
           when 'fora_da_fila' then ' A linha do extrato foi para "Fora da fila" com o mesmo motivo; de lá ela pode voltar.'
           when 'fila' then ' A linha do extrato voltou para a fila.'
           else '' end
      || coalesce(' ' || (v_grupo ->> 'frase'), '')
  );
end;
$$;


-- ── 7. Corrigir: as partes não se desencontram; pró-labore × retirada é da regra ────────────────────
CREATE OR REPLACE FUNCTION "public"."corrigir_lancamento"("p_tipo" "text", "p_id" "uuid", "p_campos" "jsonb", "p_motivo" "text" DEFAULT NULL::"text", "p_autor" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
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
$_$;


-- ── 8. Extrato com saldo e Conciliação olham o pagamento inteiro ─────────────────────────────────
CREATE OR REPLACE FUNCTION "public"."extrato_da_conta"("p_conexao" "uuid", "p_de" "date", "p_ate" "date") RETURNS TABLE("id" "uuid", "data" "date", "descricao" "text", "contraparte" "text", "documento" "text", "tipo" "text", "valor" numeric, "saldo_apos" numeric, "situacao" "text", "pendente" boolean, "lancamento_tipo" "text", "lancamento_id" "uuid", "lancamento_descricao" "text", "categoria" "text", "quem" "text", "tipo_fora" "text", "motivo_fora" "text", "proposta_id" "uuid")
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
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
$$;


CREATE OR REPLACE VIEW "public"."conciliacao_lancamentos" WITH ("security_invoker"='on') AS
 SELECT 'payable'::"text" AS "lado",
    "p"."id",
    "p"."description",
    "p"."amount",
    "p"."status",
    "p"."due_date",
    "p"."issue_date",
    COALESCE("s"."name", "p"."supplier_name") AS "contraparte",
    "p"."expense_category" AS "categoria",
    "p"."bank_transaction_id",
        CASE
            WHEN ("p"."bank_transaction_id" IS NOT NULL) THEN 'conciliado'::"text"
            WHEN ("p"."payment_method" = 'credito_fornecedor'::"text") THEN 'fora_do_banco'::"text"
            ELSE 'sem_extrato'::"text"
        END AS "situacao",
    "bt"."transaction_date" AS "extrato_data",
    "bt"."amount" AS "extrato_valor",
    "bt"."description" AS "extrato_descricao",
        CASE
            WHEN ("p"."bank_transaction_id" IS NOT NULL) THEN "round"((COALESCE("g"."soma", "p"."amount") - "bt"."amount"), 2)
            ELSE NULL::numeric
        END AS "diferenca",
    (("p"."origin" = 'bank_reconciliation'::"text") OR (EXISTS ( SELECT 1
           FROM "public"."finance_review_queue" "q"
          WHERE ("q"."created_payable_id" = "p"."id")))) AS "nasceu_do_extrato",
        CASE
            WHEN (("bt"."installment_label" ~ '^\d{1,2}/\d{1,2}$'::"text") AND (("split_part"("bt"."installment_label", '/'::"text", 2))::integer >= 2)) THEN ("abs"(("p"."amount" - ((("split_part"("bt"."installment_label", '/'::"text", 2))::integer)::numeric * "bt"."amount"))) <= (((("split_part"("bt"."installment_label", '/'::"text", 2))::integer * (("split_part"("bt"."installment_label", '/'::"text", 2))::integer - 1)))::numeric * 0.01))
            ELSE false
        END AS "compra_parcelada",
        CASE
            WHEN ("bt"."installment_label" ~ '^\d{1,2}/\d{1,2}$'::"text") THEN ("split_part"("bt"."installment_label", '/'::"text", 2))::integer
            ELSE NULL::integer
        END AS "parcelas",
    ("d"."payable_id" IS NOT NULL) AS "lancada_em_dobro"
   FROM ((("public"."payables" "p"
     LEFT JOIN "public"."bank_transactions" "bt" ON (("bt"."id" = "p"."bank_transaction_id")))
     LEFT JOIN "public"."suppliers" "s" ON (("s"."id" = "p"."supplier_id")))
     LEFT JOIN "public"."compras_parceladas_em_dobro" "d" ON (("d"."payable_id" = "p"."id")))
     LEFT JOIN LATERAL ( SELECT "sum"("x"."amount") AS "soma"
           FROM "public"."payables" "x"
          WHERE (("x"."bank_transaction_id" = "p"."bank_transaction_id") AND ("x"."status" <> 'cancelled'::"text")
            AND (COALESCE("x"."divisao_id", "x"."id") = COALESCE("p"."divisao_id", "p"."id")))) "g" ON (("p"."bank_transaction_id" IS NOT NULL))
  WHERE ("p"."status" <> 'cancelled'::"text")
UNION ALL
 SELECT 'receivable'::"text" AS "lado",
    "r"."id",
    "r"."description",
    "r"."amount",
    "r"."status",
    "r"."due_date",
    "r"."issue_date",
    "c"."name" AS "contraparte",
    "r"."category" AS "categoria",
    "r"."bank_transaction_id",
        CASE
            WHEN ("r"."bank_transaction_id" IS NOT NULL) THEN 'conciliado'::"text"
            ELSE 'sem_extrato'::"text"
        END AS "situacao",
    "bt"."transaction_date" AS "extrato_data",
    "bt"."amount" AS "extrato_valor",
    "bt"."description" AS "extrato_descricao",
        CASE
            WHEN ("r"."bank_transaction_id" IS NOT NULL) THEN "round"(("r"."amount" - "bt"."amount"), 2)
            ELSE NULL::numeric
        END AS "diferenca",
    (EXISTS ( SELECT 1
           FROM "public"."finance_review_queue" "q"
          WHERE ("q"."created_receivable_id" = "r"."id"))) AS "nasceu_do_extrato",
    false AS "compra_parcelada",
    NULL::integer AS "parcelas",
    false AS "lancada_em_dobro"
   FROM (("public"."receivables" "r"
     LEFT JOIN "public"."bank_transactions" "bt" ON (("bt"."id" = "r"."bank_transaction_id")))
     LEFT JOIN "public"."clients" "c" ON (("c"."id" = "r"."client_id")))
  WHERE ("r"."status" <> 'cancelled'::"text");


-- ── 9. A separação ─────────────────────────────────────────────────────────────────────────────
-- Leva UM pagamento (o principal e suas partes) ao estado pedido: tudo pró-labore, tudo retirada ou
-- dividido (principal = pró-labore, uma parte = retirada). Devolve 1 se mudou, 0 se já estava assim
-- e -1 se o pagamento mudou desde a leitura (outra pessoa corrigiu no meio): aí não mexe.
create or replace function public._aplicar_pro_labore(
  p_raiz uuid, p_pl numeric, p_ret numeric, p_salario numeric, p_mes date, p_autor uuid default null)
returns integer
language plpgsql security definer
set search_path = public
as $$
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
$$;

-- Para cada sócio da regra: primeiro, o pagamento ao CPF dele que chegou sem o favorecido ganha o
-- favorecido (documento igual identifica, regra do dono). Depois, mês a mês pela data do lançamento
-- (a do DRE e a do fechamento): os pagamentos, na ordem, completam o salário mínimo como pró-labore;
-- o que passa é retirada; o Pix que atravessa o limite é dividido. Padrão: todos os meses abertos
-- desde o primeiro pagamento do sócio. Idempotente: rodar de novo não muda o que já está certo.
-- Mês fechado fica como está; ano sem salário mínimo e pagamento que não deu para separar voltam em
-- "avisos" e vão para a tabela de erros do sistema (a rotina não tem para quem mostrar).
create or replace function public.separar_pro_labore(p_de date default null, p_ate date default null, p_autor uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
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
begin
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
        v_restante := greatest(0, v_salario - v_pl_fora);
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
        if v_mes_pago > 0 or v_pl_fora > 0 then
          v_meses := v_meses || jsonb_build_object(
            'socio', v_socio.name, 'mes', to_char(v_mes, 'YYYY-MM'), 'salario_minimo', v_salario,
            'pago', v_mes_pago, 'pro_labore', v_mes_pl + v_pl_fora, 'retirada', v_mes_ret,
            'pro_labore_fora_da_regra', v_pl_fora,
            'divididos', v_mes_div, 'mudados', v_mes_mudou,
            'faltou_para_o_minimo', greatest(0, v_salario - v_mes_pl - v_pl_fora));
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
$$;

-- ── 10. "Retirada de sócio" sensível, como o Pró-labore (decisão de 03/08/2026) ───────────────────
-- Hoje o dinheiro do sócio inteiro está em "Pró-labore" (sensível: só o administrador vê). Sem isto,
-- a divisão mostraria a retirada a quem não é administrador — e ele veria só uma parte do Pix.
update public.financial_categories set sensitive = true
 where name = 'Retirada de sócio' and type = 'payable' and not sensitive;

-- ── 11. Rotina: 06:20 e 15:20 de Brasília, depois da sincronização e da geração das propostas ─────
select cron.unschedule('separar-pro-labore')
 where exists (select 1 from cron.job where jobname = 'separar-pro-labore');
select cron.schedule('separar-pro-labore', '20 9,18 * * *', $cron$select public.separar_pro_labore()$cron$);

-- ── 12. Permissões: só o sistema chama a separação e as peças internas ───────────────────────────
revoke all on function public.separar_pro_labore(date, date, uuid) from public, anon, authenticated;
grant execute on function public.separar_pro_labore(date, date, uuid) to service_role;
revoke all on function public._aplicar_pro_labore(uuid, numeric, numeric, numeric, date, uuid) from public, anon, authenticated;
revoke all on function public._juntar_divisao(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public._divisao_de(uuid) from public, anon, authenticated;
revoke all on function public._confere_divisao_do_grupo(uuid) from public, anon, authenticated;
revoke all on function public._confere_divisao() from public, anon, authenticated;
revoke all on function public._app_settings_chaves_do_dono() from public, anon, authenticated;
revoke all on function public._salario_minimo_em(date) from public, anon, authenticated;
revoke all on function public._socio_com_pro_labore_pelo_minimo(uuid) from public, anon, authenticated;
revoke all on public.conciliacao_lancamentos from anon;
