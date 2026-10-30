-- Prova da capacidade do dono no motor da Agenda de Produção, Fase 6 (pacote P4; migration 20261029100400).
-- bancada: depende de 20261029100900
--
--   D1 as semanas: as 8 semanas completas antes de sex 30/10; por meio-dia do dono no plano, cumprido 1, parcial 0,5, não
--      cumprido 0 só com o motivo dele (o de material sai da conta; o cancelado por ele conta; o cancelado pela chuva e o sem
--      registro saem); a semana com 1 meio-dia só não conta; a semana de hoje fica fora; a mediana 0,70 × 0,80 = 0,56 (5
--      semanas); o piso (capacidade_dono_min) e o teto (carga_max); os parâmetros mudam a conta; rodar 2× não muda nada;
--      sem dono, nada é gravado
--   D2 _agenda_carga_da_pessoa: carga_max para todos em teste e com o item fora da lista; a troca grande vira pergunta (o
--      que vale continua 0,80); a pequena entra sozinha com a ação e o *desfaz* (0,56 só para o dono); nunca acima de
--      carga_max; o modo em sombra volta o padrão na hora; o admin pelo login lê a mesma; anon não
--   D3 o motor e o validador com 0,56 para o dono e 0,80 para os outros: o teto80 do dono (e só o dele, na posição dele)
--      cai; a mesma OS do dono que cabia na semana de 02/11 vai para a de 09/11; a mesma semana de 6 meios-dias deixa de
--      caber só para ele (a regra 6, com o texto de sempre); a equipe igual; com acima_da_carga, o 100% de sempre
--   D4 o publicado não muda: com a carga do dono abaixo do que ele já tem publicado, o motor não tira nada dele (os mesmos
--      "sai" que em teste) e a regra 6 só pesa nas alocações novas
--   D5 as cópias (_agenda_contexto e _agenda_validar_itens de 20261025100200; _agenda_aprendizado_texto de 20261029100300)
--      só acrescentam os blocos "-- FASE 6:"; as assinaturas, a segurança e as portas; as 2 novas
--   D6 byte a byte: em teste, ligado sem a lista e ligado com a pergunta aberta, o contexto, o validador e o motor inteiro
--      (agenda_propor) saem iguais às definições de antes (20261025100200, rodadas como pg_temp ou trocadas por um instante)
--      em toda a fixture
--   D7 os textos da capacidade em cada momento (spec §6.2/§6.3), sem jargão (em qualquer lugar)
--   D8 (correção C1, 20261029100900) o cancelado a pedido do dono e o parcial pela chuva fora da conta; sem o vaivém da
--      capacidade (a carga com que a semana foi marcada); a reserva por teto diz a parte da semana do dono
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_dono.sql
--   Seguro em produção: tudo dentro de begin/rollback. D5 e D7 rodam em qualquer lugar (as cópias só com as migrations como
--   texto); D1 a D4 e D6 só na bancada (a fixture-fase6; fora dela, PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- Roda p_sql como p_papel (com o login p_uid, ou sem login): o texto do resultado, ou 'erro <estado>: <mensagem>'.
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

-- O corpo de uma função numa migration (entre "as $tag$" e o fecho) e a função inteira (do "create or replace" ao fecho).
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_tag text;
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v_tag := (regexp_match(v, E'\nas (\\$[a-z]*\\$)\n'))[1];
  v := substr(v, position(E'\nas ' || v_tag || E'\n' in v) + length(E'\nas ' || v_tag));
  return left(v, position(E'\n' || v_tag || ';' in v));
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;

-- As linhas fora dos blocos "-- FASE 6: … -- FASE 6: fim" (o fim é lido pelo prefixo, como nos testes de cópia de antes).
create function pg_temp.sem_fase6(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_c6 boolean := false;  -- CORREÇÃO FASE 6 (C2): dentro de um bloco da correção da Fase 6
  v_f7 boolean := false;  -- FASE 7 (7a P5): dentro de um bloco "-- FASE 7:"
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    -- FASE 7 (7a P5): os blocos "-- FASE 7: … -- FASE 7: fim" também saem (a 20261031100400 recria _agenda_contexto e
    -- _agenda_validar_itens copiando DESTA fase: só acréscimo); o fim é lido pelo prefixo
    if not v_f7 and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_f7 := true; continue; end if;
    if v_f7 then
      if l ~ '^\s*-- FASE 7: fim' then v_f7 := false; end if;
      continue;
    end if;
    -- FASE 7 (7a P5): fim
    -- CORREÇÃO FASE 6: (C2) os blocos "-- CORREÇÃO FASE 6: … -- CORREÇÃO FASE 6: fim" também saem (a correção C2 da Fase 6
    -- recria a função copiando a definição mais nova: só acréscimo); o fim é lido pelo prefixo
    if not v_c6 and l ~ '^\s*-- CORREÇÃO FASE 6:' and l !~ '^\s*-- CORREÇÃO FASE 6: fim' then v_c6 := true; continue; end if;
    if v_c6 then
      if l ~ '^\s*-- CORREÇÃO FASE 6: fim' then v_c6 := false; end if;
      continue;
    end if;
    -- CORREÇÃO FASE 6: fim
    if not v_bloco and l ~ '^\s*-- FASE 6:' and l !~ '^\s*-- FASE 6: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 6: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- A rodada da capacidade (sex 30/10, 16:05) e a linha gravada.
create function pg_temp.capacidade() returns jsonb language sql as $f$
  select public._agenda_aprender_capacidade(date '2026-10-30', timestamptz '2026-10-30 16:05-03')
$f$;
create function pg_temp.linha() returns public.agenda_aprendizado language sql stable as $f$
  select a from public.agenda_aprendizado a where a.item = 'capacidade_dono' and a.chave = 'dono'
$f$;
-- As semanas da amostra: "31/08 3.5/5 | …" (a mais antiga primeiro).
create function pg_temp.semanas(p_a jsonb) returns text language sql immutable as $f$
  select string_agg(to_char((e ->> 'semana')::date, 'DD/MM') || ' ' || (e ->> 'feitos') || '/' || (e ->> 'planejados'), ' | '
                    order by (e ->> 'semana')::date)
    from jsonb_array_elements(p_a) e
$f$;

-- O motor de sex 30/10 às 16:30, sem gravar.
create function pg_temp.propor(p_escopo text, p_os uuid[] default null, p_restr jsonb default '{}'::jsonb) returns jsonb
language sql as $f$
  select public.agenda_propor(p_escopo, null, null, p_os, p_restr, false, 'motor', null, date '2026-10-30',
                              timestamptz '2026-10-30 16:30-03')
$f$;
-- As células "criar" de uma OS numa proposta: "05/11 manha Gustavo turno | …".
create function pg_temp.celulas(p_r jsonb, p_numero text) returns text language sql immutable as $f$
  select coalesce(string_agg(to_char((a ->> 'dia')::date, 'DD/MM') || ' ' || (a ->> 'turno') || ' ' || (a ->> 'nome') || ' ' || (a ->> 'presenca'),
                             ' | ' order by (a ->> 'dia')::date, a ->> 'turno' = 'tarde', a ->> 'nome'), '')
    from jsonb_array_elements(coalesce(p_r -> 'itens', '[]'::jsonb)) i, jsonb_array_elements(i -> 'alocacoes') a
   where i ->> 'numero' = p_numero and i ->> 'op' = 'criar'
$f$;
-- Os "sai" de uma proposta (as alocações que ela cancela), em texto.
create function pg_temp.saidas(p_r jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(a ->> 'alocacao_id', ',' order by a ->> 'alocacao_id'), '')
    from jsonb_array_elements(coalesce(p_r -> 'itens', '[]'::jsonb)) i, jsonb_array_elements(i -> 'alocacoes') a
   where i ->> 'op' = 'cancelar'
$f$;
-- As alocações vigentes do dono (dia, turno, presença, OS), em texto.
create function pg_temp.vigentes_do_dono() returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s %s', a.dia, a.turno, a.presenca, a.service_order_id), ' | '
                             order by a.dia, a.turno, a.presenca, a.id), '')
    from public.agenda_alocacoes a
   where a.payee_id = 'bb000000-0000-4000-8000-000000000001' and a.estado in ('publicada', 'fixada') and a.dia >= date '2026-10-30'
$f$;
-- Itens "criar" de n meios-dias de turno de uma pessoa na OS dada, a partir de seg 09/11 (manhã e tarde; sexta só de manhã).
create function pg_temp.itens(p_os uuid, p_payee uuid, p_nome text, p_n int) returns jsonb language sql stable as $f$
  select jsonb_build_array(jsonb_build_object('op', 'criar', 'os', p_os,
           'numero', (select service_order_number from public.service_orders where id = p_os), 'tipo', 'execucao',
           'alocacoes', (select jsonb_agg(jsonb_build_object('payee_id', p_payee, 'nome', p_nome, 'dia', m.dia, 'turno', m.turno,
                                                             'presenca', 'turno') order by m.o)
                           from (select x.dia, x.turno, row_number() over (order by x.dia, x.turno = 'tarde') as o
                                   from (values (date '2026-11-09', 'manha'), (date '2026-11-09', 'tarde'),
                                                (date '2026-11-10', 'manha'), (date '2026-11-10', 'tarde'),
                                                (date '2026-11-11', 'manha'), (date '2026-11-11', 'tarde'),
                                                (date '2026-11-12', 'manha'), (date '2026-11-12', 'tarde')) x(dia, turno)) m
                          where m.o <= p_n)))
$f$;
-- A OS-00146 (Quirino): meio dia de diagnóstico só do dono (sempre), pronta para entrar (sinal pago, material conferido).
create function pg_temp.os_do_dono() returns uuid language plpgsql as $f$
begin
  insert into public.clients (id, type, name) values ('c6000000-0000-4000-8000-000000000146', 'individual', 'Quirino');
  insert into public.vessels (id, client_id, name, asset_type)
  values ('f6000000-0000-4000-8000-000000000146', 'c6000000-0000-4000-8000-000000000146', 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
    created_at, updated_at, converted_to_os_at, grand_total)
  values ('05000000-0000-4000-8000-000000000146', 'OS-00146', 'c6000000-0000-4000-8000-000000000146',
          'f6000000-0000-4000-8000-000000000146', 'approved', 'approved', 'repair', timestamptz '2026-10-15 12:00-03',
          timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 500);
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
    unit_price_snapshot, line_total, created_at)
  values (md5('p4:servico:146')::uuid, '05000000-0000-4000-8000-000000000146', null, 'Diagnóstico do sistema elétrico', 'visit', 1,
          500, 500, timestamptz '2026-10-15 12:00-03');
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
    balance_amount, is_deposit)
  values (md5('p4:sinal:146')::uuid, 'c6000000-0000-4000-8000-000000000146', '05000000-0000-4000-8000-000000000146', 'Sinal',
          date '2026-10-20', date '2026-10-20', 200, 'paid', 200, 0, true);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em)
  values ('05000000-0000-4000-8000-000000000146', 0.5, 'dono', timestamptz '2026-10-28 18:00-03', 'sempre',
          timestamptz '2026-10-28 18:00-03');
  return '05000000-0000-4000-8000-000000000146';
end $f$;
-- Liga o item (modo ligado, capacidade_dono na lista) e deixa a troca de 0,24 caber (capacidade_troca_max 0,25): 0,56 em uso.
create function pg_temp.em_uso_056() returns jsonb language plpgsql as $f$
begin
  update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{capacidade_dono}',
                                  capacidade_troca_max = 0.25 where id;
  return pg_temp.capacidade();
end $f$;

-- ── D1. As semanas ──────────────────────────────────────────────────────────────────────────────────────
do $d1$
declare
  v_res jsonb := '[]'::jsonb;
  v   jsonb;
  a   public.agenda_aprendizado;
  n0  int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('D1 as semanas (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := pg_temp.capacidade();
    a := pg_temp.linha();
    v_res := pg_temp.ok(v_res, 'D1a em teste: 5 semanas contam, a mediana 0,70 × 0,80 = 0,56 (calculado), o padrão 0,80, nada em uso, nenhuma ação nem pergunta',
      v ->> 'estado' = 'sombra' and a.calculado = 0.56 and a.padrao = 0.80 and a.n = 5 and a.n_min = 4 and a.em_uso is null
      and a.nivel = 'dono' and v ->> 'acao_id' is null and v ->> 'pergunta_id' is null and (a.detalhe ->> 'taxa')::numeric = 0.7
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'aprendizado')
      and not exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado'),
      to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'D1b o texto do foco em teste (spec §6.2)',
      a.texto = 'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas). Hoje marco até 80% da sua semana; pelo medido seria 56% (em teste).',
      a.texto);
    v_res := pg_temp.ok(v_res, 'D1c as semanas que contam: 31/08 3,5 de 5 (o parcial vale meio; o cancelado por ele conta; o cancelado pela chuva e o sem registro saem), 07/09 2 de 4 (o de material sai), 14/09 3 de 5, 21/09 e 28/09 2 de 2',
      pg_temp.semanas(a.amostra) = '31/08 3.5/5 | 07/09 2/4 | 14/09 3/5 | 21/09 2/2 | 28/09 2/2', pg_temp.semanas(a.amostra));
    v_res := pg_temp.ok(v_res, 'D1d a janela: de seg 31/08 a dom 25/10 (8 semanas); a de 19/10, com 1 meio-dia só, aparece e não conta; a de hoje (26/10) e as sem o dono (05 e 12/10) ficam fora',
      a.detalhe ->> 'de' = '2026-08-31' and a.detalhe ->> 'ate' = '2026-10-25' and a.detalhe ->> 'janela' = '8'
      and a.detalhe -> 'semanas' -> 0 = '{"semana": "2026-10-19", "planejados": 1, "feitos": 1, "conta": false}'::jsonb
      and jsonb_array_length(a.detalhe -> 'semanas') = 6
      and not exists (select 1 from jsonb_array_elements(a.detalhe -> 'semanas') e
                       where e ->> 'semana' in ('2026-10-26', '2026-10-05', '2026-10-12')),
      (a.detalhe -> 'semanas')::text);
    v_res := pg_temp.ok(v_res, 'D1e o detalhe: 3 meios-dias fora do plano (20/10 o dia todo, 22/10 de manhã; a de 27/10 é desta semana e a "passou" não conta) e o que você disse (2 linhas)',
      a.detalhe ->> 'fora_do_plano' = '3' and jsonb_array_length(a.detalhe -> 'voce_disse') = 2
      and a.detalhe -> 'voce_disse' -> 0 ->> 'situacao' = 'disponivel', a.detalhe::text);

    select count(*) into n0 from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item = 'capacidade_dono';
    v := pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D1f rodar de novo no mesmo dia não muda nada (o mesmo estado, nenhuma entrada nova no histórico)',
      v ->> 'estado' = 'sombra' and (v ->> 'calculado')::numeric = 0.56
      and (select count(*) from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item = 'capacidade_dono') = n0,
      v::text);

    -- poucas semanas: medindo
    update public.agenda_config set capacidade_semanas_min = 6 where id;
    v := pg_temp.capacidade();
    a := pg_temp.linha();
    v_res := pg_temp.ok(v_res, 'D1g com o mínimo de 6 semanas: medindo (5 de 6), o texto de medindo',
      v ->> 'estado' = 'medindo' and a.n = 5 and a.n_min = 6
      and a.texto = 'A sua semana no plano: 5 de 6 semanas medidas; marco até 80% da sua semana (padrão).', a.texto);
    update public.agenda_config set capacidade_semanas_min = 4 where id;

    -- os parâmetros mudam a conta
    update public.agenda_config set capacidade_meios_min = 1 where id;
    v := pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D1h com capacidade_meios_min 1, a semana de 19/10 (1 de 1) conta: 6 semanas, a mediana 0,85 → 0,68',
      (v ->> 'calculado')::numeric = 0.68 and (pg_temp.linha()).n = 6, v::text);
    update public.agenda_config set capacidade_meios_min = 2, capacidade_motivos = '{esqueci}' where id;
    v := pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D1i com só "esqueci" em capacidade_motivos, a outra urgência, a equipe faltou e (correção C1, item 5) os parciais pelo trabalho de antes saem da conta (07/09 2 de 3, 14/09 2 de 2): a mediana 1 → 0,80',
      (v ->> 'calculado')::numeric = 0.80
      and pg_temp.semanas((pg_temp.linha()).amostra) = '31/08 3.5/5 | 07/09 2/3 | 14/09 2/2 | 21/09 2/2 | 28/09 2/2',
      pg_temp.semanas((pg_temp.linha()).amostra));
    update public.agenda_config set capacidade_motivos = '{equipe_faltou,urgencia_outra_os,trabalho_anterior,esqueci}' where id;

    -- o piso e o teto
    v_res := pg_temp.ok(v_res, 'D1j o piso de fábrica é 40% (capacidade_dono_min 0,40) e o teto, carga_max',
      (select capacidade_dono_min = 0.40 and carga_max = 0.80 from public.agenda_config where id), null);
    update public.agenda_config set capacidade_dono_min = 0.60 where id;
    v := pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D1k o piso: com capacidade_dono_min 0,60, o medido (0,56) sobe para 0,60',
      (v ->> 'calculado')::numeric = 0.60, v::text);
    update public.agenda_config set capacidade_dono_min = 0.40, carga_max = 0.50 where id;
    v := pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D1l com carga_max 0,50: 0,70 × 0,50 = 0,35, abaixo do piso de 40% → 0,40 (e o padrão é a carga de todos, 0,50)',
      (v ->> 'calculado')::numeric = 0.40 and (pg_temp.linha()).padrao = 0.50, v::text);
    update public.agenda_config set carga_max = 0.80 where id;

    -- sem saber quem é o dono, nada é gravado
    update public.payees set active = false where id = 'bb000000-0000-4000-8000-000000000001';
    select count(*) into n0 from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item = 'capacidade_dono';
    v := pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D1m sem dono (nenhum sócio ativo): {pulado: sem_dono} e nada gravado',
      v = '{"item": "capacidade_dono", "pulado": "sem_dono"}'::jsonb
      and (select count(*) from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item = 'capacidade_dono') = n0,
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d1$;

-- ── D2. A carga de cada pessoa ──────────────────────────────────────────────────────────────────────────
do $d2$
declare
  v_res jsonb := '[]'::jsonb;
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v   jsonb;
  a   public.agenda_aprendizado;
  q   public.agenda_perguntas;
  x   public.agenda_acoes;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('D2 a carga de cada pessoa (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    v_res := pg_temp.ok(v_res, 'D2a desligado: 0,80 para o dono, para o Roberto e para ninguém',
      public._agenda_carga_da_pessoa(c_dono) = 0.80 and public._agenda_carga_da_pessoa(c_roberto) = 0.80
      and public._agenda_carga_da_pessoa(null) = 0.80, null);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D2b em teste (0,56 calculado): o dono continua com 0,80',
      public._agenda_carga_da_pessoa(c_dono) = 0.80, null);

    -- ligado sem o item na lista: continua em teste
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fator}' where id;
    v := pg_temp.capacidade();
    v_res := pg_temp.ok(v_res, 'D2c ligado sem capacidade_dono na lista: em teste, 0,80',
      v ->> 'estado' = 'sombra' and public._agenda_carga_da_pessoa(c_dono) = 0.80, v::text);

    -- ligado com o item: a troca de 0,24 é grande (o limite é 0,20) → pergunta crítica; o que vale continua 0,80
    update public.agenda_config set aprendizado_ligados = '{capacidade_dono}' where id;
    v := pg_temp.capacidade();
    select * into q from public.agenda_perguntas where id = (v ->> 'pergunta_id')::uuid;
    v_res := pg_temp.ok(v_res, 'D2d ligado: a troca de 0,80 para 0,56 é grande → a pergunta crítica aprendizado (chave aprendizado:capacidade_dono:dono, 2 opções: sem o "volto ao padrão", que é o de agora)',
      v ->> 'estado' = 'pergunta' and q.tipo = 'aprendizado' and q.critica and q.estado = 'aberta'
      and q.chave = 'aprendizado:capacidade_dono:dono' and q.recomendacao = 1 and jsonb_array_length(q.opcoes) = 2
      and q.opcoes -> 0 -> 'efeito' = '{"em_uso": 0.56}'::jsonb and q.opcoes -> 1 -> 'efeito' = '{"travar": 0.56}'::jsonb,
      to_jsonb(q)::text);
    v_res := pg_temp.ok(v_res, 'D2e o texto da pergunta (spec §6.3)',
      q.texto = 'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano. Hoje marco até 80% da sua semana; pelo medido seriam 56%. 1) Passo a marcar até 56% (recomendo); 2) Fico com 80%.',
      q.texto);
    v_res := pg_temp.ok(v_res, 'D2f com a pergunta aberta o que vale é o de agora: 0,80; o foco diz que espera a resposta',
      public._agenda_carga_da_pessoa(c_dono) = 0.80
      and (pg_temp.linha()).texto = 'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas). Hoje marco até 80% da sua semana; pelo medido seriam 56%: a troca espera a sua resposta.',
      (pg_temp.linha()).texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    execute current_setting('agenda_teste.fase6');
    v := pg_temp.em_uso_056();
    a := pg_temp.linha();
    select * into x from public.agenda_acoes where id = (v ->> 'acao_id')::uuid;
    v_res := pg_temp.ok(v_res, 'D2g a troca cabe (capacidade_troca_max 0,25): 0,56 em uso, com a ação aprendizado (origem vigia, *desfaz* até amanhã, antes nulo = o padrão 0,80)',
      v ->> 'estado' = 'em_uso' and a.em_uso = 0.56 and a.em_uso_desde = timestamptz '2026-10-30 16:05-03'
      and x.tipo = 'aprendizado' and x.origem = 'vigia' and x.executada and x.dia = date '2026-10-30'
      and x.desfazivel_ate = timestamptz '2026-10-31 16:05-03'
      and x.antes = '{"item": "capacidade_dono", "chave": "dono", "nivel": "dono", "em_uso": null, "valor": 0.80, "estado": "medindo"}'::jsonb
      and x.depois = '{"item": "capacidade_dono", "chave": "dono", "nivel": "dono", "em_uso": 0.56, "n": 5}'::jsonb,
      to_jsonb(x)::text);
    v_res := pg_temp.ok(v_res, 'D2h o texto da ação (o que mudou sozinho, spec §6.3) e o do foco em uso',
      x.texto = 'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus do plano: passei a marcar até 56% da sua semana (era 80%). *desfaz aprendizado* volta.'
      and a.texto = 'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas): marco até 56% da sua semana desde sex 30/10.',
      x.texto || ' / ' || a.texto);
    v_res := pg_temp.ok(v_res, 'D2i em uso: 0,56 para o dono; 0,80 para o Roberto e para ninguém',
      public._agenda_carga_da_pessoa(c_dono) = 0.56 and public._agenda_carga_da_pessoa(c_roberto) = 0.80
      and public._agenda_carga_da_pessoa(null) = 0.80, null);
    v_res := pg_temp.ok(v_res, 'D2j o admin pelo login lê a mesma carga (0,56); o anon não executa (42501)',
      pg_temp.como(c_admin, 'authenticated', format('select public._agenda_carga_da_pessoa(%L)::text', c_dono)) = '0.56'
      and pg_temp.como(null, 'anon', format('select public._agenda_carga_da_pessoa(%L)::text', c_dono)) like 'erro 42501%',
      pg_temp.como(c_admin, 'authenticated', format('select public._agenda_carga_da_pessoa(%L)::text', c_dono)) || ' / '
      || pg_temp.como(null, 'anon', format('select public._agenda_carga_da_pessoa(%L)::text', c_dono)));
    update public.agenda_config set carga_max = 0.50 where id;
    v_res := pg_temp.ok(v_res, 'D2k nunca acima de carga_max: com a carga de todos em 0,50, o dono também fica em 0,50 (o 0,56 em uso não sobe)',
      public._agenda_carga_da_pessoa(c_dono) = 0.50 and public._agenda_carga_da_pessoa(c_roberto) = 0.50, null);
    update public.agenda_config set carga_max = 0.80 where id;
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'D2l o modo em sombra volta o padrão na hora (o leitor único): 0,80, sem rodar nada',
      public._agenda_carga_da_pessoa(c_dono) = 0.80 and (pg_temp.linha()).em_uso = 0.56, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d2$;

-- ── D3 e D4. O motor e o validador; o publicado não muda ────────────────────────────────────────────────
do $d3$
declare
  v_res jsonb := '[]'::jsonb;
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao    constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_hoje    constant date := date '2026-10-30';
  c_agora   constant timestamptz := timestamptz '2026-10-30 16:30-03';
  v_os   uuid;
  v_104  uuid;
  c0 jsonb; c1 jsonb;
  r0 jsonb; r1 jsonb; r2 jsonb; r3 jsonb;
  s0 jsonb; s1 jsonb;
  w0 jsonb; w1 jsonb;
  v_vig  text;
  v_sai  text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('D3 e D4 o motor e o validador (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    select id into v_104 from public.service_orders where service_order_number = 'OS-00104';
    v_os := pg_temp.os_do_dono();
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform pg_temp.capacidade();

    -- em teste
    c0 := public._agenda_contexto(date '2026-11-02', date '2026-11-14', c_hoje);
    r0 := pg_temp.propor('os', array[v_os]);
    s0 := pg_temp.propor('semana');
    w0 := pg_temp.propor('semana', null, '{"acima_da_carga": true}'::jsonb);
    v_vig := pg_temp.vigentes_do_dono();
    -- (a validação da semana de 09/11: 6 meios-dias do dono e 4 do Roberto)
    r2 := public._agenda_validar_itens(pg_temp.itens(v_104, c_dono, 'Gustavo', 6) || pg_temp.itens(v_104, c_roberto, 'Roberto', 4),
                                       '{}'::jsonb, c_hoje, c_agora, false);

    -- ligado, 0,56 em uso para o dono
    perform pg_temp.em_uso_056();
    c1 := public._agenda_contexto(date '2026-11-02', date '2026-11-14', c_hoje);
    r1 := pg_temp.propor('os', array[v_os]);
    s1 := pg_temp.propor('semana');
    w1 := pg_temp.propor('semana', null, '{"acima_da_carga": true}'::jsonb);
    r3 := public._agenda_validar_itens(pg_temp.itens(v_104, c_dono, 'Gustavo', 6) || pg_temp.itens(v_104, c_roberto, 'Roberto', 4),
                                       '{}'::jsonb, c_hoje, c_agora, false);

    v_res := pg_temp.ok(v_res, 'D3a o contexto: a pessoa 1 é você (v_pes[1]); o teto80 das suas 2 semanas cai de 5 e 7 para floor(0,56 × 7) = 3 e floor(0,56 × 9) = 5; o João e o Roberto (posições 3–6) e o teto100 não mudam',
      c1 -> 'pessoas' ->> 0 = c_dono::text and c1 ->> 'nw' = '2'
      and c0 -> 'teto80' = '[5, 7, 3, 3, 6, 7]'::jsonb and c1 -> 'teto80' = '[3, 5, 3, 3, 6, 7]'::jsonb
      and c1 -> 'teto100' = c0 -> 'teto100' and c1 -> 'esperado' = c0 -> 'esperado'
      and (c1 - 'teto80') = (c0 - 'teto80'),
      (c0 -> 'teto80')::text || ' → ' || (c1 -> 'teto80')::text || ' ' || (c1 -> 'nomes')::text);
    v_res := pg_temp.ok(v_res, 'D3b o motor: a OS-00146 (meio dia só seu) cabia na qui 05/11 de manhã (você com 3 de 5 na semana de 02/11); com 0,56 a semana de 02/11 fica cheia (3 de 3) e ela vai para seg 09/11 de manhã',
      pg_temp.celulas(r0, 'OS-00146') = '05/11 manha Gustavo turno' and pg_temp.celulas(r1, 'OS-00146') = '09/11 manha Gustavo turno'
      and r1 #>> array['carga', c_dono::text, 'semanas', '0', 'teto80'] = '3'
      and r1 #>> array['carga', c_dono::text, 'semanas', '0', 'compromisso'] = '3'
      and r0 #>> array['carga', c_dono::text, 'semanas', '0', 'teto80'] = '5',
      pg_temp.celulas(r0, 'OS-00146') || ' → ' || pg_temp.celulas(r1, 'OS-00146'));
    v_res := pg_temp.ok(v_res, 'D3c no motor, a carga da equipe não muda (o Roberto e o João com o mesmo teto80 nas duas)',
      r1 -> 'carga' -> c_roberto::text = r0 -> 'carga' -> c_roberto::text
      and coalesce(r1 -> 'carga' -> c_joao::text, 'null') = coalesce(r0 -> 'carga' -> c_joao::text, 'null')
      and s1 -> 'carga' -> c_roberto::text = s0 -> 'carga' -> c_roberto::text, null);
    v_res := pg_temp.ok(v_res, 'D3d o validador, a mesma semana de 09/11: em teste nenhuma regra 6; com 0,56, só você passa do limite, com o texto de sempre ("6 meios-dias de serviço para 5"); o Roberto (4 com 3 já publicados, teto 7) nas duas fica dentro',
      not exists (select 1 from jsonb_array_elements(r2) e where (e ->> 'regra')::int = 6)
      and (select jsonb_agg(e) from jsonb_array_elements(r3) e where (e ->> 'regra')::int = 6)
          = '[{"regra": 6, "pessoa": "Gustavo", "dia": "2026-11-09", "texto": "Gustavo passaria do limite da semana de 09/11: 6 meios-dias de serviço para 5."}]'::jsonb
      and (select jsonb_agg(e order by o) from jsonb_array_elements(r3) with ordinality t(e, o) where (e ->> 'regra')::int <> 6)
          = (select jsonb_agg(e order by o) from jsonb_array_elements(r2) with ordinality t(e, o) where (e ->> 'regra')::int <> 6),
      r3::text);
    v_res := pg_temp.ok(v_res, 'D3e com acima_da_carga o teto é o 100% de sempre: a proposta da semana sai igual à de teste (fora a carga do dono, no resumo e no texto da carga)',
      (w1 - 'carga' - 'textos') = (w0 - 'carga' - 'textos') and ((w1 -> 'textos') - 'carga') = ((w0 -> 'textos') - 'carga')
      and w1 -> 'carga' -> c_roberto::text = w0 -> 'carga' -> c_roberto::text
      and pg_temp.celulas(w1, 'OS-00146') = '05/11 manha Gustavo turno', pg_temp.celulas(w1, 'OS-00146'));
    v_res := pg_temp.ok(v_res, 'D3f o texto da carga ao dono diz o teto novo ("Você: 3 de 3 meios-dias de serviço na semana de 02/11"); o da equipe é o de teste',
      s1 -> 'textos' -> 'carga' ->> 0 = 'Você: 3 de 3 meios-dias de serviço na semana de 02/11'
      and s0 -> 'textos' -> 'carga' ->> 0 = 'Você: 4 de 5 meios-dias de serviço na semana de 02/11'
      and (s1 -> 'textos' -> 'carga') - 0 = (s0 -> 'textos' -> 'carga') - 0,
      (s0 -> 'textos' -> 'carga')::text || ' → ' || (s1 -> 'textos' -> 'carga')::text);

    v_res := pg_temp.ok(v_res, 'D4a o publicado não muda: a semana de 02/11 já tem 3 meios-dias seus de turno publicados (= o teto novo); a proposta tira as mesmas alocações que em teste (as da OS-00069, pela peça), nenhum turno seu',
      pg_temp.saidas(s1) = pg_temp.saidas(s0)
      and not exists (select 1 from jsonb_array_elements(s1 -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') x
                        join public.agenda_alocacoes a on a.id = (x ->> 'alocacao_id')::uuid
                       where i ->> 'op' = 'cancelar' and a.payee_id = c_dono and a.presenca = 'turno')
      and pg_temp.vigentes_do_dono() = v_vig,
      pg_temp.saidas(s1));

    -- a carga do dono ABAIXO do que ele já tem publicado: 0,40 → floor(0,40 × 7) = 2 < 3 na semana de 02/11
    update public.agenda_aprendizado set em_uso = 0.40 where item = 'capacidade_dono' and chave = 'dono';
    s1 := pg_temp.propor('semana');
    r3 := public._agenda_validar_itens(
            (select jsonb_agg(jsonb_build_object('op', 'cancelar', 'os', a.service_order_id, 'numero', 'OS', 'motivo', 'replanejado',
                                                 'alocacoes', jsonb_build_array(jsonb_build_object('alocacao_id', a.id))))
               from public.agenda_alocacoes a
              where a.payee_id = c_dono and a.estado = 'publicada' and a.dia = date '2026-11-04'),
            '{}'::jsonb, c_hoje, c_agora, false);
    v_res := pg_temp.ok(v_res, 'D4b com 0,40 (teto 2, abaixo dos 3 publicados): o teto80 é 2, e mesmo assim nada seu sai do plano (os mesmos "sai" que em teste)',
      s1 #>> array['carga', c_dono::text, 'semanas', '0', 'teto80'] = '2'
      and s1 #>> array['carga', c_dono::text, 'semanas', '0', 'compromisso'] = '3'
      and pg_temp.saidas(s1) = pg_temp.saidas(s0) and pg_temp.vigentes_do_dono() = v_vig,
      (s1 -> 'carga' -> c_dono::text)::text);
    v_res := pg_temp.ok(v_res, 'D4c a regra 6 só pesa em alocação nova: tirar 2 meios-dias seus da semana de 02/11 (sem pôr nada) não viola o teto de 2',
      not exists (select 1 from jsonb_array_elements(r3) e where (e ->> 'regra')::int = 6), r3::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d3$;

-- ── D5. As cópias, as assinaturas e as portas (em qualquer lugar) ───────────────────────────────────────
do $d5$
declare
  v_motor text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_forn6 text := coalesce(current_setting('agenda_teste.mig_fornecedor_fase6', true), '');
  rc record;
begin
  insert into _resultado
  select format('D5a %s: a mesma assinatura (%s → %s), %s, volatilidade %s, definer %s, search_path fixo', r.f, r.args, r.ret, r.lang, r.vol, r.def),
         p.oid is not null and pg_get_function_identity_arguments(p.oid) = r.args and pg_get_function_result(p.oid) = r.ret
         and l.lanname = r.lang and p.provolatile = r.vol and p.prosecdef = r.def
         and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%',
         format('%s(%s) → %s, %s, %s, definer %s', p.proname, pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid),
                l.lanname, p.provolatile, p.prosecdef)
    from (values ('_agenda_contexto', 'p_d_ini date, p_d_fim date, p_hoje date, p_ignorar uuid[], p_fila uuid[]', 'jsonb', 'plpgsql', 's', false,
                  'public._agenda_contexto(date, date, date, uuid[], uuid[])'),
                 ('_agenda_validar_itens', 'p_itens jsonb, p_parametros jsonb, p_hoje date, p_agora timestamp with time zone, p_aplicar boolean, p_pront jsonb',
                  'jsonb', 'plpgsql', 's', false, 'public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)'),
                 ('_agenda_aprendizado_texto', 'p_item text, p_momento text, p_d jsonb', 'text', 'plpgsql', 'i', false,
                  'public._agenda_aprendizado_texto(text, text, jsonb)'),
                 ('_agenda_carga_da_pessoa', 'p_payee uuid', 'numeric', 'plpgsql', 's', false, 'public._agenda_carga_da_pessoa(uuid)'),
                 ('_agenda_aprender_capacidade', 'p_hoje date, p_agora timestamp with time zone', 'jsonb', 'plpgsql', 'v', false,
                  'public._agenda_aprender_capacidade(date, timestamptz)')) r(f, args, ret, lang, vol, def, sig)
    left join pg_proc p on p.oid = to_regprocedure(r.sig)
    left join pg_language l on l.oid = p.prolang;

  -- as portas: anon nunca; a carga e o validador para authenticated e service_role; o contexto só service_role; o passo ninguém
  insert into _resultado
  select format('D5b %s: authenticated %s, service_role %s, anon nunca', f, aut, svc),
         not has_function_privilege('anon', to_regprocedure(f), 'execute')
         and has_function_privilege('authenticated', to_regprocedure(f), 'execute') = aut
         and has_function_privilege('service_role', to_regprocedure(f), 'execute') = svc,
         null
    from (values ('public._agenda_carga_da_pessoa(uuid)', true, true),
                 ('public._agenda_aprendizado_texto(text, text, jsonb)', true, true),
                 ('public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', true, true),
                 ('public.agenda_validar(uuid, uuid[], date, timestamptz, uuid)', true, true),
                 ('public._agenda_contexto(date, date, date, uuid[], uuid[])', false, true),
                 ('public._agenda_aprender_capacidade(date, timestamptz)', false, false)) t(f, aut, svc);

  if v_motor = '' or v_forn6 = '' then
    insert into _resultado values ('D5c as cópias', true, 'PULADO: sem agenda_teste.mig_* (rode pela bancada)');
    return;
  end if;
  for rc in
    select * from (values
      ('_agenda_contexto', 'public._agenda_contexto(date, date, date, uuid[], uuid[])', v_motor, '20261025100200'),
      ('_agenda_validar_itens', 'public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', v_motor, '20261025100200'),
      ('_agenda_aprendizado_texto', 'public._agenda_aprendizado_texto(text, text, jsonb)', v_forn6, '20261029100300')
    ) t(nome, assinatura, fonte, versao)
  loop
    insert into _resultado
    select format('D5c a cópia de %s (de %s) só acrescenta os blocos "-- FASE 6:"', rc.nome, rc.versao),
           pg_temp.sem_fase6(p.prosrc) = pg_temp.sem_fase6(pg_temp.corpo(rc.fonte, rc.nome))
           and cardinality(pg_temp.sem_fase6(p.prosrc)) > 5
           and (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: fim', 'g'))
               > (select count(*) from regexp_matches(pg_temp.corpo(rc.fonte, rc.nome), '-- FASE 6: fim', 'g')),
           format('%s linhas fora dos blocos; %s blocos (a fonte: %s)', cardinality(pg_temp.sem_fase6(p.prosrc)),
                  (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: fim', 'g')),
                  (select count(*) from regexp_matches(pg_temp.corpo(rc.fonte, rc.nome), '-- FASE 6: fim', 'g')))
      from pg_proc p where p.oid = rc.assinatura::regprocedure;
  end loop;
  -- a regra 6: dentro do bloco novo, a carga de cada pessoa; fora dele (a de antes, que não roda), carga_max; e agenda_validar
  -- continua a de 20261025100200 (só chama _agenda_validar_itens)
  insert into _resultado
  select 'D5d a regra 6 nova lê _agenda_carga_da_pessoa (3 vezes pela coluna carga) e a de antes fica num "if false"; agenda_validar não foi recriada',
         p.prosrc ~ 'public\._agenda_carga_da_pessoa\(n\.payee_id\) as carga'
         and (select count(*) from regexp_matches(p.prosrc, 'nov\.carga \*', 'g')) = 3
         and p.prosrc ~ E'\n  if false then\n  -- FASE 6: fim\n  v_v := v_v \\|\\| coalesce\\(\\('
         and (select q.prosrc from pg_proc q where q.oid = 'public.agenda_validar(uuid, uuid[], date, timestamptz, uuid)'::regprocedure)
             = pg_temp.corpo(v_motor, 'agenda_validar'),
         null
    from pg_proc p where p.oid = 'public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)'::regprocedure;
end
$d5$;

-- ── D6. Byte a byte com as definições de antes ──────────────────────────────────────────────────────────
do $d6$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_hoje    constant date := date '2026-10-30';
  c_agora   constant timestamptz := timestamptz '2026-10-30 16:30-03';
  v_modo  record;
  v_dif   text;
  v_n     int;
  v_novo  text;
  v_antes text;
  v_itens jsonb;
  v_104   uuid;
  v_os    uuid;
  v_cart  uuid[];
  v_trocou boolean;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or v_mig = '' then
    insert into _resultado values ('D6 byte a byte (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    execute replace(pg_temp.inteira(v_mig, '_agenda_contexto'), 'create or replace function public._agenda_contexto(',
                    'create function pg_temp.contexto_de_antes(');
    execute replace(pg_temp.inteira(v_mig, '_agenda_validar_itens'), 'create or replace function public._agenda_validar_itens(',
                    'create function pg_temp.validar_de_antes(');
    select id into v_104 from public.service_orders where service_order_number = 'OS-00104';
    v_os := pg_temp.os_do_dono();
    v_cart := array(select k.service_order_id from public.os_carteira(c_hoje) k order by 1);
    -- o calculado (0,56) existe em todos os modos abaixo
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform pg_temp.capacidade();

    for v_modo in
      select * from (values (1, 'em teste', 'sombra', '{}'::text[]),
                            (2, 'ligado sem a lista', 'ligado', '{fator,mo}'::text[]),
                            (3, 'ligado com a pergunta aberta (nada em uso)', 'ligado', '{capacidade_dono}'::text[])) m(k, nome, modo, lista)
       order by k
    loop
      update public.agenda_config set modo_aprendizado = v_modo.modo, aprendizado_ligados = v_modo.lista where id;
      perform pg_temp.capacidade();

      -- o contexto: cada semana de 31/08 a 14/12 (seg a sáb) e de duas em duas, e uma com a fila e o ignorar
      select count(*), string_agg(to_char(s::date, 'DD/MM'), ', ') filter (where
               public._agenda_contexto(s::date, s::date + 5, c_hoje)::text is distinct from pg_temp.contexto_de_antes(s::date, s::date + 5, c_hoje)::text
               or public._agenda_contexto(s::date, s::date + 12, c_hoje)::text is distinct from pg_temp.contexto_de_antes(s::date, s::date + 12, c_hoje)::text)
        into v_n, v_dif
        from generate_series(date '2026-08-31', date '2026-12-14', interval '7 days') s;
      v_res := pg_temp.ok(v_res, format('D6a%s %s: o contexto do motor de %s semanas (de 31/08 a 14/12, uma e duas semanas) é o de antes, byte a byte', v_modo.k, v_modo.nome, v_n),
        v_dif is null and v_n = 16
        and public._agenda_contexto(date '2026-11-02', date '2026-11-21', c_hoje,
              array(select a.id from public.agenda_alocacoes a where a.service_order_id = v_104 and a.estado = 'publicada'), v_cart)::text
            = pg_temp.contexto_de_antes(date '2026-11-02', date '2026-11-21', c_hoje,
              array(select a.id from public.agenda_alocacoes a where a.service_order_id = v_104 and a.estado = 'publicada'), v_cart)::text,
        coalesce(v_dif, '—'));

      -- o validador: os itens das propostas do motor (semana, replano, cada OS da carteira) e os da semana de 09/11
      v_itens := coalesce((select jsonb_agg(i) from (
                   select jsonb_array_elements(pg_temp.propor('semana') -> 'itens') i
                   union all select jsonb_array_elements(pg_temp.propor('replano', v_cart) -> 'itens')
                   union all select jsonb_array_elements(pg_temp.propor('os', v_cart) -> 'itens')
                   union all select jsonb_array_elements(pg_temp.propor('semana', null, '{"acima_da_carga": true}'::jsonb) -> 'itens')) x),
                 '[]'::jsonb)
                 || pg_temp.itens(v_104, c_dono, 'Gustavo', 8) || pg_temp.itens(v_104, c_roberto, 'Roberto', 8);
      v_res := pg_temp.ok(v_res, format('D6b%s %s: o validador dos %s itens (as propostas do motor e 8 meios-dias seus e do Roberto) é o de antes, com e sem acima_da_carga e p_aplicar', v_modo.k, v_modo.nome, jsonb_array_length(v_itens)),
        jsonb_array_length(v_itens) > 4
        and public._agenda_validar_itens(v_itens, '{}'::jsonb, c_hoje, c_agora, false)::text
            = pg_temp.validar_de_antes(v_itens, '{}'::jsonb, c_hoje, c_agora, false)::text
        and public._agenda_validar_itens(v_itens, '{"p_restricoes": {"acima_da_carga": true}}'::jsonb, c_hoje, c_agora, true)::text
            = pg_temp.validar_de_antes(v_itens, '{"p_restricoes": {"acima_da_carga": true}}'::jsonb, c_hoje, c_agora, true)::text
        and exists (select 1 from jsonb_array_elements(public._agenda_validar_itens(v_itens, '{}'::jsonb, c_hoje, c_agora, false)) e
                     where (e ->> 'regra')::int = 6),
        null);

      -- o motor inteiro: com as definições novas e, por um instante (desfeito na hora), com as de antes no lugar delas
      v_novo := md5(pg_temp.propor('semana')::text) || md5(pg_temp.propor('replano', v_cart)::text) || md5(pg_temp.propor('os', v_cart)::text)
                || md5(pg_temp.propor('os', array[v_os])::text);
      v_trocou := false;
      begin
        execute pg_temp.inteira(v_mig, '_agenda_contexto');
        execute pg_temp.inteira(v_mig, '_agenda_validar_itens');
        v_trocou := (select bool_and(prosrc !~ '-- FASE 6:') from pg_proc
                      where oid in ('public._agenda_contexto(date, date, date, uuid[], uuid[])'::regprocedure,
                                    'public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)'::regprocedure));
        v_antes := md5(pg_temp.propor('semana')::text) || md5(pg_temp.propor('replano', v_cart)::text) || md5(pg_temp.propor('os', v_cart)::text)
                   || md5(pg_temp.propor('os', array[v_os])::text);
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      v_res := pg_temp.ok(v_res, format('D6c%s %s: o motor (agenda_propor semana, replano, a carteira e a OS só sua) sai igual ao de antes, byte a byte', v_modo.k, v_modo.nome),
        v_trocou and v_novo = v_antes
        and (select prosrc from pg_proc where oid = 'public._agenda_contexto(date, date, date, uuid[], uuid[])'::regprocedure) ~ '-- FASE 6: \(P4\)',
        v_novo || ' / ' || coalesce(v_antes, '-'));
    end loop;

    -- o controle: com 0,56 em uso, as mesmas comparações acusam a diferença (a conferência enxerga a carga do dono)
    perform pg_temp.em_uso_056();
    v_novo := md5(pg_temp.propor('os', array[v_os])::text);
    begin
      execute pg_temp.inteira(v_mig, '_agenda_contexto');
      execute pg_temp.inteira(v_mig, '_agenda_validar_itens');
      v_antes := md5(pg_temp.propor('os', array[v_os])::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'D6d o controle, com 0,56 em uso: o contexto da semana de 02/11, o validador dos 8 meios-dias seus e o motor da OS só sua deixam de ser os de antes',
      public._agenda_contexto(date '2026-11-02', date '2026-11-07', c_hoje)::text
        is distinct from pg_temp.contexto_de_antes(date '2026-11-02', date '2026-11-07', c_hoje)::text
      and public._agenda_validar_itens(pg_temp.itens(v_104, c_dono, 'Gustavo', 8), '{}'::jsonb, c_hoje, c_agora, false)::text
        is distinct from pg_temp.validar_de_antes(pg_temp.itens(v_104, c_dono, 'Gustavo', 8), '{}'::jsonb, c_hoje, c_agora, false)::text
      and v_novo is distinct from v_antes,
      v_novo || ' / ' || coalesce(v_antes, '-'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d6$;

-- ── D7. Os textos da capacidade (em qualquer lugar: só a função) ────────────────────────────────────────
insert into _resultado
select 'D7 ' || t.nome, public._agenda_aprendizado_texto('capacidade_dono', t.momento, t.d::jsonb) = t.espera,
       public._agenda_aprendizado_texto('capacidade_dono', t.momento, t.d::jsonb)
  from (values
    ('a medindo', 'foco_medindo', '{"chave": "dono", "n": 3, "n_min": 4, "padrao": 0.8}',
     'A sua semana no plano: 3 de 4 semanas medidas; marco até 80% da sua semana (padrão).'),
    ('b em teste (spec §6.2)', 'foco_sombra', '{"chave": "dono", "calculado": 0.56, "padrao": 0.8, "n": 5, "detalhe": {"taxa": 0.7, "janela": 8}}',
     'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas). Hoje marco até 80% da sua semana; pelo medido seria 56% (em teste).'),
    ('c em uso', 'foco_em_uso', '{"chave": "dono", "em_uso": 0.72, "n": 5, "desde": "2026-11-26", "detalhe": {"taxa": 0.9, "janela": 8}}',
     'Nas últimas 8 semanas você fez 9 de cada 10 meios-dias seus marcados no plano (5 semanas medidas): marco até 72% da sua semana desde qui 26/11.'),
    ('d esperando a resposta', 'foco_pergunta', '{"chave": "dono", "calculado": 0.56, "efetivo": 0.8, "padrao": 0.8, "n": 5, "detalhe": {"taxa": 0.7, "janela": 8}}',
     'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas). Hoje marco até 80% da sua semana; pelo medido seriam 56%: a troca espera a sua resposta.'),
    ('e travado', 'foco_travado', '{"chave": "dono", "calculado": 0.56, "efetivo": 0.8, "n": 5, "travado_ate": "2026-11-27", "detalhe": {"taxa": 0.7, "janela": 8}}',
     'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano (5 semanas medidas). Pelo medido seriam 56%; fico com 80% da sua semana até sex 27/11, como você decidiu.'),
    ('f a ação (spec §6.3)', 'acao', '{"chave": "dono", "calculado": 0.72, "efetivo": 0.8, "n": 5, "detalhe": {"taxa": 0.9, "janela": 8}}',
     'Nas últimas 8 semanas você fez 9 de cada 10 meios-dias seus do plano: passei a marcar até 72% da sua semana (era 80%). *desfaz aprendizado* volta.'),
    ('g a pergunta (spec §6.3, sem as opções)', 'pergunta', '{"chave": "dono", "calculado": 0.56, "efetivo": 0.8, "n": 5, "detalhe": {"taxa": 0.7, "janela": 8}}',
     'Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano. Hoje marco até 80% da sua semana; pelo medido seriam 56%.'),
    ('h opção 1', 'opcao1', '{"chave": "dono", "calculado": 0.56}', 'Passo a marcar até 56%'),
    ('i opção 2', 'opcao2', '{"chave": "dono", "efetivo": 0.8}', 'Fico com 80%'),
    ('j desfeito (volta ao padrão)', 'desfeito', '{"chave": "dono", "volta": null, "padrao": 0.8, "trava_dias": 28}',
     'Desfeito: volto a marcar até 80% da sua semana. Não troco de novo por 28 dias, salvo se o medido mudar muito.'),
    ('k fico com o de agora', 'fico', '{"chave": "dono", "efetivo": 0.8}',
     'Combinado: fico com 80% da sua semana. Volto a perguntar se o medido mudar muito.'),
    ('l uma semana só (singular)', 'foco_sombra', '{"chave": "dono", "calculado": 0.4, "padrao": 0.8, "n": 1, "detalhe": {"taxa": 0.5, "janela": 8}}',
     'Nas últimas 8 semanas você fez 5 de cada 10 meios-dias seus marcados no plano (1 semana medida). Hoje marco até 80% da sua semana; pelo medido seria 40% (em teste).')
  ) t(nome, momento, d, espera);

insert into _resultado
select 'D7m nenhum jargão nos textos da capacidade (mediana, percentil, P80, amostra, PPC, carga_max, "du")',
       bool_and(x !~* '(mediana|percentil|p80|amostra|\mppc\M|carga_max|\mdu\M)'),
       string_agg(x, ' | ') filter (where x ~* '(mediana|percentil|p80|amostra|\mppc\M|carga_max|\mdu\M)')
  from (select public._agenda_aprendizado_texto('capacidade_dono', m, '{"chave": "dono", "calculado": 0.56, "em_uso": 0.56, "efetivo": 0.8, "padrao": 0.8, "volta": null, "n": 5, "n_min": 4, "desde": "2026-10-30", "travado_ate": "2026-11-27", "trava_dias": 28, "detalhe": {"taxa": 0.7, "janela": 8}}') as x
          from unnest(array['foco_medindo', 'foco_sombra', 'foco_em_uso', 'foco_pergunta', 'foco_travado', 'acao', 'pergunta',
                            'opcao1', 'opcao2', 'opcao3', 'desfeito', 'fico']) m) t;

-- ── D8. A correção C1 (20261029100900): itens 4, 5 e 14 ──────────────────────────────────────────────────
-- (item 5, decisão do dono com a recomendação aplicada) a capacidade conta só a falta dele: o cancelado a pedido do dono e o
-- parcial pela chuva saem da conta (o rev-f6 c4). (item 4) sem o vaivém: com 0,56 em uso e o dono fazendo tudo o que o motor
-- marcou com ela, a rodada seguinte fica em 0,56 (antes ia a 0,80). (item 14) a reserva por teto da OS que precisa do dono
-- diz a parte da semana dele.
do $d8$
declare
  v_res jsonb := '[]'::jsonb;
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_hoje    constant date := date '2026-10-30';
  v   jsonb;
  a   public.agenda_aprendizado;
  n0  int;
  r   jsonb;
  v_t text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('D8 a correção C1 da capacidade (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;

  -- (item 5) o cancelado de qui 03/09 de manhã a pedido do dono (o motor obedecendo a ele: cancelada_motivo 'dono')
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_alocacoes set cancelada_motivo = 'dono'
     where payee_id = c_dono and dia = date '2026-09-03' and turno = 'manha' and estado = 'cancelada';
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := pg_temp.capacidade();
    a := pg_temp.linha();
    v_res := pg_temp.ok(v_res, 'D8a (C1, item 5) o cancelado a pedido do dono não é falta dele: 31/08 3,5 de 4, a mediana 0,875 → 0,70',
      a.calculado = 0.70 and (a.detalhe ->> 'taxa')::numeric = 0.88 and pg_temp.semanas(a.amostra) like '31/08 3.5/4 |%',
      pg_temp.semanas(a.amostra) || ' / ' || to_jsonb(a)::text);
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{capacidade_dono}' where id;
    v := pg_temp.capacidade();
    a := pg_temp.linha();
    v_res := pg_temp.ok(v_res, 'D8b (C1, item 5) ligado, 0,80 → 0,70 cabe na troca (0,20): entra sozinha, com a ação',
      a.estado = 'em_uso' and a.em_uso = 0.70 and a.acao_id is not null and v ->> 'pergunta_id' is null, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 5) a tarde de ter 22/09 parou pela chuva (parcial, motivo clima): fora da conta
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_alocacoes set resultado = 'parcial', motivo = 'clima'
     where payee_id = c_dono and dia = date '2026-09-22' and turno = 'tarde';
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := pg_temp.capacidade();
    a := pg_temp.linha();
    v_res := pg_temp.ok(v_res, 'D8c (C1, item 5) o parcial pela chuva sai da conta (não pesa meio meio-dia contra ele): a semana de 21/09 fica com 1 de 1 (e não conta)',
      exists (select 1 from jsonb_array_elements(a.detalhe -> 'semanas') s
               where s ->> 'semana' = '2026-09-21' and s ->> 'planejados' = '1' and s ->> 'feitos' = '1' and s ->> 'conta' = 'false'),
      (a.detalhe -> 'semanas')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 4) o vaivém: 0,56 em uso desde antes da janela e o dono fez tudo o que o motor marcou com ela
  begin
    execute current_setting('agenda_teste.fase6');
    perform pg_temp.em_uso_056();
    update public.agenda_config set capacidade_troca_max = 0.20 where id;
    update public.agenda_aprendizado set em_uso_desde = timestamptz '2026-08-28 16:05-03'
     where item = 'capacidade_dono' and chave = 'dono';
    update public.agenda_alocacoes set resultado = 'cumprido', motivo = null
     where payee_id = c_dono and dia between date '2026-08-31' and date '2026-10-25' and estado in ('publicada', 'fixada')
       and resultado is not null;
    update public.agenda_alocacoes set cancelada_motivo = 'clima'
     where payee_id = c_dono and dia between date '2026-08-31' and date '2026-10-25' and estado = 'cancelada';
    select count(*) into n0 from public.agenda_acoes x where x.tipo = 'aprendizado' and x.antes ->> 'item' = 'capacidade_dono';
    v := pg_temp.capacidade();
    a := pg_temp.linha();
    v_res := pg_temp.ok(v_res, 'D8d (C1, item 4) sem o vaivém: com 0,56 em uso e tudo o que o motor marcou feito (taxa 1), a capacidade continua 0,56 (1 × a carga com que as semanas foram marcadas), sem ação nem pergunta',
      a.estado = 'em_uso' and a.em_uso = 0.56 and a.calculado = 0.56 and v ->> 'pergunta_id' is null
      and (select count(*) from public.agenda_acoes x where x.tipo = 'aprendizado' and x.antes ->> 'item' = 'capacidade_dono') = n0,
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 14) a OS-00160 (Silas): 3 dias com você o dia todo e o Roberto, pronta; com 0,56 em uso a semana de 02/11 não tem lugar
  -- para você, e a equipe guarda o lugar (reserva por teto)
  begin
    execute current_setting('agenda_teste.fase6');
    insert into public.clients (id, type, name) values ('c6000000-0000-4000-8000-000000000160', 'individual', 'Silas');
    insert into public.vessels (id, client_id, name, asset_type)
    values ('f6000000-0000-4000-8000-000000000160', 'c6000000-0000-4000-8000-000000000160', 'Motorhome', 'Motorhome');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
      created_at, updated_at, converted_to_os_at, grand_total)
    values ('05000000-0000-4000-8000-000000000160', 'OS-00160', 'c6000000-0000-4000-8000-000000000160',
            'f6000000-0000-4000-8000-000000000160', 'approved', 'approved', 'repair', timestamptz '2026-10-15 12:00-03',
            timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 3000);
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
      unit_price_snapshot, line_total, created_at)
    values (md5('c1:servico:160')::uuid, '05000000-0000-4000-8000-000000000160', null, 'Instalação do sistema de energia solar',
            'visit', 1, 3000, 3000, timestamptz '2026-10-15 12:00-03');
    insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
      balance_amount, is_deposit)
    values (md5('c1:sinal:160')::uuid, 'c6000000-0000-4000-8000-000000000160', '05000000-0000-4000-8000-000000000160', 'Sinal',
            date '2026-10-20', date '2026-10-20', 1000, 'paid', 1000, 0, true);
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em)
    values ('05000000-0000-4000-8000-000000000160', 3, 'dono', timestamptz '2026-10-28 18:00-03', 'sempre',
            timestamptz '2026-10-28 18:00-03');
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    values ('05000000-0000-4000-8000-000000000160', 'bb000000-0000-4000-8000-000000000002', 'dia');
    perform pg_temp.em_uso_056();
    -- (o piso, 40%: com 0,56 a OS ainda cabe na semana de 02/11)
    update public.agenda_aprendizado set em_uso = 0.40, calculado = 0.40 where item = 'capacidade_dono' and chave = 'dono';
    r := pg_temp.propor('semana');
    select string_agg(m #>> '{}', ' | ') into v_t
      from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'motivos') m
     where i ->> 'numero' = 'OS-00160' and i ->> 'reserva_de' = 'teto';
    v_res := pg_temp.ok(v_res, 'D8e (C1, item 14) a reserva por teto da OS que precisa de você, com 40% em uso, diz "não coube na sua parte da semana (40%)" (e não "na carga de 80%")',
      public._agenda_carga_da_pessoa(c_dono) = 0.40 and v_t = 'não coube na sua parte da semana (40%)', coalesce(v_t, '—'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
