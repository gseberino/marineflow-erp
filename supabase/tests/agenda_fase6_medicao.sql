-- Prova da medição e do gravador da Agenda de Produção, Fase 6 (pacote P1; migration 20261029100100).
-- bancada: depende de 20261029100900
--
--   M1 a classe de campo: as linhas principais reais de produção (f6p1/q01_principais), byte a byte; as armadilhas (o
--      "motorhome" que não é motor, a refrigeração); a linha de maior valor e o desempate; as palavras são parâmetro; o texto
--      de cada nível
--   M2 _agenda_dias_no_inicio: a coluna, o histórico (o dono rediz depois do check-in), os de agora, o nulo (sem dias, dito só
--      depois do check-in, sem rastro)
--   M3 o congelamento: uma vez; a sugestão não congela; o que o dono rediz depois não muda o congelado
--   M4 a medida de cada OS da fixture (a classe, os dias, os meios, o fora do plano, as diárias, o só do dono, a mão de obra,
--      o fator, o motivo, a 1ª promessa, o atraso e o aviso)
--   M5 idempotência (rodar 2× = a mesma versão), a OS que mudou depois (a diária ligada) e a reaberta; o erro de uma OS não
--      derruba a medição das outras
--   M6 _agenda_percentil
--   M7 o gravador: os 6 passos, a pergunta (as opções), a trava e o fim dela, o leitor nulo fora de ligado, os textos do fator
--   M9 (correção C1, 20261029100900) a conclusão sem check-out (a porta, senão sem_fim, e tocar a OS não a move); a medição
--      olha de novo só a janela, a reaberta e a que mudou
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_medicao.sql
--   Seguro em produção: tudo dentro de begin/rollback. M1, M6 e M7 usam linhas próprias ("TESTE AG6"); M2 a M5 rodam só na
--   bancada (a fixture-fase6; fora dela, PULADO).
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

-- O erro de um comando: 'erro <estado>: <mensagem>', ou 'aceitou'.
create function pg_temp.erro(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'aceitou';
exception when others then
  return 'erro ' || sqlstate || ': ' || sqlerrm;
end $f$;

-- A OS de teste com o bem e a linha principal dados (para a classe sem a fixture).
create function pg_temp.os_da_classe(p_n int, p_bem text, p_linhas jsonb) returns uuid language plpgsql as $f$
declare
  v_os uuid := ('d6000000-0000-4000-8000-0000000002' || lpad(p_n::text, 2, '0'))::uuid;
  e jsonb;
  k int := 0;
begin
  insert into public.vessels (id, client_id, name, asset_type)
  values (v_os, 'd6000000-0000-4000-8000-0000000000e1', 'TESTE AG6 bem', p_bem);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status)
  values (v_os, 'OS-TESTE-AG6-' || p_n, 'd6000000-0000-4000-8000-0000000000e1', v_os, 'open');
  for e in select x from jsonb_array_elements(p_linhas) x loop
    k := k + 1;
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at)
    values (v_os, e ->> 0, 'visit', 1, (e ->> 1)::numeric, (e ->> 1)::numeric,
            timestamptz '2026-10-01 12:00-03' + make_interval(secs => coalesce((e ->> 2)::int, k)));
  end loop;
  return v_os;
end $f$;

insert into public.clients (id, type, name) values ('d6000000-0000-4000-8000-0000000000e1', 'individual', 'TESTE AG6 Cliente');

-- ── M1. A classe de campo ───────────────────────────────────────────────────────────────────────────────
do $m1$
declare
  v_res jsonb := '[]'::jsonb;
  r record;
  v jsonb;
  v_os uuid;
  v_det text := '';
  v_ok boolean := true;
begin
  begin
    -- As linhas principais de produção (SELECT de 28/10, f6p1/q01_principais), com o tipo do bem de cada uma.
    for r in select * from (values
      (1, 'Motorhome', '[["Instalação 2x Carregador DC/DC 50A", 690]]', 'rv:energia', 'energia em motorhome'),
      (2, 'Motorhome', '[["DIAGNÓSTICO TÉCNICO NO LOCAL", 250]]', 'rv:diagnostico', 'diagnóstico em motorhome'),
      (3, 'Lancha', '[["AJUSTE DE LIGAÇÃO ELÉTRICA DE CARREGADOR DE BATERIAS", 450]]', 'barco:energia', 'energia em barco'),
      (4, 'Lancha', '[["DIAGNÓSTICO REPARAÇÃO TÉCNICA DE MÓDULOS ELETRÔNICOS SEAKEEPER", 1800]]', 'barco:diagnostico', 'diagnóstico em barco'),
      (5, 'Lancha', '[["Posicionamento, alinhamento, base, coxins e fixação do gerador", 2400]]', 'barco:motor', 'motor e gerador em barco'),
      (6, 'Motorhome', '[["Mão de obra - Substituição de conector e emenda no cabo de dados Starlink", 300]]', 'rv:conectividade', 'Starlink e eletrônicos em motorhome'),
      (7, 'Motorhome', '[["Substituição da Placa Controladora do Ar Condicionado", 900]]', 'rv:conforto', 'geladeira, ar e gás em motorhome'),
      (8, 'Camper', '[["Instalação e configuração do sistema", 600]]', 'rv:geral', 'outros serviços em motorhome'),
      (9, 'Equipamento', '[]', 'outro:geral', 'outros serviços em outro bem'),
      (10, 'Lancha', '[]', 'barco:geral', 'outros serviços em barco'),
      (11, 'Motorhome', '[["Conversão do sistema de refrigeração para 12V — Refrigerador Consul CRC28FB", 1200]]', 'rv:conforto', 'geladeira, ar e gás em motorhome'),
      (12, 'Lancha', '[["INSTALAÇÃO TÉCNICA DE PARELHA DE MOTORES MERCURY V8 300HP CMS", 7800]]', 'barco:motor', 'motor e gerador em barco'),
      (13, 'Motorhome', '[["INSTALAÇÃO DE CAMERAS DE ESTACIONAMENTO", 800]]', 'rv:conectividade', 'Starlink e eletrônicos em motorhome'),
      (14, 'Motorhome', '[["Instalação do novo sistema elétrico LiFePO4/Usina", 5200]]', 'rv:energia', 'energia em motorhome'),
      (15, 'Motorhome', '[["Barramento e proteções do sistema de corrente contínua", 2600]]', 'rv:energia', 'energia em motorhome'),
      (16, 'Motorhome', '[["RERPARO DE VAZAMENTO CLARABOIA DE TETO", 400]]', 'rv:geral', 'outros serviços em motorhome'),
      -- as armadilhas: "motorhome" não é motor; o nome do bem não conta, só o tipo
      (17, 'Motorhome', '[["Revisão geral do motorhome antes da viagem", 500]]', 'rv:geral', 'outros serviços em motorhome'),
      (18, 'Motor Home', '[["Revisão geral do motor home", 500]]', 'rv:geral', 'outros serviços em motorhome'),
      -- a linha de maior valor manda (o deslocamento é menor); no empate, a mais antiga
      (19, 'Motorhome', '[["Deslocamento técnico", 200, 1], ["Instalação de bateria de lítio", 900, 2]]', 'rv:energia', 'energia em motorhome'),
      (20, 'Motorhome', '[["Diagnóstico técnico no local", 250, 1], ["Instalação de inversor", 250, 2]]', 'rv:diagnostico', 'diagnóstico em motorhome'),
      (21, 'Motorhome', '[["Instalação de inversor", 250, 1], ["Diagnóstico técnico no local", 250, 2]]', 'rv:energia', 'energia em motorhome')
    ) as t(n, bem, linhas, chave, texto)
    loop
      -- (em dois comandos: a leitura STABLE não enxerga o que o mesmo comando acabou de gravar)
      v_os := pg_temp.os_da_classe(r.n, r.bem, r.linhas::jsonb);
      v := public._agenda_classe_de_campo(v_os);
      if v ->> 'chave' is distinct from r.chave or v ->> 'texto' is distinct from r.texto then
        v_ok := false;
        v_det := v_det || format('[%s %s: %s / %s] ', r.n, r.bem, v ->> 'chave', v ->> 'texto');
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'M1a as 16 linhas principais de produção e as 5 armadilhas: a classe e o texto byte a byte', v_ok, nullif(v_det, ''));
    v_res := pg_temp.ok(v_res, 'M1b a OS que não existe não tem classe',
      public._agenda_classe_de_campo('d6000000-0000-4000-8000-0000000002ff') is null);

    -- As palavras são parâmetro: a ordem e a lista de agenda_config mandam.
    update public.agenda_config set classe_sistemas = '[["energia","carregador|bateria"],["diagnostico","diagnost"]]' where id;
    v_res := pg_temp.ok(v_res, 'M1c as palavras são parâmetro: com energia antes de diagnóstico e só "carregador|bateria", a Seakeeper continua diagnóstico, o carregador é energia e o gerador vira outros serviços',
      public._agenda_classe_de_campo('d6000000-0000-4000-8000-000000000204') ->> 'chave' = 'barco:diagnostico'
      and public._agenda_classe_de_campo('d6000000-0000-4000-8000-000000000203') ->> 'chave' = 'barco:energia'
      and public._agenda_classe_de_campo('d6000000-0000-4000-8000-000000000205') ->> 'chave' = 'barco:geral'
      and public._agenda_classe_de_campo('d6000000-0000-4000-8000-000000000220') ->> 'chave' = 'rv:diagnostico');
    update public.agenda_config set classe_bens = '[["barco","lancha"]]' where id;
    v_res := pg_temp.ok(v_res, 'M1d sem rv na lista dos bens, o motorhome é outro bem',
      public._agenda_classe_de_campo('d6000000-0000-4000-8000-000000000201') ->> 'texto' = 'energia em outro bem');

    v_res := pg_temp.ok(v_res, 'M1e o texto de cada nível',
      public._agenda_classe_texto_do_nivel('rv:energia') = 'as OS de energia em motorhome'
      and public._agenda_classe_texto_do_nivel('sistema:energia') = 'as OS de energia'
      and public._agenda_classe_texto_do_nivel('bem:rv') = 'as OS em motorhome'
      and public._agenda_classe_texto_do_nivel('todas') = 'as OS'
      and public._agenda_classe_texto_do_nivel('rv:geral') = 'as OS de outros serviços em motorhome'
      and public._agenda_classe_texto_do_nivel('sistema:motor') = 'as OS de motor e gerador'
      and public._agenda_classe_texto_do_nivel('bem:outro') = 'as OS em outro bem'
      and public._agenda_classe_texto_do_nivel('dono') is null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m1$;

-- ── M2 a M5: com a fixture-fase6 ────────────────────────────────────────────────────────────────────────
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-000000000' || p_n)::uuid
$f$;

do $m2$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-30';
  v jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('M2 os dias ditos no início (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    v_res := pg_temp.ok(v_res, 'M2a os de agora, ditos antes do check-in (131: 1 dia, dono; 132: 1, aceita)',
      public._agenda_dias_no_inicio(pg_temp.os('131')) = '{"em": "2026-09-08", "dias": 1.0, "fonte": "dono", "origem": "atual"}'
      and public._agenda_dias_no_inicio(pg_temp.os('132')) = '{"em": "2026-09-09", "dias": 1.0, "fonte": "aceita", "origem": "atual"}',
      public._agenda_dias_no_inicio(pg_temp.os('131'))::text);
    v := public._agenda_dias_no_inicio(pg_temp.os('133'));
    v_res := pg_temp.ok(v_res, 'M2b o histórico: o dono disse 2 em 10/09 e rediz 3 em 17/09, depois do check-in de 15/09 → 2',
      v = '{"em": "2026-09-15", "dias": 2, "fonte": "dono", "origem": "historico"}', v::text);
    v_res := pg_temp.ok(v_res, 'M2c sem planejamento (141, só a sugerida): nulo',
      public._agenda_dias_no_inicio(pg_temp.os('141')) is null);
    -- dito só depois do check-in, sem rastro no histórico
    update public.os_planejamento set estimativa_em = timestamptz '2026-09-11 10:00-03' where service_order_id = pg_temp.os('138');
    -- dito só depois do check-in, com o histórico dizendo de onde veio
    update public.os_planejamento
       set historico = '[{"em": "2026-09-09", "antes": {"dias": null, "estimativa_fonte": null}, "depois": {"dias": 1, "estimativa_fonte": "dono"}}]'
     where service_order_id = pg_temp.os('131');
    v_res := pg_temp.ok(v_res, 'M2d dito só depois do check-in (sem rastro, e com o histórico): nulo',
      public._agenda_dias_no_inicio(pg_temp.os('138')) is null and public._agenda_dias_no_inicio(pg_temp.os('131')) is null);
    update public.os_planejamento set dias_no_inicio = 1.5, dias_no_inicio_fonte = 'aceita', dias_no_inicio_em = date '2026-09-10'
     where service_order_id = pg_temp.os('138');
    v_res := pg_temp.ok(v_res, 'M2e a coluna congelada vale primeiro',
      public._agenda_dias_no_inicio(pg_temp.os('138')) = '{"em": "2026-09-10", "dias": 1.5, "fonte": "aceita", "origem": "coluna"}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m2$;

do $m3$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-30';
  r1 jsonb;
  r2 jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('M3 o congelamento (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    r1 := public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'M3a congela as 13 OS com dias do dono (ou aceitos) e conta as 4 sem dias (141 e as 3 da fixture-fase5)',
      r1 = '{"congeladas": 13, "sem_dias": 4}', r1::text);
    v_res := pg_temp.ok(v_res, 'M3b o congelado: 133 com os 2 do início (não os 3 de agora), 132 aceita; 141 sem nada',
      (select dias_no_inicio = 2 and dias_no_inicio_fonte = 'dono' and dias_no_inicio_em = date '2026-09-15' and dias = 3
         from public.os_planejamento where service_order_id = pg_temp.os('133'))
      and (select dias_no_inicio_fonte = 'aceita' from public.os_planejamento where service_order_id = pg_temp.os('132'))
      and not exists (select 1 from public.os_planejamento where service_order_id = pg_temp.os('141')));
    -- o dono rediz os dias da 131 depois: o congelado fica, e a medida usa ele
    update public.os_planejamento set dias = 2, estimativa_em = timestamptz '2026-10-30 10:00-03',
           historico = historico || '[{"em": "2026-10-30", "antes": {"dias": 1}, "depois": {"dias": 2}}]'::jsonb
     where service_order_id = pg_temp.os('131');
    r2 := public._agenda_aprender_congelar(c_hoje);
    perform public.agenda_medir_os(pg_temp.os('131'), c_hoje);
    v_res := pg_temp.ok(v_res, 'M3c uma vez só: a 2ª rodada não congela nada; o que o dono rediz depois não muda o congelado nem a medida',
      r2 = '{"congeladas": 0, "sem_dias": 4}'
      and (select dias_no_inicio = 1 from public.os_planejamento where service_order_id = pg_temp.os('131'))
      and (select meios_planejados = 2 and dias_no_inicio = 1 and fator = 1.00 from public.agenda_medidas_os
            where service_order_id = pg_temp.os('131')),
      r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m3$;

do $m3d$
declare
  v_res jsonb := '[]'::jsonb;
  r1 jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    -- a rodada de qua 09/09 só vê o check-in até aquele dia: a 131 e a 132 (e a OS-00123 da fixture-fase5, sem dias)
    r1 := public._agenda_aprender_congelar(date '2026-09-09');
    v_res := pg_temp.ok(v_res, 'M3d só o que teve check-in até o dia da rodada: em 09/09, a 131 e a 132 (a OS-00123, sem dias)',
      r1 = '{"congeladas": 2, "sem_dias": 1}'
      and (select count(*) from public.os_planejamento where dias_no_inicio is not null) = 2, r1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m3d$;

do $m4$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-30';
  r record;
  v_det text := '';
  v_ok boolean := true;
  v_n int := 0;
  v_tem text;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('M4 a medida de cada OS (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform public.agenda_medir_os(so.id, c_hoje) from public.service_orders so where so.status in ('completed', 'invoiced');
    -- classe | dias fonte | planejados cumpridos fora sem_registro | diárias | só o dono | mo | fator | motivo |
    -- 1ª promessa atraso | avisos faixa estouro
    for r in select * from (values
      ('131', 'rv:energia|1.0 dono|2 2.0 0 0|1.00|f|690.00|1.00|-|2026-09-08 0|0 - -'),
      ('132', 'rv:energia|1.0 aceita|2 2.0 0 0|1.00|f|690.00|1.00|-|2026-09-10 -1|0 - -'),
      ('133', 'rv:energia|2.0 dono|4 5.0 0 0|3.00|f|2070.00|1.25|-|2026-09-18 -1|1 2026-09-15 2'),
      ('134', 'rv:energia|1.0 dono|2 3.0 0 0|1.50|f|1035.00|1.50|-|2026-10-21 -1|1 2026-10-20 0'),
      ('135', 'rv:energia|2.0 dono|4 6.0 0 0|4.00|f|2760.00|1.50|-|2026-10-21 2|1 2026-10-21 2'),
      ('136', 'rv:energia|2.0 dono|4 7.0 0 0|4.00|f|2760.00|1.75|-|2026-10-30 -1|1 2026-10-27 2'),
      ('137', 'rv:energia|1.0 dono|2 4.0 2 0|2.00|f|1380.00|2.00|-|2026-10-23 2|2 2026-10-26 1'),
      ('138', 'barco:motor|1.0 dono|2 2.0 0 0|1.00|f|2400.00|1.00|-|- -|0 - -'),
      ('139', 'barco:motor|1.0 dono|2 3.0 0 0|2.00|f|7800.00|1.50|-|- -|0 - -'),
      ('140', 'rv:diagnostico|1.0 dono|2 2.0 0 0|0.00|t|250.00|1.00|-|- -|0 - -'),
      ('141', 'rv:geral|1.0 sugerida|2 2.0 0 0|1.00|f|1380.00|-|dias_sugeridos|- -|0 - -'),
      ('142', 'barco:energia|1.0 dono|2 1.0 0 1|1.00|f|450.00|-|conferencia_incompleta|- -|0 - -'),
      ('143', 'outro:geral|1.0 dono|2 2.0 0 0|0.00|f|600.00|-|sem_diaria|- -|0 - -'),
      ('144', 'rv:conforto|1.0 dono|2 2.0 0 0|1.00|f|900.00|1.00|-|- -|0 - -'),
      -- as concluídas das fixtures de antes: sem dias ditos nem plano
      ('050', 'barco:energia|1.5 sugerida|3 0.0 0 0|0.00|f|3000.00|-|sem_inicio|- -|0 - -'),
      ('121', 'rv:geral|- -|- 0.0 0 0|0.00|f|0.00|-|sem_dias_no_inicio|- -|0 - -'),
      ('122', 'barco:geral|- -|- 0.0 0 0|0.00|f|0.00|-|sem_dias_no_inicio|- -|0 - -'),
      ('123', 'barco:geral|- -|- 0.0 0 0|0.00|f|0.00|-|sem_dias_no_inicio|- -|0 - -')
    ) as t(n, espera)
    loop
      select format('%s:%s|%s %s|%s %s %s %s|%s|%s|%s|%s|%s|%s %s|%s %s %s',
                    m.classe_bem, m.classe_sistema, coalesce(m.dias_no_inicio::text, '-'), coalesce(m.dias_fonte, '-'),
                    coalesce(m.meios_planejados::text, '-'), m.meios_cumpridos, m.meios_fora_do_plano, m.meios_sem_registro,
                    m.diarias_ligadas, case when m.so_o_dono then 't' else 'f' end, coalesce(m.mo::text, '-'),
                    coalesce(m.fator::text, '-'), coalesce(m.motivo, '-'),
                    coalesce(m.prometido_primeiro_ate::text, '-'), coalesce(m.atraso_cliente_du::text, '-'),
                    m.avisos_enviados, coalesce(m.aviso_faixa_ate::text, '-'), coalesce(m.aviso_estouro_du::text, '-'))
        into v_tem
        from public.agenda_medidas_os m
       where m.service_order_id = ('05000000-0000-4000-8000-000000000' || lpad(r.n, 3, '0'))::uuid;
      v_n := v_n + 1;
      if v_tem is distinct from r.espera then
        v_ok := false;
        v_det := v_det || format('[%s: %s] ', r.n, coalesce(v_tem, 'sem medida'));
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'M4a a medida de cada uma das 18 OS concluídas (as 14 da Fase 6 e as 4 de antes), coluna a coluna',
      v_ok and v_n = 18, nullif(v_det, ''));
    v_res := pg_temp.ok(v_res, 'M4b a válida tem o fator e nenhum motivo; a inválida, o motivo e nenhum fator; a concluída e a entrega em Brasília',
      (select bool_and((valida and fator is not null and motivo is null) or (not valida and fator is null and motivo is not null))
         from public.agenda_medidas_os)
      and (select concluida_em = date '2026-09-17' and entregue_em = date '2026-09-18' from public.agenda_medidas_os
            where service_order_id = pg_temp.os('133'))
      and (select count(*) filter (where valida) = 11 from public.agenda_medidas_os));
    v_res := pg_temp.ok(v_res, 'M4c o P80 das 7 de energia em motorhome é 1,70 (o "hoje seria 1,7×" da spec)',
      (select public._agenda_percentil(array_agg(fator), 0.80) from public.agenda_medidas_os
        where classe_bem = 'rv' and classe_sistema = 'energia' and valida) = 1.70);
    v_res := pg_temp.ok(v_res, 'M4d o R$ por diária das 7 de energia: R$ 11.385 de mão de obra ÷ 16,5 diárias = R$ 690',
      (select sum(mo) / sum(diarias_ligadas) from public.agenda_medidas_os
        where classe_bem = 'rv' and classe_sistema = 'energia' and valida) = 690);
    v_res := pg_temp.ok(v_res, 'M4e a pontualidade e a folga: 5 de 7 no prazo da 1ª promessa; os estouros da faixa 0, 1, 2, 2 e 2 (P80 2; a correção C1 pôs a faixa da 136 até 27/10 na fixture: com 26/10, 2,2)',
      (select count(*) filter (where atraso_cliente_du <= 0) = 5 and count(*) = 7
         from public.agenda_medidas_os where prometido_primeiro_ate is not null)
      and (select public._agenda_percentil(array_agg(aviso_estouro_du), 0.80) = 2
                  and string_agg(aviso_estouro_du::text, ',' order by aviso_estouro_du) = '0,1,2,2,2'
             from public.agenda_medidas_os where aviso_estouro_du is not null));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m4$;

do $m5$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-30';
  r1 jsonb;
  r2 jsonb;
  v  jsonb;
  m  public.agenda_medidas_os;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('M5 idempotência e a reaberta (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    r1 := public._agenda_aprender_medir(c_hoje);
    r2 := public._agenda_aprender_medir(c_hoje);
    v_res := pg_temp.ok(v_res, 'M5a a 1ª rodada mede as 18 concluídas da janela (11 valem); a 2ª não grava nada (as mesmas versões)',
      r1 = '{"olhadas": 18, "medidas": 18, "validas": 11, "erros": 0, "invalidas": {"sem_diaria": 1, "sem_inicio": 1, "dias_sugeridos": 1, "sem_dias_no_inicio": 3, "conferencia_incompleta": 1}}'
      and r2 ->> 'medidas' = '0' and r2 ->> 'olhadas' = '18'
      and (select bool_and(versao = 1 and historico = '[]') from public.agenda_medidas_os),
      r1::text || ' / ' || r2::text);
    v := public.agenda_medir_os(pg_temp.os('144'), c_hoje);
    v_res := pg_temp.ok(v_res, 'M5b medir de novo a mesma OS não muda nada',
      v ->> 'mudou' = 'false' and v ->> 'versao' = '1', v::text);

    -- A OS que mudou depois: a diária do Roberto de 25/09 é ligada à 143 → a medida passa a valer (versão 2).
    insert into public.work_shift_os (shift_id, service_order_id)
    values (md5('ws:cc000000-0000-4000-8000-000000000002:2026-09-25')::uuid, pg_temp.os('143'));
    r1 := public._agenda_aprender_medir(c_hoje);
    select * into m from public.agenda_medidas_os where service_order_id = pg_temp.os('143');
    v_res := pg_temp.ok(v_res, 'M5c a diária ligada depois: a rodada mede a 143 de novo (só ela), que passa a valer com o fator 1,00; o histórico guarda o de antes',
      r1 ->> 'medidas' = '1' and m.versao = 2 and m.valida and m.fator = 1.00 and m.diarias_ligadas = 1
      and m.historico -> 0 ->> 'em' = '2026-10-30' and m.historico -> 0 ->> 'versao' = '1'
      and m.historico #>> '{0,antes,motivo}' = 'sem_diaria' and m.historico #> '{0,depois,motivo}' = 'null'::jsonb,
      to_jsonb(m)::text);

    -- A reaberta: a 144 volta de concluída (pela porta) → a medida seguinte não vale (motivo reaberta), e guarda a conclusão.
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set status = 'in_progress', check_out_at = null, delivered_at = null where id = pg_temp.os('144');
    perform set_config('agenda.porta', 'off', true);
    r1 := public._agenda_aprender_medir(c_hoje);
    select * into m from public.agenda_medidas_os where service_order_id = pg_temp.os('144');
    v_res := pg_temp.ok(v_res, 'M5d a reaberta: a rodada a mede (tem medida), a medida fica inválida (reaberta, sem fator, versão 2) e guarda a conclusão de 28/09',
      r1 ->> 'medidas' = '1' and not m.valida and m.motivo = 'reaberta' and m.fator is null and m.versao = 2
      and m.concluida_em = date '2026-09-28' and m.historico #>> '{0,antes,fator}' = '1.00',
      to_jsonb(m)::text);
    v_res := pg_temp.ok(v_res, 'M5e a OS aberta sem medida não é medida',
      public.agenda_medir_os('05000000-0000-4000-8000-000000000069', c_hoje) = '{"ok": true, "medida": false, "motivo": "nao_concluida"}'
      and not exists (select 1 from public.agenda_medidas_os where service_order_id = '05000000-0000-4000-8000-000000000069'));

    -- O erro de uma OS: registrado em app_error_logs (agenda / aprender:medir) e as outras medidas seguem.
    create function pg_temp.quebra_a_131() returns trigger language plpgsql as $q$
    begin
      if new.service_order_id = '05000000-0000-4000-8000-000000000131' then
        raise exception 'falha de teste na 131';
      end if;
      return new;
    end $q$;
    create trigger quebra_a_131 before update on public.agenda_medidas_os for each row execute function pg_temp.quebra_a_131();
    update public.os_planejamento set prometido_primeiro_ate = date '2026-09-09'
     where service_order_id in (pg_temp.os('131'), pg_temp.os('132'));
    r1 := public._agenda_aprender_medir(c_hoje);
    v_res := pg_temp.ok(v_res, 'M5f o erro de uma OS vai a app_error_logs (agenda / aprender:medir) e a medição das outras segue',
      r1 ->> 'erros' = '1' and r1 ->> 'medidas' = '1'
      and (select prometido_primeiro_ate = date '2026-09-09' from public.agenda_medidas_os where service_order_id = pg_temp.os('132'))
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:medir'
                    and e.message like '%OS-00131%falha de teste na 131%'),
      r1::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m5$;

-- ── M6. O percentil ─────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'M6a o percentil contínuo, em numeric exato: vazio e nulo dão nulo; 1 valor; os extremos; o meio; o P80 do fator; nulos fora',
       public._agenda_percentil('{}'::numeric[], 0.8) is null
       and public._agenda_percentil(null, 0.8) is null
       and public._agenda_percentil('{1,2}', null) is null
       and public._agenda_percentil('{3}', 0.8) = 3
       and public._agenda_percentil('{1,2}', 0.5) = 1.5
       and public._agenda_percentil('{5,1,3}', 0) = 1
       and public._agenda_percentil('{5,1,3}', 1) = 5
       and public._agenda_percentil('{2.0,1.0,1.25,1.5,1.75,1.0,1.5}', 0.80) = 1.70
       and public._agenda_percentil('{0,1,2,2,3}', 0.80) = 2.2
       and public._agenda_percentil(array[1, null, 2]::numeric[], 0.5) = 1.5
       and public._agenda_percentil('{1,2,3,4}', 0.80) = (select percentile_cont(0.80) within group (order by x)::numeric
                                                           from unnest('{1,2,3,4}'::numeric[]) x),
       public._agenda_percentil('{2.0,1.0,1.25,1.5,1.75,1.0,1.5}', 0.80)::text;
insert into _resultado
select 'M6b percentil fora de 0 a 1 é recusado (22023)',
       pg_temp.erro($q$select public._agenda_percentil('{1,2}', 1.2)$q$) like 'erro 22023:%', null;

-- ── M7. O gravador ──────────────────────────────────────────────────────────────────────────────────────
do $m7$
declare
  v_res jsonb := '[]'::jsonb;
  c_agora constant timestamptz := timestamptz '2026-10-30 16:05-03';
  v jsonb;
  a public.agenda_aprendizado;
  q public.agenda_perguntas;
  x public.agenda_acoes;
  n_acoes int;
  c_fina constant text := 'rv:energia';
  -- grava o fator da classe fina com o padrão 1,5 (estouro_fator)
  g text := $g$select public._agenda_aprendizado_gravar('fator', %L, %L, %s, %s, '[]', 1.50, '{}', %L)$g$;
begin
  begin
    update public.agenda_config set modo_aprendizado = 'desligado', aprendizado_ligados = '{}' where id;

    -- 1. poucas medidas → medindo
    execute format(g, c_fina, 'fina', 1.40, 4, c_agora) into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7a 4 de 6 medidas → medindo, nada em uso; o texto do foco (§6.2)',
      a.estado = 'medindo' and a.em_uso is null and a.n = 4 and a.n_min = 6 and a.padrao = 1.50 and a.calculado = 1.40
      and a.texto = 'As OS de energia em motorhome: 4 de 6 OS medidas; para perguntar o que falta, uso 1,5× o combinado (padrão).'
      and v ->> 'estado' = 'medindo' and v ->> 'estado_antes' = 'medindo',
      a.texto);

    -- 2. com n, mas o modo não é ligado → sombra; o mesmo com ligado e o item fora da lista
    execute format(g, c_fina, 'fina', 1.70, 7, c_agora) into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7b 7 medidas com o modo desligado → em teste (sombra): o calculado e o texto "hoje seria", nada em uso, nenhuma ação nem pergunta',
      a.estado = 'sombra' and a.em_uso is null and a.calculado = 1.70
      and a.texto = 'Em teste: as OS de energia em motorhome levam até 1,7× o combinado (7 OS); hoje seria 1,7×, e vale 1,5× (padrão).'
      and public._agenda_aprendido('fator', c_fina) is null
      and not exists (select 1 from public.agenda_acoes where tipo = 'aprendizado')
      and not exists (select 1 from public.agenda_perguntas where tipo = 'aprendizado'),
      a.texto);
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{mo}' where id;
    execute format(g, c_fina, 'fina', 1.70, 7, c_agora) into v;
    v_res := pg_temp.ok(v_res, 'M7c ligado, mas o fator fora da lista → continua em teste',
      v ->> 'estado' = 'sombra' and public._agenda_aprendido('fator', c_fina) is null, v::text);

    -- 5. ligado e na lista: 1,70 contra 1,50 (0,2 ≤ 0,3) → em uso + a ação aprendizado com *desfaz*
    update public.agenda_config set aprendizado_ligados = '{fator}' where id;
    execute format(g, c_fina, 'fina', 1.70, 7, c_agora) into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    select * into x from public.agenda_acoes where id = (v ->> 'acao_id')::uuid;
    v_res := pg_temp.ok(v_res, 'M7d troca pequena (1,5× → 1,7×) entra sozinha: em uso, o leitor devolve 1,7 e o foco diz desde quando',
      a.estado = 'em_uso' and a.em_uso = 1.70 and a.em_uso_desde = c_agora and a.acao_id = x.id
      and public._agenda_aprendido('fator', c_fina) = 1.70
      -- (correção C2, texto 1) a linha do fator em uso diz para que serve
      and a.texto = 'As OS de energia em motorhome levam até 1,7× o combinado (7 OS): uso 1,7× desde sex 30/10 para perguntar o que falta (os dias do plano continuam os que você disse).',
      a.texto);
    v_res := pg_temp.ok(v_res, 'M7e a ação: aprendizado, da vigia, executada, desfazível por 24 horas (desfazer_validade), com o antes e o depois e o texto da §6.3',
      x.tipo = 'aprendizado' and x.origem = 'vigia' and x.executada and not x.critica and x.dia = date '2026-10-30'
      and x.desfazivel_ate = c_agora + (select desfazer_validade from public.agenda_config where id)
      and x.antes = '{"item": "fator", "chave": "rv:energia", "nivel": "fina", "em_uso": null, "valor": 1.50, "estado": "sombra"}'
      and x.depois = '{"item": "fator", "chave": "rv:energia", "nivel": "fina", "em_uso": 1.70, "n": 7}'
      and x.texto = 'Aprendi com as OS concluídas: as OS de energia em motorhome levam até 1,7× o combinado (7 OS). Passei a usar 1,7× no lugar de 1,5× para perguntar o que falta. *desfaz aprendizado* volta.',
      x.texto);

    -- 4. o mesmo medido no dia seguinte → fica (nenhuma ação nova; o "desde" não muda)
    execute format(g, c_fina, 'fina', 1.70, 7, c_agora + interval '1 day') into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    select count(*) into n_acoes from public.agenda_acoes where tipo = 'aprendizado';
    v_res := pg_temp.ok(v_res, 'M7f o mesmo medido → fica em uso, sem ação nova e com o mesmo "desde"',
      a.estado = 'em_uso' and n_acoes = 1 and a.em_uso_desde = c_agora and v ->> 'acao_id' is null, v::text);

    -- 6. troca grande: 2,10 contra 1,70 (0,4 > 0,3) → pergunta crítica; o 1,7 continua valendo
    execute format(g, c_fina, 'fina', 2.10, 8, c_agora + interval '2 days') into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    select * into q from public.agenda_perguntas where id = a.pergunta_id;
    v_res := pg_temp.ok(v_res, 'M7g troca grande (1,7× → 2,1×) vira pergunta crítica; enquanto isso vale o 1,7 (o leitor devolve 1,7)',
      a.estado = 'pergunta' and a.em_uso = 1.70 and public._agenda_aprendido('fator', c_fina) = 1.70
      and q.tipo = 'aprendizado' and q.critica and q.estado = 'aberta' and q.modo = 'ligado'
      and q.chave = 'aprendizado:fator:rv:energia' and q.recomendacao = 1 and jsonb_array_length(q.opcoes) = 3
      and q.texto = 'Medi as OS de energia em motorhome: levam até 2,1× o combinado (8 OS), e hoje eu uso 1,7×. É uma troca grande. 1) Passo a usar 2,1× (recomendo); 2) Fico com 1,7×; 3) Volto ao padrão.'
      and a.texto = 'As OS de energia em motorhome levam até 2,1× o combinado (8 OS), e hoje uso 1,7×: a troca espera a sua resposta.',
      q.texto);
    v_res := pg_temp.ok(v_res, 'M7h as opções da pergunta dizem o efeito (1 usa o medido, 2 trava nele, 3 volta ao padrão)',
      q.opcoes = '[{"n": 1, "texto": "Passo a usar 2,1×", "efeito": {"em_uso": 2.10}}, {"n": 2, "texto": "Fico com 1,7×", "efeito": {"travar": 2.10}}, {"n": 3, "texto": "Volto ao padrão", "efeito": {"em_uso": null}}]',
      q.opcoes::text);
    execute format(g, c_fina, 'fina', 2.10, 8, c_agora + interval '3 days') into v;
    v_res := pg_temp.ok(v_res, 'M7i o mesmo medido grande no dia seguinte: a mesma pergunta (uma aberta por chave)',
      (select count(*) from public.agenda_perguntas where tipo = 'aprendizado') = 1 and (v ->> 'pergunta_id')::uuid = q.id);
    execute format(g, c_fina, 'fina', 2.20, 9, c_agora + interval '4 days') into v;
    v_res := pg_temp.ok(v_res, 'M7j o medido grande mudou (2,2×): a pergunta velha é resolvida e abre outra com o número novo',
      (select estado = 'resolvida' and resolvida_motivo like 'O medido mudou%' from public.agenda_perguntas where id = q.id)
      and (select texto like 'Medi as OS de energia em motorhome: levam até 2,2× o combinado (9 OS)%' and estado = 'aberta'
             from public.agenda_perguntas where id = (v ->> 'pergunta_id')::uuid)
      and (select count(*) from public.agenda_perguntas where tipo = 'aprendizado' and estado = 'aberta') = 1);

    -- o medido voltou para perto do que vale (1,80 contra 1,70) → em uso, ação, a pergunta resolvida sozinha
    execute format(g, c_fina, 'fina', 1.80, 9, c_agora + interval '5 days') into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7k o medido voltou para dentro do limite (1,8×): entra sozinho e a pergunta aberta é resolvida',
      a.estado = 'em_uso' and a.em_uso = 1.80 and v ->> 'acao_id' is not null
      and not exists (select 1 from public.agenda_perguntas where tipo = 'aprendizado' and estado = 'aberta'));

    -- 3. a trava (o que o *desfaz* do P6 grava): volta a 1,70, travado até 27/11 no 1,80 recusado
    update public.agenda_aprendizado set estado = 'travado', em_uso = 1.70, travado_ate = date '2026-11-27', travado_valor = 1.80
     where item = 'fator' and chave = c_fina;
    execute format(g, c_fina, 'fina', 1.90, 9, c_agora + interval '6 days') into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7l travado e o medido andou pouco do recusado (1,8 → 1,9): fica travado, vale o 1,7',
      a.estado = 'travado' and a.em_uso = 1.70 and a.travado_ate = date '2026-11-27' and a.travado_valor = 1.80
      and public._agenda_aprendido('fator', c_fina) = 1.70
      and a.texto = 'As OS de energia em motorhome levam até 1,9× o combinado (9 OS); fico com 1,7× até sex 27/11, como você decidiu.',
      a.texto);
    execute format(g, c_fina, 'fina', 2.20, 9, c_agora + interval '7 days') into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7m o medido andou mais que o limite a partir do recusado (1,8 → 2,2): destrava e, grande contra o 1,7, pergunta',
      a.estado = 'pergunta' and a.em_uso = 1.70 and a.travado_ate is null and a.travado_valor is null, v::text);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where tipo = 'aprendizado' and estado = 'aberta';
    update public.agenda_aprendizado set estado = 'travado', em_uso = 1.70, travado_ate = date '2026-11-05', travado_valor = 2.20
     where item = 'fator' and chave = c_fina;
    execute format(g, c_fina, 'fina', 1.90, 9, timestamptz '2026-11-06 16:05-03') into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7n a trava venceu (05/11): o medido 1,9 contra o 1,7 é troca pequena e entra sozinho',
      a.estado = 'em_uso' and a.em_uso = 1.90 and v ->> 'acao_id' is not null, v::text);

    -- o modo em sombra devolve o padrão na hora (o leitor confere o modo), sem regravar; tirar da lista também
    update public.agenda_config set modo_aprendizado = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'M7o modo em sombra: o leitor devolve nulo (o padrão) na hora, a linha ainda em uso',
      public._agenda_aprendido('fator', c_fina) is null
      and (select estado = 'em_uso' from public.agenda_aprendizado where item = 'fator' and chave = c_fina));
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{mo}' where id;
    execute format(g, c_fina, 'fina', 1.90, 9, timestamptz '2026-11-07 16:05-03') into v;
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7p o item saiu da lista: na rodada seguinte a linha volta a sombra, sem nada em uso',
      a.estado = 'sombra' and a.em_uso is null and a.em_uso_desde is null and public._agenda_aprendido('fator', c_fina) is null);
    update public.agenda_config set aprendizado_ligados = '{fator}' where id;
    execute format(g, c_fina, 'fina', 1.90, 5, timestamptz '2026-11-08 16:05-03') into v;
    v_res := pg_temp.ok(v_res, 'M7q menos medidas que o mínimo (a janela cortou): medindo, nada em uso',
      v ->> 'estado' = 'medindo' and v -> 'em_uso' = 'null'::jsonb);

    -- troca grande a partir do padrão: só 2 opções (o que vale já é o padrão)
    execute format(g, 'bem:barco', 'bem', 2.10, 6, c_agora) into v;
    select * into q from public.agenda_perguntas where id = (v ->> 'pergunta_id')::uuid;
    v_res := pg_temp.ok(v_res, 'M7r troca grande a partir do padrão (1,5× → 2,1×): só as opções 1 e 2, e nada em uso',
      v ->> 'estado' = 'pergunta' and v -> 'em_uso' = 'null'::jsonb and jsonb_array_length(q.opcoes) = 2
      and q.texto = 'Medi as OS em barco: levam até 2,1× o combinado (6 OS), e hoje eu uso 1,5×. É uma troca grande. 1) Passo a usar 2,1× (recomendo); 2) Fico com 1,5×.',
      q.texto);
    -- igual ao padrão, sem nada em uso → em uso em silêncio (nada muda, nenhuma ação)
    select count(*) into n_acoes from public.agenda_acoes where tipo = 'aprendizado';
    execute format(g, 'todas', 'todas', 1.50, 11, c_agora) into v;
    v_res := pg_temp.ok(v_res, 'M7s o medido igual ao padrão → em uso sem ação (nada muda para ninguém)',
      v ->> 'estado' = 'em_uso' and (v ->> 'em_uso')::numeric = 1.50
      and (select count(*) from public.agenda_acoes where tipo = 'aprendizado') = n_acoes);

    -- a pontualidade com o cliente é só medida: com o modo ligado e tudo na lista, nunca passa de sombra
    update public.agenda_config set aprendizado_ligados = '{fator,mo,presenca,fornecedor,capacidade_dono,aviso_cliente,revisao}' where id;
    v := public._agenda_aprendizado_gravar('cliente_pontualidade', 'todas', 'todas', 0.71, 7, '[]', null, '{"no_prazo": 5}', c_agora);
    v_res := pg_temp.ok(v_res, 'M7t a pontualidade com o cliente nunca é usada: sombra mesmo com tudo ligado',
      v ->> 'estado' = 'sombra' and public._agenda_aprendido('cliente_pontualidade', 'todas') is null, v::text);
    -- a carga de todos sempre pergunta, só com 2 opções
    v := public._agenda_aprendizado_gravar('carga', 'todas', 'todas', 0.70, 3, '[]', 0.80, '{}', c_agora);
    v_res := pg_temp.ok(v_res, 'M7u a carga de todos (revisão) sempre pergunta, com 1 e 2 só',
      v ->> 'estado' = 'pergunta'
      and (select jsonb_array_length(opcoes) = 2 from public.agenda_perguntas where id = (v ->> 'pergunta_id')::uuid), v::text);

    -- o histórico guarda {em, antes, depois} de em uso, estado e calculado
    select * into a from public.agenda_aprendizado where item = 'fator' and chave = c_fina;
    v_res := pg_temp.ok(v_res, 'M7v o histórico: uma entrada por mudança de em uso, estado ou calculado (até 20), com {em, antes, depois}',
      jsonb_array_length(a.historico) between 10 and 20
      and (select bool_and(e ? 'em' and e ? 'antes' and e ? 'depois'
                           and (select bool_and(k in ('em_uso', 'estado', 'calculado')) from jsonb_object_keys(e -> 'antes') k))
             from jsonb_array_elements(a.historico) e)
      and a.historico #>> '{0,depois,calculado}' = '1.40' and a.historico #> '{0,antes,calculado}' = 'null'::jsonb,
      jsonb_array_length(a.historico)::text || ': ' || (a.historico -> 0)::text);

    -- as portas do gravador: o nível muda → recusa; item que não existe → recusa
    v_res := pg_temp.ok(v_res, 'M7w a chave não muda de nível; item que não existe é recusado (22023)',
      pg_temp.erro($q$select public._agenda_aprendizado_gravar('fator', 'rv:energia', 'todas', 1.7, 7, '[]', 1.5, '{}', now())$q$) like 'erro 22023:%nível%'
      and pg_temp.erro($q$select public._agenda_aprendizado_gravar('comissao', 'todas', 'todas', 1.7, 7, '[]', 1.5, '{}', now())$q$) like 'erro 22023:%desconhecido%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m7$;

-- ── M9. A correção C1 (20261029100900): item 9 e regressão B5 ────────────────────────────────────────────
-- (item 9) a OS concluída sem check-out: a conclusão é o 1º instante em que a porta a deixou concluída; sem ele, a medida não
-- vale (sem_fim) e a data fica a já medida — tocar a OS (faturar em 19/11) não a move (o rev-f6 c8). (B5) a medição olha de
-- novo só a OS da janela, a reaberta e a que mudou depois de medida: a medida de fora da janela que não mudou não é olhada.
do $m9$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-30';
  r1 jsonb;
  r2 jsonb;
  v  jsonb;
  m  public.agenda_medidas_os;
  n_janela int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('M9 a correção C1 da medição (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase6');
    perform public._agenda_aprender_medir(c_hoje);
    -- a OS-00131 (concluída 08/09) sem check-out, faturada (tocada) em 19/11
    alter table public.service_orders disable trigger user;  -- (só a simulação: o check-out sumido, a edição de 19/11)
    update public.service_orders set check_out_at = null, delivered_at = null, updated_at = timestamptz '2026-11-19 10:00-03'
     where id = pg_temp.os('131');
    alter table public.service_orders enable trigger user;
    v := public.agenda_medir_os(pg_temp.os('131'), date '2026-11-20');
    select * into m from public.agenda_medidas_os where service_order_id = pg_temp.os('131');
    v_res := pg_temp.ok(v_res, 'M9a (C1, item 9) sem check-out e sem a conclusão na porta, a medida não vale (sem_fim) e a conclusão continua 08/09 (tocar a OS não a move; antes ia a 19/11, com 50 dias úteis de atraso ao cliente)',
      m.concluida_em = date '2026-09-08' and m.motivo = 'sem_fim' and not m.valida and m.fator is null
      and m.atraso_cliente_du = 0, to_jsonb(m)::text);
    -- a OS-00132 (concluída 09/09) sem check-out, mas com a conclusão pela porta (qua 09/09 17:30)
    alter table public.service_orders disable trigger user;
    update public.service_orders set check_out_at = null, delivered_at = null, updated_at = timestamptz '2026-11-19 10:00-03'
     where id = pg_temp.os('132');
    alter table public.service_orders enable trigger user;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, status_antes, status_depois,
                                     antes, depois, texto)
    values (timestamptz '2026-09-09 17:30-03', date '2026-09-09', true, 'dono', 'status', pg_temp.os('132'), array[pg_temp.os('132')],
            'in_progress', 'completed', '{"status": "in_progress"}', '{"status": "completed"}', 'Teste (C1): concluída.');
    v := public.agenda_medir_os(pg_temp.os('132'), date '2026-11-20');
    select * into m from public.agenda_medidas_os where service_order_id = pg_temp.os('132');
    v_res := pg_temp.ok(v_res, 'M9b (C1, item 9) sem check-out, a conclusão é o 1º instante em que a porta a deixou concluída (09/09): a medida vale, e só a entrega (que a simulação tirou) muda',
      m.concluida_em = date '2026-09-09' and m.valida and m.historico -> -1 -> 'depois' = '{"entregue_em": null}'::jsonb,
      to_jsonb(m)::text || ' / ' || v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- (B5) um ano depois, sem nada mudado: só as medidas da janela são olhadas
  begin
    execute current_setting('agenda_teste.fase6');
    r1 := public._agenda_aprender_medir(c_hoje);
    alter table public.service_orders disable trigger user;  -- (só a simulação: nenhuma OS mudou depois de medida)
    update public.service_orders so set updated_at = timestamptz '2026-10-01 10:00-03'
     where exists (select 1 from public.agenda_medidas_os x where x.service_order_id = so.id);
    alter table public.service_orders enable trigger user;
    r2 := public._agenda_aprender_medir(date '2027-10-05');
    select count(*) into n_janela from public.agenda_medidas_os x where x.concluida_em between date '2026-10-05' and date '2027-10-05';
    v_res := pg_temp.ok(v_res, 'M9c (C1, B5) um ano depois, sem nada mudado, a medição olha só as medidas da janela (as concluídas desde 05/10/2026), e não as 18',
      r1 ->> 'olhadas' = '18' and (r2 ->> 'olhadas')::int = n_janela and n_janela between 1 and 17 and r2 ->> 'medidas' = '0',
      r2::text || ' / na janela: ' || n_janela);
    -- a que mudou depois de medida (a edição depois da medida) volta a ser olhada
    alter table public.service_orders disable trigger user;
    update public.service_orders set updated_at = now() + interval '1 minute' where id = pg_temp.os('131');
    alter table public.service_orders enable trigger user;
    r2 := public._agenda_aprender_medir(date '2027-10-06');
    select count(*) into n_janela from public.agenda_medidas_os x
     where x.concluida_em between date '2026-10-06' and date '2027-10-06' and x.service_order_id <> pg_temp.os('131');
    v_res := pg_temp.ok(v_res, 'M9d (C1, B5) a medida de fora da janela que mudou depois de medida volta a ser olhada (só ela a mais)',
      (r2 ->> 'olhadas')::int = n_janela + 1, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m9$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
