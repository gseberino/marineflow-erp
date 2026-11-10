-- Prova das compras da Agenda de Produção, Fase 7e (pacote P6; migration 20261111100500; spec-fase7e §5.5, §8.3 e o bloco R7: R7.5-15, R7.5-16, R7.6, R7.8, R7.12, R7.13).
-- bancada: depende de 20261111100500
--
--   C0  as funções: portas, tipo; o que a migration não recria nem cria (sem _agenda_folga_compra_du, R7.5-16)
--   C1  os passos da rodada: o tempo de compra (padrão 1: tempo 2; o maior de cada OS; janela, n mínimo, teto), a folga (só medida), a peça sem fornecedor (conta 7, só medida; a compra é a entrega)
--   C2  o fornecedor: Correa em desligado × sombra × ligado × ligado com o freio; a compra antes da nota da mesma entrega; a previsão de antes da compra fora do atraso da Kamell (só em ligado)
--   C2t a frase do prazo medido e o foco fornecedores dizem o que foi medido: 5 compras e 0 notas, compras e notas juntas, só notas (o texto de antes)
--   C3  os_prontidao: byte a byte em sombra (OS sem linha é o caso comum); com o freio; em ligado, o "compre até" 1 dia útil antes com o tempo 2; a marcação vale; a sombra não chama nada novo (R7.8)
--   C3b _agenda_gestor_compra_conta: as 3 contas, o v_mesma estável com o marcado, o mesmo número da prontidão, e o que grava
--   C4  o publicado não muda: a OS marcada com 2 guarda 2 quando o medido vira 3 (só o tempo: a folga fica sem leitor)
--   C5  as cópias: tirados os blocos do P6, o corpo é o da origem
--   C6  o "Como eu conto" diz o número que vale; os textos do "Fornecedor pela compra" (achado 152): nunca "nota" sem nota
--
-- ═══ COMO RODAR ═══  Na bancada: node scripts/bancada-agenda/rodar.mjs. Em produção, só DEPOIS de aplicar a migration, com o OK: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_compras.sql
--   Tudo dentro de begin/rollback. O que usa fixture só roda na bancada (fora dela sai PULADO). Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- ── C0. As funções (sem fixture) ──────────────────────────────────────────────────────────────────
create temp table _f7e_p6 (f text primary key) on commit drop;
insert into _f7e_p6 values ('public._agenda_aprender_tempo_compra(date, timestamptz)'), ('public._agenda_aprender_folga_compra(date, timestamptz)'), ('public._agenda_aprender_prazo_sem_fornecedor(date, timestamptz)');

insert into _resultado
select 'C0a os 3 passos existem, volatile, com search_path fixo, invoker; sem porta para ninguém (nem service_role, anon, authenticated)',
       count(*) = 3 and bool_and(p.provolatile = 'v' and not p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))
       and bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(p.oid::regprocedure::text, ', ') filter (where has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))
  from _f7e_p6 x join pg_proc p on p.oid = x.f::regprocedure;

insert into _resultado
select 'C0b sem _agenda_folga_compra_du (R7.5-16: sem leitor nesta etapa)', not exists (select 1 from pg_proc where proname = '_agenda_folga_compra_du' and pronamespace = 'public'::regnamespace), null;

insert into _resultado
select 'C0c as recriadas mantêm as portas: os_prontidao para authenticated; _agenda_gestor_compra_conta e _agenda_ver_gestor sem porta para anon',
       has_function_privilege('authenticated', 'public.os_prontidao(uuid, date)', 'execute')
       and not has_function_privilege('anon', 'public.os_prontidao(uuid, date)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_gestor_compra_conta(uuid, date)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_ver_gestor(date)', 'execute'), null;

-- ── A fixture e os ajudantes ──────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    execute current_setting('agenda_teste.fase7e');
    -- Só as OS desta prova contam nas medidas (as outras fixtures saem do caminho, como no teste do P2)
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00'
     where service_order_number not like 'OS-7E%' and service_order_number <> 'OS-E0' and merged_into_id is null;
    perform set_config('marineflow.agrupar_orcamentos', '', true);
  end if;
end
$carga$;

create function pg_temp.fx() returns boolean language sql stable as $f$ select coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' $f$;
create function pg_temp.adm() returns uuid language sql stable as $f$ select id from public.app_users where role = 'admin' and active order by id limit 1 $f$;

-- Uma OS aberta (o molde do teste do P3)
create function pg_temp.aberta(p_n int, p_mo numeric default 3820) returns uuid language plpgsql as $f$
declare
  v_os uuid := md5('e7e:p6:' || p_n)::uuid;
begin
  perform set_config('agenda.porta', 'on', true);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, 'OS-7EC' || p_n, 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'approved', 'approved', 'repair',
          timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', p_mo);
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, 'Instalação de inversor e baterias', 'visit', 1, p_mo, p_mo, timestamptz '2026-12-01 10:00-03');
  perform set_config('agenda.porta', 'off', true);
  return v_os;
end $f$;

-- Uma linha de material em falta, na forma real de produção (fonte nula, crítica, sem fornecedor)
create function pg_temp.falta(p_n int, p_os uuid) returns uuid language plpgsql as $f$
declare
  v_l uuid := md5('e7e:p6:linha:' || p_n)::uuid;
begin
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
  values (v_l, p_os, 'dono', 'Inversor ' || p_n, 1, 0, true, 'falta', null, pg_temp.adm());
  return v_l;
end $f$;

-- Uma medida de compra pronta (o que agenda_medir_compra grava; a forma real dela vem do replay e do teste do P2)
create function pg_temp.medida(p_n int, p_os uuid, p_forn uuid default null, p_entrega text default null, p_aprov date default date '2026-12-01', p_comp date default date '2026-12-04',
                               p_cheg date default null, p_tempo int default null, p_prazo int default null, p_vt boolean default false, p_vp boolean default false, p_vf boolean default false,
                               p_atraso int default null, p_cumpriu boolean default null, p_sem boolean default false, p_prev date default null) returns uuid language plpgsql as $f$
declare
  v_l uuid := md5('e7e:p6:m:' || p_n)::uuid;
begin
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte, atualizado_por)
  values (v_l, p_os, 'dono', 'Peça ' || p_n, 1, 0, true, 'comprado', null, pg_temp.adm());
  insert into public.agenda_medidas_compra (os_material_id, service_order_id, fornecedor_id, sem_fornecedor, entrega, aprovada_em, precisou_em, marcada_em, primeiro_dia, comprado_em, comprado_fonte,
                                            chegou_em, previsao_original_em, tempo_compra_du, prazo_real_du, atraso_chegada_du, primeiro_dia_cumprido, valida_tempo, valida_prazo, valida_folga, medida_em)
  values (v_l, p_os, p_forn, p_sem, coalesce(p_entrega, 'linha:' || v_l), p_aprov, p_aprov,
          case when p_vf then date '2026-12-10' end, case when p_vf then date '2026-12-20' end,
          p_comp, 'dono', p_cheg, p_prev, p_tempo, p_prazo, p_atraso, p_cumpriu, p_vt, p_vp, p_vf, timestamptz '2027-01-07 10:00-03');
  return v_l;
end $f$;

create function pg_temp.publica(p_os uuid, p_n int, p_de date default date '2027-02-08') returns void language plpgsql as $f$
declare
  v_d date := p_de;
  v_t text := 'manha';
  k   int;
begin
  for k in 1 .. p_n loop
    while not public.agenda_dia_util(v_d) loop v_d := v_d + 1; end loop;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (p_os, 'e7e00000-0000-4000-8000-00000000aa02', v_d, v_t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-07 10:00-03');
    if v_t = 'manha' then v_t := 'tarde'; else v_t := 'manha'; v_d := v_d + 1; end if;
  end loop;
end $f$;

-- O modo do tempo de compra e o freio (aprendizado sempre ligado; o gestor com as regras todas e o freio pedido)
create function pg_temp.modo(p_modo text, p_freio boolean) returns void language sql as $f$
  update public.agenda_config
     set modo_tempo_compra = p_modo, modo_aprendizado = 'ligado', gestor_so_propor = p_freio, modo_marcar_sozinho = 'ligado', modo_compre_ate = 'ligado', fornecedor_n_min = 3,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}',
         aprendizado_ligados = (select array(select distinct unnest(aprendizado_ligados || array['fornecedor'])))
   where id
$f$;
-- O tempo de compra medido em uso, como o gravador deixaria
create function pg_temp.em_uso(p_du numeric) returns void language sql as $f$
  insert into public.agenda_aprendizado (item, chave, nivel, padrao, n, n_min, calculado, em_uso, em_uso_desde, estado, calculado_em)
  values ('tempo_compra', 'todas', 'geral', 1, 4, 3, p_du, p_du, timestamptz '2027-01-06 16:00-03', 'em_uso', timestamptz '2027-01-06 16:00-03')
  on conflict (item, chave) do update set em_uso = excluded.em_uso, calculado = excluded.calculado, estado = 'em_uso', em_uso_desde = excluded.em_uso_desde
$f$;
-- Tira as linhas do item, como se a rodada nunca tivesse passado (o registro não se apaga pela porta da frente)
create function pg_temp.apaga(p_itens text[]) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  delete from public.agenda_aprendizado where item = any (p_itens);
  set local session_replication_role = origin;
end $f$;
create function pg_temp.aprendido(p_item text, p_chave text) returns public.agenda_aprendizado language sql stable as $f$ select * from public.agenda_aprendizado where item = p_item and chave = p_chave $f$;
create function pg_temp.item1(p_pr jsonb) returns jsonb language sql immutable as $f$
  select x from jsonb_array_elements(p_pr #> '{material,itens}') with ordinality t(x, o) where x ->> 'situacao' = 'falta' order by o limit 1
$f$;

create function pg_temp.lines(p_t text) returns setof text language sql immutable as $f$ select regexp_split_to_table(p_t, E'\n') $f$;
-- Tira os blocos do P6 de um corpo (linha a linha, como o montador faz)
create function pg_temp.sem_p6(p_t text) returns text language plpgsql immutable as $f$
declare
  l text;
  fora text[] := '{}';
  dentro boolean := false;
begin
  for l in select pg_temp.lines(replace(p_t, E'\r\n', E'\n')) loop
    if not dentro and l ~ '^\s*-- (FASE 7e: \(7e P6|\(7e P6)' then dentro := true; continue; end if;
    if dentro and l ~ '^\s*-- (FASE 7e: fim|\(7e: fim\))' then dentro := false; continue; end if;
    if dentro then continue; end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;
-- O corpo de antes (o de hoje sem os blocos do P6), como função temporária, para o byte a byte
create function pg_temp.criar_antes() returns void language plpgsql as $f$
declare
  v_b text;
begin
  v_b := pg_temp.sem_p6((select prosrc from pg_proc where oid = 'public.os_prontidao(uuid, date)'::regprocedure));
  execute 'create or replace function pg_temp.antes_pro(p_so_id uuid, p_hoje date) returns jsonb language plpgsql stable set search_path to ''public'' as ' || quote_literal(v_b);
  v_b := pg_temp.sem_p6((select prosrc from pg_proc where oid = 'public._agenda_gestor_compra_conta(uuid, date)'::regprocedure));
  execute 'create or replace function pg_temp.antes_conta(p_os uuid, p_hoje date) returns jsonb language plpgsql stable set search_path to ''public'' as ' || quote_literal(v_b);
  v_b := pg_temp.sem_p6((select prosrc from pg_proc where oid = 'public._agenda_ver_gestor(date)'::regprocedure));
  execute 'create or replace function pg_temp.antes_ver(p_hoje date) returns jsonb language plpgsql stable set search_path to ''public'' as ' || quote_literal(v_b);
  v_b := pg_temp.sem_p6((select prosrc from pg_proc where oid = 'public._agenda_aprender_fornecedor(date, timestamptz)'::regprocedure));
  execute 'create or replace function pg_temp.antes_forn(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql volatile set search_path to ''public'' as ' || quote_literal(v_b);
end $f$;

-- ── C1. Os passos da rodada ───────────────────────────────────────────────────────────────────────
do $c1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  c_ag   constant timestamptz := timestamptz '2027-01-07 16:05-03';
  r      public.agenda_aprendizado;
  v      jsonb;
  v_os   uuid[];
  n      int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C1 passos', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    perform pg_temp.modo('ligado', false);
    v_os := array[pg_temp.aberta(1), pg_temp.aberta(2), pg_temp.aberta(3), pg_temp.aberta(4)];
    perform pg_temp.medida(1, v_os[1], p_tempo => 1, p_vt => true);
    perform pg_temp.medida(2, v_os[2], p_tempo => 3, p_vt => true);
    perform pg_temp.medida(3, v_os[3], p_tempo => 5, p_vt => true);
    perform pg_temp.medida(4, v_os[4], p_tempo => 6, p_vt => true);
    perform pg_temp.medida(5, v_os[4], p_tempo => 14, p_vt => true);   -- a mesma OS: vale a de 14
    perform pg_temp.medida(6, v_os[1], p_tempo => 30, p_vt => false);  -- inválida (balcão inferido): não entra
    v := public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1a tempo: 4 OS com 1, 3, 5 e 14 (a de 14 com 2 linhas: 6 e 14): o do meio 4, Z = 4/9, padrão 1 → 2; em uso (passo 3)',
      r.calculado = 2 and r.em_uso = 2 and r.n = 4 and r.estado = 'em_uso' and (r.detalhe ->> 'percentil')::numeric = 4 and r.padrao = 1 and (v ->> 'erros')::int = 0, to_jsonb(r)::text);
    v_res := pg_temp.ok(v_res, 'C1b a amostra são as OS, com o número (sem nome); a OS de 2 linhas conta a maior (14, não 6)', jsonb_array_length(r.amostra) = 4 and r.amostra -> 0 ? 'numero' and r.amostra::text not like '%Lia%' and exists (select 1 from jsonb_array_elements(r.amostra) x where (x ->> 'du')::numeric = 14) and not exists (select 1 from jsonb_array_elements(r.amostra) x where (x ->> 'du')::numeric = 6), r.amostra::text);
    v_res := pg_temp.ok(v_res, 'C1c a ação do "o que mudou" diz o número e o dia a mais',
      exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado' and a.texto = 'Medi o seu tempo da aprovação até a compra (4 OS): passei a contar 2 dias úteis no "compre até" (era 1), só nas OS que eu ainda não marquei: o pedido de compra sai 1 dia útil mais cedo. *desfaz aprendizado* volta.'),
      (select string_agg(a.texto, ' | ') from public.agenda_acoes a where a.tipo = 'aprendizado'));
    -- em sombra e com o freio (o gravador lê o cru: em uso com o freio; o leitor é que apaga)
    perform pg_temp.modo('sombra', false);
    perform pg_temp.apaga(array['tempo_compra']);
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1d em sombra: calcula 2, em teste, nada em uso', r.calculado = 2 and r.em_uso is null and r.estado = 'sombra', to_jsonb(r)::text);
    -- o padrão da credibilidade é o parâmetro de agora (3): 4 × 4/9 + 3 × 5/9 = 3,44 → 3
    update public.agenda_config set compra_interna_du = 3 where id;
    perform pg_temp.apaga(array['tempo_compra']);
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1d2 com compra_interna_du 3, o padrão puxa o calculado para 3 e é o padrão gravado', r.calculado = 3 and r.padrao = 3, to_jsonb(r)::text);
    update public.agenda_config set compra_interna_du = 1 where id;
    perform pg_temp.modo('ligado', true);
    perform pg_temp.apaga(array['tempo_compra']);
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1e com o freio o gravador segue (modo cru, R7.6): em uso 2, e soltar o freio não recomeça do padrão', r.em_uso = 2 and r.estado = 'em_uso', to_jsonb(r)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o n mínimo, a janela, o teto, sem nada, o guarda do nulo, a amostra máxima, o erro de uma OS
    perform pg_temp.modo('ligado', false);
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1f sem medida: a linha nasce medindo, n 0, nada calculado, e o texto diz "nenhuma OS medida ainda" (nunca "medi")',
      r.n = 0 and r.calculado is null and r.em_uso is null and r.estado = 'medindo'
      and public._agenda_aprendizado_texto('tempo_compra', 'foco_medindo', jsonb_build_object('n', 0, 'n_min', 3, 'padrao', 1)) = 'Seu tempo para comprar: nenhuma OS medida ainda (da aprovação até a compra); no "compre até" conto 1 dia útil (padrão).', to_jsonb(r)::text);
    v_os := array[pg_temp.aberta(5), pg_temp.aberta(6), pg_temp.aberta(7)];
    perform pg_temp.medida(10, v_os[1], p_tempo => 2, p_vt => true);
    perform pg_temp.medida(11, v_os[2], p_tempo => 2, p_vt => true);
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1g 2 OS (mínimo 3): medindo, sem em uso', r.n = 2 and r.estado = 'medindo' and r.em_uso is null, to_jsonb(r)::text);
    perform pg_temp.medida(12, v_os[3], p_tempo => 2, p_aprov => date '2025-11-01', p_vt => true);  -- fora da janela de 365 dias
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C1h a OS aprovada fora da janela não conta', (pg_temp.aprendido('tempo_compra', 'todas')).n = 2, null);
    perform pg_temp.medida(13, v_os[3], p_tempo => null, p_vt => true);   -- válida sem número: não conta como 0
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C1i o tempo nulo fica de fora (não conta como compra de 0 dias)', (pg_temp.aprendido('tempo_compra', 'todas')).n = 2, null);
    update public.agenda_medidas_compra set tempo_compra_du = 200, valida_tempo = true, versao = versao + 1,
           historico = historico || jsonb_build_array(jsonb_build_object('em', c_hoje, 'versao', versao, 'antes', '{}'::jsonb, 'depois', '{}'::jsonb))
     where os_material_id in (md5('e7e:p6:m:10')::uuid, md5('e7e:p6:m:11')::uuid, md5('e7e:p6:m:13')::uuid);
    update public.agenda_config set tempo_compra_max_du = 5, credibilidade_k = 1, modo_tempo_compra = 'sombra' where id;
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1j o teto: o calculado para em tempo_compra_max_du (5)', r.calculado = 5, to_jsonb(r)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- só as fator_amostra_max mais recentes entram (a mais antiga fica de fora: o percentil muda)
    perform pg_temp.modo('sombra', false);
    update public.agenda_config set fator_amostra_max = 6 where id;
    -- 6 OS recentes com 2 dias; as 4 mais antigas com 20: fora (se a ordem virasse, o do meio seria 20)
    for n in 1 .. 10 loop
      perform pg_temp.medida(13 + n, pg_temp.aberta(7 + n), p_tempo => case when n >= 7 then 20 else 2 end, p_aprov => date '2026-12-20' - (n * 5), p_vt => true);
    end loop;
    perform public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('tempo_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1k fator_amostra_max: só as 6 OS mais recentes entram (as 4 antigas, de 20, ficam de fora)', r.n = 6 and (r.detalhe ->> 'percentil')::numeric = 2, to_jsonb(r)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- A folga: 5 OS com atrasos 0, 0, 1, 2, 4 → P80 2,4, Z 5/10 → 1,2 → 2; 3 começaram no dia marcado
    perform pg_temp.modo('ligado', false);
    update public.agenda_config set modo_folga_compra = 'ligado' where id;
    v_os := array[pg_temp.aberta(21), pg_temp.aberta(22), pg_temp.aberta(23), pg_temp.aberta(24), pg_temp.aberta(25)];
    perform pg_temp.medida(21, v_os[1], p_cheg => date '2026-12-15', p_atraso => 0, p_vf => true, p_cumpriu => true);
    perform pg_temp.medida(22, v_os[2], p_cheg => date '2026-12-15', p_atraso => -1, p_vf => true, p_cumpriu => true);     -- chegou antes: conta 0
    perform pg_temp.medida(23, v_os[3], p_cheg => date '2026-12-15', p_atraso => 1, p_vf => true, p_cumpriu => true);
    perform pg_temp.medida(24, v_os[4], p_cheg => date '2026-12-15', p_atraso => 2, p_vf => true);
    perform pg_temp.medida(25, v_os[5], p_cheg => date '2026-12-15', p_atraso => 4, p_vf => true, p_cumpriu => false);
    perform public._agenda_aprender_folga_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('folga_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1l a folga: atrasos 0, 0 (chegou antes conta 0), 1, 2, 4: P80 2,4, Z 5/10 → 2; n 5; no prazo 2; maior 4; 3 começaram no dia',
      r.calculado = 2 and r.n = 5 and (r.detalhe ->> 'no_prazo')::int = 2 and (r.detalhe ->> 'maior')::numeric = 4 and (r.detalhe ->> 'comecaram_no_dia')::int = 3 and r.padrao = 0, to_jsonb(r)::text);
    v_res := pg_temp.ok(v_res, 'C1m a folga é só medida (R7.5-16): mesmo ligada, em teste, nada em uso', r.estado = 'sombra' and r.em_uso is null, to_jsonb(r)::text);
    perform pg_temp.medida(26, v_os[1], p_cheg => date '2026-12-20', p_atraso => 3, p_vf => true);   -- a mesma OS: vale o maior (3)
    perform pg_temp.medida(27, pg_temp.aberta(26), p_cheg => date '2026-12-15', p_atraso => null, p_vf => true);   -- atraso nulo: fora
    perform pg_temp.medida(28, pg_temp.aberta(27), p_cheg => date '2025-11-15', p_atraso => 9, p_vf => true);      -- fora da janela
    perform pg_temp.medida(29, pg_temp.aberta(28), p_cheg => date '2026-12-15', p_atraso => 9, p_vf => false);     -- não vale para a folga: fora
    perform pg_temp.medida(30, v_os[3], p_cheg => date '2026-12-15', p_atraso => 1, p_vf => true, p_cumpriu => false);  -- a OS que começou no dia conta, mesmo com outra linha sem cumprir (bool_or)
    perform public._agenda_aprender_folga_compra(c_hoje, c_ag);
    r := pg_temp.aprendido('folga_compra', 'todas');
    v_res := pg_temp.ok(v_res, 'C1n a mesma OS conta o maior; atraso nulo não entra como 0; fora da janela e linha inválida não entram; a OS que começou no dia conta com outra linha sem cumprir', r.n = 5 and (r.detalhe ->> 'no_prazo')::int = 1 and (r.detalhe ->> 'maior')::numeric = 4 and (r.detalhe ->> 'comecaram_no_dia')::int = 3, to_jsonb(r)::text);
    update public.agenda_config set folga_compra_max_du = 1, modo_folga_compra = 'sombra' where id;
    perform public._agenda_aprender_folga_compra(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C1o o teto: folga_compra_max_du (1)', (pg_temp.aprendido('folga_compra', 'todas')).calculado = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- A peça sem fornecedor: 3 compras com 2, 3 e 5 → P80 4,2 → 5; só medida; o padrão continua 7
    perform pg_temp.modo('ligado', false);
    v_os := array[pg_temp.aberta(31), pg_temp.aberta(32)];
    perform pg_temp.medida(31, v_os[1], p_entrega => 'oc:a', p_cheg => date '2026-12-15', p_prazo => 2, p_vp => true, p_sem => true);
    perform pg_temp.medida(32, v_os[1], p_entrega => 'oc:b', p_cheg => date '2026-12-15', p_prazo => 3, p_vp => true, p_sem => true);
    perform pg_temp.medida(33, v_os[2], p_entrega => 'oc:c', p_cheg => date '2026-12-15', p_prazo => 5, p_vp => true, p_sem => true);
    perform pg_temp.medida(34, v_os[2], p_entrega => 'oc:c', p_cheg => date '2026-12-15', p_prazo => 4, p_vp => true, p_sem => true);  -- a mesma compra (entrega): não conta 2 vezes
    perform pg_temp.medida(35, v_os[2], p_entrega => 'oc:d', p_cheg => date '2026-12-15', p_prazo => 30, p_vp => true, p_sem => false); -- com fornecedor: fora
    perform pg_temp.medida(36, v_os[2], p_entrega => 'oc:e', p_cheg => date '2026-12-15', p_prazo => 40, p_vp => false, p_sem => true);   -- inválida: fora
    perform public._agenda_aprender_prazo_sem_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('prazo_sem_fornecedor', 'todas');
    v_res := pg_temp.ok(v_res, 'C1p a peça sem fornecedor: 2, 3 e 5 → P80 4,2 → 5; 3 compras (2 linhas da mesma entrega contam 1; a com fornecedor fora); só medida, padrão 7',
      r.calculado = 5 and r.n = 3 and r.estado = 'sombra' and r.em_uso is null and r.padrao = 7, to_jsonb(r)::text);
    v_res := pg_temp.ok(v_res, 'C1q o texto da peça sem fornecedor diz 5 e conta 7',
      public._agenda_aprendizado_texto('prazo_sem_fornecedor', 'foco_sombra', jsonb_build_object('n', 3, 'calculado', 5, 'padrao', 7)) = 'Peças compradas sem fornecedor dito antes: chegaram em até 5 dias úteis depois da compra (3 compras); conto 7 dias úteis (o padrão é decisão sua).', null);
    update public.agenda_medidas_compra set prazo_real_du = 90, versao = versao + 1, historico = historico || jsonb_build_array(jsonb_build_object('em', c_hoje, 'versao', versao, 'antes', '{}'::jsonb, 'depois', '{}'::jsonb))
     where os_material_id = md5('e7e:p6:m:33')::uuid;
    update public.agenda_config set fornecedor_percentil = 0.95 where id;
    perform public._agenda_aprender_prazo_sem_fornecedor(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C1r o teto de 30 dias úteis', (pg_temp.aprendido('prazo_sem_fornecedor', 'todas')).calculado = 30, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- os erros vão ao log e o passo não derruba a rodada
    perform pg_temp.modo('ligado', false);
    perform set_config('agenda.hoje', c_hoje::text, true);
    create or replace function public._agenda_aprendizado_gravar_bak() returns void language sql as 'select 1';
    drop function public._agenda_aprendizado_gravar_bak();
    alter function public._agenda_percentil(numeric[], numeric) rename to _agenda_percentil_x;
    v := public._agenda_aprender_tempo_compra(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C1s o erro não sobe: erros 1, e a etiqueta em app_error_logs', (v ->> 'erros')::int = 1 and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:tempo_compra'), v::text);
    v := public._agenda_aprender_folga_compra(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C1t idem na folga', (v ->> 'erros')::int = 1 and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:folga_compra'), v::text);
    v := public._agenda_aprender_prazo_sem_fornecedor(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C1u idem na peça sem fornecedor', (v ->> 'erros')::int = 1 and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:prazo_sem_fornecedor'), v::text);
    alter function public._agenda_percentil_x(numeric[], numeric) rename to _agenda_percentil;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C2. O fornecedor ──────────────────────────────────────────────────────────────────────────────
create function pg_temp.fornecedor(p_nome text) returns uuid language plpgsql as $f$
declare
  v uuid := md5('e7e:p6:forn:' || p_nome)::uuid;
begin
  insert into public.suppliers (id, name, trade_name, city, state, active) values (v, p_nome, null, 'Itajaí', 'SC', true) on conflict (id) do nothing;
  return v;
end $f$;
-- Troca o detalhe da linha do prazo (só para variar a origem do número sem refazer as medidas)
create function pg_temp.detalhe_prazo(p_forn uuid, p_det jsonb) returns void language sql as $f$
  update public.agenda_aprendizado set detalhe = p_det where item = 'fornecedor_prazo' and chave = p_forn::text
$f$;
create function pg_temp.nota(p_n int, p_forn uuid, p_desp date, p_cheg date) returns uuid language plpgsql as $f$
declare
  v uuid := md5('e7e:p6:nota:' || p_n)::uuid;
begin
  insert into public.material_remessas (id, nfe_chave, numero, emitida_em, fornecedor_id, chegou_em, estado)
  values (v, lpad(p_n::text, 44, '7'), '99' || p_n, p_desp, p_forn, p_cheg, 'chegou');
  return v;
end $f$;

do $c2$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  c_ag   constant timestamptz := timestamptz '2027-01-07 16:05-03';
  r      public.agenda_aprendizado;
  r2     public.agenda_aprendizado;
  v      jsonb;
  v_corr uuid;
  v_kam  uuid;
  v_os   uuid[];
  v_n1   uuid;
  v_n2   uuid;
  v_l    uuid;
  v_mis  uuid;
  v_ter  uuid;
  v_pr   jsonb;
  v_k    jsonb;
  v_t    text;
  k      int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C2 fornecedor', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  perform pg_temp.criar_antes();
  begin
    v_corr := pg_temp.fornecedor('Correa');
    v_os := array[pg_temp.aberta(41), pg_temp.aberta(42), pg_temp.aberta(43)];
    perform pg_temp.medida(41, v_os[1], v_corr, 'oc:1', p_comp => date '2026-12-10', p_cheg => date '2026-12-11', p_prazo => 1, p_vp => true);
    perform pg_temp.medida(42, v_os[2], v_corr, 'oc:2', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 2, p_vp => true);
    perform pg_temp.medida(43, v_os[3], v_corr, 'oc:3', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 2, p_vp => true);
    perform pg_temp.medida(140, v_os[3], v_corr, 'oc:3', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 1, p_vp => true);   -- a mesma entrega: vale o maior prazo (2)
    perform pg_temp.medida(141, v_os[1], v_corr, 'oc:x', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 30, p_vp => false);  -- não vale: fora
    -- outra loja, com 1 compra só: não entra na conta da Correa
    perform pg_temp.medida(142, v_os[1], pg_temp.fornecedor('Outra'), 'oc:o', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 9, p_vp => true);
    -- só com compra fora da janela, e só com compra que não vale: não ganham linha
    perform pg_temp.medida(143, v_os[1], pg_temp.fornecedor('ForaJanela'), 'oc:f', p_comp => date '2025-11-10', p_cheg => date '2025-11-14', p_prazo => 2, p_vp => true);
    perform pg_temp.medida(144, v_os[1], pg_temp.fornecedor('SemValida'), 'oc:v', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 2, p_vp => false);
    -- o percentil para cima (1, 1, 3: P80 2,2 → 3) e o prazo negativo de data errada (o piso 0)
    perform pg_temp.medida(145, v_os[1], pg_temp.fornecedor('Ceil'), 'oc:c1', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 1, p_vp => true);
    perform pg_temp.medida(146, v_os[1], pg_temp.fornecedor('Ceil'), 'oc:c2', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 1, p_vp => true);
    perform pg_temp.medida(147, v_os[1], pg_temp.fornecedor('Ceil'), 'oc:c3', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 3, p_vp => true);
    perform pg_temp.medida(148, v_os[1], pg_temp.fornecedor('Neg'), 'oc:n1', p_comp => date '2026-12-10', p_cheg => date '2026-12-09', p_prazo => -1, p_vp => true);

    -- desligado: nem a linha
    perform pg_temp.modo('desligado', false);
    v := public._agenda_aprender_fornecedor(c_hoje, c_ag);
    v_res := pg_temp.ok(v_res, 'C2a desligado: nada novo (sem linha do fornecedor)', not exists (select 1 from public.agenda_aprendizado a where a.item = 'fornecedor_prazo' and a.chave = v_corr::text), v::text);

    -- sombra: a linha nasce medindo com o teria; o calculado de antes (nenhum)
    perform pg_temp.modo('sombra', false);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2b sombra: medindo, n 0, calculado nulo, e detalhe.teria = {n: 3, du: 2} (1, 2, 2 → P80 2)',
      r.estado = 'medindo' and r.n = 0 and r.calculado is null and r.em_uso is null and r.detalhe -> 'teria' = '{"n": 3, "du": 2}'::jsonb and not r.detalhe ? 'fonte', to_jsonb(r)::text);
    v_res := pg_temp.ok(v_res, 'C2c sombra: o texto do foco é o parêntese em teste, com a frase da §6.2',
      public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_medindo', jsonb_build_object('n', 0, 'n_min', 3, 'detalhe', r.detalhe)) = 'Correa: (em teste: com as compras registradas seriam 3 entregas, até 2 dias úteis depois da compra).', r.detalhe::text);

    v_res := pg_temp.ok(v_res, 'C2b3 o teria sobe para cima (Ceil: 1, 1, 3 → P80 2,2 → 3) e o prazo negativo de data errada fica em 0 (Neg)',
      (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('Ceil')::text)).detalhe -> 'teria' = '{"n": 3, "du": 3}'::jsonb
      and (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('Neg')::text)).detalhe -> 'teria' = '{"n": 1, "du": 0}'::jsonb,
      (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('Neg')::text)).detalhe::text);
    v_res := pg_temp.ok(v_res, 'C2b4 só com compra fora da janela, ou só com compra que não vale: não ganha linha',
      (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('ForaJanela')::text)).item is null and (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('SemValida')::text)).item is null, null);
    -- quem já tem linha vem pelo 3º ramo: em ligado, as compras entram (sem apagar a linha de antes)
    perform pg_temp.modo('ligado', false);
    v := public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2b5 cada fornecedor passa 1 vez por item (o ramo novo não duplica quem já tem linha)',
      (v ->> 'chaves')::int = (select count(*)::int from public.agenda_aprendizado a where a.item in ('fornecedor_atraso', 'fornecedor_prazo')),
      v::text);
    v_res := pg_temp.ok(v_res, 'C2b2 quem já tinha linha (só pela compra): ligado, n 3 e em uso 2, pelo ramo de quem já tem linha', r.n = 3 and r.calculado = 2 and r.em_uso = 2, to_jsonb(r)::text);
    -- ligado com o freio: como sombra
    perform pg_temp.modo('ligado', true);
    perform pg_temp.apaga(array['fornecedor_prazo']);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2d ligado com o freio (R7.6): como sombra, só o teria', r.estado = 'medindo' and r.n = 0 and r.detalhe ? 'teria' and not r.detalhe ? 'fonte', to_jsonb(r)::text);

    -- ligado: entra no valor e no n; em uso 2 (padrão 1, troca 1 ≤ 3)
    perform pg_temp.modo('ligado', false);
    perform pg_temp.apaga(array['fornecedor_prazo']);
    v := public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2e ligado: as 3 compras entram no n e no valor: em uso 2 (padrão 1); detalhe.fonte = compras; a amostra diz as compras; o teria some; a ação conta',
      (v ->> 'acoes')::int >= 1 and r.n = 3 and r.calculado = 2 and r.em_uso = 2 and r.estado = 'em_uso' and r.padrao = 1 and r.detalhe ->> 'fonte' = 'compras' and (r.detalhe ->> 'compras')::int = 3 and (r.detalhe ->> 'notas')::int = 0
      and not r.detalhe ? 'teria' and jsonb_array_length(r.amostra) = 3, to_jsonb(r)::text);
    v_res := pg_temp.ok(v_res, 'C2e2 a outra loja mede só a dela (n 1)', (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('Outra')::text)).n = 1, null);
    v_res := pg_temp.ok(v_res, 'C2e3 2 linhas da mesma entrega contam o maior prazo (oc:3 = 2, não 1)', exists (select 1 from jsonb_array_elements(r.amostra) x where x ->> 'entrega' = 'oc:3' and (x ->> 'du')::int = 2), r.amostra::text);
    v_res := pg_temp.ok(v_res, 'C2f ligado: a frase em uso da §6.2',
      public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_em_uso', jsonb_build_object('n', 3, 'em_uso', r.em_uso, 'padrao', r.padrao, 'desde', c_hoje, 'detalhe', r.detalhe)) = 'Correa: entrega em até 2 dias úteis depois da compra (3 compras medidas): é o que conto desde qui 07/01.', null);
    v_res := pg_temp.ok(v_res, 'C2g ligado: a ação não fala em nota',
      exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado' and a.texto like 'Medi as compras de Correa%' and a.texto not like '%nota%'),
      (select string_agg(a.texto, ' | ') from public.agenda_acoes a where a.tipo = 'aprendizado'));
    v_res := pg_temp.ok(v_res, 'C2h o prazo do fornecedor lê o que foi medido pela compra (o motor conta 2)', (public._agenda_prazo_do_fornecedor(v_corr) ->> 'du')::int = 2, public._agenda_prazo_do_fornecedor(v_corr)::text);
    -- desligado com a linha já lá: nem fonte, nem teria, nem a contagem pela compra
    perform pg_temp.modo('desligado', false);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2s desligado com a linha já lá: nem fonte nem teria, e a compra não conta (volta a medir)', r.n = 0 and not r.detalhe ? 'teria' and not r.detalhe ? 'fonte', to_jsonb(r)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a compra antes da nota da mesma entrega: a nota não conta de novo; a outra nota conta (só do despacho); em sombra o teria diz o que seria
    perform pg_temp.modo('ligado', false);
    v_corr := pg_temp.fornecedor('Correa');
    v_n1 := pg_temp.nota(1, v_corr, date '2026-12-10', date '2026-12-20');   -- 6 dias úteis, mas a compra da mesma entrega fica no lugar dela
    v_n2 := pg_temp.nota(2, v_corr, date '2026-12-10', date '2026-12-17');   -- 5 dias úteis, outra entrega
    v_os := array[pg_temp.aberta(44), pg_temp.aberta(45), pg_temp.aberta(46)];
    perform pg_temp.nota(4, pg_temp.fornecedor('SoNota0'), date '2026-12-10', date '2026-12-14');
    perform pg_temp.nota(5, pg_temp.fornecedor('SoNota3'), date '2026-12-10', date '2026-12-14');
    perform pg_temp.medida(44, v_os[1], v_corr, 'nota:' || v_n1, p_comp => date '2026-12-10', p_cheg => date '2026-12-11', p_prazo => 1, p_vp => true);
    perform pg_temp.medida(45, v_os[2], v_corr, 'oc:5', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 2, p_vp => true);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2i a mesma entrega não conta duas vezes: 2 compras + a nota da outra entrega = 3; o calculado (1, 2 e 5: P80 3,8 → 4) não vê os 6 da nota substituída',
      r.n = 3 and (r.detalhe ->> 'compras')::int = 2 and (r.detalhe ->> 'notas')::int = 1 and r.calculado = 4, to_jsonb(r)::text);
    -- só com nota, processados depois de quem tem compra (a ordem é pelo id): o detalhe não herda a fonte de quem veio antes
    v_res := pg_temp.ok(v_res, 'C2i2 só com nota, depois de um fornecedor com compra: sem fonte e sem teria',
      not (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('SoNota0')::text)).detalhe ? 'fonte'
      and not (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('SoNota3')::text)).detalhe ? 'fonte',
      (pg_temp.aprendido('fornecedor_prazo', pg_temp.fornecedor('SoNota3')::text)).detalhe::text);
    v_res := pg_temp.ok(v_res, 'C2j a frase com compras e notas diz as duas',
      public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_em_uso', jsonb_build_object('n', 3, 'em_uso', 2, 'padrao', 1, 'desde', c_hoje, 'detalhe', r.detalhe)) = 'Correa: entrega em até 2 dias úteis depois da compra (2 compras e 1 nota medidas): é o que conto desde qui 07/01.', null);
    -- sombra: com notas, a frase de sempre e o parêntese; o teria sem a nota substituída; o calculado sem as compras
    perform pg_temp.modo('sombra', false);
    perform pg_temp.apaga(array['fornecedor_prazo']);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2k sombra com notas: n 2, as 2 notas (6 e 2: P80 5,2 → 6) no calculado de antes; teria = 3 entregas (a nota substituída sai): 5, 1 e 2 → até 4',
      r.n = 2 and r.calculado = 6 and r.detalhe -> 'teria' = '{"n": 3, "du": 4}'::jsonb and not r.detalhe ? 'fonte', to_jsonb(r)::text);
    v_res := pg_temp.ok(v_res, 'C2l sombra com notas: a frase da Fase 6 + o parêntese',
      public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_medindo', jsonb_build_object('n', 2, 'n_min', 3, 'padrao', 1, 'detalhe', r.detalhe)) = 'Correa: 2 de 3 notas medidas da saída até a chegada; conto 1 dia útil (padrão). (em teste: com as compras registradas seriam 3 entregas, até 4 dias úteis depois da compra).',
      public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_medindo', jsonb_build_object('n', 2, 'n_min', 3, 'padrao', 1, 'detalhe', r.detalhe)));
    v_res := pg_temp.ok(v_res, 'C2m a ação e a pergunta nunca levam o parêntese em teste',
      public._agenda_aprendizado_texto('fornecedor_prazo', 'acao', jsonb_build_object('n', 2, 'calculado', 2, 'efetivo', 1, 'detalhe', r.detalhe)) not like '%em teste%', null);
    v_res := pg_temp.ok(v_res, 'C2n 1 entrega no teria sai no singular', public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_medindo', jsonb_build_object('n', 0, 'detalhe', jsonb_build_object('nome', 'Correa', 'teria', jsonb_build_object('n', 1, 'du', 1)))) = 'Correa: (em teste: com as compras registradas seria 1 entrega, até 1 dia útil depois da compra).', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a previsão de antes da compra fora do atraso (d6): só em ligado; em sombra, o de antes byte a byte; a linha de quem já tem linha (o 3º ramo)
    v_kam := pg_temp.fornecedor('Kamell');
    v_os := array[pg_temp.aberta(47), pg_temp.aberta(48)];
    perform pg_temp.medida(47, v_os[1], v_kam, 'linha:k1', p_comp => date '2026-11-12', p_cheg => date '2026-12-15', p_prazo => 3, p_prev => date '2026-11-10');
    update public.os_material set situacao = 'na_mao', chegou_em = date '2026-12-15', previsao_original = date '2026-12-01', previsao_original_fonte = 'fornecedor', fornecedor_id = v_kam, quantidade_na_mao = 1
     where id = md5('e7e:p6:m:47')::uuid;
    perform pg_temp.medida(48, v_os[2], v_kam, 'linha:k2', p_comp => date '2026-11-12', p_cheg => date '2026-12-05', p_prazo => 3, p_prev => date '2026-11-13');
    update public.os_material set situacao = 'na_mao', chegou_em = date '2026-12-05', previsao_original = date '2026-12-01', previsao_original_fonte = 'fornecedor', fornecedor_id = v_kam, quantidade_na_mao = 1
     where id = md5('e7e:p6:m:48')::uuid;
    perform pg_temp.medida(149, v_os[1], v_kam, 'oc:k3', p_comp => date '2026-12-01', p_cheg => date '2026-12-03', p_prazo => 2, p_vp => true);
    perform pg_temp.modo('sombra', false);
    perform pg_temp.antes_forn(c_hoje, c_ag);
    r2 := pg_temp.aprendido('fornecedor_atraso', v_kam::text);
    perform pg_temp.apaga(array['fornecedor_atraso', 'fornecedor_prazo']);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_atraso', v_kam::text);
    v_res := pg_temp.ok(v_res, 'C2o sombra: o atraso igual ao de antes (byte a byte, as 2 linhas): a previsão anterior à compra continua dentro até ligar',
      r.n = 2 and r2.n = 2 and to_jsonb(r) - array['id', 'criado_em', 'atualizado_em', 'calculado_em', 'historico'] = to_jsonb(r2) - array['id', 'criado_em', 'atualizado_em', 'calculado_em', 'historico'], to_jsonb(r)::text || ' <> ' || to_jsonb(r2)::text);
    perform pg_temp.modo('ligado', false);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_atraso', v_kam::text);
    v_res := pg_temp.ok(v_res, 'C2p ligado: a previsão dita antes da compra sai do atraso da Kamell (n 1: fica a de 05/12, a de 15/12 sai)', r.n = 1 and r.amostra -> 0 ->> 'em' = '2026-12-05', to_jsonb(r)::text);
    v_res := pg_temp.ok(v_res, 'C2p2 o atraso não vira compra: sem fonte, sem teria, e o n não soma as compras', not r.detalhe ? 'fonte' and not r.detalhe ? 'teria', r.detalhe::text);
    r := pg_temp.aprendido('fornecedor_prazo', v_kam::text);
    v_res := pg_temp.ok(v_res, 'C2q em ligado, só a compra com valida_prazo vira amostra (n 1, as 2 linhas sem validade ficam de fora)', r.n = 1 and r.detalhe ->> 'fonte' = 'compras', to_jsonb(r)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- sem compra medida: byte a byte contra o corpo de antes, em todos os modos; e a compra fora da janela não vira amostra
    v_corr := pg_temp.fornecedor('Correa');
    v_n1 := pg_temp.nota(3, v_corr, date '2026-12-10', date '2026-12-14');
    v_l := pg_temp.medida(49, pg_temp.aberta(49), v_corr, 'oc:9', p_comp => date '2025-11-10', p_cheg => date '2025-11-14', p_prazo => 2, p_vp => true);
    perform pg_temp.modo('ligado', false);
    perform pg_temp.antes_forn(c_hoje, c_ag);
    r2 := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    perform pg_temp.apaga(array['fornecedor_prazo']);
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);
    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_res := pg_temp.ok(v_res, 'C2r ligado sem compra na janela: igual ao de antes, sem fonte (compra fora da janela não entra)',
      r.n = 1 and not r.detalhe ? 'fonte' and to_jsonb(r) - array['id', 'criado_em', 'atualizado_em', 'calculado_em', 'historico'] = to_jsonb(r2) - array['id', 'criado_em', 'atualizado_em', 'calculado_em', 'historico'], to_jsonb(r)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- Quem LÊ o n de fornecedor_prazo também diz o que foi medido (conferência do P6; R7.12-9): o gravador passou a contar compras, e "(medido em 5 notas)" sem nota nenhuma é afirmação falsa.
    perform pg_temp.modo('ligado', false);
    v_corr := pg_temp.fornecedor('Correa');
    v_mis := pg_temp.fornecedor('Mista');
    v_ter := pg_temp.fornecedor('Terceira');
    v_os := array[pg_temp.aberta(61), pg_temp.aberta(62), pg_temp.aberta(63)];
    for k in 1 .. 5 loop
      perform pg_temp.medida(160 + k, v_os[1], v_corr, 'oc:t' || k, p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 2, p_vp => true);
    end loop;
    for k in 1 .. 3 loop
      perform pg_temp.medida(170 + k, v_os[2], v_mis, 'oc:m' || k, p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 2, p_vp => true);
    end loop;
    perform pg_temp.nota(61, v_mis, date '2026-12-10', date '2026-12-14');   -- 2 dias úteis, outra entrega
    perform pg_temp.nota(62, v_mis, date '2026-12-11', date '2026-12-15');   -- 2 dias úteis, outra entrega
    perform pg_temp.medida(180, v_os[2], v_ter, 'oc:u1', p_comp => date '2026-12-10', p_cheg => date '2026-12-14', p_prazo => 2, p_vp => true);   -- 1 só: fica medindo
    perform public._agenda_aprender_fornecedor(c_hoje, c_ag);

    r := pg_temp.aprendido('fornecedor_prazo', v_corr::text);
    v_pr := public._agenda_prazo_do_fornecedor(v_corr);
    v_res := pg_temp.ok(v_res, 'C2t1 5 compras e 0 notas: "(medido em 5 compras)", sem falar em nota; o resto do objeto é o do prazo medido (du 2, fonte medido, du_classe 1)',
      r.em_uso = 2 and (r.detalhe ->> 'compras')::int = 5 and (r.detalhe ->> 'notas')::int = 0
      and v_pr ->> 'texto' = 'entrega local, 2 dias úteis (medido em 5 compras)'
      and v_pr - 'texto' = jsonb_build_object('classe', 'entrega_local', 'du', 2, 'corridos', null, 'fonte', 'medido', 'duvida', null, 'principal_id', null, 'du_classe', 1), v_pr::text);
    r := pg_temp.aprendido('fornecedor_prazo', v_mis::text);
    v_pr := public._agenda_prazo_do_fornecedor(v_mis);
    v_res := pg_temp.ok(v_res, 'C2t2 3 compras e 2 notas: "(medido em 3 compras e 2 notas)"',
      r.em_uso = 2 and (r.detalhe ->> 'compras')::int = 3 and (r.detalhe ->> 'notas')::int = 2
      and v_pr ->> 'texto' = 'entrega local, 2 dias úteis (medido em 3 compras e 2 notas)', v_pr::text);

    -- a conta do gestor classifica pelo texto (like '%(medido em %'): a frase nova continua "medido"
    v_l := pg_temp.falta(64, v_os[3]);
    update public.os_material set fornecedor_id = v_corr where id = v_l;
    perform pg_temp.publica(v_os[3], 4);
    v_k := public._agenda_gestor_compra_conta(v_os[3], c_hoje) -> 'itens' -> 0;
    v_res := pg_temp.ok(v_res, 'C2t3 a conta do gestor continua classificando a compra medida como medido (prazo_fonte medido, prazo 2)',
      v_k ->> 'prazo_fonte' = 'medido' and (v_k ->> 'prazo')::int = 2, v_k::text);

    -- o foco fornecedores: Correa (só compras) na lista
    v_t := public._agenda_ver_fornecedores(c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C2t4 foco fornecedores, só compras: o bloco diz "pelas compras", a linha diz "5 compras" e não sobra "nota"',
      v_t like E'%Medido (pelas compras que chegaram):\n• Correa (Itajaí/SC): entrega local, 2 dias úteis (medido em 5 compras).\n%' and v_t not like '%nota%', v_t);

    -- entra a Mista (compras e notas)
    update public.os_material set fornecedor_id = v_mis where id = md5('e7e:p6:m:171')::uuid;
    v_t := public._agenda_ver_fornecedores(c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C2t5 foco fornecedores, compras e notas num fornecedor: o bloco diz "pelas compras e notas"',
      v_t like E'%Medido (pelas compras e notas que chegaram):\n%' and v_t like '%(medido em 3 compras e 2 notas).%' and v_t like '%(medido em 5 compras).%', v_t);

    -- 1 compra e 1 nota: o singular
    perform pg_temp.detalhe_prazo(v_mis, jsonb_build_object('fonte', 'compras', 'compras', 1, 'notas', 1));
    v_pr := public._agenda_prazo_do_fornecedor(v_mis);
    v_res := pg_temp.ok(v_res, 'C2t6 o singular: "(medido em 1 compra e 1 nota)"', v_pr ->> 'texto' = 'entrega local, 2 dias úteis (medido em 1 compra e 1 nota)', v_pr::text);

    -- sem compra medida (o detalhe de antes do P6): o texto de antes, byte a byte
    perform pg_temp.detalhe_prazo(v_mis, jsonb_build_object('n', 5, 'p50', 2, 'dono', false));
    v_pr := public._agenda_prazo_do_fornecedor(v_mis);
    v_res := pg_temp.ok(v_res, 'C2t7 sem compra medida: o texto de antes, byte a byte (o n da linha, "notas")', v_pr ->> 'texto' = 'entrega local, 2 dias úteis (medido em 5 notas)', v_pr::text);
    v_t := public._agenda_ver_fornecedores(c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C2t8 um só com compras, outro só com notas: o bloco diz "pelas compras e notas"', v_t like E'%Medido (pelas compras e notas que chegaram):\n%' and v_t like '%(medido em 5 notas).%', v_t);

    -- ninguém em uso por compra, e alguém medindo pela compra (fora do bloco): o título de antes
    perform pg_temp.detalhe_prazo(v_corr, jsonb_build_object('n', 5, 'p50', 2, 'dono', false));
    update public.os_material set fornecedor_id = v_ter where id = md5('e7e:p6:m:172')::uuid;
    v_res := pg_temp.ok(v_res, 'C2t9 a Terceira tem compra medida e ainda mede (fora do bloco)', (pg_temp.aprendido('fornecedor_prazo', v_ter::text)).detalhe ->> 'fonte' = 'compras' and (pg_temp.aprendido('fornecedor_prazo', v_ter::text)).em_uso is null, null);
    v_t := public._agenda_ver_fornecedores(c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C2t10 só notas no bloco: o título de antes, byte a byte, mesmo com alguém medindo pela compra', v_t like E'%Medido (pelas notas que chegaram):\n%' and v_t not like '%pelas compras%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C3. os_prontidao, C3b. a conta, C4. o publicado, C6. o Como eu conto ──────────────────────────
do $c3$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_os   uuid;
  v_os2  uuid;
  v_l    uuid;
  v_a    jsonb;
  v_b    jsonb;
  v_i    jsonb;
  v_ia   jsonb;
  v_k    jsonb;
  m      text;
  f      boolean;
  v_dif  int;
  v_i2   jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C3 prontidão', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  perform pg_temp.criar_antes();
  begin
    v_os := pg_temp.aberta(51);             -- a OS sem linha de os_planejamento: o caso comum (127 de 131)
    perform pg_temp.falta(51, v_os);
    perform pg_temp.publica(v_os, 4);
    v_os2 := pg_temp.aberta(52);
    perform pg_temp.falta(52, v_os2);       -- sem compromisso: a outra forma
    insert into public.os_planejamento (service_order_id, atualizado_em) values (v_os2, timestamptz '2026-12-01 10:00-03');
    v_dif := 0;
    foreach m in array array['desligado', 'sombra', 'ligado'] loop
      foreach f in array array[false, true] loop
        continue when m = 'ligado' and not f;   -- ligado de verdade é o caso do bloco de baixo
        perform pg_temp.modo(m, f);
        if public.os_prontidao(v_os, c_hoje) is distinct from pg_temp.antes_pro(v_os, c_hoje)
           or public.os_prontidao(v_os2, c_hoje) is distinct from pg_temp.antes_pro(v_os2, c_hoje)
           or public._agenda_gestor_compra_conta(v_os, c_hoje) is distinct from pg_temp.antes_conta(v_os, c_hoje) then v_dif := v_dif + 1; end if;
      end loop;
    end loop;
    v_res := pg_temp.ok(v_res, 'C3a desligado, sombra (com e sem freio) e ligado com o freio: prontidão e conta iguais às de antes, byte a byte, com OS sem linha de planejamento e com linha sem marcação', v_dif = 0, format('diferentes: %s', v_dif));
    perform pg_temp.modo('ligado', false);
    v_a := public.os_prontidao(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'C3b ligado sem medida em uso: o de antes, sem chave nova (e o "compre até" conta 1)', v_a = pg_temp.antes_pro(v_os, c_hoje) and not (pg_temp.item1(v_a)) ? 'tempo_interno_du', pg_temp.item1(v_a)::text);
    -- com o medido em uso: 1 dia útil antes com o tempo 2
    perform pg_temp.em_uso(2);
    v_i := pg_temp.item1(public.os_prontidao(v_os, c_hoje));
    v_ia := pg_temp.item1(pg_temp.antes_pro(v_os, c_hoje));
    v_res := pg_temp.ok(v_res, 'C3c ligado com tempo 2: o "compre até" 1 dia útil antes; o item diz o número',
      (v_i ->> 'compre_ate')::date = public.agenda_somar_du((v_ia ->> 'compre_ate')::date, -1) and (v_i ->> 'tempo_interno_du')::int = 2, v_i::text);
    v_res := pg_temp.ok(v_res, 'C3d a chegada "se comprar" também conta o tempo 2: 1 dia útil depois da de antes', (v_i ->> 'data')::date = public.agenda_somar_du((v_ia ->> 'data')::date, 1), v_i::text);
    -- tempo = o parâmetro: nada (efeito que não muda o número não é efeito)
    perform pg_temp.em_uso(1);
    v_res := pg_temp.ok(v_res, 'C3e em uso igual ao parâmetro: sem chave', not (pg_temp.item1(public.os_prontidao(v_os, c_hoje))) ? 'tempo_interno_du', null);
    -- sem a regra compra_firme: nada muda
    perform pg_temp.em_uso(2);
    update public.agenda_config set marcar_regras = array_remove(marcar_regras, 'compra_firme') where id;
    v_a := public.os_prontidao(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'C3f sem a regra compra_firme: o de antes, byte a byte, sem chave', v_a = pg_temp.antes_pro(v_os, c_hoje) and not (pg_temp.item1(v_a)) ? 'tempo_interno_du', null);
    -- com compra_firme, mas sem prazo nenhum (sem prazo_padrao): não há compra firme no item, e ele não ganha a chave
    update public.agenda_config set marcar_regras = array_remove(marcar_regras || array['compra_firme'], 'prazo_padrao') where id;
    v_i := pg_temp.item1(public.os_prontidao(v_os, c_hoje));
    v_res := pg_temp.ok(v_res, 'C3f2 item em falta sem compra_firme (sem prazo): sem a chave', not (coalesce((v_i ->> 'compra_firme')::boolean, false)) and not v_i ? 'tempo_interno_du', v_i::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- R7.8: em sombra, nenhuma chamada nova (as 2 funções trocadas por versões que lançam), inclusive na OS marcada
    v_os := pg_temp.aberta(53);
    perform pg_temp.falta(53, v_os);
    perform pg_temp.publica(v_os, 4);
    insert into public.os_planejamento (service_order_id, tempo_compra_marcado, marcado_em, atualizado_em) values (v_os, 1, date '2027-01-06', timestamptz '2026-12-01 10:00-03');
    perform pg_temp.modo('sombra', false);
    create or replace function public._agenda_tempo_interno_compra(p_os uuid) returns int language plpgsql as 'begin raise exception ''chamou''; end';
    v_b := public.os_prontidao(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'C3g em sombra, a OS marcada não chama função nova (R7.8): lê o que está na mão', v_b ->> 'ok' = 'true', null);
    v_res := pg_temp.ok(v_res, 'C3h marcada com o mesmo número do parâmetro: sem chave', not (pg_temp.item1(v_b)) ? 'tempo_interno_du', null);
    -- e a OS sem linha de planejamento, em sombra
    v_os2 := pg_temp.aberta(56);
    perform pg_temp.falta(56, v_os2);
    perform pg_temp.publica(v_os2, 4, date '2027-03-01');
    v_res := pg_temp.ok(v_res, 'C3h2 a OS sem linha de planejamento, em sombra, também não chama função nova', public.os_prontidao(v_os2, c_hoje) ->> 'ok' = 'true', null);
    perform pg_temp.modo('ligado', true);
    v_res := pg_temp.ok(v_res, 'C3h3 com o freio, fora da simulação do gestor, ligado não chama função nova na prontidão (v_f7_firme é falsa)', public.os_prontidao(v_os2, c_hoje) ->> 'ok' = 'true', null);
    -- a simulação do gestor (agenda.gestor = sombra) liga as regras mesmo com o freio: ligado com o freio vale sombra também no custo, e a OS sem marcação fica no parâmetro sem chamar a função
    perform set_config('agenda.gestor', 'sombra', true);
    begin
      v_i2 := pg_temp.item1(public.os_prontidao(v_os2, c_hoje));
    exception when others then
      v_i2 := jsonb_build_object('lancou', sqlerrm);
    end;
    v_res := pg_temp.ok(v_res, 'C3h4 com o freio e na simulação do gestor, ligado, OS sem marcação: a regra roda (compra_firme) e a prontidão não chama a função nem muda o parâmetro',
      not v_i2 ? 'lancou' and coalesce((v_i2 ->> 'compra_firme')::boolean, false) and not v_i2 ? 'tempo_interno_du', v_i2::text);
    -- a OS marcada usa o dela, lido da linha: é o que o comentário de os_prontidao afirma
    insert into public.os_planejamento (service_order_id, tempo_compra_marcado, marcado_em, atualizado_em) values (v_os2, 2, date '2027-01-06', timestamptz '2026-12-01 10:00-03');
    v_i2 := pg_temp.item1(public.os_prontidao(v_os2, c_hoje));
    v_res := pg_temp.ok(v_res, 'C3h5 com o freio e na simulação do gestor, a OS marcada usa o número dela (2), lido da linha, sem chamar a função', (v_i2 ->> 'tempo_interno_du')::int = 2, v_i2::text);
    perform set_config('agenda.gestor', '', true);
    -- o portão de firme: ligado de verdade, mas sem a regra compra_firme a conta não roda; a OS sem marcação não chama a função
    perform pg_temp.modo('ligado', false);
    update public.agenda_config set marcar_regras = array_remove(marcar_regras, 'compra_firme') where id;
    v_os2 := pg_temp.aberta(57);
    perform pg_temp.falta(57, v_os2);
    perform pg_temp.publica(v_os2, 4, date '2027-03-15');
    begin
      v_i2 := pg_temp.item1(public.os_prontidao(v_os2, c_hoje));
    exception when others then
      v_i2 := jsonb_build_object('lancou', sqlerrm);
    end;
    v_res := pg_temp.ok(v_res, 'C3h6 ligado sem o freio, mas sem a regra compra_firme: a OS sem marcação não chama a função (a conta não roda)', not v_i2 ? 'lancou', v_i2::text);
    perform pg_temp.modo('sombra', false);
    v_res := pg_temp.ok(v_res, 'C6a2 o "Como eu conto" em sombra não chama função nova', public._agenda_ver_gestor(c_hoje) is not null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- C3b: o v_mesma estável com o marcado; o mesmo número na prontidão e no gravado
    v_os := pg_temp.aberta(54);
    v_l := pg_temp.falta(54, v_os);
    perform pg_temp.publica(v_os, 4);
    insert into public.os_planejamento (service_order_id, tempo_compra_marcado, marcado_em, atualizado_em) values (v_os, 2, date '2027-01-06', timestamptz '2026-12-01 10:00-03');
    perform pg_temp.modo('sombra', false);
    v_k := public._agenda_gestor_compra_conta(v_os, c_hoje) -> 'itens' -> 0;
    v_res := pg_temp.ok(v_res, 'C3i a conta lê o marcado (2): base.interno 2; compre_ate = 1º dia − 1 (folga) − 7 (padrão) − 2',
      (v_k #>> '{base,interno}')::int = 2 and (v_k ->> 'compre_ate')::date = public.agenda_somar_du(date '2027-02-08', -10) and (v_k ->> 'gravado') is null and (v_k ->> 'muda')::boolean, v_k::text);
    -- a primeira gravação e a volta: "muda" falso, com o marcado valendo
    update public.os_material set compre_ate = (v_k ->> 'compre_ate')::date, compre_ate_base = v_k -> 'base', compre_ate_em = timestamptz '2027-01-07 10:00-03' where id = v_l;
    v_k := public._agenda_gestor_compra_conta(v_os, c_hoje) -> 'itens' -> 0;
    v_res := pg_temp.ok(v_res, 'C3j gravado com o marcado: v_mesma estável (muda falso na rodada seguinte; a base guarda 2)', (v_k ->> 'muda')::boolean = false and (v_k ->> 'gravado')::date = (v_k ->> 'compre_ate')::date, v_k::text);
    v_i := pg_temp.item1(public.os_prontidao(v_os, c_hoje));
    v_res := pg_temp.ok(v_res, 'C3k a prontidão diz o mesmo "compre até" do gravado e o número (2 ≠ parâmetro 1)', (v_i ->> 'compre_ate')::date = (v_k ->> 'compre_ate')::date and (v_i ->> 'tempo_interno_du')::int = 2, v_i::text);
    -- C4: o medido vira 3 (ligado de verdade): a OS marcada guarda 2, sem recontar nem mudar o gravado
    perform pg_temp.modo('ligado', false);
    perform pg_temp.em_uso(3);
    v_k := public._agenda_gestor_compra_conta(v_os, c_hoje) -> 'itens' -> 0;
    v_i := pg_temp.item1(public.os_prontidao(v_os, c_hoje));
    v_res := pg_temp.ok(v_res, 'C4a o publicado não muda: a OS marcada com 2 guarda 2 com o medido em 3 (muda falso, compre_ate o mesmo)', (v_k ->> 'muda')::boolean = false and (v_k #>> '{base,interno}')::int = 2 and (v_i ->> 'tempo_interno_du')::int = 2, v_k::text);
    -- e a OS não marcada, com a mesma carteira, conta 3
    v_os2 := pg_temp.aberta(55);
    perform pg_temp.falta(55, v_os2);
    perform pg_temp.publica(v_os2, 4, date '2027-03-01');
    v_k := public._agenda_gestor_compra_conta(v_os2, c_hoje) -> 'itens' -> 0;
    v_res := pg_temp.ok(v_res, 'C4b a OS ainda não marcada conta 3: a base guarda 3', (v_k #>> '{base,interno}')::int = 3 and (v_k ->> 'compre_ate')::date = public.agenda_somar_du(date '2027-03-01', -11), v_k::text);
    -- e a sem linha de planejamento volta ao parâmetro quando o medido sai de uso (nada de nulo no "compre até")
    perform pg_temp.apaga(array['tempo_compra']);
    v_k := public._agenda_gestor_compra_conta(v_os2, c_hoje) -> 'itens' -> 0;
    v_res := pg_temp.ok(v_res, 'C4c sem medido em uso, o parâmetro (nunca nulo): base.interno 1', (v_k #>> '{base,interno}')::int = 1, v_k::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- C6: o "Como eu conto" diz o número que vale (só em ligado de verdade)
    perform pg_temp.modo('sombra', false);
    perform pg_temp.em_uso(3);
    v_a := public._agenda_ver_gestor(c_hoje);
    v_res := pg_temp.ok(v_res, 'C6a sombra: o "Como eu conto" igual ao de antes, com o parâmetro', v_a = pg_temp.antes_ver(c_hoje) and v_a ->> 'texto' like '%entre decidir e comprar: 1 dia útil%', v_a ->> 'texto');
    perform pg_temp.modo('ligado', true);
    v_a := public._agenda_ver_gestor(c_hoje);
    v_res := pg_temp.ok(v_res, 'C6b ligado com o freio: ainda o parâmetro', v_a ->> 'texto' like '%entre decidir e comprar: 1 dia útil%', v_a ->> 'texto');
    perform pg_temp.modo('ligado', false);
    v_a := public._agenda_ver_gestor(c_hoje);
    v_res := pg_temp.ok(v_res, 'C6c ligado de verdade: o medido em uso (3)', v_a ->> 'texto' like '%entre decidir e comprar: 3 dias úteis%', v_a ->> 'texto');
    perform pg_temp.apaga(array['tempo_compra']);
    v_a := public._agenda_ver_gestor(c_hoje);
    v_res := pg_temp.ok(v_res, 'C6d ligado sem medida: o parâmetro', v_a ->> 'texto' like '%entre decidir e comprar: 1 dia útil%', v_a ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c3$;

-- ── C6e. Os textos do "Fornecedor pela compra": todos os momentos sem "nota" quando só há compra ──
do $c6$
declare
  v_res jsonb := '[]'::jsonb;
  v_d   jsonb := jsonb_build_object('n', 3, 'n_min', 3, 'calculado', 2, 'em_uso', 2, 'efetivo', 1, 'padrao', 1, 'volta', 1, 'desde', date '2027-01-07', 'travado_ate', date '2027-02-04', 'trava_dias', 28,
                                    'detalhe', jsonb_build_object('nome', 'Correa', 'fonte', 'compras', 'compras', 3, 'notas', 0));
  m     text;
  v_t   text;
  v_mal text := '';
begin
  foreach m in array array['foco_medindo', 'foco_sombra', 'foco_em_uso', 'foco_pergunta', 'foco_travado', 'acao', 'pergunta', 'desfeito'] loop
    v_t := public._agenda_aprendizado_texto('fornecedor_prazo', m, v_d);
    if v_t is null or length(v_t) = 0 or v_t ~ 'nota' or v_t !~ 'Correa' then v_mal := v_mal || m || ': ' || coalesce(v_t, 'nulo') || ' | '; end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'C6e fonte compras: nenhum dos 8 momentos fala em nota (texto não vazio, com o nome)', v_mal = '', v_mal);
  v_t := public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_em_uso', v_d || jsonb_build_object('detalhe', jsonb_build_object('nome', 'Correa')));
  v_res := pg_temp.ok(v_res, 'C6f contraste: sem a fonte, a frase da Fase 6 fala em nota (a varredura não passa vazia)', v_t ~ 'nota', v_t);
  v_res := pg_temp.ok(v_res, 'C6g as opções e o "fico" seguem a Fase 6, sem compra',
    public._agenda_aprendizado_texto('fornecedor_prazo', 'opcao1', v_d) = 'Passo a contar 2 dias úteis' and public._agenda_aprendizado_texto('fornecedor_prazo', 'fico', v_d) like 'Combinado: para Correa fico com%', null);
  v_res := pg_temp.ok(v_res, 'C6h o dono disse (medindo): diz que vale o dele',
    public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_medindo', v_d || jsonb_build_object('n', 1, 'detalhe', (v_d -> 'detalhe') || jsonb_build_object('dono', true))) = 'Correa: você disse 1 dia útil; medi 1 entregas da compra até a chegada (vale o que você disse).',
    public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_medindo', v_d || jsonb_build_object('n', 1, 'detalhe', (v_d -> 'detalhe') || jsonb_build_object('dono', true))));
  v_t := public._agenda_aprendizado_texto('fornecedor_prazo', 'foco_em_uso', v_d || jsonb_build_object('detalhe', jsonb_build_object('nome', 'Correa', 'teria', jsonb_build_object('n', 2, 'du', 3))) || jsonb_build_object('n', 5));
  v_res := pg_temp.ok(v_res, 'C6i em uso pela nota com o parêntese do teria (Fase 6 + em teste)', v_t like '%notas%' and v_t like '% (em teste: com as compras registradas seriam 2 entregas, até 3 dias úteis depois da compra).', v_t);
  perform pg_temp.gravar(v_res);
end
$c6$;

-- ── C5. As cópias ─────────────────────────────────────────────────────────────────────────────────
do $c5$
declare
  v_res jsonb := '[]'::jsonb;
  v_m text := coalesce(current_setting('agenda_teste.mig_compras_fase7e', true), '');
  r record;
begin
  if v_m = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'C5 as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)'));
    return;
  end if;
  v_res := pg_temp.ok(v_res, 'C5a a migration não recria o que R7.1 proíbe (_agenda_aprendido, agenda_aprender, agenda_propor, agenda_vigiar, agenda_cliente_vigiar) e não cria _agenda_folga_compra_du',
    v_m !~ 'create or replace function public\._agenda_aprendido\(' and v_m !~ 'function public\.agenda_aprender\(' and v_m !~ 'function public\.agenda_propor\(' and v_m !~ 'function public\.agenda_vigiar\(' and v_m !~ 'function public\.agenda_cliente_vigiar\(' and v_m !~ 'create or replace function public\._agenda_folga_compra_du\(', null);
  v_res := pg_temp.ok(v_res, 'C5b _agenda_tempo_interno_compra é a do P2 (não foi recriada)', v_m !~ 'create or replace function public\._agenda_tempo_interno_compra\(', null);
  for r in select * from (values
    ('_agenda_aprender_fornecedor', 'public._agenda_aprender_fornecedor(date, timestamptz)', 'c3ac59cf8a2166cb436d644a4276516e'),
    ('os_prontidao', 'public.os_prontidao(uuid, date)', 'c69862188638af46cbb0d2d9d1b1e7ea'),
    ('_agenda_gestor_compra_conta', 'public._agenda_gestor_compra_conta(uuid, date)', '559c1ecb44eab4dce4bdb91d0221e34b'),
    ('_agenda_ver_gestor', 'public._agenda_ver_gestor(date)', '9a4f0eff1587a01a4963ac4161a64731'),
    -- Integração P4–P6 (09/11): a origem do texto é a 20261111100300 (o P4 a recriou depois do P2, com o texto da folga sem medida); no ramo do P6 era a 20261111100100 (d6efbf56237d8da99642b5411ba86930)
    ('_agenda_aprendizado_texto', 'public._agenda_aprendizado_texto(text, text, jsonb)', '3da677f2b336f2fd012ccb96bde4f4a0'),
    ('_agenda_prazo_do_fornecedor', 'public._agenda_prazo_do_fornecedor(uuid)', '82e9ff9a043dc182586acd751ee2a9a9'),
    ('_agenda_ver_fornecedores', 'public._agenda_ver_fornecedores(date)', 'e71ba407c805508d2914f6a173f0b572')) t(nome, assin, md5o)
  loop
    v_res := pg_temp.ok(v_res, 'C5c ' || r.nome || ': tirados os blocos do P6, o corpo é o da origem (md5)',
      md5(pg_temp.sem_p6((select prosrc from pg_proc where oid = r.assin::regprocedure))) = r.md5o,
      md5(pg_temp.sem_p6((select prosrc from pg_proc where oid = r.assin::regprocedure))));
  end loop;
  perform pg_temp.gravar(v_res);
end
$c5$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
