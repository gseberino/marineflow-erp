-- Prova do fornecedor no aprendizado da Agenda de Produção, Fase 6 (pacote P3; migration 20261029100300): o atraso medido das
-- entregas, o prazo medido da nota e a data provável do material na prontidão (só no nível B).
-- bancada: depende de 20261029100950
--
--   F1 as entregas e o atraso: 3 linhas da mesma nota = 1 entrega (o maior atraso das linhas), o fornecedor da linha, da OC ou
--      da nota, o atraso assinado (−1 = adiantou), o P80 (2 dias úteis, 4 de 6 no prazo); a Correa abaixo do mínimo; rodar 2×
--      não muda nada; em teste nada vale; ligado, a troca pequena entra sozinha (a ação) e a grande vira pergunta
--   F2 o prazo medido da nota (6 dias úteis em 5 notas; o padrão "outro estado" é 4) e a fonte medido em
--      _agenda_prazo_do_fornecedor, logo depois do que o dono disse (o dono vem antes; em teste, a de antes)
--   F3 os_prontidao: no nível B, a data provável (data) e o dia dito (data_dita) com o texto "a OC diz …: conto com …"; o DPM e
--      o início pelo material pela provável; C (você disse), o dia que chegou e o atrasado pelo dia dito; a "chegou?" (a vigia e
--      a restrição) pelo os_material.previsao_ate; o foco compras não diz "chega <provável>"; em teste e ligado sem a lista,
--      TODAS as OS da fixture saem byte a byte iguais à definição de antes (20261027100200, rodada como pg_temp)
--   F4 a vigia de terços igual (a mesma mensagem ao fornecedor, com o dia dele) com e sem o atraso em uso; nenhuma mensagem nova
--      a ninguém (as filas não mudam; nada na migration escreve nelas)
--   F5 o foco compras: desligado, o de antes; em teste, as linhas do que a agenda mediu dos fornecedores
--   F6 as cópias só acrescentam os blocos "-- FASE 6:"; as assinaturas, a segurança e as portas
--   F7 os textos do atraso e do prazo em cada momento (spec §6.2/§6.3), sem jargão (em qualquer lugar)
--
-- QUEM LÊ O "data" DOS ITENS DA PRONTIDÃO (grep em supabase/migrations, supabase/functions e src, 28/10; a definição mais nova
-- de cada função):
--   · os_prontidao (o DPM, o gargalo, o início pelo material, o "se X chegar …") → o motor, _agenda_aviso_do_material ("só chega
--     por volta de …"), agenda_ctp ("chegam por volta de …"), _agenda_cliente_risco (a faixa da peça): a provável, de propósito;
--   · a "chegou?" (_agenda_vigia_chegou, _agenda_vigia_limpeza), a restrição "a previsão … venceu", _agenda_atrasos_de: só o
--     item atrasado (o dia dito já passou) → data = o dia dito (F3e prova a pergunta com previsao_ate);
--   · agenda_ver_material ("você ainda não me disse que chegou" com data <= hoje) → no dia dito, data = o dia dito (F3d);
--   · _agenda_compras_da_os ("chega … (pela nota …)") → recriada: com data_dita, o data_texto (F3c);
--   · os_plano_da_os (o cartão) e o TS (PlanoDaOs, ferramentas) só leem data_texto; os terços leem os_material.previsao_ate (F4).
--   F8 (correção C1, 20261029100900) o publicado não cai pela data provável (nem o confirmado pelo cliente); a nota sem o
--      atraso por cima e fora da medida do atraso; o fornecedor inativo mede e lê pelo principal
--   F9 (correção C2, 20261029100950) a linha do atraso do foco compras pelo principal do cadastro inativo
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_fornecedor.sql
--   Seguro em produção: tudo dentro de begin/rollback. F6 e F7 rodam em qualquer lugar (as cópias só com as migrations como
--   texto); F1 a F5 só na bancada (a fixture-fase6; fora dela, PULADO).
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
  v_c6 boolean := false;  -- CORREÇÃO FASE 6 (C1): dentro de um bloco da correção da Fase 6
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    -- CORREÇÃO FASE 6: (C1) os blocos "-- CORREÇÃO FASE 6: … -- CORREÇÃO FASE 6: fim" também saem (a correção C1 da Fase 6
    -- recria a função copiando a definição mais nova: só acréscimo); o fim é lido pelo prefixo
    -- CORREÇÃO 29/10 (P5): e os blocos "-- CORREÇÃO 29/10 (P5): … fim" (os_prontidao recriada de novo em 20261030100400)
    if not v_c6 and l ~ '^\s*-- CORREÇÃO (FASE 6|29/10 \(P5\)):' and l !~ '^\s*-- CORREÇÃO (FASE 6|29/10 \(P5\)): fim' then v_c6 := true; continue; end if;
    if v_c6 then
      if l ~ '^\s*-- CORREÇÃO (FASE 6|29/10 \(P5\)): fim' then v_c6 := false; end if;
      continue;
    end if;
    -- CORREÇÃO FASE 6: fim
    -- FASE 7 (7a P3): e os blocos "-- FASE 7: … fim" (os_prontidao recriada de novo em 20261031100200: só acréscimo)
    if not v_bloco and l ~ '^\s*-- FASE [67]:' and l !~ '^\s*-- FASE [67]: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE [67]: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- O item de material da prontidão da OS cuja descrição começa com p_desc.
create function pg_temp.item(p_os uuid, p_desc text, p_hoje date) returns jsonb language sql stable as $f$
  select e from jsonb_array_elements(public.os_prontidao(p_os, p_hoje) #> '{material,itens}') e
   where e ->> 'descricao' like p_desc || '%' limit 1
$f$;

-- O painel do Nelson (OS-00112) passa a ser da Kamell, com a previsão p_prev dita por p_fonte; os outros itens dele saem da
-- conta (dispensados), para o material dele depender só do painel (o DPM e o início pelo material aparecem).
create function pg_temp.painel_da_kamell(p_prev date, p_fonte text, p_so_ele boolean) returns void language plpgsql as $f$
begin
  update public.os_material
     set fornecedor_id = 'dd000000-0000-4000-8000-000000000002', previsao_ate = p_prev, previsao_fonte = p_fonte
   where service_order_id = '05000000-0000-4000-8000-000000000112' and descricao like 'Painel Touch%';
  if p_so_ele then
    update public.os_material set situacao = 'dispensado', compra_prevista_em = null
     where service_order_id = '05000000-0000-4000-8000-000000000112' and descricao not like 'Painel Touch%';
  end if;
end $f$;

-- ── F1. As entregas e o atraso ──────────────────────────────────────────────────────────────────────────
do $f1$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-30';
  c_agora  constant timestamptz := timestamptz '2026-10-30 16:05-03';
  c_kamell constant text := 'dd000000-0000-4000-8000-000000000002';
  c_correa constant text := 'dd000000-0000-4000-8000-000000000008';
  c_tec    constant uuid := 'aa000000-0000-4000-8000-0000000000ff';
  v  jsonb;
  a  public.agenda_aprendizado;
  n0 int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('F1 as entregas e o atraso (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v := public._agenda_aprender_fornecedor(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'F1a em teste: 3 chaves (o atraso e o prazo da Kamell em teste, o atraso da Correa medindo), nenhuma ação nem pergunta',
      v = '{"chaves": 3, "estados": {"sombra": 2, "medindo": 1}, "acoes": 0, "perguntas": 0, "erros": 0}', v::text);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_atraso' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F1b Kamell: 6 entregas, 4 no prazo, o P80 do atraso 2 dias úteis, padrão 0, em teste (o texto da spec §6.2)',
      a.calculado = 2 and a.n = 6 and a.n_min = 5 and a.padrao = 0 and a.nivel = 'fornecedor' and a.estado = 'sombra'
      and a.em_uso is null and (a.detalhe ->> 'no_prazo')::int = 4 and a.detalhe ->> 'nome' = 'Kamell'
      and a.texto = 'Kamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis (em teste).',
      to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'F1c a nota com 3 linhas (uma adiantada 1 dia, duas no dia) é UMA entrega, com o maior atraso (0); o atraso é assinado (−1 = a OS-00132 adiantou); os atrasos −1, 0, 0, 0, 2, 3',
      (select count(*) from jsonb_array_elements(a.amostra) e where e ->> 'entrega' = 'nota:d6300000-0000-4000-8000-000000000101'
          and e ->> 'linhas' = '3' and e ->> 'atraso' = '0') = 1
      and exists (select 1 from jsonb_array_elements(a.amostra) e where e ->> 'numero' = 'OS-00132' and e ->> 'atraso' = '-1')
      and (select string_agg(e ->> 'atraso', ',' order by (e ->> 'atraso')::int) from jsonb_array_elements(a.amostra) e) = '-1,0,0,0,2,3',
      a.amostra::text);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_atraso' and chave = c_correa;
    v_res := pg_temp.ok(v_res, 'F1d Correa: 4 entregas, abaixo do mínimo (5): medindo, "Correa: 4 de 5 entregas medidas."',
      a.estado = 'medindo' and a.n = 4 and a.em_uso is null and a.texto = 'Correa: 4 de 5 entregas medidas.', to_jsonb(a)::text);
    v := public._agenda_atraso_do_fornecedor(c_kamell::uuid);
    v_res := pg_temp.ok(v_res, 'F1e em teste nada vale: _agenda_aprendido nulo; _agenda_atraso_do_fornecedor diz o medido (2), o n e em_uso nulo; sem medida, nulo',
      public._agenda_aprendido('fornecedor_atraso', c_kamell) is null
      and (v ->> 'du')::numeric = 2 and v ->> 'n' = '6' and v ->> 'no_prazo' = '4' and v -> 'em_uso' = 'null'::jsonb
      and v ->> 'nome' = 'Kamell' and v ->> 'estado' = 'sombra'
      and public._agenda_atraso_do_fornecedor('dd000000-0000-4000-8000-000000000001') is null
      and public._agenda_atraso_do_fornecedor(null) is null, v::text);
    v_res := pg_temp.ok(v_res, 'F1f o técnico não lê o que a agenda mediu (a RLS): nulo, sem erro',
      pg_temp.como(c_tec, 'authenticated',
        format($q$select coalesce(public._agenda_atraso_do_fornecedor(%L)::text, 'nulo')$q$, c_kamell)) = 'nulo',
      pg_temp.como(c_tec, 'authenticated',
        format($q$select coalesce(public._agenda_atraso_do_fornecedor(%L)::text, 'nulo')$q$, c_kamell)));

    select count(*) into n0 from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item like 'fornecedor%';
    v := public._agenda_aprender_fornecedor(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'F1g rodar de novo no mesmo dia não muda nada (os mesmos estados, nenhuma entrada nova no histórico)',
      v ->> 'estados' = '{"sombra": 2, "medindo": 1}'
      and (select count(*) from public.agenda_aprendizado y, jsonb_array_elements(y.historico) h where y.item like 'fornecedor%') = n0,
      v::text);

    -- a linha da OS-00134 pela OC: sem fornecedor na linha, o da OC
    insert into public.purchase_orders (id, po_number, status, supplier_id, service_order_id, expected_date, created_at, updated_at)
    values ('70000000-0000-4000-8000-000000000631', 'OC-00631', 'received', c_kamell::uuid,
            '05000000-0000-4000-8000-000000000134', date '2026-10-14', '2026-10-08 10:00-03', '2026-10-14 15:00-03');
    insert into public.purchase_order_items (id, purchase_order_id, product_id, description, quantity, unit_cost, received_qty, created_at)
    values ('71000000-0000-4000-8000-000000000631', '70000000-0000-4000-8000-000000000631', null, 'Inversor 3000W 12V (AG6F)', 1, 0, 1,
            '2026-10-08 10:00-03');
    update public.os_material set origem = 'oc', purchase_order_item_id = '71000000-0000-4000-8000-000000000631', fornecedor_id = null
     where id = 'd6300000-0000-4000-8000-000000000006';
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_atraso' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F1h a linha sem fornecedor ligada a uma OC da Kamell conta para a Kamell (o fornecedor da OC), como uma entrega da OC',
      a.n = 6 and a.calculado = 2
      and exists (select 1 from jsonb_array_elements(a.amostra) e where e ->> 'entrega' = 'oc:70000000-0000-4000-8000-000000000631'),
      a.amostra::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ligado com o fornecedor na lista: a troca pequena (0 → 2 dias úteis) entra sozinha
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
    v := public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_atraso' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F1i ligado: a troca pequena (de 0 para 2 dias úteis; o limite é 3) entra sozinha, com a ação no "o que mudou" e o *desfaz*',
      v ->> 'acoes' = '2' and v ->> 'perguntas' = '0' and a.estado = 'em_uso' and a.em_uso = 2
      and public._agenda_aprendido('fornecedor_atraso', c_kamell) = 2
      and exists (select 1 from public.agenda_acoes x
                   where x.tipo = 'aprendizado' and x.origem = 'vigia' and x.desfazivel_ate > c_agora
                     and x.antes ->> 'item' = 'fornecedor_atraso' and x.antes -> 'em_uso' = 'null'::jsonb
                     and x.depois ->> 'em_uso' = '2'
                     and x.texto = 'Kamell atrasou até 2 dias úteis em 6 entregas: passei a contar a chegada 2 dias úteis depois do que o fornecedor diz. *desfaz aprendizado* volta.'),
      v::text || ' / ' || to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'F1j em uso, o texto do foco diz o que vale e desde quando',
      a.texto = 'Kamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis: conto a chegada 2 dias úteis depois do que o fornecedor diz (desde sex 30/10).',
      a.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- a troca grande (de 0 para 5 dias úteis) vira pergunta crítica, e nada vale até o dono responder
  begin
    execute current_setting('agenda_teste.fase6');
    update public.os_material set chegou_em = date '2026-10-22' where id = 'd6300000-0000-4000-8000-000000000007';  -- 5 dias úteis
    update public.os_material set chegou_em = date '2026-10-28' where id = 'd6300000-0000-4000-8000-000000000008';  -- 6 dias úteis
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
    v := public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_atraso' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F1k a troca grande (de 0 para 5 dias úteis) vira pergunta crítica (sem a opção 3: o que vale é o padrão) e nada vale até a resposta',
      a.estado = 'pergunta' and a.calculado = 5 and a.em_uso is null
      and public._agenda_aprendido('fornecedor_atraso', c_kamell) is null
      and exists (select 1 from public.agenda_perguntas q
                   where q.tipo = 'aprendizado' and q.estado = 'aberta' and q.chave = 'aprendizado:fornecedor_atraso:' || c_kamell
                     and jsonb_array_length(q.opcoes) = 2
                     and q.texto = 'Medi as entregas de Kamell: o atraso chega a 5 dias úteis (6 entregas), e hoje eu conto a chegada no dia que o fornecedor diz. É uma troca grande. 1) Passo a contar a chegada 5 dias úteis depois do que o fornecedor diz (recomendo); 2) Fico com a chegada no dia que o fornecedor diz.'),
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'aprendizado'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f1$;

-- ── F2. O prazo medido da nota ──────────────────────────────────────────────────────────────────────────
do $f2$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-30';
  c_agora  constant timestamptz := timestamptz '2026-10-30 16:05-03';
  c_kamell constant text := 'dd000000-0000-4000-8000-000000000002';
  v   jsonb;
  pf0 jsonb;
  pf  jsonb;
  a   public.agenda_aprendizado;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('F2 o prazo medido (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    pf0 := public._agenda_prazo_do_fornecedor(c_kamell::uuid);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_prazo' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F2a em teste: as 5 notas da Kamell que chegaram levam até 6 dias úteis da saída até a chegada (o padrão, "outro estado", 4)',
      a.calculado = 6 and a.n = 5 and a.padrao = 4 and a.estado = 'sombra' and a.em_uso is null
      and a.texto = 'Em teste: Kamell leva até 6 dias úteis da saída da nota até a chegada (5 notas); hoje conto 4 dias úteis (padrão).',
      to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'F2b em teste o prazo do fornecedor é o de antes, byte a byte (pela cidade, 4 dias úteis)',
      public._agenda_prazo_do_fornecedor(c_kamell::uuid) = pf0 and pf0 ->> 'fonte' = 'cidade' and pf0 ->> 'du' = '4'
      and not (pf0 ? 'du_classe'), pf0::text);

    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    pf := public._agenda_prazo_do_fornecedor(c_kamell::uuid);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_prazo' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F2c ligado: o prazo medido entra sozinho (de 4 para 6; o limite é 3), com a ação, e o prazo do fornecedor passa à fonte medido (a classe fica; du_classe = o de antes)',
      a.estado = 'em_uso' and a.em_uso = 6
      and pf ->> 'fonte' = 'medido' and pf ->> 'du' = '6' and pf ->> 'du_classe' = '4' and pf ->> 'classe' = 'outro_estado'
      and pf ->> 'texto' = 'outro estado, 6 dias úteis (medido em 5 notas)'
      and exists (select 1 from public.agenda_acoes x where x.tipo = 'aprendizado' and x.antes ->> 'item' = 'fornecedor_prazo'
                     and x.texto = 'Medi as notas de Kamell: da saída até a chegada levam até 6 dias úteis (5 notas). Passei a contar 6 dias úteis no lugar de 4 dias úteis. *desfaz aprendizado* volta.'),
      pf::text || ' / ' || to_jsonb(a)::text);
    v := public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_prazo' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F2d na rodada seguinte o padrão continua o da classe (4, e não o medido em uso): nada muda, nenhuma ação nova',
      a.padrao = 4 and a.em_uso = 6 and a.estado = 'em_uso' and v ->> 'acoes' = '0', v::text || ' / ' || to_jsonb(a)::text);
    v_res := pg_temp.ok(v_res, 'F2e a prontidão usa o prazo medido no item sem previsão (o Cerbo do Nelson, a comprar da Kamell: "se comprar hoje" com 6 dias úteis)',
      pg_temp.item('05000000-0000-4000-8000-000000000112', 'CENTRAL DE CONTROLE', c_hoje) ->> 'prazo_du' = '6'
      and pg_temp.item('05000000-0000-4000-8000-000000000112', 'CENTRAL DE CONTROLE', c_hoje) ->> 'data' = '2026-11-10'
      and pg_temp.item('05000000-0000-4000-8000-000000000112', 'CENTRAL DE CONTROLE', c_hoje) ->> 'prazo_texto' = 'outro estado, 6 dias úteis (medido em 5 notas)',
      pg_temp.item('05000000-0000-4000-8000-000000000112', 'CENTRAL DE CONTROLE', c_hoje)::text);

    -- o que o dono disse vem antes do medido: o medido não vale, e a rodada só mede
    update public.suppliers set modalidade = 'outro_estado', prazo_dias_uteis = 3, prazo_fonte = 'dono' where id = c_kamell::uuid;
    pf := public._agenda_prazo_do_fornecedor(c_kamell::uuid);
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_prazo' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F2f o que o dono disse (3 dias úteis) vem antes do medido; a rodada só mede e diz que vale o dele',
      pf ->> 'fonte' = 'dono' and pf ->> 'du' = '3' and not (pf ? 'du_classe')
      and a.estado = 'medindo' and a.em_uso is null
      and a.texto = 'Kamell: você disse 3 dias úteis; medi 5 notas da saída até a chegada (vale o que você disse).',
      pf::text || ' / ' || to_jsonb(a)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f2$;

-- ── F3. A data provável na prontidão ────────────────────────────────────────────────────────────────────
do $f3$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-30';
  c_agora  constant timestamptz := timestamptz '2026-10-30 16:05-03';
  c_nelson constant uuid := '05000000-0000-4000-8000-000000000112';
  v  jsonb;
  p  jsonb;
  r  jsonb;
  v_id text;
  v_folga int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('F3 a data provável na prontidão (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    v_folga := (select folga_material_du from public.agenda_config where id);
    perform pg_temp.painel_da_kamell(date '2026-11-05', 'oc', true);
    v_id := (select m.id::text from public.os_material m where m.service_order_id = c_nelson and m.descricao like 'Painel Touch%');
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    v := pg_temp.item(c_nelson, 'Painel Touch', c_hoje);
    p := public.os_prontidao(c_nelson, c_hoje) -> 'material';
    v_res := pg_temp.ok(v_res, 'F3a em teste: o painel (nível B, a OC diz qui 05/11) chega no dia dito, sem data_dita; o DPM é qui 05/11',
      v ->> 'nivel' = 'B' and v ->> 'data' = '2026-11-05' and not (v ? 'data_dita') and v ->> 'data_texto' = 'chega qui 05/11 (pela OC)'
      and p ->> 'dpm' = '2026-11-05' and p ->> 'estado' = 'previsto'
      and p ->> 'inicio_mat' = public.agenda_somar_du(date '2026-11-05', v_folga)::text,
      v::text || ' / ' || p::text);

    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    v := pg_temp.item(c_nelson, 'Painel Touch', c_hoje);
    p := public.os_prontidao(c_nelson, c_hoje) -> 'material';
    v_res := pg_temp.ok(v_res, 'F3b ligado: data = seg 09/11 (qui 05/11 + 2 dias úteis), data_dita = qui 05/11, o texto "a OC diz …: conto com …"; atrasado e sem_data pelo dia dito',
      v ->> 'nivel' = 'B' and v ->> 'data' = '2026-11-09' and v ->> 'data_dita' = '2026-11-05'
      and v ->> 'data_texto' = 'a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11'
      and v ->> 'atrasado' = 'false' and v ->> 'sem_data' = 'false' and v ->> 'previsao_fonte' = 'oc',
      v::text);
    v_res := pg_temp.ok(v_res, 'F3c o DPM, o gargalo e o início pelo material passam à data provável (o risco do início: o motor e o aviso ao cliente)',
      p ->> 'dpm' = '2026-11-09' and p ->> 'inicio_mat' = public.agenda_somar_du(date '2026-11-09', v_folga)::text
      and p ->> 'gargalo' like 'Painel Touch%', p::text);
    r := public._agenda_ver_compras(c_nelson, c_hoje);
    v_res := pg_temp.ok(v_res, 'F3d o foco compras da OS diz o que a OC diz e com que dia a agenda conta (nunca "chega seg 09/11", que poria a conta como palavra do fornecedor)',
      r ->> 'texto' like '%"Painel Touch de…" a OC diz qui 05/11; Kamell costuma atrasar até 2 dias úteis: conto com seg 09/11%'
      and r ->> 'texto' not like '%chega seg 09/11%', r ->> 'texto');

    -- o que o dono disse (C): não muda
    update public.os_material set previsao_fonte = 'dono' where id = v_id::uuid;
    v := pg_temp.item(c_nelson, 'Painel Touch', c_hoje);
    v_res := pg_temp.ok(v_res, 'F3e o dia que você disse (nível C) não ganha atraso: qui 05/11, sem data_dita',
      v ->> 'nivel' = 'C' and v ->> 'data' = '2026-11-05' and not (v ? 'data_dita') and v ->> 'data_texto' = 'chega qui 05/11 (você disse)',
      v::text);
    -- o dia dito chegou: vale o dia dito (é o dia da "chegou?")
    update public.os_material set previsao_fonte = 'oc', previsao_ate = c_hoje where id = v_id::uuid;
    v := pg_temp.item(c_nelson, 'Painel Touch', c_hoje);
    v_res := pg_temp.ok(v_res, 'F3f no dia dito (hoje), vale o dia dito: data = sex 30/10, sem data_dita (a leitura "você ainda não me disse que chegou" lê o mesmo dia)',
      v ->> 'nivel' = 'B' and v ->> 'data' = '2026-10-30' and not (v ? 'data_dita') and v ->> 'atrasado' = 'false', v::text);
    -- o dia dito passou: atrasado pelo dia dito, e a "chegou?" pergunta pelo os_material.previsao_ate
    update public.os_material set previsao_ate = date '2026-10-28' where id = v_id::uuid;
    v := pg_temp.item(c_nelson, 'Painel Touch', c_hoje);
    r := (select e from jsonb_array_elements(public.os_prontidao(c_nelson, c_hoje) -> 'restricoes') e where e ->> 'tipo' = 'atrasado');
    v_res := pg_temp.ok(v_res, 'F3g a previsão venceu (qua 28/10): o item é atrasado pelo dia dito (data = 28/10, sem data_dita), e a restrição diz "venceu em 28/10: chegou?"',
      v ->> 'data' = '2026-10-28' and v ->> 'atrasado' = 'true' and not (v ? 'data_dita')
      and r ->> 'desde' = '2026-10-28' and r ->> 'texto' = 'a previsão de "Painel Touch de…" venceu em 28/10: chegou?',
      v::text || ' / ' || coalesce(r::text, '—'));
    perform public._agenda_vigia_chegou(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'F3h a vigia pergunta "chegou?" pelo os_material.previsao_ate (a chave e o texto com qua 28/10), não pela data provável',
      exists (select 1 from public.agenda_perguntas q
               where q.tipo = 'chegou' and q.estado = 'aberta'
                 and q.chave = format('chegou:%s:%s', v_id,
                                      (select m.previsao_ate from public.os_material m where m.id = v_id::uuid))
                 and q.chave = 'chegou:' || v_id || ':2026-10-28'
                 and q.texto like '%"Painel Touch de…" tinha previsão para qua 28/10. Chegou?'),
      (select string_agg(q.chave || ' ' || q.texto, ' | ') from public.agenda_perguntas q where q.tipo = 'chegou'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f3$;

-- F3z. Em teste (e ligado sem a lista), TODAS as OS da fixture saem byte a byte iguais à definição de antes.
do $f3z$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v_mig text := coalesce(current_setting('agenda_teste.mig_compras_fase4', true), '');
  v_n   int;
  v_dif text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' or v_mig = '' then
    insert into _resultado values ('F3z em teste, a prontidão de antes (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    execute replace(pg_temp.inteira(v_mig, 'os_prontidao'), 'create or replace function public.os_prontidao(',
                    'create function pg_temp.prontidao_de_antes(');
    -- um item de nível B da Kamell na carteira (o painel do Nelson), para a provável ter onde aparecer
    perform pg_temp.painel_da_kamell(date '2026-11-05', 'oc', false);
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select count(*), string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             public.os_prontidao(so.id, c_hoje)::text is distinct from pg_temp.prontidao_de_antes(so.id, c_hoje)::text)
      into v_n, v_dif from public.service_orders so;
    v_res := pg_temp.ok(v_res, 'F3za em teste (o atraso e o prazo da Kamell calculados), a prontidão de todas as OS é a de antes, byte a byte',
      v_dif is null and v_n > 30, format('%s OS; diferentes: %s', v_n, coalesce(v_dif, '—')));
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{}' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             public.os_prontidao(so.id, c_hoje)::text is distinct from pg_temp.prontidao_de_antes(so.id, c_hoje)::text)
      into v_dif from public.service_orders so;
    v_res := pg_temp.ok(v_res, 'F3zb ligado com a lista vazia: o mesmo (nada em uso)', v_dif is null, coalesce(v_dif, '—'));
    update public.agenda_config set aprendizado_ligados = '{fornecedor}' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    -- (a definição de antes chama a _agenda_prazo_do_fornecedor de agora: o prazo medido aparece nas duas; a diferença é a
    -- data provável)
    select string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             public.os_prontidao(so.id, c_hoje)::text is distinct from pg_temp.prontidao_de_antes(so.id, c_hoje)::text)
      into v_dif from public.service_orders so;
    v_res := pg_temp.ok(v_res, 'F3zc ligado com o fornecedor: só a OS com item de nível B da Kamell (o Nelson) muda',
      coalesce(v_dif, '—') = 'OS-00112', coalesce(v_dif, '—'));
    select string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             (public.os_prontidao(so.id, c_hoje) - 'material')::text is distinct from (pg_temp.prontidao_de_antes(so.id, c_hoje) - 'material')::text
             or ((public.os_prontidao(so.id, c_hoje) -> 'material') - 'itens' - 'dpm' - 'inicio_mat' - 'gargalo')::text
                is distinct from ((pg_temp.prontidao_de_antes(so.id, c_hoje) -> 'material') - 'itens' - 'dpm' - 'inicio_mat' - 'gargalo')::text
             or (select jsonb_agg(e - 'data' - 'data_dita' - 'data_texto')
                   from jsonb_array_elements(public.os_prontidao(so.id, c_hoje) #> '{material,itens}') e)::text
                is distinct from
                (select jsonb_agg(e - 'data' - 'data_dita' - 'data_texto')
                   from jsonb_array_elements(pg_temp.prontidao_de_antes(so.id, c_hoje) #> '{material,itens}') e)::text)
      into v_dif from public.service_orders so;
    v_res := pg_temp.ok(v_res, 'F3zd e nela só mudam a data, o dia dito e o texto do item (e o que a data move: o DPM, o início pelo material, o gargalo)',
      v_dif is null, coalesce(v_dif, '—'));
    select string_agg(e ->> 'descricao', ', ') into v_dif
      from jsonb_array_elements(public.os_prontidao('05000000-0000-4000-8000-000000000112', c_hoje) #> '{material,itens}') e
     where e ? 'data_dita';
    v_res := pg_temp.ok(v_res, 'F3ze no Nelson, só o painel (o nível B da Kamell) ganha o dia dito; o Cerbo (a comprar, da Kamell: nível D) não',
      v_dif like 'Painel Touch%' and v_dif not like '%,%', coalesce(v_dif, '—'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f3z$;

-- ── F4. A vigia de terços igual; nenhuma mensagem nova ──────────────────────────────────────────────────
do $f4$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v_mig text := coalesce(current_setting('agenda_teste.mig_fornecedor_fase6', true), '');
  t1 jsonb; t2 jsonb;
  m1 text;  m2 text;
  n0 text;  n1 text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('F4 a vigia de terços e as filas (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
  else
    -- com o atraso da Kamell em uso
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.painel_da_kamell(date '2026-11-11', 'fornecedor', false);
      update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}', modo_fornecedor = 'sombra' where id;
      perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
      t1 := public._agenda_material_tercos(c_hoje, c_agora);
      select string_agg(concat_ws('|', x.service_order_id, x.terco, x.modo, x.estado, x.texto, x.enviar_em), E'\n' order by x.service_order_id, x.terco)
        into m1 from public.agenda_fornecedor_mensagens x;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- sem nada aprendido em uso
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.painel_da_kamell(date '2026-11-11', 'fornecedor', false);
      update public.agenda_config set modo_fornecedor = 'sombra' where id;
      t2 := public._agenda_material_tercos(c_hoje, c_agora);
      select string_agg(concat_ws('|', x.service_order_id, x.terco, x.modo, x.estado, x.texto, x.enviar_em), E'\n' order by x.service_order_id, x.terco)
        into m2 from public.agenda_fornecedor_mensagens x;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_res := pg_temp.ok(v_res, 'F4a a vigia de terços faz a mesma pergunta ao fornecedor, com o dia DELE (qua 11/11), com e sem o atraso em uso',
      t1 = t2 and m1 = m2 and (t1 ->> 'registradas')::int = 1 and m1 like '%a entrega continua prevista para qua 11/11? Obrigado!%',
      coalesce(m1, '—') || ' × ' || coalesce(m2, '—'));

    -- nada do P3 escreve em fila: as mensagens ao fornecedor, ao cliente, à equipe e a fila do WhatsApp ficam iguais
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.painel_da_kamell(date '2026-11-05', 'oc', false);
      update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}', modo_fornecedor = 'ligado' where id;
      select concat_ws(',', (select count(*) from public.agenda_fornecedor_mensagens), (select count(*) from public.whatsapp_send_queue),
                       (select count(*) from public.agenda_cliente_mensagens), (select count(*) from public.agenda_equipe_mensagens))
        into n0;
      perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
      perform public.os_prontidao(k.service_order_id, c_hoje) from public.os_carteira(c_hoje) k;
      perform public._agenda_ver_compras(null, c_hoje);
      perform public._agenda_ver_compras('05000000-0000-4000-8000-000000000112', c_hoje);
      select concat_ws(',', (select count(*) from public.agenda_fornecedor_mensagens), (select count(*) from public.whatsapp_send_queue),
                       (select count(*) from public.agenda_cliente_mensagens), (select count(*) from public.agenda_equipe_mensagens))
        into n1;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_res := pg_temp.ok(v_res, 'F4b aprender, a prontidão da carteira e o foco compras (tudo ligado) não põem nada em fila nenhuma',
      n0 = n1, n0 || ' → ' || n1);
    perform pg_temp.gravar(v_res);
  end if;

  if v_mig = '' then
    insert into _resultado values ('F4c a migration não escreve mensagem', true, 'PULADO: sem agenda_teste.mig_fornecedor_fase6 (rode pela bancada)');
  else
    insert into _resultado values ('F4c nada na 20261029100300 escreve em fila de mensagem nem chama quem escreve',
      v_mig !~* 'insert\s+into\s+public\.(agenda_fornecedor_mensagens|whatsapp_send_queue|agenda_cliente_mensagens|agenda_equipe_mensagens)'
      and v_mig !~ '_agenda_fornecedor_registrar|_agenda_fornecedor_enfileirar|_agenda_cliente_registrar', null);
  end if;
end
$f4$;

-- ── F5. O foco compras ──────────────────────────────────────────────────────────────────────────────────
do $f5$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-10-30';
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  t0 text; t1 text; t2 text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('F5 o foco compras (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    t0 := public._agenda_ver_compras(null, c_hoje) ->> 'texto';
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    t1 := public._agenda_ver_compras(null, c_hoje) ->> 'texto';
    update public.agenda_config set modo_aprendizado = 'desligado' where id;
    t2 := public._agenda_ver_compras(null, c_hoje) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'F5a em teste, o foco compras fecha com o que a agenda mediu dos fornecedores (os de mais medidas primeiro)',
      t1 = t0 || E'\nKamell: 4 de 6 entregas no prazo; o atraso chega a 2 dias úteis (em teste).'
              || E'\nEm teste: Kamell leva até 6 dias úteis da saída da nota até a chegada (5 notas); hoje conto 4 dias úteis (padrão).'
              || E'\nCorrea: 4 de 5 entregas medidas.',
      t1);
    v_res := pg_temp.ok(v_res, 'F5b com o aprendizado desligado, o foco de antes (mesmo com as linhas medidas)', t2 = t0, t2);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f5$;

-- ── F6. As cópias, as assinaturas e as portas (em qualquer lugar) ───────────────────────────────────────
do $f6$
declare
  v_forn text := coalesce(current_setting('agenda_teste.mig_fornecedores_fase4', true), '');
  v_comp text := coalesce(current_setting('agenda_teste.mig_compras_fase4', true), '');
  v_leit text := coalesce(current_setting('agenda_teste.mig_leituras_fase4', true), '');
  v_os6  text := coalesce(current_setting('agenda_teste.mig_os_fase6', true), '');
  rc record;
begin
  insert into _resultado
  select format('F6a %s: a mesma assinatura (%s → %s), %s, volatilidade %s, definer %s, search_path fixo', r.f, r.args, r.ret, r.lang, r.vol, r.def),
         p.oid is not null and pg_get_function_identity_arguments(p.oid) = r.args and pg_get_function_result(p.oid) = r.ret
         and l.lanname = r.lang and p.provolatile = r.vol and p.prosecdef = r.def
         and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%',
         format('%s(%s) → %s, %s, %s, definer %s', p.proname, pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid),
                l.lanname, p.provolatile, p.prosecdef)
    from (values ('_agenda_prazo_do_fornecedor', 'p_fornecedor uuid', 'jsonb', 'plpgsql', 's', false, 'public._agenda_prazo_do_fornecedor(uuid)'),
                 ('os_prontidao', 'p_so_id uuid, p_hoje date', 'jsonb', 'plpgsql', 's', false, 'public.os_prontidao(uuid, date)'),
                 ('_agenda_compras_da_os', 'p_p jsonb, p_esp jsonb, p_hoje date', 'text', 'plpgsql', 's', false,
                  'public._agenda_compras_da_os(jsonb, jsonb, date)'),
                 ('_agenda_ver_compras', 'p_os uuid, p_hoje date', 'jsonb', 'plpgsql', 's', true, 'public._agenda_ver_compras(uuid, date)'),
                 ('_agenda_aprendizado_texto', 'p_item text, p_momento text, p_d jsonb', 'text', 'plpgsql', 'i', false,
                  'public._agenda_aprendizado_texto(text, text, jsonb)')) r(f, args, ret, lang, vol, def, sig)
    left join pg_proc p on p.oid = to_regprocedure(r.sig)
    left join pg_language l on l.oid = p.prolang;

  -- as portas: a leitura nova para authenticated e service_role; o passo para ninguém; as recriadas como antes; nunca anon
  insert into _resultado
  select format('F6b %s: %s', f, quem),
         not has_function_privilege('anon', to_regprocedure(f), 'execute')
         and has_function_privilege('authenticated', to_regprocedure(f), 'execute') = (quem = 'leitura')
         and has_function_privilege('service_role', to_regprocedure(f), 'execute') = (quem = 'leitura')
         and (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%' from pg_proc p where p.oid = to_regprocedure(f)),
         null
    from (values ('public._agenda_atraso_do_fornecedor(uuid)', 'leitura'),
                 ('public._agenda_prazo_do_fornecedor(uuid)', 'leitura'), ('public.os_prontidao(uuid, date)', 'leitura'),
                 ('public._agenda_compras_da_os(jsonb, jsonb, date)', 'leitura'), ('public._agenda_ver_compras(uuid, date)', 'leitura'),
                 ('public._agenda_aprendizado_texto(text, text, jsonb)', 'leitura'),
                 ('public._agenda_aprender_fornecedor(date, timestamptz)', 'interna')) t(f, quem);
  insert into _resultado
  select 'F6c as 2 novas: invoker (nenhuma definer nova), a leitura STABLE e o passo volátil',
         bool_and(not p.prosecdef) and bool_and(p.provolatile = case p.proname when '_agenda_aprender_fornecedor' then 'v' else 's' end),
         string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ')
    from pg_proc p where p.oid in (to_regprocedure('public._agenda_atraso_do_fornecedor(uuid)'),
                                   to_regprocedure('public._agenda_aprender_fornecedor(date, timestamptz)'));

  if v_forn = '' or v_comp = '' or v_leit = '' or v_os6 = '' then
    insert into _resultado values ('F6d as cópias', true, 'PULADO: sem agenda_teste.mig_* (rode pela bancada)');
    return;
  end if;
  for rc in
    select * from (values
      ('_agenda_prazo_do_fornecedor', 'public._agenda_prazo_do_fornecedor(uuid)', v_forn, '20261027100100'),
      ('os_prontidao', 'public.os_prontidao(uuid, date)', v_comp, '20261027100200'),
      ('_agenda_compras_da_os', 'public._agenda_compras_da_os(jsonb, jsonb, date)', v_leit, '20261027100600'),
      ('_agenda_ver_compras', 'public._agenda_ver_compras(uuid, date)', v_leit, '20261027100600'),
      ('_agenda_aprendizado_texto', 'public._agenda_aprendizado_texto(text, text, jsonb)', v_os6, '20261029100200')
    ) t(nome, assinatura, fonte, versao)
  loop
    insert into _resultado
    select format('F6d a cópia de %s (de %s) só acrescenta os blocos "-- FASE 6:"', rc.nome, rc.versao),
           pg_temp.sem_fase6(p.prosrc) = pg_temp.sem_fase6(pg_temp.corpo(rc.fonte, rc.nome))
           and cardinality(pg_temp.sem_fase6(p.prosrc)) > 5
           and (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: fim', 'g'))
               > (select count(*) from regexp_matches(pg_temp.corpo(rc.fonte, rc.nome), '-- FASE 6: fim', 'g')),
           format('%s linhas fora dos blocos; %s blocos (a fonte: %s)', cardinality(pg_temp.sem_fase6(p.prosrc)),
                  (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: fim', 'g')),
                  (select count(*) from regexp_matches(pg_temp.corpo(rc.fonte, rc.nome), '-- FASE 6: fim', 'g')))
      from pg_proc p where p.oid = rc.assinatura::regprocedure;
  end loop;
end
$f6$;

-- ── F7. Os textos do atraso e do prazo (em qualquer lugar: só a função) ─────────────────────────────────
insert into _resultado
select 'F7 ' || t.nome, public._agenda_aprendizado_texto(t.item, t.momento, t.d::jsonb) = t.espera,
       public._agenda_aprendizado_texto(t.item, t.momento, t.d::jsonb)
  from (values
    ('a1 atraso, esperando a resposta', 'fornecedor_atraso', 'foco_pergunta',
     '{"chave": "x", "calculado": 5, "n": 6, "efetivo": 2, "detalhe": {"nome": "Kamell"}}',
     'Kamell: o atraso chega a 5 dias úteis (6 entregas), e hoje conto a chegada 2 dias úteis depois do que o fornecedor diz: a troca espera a sua resposta.'),
    ('a2 atraso, travado no dia dito', 'fornecedor_atraso', 'foco_travado',
     '{"chave": "x", "calculado": 5, "n": 6, "efetivo": 0, "travado_ate": "2026-11-27", "detalhe": {"nome": "Kamell"}}',
     'Kamell: o atraso chega a 5 dias úteis (6 entregas); fico com a chegada no dia que o fornecedor diz até sex 27/11, como você decidiu.'),
    ('a3 atraso, voltou ao prazo (a ação)', 'fornecedor_atraso', 'acao',
     '{"chave": "x", "calculado": 0, "n": 6, "efetivo": 2, "detalhe": {"nome": "Kamell", "no_prazo": 5}}',
     'Kamell voltou a entregar no prazo (5 de 6 entregas): passei a contar a chegada no dia que o fornecedor diz. *desfaz aprendizado* volta.'),
    ('a4 atraso, desfeito (volta ao padrão)', 'fornecedor_atraso', 'desfeito',
     '{"chave": "x", "volta": null, "padrao": 0, "trava_dias": 28, "detalhe": {"nome": "Kamell"}}',
     'Desfeito: para Kamell volto a contar a chegada no dia que o fornecedor diz. Não troco de novo por 28 dias, salvo se o medido mudar muito.'),
    ('a5 atraso, fico com o de agora', 'fornecedor_atraso', 'fico', '{"chave": "x", "efetivo": 1, "detalhe": {"nome": "Kamell"}}',
     'Combinado: para Kamell fico com a chegada 1 dia útil depois do que o fornecedor diz. Volto a perguntar se o medido mudar muito.'),
    ('a6 atraso em teste sem atraso', 'fornecedor_atraso', 'foco_sombra',
     '{"chave": "x", "calculado": 0, "n": 5, "detalhe": {"nome": "Correa", "no_prazo": 5}}',
     'Correa: 5 de 5 entregas no prazo (em teste).'),
    ('b1 prazo, medindo', 'fornecedor_prazo', 'foco_medindo', '{"chave": "x", "n": 3, "n_min": 5, "padrao": 4, "detalhe": {"nome": "Kamell"}}',
     'Kamell: 3 de 5 notas medidas da saída até a chegada; conto 4 dias úteis (padrão).'),
    ('b2 prazo, em uso', 'fornecedor_prazo', 'foco_em_uso',
     '{"chave": "x", "em_uso": 6, "n": 5, "desde": "2026-10-30", "detalhe": {"nome": "Kamell"}}',
     'Kamell leva até 6 dias úteis da saída da nota até a chegada (5 notas): é o prazo que uso desde sex 30/10.'),
    ('b3 prazo, a pergunta', 'fornecedor_prazo', 'pergunta', '{"chave": "x", "calculado": 9, "n": 5, "efetivo": 4, "detalhe": {"nome": "Kamell"}}',
     'Medi as notas de Kamell: da saída até a chegada levam até 9 dias úteis (5 notas), e hoje eu conto 4 dias úteis. É uma troca grande.'),
    ('b4 prazo, desfeito', 'fornecedor_prazo', 'desfeito',
     '{"chave": "x", "volta": null, "padrao": 4, "trava_dias": 28, "detalhe": {"nome": "Kamell"}}',
     'Desfeito: para Kamell volto a contar 4 dias úteis da saída da nota até a chegada. Não troco de novo por 28 dias, salvo se o medido mudar muito.')
  ) t(nome, item, momento, d, espera);

insert into _resultado
select 'F7c nenhum jargão nos textos do fornecedor (P80, percentil, amostra, remessa, "du")',
       bool_and(x !~* '(p80|percentil|amostra|remessa|\mdu\M)'),
       string_agg(x, ' | ') filter (where x ~* '(p80|percentil|amostra|remessa|\mdu\M)')
  from (select public._agenda_aprendizado_texto(i, m, '{"chave": "x", "calculado": 2, "em_uso": 2, "efetivo": 0, "padrao": 0, "n": 6, "n_min": 5, "desde": "2026-10-30", "travado_ate": "2026-11-27", "trava_dias": 28, "detalhe": {"nome": "Kamell", "no_prazo": 4}}') as x
          from unnest(array['fornecedor_atraso', 'fornecedor_prazo']) i,
               unnest(array['foco_medindo', 'foco_sombra', 'foco_em_uso', 'foco_pergunta', 'foco_travado', 'acao', 'pergunta',
                            'opcao1', 'opcao2', 'opcao3', 'desfeito', 'fico']) m) t;

-- ── F8. A correção C1 (20261029100900): itens 1, 2 e 8 ───────────────────────────────────────────────────
-- (item 1) o publicado não cai pelo aprendizado: com o atraso do fornecedor em uso, o dia publicado no início pelo material de
-- antes (o do dia dito) fica — e o confirmado pelo cliente também; a data provável só encaixa o que é novo (o rev-f6 c10).
-- (item 2) a nota não ganha o atraso por cima (a previsão dela já é saída + prazo) e a entrega da nota não entra no atraso
-- (o c3). (item 8) o cadastro inativo mede pelo principal, e o prazo dele é lido como medido (o c11).
do $f8$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje    constant date := date '2026-10-30';
  c_agora   constant timestamptz := timestamptz '2026-10-30 16:05-03';
  c_nelson  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_kamell  constant text := 'dd000000-0000-4000-8000-000000000002';
  c_itajai  constant text := 'dd000000-0000-4000-8000-000000000003';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  v_fix  text;
  v_ini  date;
  v_prev date;
  v      jsonb;
  p      jsonb;
  r      jsonb;
  v_canc text;
  a      public.agenda_aprendizado;
  pf     jsonb;
  n0     int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('F8 a correção C1 do fornecedor (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;

  -- (item 1) o dia publicado pelo motor e o dia confirmado pelo cliente
  foreach v_fix in array array['publicada', 'cliente_confirmou'] loop
    begin
      execute current_setting('agenda_teste.fase6');
      perform pg_temp.painel_da_kamell(date '2026-11-10', 'oc', true);
      update public.os_material set situacao = 'a_caminho', critico = true
       where service_order_id = c_nelson and descricao like 'Painel Touch%';
      update public.agenda_config set modo_aprendizado = 'sombra' where id;
      perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
      v_ini := (public.os_prontidao(c_nelson, c_hoje) #>> '{material,inicio_mat}')::date;
      update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
      perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
      p := public.os_prontidao(c_nelson, c_hoje) -> 'material';
      -- o 1º dia publicado (antes de ligar) no início pelo material do dia dito
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, fixado_por, origem,
                                           publicada_em)
      select c_nelson, c_roberto, v_ini, t, 'turno', 'execucao', case when v_fix = 'publicada' then 'publicada' else 'fixada' end,
             case when v_fix = 'publicada' then null else v_fix end, 'motor', timestamptz '2026-10-29 16:30-03'
        from (values ('manha'), ('tarde')) tt(t);
      r := public.agenda_propor('os', null, null, array[c_nelson], '{}'::jsonb, false, 'motor', null, c_hoje,
                                timestamptz '2026-10-30 16:30-03');
      select string_agg((i ->> 'motivo') || ': ' || (i ->> 'texto'), ' | ') into v_canc
        from jsonb_array_elements(r -> 'itens') i where i ->> 'op' = 'cancelar';
      if v_fix = 'publicada' then
        v_res := pg_temp.ok(v_res, 'F8a (C1, item 1) a prontidão diz os dois inícios: pelo dia dito (inicio_mat_dito = o de teste, qua 11/11) e pela data provável (inicio_mat, 2 dias úteis depois)',
          p ->> 'inicio_mat_dito' = v_ini::text and (p ->> 'inicio_mat')::date = public.agenda_somar_du(v_ini, 2), p::text);
        v_res := pg_temp.ok(v_res, 'F8b (C1, item 1) ligado com o atraso da Kamell em uso, o dia JÁ publicado no início do dia dito não sai pelo material (nenhum "cancelar")',
          v_canc is null, coalesce(v_canc, '—'));
      else
        v_res := pg_temp.ok(v_res, 'F8c (C1, item 1) o dia confirmado pelo cliente (fixado_por cliente_confirmou) também não sai pela data provável',
          v_canc is null, coalesce(v_canc, '—'));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  -- (item 2) a previsão da nota não ganha o atraso; a da OC ganha
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    v_prev := public.agenda_somar_du(c_hoje, (public._agenda_prazo_do_fornecedor(c_kamell::uuid) ->> 'du')::int);
    perform pg_temp.painel_da_kamell(v_prev, 'nfe', true);
    update public.os_material set situacao = 'a_caminho' where service_order_id = c_nelson and descricao like 'Painel Touch%';
    v := pg_temp.item(c_nelson, 'Painel Touch', c_hoje);
    v_res := pg_temp.ok(v_res, 'F8d (C1, item 2) com o prazo medido (6) e o atraso (2) em uso, a linha da nota despachada hoje conta com o dia da nota (ter 10/11), sem o atraso por cima (sem data_dita)',
      public._agenda_aprendido('fornecedor_atraso', c_kamell) = 2 and public._agenda_prazo_do_fornecedor(c_kamell::uuid) ->> 'fonte' = 'medido'
      and v ->> 'nivel' = 'B' and v ->> 'data' = v_prev::text and not (v ? 'data_dita') and v ->> 'data_texto' = 'chega ter 10/11 (pela nota)',
      v::text);
    update public.os_material set previsao_fonte = 'oc' where service_order_id = c_nelson and descricao like 'Painel Touch%';
    v := pg_temp.item(c_nelson, 'Painel Touch', c_hoje);
    v_res := pg_temp.ok(v_res, 'F8e (C1, item 2) a mesma previsão dita pela OC continua com o atraso medido (+2 dias úteis, data_dita = o dia da OC)',
      v ->> 'data' = public.agenda_somar_du(v_prev, 2)::text and v ->> 'data_dita' = v_prev::text, v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 2) a entrega cuja 1ª previsão é a da nota não entra no atraso
  begin
    execute current_setting('agenda_teste.fase6');
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, situacao,
      fonte, fornecedor_id, previsao_ate, previsao_fonte, previsao_original, previsao_original_fonte, previsao_original_em,
      chegou_em, atualizado_em)
    values ('d6300000-0000-4000-8000-0000000000c1', '05000000-0000-4000-8000-000000000138', 'dono', 'Barramento 150A (C1)', 1, 1,
            'na_mao', 'nfe', c_kamell::uuid, date '2026-10-01', 'nfe', date '2026-10-01', 'nfe', date '2026-09-28',
            date '2026-10-08', timestamptz '2026-10-08 17:00-03');
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_atraso' and chave = c_kamell;
    v_res := pg_temp.ok(v_res, 'F8f (C1, item 2) uma entrega da Kamell com a 1ª previsão da nota (5 dias úteis depois dela) não entra no atraso: as 6 entregas e o P80 2 de sempre',
      a.n = 6 and a.calculado = 2
      and not exists (select 1 from jsonb_array_elements(a.amostra) e where e ->> 'entrega' = 'linha:d6300000-0000-4000-8000-0000000000c1'),
      to_jsonb(a)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (item 8) o cadastro inativo (a Kamell de Itajaí) com as 5 notas: mede pelo principal (a de Vila Velha)
  begin
    execute current_setting('agenda_teste.fase6');
    update public.suppliers set active = false where id = c_itajai::uuid;
    alter table public.material_remessas disable trigger user;  -- (só a simulação: as notas chegaram para o cadastro de Itajaí)
    update public.material_remessas set fornecedor_id = c_itajai::uuid where fornecedor_id = c_kamell::uuid and estado = 'chegou';
    alter table public.material_remessas enable trigger user;
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
    perform public._agenda_aprender_fornecedor(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'fornecedor_prazo' and chave = c_kamell;
    pf := public._agenda_prazo_do_fornecedor(c_itajai::uuid);
    v_res := pg_temp.ok(v_res, 'F8g (C1, item 8) as notas do cadastro inativo medem pelo principal: a chave é a Kamell de Vila Velha (6, em uso), nenhuma linha com a de Itajaí, e o prazo da de Itajaí é o medido (6)',
      a.n = 5 and a.em_uso = 6 and a.estado = 'em_uso'
      and not exists (select 1 from public.agenda_aprendizado x where x.item like 'fornecedor%' and x.chave = c_itajai)
      and pf ->> 'fonte' = 'medido' and pf ->> 'du' = '6' and pf ->> 'principal_id' = c_kamell,
      coalesce(to_jsonb(a)::text, '—') || ' / ' || pf::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f8$;

-- ── F9. A correção C2 (20261029100950): a sobra (a) da C1 ──────────────────────────────────────────────────
-- A linha do atraso do foco compras (_agenda_atraso_do_fornecedor) lê o cadastro inativo pelo principal, como a medição: a
-- Kamell de Itajaí desativada tem a linha da Kamell de Vila Velha (antes, nada: lia pelo id cru).
do $f9$
declare
  v_res jsonb := '[]'::jsonb;
  c_kamell  constant text := 'dd000000-0000-4000-8000-000000000002';
  c_itajai  constant text := 'dd000000-0000-4000-8000-000000000003';
  v  jsonb;
  w  jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('F9 a correção C2 do fornecedor (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fornecedor}' where id;
    perform public._agenda_aprender_fornecedor(date '2026-10-30', timestamptz '2026-10-30 16:05-03');
    update public.suppliers set active = false where id = c_itajai::uuid;
    v := public._agenda_atraso_do_fornecedor(c_itajai::uuid);
    w := public._agenda_atraso_do_fornecedor(c_kamell::uuid);
    v_res := pg_temp.ok(v_res, 'F9a (C2, sobra a da C1) o atraso do cadastro inativo (a Kamell de Itajaí) é lido pelo principal: a mesma linha, o mesmo em uso (2) e o id pedido, como a medição',
      v is not null and v ->> 'fornecedor_id' = c_itajai and (v ->> 'em_uso')::numeric = 2 and (v ->> 'du')::numeric = 2
      and v ->> 'texto' = w ->> 'texto' and (w ->> 'em_uso')::numeric = 2,
      coalesce(v::text, 'nulo') || ' / ' || coalesce(w::text, 'nulo'));
    update public.suppliers set active = true where id = c_itajai::uuid;
    v_res := pg_temp.ok(v_res, 'F9b (C2, sobra a da C1) o cadastro ativo sem medida (a de Itajaí de volta ao uso) não ganha a linha do outro',
      public._agenda_atraso_do_fornecedor(c_itajai::uuid) is null, coalesce(public._agenda_atraso_do_fornecedor(c_itajai::uuid)::text, 'nulo'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$f9$;
select teste, ok, detalhe from _resultado order by teste;

rollback;
