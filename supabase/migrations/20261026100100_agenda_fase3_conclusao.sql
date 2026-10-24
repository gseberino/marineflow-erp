-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P2: a conclusão no banco — a porta
-- completa (conclusão, faturamento, reabertura e conversão ORÇ→OS mantendo o número), as cobranças da conclusão portadas da
-- tela com paridade, a entrega, os marcos, o desfazer da conclusão e da entrega, e o sinal pago que também mantém o número.
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§5; §3.2, §3.3 d5–d9, d25–d27; §13.4, §13.6). Notas entre pacotes:
-- notas-fase3.md ("Para o P2": a porta MANTÉM A PARIDADE com a tela; corrigir o NOVO-agenda-22 é do dono).
-- Depende de 20261026100000 (delivered_at e o gatilho da entrega, agenda_acoes.receivable_ids e os tipos concluir/entregar)
-- e das Fases 1 e 2 inteiras (a porta de 20261025100100, o desfazer de 20261025100200).
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas e recriadas; nenhuma tabela, nenhuma coluna, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE (o D7): hoje a OS é concluída pela tela com um UPDATE direto, e as cobranças da condição saem de
-- ensureCompletionReceivables ANTES dele, no navegador, com o erro engolido: o técnico que conclui não gera cobrança (a RLS de
-- receivables só deixa admin/financeiro inserir, NOVO-agenda-14) e a OS fica "concluída" sem nada a receber. A assinatura do
-- cliente e o sinal pago mudam o status por fora, e o orçamento convertido por eles fica com o número de orçamento
-- (NOVO-agenda-15). Esta migration põe a conclusão no banco: a saída e as cobranças da condição na MESMA transação, ou nada
-- muda e o texto diz por quê.
--
-- O QUE MUDA:
--   1. _os_recebiveis_da_conclusao(OS, dia): o espelho de recebiveisDaConclusao (src/lib/completion-receivables.ts), sem
--      escrever nada: {motivo ja_tem|parcelas|titulo_unico|total_zero|nao_achei, linhas, vencem_na_entrega, total}. A conta é
--      em double e na ordem do TypeScript, e o arredondamento é o Math.round do JavaScript (1,005 dá 1,00). Paridade provada
--      caso a caso contra o JSON que o vitest também confere (scripts/bancada-agenda/recebiveis-casos.json).
--      _os_criar_recebiveis_da_conclusao(OS, dia): insere as linhas e devolve os ids; o erro SOBE (período fechado, coerência).
--   2. _agenda_escrever_conclusao: a SEGUNDA função que liga agenda.porta. Um UPDATE só com o status, a saída (check_out_at),
--      a entrega (delivered_at) e, na conversão, o número, converted_to_os_at e original_quote_amount — os gatilhos de status
--      de produção (vencimento "na entrega", estoque, comissão de vendedor, casos de serviço) veem tudo junto, como no UPDATE
--      da tela. O status só entra no UPDATE quando muda.
--   3. os_transicionar_status recriada com p_check_out no fim (drop da assinatura de 8 argumentos + create da de 9; quem
--      chama com 8 resolve pelo default). Vias novas: tela, assinatura (sem autor, só service_role), equipe (o gestor, sem
--      autor). Agora a porta também:
--        · conclui (ativo → concluída): trava a OS, cria as cobranças ANTES do status (a ordem da tela: o gatilho do vencimento
--          roda depois), grava a saída (a que já existia, senão p_check_out, senão p_agora) e registra agenda_acoes tipo
--          concluir com as cobranças criadas. Erro nas cobranças ou na escrita = nada muda e {ok false} com o texto;
--        · fatura (concluída → faturada) e reabre (concluída → em andamento/aguardando, pela tela ou pelo dono: as cobranças e a
--          saída ficam, como na tela), só o administrador;
--        · converte (orçamento → X pela tela, assistente, dono, aprovação ou assinatura): o número troca SÓ o prefixo ORÇ- por
--          OS-, converted_to_os_at e original_quote_amount uma vez, e na mesma chamada aplica a regra de aprovada → X
--          (orçamento → concluída converte e conclui). Recusado o passo X, a conversão também não fica;
--        · desfaz a conclusão (via desfazer, só de dentro do agenda_desfazer).
--      Quem pode: status de agenda = admin/financeiro, técnico da OS, vendedor pela tela; converter = admin/financeiro,
--      vendedor (tela, assistente), a assinatura; concluir = admin/financeiro, técnico da OS, a assinatura, o gestor (equipe);
--      faturar, reabrir e desfazer a conclusão = admin/financeiro.
--   4. agenda_desfazer recriada (corpo de 20261025100200, um bloco -- FASE 3:) + _agenda_desfazer_marco: o desfazer da
--      conclusão volta o status e a saída, cancela as cobranças que ela criou e a comissão de vendedor que nasceu com ela, e
--      devolve os vencimentos "na entrega" que o gatilho tinha movido; recusa com pagamento, com a OS entregue, fora do prazo ou
--      com a OS já fora de concluída. O desfazer da entrega tira a entrega (e, se ela concluiu junto, a conclusão também).
--   5. os_registrar_marco(OS, conclusao|entrega, via, …): conclusão = a porta; entrega = conclui antes se preciso (na mesma
--      transação) e grava delivered_at (nunca antes da saída) com agenda_acoes tipo entregar.
--   6. agenda_marcos_da_os(OS, dia): entrada, início, conclusão e entrega, os intervalos em dias úteis e o texto pronto.
--   7. handle_quote_deposit_payment recriada (corpo de 20261003210000, a mais nova): ao converter pelo sinal pago, troca o
--      prefixo do número e guarda o valor orçado, como os outros caminhos.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase3_conclusao.sql, _recebiveis.sql e _replay_conclusoes.sql):
--   · Não existe via 'marco' na porta: os_registrar_marco chama a porta com o próprio p_via (tela, dono, assistente, equipe,
--     conferencia), e a origem e quem pode saem dele — é o "origem pelo p_via" da spec com um caminho a menos para autorizar.
--   · os_registrar_marco(p_os, p_marco, p_via, p_quando, …): p_via vem antes de p_quando (na ordem da spec, um parâmetro sem
--     default depois de um com default não compila).
--   · A assinatura também CONVERTE: em produção signature_status_after = 'approved' (SELECT i07 de 24/10), e a ORÇ-00070
--     (assinada em 29/07, nunca convertida, concluída com o número de orçamento) saiu do rascunho por ela, não pelo sinal pago
--     (NOVO-agenda-23). Com a assinatura entre as vias da conversão, o P3 corrige esse caminho ao passar submit-signature pela
--     porta.
--   · O arredondamento é o do Math.round do JavaScript exato (floor + "fração ≥ 0,5"), não floor(x + 0,5): este último erra
--     perto de 0,5 em double (0,49999999999999994 vira 1).
--   · Texto do período fechado: "Não concluí: o período de outubro está fechado no financeiro (as cobranças da conclusão
--     entrariam nele). Reabra o período e conclua de novo." — a spec sugeria "conclua com outra data", mas as cobranças usam
--     o dia de hoje (p_hoje, paridade com a tela), não a data da saída: outra data não resolve.
--   · O status de agenda pelo gestor (via equipe) é desfazível como o do motor e da vigia (é ação autônoma).
--   · O desfazer da conclusão também devolve o vencimento das cobranças "na entrega" que já existiam (o gatilho de produção
--     as tinha movido para o dia da saída) e o das cobranças em collections; a spec não dizia.
--
-- PARIDADE INTENCIONAL (não é correção, de propósito):
--   · NOVO-agenda-22: a OS que só tem o sinal não ganha o saldo na conclusão (qualquer recebível vivo = "já tem"). Corrigir é
--     decisão do dono; o caso está em recebiveis-casos.json e no teste.
--   · NOVO-agenda-21: o gatilho de produção sync_balance_due_on_completion põe a parcela "na entrega" no check_out_at::date
--     do fuso da sessão (UTC): concluir depois das 21h de Brasília faz ela vencer no dia seguinte. A porta não mexe nisso.
--   · O vencimento das cobranças usa p_hoje (o dia de Brasília), como a tela usava o dia do navegador.
--
-- RISCO REGISTRADO: set_config('agenda.porta', 'on', true) é alcançável por quem tem SQL direto no banco (como na Fase 2). Pela
-- API não: as duas funções que ligam a chave não têm grant. O mesmo vale para agenda.desfaz_conclusao.
--
-- O QUE NÃO MUDA: nenhum caminho do app chama a conclusão pela porta ainda (a tela, a assinatura e o assistente passam no P3);
-- ensureCompletionReceivables continua igual (só a regra virou uma função pura). Nenhum dado é escrito.
--
-- ORDEM DE LIGAR: depois de 20261026100000; antes de 20261026100200 (os caminhos chamam a porta completa).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_conclusao.sql, agenda_fase3_recebiveis.sql e
-- agenda_fase3_replay_conclusoes.sql (begin/rollback; o replay só na bancada, com a fixture). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261026100100_agenda_fase3_conclusao.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100100', 'agenda_fase3_conclusao');"
--
-- IDEMPOTENTE: create or replace function; o drop da assinatura antiga da porta é "if exists"; revoke/grant e comment.

-- ── 1. As cobranças da conclusão (o espelho de recebiveisDaConclusao) ──────────────────────────────────────

-- Number(x) do JavaScript para um valor JSON: número = ele; texto = o número escrito (vazio = 0; o que não é número = NaN);
-- booleano = 1/0; null = 0; lista vazia = 0; o resto = NaN. Só o que as parcelas usam (percentuais e dias).
create or replace function public._os_numero_js(p jsonb)
 returns double precision
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case jsonb_typeof(p)
    when 'number'  then (p #>> '{}')::double precision
    when 'string'  then case
      when btrim(p #>> '{}', E' \t\n\r') = '' then 0::double precision
      when btrim(p #>> '{}', E' \t\n\r') ~ '^[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?$'
        then btrim(p #>> '{}', E' \t\n\r')::double precision
      else 'NaN'::double precision end
    when 'boolean' then case when (p #>> '{}')::boolean then 1::double precision else 0::double precision end
    when 'null'    then 0::double precision
    when 'array'   then case when jsonb_array_length(p) = 0 then 0::double precision else 'NaN'::double precision end
    else 'NaN'::double precision end;
$function$;

comment on function public._os_numero_js(jsonb) is
  'Agenda de Produção (Fase 3, P2): Number() do JavaScript para um valor JSON das parcelas da condição (normalizeInstallment em quote-deposit.ts): número; texto com número (vazio = 0, outro = NaN); booleano 1/0; null 0; lista vazia 0; resto NaN.';

-- O rótulo da parcela como o TS: label || "Parcela <posição>" (vazio, ausente, null, 0 e false viram "Parcela n").
create or replace function public._os_rotulo_js(p jsonb, p_posicao integer)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p is null or jsonb_typeof(p) = 'null' then 'Parcela ' || p_posicao
    when jsonb_typeof(p) = 'string' then coalesce(nullif(p #>> '{}', ''), 'Parcela ' || p_posicao)
    when jsonb_typeof(p) = 'number' then
      case when (p #>> '{}')::numeric = 0 then 'Parcela ' || p_posicao else ((p #>> '{}')::double precision)::text end
    when jsonb_typeof(p) = 'boolean' then case when (p #>> '{}')::boolean then 'true' else 'Parcela ' || p_posicao end
    when jsonb_typeof(p) = 'object' then '[object Object]'
    else (select coalesce(string_agg(x #>> '{}', ',' order by o), '') from jsonb_array_elements(p) with ordinality t(x, o))
  end;
$function$;

comment on function public._os_rotulo_js(jsonb, integer) is
  'Agenda de Produção (Fase 3, P2): o rótulo da parcela como computeAllInstallments: o label, ou "Parcela <posição na lista, de 1 em diante>" quando ele é vazio, ausente, null, 0 ou false.';

create or replace function public._os_recebiveis_da_conclusao(p_os uuid, p_data date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_os     record;
  v_parc   jsonb;
  r        record;
  v_lab    double precision;
  v_parts  double precision;
  v_exp    double precision;
  v_sub    double precision;
  v_base   double precision;
  v_ratio  double precision;
  v_s      double precision;
  v_p      double precision;
  v_x      double precision;
  v_d      double precision;
  v_g      double precision;
  v_n      double precision;
  v_v      double precision;
  v_tipo   text;
  v_rot    text;
  v_valor  numeric(12,2);
  v_linhas jsonb := '[]'::jsonb;
  v_venc   jsonb;
  v_total  numeric := 0;
begin
  if p_os is null or p_data is null then
    raise exception 'Faltam a OS ou o dia da conclusão.' using errcode = '22023';
  end if;
  select so.service_order_number as numero, so.grand_total, so.labor_cost_total, so.parts_cost_total,
         so.operational_cost_total, so.travel_cost_total, so.subcontract_cost_total, so.is_travel_billable,
         so.discount_amount, so.tax_amount, so.custom_payment_installments as personalizadas, pc.installments as do_preset
    into v_os
    from public.service_orders so
    left join public.payment_condition_presets pc on pc.id = so.payment_condition_preset_id
   where so.id = p_os;
  if not found then
    return jsonb_build_object('motivo', 'nao_achei', 'linhas', '[]'::jsonb, 'vencem_na_entrega', '[]'::jsonb, 'total', 0);
  end if;

  -- As cobranças "na entrega" que já existem: o gatilho de produção (sync_balance_due_on_completion) as põe no dia da saída.
  select coalesce(jsonb_agg(jsonb_build_object('id', rc.id, 'description', rc.description, 'amount', rc.amount,
                                               'due_date', rc.due_date) order by rc.created_at, rc.id), '[]'::jsonb)
    into v_venc
    from public.receivables rc
   where rc.service_order_id = p_os and rc.due_on_completion and rc.status not in ('paid', 'cancelled');

  -- Idempotência (a correção de 24/09): QUALQUER recebível vivo — o sinal incluído — é o financeiro da OS.
  if exists (select 1 from public.receivables rc where rc.service_order_id = p_os and rc.status <> 'cancelled') then
    return jsonb_build_object('motivo', 'ja_tem', 'linhas', '[]'::jsonb, 'vencem_na_entrega', v_venc, 'total', 0);
  end if;

  -- As parcelas: as do preset, se forem lista; senão as personalizadas da OS, se forem lista; senão nenhuma.
  v_parc := case when jsonb_typeof(v_os.do_preset) = 'array' then v_os.do_preset
                 when jsonb_typeof(v_os.personalizadas) = 'array' then v_os.personalizadas
                 else '[]'::jsonb end;

  -- A base (depositBaseFromOrder), em double e na ordem das contas do TS. Nulo = 0; deslocamento só quando faturável.
  v_lab   := coalesce(v_os.labor_cost_total, 0)::double precision;
  v_parts := coalesce(v_os.parts_cost_total, 0)::double precision;
  v_exp   := (coalesce(v_os.operational_cost_total, 0)::double precision
              + case when v_os.is_travel_billable is distinct from false
                     then coalesce(v_os.travel_cost_total, 0)::double precision else 0::double precision end)
             + coalesce(v_os.subcontract_cost_total, 0)::double precision;
  v_sub   := (v_lab + v_parts) + v_exp;
  v_base  := (v_sub - coalesce(v_os.discount_amount, 0)::double precision) + coalesce(v_os.tax_amount, 0)::double precision;
  v_ratio := case when v_sub > 0 then v_base / v_sub else 1::double precision end;

  for r in select t.e, t.o::int as o from jsonb_array_elements(v_parc) with ordinality t(e, o) order by t.o loop
    -- normalizeInstallment: services/parts caem no percent antigo; despesas e dias não.
    v_s := public._os_numero_js(coalesce(nullif(r.e -> 'services_pct', 'null'::jsonb), nullif(r.e -> 'percent', 'null'::jsonb), '0'::jsonb));
    v_p := public._os_numero_js(coalesce(nullif(r.e -> 'parts_pct', 'null'::jsonb), nullif(r.e -> 'percent', 'null'::jsonb), '0'::jsonb));
    v_x := public._os_numero_js(coalesce(nullif(r.e -> 'expenses_pct', 'null'::jsonb), '0'::jsonb));
    v_d := public._os_numero_js(coalesce(nullif(r.e -> 'days_after_approval', 'null'::jsonb), '0'::jsonb));
    -- depositAmountFromPcts: (mão de obra·s% + peças·p% + despesas·x%) × discountRatio, arredondado como
    -- Math.round(n * 100) / 100 sobre double (o inteiro mais próximo; o meio vai para cima).
    v_g := (v_lab * v_s / 100 + v_parts * v_p / 100) + v_exp * v_x / 100;
    v_n := (v_g * v_ratio) * 100;
    v_v := (floor(v_n) + case when v_n - floor(v_n) >= 0.5 then 1 else 0 end) / 100;
    -- Só parcela com valor (NaN fica de fora: no Postgres NaN é maior que tudo, no JS "NaN > 0" é falso).
    if v_v <> 'NaN'::double precision and v_v > 0 then
      v_tipo  := case when jsonb_typeof(r.e) = 'object' then r.e ->> 'tipo' end;
      v_rot   := public._os_rotulo_js(case when jsonb_typeof(r.e) = 'object' then r.e -> 'label' end, r.o);
      v_valor := v_v::numeric(12,2);
      v_linhas := v_linhas || jsonb_build_object(
        'description', v_rot || ' — ' || v_os.numero,
        'issue_date', p_data,
        -- "na entrega" vence na conclusão; o resto, conclusão + os dias (addDays trunca o fracionado; NaN = 0)
        'due_date', case when v_tipo = 'entrega' then p_data
                         else p_data + floor(case when v_d = 'NaN'::double precision then 0 else v_d end)::int end,
        'amount', v_valor,
        'due_on_completion', coalesce(v_tipo = 'entrega', false),
        'rotulo', v_rot, 'tipo', v_tipo, 'posicao', r.o);
      v_total := v_total + v_valor;
    end if;
  end loop;

  if jsonb_array_length(v_linhas) > 0 then
    return jsonb_build_object('motivo', 'parcelas', 'linhas', v_linhas, 'vencem_na_entrega', v_venc, 'total', v_total);
  end if;
  -- Sem parcela com valor: o título único do total, em 30 dias (a descrição é o número como está).
  if coalesce(v_os.grand_total, 0) <= 0 then
    return jsonb_build_object('motivo', 'total_zero', 'linhas', '[]'::jsonb, 'vencem_na_entrega', v_venc, 'total', 0);
  end if;
  return jsonb_build_object('motivo', 'titulo_unico',
    'linhas', jsonb_build_array(jsonb_build_object(
      'description', v_os.numero, 'issue_date', p_data, 'due_date', p_data + 30, 'amount', v_os.grand_total,
      'due_on_completion', false, 'rotulo', null, 'tipo', null, 'posicao', null)),
    'vencem_na_entrega', v_venc, 'total', v_os.grand_total);
end;
$function$;

comment on function public._os_recebiveis_da_conclusao(uuid, date) is
  'Agenda de Produção (Fase 3, P2): as cobranças que a conclusão da OS lança no dia p_data, SEM escrever — o espelho de recebiveisDaConclusao (src/lib/completion-receivables.ts), com paridade provada em supabase/tests/agenda_fase3_recebiveis.sql. {motivo: nao_achei | ja_tem (qualquer recebível vivo, o sinal incluído) | parcelas (um por parcela da condição com valor: "<rótulo> — <número>", "na entrega" vence no dia com due_on_completion, o resto em dia + dias) | titulo_unico (o número, o total, em 30 dias) | total_zero; linhas; vencem_na_entrega (as "na entrega" que já existem e o gatilho vai mover para o dia da saída); total}. Só service_role (a porta e o replay pós-deploy).';

create or replace function public._os_criar_recebiveis_da_conclusao(p_os uuid, p_data date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v     jsonb := public._os_recebiveis_da_conclusao(p_os, p_data);
  v_cli uuid;
  v_l   record;
  v_id  uuid;
  v_ids uuid[] := '{}';
begin
  if v ->> 'motivo' in ('parcelas', 'titulo_unico') then
    select so.client_id into v_cli from public.service_orders so where so.id = p_os;
    for v_l in select t.l from jsonb_array_elements(v -> 'linhas') with ordinality t(l, o) order by t.o loop
      insert into public.receivables (service_order_id, client_id, description, issue_date, due_date, amount, balance_amount,
                                      paid_amount, status, is_deposit, due_on_completion)
      values (p_os, v_cli, v_l.l ->> 'description', (v_l.l ->> 'issue_date')::date, (v_l.l ->> 'due_date')::date,
              (v_l.l ->> 'amount')::numeric, (v_l.l ->> 'amount')::numeric, 0, 'pending', false,
              (v_l.l ->> 'due_on_completion')::boolean)
      returning id into v_id;
      v_ids := v_ids || v_id;
    end loop;
  end if;
  return jsonb_build_object('motivo', v ->> 'motivo', 'criados', to_jsonb(v_ids), 'linhas', v -> 'linhas',
                            'vencem_na_entrega', v -> 'vencem_na_entrega', 'total', v -> 'total');
end;
$function$;

comment on function public._os_criar_recebiveis_da_conclusao(uuid, date) is
  'Agenda de Produção (Fase 3, P2): insere as cobranças de _os_recebiveis_da_conclusao (pendentes, uma por linha, na ordem) e devolve {motivo, criados: [ids], linhas, vencem_na_entrega, total}. O erro SOBE (período fechado, coerência do recebível, orçamento agrupado): quem chama decide — a porta faz tudo ou nada. Sem grant.';

-- ── 2. A escrita da conclusão (a segunda chave da porta) ──────────────────────────────────────────────────
create or replace function public._agenda_escrever_conclusao(
  p_os               uuid,
  p_status           text,
  p_check_out        timestamptz,
  p_limpar_check_out boolean,
  p_delivered        timestamptz,
  p_conversao        jsonb,
  p_check_in         timestamptz default null,
  p_limpar_entrega   boolean     default false)
 returns void
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_status text;
begin
  select so.status into v_status from public.service_orders so where so.id = p_os for update;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  perform set_config('agenda.porta', 'on', true);
  -- Um UPDATE só: os gatilhos de status veem a saída, a entrega e a conversão junto. O status só entra quando muda (os
  -- gatilhos "AFTER UPDATE OF status" disparam pela coluna listada, mesmo com o valor igual).
  if p_status is not null and p_status is distinct from v_status then
    update public.service_orders so
       set status                = p_status,
           check_in_at           = coalesce(so.check_in_at, p_check_in),
           check_out_at          = case when coalesce(p_limpar_check_out, false) then null
                                        else coalesce(so.check_out_at, p_check_out) end,
           delivered_at          = case when coalesce(p_limpar_entrega, false) then null
                                        else coalesce(p_delivered, so.delivered_at) end,
           service_order_number  = coalesce(p_conversao ->> 'numero', so.service_order_number),
           converted_to_os_at    = coalesce(so.converted_to_os_at, (p_conversao ->> 'converted_to_os_at')::timestamptz),
           original_quote_amount = coalesce(so.original_quote_amount, (p_conversao ->> 'original_quote_amount')::numeric)
     where so.id = p_os;
  else
    update public.service_orders so
       set check_in_at           = coalesce(so.check_in_at, p_check_in),
           check_out_at          = case when coalesce(p_limpar_check_out, false) then null
                                        else coalesce(so.check_out_at, p_check_out) end,
           delivered_at          = case when coalesce(p_limpar_entrega, false) then null
                                        else coalesce(p_delivered, so.delivered_at) end,
           service_order_number  = coalesce(p_conversao ->> 'numero', so.service_order_number),
           converted_to_os_at    = coalesce(so.converted_to_os_at, (p_conversao ->> 'converted_to_os_at')::timestamptz),
           original_quote_amount = coalesce(so.original_quote_amount, (p_conversao ->> 'original_quote_amount')::numeric)
     where so.id = p_os;
  end if;
  perform set_config('agenda.porta', 'off', true);
end;
$function$;

comment on function public._agenda_escrever_conclusao(uuid, text, timestamptz, boolean, timestamptz, jsonb, timestamptz, boolean) is
  'Agenda de Produção (Fase 3, P2): a SEGUNDA (e última) função que liga agenda.porta. Um UPDATE só com o status (só se muda), a saída (a que existe, senão p_check_out; p_limpar_check_out apaga), a entrega (p_delivered; p_limpar_entrega apaga), o início (só se vazio) e, na conversão (p_conversao {numero, converted_to_os_at, original_quote_amount}), o número e as duas colunas que só se preenchem uma vez. Sem grant: só as funções security definer da porta a chamam.';

comment on function public._agenda_escrever_os(uuid, text, timestamptz, timestamptz, timestamptz, boolean) is
  'Agenda de Produção (Fase 2): uma das DUAS funções que ligam agenda.porta (a outra é _agenda_escrever_conclusao, Fase 3). Escreve o status (se mudou, com o check-in junto), o check-in (só se estava vazio: nunca sobrescreve) e, com p_espelho, as datas scheduled_* (nulas = a OS saiu do plano). Sem grant: só as funções security definer da agenda a chamam.';

-- ── 3. Textos da conclusão ────────────────────────────────────────────────────────────────────────────────

-- As cobranças, na ordem dos ids: "Entrada 50% R$ 2.280,00 (vence hoje) · Saldo 50% R$ 2.280,00 (vence hoje)". O rótulo é a
-- descrição sem o " — <número>" do fim; o título único (descrição = número) sai só com o valor.
create or replace function public._os_cobrancas_texto(p_ids uuid[], p_hoje date, p_numero text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select string_agg(
           ltrim(case when r.description = p_numero then ''
                      when right(r.description, char_length(' — ' || p_numero)) = ' — ' || p_numero
                        then left(r.description, char_length(r.description) - char_length(' — ' || p_numero))
                      else r.description end || ' ')
           || public._brl(r.amount)
           || ' (vence ' || case when r.due_date = p_hoje then 'hoje' else public._dia_curto(r.due_date) end || ')',
           ' · ' order by u.o)
    from unnest(p_ids) with ordinality u(id, o)
    join public.receivables r on r.id = u.id;
$function$;

comment on function public._os_cobrancas_texto(uuid[], date, text) is
  'Agenda de Produção (Fase 3, P2): as cobranças da conclusão em texto, na ordem: "<rótulo> R$ X (vence hoje|ter 27/10)", separadas por " · ".';

-- O erro que impediu a conclusão, para o dono.
create or replace function public._os_erro_da_conclusao(p_msg text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_msg ~ '^O período de [0-9]{2}/[0-9]{4} está fechado' then
      format('Não concluí: o período de %s está fechado no financeiro (as cobranças da conclusão entrariam nele). Reabra o período e conclua de novo.',
             (array['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro',
                    'novembro', 'dezembro'])[substring(p_msg from '^O período de ([0-9]{2})/')::int])
    else 'Não concluí: ' || rtrim(coalesce(nullif(btrim(p_msg), ''), 'o banco recusou sem dizer por quê'), '. ') || '.'
  end;
$function$;

comment on function public._os_erro_da_conclusao(text) is
  'Agenda de Produção (Fase 3, P2): o texto ao dono quando a conclusão não passa ("Não concluí: o período de outubro está fechado no financeiro …"; outro erro: "Não concluí: <a mensagem do banco>.").';

-- ── 4. A porta completa ───────────────────────────────────────────────────────────────────────────────────
-- FASE 3: a assinatura ganha p_check_out no fim. Quem chama com os 8 argumentos da Fase 2 resolve pela nova (default).
drop function if exists public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz);

create or replace function public.os_transicionar_status(
  p_os        uuid,
  p_para      text,
  p_via       text,
  p_motivo    text        default null,
  p_autor     uuid        default null,
  p_check_in  timestamptz default null,
  p_hoje      date        default public._hoje_brt(),
  p_agora     timestamptz default now(),
  p_check_out timestamptz default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c        public.agenda_config;
  v_uid    uuid := auth.uid();
  v_papel  text;
  v_autor  uuid;
  v_os     record;
  v_de     text;
  v_para   text := p_para;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_nome   text;
  v_check  timestamptz;
  v_novo_check boolean := false;
  v_falta  text;
  v_antes  text;
  v_texto  text;
  v_origem text;
  v_acao   uuid;
  -- FASE 3: quem pode, a conversão, a conclusão e o desfazer dela.
  v_tipo      text;
  v_gestor    boolean := false;
  v_tecnico   boolean := false;
  v_vendedor  boolean := false;
  v_num_novo  text;
  v_acao_conv uuid;
  v_r         jsonb;
  v_conc      public.agenda_acoes%rowtype;
  v_saida     timestamptz;
  v_venc      jsonb;
  v_venc_cob  jsonb;
  v_com_antes uuid[];
  v_coms      uuid[];
  v_rec       jsonb;
  v_ids       uuid[];
  v_erro      text;
  v_cob       text;
  v_venc_dia  date;
  v_venc_soma numeric;
  -- FASE 3: fim
begin
  if p_via is null or p_via not in ('tela_agendar', 'aprovacao', 'assistente', 'check_in', 'oc', 'motor', 'vigia',
                                    'conferencia', 'dono', 'desfazer',
                                    -- FASE 3: a tela (a mudança genérica de status), a assinatura do cliente e o gestor
                                    -- pela palavra do técnico.
                                    'tela', 'assinatura', 'equipe') then
    raise exception 'Caminho desconhecido para mudar o status: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_para is null or p_para not in ('draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client',
                                      'approved', 'completed', 'invoiced', 'cancelled') then
    raise exception 'Status desconhecido: "%".', coalesce(p_para, '') using errcode = '22023';
  end if;
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam a OS, o dia ou a hora para mudar o status.' using errcode = '22023';
  end if;

  perform set_config('agenda.hoje', p_hoje::text, true);
  c := public._agenda_cfg();

  select so.id, so.service_order_number as numero, so.status, so.check_in_at, cl.name as cliente,
         -- FASE 3: o que a conclusão, a entrega e a conversão leem.
         so.check_out_at, so.delivered_at, so.converted_to_os_at, so.grand_total, so.original_quote_amount
    into v_os
    from public.service_orders so
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os
     for update of so;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  -- Quem pede: com login, o próprio login; sem login (service role, o próprio banco), p_autor — motor e vigia podem
  -- vir sem. Um JWT de outro papel sem login não ganha o direito de dizer quem é.
  if v_uid is not null then
    -- FASE 3: a assinatura do cliente vem só pela service_role (submit-signature), nunca com login.
    if p_via = 'assinatura' then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    v_autor := v_uid;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    -- FASE 3: além do motor e da vigia, o gestor (equipe) e a assinatura do cliente vêm sem autor.
    if v_papel not in ('', 'service_role') or (p_autor is null and p_via not in ('motor', 'vigia', 'equipe', 'assinatura')) then
      raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
    end if;
    -- FASE 3: a assinatura é do cliente: nunca tem autor.
    v_autor := case when p_via = 'assinatura' then null else p_autor end;
  end if;

  -- FASE 3: quem pode muda com o que se pede (spec-fase3 §5.3). A régua da Fase 2 (admin/financeiro ativo ou técnico ativo
  -- da OS, com a mesma frase) continua para o status de agenda, e o vendedor ativo entra nela pela tela; converter,
  -- concluir, faturar e reabrir têm a régua e a frase delas.
  if v_autor is not null then
    v_gestor   := public.is_admin_or_financial(v_autor);
    v_tecnico  := exists (select 1 from public.service_order_technicians t
                            join public.app_users u on u.id = t.user_id
                           where t.service_order_id = p_os and t.user_id = v_autor and u.active);
    v_vendedor := exists (select 1 from public.app_users u where u.id = v_autor and u.active and u.role = 'seller');
  end if;
  v_tipo := case
    when v_os.status = 'draft' and v_para not in ('draft', 'cancelled')
         and p_via in ('tela', 'assistente', 'dono', 'aprovacao', 'assinatura') then 'conversao'
    when v_os.status not in ('draft', 'completed', 'invoiced', 'cancelled') and v_para = 'completed' then 'concluir'
    when v_os.status = 'completed' and v_para not in ('completed', 'cancelled')
         and ((v_para = 'invoiced' and p_via in ('tela', 'assistente', 'dono'))
              or (v_para in ('in_progress', 'awaiting_parts', 'awaiting_client') and p_via in ('tela', 'dono'))
              or p_via = 'desfazer') then 'encerrada'
    else 'agenda' end;
  if v_tipo = 'agenda' and v_autor is not null and not (v_gestor or v_tecnico or (v_vendedor and p_via = 'tela')) then
    raise exception 'Você não pode mudar o status desta OS.' using errcode = '42501';
  elsif v_tipo = 'conversao'
        and not (v_gestor or (v_vendedor and p_via in ('tela', 'assistente')) or (v_autor is null and p_via = 'assinatura')) then
    raise exception 'Converter orçamento em OS é com o administrador ou o vendedor.' using errcode = '42501';
  elsif v_tipo = 'concluir' and not (v_gestor or v_tecnico or (v_autor is null and p_via in ('equipe', 'assinatura'))) then
    raise exception 'Concluir é com o administrador ou o técnico da OS.' using errcode = '42501';
  elsif v_tipo = 'encerrada' and not v_gestor then
    raise exception 'Faturar e reabrir são com o administrador.' using errcode = '42501';
  end if;
  -- FASE 3: a origem de cada caminho (estava depois da escrita; a conclusão e a conversão também a usam).
  v_origem := case p_via
    when 'tela_agendar' then 'tela'
    when 'check_in'     then 'sistema'
    when 'oc'           then 'sistema'
    when 'desfazer'     then 'dono'
    when 'assinatura'   then 'sistema'
    else p_via end;
  -- FASE 3: fim

  v_de   := v_os.status;
  v_nome := coalesce(public._agenda_nome_curto(v_os.cliente) || ' (' || v_os.numero || ')', v_os.numero);

  -- FASE 3: encerrada, faturada, cancelada e orçamento. A Fase 2 recusava tudo aqui ("concluir é pela tela"); agora a
  -- conclusão, o faturamento, a reabertura e a conversão são da porta. Cancelar continua no botão Cancelar OS.
  if v_de = 'cancelled' then
    return public._agenda_porta_fica(false, v_de,
      format('A %s está cancelada: a agenda não muda o status dela.', v_os.numero));
  end if;
  if v_de = 'invoiced' then
    if v_para = 'invoiced' then
      return public._agenda_porta_fica(true, v_de, format('%s já está faturada.', v_nome));
    end if;
    return public._agenda_porta_fica(false, v_de, format('A %s está faturada: reabrir é pelo financeiro.', v_os.numero));
  end if;
  if v_para = 'cancelled' then
    return public._agenda_porta_fica(false, v_de, 'Cancelar é pelo botão Cancelar OS.');
  end if;

  if v_de = 'completed' then
    if v_para = 'completed' then
      return public._agenda_porta_fica(true, v_de, format('%s já está concluída.', v_nome));
    end if;
    if v_tipo <> 'encerrada' then
      return public._agenda_porta_fica(false, v_de,
        format('A %s está concluída: a agenda não muda o status dela.', v_os.numero));
    end if;

    -- O desfazer da conclusão (só de dentro do agenda_desfazer, que diz qual ação desfaz em agenda.desfaz_conclusao):
    -- volta ao status de antes, e a saída sai se foi a conclusão que a gravou.
    if p_via = 'desfazer' then
      select a.* into v_conc
        from public.agenda_acoes a
       where a.id::text = coalesce(current_setting('agenda.desfaz_conclusao', true), '')
         and a.service_order_id = p_os and a.tipo = 'concluir' and a.executada and a.desfeita_em is null;
      if not found or v_conc.status_antes is distinct from v_para then
        return public._agenda_porta_fica(false, v_de,
          'Desfazer a conclusão é pelo *desfaz* da agenda; para reabrir, use a tela da OS.');
      end if;
      perform public._agenda_escrever_conclusao(p_os, v_para, null, (v_conc.antes ->> 'check_out_at') is null, null, null);
      v_texto := format('%s: de concluída para %s (desfeito).', v_nome, public._agenda_status_texto(v_para));
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
              jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at),
              jsonb_build_object('status', v_para, 'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os),
                                 'via', p_via, 'desfaz_conclusao', v_conc.id),
              left(v_texto, 400), v_autor)
      returning id into v_acao;
      return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                                'acao_id', v_acao, 'check_in_at', v_os.check_in_at,
                                'check_out_at', (select so.check_out_at from public.service_orders so where so.id = p_os));
    end if;

    if v_para = 'invoiced' then
      perform public._agenda_escrever_os(p_os, 'invoiced', null, null, null, false);
      v_texto := format('%s: faturada.', v_nome);
    else
      -- Reabrir (paridade com a tela: a saída e as cobranças ficam; o início, se faltava, como no "em andamento").
      if v_para = 'in_progress' and v_os.check_in_at is null then
        v_check := coalesce(p_check_in, p_agora);
        v_novo_check := true;
      end if;
      perform public._agenda_escrever_os(p_os, v_para, v_check, null, null, false);
      v_texto := format('Reabri o %s', v_nome)
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.status <> 'cancelled')
                then '. As cobranças da conclusão continuam; se for o caso, ajuste no financeiro.'
                else ' (agora está ' || public._agenda_status_texto(v_para) || ').' end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor)
    values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
            jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at, 'check_out_at', v_os.check_out_at),
            jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
            left(v_texto, 400), left(v_motivo, 200), v_autor)
    returning id into v_acao;
    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check),
                              'check_out_at', v_os.check_out_at);
  end if;

  if v_de = 'draft' then
    if v_tipo <> 'conversao' then
      return public._agenda_porta_fica(false, v_de, 'Isso ainda é orçamento: converta antes.');
    end if;
    -- A conversão: o número troca SÓ o prefixo (ORÇ-00119 → OS-00119), converted_to_os_at e original_quote_amount uma vez;
    -- depois, na mesma chamada, a regra de aprovada → X. Se o passo X recusar, a conversão também não fica.
    v_num_novo := case when v_os.numero like 'ORÇ-%' then 'OS-' || substr(v_os.numero, 5) else v_os.numero end;
    if v_num_novo <> v_os.numero
       and exists (select 1 from public.service_orders o2 where o2.service_order_number = v_num_novo and o2.id <> p_os) then
      return public._agenda_porta_fica(false, v_de, format('Não converti: o número %s já é de outra OS.', v_num_novo));
    end if;
    begin
      perform public._agenda_escrever_conclusao(p_os, 'approved', null, false, null,
        jsonb_build_object('numero', v_num_novo, 'converted_to_os_at', coalesce(v_os.converted_to_os_at, p_agora),
                           'original_quote_amount', coalesce(v_os.original_quote_amount, nullif(v_os.grand_total, 0))));
      v_texto := format('Orçamento %s virou a %s (aprovada).', v_os.numero, v_num_novo);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                       status_depois, antes, depois, texto, autor)
      values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], 'draft', 'approved',
              jsonb_build_object('status', 'draft', 'numero', v_os.numero, 'converted_to_os_at', v_os.converted_to_os_at),
              jsonb_build_object('status', 'approved', 'numero', v_num_novo, 'convertido', true, 'via', p_via),
              left(v_texto, 400), v_autor)
      returning id into v_acao_conv;
      if v_para = 'approved' then
        return jsonb_build_object('ok', true, 'mudou', true, 'de', 'draft', 'para', 'approved', 'texto', left(v_texto, 400),
                                  'acao_id', v_acao_conv, 'convertido', true, 'numero', v_num_novo,
                                  'numero_antes', v_os.numero, 'check_in_at', v_os.check_in_at);
      end if;
      v_r := public.os_transicionar_status(p_os, v_para, p_via, p_motivo, p_autor, p_check_in, p_hoje, p_agora, p_check_out);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = v_r::text;
      end if;
    exception when sqlstate 'P0098' then
      return sqlerrm::jsonb || jsonb_build_object('de', 'draft', 'para', 'draft', 'mudou', false);
    end;
    return v_r || jsonb_build_object('de', 'draft', 'mudou', true, 'convertido', true, 'numero', v_num_novo,
                                     'numero_antes', v_os.numero, 'acao_conversao', v_acao_conv,
                                     'acao_id', coalesce(v_r -> 'acao_id', to_jsonb(v_acao_conv)),
                                     'texto', left(v_texto || ' ' || coalesce(v_r ->> 'texto', ''), 400));
  end if;

  if v_para = 'draft' then
    return public._agenda_porta_fica(false, v_de, 'Uma OS não volta a ser orçamento pela agenda.');
  end if;
  if v_para = 'invoiced' then
    return public._agenda_porta_fica(false, v_de, 'Fature depois de concluir.');
  end if;

  -- A conclusão (ativo → concluída): (1) a OS já está travada; (2) as cobranças ANTES do status, como a tela (o gatilho do
  -- vencimento "na entrega" roda depois e as acerta); (3) um UPDATE com o status e a saída; (4) a ação concluir com as
  -- cobranças criadas. Erro em (2) ou (3) = nada muda (a OS, as cobranças e a saída ficam como estavam) e o texto diz por quê.
  if v_para = 'completed' then
    -- O retrato do que a conclusão vai mexer, para o desfazer: os vencimentos "na entrega" que o gatilho move e as comissões
    -- que já existiam (a de vendedor nasce no gatilho).
    select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'due_date', r.due_date) order by r.id), '[]'::jsonb) into v_venc
      from public.receivables r
     where r.service_order_id = p_os and r.due_on_completion and r.status not in ('paid', 'cancelled');
    select coalesce(jsonb_agg(jsonb_build_object('id', cc.id, 'due_date', cc.due_date) order by cc.id), '[]'::jsonb) into v_venc_cob
      from public.collections cc
      join public.receivables r on r.id = cc.receivable_id
     where r.service_order_id = p_os and r.due_on_completion and cc.status = 'pending';
    v_com_antes := array(select cm.id from public.commissions cm where cm.service_order_id = p_os);
    v_saida := coalesce(v_os.check_out_at, p_check_out, p_agora);
    begin
      v_rec := public._os_criar_recebiveis_da_conclusao(p_os, p_hoje);
      perform public._agenda_escrever_conclusao(p_os, 'completed', v_saida, false, null, null);
    exception when others then
      get stacked diagnostics v_erro = message_text;
      return public._agenda_porta_fica(false, v_de, public._os_erro_da_conclusao(v_erro));
    end;
    v_ids  := coalesce(array(select (x #>> '{}')::uuid from jsonb_array_elements(v_rec -> 'criados') x), '{}');
    v_coms := array(select cm.id from public.commissions cm
                     where cm.service_order_id = p_os and not (cm.id = any (v_com_antes)) order by cm.id);

    if v_rec ->> 'motivo' in ('parcelas', 'titulo_unico') then
      v_cob := case when cardinality(v_ids) = 1 then 'Cobrança: ' else 'Cobranças: ' end
               || public._os_cobrancas_texto(v_ids, p_hoje, v_os.numero) || '.';
    elsif v_rec ->> 'motivo' = 'total_zero' then
      v_cob := 'Sem cobrança: o total da OS está zerado.';
    else
      select min(r.due_date), sum(r.amount) into v_venc_dia, v_venc_soma
        from public.receivables r
       where r.id in (select (x ->> 'id')::uuid from jsonb_array_elements(v_venc) x);
      v_cob := 'As cobranças já existiam'
        || case when exists (select 1 from public.receivables r where r.service_order_id = p_os and r.is_deposit
                                                                 and r.status in ('paid', 'partially_paid'))
                then ' (sinal pago)' else '' end
        || case when v_venc_dia is not null
                then format('; o saldo na entrega (%s) passa a vencer %s', public._brl(v_venc_soma),
                            case when v_venc_dia = p_hoje then 'hoje' else public._dia_curto(v_venc_dia) end)
                else '' end
        || '.';
    end if;
    v_texto := format('%s: concluída — saída %s %s.', v_nome,
                      public._dia_curto((v_saida at time zone 'America/Sao_Paulo')::date),
                      to_char(v_saida at time zone 'America/Sao_Paulo', 'HH24:MI'))
               || ' ' || v_cob;

    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                     status_depois, antes, depois, texto, motivo, autor, desfazivel_ate, receivable_ids)
    values (clock_timestamp(), p_hoje, true, v_origem, 'concluir', p_os, array[p_os], v_de, 'completed',
            jsonb_build_object('status', v_de, 'check_out_at', v_os.check_out_at, 'vencimentos', v_venc,
                               'cobrancas_vencimento', v_venc_cob),
            jsonb_build_object('status', 'completed', 'check_out_at', v_saida, 'via', p_via, 'cobrancas', v_rec ->> 'motivo',
                               'comissoes', to_jsonb(v_coms)),
            left(v_texto, 400), left(v_motivo, 200), v_autor,
            -- o gestor (equipe) e o dono (palavra, conversa) desfazem; a tela e a assinatura reabrem pela tela.
            case when v_origem in ('equipe', 'dono') then p_agora + c.desfazer_validade end,
            v_ids)
    returning id into v_acao;

    return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', 'completed', 'texto', left(v_texto, 400),
                              'acao_id', v_acao, 'check_in_at', v_os.check_in_at, 'check_out_at', v_saida,
                              'cobrancas', v_rec, 'cobrancas_texto', v_cob);
  end if;
  -- FASE 3: fim

  -- Igual: nada a fazer — menos o início que faltava numa OS em andamento.
  if v_para = v_de then
    if v_de = 'in_progress' and v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    else
      return public._agenda_porta_fica(true, v_de, format('%s já está %s.', v_nome, public._agenda_status_texto(v_de)));
    end if;
  end if;

  -- A regra de cada passagem (vale em todos os modos; a do dia no plano, só em 'ligado').
  if v_para = 'scheduled' then
    if v_de = 'in_progress' then
      return public._agenda_porta_fica(true, v_de, 'A OS já começou: não volta para agendada.');
    end if;
    if v_de = 'awaiting_client' and p_via not in ('dono', 'tela_agendar', 'aprovacao') then
      return public._agenda_porta_fica(true, v_de, 'O cliente ainda não liberou: a OS continua aguardando o cliente.');
    end if;
    if v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    end if;
    if c.modo_proposta = 'ligado' and not public._agenda_os_tem_dia(p_os, p_hoje) then
      return public._agenda_porta_fica(true, v_de,
        format('Sem dia no plano: a OS continua %s.', public._agenda_status_texto(v_de)));
    end if;

  elsif v_para = 'in_progress' then
    if v_os.check_in_at is null then
      v_check := coalesce(p_check_in, p_agora);
      v_novo_check := true;
    end if;

  elsif v_para in ('awaiting_parts', 'awaiting_client') then
    if v_de = 'in_progress' then
      if p_via = 'oc' then
        return public._agenda_porta_fica(true, v_de, 'A OS segue em andamento; a compra foi registrada.');
      end if;
      if p_via <> 'dono' or v_motivo is null then
        return public._agenda_porta_fica(false, v_de,
          'A OS já começou: só volta a aguardar quando você diz que parou e por quê.');
      end if;
    end if;

  elsif v_para in ('open', 'approved') then
    if v_de = 'in_progress' then
      return public._agenda_porta_fica(true, v_de,
        format('A OS já começou: não volta para %s.', public._agenda_status_texto(v_para)));
    end if;
    if v_de = 'scheduled' then
      if p_via not in ('motor', 'vigia', 'desfazer', 'dono') then
        return public._agenda_porta_fica(false, v_de, 'A OS está agendada: para tirar da agenda, desmarque o dia.');
      end if;
      if public._agenda_os_tem_dia(p_os, p_hoje) then
        return public._agenda_porta_fica(false, v_de, 'A OS ainda tem dia no plano: tire o dia antes.');
      end if;
      -- Volta ao que era antes de agendar (aberta ou aprovada); sem registro, aprovada.
      select a.status_antes into v_antes
        from public.agenda_acoes a
       where a.service_order_id = p_os and a.tipo = 'status' and a.executada and a.status_depois = 'scheduled'
       order by a.criada_em desc, a.id desc
       limit 1;
      v_para := case when v_antes in ('open', 'approved') then v_antes else 'approved' end;
    elsif v_de = 'awaiting_parts' then
      v_falta := public._agenda_falta_material(p_os, p_hoje);
      if v_falta is not null then
        return public._agenda_porta_fica(true, v_de,
          format('%s: a OS continua aguardando peças.', v_falta));
      end if;
    elsif v_de = 'awaiting_client' and p_via not in ('dono', 'tela_agendar', 'aprovacao') then
      return public._agenda_porta_fica(true, v_de, 'O cliente ainda não liberou: a OS continua aguardando o cliente.');
    end if;
  end if;

  -- Grava (a única escrita) e registra.
  perform public._agenda_escrever_os(p_os, case when v_para <> v_de then v_para end, v_check, null, null, false);

  v_texto := case
    when v_para = v_de then format('%s: início registrado', v_nome)
    else format('%s: de %s para %s', v_nome, public._agenda_status_texto(v_de), public._agenda_status_texto(v_para)) end
    || case when v_novo_check
            then format(' (%s às %s)', public._dia_curto((v_check at time zone 'America/Sao_Paulo')::date),
                        to_char(v_check at time zone 'America/Sao_Paulo', 'HH24:MI'))
            else '' end
    || coalesce(' — ' || rtrim(v_motivo, '. '), '') || '.';
  -- FASE 3: a origem de cada caminho saiu daqui para antes das regras (a conclusão e a conversão também a usam).

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes,
                                   status_depois, antes, depois, texto, motivo, autor, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, v_origem, 'status', p_os, array[p_os], v_de, v_para,
          jsonb_build_object('status', v_de, 'check_in_at', v_os.check_in_at),
          jsonb_build_object('status', v_para, 'check_in_at', coalesce(v_os.check_in_at, v_check), 'via', p_via),
          left(v_texto, 400), left(v_motivo, 200), v_autor,
          -- FASE 3: o gestor (equipe) desfaz como o motor e a vigia: é ação autônoma.
          case when v_origem in ('motor', 'vigia', 'equipe') then p_agora + c.desfazer_validade end)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'de', v_de, 'para', v_para, 'texto', left(v_texto, 400),
                            'acao_id', v_acao, 'check_in_at', coalesce(v_os.check_in_at, v_check));
end;
$function$;

comment on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 2; Fase 3: conclusão, faturamento, reabertura, conversão e p_check_out): a porta única de status da OS. Vias: tela, tela_agendar, aprovacao, assistente, check_in, oc, motor, vigia, equipe, conferencia, dono, assinatura, desfazer. Status de agenda (todos os modos): em andamento nunca volta (agendada/aberta/aprovada) e só volta a aguardar com "parou" do dono e o motivo (a OC: ok, nada muda); aguardando peças só sai com o material completo; aguardando o cliente só sai pelo dono, a tela de agendar ou a aprovação; agendada só volta (para o status de antes) pela agenda ou pelo dono e sem dia no plano; em modo_proposta ligado, agendada só com dia no plano; check_in_at uma vez. Fase 3: concluir (ativo → concluída) cria as cobranças da condição (_os_criar_recebiveis_da_conclusao, paridade com a tela) ANTES do status e grava a saída num UPDATE só, tudo ou nada ({ok false} com o texto); faturar só concluída; reabrir concluída (tela, dono) mantém saída e cobranças; orçamento → X (tela, assistente, dono, aprovação, assinatura) converte trocando só o prefixo do número e aplica aprovada → X na mesma chamada; cancelar é Cancelar OS. Quem pode: status de agenda = admin/financeiro, técnico da OS, vendedor pela tela; converter = admin/financeiro, vendedor (tela, assistente), assinatura; concluir = admin/financeiro, técnico da OS, assinatura, equipe; faturar/reabrir/desfazer a conclusão = admin/financeiro. Toda mudança: linha em agenda_acoes (status; concluir com receivable_ids; desfazível quando foi motor/vigia/equipe, e a conclusão pela equipe ou pelo dono). Devolve {ok, mudou, de, para, texto, acao_id, check_in_at, check_out_at; na conclusão cobrancas e cobrancas_texto; na conversão convertido, numero, numero_antes}.';

-- ── 5. O desfazer da conclusão e da entrega ───────────────────────────────────────────────────────────────
create or replace function public._agenda_desfazer_marco(p_acao uuid, p_autor uuid, p_via text, p_hoje date,
                                                         p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_a     public.agenda_acoes%rowtype;
  v_os    record;
  v_nome  text;
  v_porta jsonb;
  v_conc  jsonb;
  v_n     int := 0;
  v_valor numeric := 0;
  v_canc  uuid[] := '{}';
  v_coms  int := 0;
  v_cob   text;
  v_txt   text;
  v_acao  uuid;
  v_oque  text;
begin
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found or v_a.tipo not in ('concluir', 'entregar') then
    raise exception 'Não encontrei essa conclusão ou entrega.' using errcode = 'P0002';
  end if;
  select so.id, so.service_order_number as numero, so.status, so.check_out_at, so.delivered_at into v_os
    from public.service_orders so where so.id = v_a.service_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'A OS dessa mudança não existe mais.');
  end if;
  v_nome := public._agenda_rotulo_da_os(v_os.id);
  v_oque := case v_a.tipo when 'concluir' then 'conclusão' else 'entrega' end;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false,
      'texto', format('A %s do %s foi feita na OS: para mudar, use a tela da OS.', v_oque, v_nome));
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá mais para desfazer a %s do %s: passou o prazo. Para mudar, use a tela da OS.', v_oque, v_nome));
  end if;

  if v_a.tipo = 'entregar' then
    if v_os.delivered_at is distinct from (v_a.depois ->> 'delivered_at')::timestamptz then
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: a entrega do %s mudou depois. Para mudar, use a tela da OS.', v_nome));
    end if;
    -- A entrega sai; se ela concluiu junto, a conclusão volta também (tudo ou nada).
    begin
      perform public._agenda_escrever_conclusao(v_os.id, null, null, false, null, null, null, true);
      if v_a.depois ? 'concluir_acao' then
        v_conc := public._agenda_desfazer_marco((v_a.depois ->> 'concluir_acao')::uuid, p_autor, p_via, p_hoje, p_agora);
        if not coalesce((v_conc ->> 'ok')::boolean, false) then
          raise exception using errcode = 'P0097', message = coalesce(v_conc ->> 'texto', 'Não dá para desfazer.');
        end if;
      end if;
    exception when sqlstate 'P0097' then
      return jsonb_build_object('ok', false, 'texto', sqlerrm);
    end;
    v_txt := case when v_conc is null then format('Desfeito: tirei a entrega do %s.', v_nome)
                  else format('Desfeito: o %s voltou para %s, sem a entrega%s.', v_nome, v_conc ->> 'status_texto',
                              coalesce('; ' || (v_conc ->> 'cobrancas_texto'), '')) end;
  else
    if v_os.status <> 'completed' then
      return jsonb_build_object('ok', false, 'texto',
        format('Não dá para desfazer: o %s já não está concluído (está %s).', v_nome, public._agenda_status_texto(v_os.status)));
    end if;
    if v_os.delivered_at is not null then
      return jsonb_build_object('ok', false, 'texto',
        format('Não dá para desfazer a conclusão: o %s já foi entregue (%s). Desfaça a entrega antes.', v_nome,
               public._dia_curto((v_os.delivered_at at time zone 'America/Sao_Paulo')::date)));
    end if;
    if exists (select 1 from public.receivables r
                where r.id = any (v_a.receivable_ids)
                  and (coalesce(r.paid_amount, 0) > 0
                       or exists (select 1 from public.payments p where p.receivable_id = r.id and p.status = 'confirmed'))) then
      return jsonb_build_object('ok', false,
        'texto', 'Não dá para desfazer: já entrou pagamento na cobrança da conclusão. Reabra pela OS e ajuste no financeiro.');
    end if;
    -- O status e a saída voltam pela porta (via desfazer), que só aceita com a ação dita aqui.
    perform set_config('agenda.desfaz_conclusao', v_a.id::text, true);
    v_porta := public.os_transicionar_status(v_os.id, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
    perform set_config('agenda.desfaz_conclusao', '', true);
    if not coalesce((v_porta ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'texto', v_porta ->> 'texto');
    end if;
    -- As cobranças que a conclusão criou.
    with x as (
      update public.receivables r set status = 'cancelled', balance_amount = 0
       where r.id = any (v_a.receivable_ids) and r.status is distinct from 'cancelled'
      returning r.id, r.amount)
    select count(*), coalesce(sum(x.amount), 0), coalesce(array_agg(x.id), '{}') into v_n, v_valor, v_canc from x;
    -- A comissão de vendedor que nasceu com ela, se ainda pendente e sem conta a pagar.
    with m as (
      update public.commissions cm set status = 'cancelled', updated_at = p_agora
       where cm.id in (select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(v_a.depois -> 'comissoes', '[]'::jsonb)) x)
         and cm.status = 'pending' and cm.payable_id is null
      returning 1)
    select count(*) into v_coms from m;
    -- Os vencimentos "na entrega" que o gatilho tinha posto no dia da saída voltam ao que eram.
    update public.receivables r set due_date = (x ->> 'due_date')::date
      from jsonb_array_elements(coalesce(v_a.antes -> 'vencimentos', '[]'::jsonb)) x
     where r.id = (x ->> 'id')::uuid and r.due_on_completion and r.status not in ('paid', 'cancelled');
    update public.collections cc set due_date = (x ->> 'due_date')::date
      from jsonb_array_elements(coalesce(v_a.antes -> 'cobrancas_vencimento', '[]'::jsonb)) x
     where cc.id = (x ->> 'id')::uuid and cc.status = 'pending';
    v_cob := case when v_n = 1 then format('cancelei a cobrança de %s da conclusão', public._brl(v_valor))
                  when v_n > 1 then format('cancelei as %s cobranças da conclusão (%s)', v_n, public._brl(v_valor)) end;
    if v_coms > 0 then
      v_cob := coalesce(v_cob || ' e a comissão de vendedor que ela gerou', 'cancelei a comissão de vendedor que ela gerou');
    end if;
    v_txt := format('Desfeito: o %s voltou para %s%s.', v_nome, public._agenda_status_texto(v_a.status_antes),
                    coalesce('; ' || v_cob, ''));
  end if;

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   autor, desfaz_a, receivable_ids)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer',
          v_os.id, array[v_os.id], jsonb_build_object('acao', v_a.id, 'tipo', v_a.tipo),
          jsonb_build_object('cobrancas_canceladas', to_jsonb(v_canc), 'comissoes_canceladas', v_coms), left(v_txt, 400),
          p_autor, v_a.id, v_canc)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  return jsonb_build_object('ok', true, 'texto', left(v_txt, 400), 'acao_id', v_acao,
                            'status_texto', public._agenda_status_texto(coalesce(v_a.status_antes, v_os.status)),
                            'cobrancas_texto', v_cob, 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public._agenda_desfazer_marco(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P2): o desfazer de uma ação concluir ou entregar (chamado pelo agenda_desfazer). Recusa (nada muda): feita pela tela/assinatura (sem desfazivel_ate), fora do prazo, a OS já não concluída, entregue (desfaça a entrega antes) ou com pagamento numa cobrança da conclusão. Concluir: o status de antes e a saída (se foi a conclusão que a gravou) pela porta (via desfazer), as cobranças da conclusão canceladas, a comissão de vendedor que nasceu com ela cancelada (pendente e sem conta a pagar) e os vencimentos "na entrega" de volta. Entregar: tira a entrega; a que concluiu junto desfaz a conclusão também (tudo ou nada). Nova ação desfazer e a original ganha desfeita_*. Sem grant.';

-- ── 5b. agenda_desfazer recriada (corpo de 20261025100200, a única que a define; a mudança é o bloco -- FASE 3:) ──────
create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega).';

-- ── 6. Os marcos: conclusão e entrega ─────────────────────────────────────────────────────────────────────
create or replace function public.os_registrar_marco(
  p_os     uuid,
  p_marco  text,
  p_via    text,
  p_quando timestamptz default null,
  p_autor  uuid        default null,
  p_trecho text        default null,
  p_hoje   date        default public._hoje_brt(),
  p_agora  timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c         public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_autor   uuid;
  v_os      record;
  v_nome    text;
  v_conc    jsonb;
  v_saida   timestamptz;
  v_entrega timestamptz;
  v_texto   text;
  v_acao    uuid;
  v_dia     text;
begin
  if p_marco is null or p_marco not in ('conclusao', 'entrega') then
    raise exception 'Marco desconhecido: "%".', coalesce(p_marco, '') using errcode = '22023';
  end if;
  if p_via is null or p_via not in ('tela', 'dono', 'assistente', 'equipe', 'conferencia') then
    raise exception 'Caminho desconhecido para o marco: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam a OS, o dia ou a hora do marco.' using errcode = '22023';
  end if;

  -- A conclusão é a porta (com o caminho de quem pediu: a origem e quem pode saem dele).
  if p_marco = 'conclusao' then
    return public.os_transicionar_status(p_os, 'completed', p_via, p_trecho, p_autor, null, p_hoje, p_agora, p_quando)
           || jsonb_build_object('marco', 'conclusao');
  end if;

  perform set_config('agenda.hoje', p_hoje::text, true);
  c := public._agenda_cfg();
  select so.id, so.service_order_number as numero, so.status, so.check_out_at, so.delivered_at, cl.name as cliente
    into v_os
    from public.service_orders so
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os
     for update of so;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;

  -- Quem pede: a régua de concluir da porta (admin/financeiro ativo ou técnico ativo da OS; o gestor, sem autor).
  if v_uid is not null then
    v_autor := v_uid;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') or (p_autor is null and p_via <> 'equipe') then
      raise exception 'Registrar a entrega é com o administrador ou o técnico da OS.' using errcode = '42501';
    end if;
    v_autor := p_autor;
  end if;
  if v_autor is not null
     and not (public.is_admin_or_financial(v_autor)
              or exists (select 1 from public.service_order_technicians t
                           join public.app_users u on u.id = t.user_id
                          where t.service_order_id = p_os and t.user_id = v_autor and u.active)) then
    raise exception 'Registrar a entrega é com o administrador ou o técnico da OS.' using errcode = '42501';
  end if;

  v_nome := coalesce(public._agenda_nome_curto(v_os.cliente) || ' (' || v_os.numero || ')', v_os.numero);
  if v_os.delivered_at is not null then
    return jsonb_build_object('ok', true, 'mudou', false, 'marco', 'entrega', 'delivered_at', v_os.delivered_at,
      'texto', format('O %s já foi entregue em %s.', v_nome,
                      public._dia_curto((v_os.delivered_at at time zone 'America/Sao_Paulo')::date)));
  end if;
  if v_os.status = 'cancelled' then
    return jsonb_build_object('ok', false, 'mudou', false, 'marco', 'entrega',
      'texto', format('A %s está cancelada: não registro a entrega.', v_os.numero));
  end if;

  -- Concluído ≠ entregue, sem caminho que pule a conclusão: a OS ainda aberta conclui antes, na mesma transação.
  v_saida := v_os.check_out_at;
  if v_os.status not in ('completed', 'invoiced') then
    v_conc := public.os_transicionar_status(p_os, 'completed', p_via, p_trecho, p_autor, null, p_hoje, p_agora, p_quando);
    if not coalesce((v_conc ->> 'ok')::boolean, false) or v_conc ->> 'para' is distinct from 'completed' then
      return v_conc || jsonb_build_object('marco', 'entrega', 'mudou', false);
    end if;
    v_saida := (v_conc ->> 'check_out_at')::timestamptz;
  end if;
  -- A entrega nunca antes da saída.
  v_entrega := greatest(coalesce(p_quando, p_agora), v_saida);
  perform public._agenda_escrever_conclusao(p_os, null, null, false, v_entrega, null);

  v_dia := format('%s às %s', public._dia_curto((v_entrega at time zone 'America/Sao_Paulo')::date),
                  to_char(v_entrega at time zone 'America/Sao_Paulo', 'HH24:MI'));
  v_texto := case when v_conc is null then format('Entregue: o %s, %s.', v_nome, v_dia)
                  else format('O %s ainda estava %s: concluí e marquei a entrega (%s). %s', v_nome,
                              public._agenda_status_texto(v_conc ->> 'de'), v_dia, coalesce(v_conc ->> 'cobrancas_texto', ''))
             end;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, autor, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, p_via, 'entregar', p_os, array[p_os],
          jsonb_build_object('status', v_os.status, 'delivered_at', null),
          jsonb_build_object('delivered_at', v_entrega, 'via', p_via)
            || case when v_conc is not null then jsonb_build_object('concluir_acao', v_conc -> 'acao_id') else '{}'::jsonb end,
          left(rtrim(v_texto), 400), left(nullif(btrim(coalesce(p_trecho, '')), ''), 200), v_autor,
          case when p_via in ('equipe', 'dono') then p_agora + c.desfazer_validade end)
  returning id into v_acao;

  return jsonb_build_object('ok', true, 'mudou', true, 'marco', 'entrega', 'texto', left(rtrim(v_texto), 400),
                            'acao_id', v_acao, 'delivered_at', v_entrega, 'concluiu', v_conc is not null,
                            'conclusao', v_conc);
end;
$function$;

comment on function public.os_registrar_marco(uuid, text, text, timestamptz, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P2): o marco da OS. conclusao = a porta (os_transicionar_status → concluída, com o p_via de quem pediu: tela, dono, assistente, equipe, conferencia; p_quando vira a saída se ela ainda não existe). entrega = admin/financeiro ou técnico da OS (o gestor, via equipe, sem autor): a OS que ainda não está concluída conclui antes, na mesma transação (se a conclusão recusa, nada muda); delivered_at = p_quando (senão agora), nunca antes da saída; ação entregar (desfazível quando foi o dono ou o gestor; a que concluiu junto aponta a conclusão em depois.concluir_acao). Já entregue: {ok true, mudou false} "O Lenine (OS-00074) já foi entregue em sex 30/10."';

-- ── 7. Os 4 marcos da OS (o cartão "Plano" e agenda_ver foco marcos) ──────────────────────────────────────
create or replace function public.agenda_marcos_da_os(p_os uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v       record;
  v_fonte text;
  d_ent   date;
  d_ini   date;
  d_con   date;
  d_ent2  date;
  du_ini  int;
  du_con  int;
  du_ent  int;
  v_du    text := ' (%s du)';
begin
  select so.converted_to_os_at, so.signed_at, so.created_at, so.check_in_at, so.check_out_at, so.delivered_at into v
    from public.service_orders so where so.id = p_os;
  if not found then
    raise exception 'Não encontrei a OS.' using errcode = 'P0002';
  end if;
  -- A entrada: a conversão, senão a assinatura, senão a criação (a mesma régua de aprovada_em da Fase 1).
  v_fonte := case when v.converted_to_os_at is not null then 'conversao'
                  when v.signed_at is not null then 'assinatura' else 'criacao' end;
  d_ent  := (coalesce(v.converted_to_os_at, v.signed_at, v.created_at) at time zone 'America/Sao_Paulo')::date;
  d_ini  := (v.check_in_at at time zone 'America/Sao_Paulo')::date;
  d_con  := (v.check_out_at at time zone 'America/Sao_Paulo')::date;
  d_ent2 := (v.delivered_at at time zone 'America/Sao_Paulo')::date;
  -- Cada intervalo conta do marco anterior que existe.
  du_ini := public.agenda_du_entre(d_ent, d_ini);
  du_con := public.agenda_du_entre(coalesce(d_ini, d_ent), d_con);
  du_ent := public.agenda_du_entre(d_con, d_ent2);
  return jsonb_build_object(
    'entrada',   jsonb_build_object('em', coalesce(v.converted_to_os_at, v.signed_at, v.created_at), 'dia', d_ent, 'fonte', v_fonte),
    'inicio',    jsonb_build_object('em', v.check_in_at, 'dia', d_ini, 'du', du_ini),
    'conclusao', jsonb_build_object('em', v.check_out_at, 'dia', d_con, 'du', du_con),
    'entrega',   jsonb_build_object('em', v.delivered_at, 'dia', d_ent2, 'du', du_ent),
    'sem_entrega_du', case when d_con is not null and d_ent2 is null then public.agenda_du_entre(d_con, p_hoje) end,
    'texto', 'Entrada ' || public._dia_curto(d_ent)
      || ' · início '    || coalesce(public._dia_curto(d_ini)  || case when du_ini > 0 then format(v_du, du_ini) else '' end, '—')
      || ' · conclusão ' || coalesce(public._dia_curto(d_con)  || case when du_con > 0 then format(v_du, du_con) else '' end, '—')
      || ' · entrega '   || coalesce(public._dia_curto(d_ent2) || case when du_ent > 0 then format(v_du, du_ent) else '' end, '—'));
end;
$function$;

comment on function public.agenda_marcos_da_os(uuid, date) is
  'Agenda de Produção (Fase 3, P2): os 4 marcos da OS — entrada (conversão, senão assinatura, senão criação, com a fonte), início (check_in_at), conclusão (check_out_at), entrega (delivered_at) —, cada um com o dia de Brasília e os dias úteis desde o marco anterior que existe; sem_entrega_du = concluída e ainda não entregue há N du; e o texto pronto: "Entrada qua 22/09 · início ter 27/10 (24 du) · conclusão ter 27/10 · entrega sex 30/10 (3 du)" (marco sem data = "—"). Invoker: lê agenda_config pelo dia útil (admin/financeiro, ou as funções definer).';

-- ── 8. O sinal pago também mantém o número (corpo de 20261003210000, a definição mais nova) ───────────────
create or replace function public.handle_quote_deposit_payment()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- Only fire when status moves TO paid/partially_paid
  if new.service_order_id is not null
     and new.status in ('paid', 'partially_paid')
     and (old.status is distinct from new.status) then

    update public.service_orders so
    set
      converted_to_os_at = now(),
      status             = 'approved',
      quote_status       = 'approved',
      -- FASE 3: a conversão troca só o prefixo do número (ORÇ-00119 → OS-00119), como a tela, register_deposit_and_convert
      -- e a porta; se o número novo já for de outra OS, fica o de agora (o pagamento nunca quebra por isso).
      service_order_number = case
        when so.service_order_number like 'ORÇ-%'
             and not exists (select 1 from public.service_orders o2
                              where o2.service_order_number = 'OS-' || substr(so.service_order_number, 5) and o2.id <> so.id)
          then 'OS-' || substr(so.service_order_number, 5)
        else so.service_order_number end,
      -- FASE 3: o valor orçado fica guardado (valor orçado × realizado), como nos outros caminhos da conversão.
      original_quote_amount = coalesce(so.original_quote_amount, nullif(so.grand_total, 0))
    where so.id                  = new.service_order_id
      and so.converted_to_os_at  is null
      and so.quote_status         = 'awaiting_deposit';

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
$function$;

comment on function public.handle_quote_deposit_payment() is
  'Gatilho on_quote_deposit_paid (AFTER UPDATE em receivables): o recebível da OS que passa a pago/parcialmente pago converte o orçamento que aguardava sinal (converted_to_os_at, status e quote_status aprovados; Fase 3: o número troca só o prefixo ORÇ- por OS- e o valor orçado fica em original_quote_amount) ou, numa OS já convertida, só aprova o orçamento.';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
-- A porta e o marco: o painel (authenticated, com o cargo conferido dentro) e o WhatsApp/motor (service_role). Nunca anon.
revoke all on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)
  to authenticated, service_role;
revoke all on function public.os_registrar_marco(uuid, text, text, timestamptz, uuid, text, date, timestamptz) from public, anon;
grant execute on function public.os_registrar_marco(uuid, text, text, timestamptz, uuid, text, date, timestamptz)
  to authenticated, service_role;
-- Os marcos: leitura, como as da Fase 1 (authenticated e service_role).
revoke all on function public.agenda_marcos_da_os(uuid, date) from public, anon;
grant execute on function public.agenda_marcos_da_os(uuid, date) to authenticated, service_role;
-- As cobranças sem escrever: só service_role (a porta, o rascunho do P3 e o replay pós-deploy chamam por dentro).
revoke all on function public._os_recebiveis_da_conclusao(uuid, date), public._os_numero_js(jsonb),
  public._os_rotulo_js(jsonb, integer), public._os_cobrancas_texto(uuid[], date, text), public._os_erro_da_conclusao(text)
  from public, anon, authenticated;
grant execute on function public._os_recebiveis_da_conclusao(uuid, date), public._os_numero_js(jsonb),
  public._os_rotulo_js(jsonb, integer), public._os_cobrancas_texto(uuid[], date, text), public._os_erro_da_conclusao(text)
  to service_role;
-- O que escreve: ninguém de fora (nem service_role). Só as funções security definer da porta.
revoke all on function public._os_criar_recebiveis_da_conclusao(uuid, date),
  public._agenda_escrever_conclusao(uuid, text, timestamptz, boolean, timestamptz, jsonb, timestamptz, boolean),
  public._agenda_desfazer_marco(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated, service_role;
-- O desfazer e o gatilho do sinal: a mesma ACL de antes (create or replace a mantém; o revoke de novo não custa).
revoke all on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) to service_role;
revoke all on function public.handle_quote_deposit_payment() from public, anon, authenticated;
