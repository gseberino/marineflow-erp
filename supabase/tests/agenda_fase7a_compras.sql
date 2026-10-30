-- Prova do "compre até" contado para trás, Fase 7a (pacote P10, migration 20261031100800), sobre a carteira REAL de 29/10 (o
-- replay, com a presença do dono de produção no Lenine e no Vanderlei) e a sintética da 7a (o Wagner, meio dia com o João em ter
-- 03/11; o Sérgio, com as 4 baterias na mão). O cenário E da spec (§8.3: o Vanderlei de qui 29/10 a qua 04/11) está em
-- agenda_fase7a_replay.sql; aqui, o resto.
-- bancada: depende de 20261031100800
--
--   C0 as portas e o que é (sem fixture): a conta e as compras da semana invoker, STABLE e sem grant; o passo definer e sem grant a
--      ninguém (nem service_role); as 4 recriadas com as portas de antes
--   C1 o "compre até" gravado: a conta do 1º dia para trás (folga, prazo, tempo interno), a base, o histórico, só quando muda; a
--      prontidão lê o gravado e o publicado não desliza (o controle sem o gravado desliza); a rodada chama o passo também nos
--      tiques fora dos diários (desligado, não)
--   C2 cobra × empurra × limite: a pergunta do dia uma vez (o tique seguinte não repete nem conta de novo); comprando hoje sem
--      chegar, nada (a vigia empurra) e a aberta resolvida; o limite (o 2º empurrão automático): "parei de remarcar", a compra
--      deixa de ser firme e a vigia leva à reserva; o urgente ("Compre hoje: … para começar ter 03/11")
--   C3 as compras da semana: por fornecedor, o urgente primeiro, até o fim da semana que vem; o "Separar amanhã"; a linha compras
--      do fechamento (80 com urgente, 65 com o de hoje), o foco gestor; em teste, só o diário
--   C4 o defeito reabre: a peça que estava na mão e volta a faltar (o *grava*): defeito_em, sem o "compre até", sem os empurrões, e
--      a frase "… voltou a faltar: o 'compre até' reabriu (comprando hoje, chega ter 10/11)."; desligado, sem a frase
--   C5 o foco compras: "Compras da semana:" no topo (ligado), "(em teste)" (sombra); desligado e com OS, o de antes, byte a byte
--   C6 as cópias: as 4 recriadas sem os blocos "-- FASE 7: (7a P10" são o corpo da origem
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_compras.sql
--   Seguro em produção: C0 e C6 (as cópias saem PULADO sem as migrations como texto) só leem; C1 a C5 usam as fixtures e só
--   rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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
-- A OS pelo número (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- Os 5 modos do gestor (as regras todas).
create function pg_temp.modos(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id
$f$;
-- O replay e a sintética (uma vez por transação), com a presença do dono de produção no Lenine e no Vanderlei.
create function pg_temp.fixtures() returns void language plpgsql as $f$
begin
  if pg_temp.os('OS-97006') is null then
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  end if;
end $f$;
-- O Lenine e o Vanderlei marcados pela estimativa (o cenário B da §8.3: o motor, persistir e aplicar), qui 29/10 16:52.
create function pg_temp.marcar() returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00069'), pg_temp.os('OS-00074')], '{}'::jsonb, true, 'vigia',
                              null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-10-29',
                               timestamptz '2026-10-29 16:52-03');
end $f$;
-- O Wagner (OS-97006, meio dia com o João em ter 03/11) com uma peça crítica a comprar de um fornecedor de entrega local.
create function pg_temp.wagner_com_peca() returns void language plpgsql as $f$
declare
  v_forn uuid := md5('p10:forn:local')::uuid;
begin
  insert into public.suppliers (id, name, modalidade, prazo_dias_uteis, prazo_fonte, active)
  values (v_forn, 'Elétrica Central', 'entrega_local', 1, 'dono', true);
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, critico, situacao, fonte,
                                  fornecedor_id, conferido_em)
  values (md5('p10:mat:wagner')::uuid, pg_temp.os('OS-97006'), 'dono', 'Tomada USB dupla 12 V', 2, true, 'falta', 'dono', v_forn,
          timestamptz '2026-10-28 10:00-03');
end $f$;
-- As linhas de material de uma OS: "descrição: compre_ate empurrões cobranças".
create function pg_temp.mat(p_os uuid) returns text language sql stable as $f$
  select string_agg(format('%s: %s %s %s', left(m.descricao, 12), coalesce(m.compre_ate::text, '-'), m.empurrada_vezes, m.cobrado_vezes),
                    ' | ' order by m.descricao)
    from public.os_material m where m.service_order_id = p_os and m.critico
$f$;
-- O 1º e o último dia de compromisso de uma OS de p_hoje em diante e o tipo.
create function pg_temp.plano(p_os uuid, p_hoje date) returns text language sql stable as $f$
  select min(a.dia)::text || '..' || max(a.dia)::text || ' ' || string_agg(distinct a.tipo, ',')
    from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
$f$;
-- A função inteira e o corpo, a partir do texto da migration.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O corpo sem os blocos deste pacote ("-- FASE 7: (7a P10 … -- FASE 7: fim"; os das etapas de antes ficam).
create function pg_temp.sem_p10(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7: \(7a P10' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- ── C0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem, definer, vol) as (values
  ('public._agenda_gestor_compra_conta(uuid, date)', 'ninguem', false, 's'),
  ('public._agenda_compras_da_semana(date)', 'ninguem', false, 's'),
  ('public._agenda_gestor_compre_ate(date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_ver_compras(uuid, date)', 'leitura', true, 's'),
  ('public.agenda_rascunho_gravar(uuid, date)', 'leitura', true, 'v'),
  ('public._agenda_aplicar_material(uuid, uuid, jsonb, text, date)', 'servico', true, 'v'),
  ('public.agenda_gestor_rodar(date, timestamptz)', 'servico', true, 'v'))
insert into _resultado
select 'C0a as portas: a conta e as compras da semana invoker, STABLE e sem grant; o passo compre_ate definer, volátil e sem grant a ninguém (nem service_role); as 4 recriadas como eram (o foco compras e o *grava* para authenticated e service_role; o aplicar do material e a rodada só service_role); nunca anon; search_path fixo',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = (f.quem = 'leitura')
                and has_function_privilege('service_role', f.assinatura, 'execute') = (f.quem in ('leitura', 'servico'))
                and p.prosecdef = f.definer and p.provolatile::text = f.vol
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> (f.quem = 'leitura')
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> (f.quem in ('leitura', 'servico'))
                                              or p.prosecdef <> f.definer or p.provolatile::text <> f.vol)
  from f join pg_proc p on p.oid = f.assinatura::regprocedure;

-- ── C1 a C5: com as fixtures (o replay de 29/10 e a sintética, por cima) ──────────────────────────────────
do $fx$
declare
  v_res    jsonb := '[]'::jsonb;
  c_qui    constant date := date '2026-10-29';
  c_sex    constant date := date '2026-10-30';
  c_ter    constant date := date '2026-11-03';
  c_qua    constant date := date '2026-11-04';
  c_hoje   constant text := 'Compre até hoje: 3 itens de Vanderlei (Kit Cabos/ Conectores/…, Cabos Elétricos Diversos… e Kit cabos eletricos…) — de quem? Contei 7 dias úteis de entrega. Comprando hoje, o serviço segue em qui 12/11.';
  c_limite constant text := 'Os itens de Vanderlei já empurraram o serviço 2 vezes: parei de remarcar. Ele fica guardado até você me dizer de quem e quando compra.';
  c_urg    constant text := 'Compre hoje: 2 × Tomada USB dupla… de Wagner, para começar ter 03/11 (faltam menos de 7 dias úteis). De Elétrica, 1 dia útil de entrega.';
  c_cs_v   constant text := 'Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje.';
  c_cs_w   constant text := 'Elétrica: 2 × Tomada USB dupla… de Wagner — compre hoje para começar ter 03/11.';
  c_sep    constant text := 'Separar amanhã: 8 × Porta Fusível MIDI… (Vanderlei).';
  c_ser    constant text := 'Bateria de lítio… de Sérgio voltou a faltar: o ''compre até'' reabriu (comprando hoje, chega ter 10/11).';
  v_van    uuid;
  v_wag    uuid;
  v_ser    uuid;
  v_adm    uuid;
  r        jsonb;
  r2       jsonb;
  v_t      text;
  v_t2     text;
  v_n      int;
  v_ok     boolean;
  v_h      int;
  v_c      jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('C1 a C5 (o replay de 29/10 e a sintética)', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.fixtures();
    v_van := pg_temp.os('OS-00069');
    v_wag := pg_temp.os('OS-97006');
    v_ser := pg_temp.os('OS-97002');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;
    perform pg_temp.modos('ligado');
    r := pg_temp.marcar();

    -- ── C1. O "compre até" gravado ──
    r := public._agenda_gestor_compre_ate(c_qui, pg_temp.em(c_qui, '10:07'));
    select count(*), bool_and(m.compre_ate = c_qui
                              and m.compre_ate_base = '{"primeiro": "2026-11-12", "folga": 1, "prazo": 7, "prazo_fonte": "padrao", "interno": 1}'::jsonb
                              and m.compre_ate_em = pg_temp.em(c_qui, '10:07')
                              and m.historico -> -1 ->> 'por' = 'gestor'
                              and m.historico -> -1 ->> 'nota' = 'compre até qui 29/10 (para começar qui 12/11)')
      into v_n, v_ok
      from public.os_material m where m.service_order_id = v_van and m.compre_ate is not null;
    v_res := pg_temp.ok(v_res, 'C1a às 10:07 (antes da cobrança): as 3 linhas críticas do Vanderlei ganham o "compre até" qui 29/10 = qui 12/11 − 1 de folga − 7 dias úteis sem fornecedor − 1 de compra interna (Finados no meio), com a base, a hora e o histórico do gestor; o porta-fusível (miúdo) não; nenhuma pergunta e nada no diário',
      v_n = 3 and v_ok and (r ->> 'gravados')::int = 3 and not (r ->> 'cobranca')::boolean
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'compre_ate')
      and not exists (select 1 from public.agenda_gestor_dia g where g.dia = c_qui and g.compras <> '[]'::jsonb)
      and not exists (select 1 from public.os_material m where m.service_order_id = v_van and not m.critico and m.compre_ate is not null),
      pg_temp.mat(v_van));
    v_h := (select sum(jsonb_array_length(m.historico)) from public.os_material m where m.service_order_id = v_van);
    r := public._agenda_gestor_compre_ate(c_qui, pg_temp.em(c_qui, '10:22'));
    v_res := pg_temp.ok(v_res, 'C1b o tique seguinte não grava de novo (a conta não mudou): nada no histórico',
      (r ->> 'gravados')::int = 0 and (select sum(jsonb_array_length(m.historico)) from public.os_material m where m.service_order_id = v_van) = v_h
      and (select bool_and(m.compre_ate_em = pg_temp.em(c_qui, '10:07')) from public.os_material m
            where m.service_order_id = v_van and m.compre_ate is not null), r::text);
    select string_agg(e ->> 'data_texto', ' | ' order by o) into v_t
      from jsonb_array_elements(public.os_prontidao(v_van, c_qui) #> '{material,itens}') with ordinality t(e, o)
     where (e ->> 'critico')::boolean;
    v_res := pg_temp.ok(v_res, 'C1c a prontidão lê o gravado: "se comprar até qui 29/10, chega por volta de qua 11/11" nos 3 (compra firme), o material pronto a partir de qui 12/11, classe 2',
      v_t = 'se comprar até qui 29/10, chega por volta de qua 11/11 | se comprar até qui 29/10, chega por volta de qua 11/11 | se comprar até qui 29/10, chega por volta de qua 11/11'
      and public.os_prontidao(v_van, c_qui) #>> '{material,inicio_mat}' = '2026-11-12'
      and (public._agenda_classe_agora(v_van, c_qui) ->> 'classe')::int = 2, v_t);
    -- sex 30/10: com o gravado, a vigia não mexe; sem ele (o controle), a prontidão conta a compra a partir de amanhã e empurra
    r := public._agenda_vigia_violacoes(c_sex, pg_temp.em(c_sex, '08:00'));
    begin
      update public.os_material set compre_ate = null, compre_ate_base = null where service_order_id = v_van;
      r2 := public._agenda_vigia_violacoes(c_sex, pg_temp.em(c_sex, '08:00'));
      v_t := pg_temp.plano(v_van, c_sex);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C1d o publicado não desliza: na sex 30/10 a vigia não mexe no Vanderlei (o "compre até" de qui 29/10 venceu, mas comprando hoje chega qua 11/11); o controle sem o gravado: a vigia o empurra para sex 13/11',
      (r ->> 'violadas')::int = 0 and pg_temp.plano(v_van, c_sex) = '2026-11-12..2026-11-24 execucao'
      and (r2 ->> 'violadas')::int = 1 and v_t = '2026-11-13..2026-11-25 execucao', coalesce(v_t, '-') || ' / ' || r2::text);
    begin
      r := public.agenda_gestor_rodar(c_qui, pg_temp.em(c_qui, '11:07'));
      v_ok := r -> 'contagens' ? 'compre_ate' and (r #>> '{contagens,compre_ate,modo}') = 'ligado' and not (r ->> 'diaria')::boolean;
      update public.agenda_config set modo_compre_ate = 'desligado' where id;
      r := public.agenda_gestor_rodar(c_qui, pg_temp.em(c_qui, '11:22'));
      v_ok := v_ok and not (r -> 'contagens' ? 'compre_ate') and (r ->> 'rodou')::boolean;
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C1e a rodada do gestor chama o passo compre_ate também no tique fora dos diários (qui 29/10 11:07); com o compre_ate desligado, não (a rodada de antes)',
      v_ok, r::text);

    -- ── C2. Cobra × empurra × limite ──
    r := public._agenda_gestor_compre_ate(c_qui, pg_temp.em(c_qui, '16:52'));
    select count(*) into v_n from public.agenda_perguntas q
     where q.tipo = 'compre_ate' and q.estado = 'aberta' and q.modo = 'ligado' and q.service_order_id = v_van
       and q.chave = format('compre_ate:%s:hoje:2026-10-29', v_van) and q.texto = c_hoje and q.opcoes = '[]'::jsonb
       and q.veto_ate is null and q.opcao_padrao is null and not q.critica;
    v_res := pg_temp.ok(v_res, 'C2a às 16:52 a cobrança: uma pergunta compre_ate para o Vanderlei, sem opções e sem prazo (spec §6.3, o "hoje"), e a cobrança contada nos 3 itens',
      v_n = 1 and (r ->> 'cobrancas')::int = 1
      and (select bool_and(m.cobrado_vezes = 1 and m.cobrado_em = pg_temp.em(c_qui, '16:52')) from public.os_material m
            where m.service_order_id = v_van and m.compre_ate is not null), r #>> '{perguntas,0,texto}');
    r := public._agenda_gestor_compre_ate(c_qui, pg_temp.em(c_qui, '17:07'));
    v_res := pg_temp.ok(v_res, 'C2b o tique seguinte (17:07) não pergunta de novo nem conta outra cobrança (a mesma chave aberta)',
      (r ->> 'cobrancas')::int = 0 and (select count(*) from public.agenda_perguntas q where q.tipo = 'compre_ate') = 1
      and (select bool_and(m.cobrado_vezes = 1) from public.os_material m where m.service_order_id = v_van and m.compre_ate is not null),
      r::text);
    -- ter 03/11 16:52 sem a vigia ter passado: comprando hoje já não chega para qui 12/11 — nada aqui (a vigia empurra)
    begin
      r := public._agenda_gestor_compre_ate(c_ter, pg_temp.em(c_ter, '16:52'));
      v_t := (select q.estado || ': ' || coalesce(q.resolvida_motivo, '-') from public.agenda_perguntas q where q.tipo = 'compre_ate' limit 1);
      v_ok := (r ->> 'cobrancas')::int = 0 and (r #>> '{os,0,cobranca}') is null and (r ->> 'resolvidas')::int = 1;
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C2c comprando hoje já não chega (ter 03/11, antes da vigia): nenhuma pergunta nova (a violação de material da vigia empurra) e a aberta resolvida',
      v_ok and v_t = 'resolvida: não precisa mais: nada a cobrar dessa compra agora', v_t);
    -- o limite: os 3 itens já tinham empurrado o serviço 1 vez; a vigia de ter 03/11 empurra a 2ª (automática)
    begin
      update public.os_material set empurrada_vezes = 1 where service_order_id = v_van and compre_ate is not null;
      r := public._agenda_vigia_violacoes(c_ter, pg_temp.em(c_ter, '08:00'));
      r := public._agenda_gestor_compre_ate(c_ter, pg_temp.em(c_ter, '16:52'));
      v_t := (select q.texto from public.agenda_perguntas q
               where q.tipo = 'compre_ate' and q.estado = 'aberta' and q.chave = format('compre_ate:%s:limite:2', v_van));
      v_ok := (r ->> 'limites')::int = 1 and (r ->> 'empurrados')::int = 3
              and (select bool_and(m.empurrada_vezes = 2) from public.os_material m where m.service_order_id = v_van and m.compre_ate is not null)
              and (select count(*) from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta' and q.service_order_id = v_van) = 1
              and not exists (select 1 from jsonb_array_elements(public.os_prontidao(v_van, c_ter) #> '{material,itens}') e
                               where (e ->> 'critico')::boolean and (e ->> 'compra_firme')::boolean)
              and public._agenda_classe_agora(v_van, c_ter) ->> 'motivo' = 'compra';
      v_c := jsonb_build_object('passo', r, 'mat', pg_temp.mat(v_van), 'abertas', (select string_agg(q.chave, ',') from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta' and q.service_order_id = v_van), 'classe', public._agenda_classe_agora(v_van, c_ter) - 'pront');
      r := public._agenda_vigia_violacoes(c_qua, pg_temp.em(c_qua, '08:00'));
      v_t2 := pg_temp.plano(v_van, c_qua);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C2d o limite (o 2º empurrão automático, compre_ate_empurroes_max 2): "Os itens de Vanderlei já empurraram o serviço 2 vezes: parei de remarcar. …" (a única aberta); a compra deixa de ser firme (classe 3, compra) e a vigia de qua 04/11 leva o Vanderlei à reserva',
      v_ok and v_t = c_limite and v_t2 like '% reserva', coalesce(v_t, '-') || ' / ' || coalesce(v_t2, '-') || ' / ' || left(coalesce(v_c::text, '-'), 300));
    -- o urgente: o Wagner (meio dia em ter 03/11) com 2 tomadas a comprar de um fornecedor de entrega local (1 dia útil)
    perform pg_temp.wagner_com_peca();
    r := public._agenda_gestor_compre_ate(c_qui, pg_temp.em(c_qui, '17:22'));
    v_res := pg_temp.ok(v_res, 'C2e o urgente (AG7-07): o Wagner começa ter 03/11, a menos de 7 dias úteis — "Compre hoje: 2 × Tomada USB dupla… de Wagner, para começar ter 03/11 (faltam menos de 7 dias úteis). De Elétrica, 1 dia útil de entrega."',
      exists (select 1 from public.agenda_perguntas q where q.tipo = 'compre_ate' and q.estado = 'aberta' and q.service_order_id = v_wag
               and q.chave = format('compre_ate:%s:urgente:2026-11-03', v_wag) and q.texto = c_urg),
      (select string_agg(q.texto, ' | ') from public.agenda_perguntas q where q.service_order_id = v_wag));

    -- ── C3. As compras da semana ──
    v_c := (select g.compras from public.agenda_gestor_dia g where g.dia = c_qui);
    v_res := pg_temp.ok(v_res, 'C3a o diário de qui 29/10 (17:22): por fornecedor, o urgente primeiro — "Elétrica: 2 × Tomada USB dupla… de Wagner — compre hoje para começar ter 03/11." e "Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje."',
      jsonb_array_length(v_c) = 2 and v_c -> 0 ->> 'texto' = c_cs_w and (v_c -> 0 ->> 'urgente')::boolean
      and v_c -> 1 ->> 'texto' = c_cs_v and not (v_c -> 1 ->> 'urgente')::boolean and v_c -> 1 ->> 'compre_ate' = '2026-10-29'
      and jsonb_array_length(v_c -> 1 -> 'itens') = 3, v_c::text);
    v_t := (select x ->> 'texto' || ' [' || (x ->> 'perda') || ' ' || (x ->> 'modo') || ']'
              from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_qui)) x where x ->> 'tipo' = 'compras');
    v_res := pg_temp.ok(v_res, 'C3b a linha compras do fechamento das 17:30: as duas, perda 80 (há compra urgente: vai como decisão), modo ligado',
      v_t = 'Compras: ' || c_cs_w || ' ' || c_cs_v || ' [80 ligado]', v_t);
    v_t := public._agenda_ver_gestor(c_qui) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C3c o foco gestor: "Compras da semana:" com as duas, uma por linha',
      position(E'Compras da semana:\n• ' || c_cs_w || E'\n• ' || c_cs_v in v_t) > 0, v_t);
    begin
      delete from public.os_material where id = md5('p10:mat:wagner')::uuid;
      r := public._agenda_gestor_compre_ate(c_qui, pg_temp.em(c_qui, '17:37'));
      v_t := (select x ->> 'texto' || ' [' || (x ->> 'perda') || ']'
                from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_qui)) x where x ->> 'tipo' = 'compras');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C3d sem o urgente (a peça do Wagner saiu), a linha é a do Vanderlei com perda 65 ("compre até" hoje)',
      v_t = 'Compras: ' || c_cs_v || ' [65]', v_t);
    v_c := public._agenda_compras_da_semana(date '2026-11-11');
    v_res := pg_temp.ok(v_res, 'C3e qua 11/11 (o Vanderlei começa qui 12/11): o miúdo vai no fim, "Separar amanhã: 8 × Porta Fusível MIDI… (Vanderlei)." (sem "compre até")',
      v_c -> -1 ->> 'texto' = c_sep and (v_c -> -1 ->> 'separar')::boolean and v_c -> -1 -> 'compre_ate' = 'null'::jsonb, v_c::text);
    v_res := pg_temp.ok(v_res, 'C3f até o fim da semana que vem: de seg 19/10 (até dom 01/11) o "compre até" de qui 29/10 entra; de seg 12/10 (até dom 25/10), não',
      exists (select 1 from jsonb_array_elements(public._agenda_compras_da_semana(date '2026-10-19')) x where x ->> 'texto' like 'Sem fornecedor%')
      and not exists (select 1 from jsonb_array_elements(public._agenda_compras_da_semana(date '2026-10-12')) x where x ->> 'texto' like 'Sem fornecedor%'),
      public._agenda_compras_da_semana(date '2026-10-12')::text);
    -- em teste: tudo seco, só o diário
    begin
      perform pg_temp.modos('sombra');
      delete from public.agenda_gestor_dia where dia = c_sex;
      update public.os_material set compre_ate = null, compre_ate_base = null, compre_ate_em = null where compre_ate is not null;
      v_n := (select count(*) from public.agenda_perguntas);
      r := public._agenda_gestor_compre_ate(c_sex, pg_temp.em(c_sex, '10:07'));
      v_ok := (r ->> 'simulacao')::boolean and not (r ->> 'cobranca')::boolean
              and not exists (select 1 from public.agenda_gestor_dia g where g.dia = c_sex);
      r := public._agenda_gestor_compre_ate(c_sex, pg_temp.em(c_sex, '16:52'));
      v_ok := v_ok and (r ->> 'simulacao')::boolean and (select count(*) from public.agenda_perguntas) = v_n
              and not exists (select 1 from public.os_material m where m.compre_ate is not null)
              and coalesce(current_setting('agenda.gestor', true), '') = '';
      v_t := (select x ->> 'texto' || ' [' || (x ->> 'perda') || ' ' || (x ->> 'modo') || ']'
                from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_sex)) x where x ->> 'tipo' = 'compras');
      v_t2 := left(public._agenda_ver_compras(null, c_sex) ->> 'texto', 120);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C3g em teste: fora da cobrança, nada; às 16:52 só o diário (nenhum "compre até" gravado, nenhuma pergunta; a variável agenda.gestor volta vazia); a linha compras vai em teste (sombra, perda 80 pelo urgente do Wagner) e o foco compras diz "(em teste)"',
      v_ok and v_t = 'Compras: ' || c_cs_w || ' ' || c_cs_v || ' [80 sombra]'
      and v_t2 like E'Compras da semana (em teste):\n• Elétrica:%',
      coalesce(v_t, '-') || ' / ' || coalesce(v_t2, '-'));

    -- ── C4. O defeito reabre (as baterias do Sérgio estavam na mão e voltam a faltar) ──
    begin
      update public.os_material set compre_ate = date '2026-10-20', compre_ate_base = '{"primeiro": "2026-11-03"}', empurrada_vezes = 1
       where service_order_id = v_ser;
      r := public.agenda_rascunho_material(v_adm, 'whatsapp', 'Sérgio', array['Bateria'], 'falta', null, null, null, false,
                                           'a bateria do Sérgio veio com defeito', c_qui, null);
      r := public.agenda_rascunho_gravar(v_adm, c_qui);
      v_t := r ->> 'texto';
      v_ok := (select m.situacao = 'falta' and m.quantidade_na_mao = 0 and m.chegou_em is null and m.defeito_em is not null
                      and m.compre_ate is null and m.compre_ate_base is null and m.empurrada_vezes = 0
                 from public.os_material m where m.service_order_id = v_ser)
              and coalesce(current_setting('agenda.material_reabriu', true), '') = '';
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C4a o *grava* da peça que voltou a faltar (ligado): "Gravado. Agora:" com a linha do Sérgio e "• Bateria de lítio… de Sérgio voltou a faltar: o ''compre até'' reabriu (comprando hoje, chega ter 10/11)."; a linha em falta, sem nada na mão, com defeito_em, sem o "compre até" e sem os empurrões',
      v_ok and v_t like E'Gravado. Agora:\n• Sérgio: %' and v_t like E'%\n• ' || c_ser, v_t);
    begin
      perform pg_temp.modos('desligado');
      update public.os_material set compre_ate = date '2026-10-20', compre_ate_base = '{"primeiro": "2026-11-03"}', empurrada_vezes = 1
       where service_order_id = v_ser;
      r := public.agenda_rascunho_material(v_adm, 'whatsapp', 'Sérgio', array['Bateria'], 'falta', null, null, null, false,
                                           'a bateria do Sérgio veio com defeito', c_qui, null);
      r := public.agenda_rascunho_gravar(v_adm, c_qui);
      v_t := r ->> 'texto';
      v_ok := (select m.defeito_em is not null and m.compre_ate is null and m.empurrada_vezes = 0
                 from public.os_material m where m.service_order_id = v_ser);
      r2 := public._agenda_aplicar_material(v_adm, v_ser, jsonb_build_object('origem', 'dono', 'linha_id', md5('f7a:material:97002:baterias')::text,
                                                                              'acao', 'na_mao', 'chegou_em', '2026-10-29'), 'chegou', c_qui);
      r2 := public._agenda_aplicar_material(v_adm, v_ser, jsonb_build_object('origem', 'dono', 'linha_id', md5('f7a:material:97002:baterias')::text,
                                                                              'acao', 'falta'), 'veio errada', c_qui);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C4b com o "compre até" do gestor desligado: os fatos da linha (defeito_em, sem o gravado, sem os empurrões), mas o *grava* sem a frase e a saída de _agenda_aplicar_material só {linha, de, para}',
      v_ok and v_t not like '%reabriu%' and v_t like E'Gravado. Agora:\n• Sérgio: %' and position(E'\n' in substr(v_t, 17)) = 0
      and r2 ?& array['linha', 'de', 'para'] and not (r2 ? 'texto'), v_t || ' / ' || r2::text);

    -- ── C5. O foco compras ──
    v_t := public._agenda_ver_compras(null, c_qui) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C5a o foco compras (ligado): "Compras da semana:" no topo, pela conta de agora (o urgente do Wagner, o Vanderlei), e o de sempre depois ("Compras (qui 29/10):")',
      v_t like E'Compras da semana:\n• ' || c_cs_w || E'\n• ' || c_cs_v || E'\nCompras (qui 29/10):\n%', left(v_t, 400));
    v_t := public.agenda_ver(null, null, null, 'compras', null, null, false, c_qui) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C5b pelo agenda_ver (o foco compras do assistente), o mesmo texto',
      v_t like E'Compras da semana:\n• %', left(v_t, 200));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── C5c, C5d e C6. O portão falso e as cópias ───────────────────────────────────────────────────────────────
do $copias$
declare
  v_res  jsonb := '[]'::jsonb;
  v_c6   text := coalesce(current_setting('agenda_teste.mig_correcao_textos_fase6', true), '');
  v_np   text := coalesce(current_setting('agenda_teste.mig_notas_pix_fase4', true), '');
  v_p7   text := coalesce(current_setting('agenda_teste.mig_rodada_fase7a', true), '');
  r      record;
  v_novo text;
  v_n    int;
  v_a    text;
  v_b    text;
  d      date;
begin
  if v_c6 = '' or v_np = '' or v_p7 = '' then
    insert into _resultado values ('C6 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_ver_compras', 'public._agenda_ver_compras(uuid, date)', v_c6, '20261029100950', 2),
      ('_agenda_aplicar_material', 'public._agenda_aplicar_material(uuid, uuid, jsonb, text, date)', v_np, '20261027100300', 3),
      ('agenda_rascunho_gravar', 'public.agenda_rascunho_gravar(uuid, date)', v_np, '20261027100300', 2),
      ('agenda_gestor_rodar', 'public.agenda_gestor_rodar(date, timestamptz)', v_p7, '20261031100600', 1)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: \(7a P10', 'g');
    v_res := pg_temp.ok(v_res,
      format('C6 %s: sem os %s blocos "-- FASE 7: (7a P10", é o corpo de %s (a mais nova antes do P10)', r.nome, r.blocos, r.versao),
      v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_p10(v_novo) = pg_temp.corpo(r.fonte, r.nome),
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
             length(pg_temp.sem_p10(v_novo))));
  end loop;

  -- com o "compre até" do gestor desligado, o foco compras é o de antes, byte a byte (sem OS e com OS)
  if coalesce(current_setting('agenda_teste.replay2910', true), '') <> '' and coalesce(current_setting('agenda_teste.fase7a', true), '') <> '' then
    begin
      perform pg_temp.fixtures();
      execute replace(pg_temp.inteira(v_c6, '_agenda_ver_compras'), 'create or replace function public._agenda_ver_compras(',
                      'create function pg_temp.ver_compras_antes(');
      perform pg_temp.modos('ligado');
      perform pg_temp.marcar();
      perform pg_temp.wagner_com_peca();
      perform public._agenda_gestor_compre_ate(date '2026-10-29', pg_temp.em(date '2026-10-29', '16:52'));
      update public.agenda_config set modo_compre_ate = 'desligado' where id;
      v_a := '';
      v_b := '';
      foreach d in array array[date '2026-10-29', date '2026-10-30', date '2026-11-11'] loop
        v_a := v_a || (public._agenda_ver_compras(null, d))::text || (public._agenda_ver_compras(pg_temp.os('OS-00069'), d))::text;
        v_b := v_b || (pg_temp.ver_compras_antes(null, d))::text || (pg_temp.ver_compras_antes(pg_temp.os('OS-00069'), d))::text;
      end loop;
      v_res := pg_temp.ok(v_res, 'C5c com o "compre até" do gestor desligado (o resto do gestor ligado e o diário cheio), o foco compras é o de antes, byte a byte (sem OS e com o Vanderlei; qui 29/10, sex 30/10 e qua 11/11)',
        v_a = v_b and length(v_a) > 100, md5(v_a) || ' / ' || md5(v_b));
      update public.agenda_config set modo_compre_ate = 'ligado' where id;
      v_a := (public._agenda_ver_compras(pg_temp.os('OS-00069'), date '2026-10-29'))::text;
      v_b := (pg_temp.ver_compras_antes(pg_temp.os('OS-00069'), date '2026-10-29'))::text;
      v_res := pg_temp.ok(v_res, 'C5d com OS, o foco compras não muda nem com o "compre até" ligado (a seção é só do foco sem OS)',
        v_a = v_b, left(v_a, 200));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  else
    insert into _resultado values ('C5c o portão falso do foco compras', true, 'PULADO: sem as fixtures (rode pela bancada)');
  end if;
  perform pg_temp.gravar(v_res);
end
$copias$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
