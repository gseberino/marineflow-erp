-- Prova da comissão "o maior dos dois" — SÓ A CONTA —, Agenda de Produção Fase 3 (pacote P5; migration 20261026100400).
-- bancada: depende de 20261026100400
--
--   S  o cenário sintético (scripts/bancada-agenda/cenario-comissao.sql, novembro de 2026, números à mão): cada célula das
--      OS, as partes, o centavo da sobra (para menos na maior parte; para mais no empate, ao menor payee_id), o que fica sem
--      dia para dividir, maior/bônus, os avisos; fora da conta: a OS paga em parte, o recebível cancelado, o pagamento
--      cancelado, a nota de homologação e a cancelada; a concluída em outubro e paga em novembro conta em novembro; os
--      parâmetros (competência pela saída; imposto nenhum/sempre; a alíquota de reserva e a falta dela; o início do teste);
--      o mês até hoje e o mês futuro; o texto e a linha; quem pode ver
--   P  o espelho de produção (scripts/bancada-agenda/cenario-comissao-2410.sql: as 21 OS de i04 e as 56 diárias de i09, só
--      números): outubro até 24/10 = R$ 2.094,20 sem dia para dividir (OS-00094/61/77/110); setembro R$ 226,00 (OS-00105);
--      as diárias de 07/09 a 17/10 = R$ 6.040,00; a conciliação com o "≈ R$ 6.600" de 23/10 (20% do VALOR das 6 OS do
--      período, R$ 3.378,00 só da OS-00038); a OS-00038 entra quando for paga; a linha de ter 03/11 (1º dia útil) e o resumo
--      sem mês nos dias antes dele
--   N  nada é escrito (commissions, payables, payments, receivables, work_shifts e work_shift_os com a mesma contagem) e a
--      conta é determinística (md5 de duas chamadas)
--   J  portas (rodam sempre): STABLE, security definer e search_path fixo; anon sem execute; a view security_invoker e sem
--      anon; um JWT sem login de outro papel recebe 42501; os CHECKs de comissao_config (competência, imposto, pagamento)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100400
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_comissao.sql
--   Sem os cenários (produção) S, P e N saem PULADO e só J roda. Os cenários mexem em linhas só dentro de subtransações
--   desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou
-- 'erro <estado>: <mensagem>'. Volta ao dono do teste no fim.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;
-- A conta do mês (com p_hoje) e os pedaços dela.
create function pg_temp.conta(p_mes text, p_hoje text) returns jsonb language sql stable as $f$
  select public.comissao_tecnicos_do_mes(p_mes::date, p_hoje::date)
$f$;
create function pg_temp.os(p_r jsonb, p_numero text) returns jsonb language sql immutable as $f$
  select e from jsonb_array_elements(p_r -> 'os') e where e ->> 'numero' = p_numero
$f$;
create function pg_temp.tec(p_r jsonb, p_nome text) returns jsonb language sql immutable as $f$
  select e from jsonb_array_elements(p_r -> 'tecnicos') e where e ->> 'nome' = p_nome
$f$;
-- A parte de uma pessoa numa OS (null = sem parte).
create function pg_temp.parte(p_r jsonb, p_nome text, p_numero text) returns numeric language sql immutable as $f$
  select (o ->> 'parte')::numeric from jsonb_array_elements(pg_temp.tec(p_r, p_nome) -> 'os') o where o ->> 'numero' = p_numero
$f$;
create function pg_temp.numeros(p_lista jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(e ->> 'numero', ',' order by n), '') from jsonb_array_elements(p_lista) with ordinality x(e, n)
$f$;
create function pg_temp.avisos(p_r jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(a, ',' order by a), '') from jsonb_array_elements_text(p_r -> 'avisos') a
$f$;
-- O que não pode mudar: a contagem das tabelas de dinheiro e das diárias.
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'commissions', (select count(*) from public.commissions), 'payables', (select count(*) from public.payables),
    'payments', (select count(*) from public.payments), 'receivables', (select count(*) from public.receivables),
    'work_shifts', (select count(*) from public.work_shifts), 'work_shift_os', (select count(*) from public.work_shift_os))
$f$;

-- ── S. O cenário sintético (novembro) ─────────────────────────────────────────────────────────────────────
do $s$
declare
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  r2      jsonb;
  o       jsonb;
  t       jsonb;
  v_antes jsonb;
  v_txt   text;
  c_texto_nov constant text := concat_ws(E'\n',
    'Comissão de novembro, em teste — nada foi pago.',
    '• Roberto: diárias R$ 990,00 × comissão R$ 2.488,41 → seria R$ 1.498,41 de bônus.',
    '• João: diárias R$ 300,00 × comissão R$ 418,36 → seria R$ 118,36 de bônus.',
    '• Mickael: diárias R$ 0,00 × comissão R$ 33,33 → seria R$ 33,33 de bônus.',
    '• Sem dia lançado na OS para dividir: R$ 450,00 (OS-00503 R$ 450,00).',
    'A conta: 20% do que entrou menos o material ao custo, as despesas da OS, o imposto da nota e a taxa do cartão; as diárias não entram. '
    || '2 das 9 diárias do mês não estão ligadas a uma OS: elas não contam na divisão. '
    || 'O imposto (6% do Simples) só entra nas OS com nota emitida: 5 das 6 estão sem nota. '
    || 'Sem lucro na conta, comissão zero: OS-00507. '
    || 'Entra quando for paga: OS-00504. '
    || 'Para a conta valer, falta você dizer se o imposto é só nas OS com nota, se a OS conta no mês em que ficou concluída e paga e quando começam os 3 meses de teste.');
  c_linha_nov constant text :=
    'Comissão de novembro (teste, nada pago): diárias R$ 1.290,00 × comissão R$ 2.940,10 (Roberto, João e mais 1); '
    || 'R$ 450,00 sem dia lançado na OS para dividir. *comissão novembro* mostra a conta.';
begin
  if coalesce(current_setting('agenda_teste.cenario_comissao', true), '') = '' then
    insert into _resultado values ('S0 o cenário sintético (cenario-comissao.sql)', true, 'PULADO: sem agenda_teste.cenario_comissao (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.cenario_comissao');
    v_antes := pg_temp.contagens();
    r := pg_temp.conta('2026-11-01', '2026-11-30');

    v_res := pg_temp.ok(v_res, 'S1 novembro: 6 OS na ordem da competência (OS-00505, concluída em outubro e paga em 10/11, entra); a paga em parte (OS-00504) fica fora',
      pg_temp.numeros(r -> 'os') = 'OS-00501,OS-00502,OS-00505,OS-00503,OS-00506,OS-00507'
      and r ->> 'mes' = '2026-11-01' and r ->> 'ate' = '2026-11-30' and (r ->> 'pct')::numeric = 0.2, pg_temp.numeros(r -> 'os'));

    o := pg_temp.os(r, 'OS-00501');
    v_res := pg_temp.ok(v_res, 'S2 OS-00501: competência 06/11 (o pagamento depois da saída), recebido 10.000, material 1.999,50 (2 peças), imposto 0 (a nota de homologação não conta), taxa 300 (pelo líquido), lucro 7.700,50, comissão 1.540,10, 4 dias',
      o ->> 'competencia' = '2026-11-06' and o ->> 'saida' = '2026-11-05' and (o ->> 'recebido')::numeric = 10000
      and (o ->> 'material')::numeric = 1999.50 and (o ->> 'despesas')::numeric = 0 and (o ->> 'imposto')::numeric = 0
      and (o ->> 'sem_nota')::boolean and (o ->> 'taxa_cartao')::numeric = 300 and (o ->> 'lucro')::numeric = 7700.50
      and (o ->> 'comissao')::numeric = 1540.10 and (o ->> 'dias_total')::numeric = 4 and not (o ->> 'lucro_negativo')::boolean
      and not o ? 'id', o::text);

    o := pg_temp.os(r, 'OS-00502');
    v_res := pg_temp.ok(v_res, 'S3 OS-00502 (faturada): recebido 5.000 (o pagamento cancelado fora), imposto 300 (6% com nota de produção), lucro 3.500, comissão 700, 1,5 dia (metade do turno com 2 OS)',
      (o ->> 'recebido')::numeric = 5000 and (o ->> 'material')::numeric = 1200 and (o ->> 'imposto')::numeric = 300
      and not (o ->> 'sem_nota')::boolean and (o ->> 'taxa_cartao')::numeric = 0 and (o ->> 'lucro')::numeric = 3500
      and (o ->> 'comissao')::numeric = 700 and (o ->> 'dias_total')::numeric = 1.5, o::text);

    o := pg_temp.os(r, 'OS-00503');
    v_res := pg_temp.ok(v_res, 'S4 OS-00503: despesa não faturável 250, lucro 2.250, comissão 450, nenhum dia (a nota cancelada não conta)',
      o ->> 'competencia' = '2026-11-13' and (o ->> 'recebido')::numeric = 3000 and (o ->> 'material')::numeric = 500
      and (o ->> 'despesas')::numeric = 250 and (o ->> 'imposto')::numeric = 0 and (o ->> 'sem_nota')::boolean
      and (o ->> 'lucro')::numeric = 2250 and (o ->> 'comissao')::numeric = 450 and (o ->> 'dias_total')::numeric = 0, o::text);

    o := pg_temp.os(r, 'OS-00505');
    v_res := pg_temp.ok(v_res, 'S5 OS-00505: saída 29/10, competência 10/11; recebido 4.000 (o sinal entra; o recebível cancelado fora), lucro 3.000, comissão 600, 1 dia (de outubro)',
      o ->> 'saida' = '2026-10-29' and o ->> 'competencia' = '2026-11-10' and (o ->> 'recebido')::numeric = 4000
      and (o ->> 'lucro')::numeric = 3000 and (o ->> 'comissao')::numeric = 600 and (o ->> 'dias_total')::numeric = 1, o::text);

    o := pg_temp.os(r, 'OS-00506');
    v_res := pg_temp.ok(v_res, 'S6 OS-00506: taxa 15 (card_fee_percent 1,5% sem líquido), lucro 500, comissão 100, 3 dias',
      (o ->> 'taxa_cartao')::numeric = 15 and (o ->> 'material')::numeric = 485 and (o ->> 'lucro')::numeric = 500
      and (o ->> 'comissao')::numeric = 100 and (o ->> 'dias_total')::numeric = 3, o::text);

    o := pg_temp.os(r, 'OS-00507');
    v_res := pg_temp.ok(v_res, 'S7 OS-00507: lucro −200, comissão 0, lucro_negativo; saída qui 19/11 (22:30 de Brasília, 01:30 UTC do dia 20)',
      o ->> 'saida' = '2026-11-19' and (o ->> 'lucro')::numeric = -200 and (o ->> 'comissao')::numeric = 0
      and (o ->> 'lucro_negativo')::boolean, o::text);

    v_res := pg_temp.ok(v_res, 'S8 OS-00501 dividida 3:1: 1.155,08 + 385,03 = 1.540,11 → a sobra de −0,01 na maior parte (Roberto 1.155,07, João 385,03); a falta do Mickael ligada a ela não leva parte',
      pg_temp.parte(r, 'Roberto', 'OS-00501') = 1155.07 and pg_temp.parte(r, 'João', 'OS-00501') = 385.03
      and pg_temp.parte(r, 'Mickael', 'OS-00501') is null,
      format('Roberto %s, João %s, Mickael %s', pg_temp.parte(r, 'Roberto', 'OS-00501'), pg_temp.parte(r, 'João', 'OS-00501'),
             pg_temp.parte(r, 'Mickael', 'OS-00501')));
    v_res := pg_temp.ok(v_res, 'S9 OS-00506 dividida 1:1:1: 33,33 × 3 = 99,99 → a sobra de +0,01 empata e vai ao menor payee_id (Roberto 33,34)',
      pg_temp.parte(r, 'Roberto', 'OS-00506') = 33.34 and pg_temp.parte(r, 'João', 'OS-00506') = 33.33
      and pg_temp.parte(r, 'Mickael', 'OS-00506') = 33.33,
      format('Roberto %s, João %s, Mickael %s', pg_temp.parte(r, 'Roberto', 'OS-00506'), pg_temp.parte(r, 'João', 'OS-00506'),
             pg_temp.parte(r, 'Mickael', 'OS-00506')));

    t := pg_temp.tec(r, 'Roberto');
    v_res := pg_temp.ok(v_res, 'S10 Roberto: diárias 990 (5,5 × 180; a de ter 10/11 sem OS conta), comissão 2.488,41, o maior 2.488,41, bônus que seria 1.498,41; 4 OS na ordem',
      (t ->> 'diarias')::numeric = 990 and (t ->> 'n_diarias')::int = 6 and (t ->> 'diarias_sem_os')::int = 1
      and (t ->> 'comissao')::numeric = 2488.41 and (t ->> 'maior')::numeric = 2488.41 and (t ->> 'bonus')::numeric = 1498.41
      and pg_temp.numeros(t -> 'os') = 'OS-00501,OS-00502,OS-00505,OS-00506'
      and (t -> 'os' -> 0 ->> 'dias')::numeric = 3 and (t -> 'os' -> 1 ->> 'dias')::numeric = 1.5
      and t ->> 'payee_id' = 'bb000000-0000-4000-8000-000000000002', t::text);
    t := pg_temp.tec(r, 'João');
    v_res := pg_temp.ok(v_res, 'S11 João: diárias 300 (2 × 150), comissão 418,36, o maior 418,36, bônus 118,36',
      (t ->> 'diarias')::numeric = 300 and (t ->> 'n_diarias')::int = 3 and (t ->> 'diarias_sem_os')::int = 1
      and (t ->> 'comissao')::numeric = 418.36 and (t ->> 'maior')::numeric = 418.36 and (t ->> 'bonus')::numeric = 118.36, t::text);
    t := pg_temp.tec(r, 'Mickael');
    v_res := pg_temp.ok(v_res, 'S12 Mickael: diárias 0 (a falta não vale), comissão 33,33 (do dia de outubro), bônus 33,33',
      (t ->> 'diarias')::numeric = 0 and (t ->> 'n_diarias')::int = 0 and (t ->> 'comissao')::numeric = 33.33
      and (t ->> 'maior')::numeric = 33.33 and (t ->> 'bonus')::numeric = 33.33, t::text);
    v_res := pg_temp.ok(v_res, 'S13 técnicos: Roberto, João e Mickael, na ordem do maior; o Gustavo (sócio) nunca',
      (select string_agg(e ->> 'nome', ',' order by n) from jsonb_array_elements(r -> 'tecnicos') with ordinality x(e, n))
        = 'Roberto,João,Mickael', (r -> 'tecnicos')::text);

    v_res := pg_temp.ok(v_res, 'S14 sem dia para dividir: R$ 450 (OS-00503; a OS-00507 sem comissão não entra na lista); partes + sem dia = a comissão das OS (3.390,10)',
      (r ->> 'nao_atribuida')::numeric = 450 and r -> 'nao_atribuida_os' = '[{"numero": "OS-00503", "comissao": 450.00}]'::jsonb
      and (select sum((e ->> 'comissao')::numeric) from jsonb_array_elements(r -> 'os') e) = 3390.10
      and (select sum((e ->> 'comissao')::numeric) from jsonb_array_elements(r -> 'tecnicos') e) + 450 = 3390.10,
      (r -> 'nao_atribuida_os')::text);
    v_res := pg_temp.ok(v_res, 'S15 espera o pagamento: a OS-00504 (concluída seg 16/11, paga em parte)',
      r -> 'aguardando_pagamento' = '[{"numero": "OS-00504", "saida": "2026-11-16", "pagamento": "partially_paid"}]'::jsonb,
      (r -> 'aguardando_pagamento')::text);
    v_res := pg_temp.ok(v_res, 'S16 avisos: pagamento desligado, teste, sem dia, sem nota, lucro negativo, espera pagamento (há despesa: sem despesas_zeradas); 9 diárias no mês, 2 sem OS',
      pg_temp.avisos(r) = 'aguardando_pagamento,lucro_negativo,pagamento_desligado,sem_dias,sem_nota,teste'
      and r -> 'diarias_do_mes' = '{"diarias": 9, "sem_os": 2}'::jsonb and (r -> 'aliquota')::numeric = 6,
      pg_temp.avisos(r) || ' ' || (r -> 'diarias_do_mes')::text);
    v_res := pg_temp.ok(v_res, 'S17 o texto de novembro (seria, nada foi pago, as premissas a confirmar)',
      r ->> 'texto' = c_texto_nov, r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'S18 o texto nunca diz "a pagar" nem "vou pagar"',
      position('a pagar' in lower(r ->> 'texto')) = 0 and position('vou pagar' in lower(r ->> 'texto')) = 0
      and position('nada foi pago' in r ->> 'texto') > 0, null);

    -- o mês até hoje, o mês de antes e o mês futuro
    r2 := pg_temp.conta('2026-11-01', '2026-11-10');
    v_res := pg_temp.ok(v_res, 'S19 novembro até ter 10/11: "(até 10/11)"; só as OS com competência até 10/11 (OS-00501, 502, 505)',
      r2 ->> 'ate' = '2026-11-10' and pg_temp.numeros(r2 -> 'os') = 'OS-00501,OS-00502,OS-00505'
      and r2 ->> 'texto' like 'Comissão de novembro (até 10/11), em teste — nada foi pago.%', r2 ->> 'texto');
    r2 := pg_temp.conta('2026-10-15', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S20 outubro (qualquer dia do mês serve): a OS-00505 não está (conta em novembro); "Nenhuma OS concluída e paga no mês."',
      r2 ->> 'mes' = '2026-10-01' and r2 ->> 'ate' = '2026-10-31' and jsonb_array_length(r2 -> 'os') = 0
      and position('• Nenhuma OS concluída e paga no mês.' in r2 ->> 'texto') > 0 and not (r2 -> 'avisos') ? 'despesas_zeradas',
      r2 ->> 'texto');
    r2 := pg_temp.conta('2026-12-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S21 dezembro visto em 30/11: o mês ainda não começou (ate nulo, aviso mes_futuro)',
      r2 -> 'ate' = 'null'::jsonb and (r2 -> 'avisos') ? 'mes_futuro'
      and r2 ->> 'texto' = 'Comissão de dezembro: o mês ainda não começou. Nada foi pago.', r2::text);

    -- os parâmetros (as premissas do dono)
    update public.comissao_config set competencia = 'saida' where id;
    r2 := pg_temp.conta('2026-11-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S22 competência pela saída: novembro sem a OS-00505 (comissão das OS 2.790,10; Roberto 1.888,41)',
      pg_temp.numeros(r2 -> 'os') = 'OS-00501,OS-00502,OS-00503,OS-00506,OS-00507'
      and (select sum((e ->> 'comissao')::numeric) from jsonb_array_elements(r2 -> 'os') e) = 2790.10
      and (pg_temp.tec(r2, 'Roberto') ->> 'comissao')::numeric = 1888.41
      and position('se a OS conta no mês da conclusão, depois de paga' in r2 ->> 'texto') > 0, pg_temp.numeros(r2 -> 'os'));
    r2 := pg_temp.conta('2026-10-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S23 competência pela saída: outubro (visto em 30/11) com a OS-00505 (600, Roberto)',
      pg_temp.numeros(r2 -> 'os') = 'OS-00505' and (pg_temp.tec(r2, 'Roberto') ->> 'comissao')::numeric = 600, pg_temp.numeros(r2 -> 'os'));
    r2 := pg_temp.conta('2026-10-01', '2026-11-09');
    v_res := pg_temp.ok(v_res, 'S24 competência pela saída: outubro visto em 09/11 ainda sem a OS-00505 (paga em 10/11)',
      jsonb_array_length(r2 -> 'os') = 0, pg_temp.numeros(r2 -> 'os'));
    update public.comissao_config set competencia = 'concluida_e_paga', imposto_fonte = 'nenhum' where id;
    r2 := pg_temp.conta('2026-11-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S25 imposto nenhum: OS-00502 sem imposto, comissão 760; sem aviso sem_nota; a conta não fala em imposto',
      (pg_temp.os(r2, 'OS-00502') ->> 'imposto')::numeric = 0 and (pg_temp.os(r2, 'OS-00502') ->> 'comissao')::numeric = 760
      and not (r2 -> 'avisos') ? 'sem_nota'
      and position('as despesas da OS e a taxa do cartão; as diárias não entram.' in r2 ->> 'texto') > 0
      and position('se a conta fica sem imposto' in r2 ->> 'texto') > 0, r2 ->> 'texto');
    update public.comissao_config set imposto_fonte = 'aliquota_simples_sempre' where id;
    r2 := pg_temp.conta('2026-11-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S26 imposto em toda OS: OS-00501 com 600 de imposto (6% de 10.000), comissão 1.420,10',
      (pg_temp.os(r2, 'OS-00501') ->> 'imposto')::numeric = 600 and (pg_temp.os(r2, 'OS-00501') ->> 'comissao')::numeric = 1420.10
      and not (r2 -> 'avisos') ? 'sem_nota' and position('o imposto do Simples e a taxa do cartão' in r2 ->> 'texto') > 0,
      (pg_temp.os(r2, 'OS-00501'))::text);
    update public.comissao_config set imposto_fonte = 'aliquota_simples_com_nota' where id;
    update public.company_fiscal_settings set nfse_total_tax_rate_sn = null;
    update public.app_settings set value = '5' where key = 'simples_aliquota';
    r2 := pg_temp.conta('2026-11-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S27 sem a alíquota da NFS-e: a linha simples_aliquota de app_settings (5%) → OS-00502 com 250 de imposto, comissão 710',
      (r2 -> 'aliquota')::numeric = 5 and (pg_temp.os(r2, 'OS-00502') ->> 'imposto')::numeric = 250
      and (pg_temp.os(r2, 'OS-00502') ->> 'comissao')::numeric = 710, (pg_temp.os(r2, 'OS-00502'))::text);
    delete from public.app_settings where key = 'simples_aliquota';
    r2 := pg_temp.conta('2026-11-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S28 sem alíquota nenhuma: imposto 0, aviso sem_aliquota e o texto diz',
      r2 -> 'aliquota' = 'null'::jsonb and (pg_temp.os(r2, 'OS-00502') ->> 'imposto')::numeric = 0 and (r2 -> 'avisos') ? 'sem_aliquota'
      and position('A alíquota do Simples não está nas configurações fiscais: o imposto ficou em R$ 0.' in r2 ->> 'texto') > 0,
      r2 ->> 'texto');
    update public.company_fiscal_settings set nfse_total_tax_rate_sn = 6.00;
    update public.comissao_config set inicio = '2026-11-01' where id;
    r2 := pg_temp.conta('2026-11-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S29 com o início em novembro: "mês 1 de 3 do teste", sem o aviso teste e sem pedir as premissas',
      r2 ->> 'texto' like 'Comissão de novembro, mês 1 de 3 do teste — nada foi pago.%' and not (r2 -> 'avisos') ? 'teste'
      and position('Para a conta valer' in r2 ->> 'texto') = 0 and (r2 #>> '{teste,mes_do_teste}')::int = 1, r2 -> 'teste' ->> 'mes_do_teste');
    update public.comissao_config set inicio = '2026-08-01' where id;
    r2 := pg_temp.conta('2026-11-01', '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S30 com o início em agosto, novembro é o 4º mês: fora dos 3 do teste → "em teste"',
      r2 ->> 'texto' like 'Comissão de novembro, em teste — nada foi pago.%' and (r2 -> 'avisos') ? 'teste'
      and (r2 #>> '{teste,mes_do_teste}')::int = 4, r2 -> 'teste' ->> 'mes_do_teste');
    update public.comissao_config set inicio = null where id;

    -- o resumo e a linha do 1º dia útil
    r2 := public.comissao_resumo_do_mes(null, date '2026-12-01');
    v_res := pg_temp.ok(v_res, 'S31 resumo de ter 01/12 (1º dia útil de dezembro): novembro inteiro; a linha de 3 técnicos passa de 200 e sai somada, com os nomes',
      r2 ->> 'mes' = '2026-11-01' and r2 ->> 'ate' = '2026-11-30' and (r2 ->> 'primeiro_dia_util')::boolean
      and r2 ->> 'linha' = c_linha_nov and char_length(r2 ->> 'linha') <= 200 and r2 ->> 'texto' = c_texto_nov,
      format('%s (%s)', r2 ->> 'linha', char_length(r2 ->> 'linha')));
    r2 := public.comissao_resumo_do_mes(null, date '2026-11-30');
    v_res := pg_temp.ok(v_res, 'S32 resumo de seg 30/11: o mês corrente (novembro até 30/11), não é o 1º dia útil',
      r2 ->> 'mes' = '2026-11-01' and not (r2 ->> 'primeiro_dia_util')::boolean, r2 ->> 'linha');
    r2 := public.comissao_resumo_do_mes(date '2026-11-20', date '2026-12-15');
    v_res := pg_temp.ok(v_res, 'S33 resumo com o mês dito (qualquer dia dele): novembro',
      r2 ->> 'mes' = '2026-11-01' and r2 ->> 'texto' = c_texto_nov, r2 ->> 'mes');

    -- quem pode ver (com a fixture: o Gustavo é admin; o Roberto é técnico)
    v_txt := pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
                          $q$select (public.comissao_tecnicos_do_mes('2026-11-01', '2026-11-30') ->> 'nao_atribuida')$q$);
    v_res := pg_temp.ok(v_res, 'S34 o admin pelo painel vê a conta', v_txt = '450.00', v_txt);
    v_txt := pg_temp.como('aa000000-0000-4000-8000-000000000002', 'authenticated',
                          $q$select public.comissao_tecnicos_do_mes('2026-11-01', '2026-11-30')::text$q$);
    v_res := pg_temp.ok(v_res, 'S35 o técnico pelo painel: 42501 "A comissão é com o administrador ou o financeiro."',
      v_txt = 'erro 42501: A comissão é com o administrador ou o financeiro.', v_txt);
    v_txt := pg_temp.como('aa000000-0000-4000-8000-000000000002', 'authenticated',
                          $q$select public.comissao_resumo_do_mes(null, '2026-12-01')::text$q$);
    v_res := pg_temp.ok(v_res, 'S36 o técnico no resumo: 42501 também', v_txt like 'erro 42501:%', v_txt);
    v_txt := pg_temp.como(null, 'service_role', $q$select (public.comissao_resumo_do_mes(null, '2026-12-01') ->> 'mes')$q$);
    v_res := pg_temp.ok(v_res, 'S37 o service_role (assistente, fechamento) vê', v_txt = '2026-11-01', v_txt);

    -- N: nada foi escrito, e a conta é a mesma duas vezes
    v_res := pg_temp.ok(v_res, 'N1 (sintético) commissions, payables, payments, receivables, work_shifts e work_shift_os com a mesma contagem depois de todas as contas',
      pg_temp.contagens() = v_antes, format('%s → %s', v_antes, pg_temp.contagens()));
    v_res := pg_temp.ok(v_res, 'N2 (sintético) determinismo: md5 de duas chamadas igual',
      md5(pg_temp.conta('2026-11-01', '2026-11-30')::text) = md5(pg_temp.conta('2026-11-01', '2026-11-30')::text), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s$;

-- ── P. O espelho de produção (outubro e setembro) ─────────────────────────────────────────────────────────
do $p$
declare
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  r2      jsonb;
  t       jsonb;
  v_antes jsonb;
  v_txt   text;
  v_num   numeric;
  v_num2  numeric;
  c_texto_out constant text := concat_ws(E'\n',
    'Comissão de outubro (até 24/10), em teste — nada foi pago.',
    '• Roberto: diárias R$ 2.660,00 × comissão R$ 0,00 → fica a diária.',
    '• João: diárias R$ 880,00 × comissão R$ 0,00 → fica a diária.',
    '• Sem dia lançado na OS para dividir: R$ 2.094,20 (OS-00094 R$ 161,25 · OS-00061 R$ 1.000,00 · OS-00077 R$ 131,35 · OS-00110 R$ 801,60).',
    'A conta: 20% do que entrou menos o material ao custo, as despesas da OS, o imposto da nota e a taxa do cartão; as diárias não entram. '
    || 'Nenhuma das 26 diárias do mês está ligada a uma OS: elas não contam na divisão. '
    || 'As despesas das OS não estão lançadas (R$ 0 em todas), então o lucro está maior do que o real. '
    || 'O imposto (6% do Simples) só entra nas OS com nota emitida: as 4 estão sem nota. '
    || 'Entram quando forem pagas: OS-00038 e OS-00051. '
    || 'Para a conta valer, falta você dizer se o imposto é só nas OS com nota, se a OS conta no mês em que ficou concluída e paga e quando começam os 3 meses de teste.');
  c_linha_out constant text :=
    'Comissão de outubro (teste, nada pago): diárias R$ 3.540,00 × comissão R$ 0,00 (Roberto e João); '
    || 'R$ 2.094,20 sem dia lançado na OS para dividir. *comissão outubro* mostra a conta.';
begin
  if coalesce(current_setting('agenda_teste.cenario_comissao_2410', true), '') = '' then
    insert into _resultado values ('P0 o espelho de produção (cenario-comissao-2410.sql)', true, 'PULADO: sem agenda_teste.cenario_comissao_2410 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.cenario_comissao_2410');

    -- o espelho é o de i04 e i09 (o gatilho de produção pôs o payment_status; os insumos batem OS a OS)
    v_res := pg_temp.ok(v_res, 'P0 o espelho bate com i04: as 21 OS, o payment_status pelo gatilho, o que entrou, o material, as despesas e as notas',
      (select count(*) = 21 and bool_and(
                so.payment_status = e.payment_status
                and coalesce((select sum(p.amount) from public.receivables rc join public.payments p on p.receivable_id = rc.id
                               where rc.service_order_id = so.id and rc.status <> 'cancelled' and p.status = 'confirmed'), 0) = e.recebido
                and coalesce((select sum(sp.line_total_cost) from public.service_order_parts sp where sp.service_order_id = so.id), 0) = e.material
                and coalesce((select sum(x.amount) from public.service_order_expenses x where x.service_order_id = so.id), 0) = e.despesas
                and (select count(*) from public.issued_fiscal_documents f where f.origin_id = so.id and f.status = 'authorized') = e.notas
                and (so.check_out_at at time zone 'America/Sao_Paulo')::date = e.saida)
         from _espelho_i04 e join public.service_orders so on so.service_order_number = e.numero),
      (select string_agg(e.numero || ':' || so.payment_status, ' ') from _espelho_i04 e
         join public.service_orders so on so.service_order_number = e.numero where so.payment_status <> e.payment_status));
    v_res := pg_temp.ok(v_res, 'P1 as 56 diárias de i09 (de 07/09 a 23/10), nenhuma ligada a uma OS; o total delas R$ 6.760',
      (select count(*) from public.work_shifts) = 56 and (select count(*) from public.work_shift_os) = 0
      and (select sum(valor_dia) from public.work_shifts) = 6760
      and (select min(data) from public.work_shifts) = date '2026-09-07' and (select max(data) from public.work_shifts) = date '2026-10-23',
      (select format('%s diárias, R$ %s', count(*), sum(valor_dia)) from public.work_shifts));

    v_antes := pg_temp.contagens();
    r := pg_temp.conta('2026-10-01', '2026-10-24');
    v_res := pg_temp.ok(v_res, 'P2 outubro até 24/10: as 4 OS concluídas e pagas (OS-00094 pela saída de 03/10, paga em 08/09; OS-00061/77/110 de 13/10), lucro e comissão de cada uma',
      pg_temp.numeros(r -> 'os') = 'OS-00094,OS-00061,OS-00077,OS-00110'
      and pg_temp.os(r, 'OS-00094') ->> 'competencia' = '2026-10-03'
      and (pg_temp.os(r, 'OS-00094') ->> 'lucro')::numeric = 806.26 and (pg_temp.os(r, 'OS-00094') ->> 'comissao')::numeric = 161.25
      and (pg_temp.os(r, 'OS-00061') ->> 'lucro')::numeric = 5000 and (pg_temp.os(r, 'OS-00061') ->> 'comissao')::numeric = 1000
      and (pg_temp.os(r, 'OS-00077') ->> 'lucro')::numeric = 656.75 and (pg_temp.os(r, 'OS-00077') ->> 'comissao')::numeric = 131.35
      and (pg_temp.os(r, 'OS-00110') ->> 'lucro')::numeric = 4008 and (pg_temp.os(r, 'OS-00110') ->> 'comissao')::numeric = 801.60
      and (select bool_and((e ->> 'imposto')::numeric = 0 and (e ->> 'taxa_cartao')::numeric = 0 and (e ->> 'despesas')::numeric = 0
                           and (e ->> 'dias_total')::numeric = 0) from jsonb_array_elements(r -> 'os') e),
      (r -> 'os')::text);
    v_res := pg_temp.ok(v_res, 'P3 outubro: R$ 2.094,20 sem dia lançado na OS para dividir (161,25 + 1.000,00 + 131,35 + 801,60)',
      (r ->> 'nao_atribuida')::numeric = 2094.20
      and r -> 'nao_atribuida_os' = '[{"numero": "OS-00094", "comissao": 161.25}, {"numero": "OS-00061", "comissao": 1000.00},
                                      {"numero": "OS-00077", "comissao": 131.35}, {"numero": "OS-00110", "comissao": 801.60}]'::jsonb,
      (r -> 'nao_atribuida_os')::text);
    v_res := pg_temp.ok(v_res, 'P4 outubro: Roberto diárias 2.660 (17 diárias) × 0, João 880 (9) × 0, Mickael 0 × 0 — fica a diária; ninguém com parte',
      (pg_temp.tec(r, 'Roberto') ->> 'diarias')::numeric = 2660 and (pg_temp.tec(r, 'Roberto') ->> 'n_diarias')::int = 17
      and (pg_temp.tec(r, 'João') ->> 'diarias')::numeric = 880 and (pg_temp.tec(r, 'João') ->> 'n_diarias')::int = 9
      and (pg_temp.tec(r, 'Mickael') ->> 'diarias')::numeric = 0
      and (select bool_and((e ->> 'comissao')::numeric = 0 and (e ->> 'bonus')::numeric = 0 and (e ->> 'maior')::numeric = (e ->> 'diarias')::numeric
                           and jsonb_array_length(e -> 'os') = 0) from jsonb_array_elements(r -> 'tecnicos') e)
      and jsonb_array_length(r -> 'tecnicos') = 3, (r -> 'tecnicos')::text);
    v_res := pg_temp.ok(v_res, 'P5 outubro: avisos (despesas zeradas, sem dia, sem nota, espera pagamento, teste, pagamento desligado); 26 diárias, as 26 sem OS; a OS-00038 e a OS-00051 esperam o pagamento',
      pg_temp.avisos(r) = 'aguardando_pagamento,despesas_zeradas,pagamento_desligado,sem_dias,sem_nota,teste'
      and r -> 'diarias_do_mes' = '{"diarias": 26, "sem_os": 26}'::jsonb
      and pg_temp.numeros(r -> 'aguardando_pagamento') = 'OS-00038,OS-00051', pg_temp.avisos(r));
    v_res := pg_temp.ok(v_res, 'P6 o texto de outubro (diz o que não dá para calcular: as diárias sem OS, as despesas zeradas, o imposto só com nota, o que espera pagamento)',
      r ->> 'texto' = c_texto_out, r ->> 'texto');

    r2 := pg_temp.conta('2026-09-01', '2026-10-24');
    v_res := pg_temp.ok(v_res, 'P7 setembro: só a OS-00105 (recebido 3.035, despesas 1.905, lucro 1.130, comissão 226, sem dia); diárias Roberto 2.460, João 280, Mickael 480; há despesa',
      pg_temp.numeros(r2 -> 'os') = 'OS-00105' and (pg_temp.os(r2, 'OS-00105') ->> 'recebido')::numeric = 3035
      and (pg_temp.os(r2, 'OS-00105') ->> 'despesas')::numeric = 1905 and (pg_temp.os(r2, 'OS-00105') ->> 'lucro')::numeric = 1130
      and (r2 ->> 'nao_atribuida')::numeric = 226
      and (pg_temp.tec(r2, 'Roberto') ->> 'diarias')::numeric = 2460 and (pg_temp.tec(r2, 'João') ->> 'diarias')::numeric = 280
      and (pg_temp.tec(r2, 'Mickael') ->> 'diarias')::numeric = 480 and not (r2 -> 'avisos') ? 'despesas_zeradas'
      and position('O imposto (6% do Simples) só entra nas OS com nota emitida: a OS está sem nota.' in r2 ->> 'texto') > 0
      and r2 ->> 'texto' like 'Comissão de setembro, em teste — nada foi pago.%', r2 ->> 'texto');

    -- a medição de 23/10 (07/09 a 17/10)
    r := pg_temp.conta('2026-10-01', '2026-10-17');
    v_num := (select sum((e ->> 'diarias')::numeric) from jsonb_array_elements(r2 -> 'tecnicos') e)
           + (select sum((e ->> 'diarias')::numeric) from jsonb_array_elements(r -> 'tecnicos') e);
    v_res := pg_temp.ok(v_res, 'P8 a medição de 07/09 a 17/10: diárias R$ 6.040,00 = setembro 3.220 + outubro até 17/10 2.820 (Roberto 1.940, João 880)',
      v_num = 6040 and (pg_temp.tec(r, 'Roberto') ->> 'diarias')::numeric = 1940 and (pg_temp.tec(r, 'João') ->> 'diarias')::numeric = 880
      and (select sum((e ->> 'diarias')::numeric) from jsonb_array_elements(r2 -> 'tecnicos') e) = 3220
      and (r ->> 'nao_atribuida')::numeric = 2094.20, v_num::text);
    select round((select c.pct from public.comissao_config c where c.id)
                 * sum(e.valor - e.material - e.despesas), 2),
           round((select c.pct from public.comissao_config c where c.id)
                 * sum(e.valor - e.material - e.despesas) filter (where e.numero = 'OS-00038'), 2)
      into v_num, v_num2
      from _espelho_i04 e where e.saida between date '2026-09-07' and date '2026-10-17';
    v_res := pg_temp.ok(v_res, 'P9 o "≈ R$ 6.600" de 23/10 era 20% do VALOR das 6 OS concluídas no período, pagas ou não (6.614,22; 3.378,00 só da OS-00038); pela regra (concluída E paga, o que entrou) setembro + outubro = 2.320,20',
      v_num = 6614.22 and v_num2 = 3378.00
      and (r2 ->> 'nao_atribuida')::numeric + (r ->> 'nao_atribuida')::numeric = 2320.20,
      format('valor %s, OS-00038 %s, regra %s', v_num, v_num2, (r2 ->> 'nao_atribuida')::numeric + (r ->> 'nao_atribuida')::numeric));

    -- o resumo do 1º dia útil de novembro (ter 03/11: dom 01 e seg 02, Finados) e os dias antes dele
    r2 := public.comissao_resumo_do_mes(null, date '2026-11-03');
    v_res := pg_temp.ok(v_res, 'P10 a linha de ter 03/11 (1º dia útil): outubro inteiro; com 2 técnicos passa de 200 e sai somada, com os nomes',
      r2 ->> 'mes' = '2026-10-01' and r2 ->> 'ate' = '2026-10-31' and (r2 ->> 'primeiro_dia_util')::boolean
      and r2 ->> 'linha' = c_linha_out and char_length(r2 ->> 'linha') <= 200,
      format('%s (%s)', r2 ->> 'linha', char_length(r2 ->> 'linha')));
    v_res := pg_temp.ok(v_res, 'P11 o resumo sem mês: dom 01/11 e seg 02/11 (Finados) ainda mostram outubro; qua 04/11 já é novembro',
      public.comissao_resumo_do_mes(null, date '2026-11-01') ->> 'mes' = '2026-10-01'
      and public.comissao_resumo_do_mes(null, date '2026-11-02') ->> 'mes' = '2026-10-01'
      and not (public.comissao_resumo_do_mes(null, date '2026-11-02') ->> 'primeiro_dia_util')::boolean
      and public.comissao_resumo_do_mes(null, date '2026-11-04') ->> 'mes' = '2026-11-01', null);
    v_res := pg_temp.ok(v_res, 'N3 (espelho) nada foi escrito pelas contas e pelos resumos',
      pg_temp.contagens() = v_antes, format('%s → %s', v_antes, pg_temp.contagens()));
    v_res := pg_temp.ok(v_res, 'N4 (espelho) determinismo: md5 de duas chamadas igual',
      md5(pg_temp.conta('2026-10-01', '2026-10-24')::text) = md5(pg_temp.conta('2026-10-01', '2026-10-24')::text), null);

    -- a OS-00038 entra quando for paga (no dia em que o pagamento chegar: competência = o mais tarde dos dois)
    update public.receivables set status = 'paid', paid_amount = amount, balance_amount = 0
     where id = md5('espelho:rec:OS-00038')::uuid;
    insert into public.payments (receivable_id, payment_date, amount, payment_method, status)
    values (md5('espelho:rec:OS-00038')::uuid, date '2026-10-24', 16890, 'pix', 'confirmed');
    r := pg_temp.conta('2026-10-01', '2026-10-24');
    v_res := pg_temp.ok(v_res, 'P12 paga em 24/10, a OS-00038 entra em outubro (comissão 3.378,00) e sai da espera; sem dia para dividir 5.472,20',
      (pg_temp.os(r, 'OS-00038') ->> 'comissao')::numeric = 3378 and pg_temp.os(r, 'OS-00038') ->> 'competencia' = '2026-10-24'
      and (r ->> 'nao_atribuida')::numeric = 5472.20 and pg_temp.numeros(r -> 'aguardando_pagamento') = 'OS-00051',
      (pg_temp.os(r, 'OS-00038'))::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$p$;

-- ── J. Portas (rodam sempre) ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('J1 %s: STABLE, security definer, search_path fixo', f),
       (select p.provolatile = 's' and p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
          from pg_proc p where p.oid = f::regprocedure), null
  from unnest(array['public.comissao_tecnicos_do_mes(date, date)', 'public.comissao_resumo_do_mes(date, date)']) f;

insert into _resultado
select format('J2 %s: authenticated e service_role executam; anon e public não', f),
       has_function_privilege('authenticated', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute')
       and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                        where p.oid = f::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE'), null
  from unnest(array['public.comissao_tecnicos_do_mes(date, date)', 'public.comissao_resumo_do_mes(date, date)']) f;

insert into _resultado
select 'J3 v_dias_por_os_e_pessoa: security_invoker; authenticated e service_role leem; anon não',
       coalesce((select array_to_string(c.reloptions, ',') from pg_class c where c.oid = 'public.v_dias_por_os_e_pessoa'::regclass)
                ~ 'security_invoker=(on|true)', false)
       and has_table_privilege('authenticated', 'public.v_dias_por_os_e_pessoa', 'select')
       and has_table_privilege('service_role', 'public.v_dias_por_os_e_pessoa', 'select')
       and not has_table_privilege('anon', 'public.v_dias_por_os_e_pessoa', 'select')
       and not has_table_privilege('authenticated', 'public.v_dias_por_os_e_pessoa', 'insert'),
       (select array_to_string(c.reloptions, ',') from pg_class c where c.oid = 'public.v_dias_por_os_e_pessoa'::regclass);

insert into _resultado
select 'J4 um JWT de authenticated sem login: 42501 (só o service_role vê sem login)',
       pg_temp.como(null, 'authenticated', $q$select public.comissao_tecnicos_do_mes('2026-10-01', '2026-10-24')::text$q$)
         = 'erro 42501: A comissão é com o administrador ou o financeiro.',
       pg_temp.como(null, 'authenticated', $q$select public.comissao_tecnicos_do_mes('2026-10-01', '2026-10-24')::text$q$);

insert into _resultado
select 'J5 o service_role sem login vê a conta (e o resumo)',
       pg_temp.como(null, 'service_role', $q$select (public.comissao_tecnicos_do_mes('2026-10-01', '2026-10-24') ->> 'mes')$q$) = '2026-10-01'
       and pg_temp.como(null, 'service_role', $q$select (public.comissao_resumo_do_mes('2026-10-01', '2026-10-24') ->> 'mes')$q$) = '2026-10-01',
       pg_temp.como(null, 'service_role', $q$select (public.comissao_resumo_do_mes('2026-10-01', '2026-10-24') ->> 'mes')$q$);

insert into _resultado
select 'J6 sem o mês ou sem o dia de hoje: 22004',
       pg_temp.erro_de($q$select public.comissao_tecnicos_do_mes(null, '2026-10-24')$q$) like '22004 %'
       and pg_temp.erro_de($q$select public.comissao_tecnicos_do_mes('2026-10-01', null)$q$) like '22004 %'
       and pg_temp.erro_de($q$select public.comissao_resumo_do_mes(null, null)$q$) like '22004 %', null;

insert into _resultado
select format('J7 comissao_config: %s', c.caso), pg_temp.erro_de(c.comando) like c.esperado, pg_temp.erro_de(c.comando)
  from (values
    ('competência nasce "concluída e paga"', $q$do $x$ begin if (select competencia from public.comissao_config where id) <> 'concluida_e_paga' then raise exception 'nasceu %', (select competencia from public.comissao_config where id); end if; end $x$$q$, 'sem erro'),
    ('competência pelo pagamento recusada', $q$update public.comissao_config set competencia = 'pagamento' where id$q$, '23514 %comissao_config_competencia_check%'),
    ('competência pela saída aceita', $q$update public.comissao_config set competencia = 'saida' where id$q$, 'sem erro'),
    ('imposto em toda OS aceito', $q$update public.comissao_config set imposto_fonte = 'aliquota_simples_sempre' where id$q$, 'sem erro'),
    ('imposto pelo chute recusado', $q$update public.comissao_config set imposto_fonte = 'chute' where id$q$, '23514 %comissao_config_imposto_fonte_check%'),
    ('pagamento ligado continua recusado', $q$update public.comissao_config set pagamento = 'ligado' where id$q$, '23514 %comissao_config_pagamento_check%')
  ) as c(caso, comando, esperado);

select teste, ok, detalhe from _resultado order by teste;

rollback;
