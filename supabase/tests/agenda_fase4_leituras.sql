-- Prova das leituras da Agenda de Produção, Fase 4 (pacote P6): migration 20261027100600 — a espera de peça (os 3
-- componentes e o KPI "dias da aprovação até a compra"), o foco compras e o foco fornecedores da agenda_ver.
-- bancada: depende de 20261027100600
--
--   L0 portas: a view com security_invoker e sem anon; as funções novas para authenticated e service_role, nunca anon;
--      security definer só as duas leituras dos focos (compras e fornecedores); search_path fixo; tudo STABLE/IMMUTABLE
--   L1 a espera de peça (fixture-fase4, sex 30/10): o Flávio aprovado ter 22/09 (Brasília; o ::date de UTC daria 23/09),
--      comprado ter 13/10 (21 dias, 14 úteis), chegou qua 14/10 (1 dia útil), parado há 12 dias úteis; o Vanderlei sem
--      compra; o Nelson 9 dias; a view = a função no dia de agora; a mediana dos 90 dias (15) = a da agenda_saude; a OC ligada
--      à linha dá o dia da compra (a cancelada não); o início pelo check-in e pelo meio-dia cumprido; a concluída nos
--      últimos 180 dias entra (a de antes, não)
--   L2 os textos (a amostra da spec §6.5, conferida contra o que o banco devolve, byte a byte): o foco compras (as notas sem
--      a palavra do dono, o tempo até comprar, a pergunta ao fornecedor em teste, o detector em teste), com a OS (Flávio,
--      Vanderlei, Nelson depois do *grava* da nota), o foco fornecedores; a pergunta ao fornecedor em ligado (recusada sem
--      conversa, saiu, na fila, não saiu); o detector e o fornecedor desligados não aparecem
--   L3 os focos novos pela agenda_ver (rota compras, compras_os, fornecedores; a OS concluída também); o foco que não existe
--      lança 22023 citando os 17; desligada = "a agenda de produção está desligada"
--   L4 determinismo: duas leituras seguidas = o mesmo texto (md5)
--   L5 quem vê: o técnico recebe 42501 nas leituras novas e não vê nada na view; o administrador com login lê o mesmo que o
--      service_role; anon sem privilégio
--   L6 a cópia de agenda_ver só muda nos blocos "-- FASE 4:" (× 20261026100500; fora deles só saem as 5 linhas da
--      conferência do foco)
--   L7 o teto (texto_max): cabe; primeiro sai o detector e o parado no cliente, depois os serviços do fim ("• e mais N"),
--      nunca o meio de uma linha
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase4_leituras.sql
--   Seguro em produção: tudo termina em ROLLBACK. L1–L5 e L7 rodam só na bancada (fixture-fase4; fora dela, PULADO); L6 só
--   com a migration antiga como texto.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

-- Texto igual ao esperado: o detalhe mostra o que veio (só quando difere).
create function pg_temp.igual(p_res jsonb, p_nome text, p_veio text, p_esperado text) returns jsonb
language sql immutable as $f$
  select pg_temp.ok(p_res, p_nome, p_veio is not distinct from p_esperado,
                    case when p_veio is distinct from p_esperado then coalesce(p_veio, '(nulo)') end)
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
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

-- O bloco "create or replace function public.<nome>(…)" de uma migration: o corpo (entre "as $function$" e "$function$;").
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'as $function$\n' in v) + length(E'as $function$'));
  return left(v, position(E'\n$function$;' in v));
end $f$;

-- O corpo sem os blocos "-- FASE 4: … -- FASE 4: fim" (linhas).
create function pg_temp.sem_fase4(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 4:' and l !~ '^\s*-- FASE 4: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 4: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- A agenda_ver do dono pelo WhatsApp (service_role, sem login), sex 30/10.
create function pg_temp.ver(p_foco text, p_os text default null, p_hoje date default date '2026-10-30') returns jsonb
language sql as $f$
  select public.agenda_ver('aa000000-0000-4000-8000-000000000001', null, null, p_foco, p_os, null, false, p_hoje)
$f$;
create function pg_temp.txt(p_foco text, p_os text default null) returns text language sql as $f$
  select pg_temp.ver(p_foco, p_os) ->> 'texto'
$f$;
-- A linha da espera de uma OS (pelo número), sex 30/10.
create function pg_temp.esp(p_numero text) returns jsonb language sql stable as $f$
  select to_jsonb(x) from public._agenda_espera_linhas(date '2026-10-30') x where x.numero = p_numero
$f$;

-- O estado das leituras (fixture-fase4, sex 30/10): a leitura ligada; o material, o detector e o fornecedor em sombra; a
-- rodada do material de qua 28/10 10:00 (o 2º terço do painel do Nelson: a pergunta à AliExpress, em teste) e a de sex 30/10
-- 09:00 (as perguntas das notas, em teste), depois de as duas notas do e-mail virarem remessa (o email-imap: a da Kamell
-- chegou ter 27/10, a da Correa qui 29/10).
create function pg_temp.estado() returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.fase4');
  update public.agenda_config set modo_leitura = 'ligado', modo_material = 'sombra', modo_detector = 'sombra',
                                  modo_fornecedor = 'sombra' where id;
  perform public.agenda_material_vigiar(date '2026-10-28', timestamptz '2026-10-28 10:00-03');
  perform public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e1', date '2026-10-27');
  perform public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e2', date '2026-10-29');
  perform public.agenda_material_vigiar(date '2026-10-30', timestamptz '2026-10-30 09:00-03');
end $f$;

-- ── L0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $l0$
declare
  v_res jsonb := '[]'::jsonb;
  f text;
  v_ruins text := '';
  v_leitura text[] := array[
    'public._agenda_espera_linhas(date)', 'public._agenda_dias_depois(integer, text)', 'public._agenda_espera_texto(jsonb, date)',
    'public.agenda_espera_de_peca(uuid, date)', 'public._agenda_compras_da_os(jsonb, jsonb, date)',
    'public._agenda_fornecedor_frase(uuid, date)', 'public._agenda_ver_compras(uuid, date)',
    'public._agenda_ver_fornecedores(date)', 'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)'];
begin
  v_res := pg_temp.ok(v_res, 'L0a a view: security_invoker ligado; authenticated e service_role leem; anon não',
    (select coalesce(array_to_string(c.reloptions, ','), '') like '%security_invoker=on%' from pg_class c
      where c.oid = 'public.v_agenda_espera_de_peca'::regclass)
    and has_table_privilege('authenticated', 'public.v_agenda_espera_de_peca', 'select')
    and has_table_privilege('service_role', 'public.v_agenda_espera_de_peca', 'select')
    and not has_table_privilege('anon', 'public.v_agenda_espera_de_peca', 'select'));
  foreach f in array v_leitura loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'L0b as leituras novas e a agenda_ver: authenticated e service_role, nunca anon', v_ruins = '', nullif(v_ruins, ''));
  v_ruins := '';
  foreach f in array v_leitura loop
    if (select p.prosecdef from pg_proc p where p.oid = f::regprocedure)
       <> (f in ('public._agenda_ver_compras(uuid, date)', 'public._agenda_ver_fornecedores(date)')) then
      v_ruins := v_ruins || 'definer: ' || f || ' ';
    end if;
    if coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = f::regprocedure), '') not like '%search_path=%' then
      v_ruins := v_ruins || 'sem search_path: ' || f || ' ';
    end if;
    if (select p.provolatile from pg_proc p where p.oid = f::regprocedure) not in ('s', 'i') then
      v_ruins := v_ruins || 'grava: ' || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'L0c security definer só as leituras dos focos compras e fornecedores; search_path fixo; nada grava (STABLE/IMMUTABLE)',
    v_ruins = '', nullif(v_ruins, ''));
  perform pg_temp.gravar(v_res);
end
$l0$;

-- ── L1. A espera de peça ────────────────────────────────────────────────────────────────────────────────
do $l1$
declare
  v_res jsonb := '[]'::jsonb;
  c_fla constant uuid := '05000000-0000-4000-8000-000000000104';
  c_nel constant uuid := '05000000-0000-4000-8000-000000000112';
  e jsonb;
  r jsonb;
  v_oc uuid;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('L1 a espera de peça (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.estado();
    e := pg_temp.esp('OS-00104');
    v_res := pg_temp.ok(v_res, 'L1a Flávio: aprovada ter 22/09 (Brasília; o ::date de UTC daria qua 23/09), comprado ter 13/10 = 21 dias (14 úteis); chegou qua 14/10 = 1 dia útil; parado há 12 dias úteis (16 corridos), sem início',
      e ->> 'aprovada_em' = '2026-09-22'
      and (select (so.converted_to_os_at)::date from public.service_orders so where so.id = c_fla) = date '2026-09-23'
      and e ->> 'primeira_compra' = '2026-10-13' and e ->> 'ultima_compra' = '2026-10-13'
      and (e ->> 'dias_ate_comprar')::int = 21 and (e ->> 'du_ate_comprar')::int = 14
      and e ->> 'ultima_chegada' = '2026-10-14' and (e ->> 'dias_do_fornecedor')::int = 1 and (e ->> 'du_do_fornecedor')::int = 1
      and (e ->> 'dias_parada')::int = 16 and (e ->> 'du_parada')::int = 12 and e ->> 'inicio' is null
      and (e ->> 'material_na_mao')::boolean and (e ->> 'linhas')::int = 1 and (e ->> 'na_carteira')::boolean, e::text);
    e := pg_temp.esp('OS-00069');
    r := pg_temp.esp('OS-00112');
    v_res := pg_temp.ok(v_res, 'L1b Vanderlei: 4 linhas, nenhuma comprada (sem os componentes); Nelson: o painel comprado qui 15/10 = 9 dias, 3 sem compra, não chegou',
      e ->> 'primeira_compra' is null and (e ->> 'linhas')::int = 4 and (e ->> 'linhas_sem_compra')::int = 4
      and e ->> 'dias_ate_comprar' is null and e ->> 'dias_parada' is null and not (e ->> 'material_na_mao')::boolean
      and r ->> 'primeira_compra' = '2026-10-15' and (r ->> 'dias_ate_comprar')::int = 9 and (r ->> 'du_ate_comprar')::int = 6
      and (r ->> 'linhas_sem_compra')::int = 3 and r ->> 'dias_do_fornecedor' is null and r ->> 'dias_parada' is null,
      concat_ws(' | ', e, r));
    perform set_config('agenda.hoje', '2026-10-30', true);
    v_res := pg_temp.ok(v_res, 'L1c a view é a função no dia de agora (agenda.hoje): as mesmas linhas, sem a descrição',
      (select jsonb_agg(to_jsonb(v) order by v.numero) from public.v_agenda_espera_de_peca v)
      = (select jsonb_agg(to_jsonb(x) - 'linha_unica' order by x.numero) from public._agenda_espera_linhas(date '2026-10-30') x)
      and (select count(*) from public.v_agenda_espera_de_peca) = 3, null);
    perform set_config('agenda.hoje', '', true);
    r := public.agenda_espera_de_peca(null, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'L1d a mediana dos aprovados nos últimos 90 dias (Flávio 21, Nelson 9; o Vanderlei é de 93 dias atrás) = 15 = a da agenda_saude',
      (r ->> 'mediana_ate_comprar_90d')::numeric = 15
      and (public.agenda_saude(date '2026-10-30', timestamptz '2026-10-30 10:00-03') #>> '{material,espera,mediana_ate_comprar_90d}')::numeric = 15
      and jsonb_array_length(r -> 'os') = 3, r ->> 'mediana_ate_comprar_90d');

    -- a OC ligada à linha (P2): o KIT do Nelson sem comprado_em ganha o dia da OC; a OC cancelada não conta
    begin
      insert into public.purchase_orders (po_number, status, supplier_id, service_order_id, created_at)
      values ('OC-TESTE-AG4L-1', 'sent', 'dd000000-0000-4000-8000-000000000001', c_nel, timestamptz '2026-10-12 23:30-03')
      returning id into v_oc;
      insert into public.purchase_order_items (purchase_order_id, description, quantity, unit_cost, service_order_part_id)
      values (v_oc, 'KIT cabos (AG4L)', 1, 10, md5('peca:112:1')::uuid);
      e := pg_temp.esp('OS-00112');
      v_res := pg_temp.ok(v_res, 'L1e a OC ligada à linha (criada seg 12/10 23:30 de Brasília) é a 1ª compra do Nelson: 6 dias; a OC cancelada não conta',
        e ->> 'primeira_compra' = '2026-10-12' and (e ->> 'dias_ate_comprar')::int = 6 and (e ->> 'linhas_sem_compra')::int = 2, e::text);
      update public.purchase_orders set status = 'cancelled' where id = v_oc;
      e := pg_temp.esp('OS-00112');
      v_res := pg_temp.ok(v_res, 'L1f cancelada a OC, volta a 1ª compra de qui 15/10 (9 dias)',
        e ->> 'primeira_compra' = '2026-10-15' and (e ->> 'linhas_sem_compra')::int = 3, e::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- o início: o check-in (Brasília) e, sem ele, o 1º meio-dia do plano cumprido
    begin
      update public.service_orders set check_in_at = timestamptz '2026-10-29 08:10-03' where id = c_fla;
      e := pg_temp.esp('OS-00104');
      v_res := pg_temp.ok(v_res, 'L1g com o check-in de qui 29/10: começou 11 dias úteis depois de chegar (15 corridos), e a frase diz',
        e ->> 'inicio' = '2026-10-29' and (e ->> 'du_parada')::int = 11 and (e ->> 'dias_parada')::int = 15
        and public._agenda_espera_texto(e, date '2026-10-30') like '%; começou qui 29/10 (11 dias úteis depois de chegar).', e::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- (o plano publicado da fixture é de 03 a 06/11; a alocação publicada não muda: um meio-dia novo, cumprido, ter 27/10)
      perform set_config('agenda.hoje', '2026-10-30', true);
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, periodo, estado, origem, resultado, resultado_via)
      values (c_fla, 'bb000000-0000-4000-8000-000000000002', date '2026-10-27', 'manha',
              tstzrange(timestamptz '2026-10-27 08:00-03', timestamptz '2026-10-27 12:00-03'), 'publicada', 'dono', 'cumprido', 'sistema');
      perform set_config('agenda.hoje', '', true);
      e := pg_temp.esp('OS-00104');
      v_res := pg_temp.ok(v_res, 'L1h sem check-in, o 1º meio-dia cumprido até hoje (ter 27/10) é o início: 9 dias úteis depois de chegar',
        e ->> 'inicio' = '2026-10-27' and (e ->> 'du_parada')::int = 9, e::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- a concluída: com saída nos últimos 180 dias entra (fora da carteira); com saída antes, não
    begin
      update public.service_orders set status = 'completed', check_out_at = timestamptz '2026-10-29 17:00-03' where id = c_fla;
      e := pg_temp.esp('OS-00104');
      v_res := pg_temp.ok(v_res, 'L1i a concluída com saída qui 29/10 entra (na_carteira false; os componentes iguais); a frase não diz "ainda não começou"',
        e is not null and not (e ->> 'na_carteira')::boolean and (e ->> 'dias_ate_comprar')::int = 21
        and public._agenda_espera_texto(e, date '2026-10-30') not like '%ainda não começou%', coalesce(e::text, 'null'));
      update public.service_orders set check_out_at = timestamptz '2026-05-02 17:00-03' where id = c_fla;
      v_res := pg_temp.ok(v_res, 'L1j a concluída com saída há mais de 180 dias fica de fora', pg_temp.esp('OS-00104') is null);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$l1$;

-- ── L2, L3, L4, L5, L7. Os textos, os focos, o determinismo, quem vê e o teto ───────────────────────────
do $l2$
declare
  v_res jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec   constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_ali   constant uuid := 'dd000000-0000-4000-8000-000000000005';
  v_compras  text;
  v_forn     text;
  v_t        text;
  r jsonb;
  m public.agenda_fornecedor_mensagens;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('L2 os textos (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.estado();

    -- ── L2: os textos
    v_compras := pg_temp.txt('compras');
    v_res := pg_temp.igual(v_res, 'L2a foco compras (sex 30/10, em sombra): os serviços, o parado no cliente, as notas sem a palavra do dono, o tempo até comprar, a pergunta ao fornecedor em teste e o detector em teste',
      v_compras,
      E'Compras (sex 30/10):\n'
      || E'• Vanderlei (OS-00069): 4 itens a comprar, nada comprado desde a aprovação (qua 29/07, há 93 dias). Compre até sex 30/10 para começar ter 03/11.\n'
      || E'• Flávio (OS-00104): material na mão desde qua 14/10, parado há 12 dias úteis; começa ter 03/11.\n'
      || E'• Nelson (OS-00112): "Central de controle…" a comprar; "Painel Touch de…" chega qua 04/11 (você disse); 2 itens sem fornecedor: de quem e quando?\n'
      || E'Não conto 3 parados no cliente.\n'
      || E'Não sei de qual serviço são: nota 51038 da Kamell (seg 26/10) e nota 812 da Correa (qui 29/10). Me diga, ou se não são de serviço.\n'
      || E'Tempo até comprar: Vanderlei ainda não comprou (93 dias), Flávio 21 dias depois da aprovação e Nelson 9 dias. Mediana dos aprovados nos últimos 90 dias: 15 dias.\n'
      || E'Ao fornecedor (em teste): eu teria perguntado à Aliexpress, qua 28/10, se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11.\n'
      || 'Leitura das conversas (em teste): nenhuma mensagem de fornecedor com prazo em 14 dias.');
    v_res := pg_temp.ok(v_res, 'L2b o foco compras cabe no teto (texto_max) e não usa jargão (du, nível, remessa, sinal, proposta, OC sem número)',
      char_length(v_compras) <= (select texto_max from public.agenda_config)
      and v_compras !~* '\m(du|nível|nivel|remessa|sinal|proposta)\M' and v_compras !~ '\mOC\M(?!-)',
      char_length(v_compras)::text);
    v_res := pg_temp.igual(v_res, 'L2c foco compras com a OS (Flávio): os 3 componentes da espera',
      pg_temp.txt('compras', 'Flávio'),
      'Flávio (OS-00104): aprovada ter 22/09; "Compressor 12V de…" comprado ter 13/10 (21 dias depois); chegou qua 14/10 (1 dia útil depois da compra); ainda não começou: parado há 12 dias úteis com o material na mão.');
    v_res := pg_temp.igual(v_res, 'L2d foco compras com a OS (Vanderlei): nada comprado e o que falta, com o "compre até"',
      pg_temp.txt('compras', 'Vanderlei'),
      E'Vanderlei (OS-00069): aprovada qua 29/07; nada comprado ainda (93 dias desde a aprovação).\n'
      || '• Material: 4 itens a comprar, nada comprado desde a aprovação (qua 29/07, há 93 dias). Compre até sex 30/10 para começar ter 03/11.');
    v_forn := pg_temp.txt('fornecedores');
    -- (os principais na fixture: os de compra viva — a Premel e a Kamell das linhas da carteira, o Mateus da OC-00004, a
    -- AliExpress do painel comprado e a Correa da nota a caminho; nenhuma conta de material em 365 dias)
    v_res := pg_temp.igual(v_res, 'L2e foco fornecedores: você disse (nenhum), o meu chute pela cidade ou pelo nome, o que falta você dizer (a Kamell repetida, o Mateus sem cidade) e como responder',
      v_forn,
      E'Como eu conto a chegada do material dos fornecedores principais:\n'
      || E'Você disse: nenhum ainda.\n'
      || E'Meu chute (pela cidade ou pelo nome):\n'
      || E'• entrega local, 1 dia útil: Correa (Balneário Camboriú/SC) e Premel (Itajaí/SC).\n'
      || E'• outro estado, 4 dias úteis: Kamell (Vila Velha/ES).\n'
      || E'• importado, 20 dias corridos: Aliexpress.\n'
      || E'Falta você dizer:\n'
      || E'• Kamell: cadastrada 2 vezes (Vila Velha/ES e Itajaí/SC); conto pela de Vila Velha/ES. É a mesma?\n'
      || E'• Mateus: sem cidade no cadastro.\n'
      || 'Pode ser um áudio só: "a Correa eu pego no balcão", "a Premel chega em 3 dias úteis".');

    -- o que o dono disse do fornecedor (o *grava* do fornecedor_prazo) vai para "Você disse"
    begin
      perform public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Premel', 'balcao', null, null, null,
                                               'a Premel eu pego no balcão', date '2026-10-30');
      perform public.agenda_rascunho_gravar(c_admin, date '2026-10-30');
      v_t := pg_temp.txt('fornecedores');
      v_res := pg_temp.ok(v_res, 'L2f o que o dono disse (a Premel no balcão) vai para "Você disse" e sai do chute',
        v_t like E'%Você disse:\n• balcão, na mão no mesmo dia: Premel (Itajaí/SC).\nMeu chute (pela cidade ou pelo nome):\n• entrega local, 1 dia útil: Correa (Balneário Camboriú/SC).\n• outro estado, 4 dias úteis: Kamell (Vila Velha/ES).%', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- o *grava* da nota da Kamell para o Cerbo do Nelson: a linha diz a nota; a nota sai da lista das sem resposta
    begin
      perform public.agenda_rascunho_material(c_admin, 'whatsapp', 'Nelson', array['Cerbo'], 'a_caminho', null, null, null, false,
                                              'a nota da Kamell é do Nelson, o Cerbo', date '2026-10-30', 'a nota da Kamell');
      perform public.agenda_rascunho_gravar(c_admin, date '2026-10-30');
      v_t := pg_temp.txt('compras');
      v_res := pg_temp.ok(v_res, 'L2g depois do *grava* da nota: "Central de controle…" chega sex 30/10 (pela nota 51038 da Kamell); só a nota da Correa fica sem resposta',
        v_t like E'%• Nelson (OS-00112): "Central de controle…" chega sex 30/10 (pela nota 51038 da Kamell); "Painel Touch de…" chega qua 04/11 (você disse); 2 itens sem fornecedor: de quem e quando?\n%'
        and v_t like E'%\nNão sei de qual serviço é a nota 812 da Correa (qui 29/10): me diga, ou se não é de serviço.\n%', v_t);
      v_res := pg_temp.igual(v_res, 'L2h foco compras com a OS (Nelson): a 1ª e a última compra, o que vem pela nota, a pergunta ao fornecedor em teste',
        pg_temp.txt('compras', 'Nelson'),
        E'Nelson (OS-00112): aprovada ter 06/10; a 1ª compra qui 15/10 (9 dias depois), a última seg 26/10, 2 itens ainda sem compra.\n'
        || E'• Material: "Central de controle…" chega sex 30/10 (pela nota 51038 da Kamell); "Painel Touch de…" chega qua 04/11 (você disse); 2 itens sem fornecedor: de quem e quando?\n'
        || '• Ao fornecedor (em teste): eu teria perguntado à Aliexpress, qua 28/10, se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11.');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- a pergunta ao fornecedor em ligado: recusada (sem conversa), na fila, saiu, não saiu
    begin
      update public.agenda_config set modo_fornecedor = 'ligado' where id;
      -- (a mensagem em teste fica: o registro nunca se apaga; a de ligado tem outra chave)
      perform public.agenda_material_vigiar(date '2026-10-28', timestamptz '2026-10-28 10:05-03');
      select * into m from public.agenda_fornecedor_mensagens x where x.modo = 'ligado' order by x.criada_em desc limit 1;
      v_t := public._agenda_fornecedor_frase(m.id, date '2026-10-30');
      v_res := pg_temp.igual(v_res, 'L2i ligado, sem conversa com a AliExpress nos últimos 90 dias: "não perguntei … (sem conversa …)"',
        v_t, 'não perguntei à Aliexpress, qua 28/10, se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11 (sem conversa com a HBR nos últimos 90 dias)');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      update public.agenda_config set modo_fornecedor = 'ligado', fornecedor_conversa_dias = 0 where id;
      update public.suppliers set phone = '5547900000205', contact_name = 'Lia' where id = c_ali;
      perform public.agenda_material_vigiar(date '2026-10-28', timestamptz '2026-10-28 10:05-03');
      select * into m from public.agenda_fornecedor_mensagens x where x.modo = 'ligado' and x.estado = 'enfileirada' limit 1;
      v_res := pg_temp.igual(v_res, 'L2j ligado, na fila e o dia já passou: "a pergunta … ainda não saiu (…)"',
        public._agenda_fornecedor_frase(m.id, date '2026-10-30'),
        'a pergunta à Aliexpress de qua 28/10 ainda não saiu (se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11)');
      v_res := pg_temp.igual(v_res, 'L2k ligado, na fila e o dia não passou: "vou perguntar à …"',
        public._agenda_fornecedor_frase(m.id, date '2026-10-28'),
        'vou perguntar à Aliexpress, qua 28/10, se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11');
      update public.whatsapp_send_queue set status = 'sent', sent_at = timestamptz '2026-10-28 10:06-03' where id = m.fila_id;
      v_t := pg_temp.txt('compras');
      v_res := pg_temp.ok(v_res, 'L2l ligado, saiu: no foco compras "Ao fornecedor: perguntei à Aliexpress, qua 28/10, se …" (sem "em teste" na de ligado)',
        v_t like E'%\nAo fornecedor: perguntei à Aliexpress, qua 28/10, se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11.%', v_t);
      update public.whatsapp_send_queue set status = 'failed', sent_at = null where id = m.fila_id;
      v_res := pg_temp.igual(v_res, 'L2m ligado, falhou: "a pergunta … não saiu (…)"',
        public._agenda_fornecedor_frase(m.id, date '2026-10-30'),
        'a pergunta à Aliexpress de qua 28/10 não saiu (se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11)');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- desligados: o detector e a pergunta ao fornecedor não aparecem; em sombra sem pergunta na semana, a linha diz
    begin
      update public.agenda_config set modo_detector = 'desligado', modo_fornecedor = 'desligado' where id;
      v_t := pg_temp.txt('compras');
      v_res := pg_temp.ok(v_res, 'L2n o detector e o fornecedor desligados: sem a linha da leitura das conversas; a pergunta já registrada em teste continua aparecendo',
        v_t not like '%Leitura das conversas%' and v_t like '%Ao fornecedor (em teste): eu teria perguntado%', v_t);
      update public.agenda_config set modo_fornecedor = 'sombra' where id;
      v_t := (public._agenda_ver_compras(null, date '2026-11-20') ->> 'texto');
      v_res := pg_temp.ok(v_res, 'L2o em sombra, sem pergunta ao fornecedor na semana: "Ao fornecedor (em teste): nenhuma pergunta nesta semana."',
        v_t like '%Ao fornecedor (em teste): nenhuma pergunta nesta semana.%', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── L3: os focos pela agenda_ver
    v_res := pg_temp.ok(v_res, 'L3a rotas: compras, compras_os (com a OS) e fornecedores (com ou sem a OS)',
      pg_temp.ver('compras') ->> 'rota' = 'compras' and pg_temp.ver('compras', 'Flávio') ->> 'rota' = 'compras_os'
      and pg_temp.ver('fornecedores') ->> 'rota' = 'fornecedores' and pg_temp.ver('fornecedores', 'Nelson') ->> 'rota' = 'fornecedores'
      and pg_temp.ver('fornecedores', 'Nelson') ->> 'texto' = v_forn and (pg_temp.ver('compras') ->> 'ok')::boolean, null);
    begin
      update public.service_orders set status = 'completed', check_out_at = timestamptz '2026-10-29 17:00-03'
       where id = '05000000-0000-4000-8000-000000000104';
      r := pg_temp.ver('compras', 'OS-00104');
      v_res := pg_temp.ok(v_res, 'L3b a OS concluída (fora da carteira) também tem o foco compras: a espera dela, sem "ainda não começou"',
        r ->> 'rota' = 'compras_os' and r ->> 'texto' like 'Flávio (OS-00104): aprovada ter 22/09; "Compressor 12V de…" comprado ter 13/10 (21 dias depois); chegou qua 14/10 (1 dia útil depois da compra).',
        r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_t := pg_temp.como(null, 'service_role',
      $q$select public.agenda_ver(null, null, null, 'comprar', null, null, false, '2026-10-30') ->> 'texto'$q$);
    v_res := pg_temp.ok(v_res, 'L3c o foco que não existe lança 22023 e a mensagem cita os 17',
      v_t = 'erro 22023: agenda_ver: foco "comprar" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras ou fornecedores)', v_t);
    begin
      update public.agenda_config set modo_leitura = 'desligado' where id;
      r := pg_temp.ver('compras');
      v_res := pg_temp.ok(v_res, 'L3d com a leitura desligada, os focos novos dizem que a agenda está desligada (como os de antes)',
        r ->> 'rota' = 'desligada' and r ->> 'texto' = 'A agenda de produção está desligada agora.'
        and pg_temp.ver('fornecedores') ->> 'rota' = 'desligada', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── L4: determinismo
    v_res := pg_temp.ok(v_res, 'L4 duas leituras seguidas dão o mesmo texto (md5): compras, compras com a OS, fornecedores',
      md5(pg_temp.txt('compras')) = md5(pg_temp.txt('compras')) and md5(pg_temp.txt('compras')) = md5(v_compras)
      and md5(pg_temp.txt('compras', 'Nelson')) = md5(pg_temp.txt('compras', 'Nelson'))
      and md5(pg_temp.txt('fornecedores')) = md5(v_forn), null);

    -- ── L5: quem vê
    v_t := pg_temp.como(c_tec, 'authenticated', $q$select public._agenda_ver_compras(null, '2026-10-30') ->> 'texto'$q$);
    v_res := pg_temp.ok(v_res, 'L5a o técnico: o foco compras, o foco fornecedores e a espera de peça recusam (42501); a view não mostra nada',
      v_t like 'erro 42501:%'
      and pg_temp.como(c_tec, 'authenticated', $q$select public._agenda_ver_fornecedores('2026-10-30') ->> 'texto'$q$) like 'erro 42501:%'
      and pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_espera_de_peca(null, '2026-10-30')::text$q$) like 'erro 42501:%'
      and pg_temp.como(c_tec, 'authenticated', $q$select count(*)::text from public.v_agenda_espera_de_peca$q$) = '0', v_t);
    v_res := pg_temp.ok(v_res, 'L5b o administrador com login lê o mesmo que o service_role (o foco compras e o foco fornecedores)',
      pg_temp.como(c_admin, 'authenticated', $q$select public._agenda_ver_compras(null, '2026-10-30') ->> 'texto'$q$) = v_compras
      and pg_temp.como(c_admin, 'authenticated', $q$select public._agenda_ver_fornecedores('2026-10-30') ->> 'texto'$q$) = v_forn,
      pg_temp.como(c_admin, 'authenticated', $q$select public._agenda_ver_compras(null, '2026-10-30') ->> 'texto'$q$));
    v_res := pg_temp.ok(v_res, 'L5c anon: nem a view nem as leituras',
      pg_temp.como(null, 'anon', $q$select public._agenda_ver_compras(null, '2026-10-30') ->> 'texto'$q$) like 'erro 42501:%'
      and pg_temp.como(null, 'anon', $q$select count(*)::text from public.v_agenda_espera_de_peca$q$) like 'erro 42501:%', null);

    -- ── L7: o teto
    begin
      update public.agenda_config set texto_max = 400 where id;
      v_t := pg_temp.txt('compras');
      v_res := pg_temp.ok(v_res, 'L7a com texto_max 400: cabe; o cabeçalho fica; sai primeiro o detector e o parado no cliente; os serviços do fim saem com "• e mais N"',
        char_length(v_t) <= 400 and v_t like E'Compras (sex 30/10):\n%' and v_t not like '%Leitura das conversas%'
        and v_t not like '%parados no cliente%' and v_t ~ E'\n• e mais [0-9]+\n'
        and not exists (select 1 from regexp_split_to_table(v_t, E'\n') l where l like '%…' and l not like '%"%'), v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      update public.agenda_config set texto_max = 750 where id;
      v_t := pg_temp.txt('compras');
      v_res := pg_temp.ok(v_res, 'L7b com texto_max 750: saem o detector e o parado no cliente, depois o serviço do fim ("• e mais 1"); as notas, o tempo e a pergunta ao fornecedor ficam',
        char_length(v_t) <= 750 and v_t like '%• Vanderlei (OS-00069)%' and v_t like '%• Flávio (OS-00104)%'
        and v_t not like '%• Nelson (OS-00112)%' and v_t like E'%\n• e mais 1\n%' and v_t not like '%Leitura das conversas%'
        and v_t not like '%parados no cliente%' and v_t like '%Não sei de qual serviço são%' and v_t like '%Tempo até comprar%'
        and v_t like '%Ao fornecedor (em teste)%', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$l2$;

-- ── L6. A cópia de agenda_ver só muda nos blocos "-- FASE 4:" (× 20261026100500) ────────────────────────
do $l6$
declare
  v_mig text := coalesce(current_setting('agenda_teste.mig_acompanhamento_fase3', true), '');
  v_velho text[];
  v_novo text[];
  -- as 5 linhas da conferência do foco que saem (entram ampliadas no 1º bloco)
  v_rem constant text[] := array[
    '  if v_foco not in (''tudo'', ''livre'', ''o_que_fazer'', ''riscos'', ''material'', ''atrasos'', ''aprontar'', ''decisoes'', ''mudancas'', ''plano'',',
    '                    ''ppc'', ''diarias'', ''marcos'', ''comissao'', ''equipe'') then',
    '    raise exception ''agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao ou equipe)'', p_foco',
    '      using errcode = ''22023'';',
    '  end if;'];
  v_src text := (select p.prosrc from pg_proc p where p.oid = 'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)'::regprocedure);
  v_saiu int := 0;
  i int;
begin
  if v_mig = '' then
    insert into _resultado values ('L6 a cópia de agenda_ver', true, 'PULADO: sem agenda_teste.mig_acompanhamento_fase3 (rode pela bancada)');
    return;
  end if;
  v_velho := string_to_array(pg_temp.corpo(v_mig, 'agenda_ver'), E'\n');
  -- tira as 5 linhas, cada uma uma vez, na ordem (a 1ª ocorrência de cada a partir da anterior)
  for i in 1 .. 5 loop
    if array_position(v_velho, v_rem[i]) is not null then
      v_velho := v_velho[1:array_position(v_velho, v_rem[i]) - 1] || v_velho[array_position(v_velho, v_rem[i]) + 1:];
      v_saiu := v_saiu + 1;
    end if;
  end loop;
  v_novo := pg_temp.sem_fase4(v_src);
  insert into _resultado values ('L6 a cópia de agenda_ver só muda nos blocos "-- FASE 4:" (3 blocos) e nas 5 linhas da conferência do foco (× 20261026100500)',
    v_saiu = 5 and v_novo = v_velho
    and (select count(*) from regexp_matches(v_src, '-- FASE 4: fim', 'g')) = 3,
    format('saíram %s; linhas %s × %s', v_saiu, array_length(v_novo, 1), array_length(v_velho, 1)));
end
$l6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
