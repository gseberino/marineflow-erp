-- Prova das proteções do cliente e da equipe, Fase 7a (pacote P11, migration 20261031100850), sobre a carteira REAL de 29/10 (o
-- replay, com a presença do dono de produção no Lenine e no Vanderlei), com o Lenine e o Vanderlei marcados pela estimativa (o
-- cenário B da spec §8.3: o Lenine de ter 03 a ter 10/11 — o João em ter 03 e qua 04, o Roberto de qui 05 a ter 10/11 —, o
-- Vanderlei de qui 12 a ter 24/11). O cenário F da spec (a rodada do cliente sobre o replay) está em agenda_fase7a_replay.sql.
-- bancada: depende de 20261031100850
--
--   P0 as portas e o que é (sem fixture): as 4 leituras novas invoker, STABLE, para authenticated e service_role; o passo fichas
--      sem grant; as 7 recriadas com as portas de antes; a pergunta ficha_estimativa é das mensagens à equipe (modo_equipe), também
--      com *gestor, só propor*; sem o ligar do gestor, a ficha sempre pode sair e o passo pula
--   P1 compra pendente = nenhum M1 (a regra da Fase 5 continua): a OS por estimativa (o compromisso de duracao_fonte orcamento, sem
--      os dias do dono) e a compra pendente (crítico em falta); o Vanderlei não recebe confirmação nem véspera
--   P2 por estimativa = pedida até 3 dias distintos aprovados; a véspera livre: confirmar, nova_data e material_chegou levam
--      base.dados.por_estimativa e pedem o sim do dono mesmo com o tipo liberado; os dias do dono tiram a estimativa; 2 dias
--      aprovados por estimativa ainda pedem, o 3º libera; o aprovado vai à fila como sempre; o zero da saúde
--   P3 a ficha na janela: a pergunta (o texto da §6.3, o prazo na hora da ficha), a linha própria no fechamento (perda 75); não
--      mostrada = veto (e o que mudou conta ao dono; a confirmação da manhã também fica); mostrada = sai; segurada (2) = veto;
--      o "mande" (1); o prazo pelo passo vetos; o "como foi hoje?" não leva a ficha protegida sem o "mande"; fora da janela = sai
--   P4 as cópias: as 7 recriadas sem os blocos "-- FASE 7: (7a P11" são o corpo da origem
--   P5 o de antes, byte a byte: sem dia pela estimativa e sem o ligar do gestor, as rotinas da equipe, o registro da mensagem ao
--      cliente, as linhas do fechamento e o modo de cada pergunta dão o mesmo que as definições de antes (rodadas como pg_temp)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_protecoes.sql
--   Seguro em produção: P0 e P4 (as cópias saem PULADO sem as migrations como texto) só leem; P1, P2, P3 e P5 usam o replay e só
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
-- A OS pelo número e a pessoa pelo nome (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select py.id from public.payees py where py.name = p_nome and py.active order by py.id limit 1
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- Os 5 modos do gestor (as regras todas); ligado = o ligar de qui 29/10 16:46 (a janela da ficha: de qui 29/10 a qua 18/11).
create function pg_temp.modos(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id
$f$;
-- O replay (uma vez por transação), com a presença do dono de produção no Lenine e no Vanderlei, o gestor ligado e os dois
-- marcados pela estimativa (o cenário B: o motor, persistir e aplicar, qui 29/10 16:52).
create function pg_temp.fixtures() returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  execute current_setting('agenda_teste.replay2910');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  -- (correção 2 da 7a, a ficha prometida a quem não tem telefone, 20261031100985) o gestor só pergunta a ficha de quem tem
  -- telefone: no replay o João não tem (o Roberto tem). Este teste é da janela de veto, então o João ganha um.
  update public.payees set phone = '5547900000004' where name = 'João' and phone is null;
  perform pg_temp.modos('ligado');
  v_p := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00069'), pg_temp.os('OS-00074')], '{}'::jsonb, true, 'vigia',
                              null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-10-29',
                               timestamptz '2026-10-29 16:52-03');
end $f$;
-- n mensagens aprovadas pelo dono (da rodada, em ligado) de um tipo, uma por dia a partir de p_de, com ou sem a estimativa: o
-- que libera o tipo (Fase 5) e a aprovação por estimativa (P11).
create function pg_temp.aprovadas(p_tipo text, p_n int, p_de date, p_est boolean, p_sufixo text) returns void language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                               aprovacao, aprovada_em, estado, dedupe_key, enviada_em, base)
  select so.client_id, so.id, p_tipo, 'rodada', 'ligado', 'mensagem de teste (P11)', pg_temp.em(p_de + k, '10:00'),
         pg_temp.em(p_de + k, '11:00'), 'aprovada', pg_temp.em(p_de + k, '10:00'), 'enviada',
         format('agenda-cliente:p11:%s:%s:%s', p_tipo, p_sufixo, k), pg_temp.em(p_de + k, '10:00'),
         case when p_est then '{"dados": {"por_estimativa": true}}'::jsonb else '{}'::jsonb end
    from generate_series(0, p_n - 1) k, public.service_orders so
   where so.service_order_number = 'OS-00074'
$f$;
-- As mensagens à equipe de uma pessoa: "tipo dia estado/motivo [leva]".
create function pg_temp.equipe(p_payee uuid) returns text language sql stable as $f$
  select string_agg(format('%s %s %s%s', m.tipo, m.dia, m.estado || coalesce('/' || m.recusa_motivo, ''),
                           coalesce(' leva ' || m.leva_ficha_de, '')), ' | ' order by m.dia, m.criada_em, m.tipo)
    from public.agenda_equipe_mensagens m where m.payee_id = p_payee and m.modo = 'ligado'
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
-- O corpo sem os blocos deste pacote ("-- FASE 7: (7a P11 … -- FASE 7: fim"; os das etapas de antes ficam) e dos pacotes que
-- recriam depois a mesma função (7a P12: _agenda_gestor_decidir, com o sábado).
create function pg_temp.sem_p11(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7: \(7a P1[12]' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- ── P0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, quem, definer, vol) as (values
  ('public._agenda_os_por_estimativa(uuid, date)', 'leitura', false, 's'),
  ('public._agenda_os_compra_pendente(uuid, date)', 'leitura', false, 's'),
  ('public._agenda_cliente_estimativa_liberada(text)', 'leitura', false, 's'),
  ('public._agenda_ficha_liberada(uuid, date, timestamptz)', 'leitura', false, 's'),
  ('public._agenda_gestor_fichas(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid)', 'ninguem', true, 'v'),
  ('public._agenda_rotina_ficha(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_rotina_como_foi(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_rotina_confirmar(date, timestamptz)', 'ninguem', false, 'v'),
  ('public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_linhas_do_fechamento(date)', 'leitura', false, 's'),
  ('public._agenda_modo_da_pergunta(text, text)', 'servico', false, 's'))
insert into _resultado
select 'P0a as portas: as 4 leituras novas invoker, STABLE, para authenticated e service_role; o passo fichas invoker, volátil e sem grant a ninguém (nem service_role); as 7 recriadas como eram (o registro do cliente, as 3 rotinas da equipe e o despacho do gestor sem grant; as linhas do fechamento para authenticated e service_role; o modo da pergunta só service_role); nunca anon; search_path fixo',
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

do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  v_cf  public.agenda_config;
  v_m   text;
  v_t   text;
  r     jsonb;
begin
  select * into v_cf from public.agenda_config where id;
  begin
    v_t := '';
    foreach v_m in array array['desligado', 'sombra', 'ligado'] loop
      update public.agenda_config set modo_equipe = v_m, modo_marcar_sozinho = 'ligado', gestor_so_propor = false where id;
      v_t := v_t || coalesce(public._agenda_modo_da_pergunta('ficha_estimativa', 'ficha_estimativa:x:2026-11-05'), '-') || ',';
    end loop;
    update public.agenda_config set modo_equipe = 'ligado', modo_marcar_sozinho = 'ligado', gestor_so_propor = true where id;
    v_t := v_t || public._agenda_modo_da_pergunta('ficha_estimativa', 'x') || ',' || public._agenda_modo_da_pergunta('situacao', 'x');
    v_res := pg_temp.ok(v_res, 'P0b a pergunta ficha_estimativa é das mensagens à equipe: o modo dela é o modo_equipe (desligado, sombra, ligado), também com *gestor, só propor*; os tipos do gestor que marca continuam com o modo dele (situacao em sombra com a palavra)',
      v_t = 'desligado,sombra,ligado,ligado,sombra', v_t);
    -- sem o ligar do gestor (marcar_sozinho_desde nulo), a ficha sempre pode sair e o passo pula
    update public.agenda_config set gestor_so_propor = false, marcar_sozinho_desde = null where id;
    r := public._agenda_gestor_fichas(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:52'));
    v_res := pg_temp.ok(v_res, 'P0c sem o ligar do gestor: _agenda_ficha_liberada é sempre verdadeira e o passo fichas pula ("o gestor ainda não marca sozinho")',
      public._agenda_ficha_liberada(gen_random_uuid(), date '2026-11-05', now())
      and (r ->> 'pulado')::boolean and r ->> 'motivo' like 'o gestor ainda não marca sozinho%', r::text);
    update public.agenda_config set modo_equipe = 'desligado', marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03' where id;
    r := public._agenda_gestor_fichas(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:52'));
    v_res := pg_temp.ok(v_res, 'P0d com as mensagens à equipe desligadas, o passo fichas pula (não há ficha a proteger)',
      (r ->> 'pulado')::boolean and r ->> 'motivo' = 'as mensagens à equipe estão desligadas', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── P1, P2 e P3: com o replay (o Lenine e o Vanderlei marcados pela estimativa) ─────────────────────────────────────
do $fx$
declare
  v_res   jsonb := '[]'::jsonb;
  c_qui   constant date := date '2026-10-29';
  c_qua   constant date := date '2026-11-04';
  c_q05   constant date := date '2026-11-05';
  c_s06   constant date := date '2026-11-06';
  c_perg  constant text := 'Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
  c_seg   constant text := 'Hoje às 19:30 a ficha de segunda vai para Roberto: Lenine, seg 09/11 o dia todo — dia 5 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
  c_ter   constant text := 'Hoje às 19:30 a ficha de terça vai para João: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
  c_acao  constant text := 'Não mandei a ficha de qui 05/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto.';
  v_len   uuid;
  v_van   uuid;
  v_rob   uuid;
  v_joao  uuid;
  v_adm   uuid;
  v_q     uuid;
  v_q2    uuid;
  r       jsonb;
  r2      jsonb;
  v_t     text;
  v_t2    text;
  v_n     int;
  v_n2    int;
  v_ok    boolean;
  v_lin   jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('P1 a P3 (o replay de 29/10)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;
  begin
    r := pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    v_van := pg_temp.os('OS-00069');
    v_rob := pg_temp.pessoa('Roberto');
    v_joao := pg_temp.pessoa('João');
    select u.id into v_adm from public.app_users u where u.role = 'admin' order by u.id limit 1;

    -- ── P1. A OS por estimativa e a compra pendente; nenhum M1 com compra pendente ──
    v_res := pg_temp.ok(v_res, 'P1a por estimativa: o Lenine e o Vanderlei (compromisso de duracao_fonte orcamento de hoje em diante) sim; o Nelson (sem compromisso) e o Lenine depois do último dia (qua 11/11) não',
      public._agenda_os_por_estimativa(v_len, c_qui) and public._agenda_os_por_estimativa(v_van, c_qui)
      and not public._agenda_os_por_estimativa(pg_temp.os('OS-00112'), c_qui)
      and not public._agenda_os_por_estimativa(v_len, date '2026-11-11') and not public._agenda_os_por_estimativa(null, c_qui), null);
    begin
      update public.os_planejamento set dias = 6, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_qui, '17:00')
       where service_order_id = v_len;
      v_ok := not public._agenda_os_por_estimativa(v_len, c_qui);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'P1b os dias ditos pelo dono (estimativa_fonte dono) tiram a estimativa, mesmo com as alocações de antes', v_ok, null);
    v_res := pg_temp.ok(v_res, 'P1c compra pendente: o Vanderlei (3 itens críticos em falta, sem fornecedor) sim; o Lenine (sem peça) não',
      public._agenda_os_compra_pendente(v_van, c_qui) and not public._agenda_os_compra_pendente(v_len, c_qui)
      and not public._agenda_os_compra_pendente(null, c_qui), null);
    begin
      perform pg_temp.aprovadas('confirmar', 3, date '2026-09-01', false, 'f5');
      perform pg_temp.aprovadas('vespera', 3, date '2026-09-01', false, 'f5');
      r := public.agenda_cliente_vigiar(c_qui, pg_temp.em(c_qui, '17:05'));
      r2 := public.agenda_cliente_vigiar(date '2026-11-11', pg_temp.em(date '2026-11-11', '17:05'));
      v_n := (select count(*) from public.agenda_cliente_mensagens m where m.service_order_id = v_van
               and m.tipo in ('confirmar', 'vespera', 'acesso') and m.dedupe_key not like 'agenda-cliente:p11:%');
      v_n2 := (select count(*) from public.agenda_cliente_mensagens m where m.service_order_id = v_len and m.tipo = 'confirmar'
                and m.dedupe_key not like 'agenda-cliente:p11:%');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'P1d nenhum M1 com compra pendente: a rodada do cliente (qui 29/10 e qua 11/11, o tipo liberado) não confirma nem avisa a véspera do Vanderlei — a Fase 5 já exige o material completo; o Lenine (sem peça) tem a confirmação',
      v_n = 0 and v_n2 = 1, format('Vanderlei %s, Lenine %s', v_n, v_n2));

    -- ── P2. Por estimativa: o sim do dono nos 3 primeiros dias, mesmo com o tipo liberado ──
    begin
      perform pg_temp.aprovadas('confirmar', 3, date '2026-09-01', false, 'f5');
      r := public._agenda_cliente_registrar('confirmar', null, v_len, date '2026-11-03', '{}'::jsonb, pg_temp.em(date '2026-10-30', '09:00'),
                                            null, 'rodada', null, pg_temp.em(c_qui, '17:10'));
      select q.texto into v_t from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid;
      v_res := pg_temp.ok(v_res, 'P2a o tipo confirmar já liberado pela Fase 5 (3 dias aprovados sem estimativa): a confirmação do Lenine, marcado pela estimativa, pede o sim do dono — pedida, esperando o dono, base.dados.por_estimativa, a pergunta cliente_aprovar "Mensagem para Lenine (confirmação; o dia é pela minha estimativa), sai …"; o texto ao cliente é o de sempre',
        public._agenda_cliente_tipo_liberado('confirmar') and not public._agenda_cliente_estimativa_liberada('confirmar')
        and r ->> 'aprovacao' = 'pedida' and r ->> 'estado' = 'aguardando_dono'
        and (select m.base -> 'dados' ->> 'por_estimativa' from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid) = 'true'
        and v_t like 'Mensagem para Lenine (confirmação; o dia é pela minha estimativa), sai amanhã às 09:00: "Lenine, conseguimos encaixar o serviço no seu motorhome para terça (03/11)%". *manda cliente Lenine* ou *segura cliente Lenine*.'
        and r ->> 'texto' not like '%estimativa%', coalesce(v_t, '-') || ' | ' || (r ->> 'texto'));
      -- o dono responde manda: aprovada; na hora do envio, a fila a leva (a marca na base não muda a revalidação)
      -- (o Lenine não tem telefone no replay, como em produção, nem conversa recente: um fictício e a conversa dispensada, para a
      -- fila poder levar)
      update public.clients set phone = '5547900000099' where id = (select so.client_id from public.service_orders so where so.id = v_len);
      update public.agenda_config set cliente_conversa_dias = 0 where id;
      r2 := public.agenda_decidir((r ->> 'pergunta_id')::uuid, 1::smallint, v_adm, 'whatsapp', 'manda', c_qui, pg_temp.em(c_qui, '17:40'));
      perform public._agenda_cliente_fila(date '2026-10-30', pg_temp.em(date '2026-10-30', '09:01'));
      v_res := pg_temp.ok(v_res, 'P2b o *manda cliente*: aprovada, e na hora do envio a fila a leva (enfileirada; a marca por_estimativa não muda a revalidação)',
        (select m.aprovacao || ' ' || m.estado from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid) = 'aprovada enfileirada',
        (select m.aprovacao || ' ' || m.estado || ' ' || coalesce(m.recusa_motivo, '-') from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid)
        || ' | ' || r2::text);
      -- os dias do dono: a mesma confirmação sai sozinha (o tipo liberado), sem a marca
      update public.os_planejamento set dias = 6, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(c_qui, '17:00')
       where service_order_id = v_len;
      r2 := public._agenda_cliente_registrar('confirmar', null, v_len, date '2026-11-03', '{"chave": "p11-dono"}'::jsonb,
                                             pg_temp.em(date '2026-10-30', '09:00'), null, 'rodada', null, pg_temp.em(c_qui, '17:10'));
      v_res := pg_temp.ok(v_res, 'P2c com os dias ditos pelo dono, a confirmação sai sozinha como antes (livre, sem base.dados.por_estimativa)',
        r2 ->> 'aprovacao' = 'livre'
        and (select m.base -> 'dados' ? 'por_estimativa' from public.agenda_cliente_mensagens m where m.id = (r2 ->> 'id')::uuid) = false,
        r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- nova_data e material_chegou levam a marca; a véspera e o aviso de atraso, não
      perform pg_temp.aprovadas('vespera', 3, date '2026-09-01', false, 'f5');
      v_t := '';
      foreach v_t2 in array array['nova_data', 'material_chegou', 'vespera', 'pode_atrasar'] loop
        r := public._agenda_cliente_registrar(v_t2, case v_t2 when 'pode_atrasar' then 'execucao' end, v_len, date '2026-11-03',
               jsonb_build_object('chave', 'p11-' || v_t2, 'faixa_de', '2026-11-10', 'faixa_ate', '2026-11-11', 'dia', '2026-11-03'),
               pg_temp.em(date '2026-10-31', '09:00'), null, 'rodada', null, pg_temp.em(date '2026-10-30', '17:10'));
        v_t := v_t || v_t2 || ':' || coalesce((select m.base -> 'dados' ->> 'por_estimativa' from public.agenda_cliente_mensagens m
                                               where m.id = (r ->> 'id')::uuid), '-') || ':' || (r ->> 'aprovacao') || ' ';
      end loop;
      v_res := pg_temp.ok(v_res, 'P2d a nova data e o "o material chegou" também levam a marca (e pedem o sim); a véspera (o dia de início é real) não, e com o tipo liberado sai sozinha; o aviso de atraso não muda',
        v_t = 'nova_data:true:pedida material_chegou:true:pedida vespera:-:livre pode_atrasar:-:pedida ', v_t);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- 2 dias aprovados por estimativa (o 2º com duas) + 1 segurado: ainda pede; o 3º dia libera
      perform pg_temp.aprovadas('confirmar', 3, date '2026-09-01', false, 'f5');
      perform pg_temp.aprovadas('confirmar', 2, date '2026-10-05', true, 'e2');
      perform pg_temp.aprovadas('confirmar', 1, date '2026-10-06', true, 'e2b');
      insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                   aprovacao, aprovada_em, estado, recusa_motivo, dedupe_key, base)
      select so.client_id, so.id, 'confirmar', 'rodada', 'ligado', 'mensagem de teste (P11)', pg_temp.em(date '2026-10-08', '10:00'),
             pg_temp.em(date '2026-10-08', '11:00'), 'segurada', pg_temp.em(date '2026-10-08', '10:00'), 'recusada', 'segurada',
             'agenda-cliente:p11:segurada', '{"dados": {"por_estimativa": true}}'::jsonb
        from public.service_orders so where so.id = v_len;
      r := public._agenda_cliente_registrar('confirmar', null, v_len, date '2026-11-03', '{"chave": "p11-2"}'::jsonb,
                                            pg_temp.em(date '2026-10-30', '09:00'), null, 'rodada', null, pg_temp.em(c_qui, '17:10'));
      perform pg_temp.aprovadas('confirmar', 1, date '2026-10-09', true, 'e3');
      r2 := public._agenda_cliente_registrar('confirmar', null, v_len, date '2026-11-03', '{"chave": "p11-3"}'::jsonb,
                                             pg_temp.em(date '2026-10-30', '09:00'), null, 'rodada', null, pg_temp.em(c_qui, '17:10'));
      v_res := pg_temp.ok(v_res, 'P2e 2 dias distintos aprovados por estimativa (o 2º com duas) e 1 segurado: ainda pede; com o 3º dia aprovado, a confirmação por estimativa sai sozinha (livre, com a marca)',
        r ->> 'aprovacao' = 'pedida' and r2 ->> 'aprovacao' = 'livre' and public._agenda_cliente_estimativa_liberada('confirmar')
        and (select m.base -> 'dados' ->> 'por_estimativa' from public.agenda_cliente_mensagens m where m.id = (r2 ->> 'id')::uuid) = 'true',
        (r ->> 'aprovacao') || ' / ' || (r2 ->> 'aprovacao'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o zero da saúde: 0 com o caminho certo; a mensagem por estimativa que saiu sem o sim antes dos 3 dias conta 1
      perform pg_temp.aprovadas('confirmar', 3, date '2026-09-01', false, 'f5');
      r := public._agenda_cliente_registrar('confirmar', null, v_len, date '2026-11-03', '{}'::jsonb, pg_temp.em(date '2026-10-30', '09:00'),
                                            null, 'rodada', null, pg_temp.em(c_qui, '17:10'));
      v_n := (public.agenda_saude(c_qui, pg_temp.em(c_qui, '17:20')) -> 'gestor' ->> 'cliente_estimativa_sem_aprovacao')::int;
      insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                   aprovacao, estado, dedupe_key, enviada_em, base, criada_em)
      select so.client_id, so.id, 'confirmar', 'rodada', 'ligado', 'mensagem de teste (P11)', pg_temp.em(c_qui, '17:12'),
             pg_temp.em(c_qui, '18:00'), 'livre', 'enviada', 'agenda-cliente:p11:sem-sim', pg_temp.em(c_qui, '17:12'),
             '{"dados": {"por_estimativa": true}}'::jsonb, pg_temp.em(c_qui, '17:12')
        from public.service_orders so where so.id = v_len;
      v_n2 := (public.agenda_saude(c_qui, pg_temp.em(c_qui, '17:20')) -> 'gestor' ->> 'cliente_estimativa_sem_aprovacao')::int;
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'P2f o zero cliente_estimativa_sem_aprovacao da saúde: 0 com a confirmação pedida; a mensagem por estimativa que saiu sem o sim antes dos 3 dias conta 1',
      v_n = 0 and v_n2 = 1, format('%s / %s', v_n, v_n2));

    -- ── P3. A ficha na janela de veto (o ligar de qui 29/10 16:46: os dias de qui 29/10 a qua 18/11) ──
    begin
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      select format('%s|%s|%s|%s|%s|%s|%s|%s', q.tipo, q.chave = format('ficha_estimativa:%s:%s', v_rob, c_q05), q.critica, q.modo,
                    q.veto_ate = pg_temp.em(c_qua, '19:30'), q.opcao_padrao, q.recomendacao, q.service_order_id = v_len),
             q.texto
        into v_t, v_t2 from public.agenda_perguntas q where q.id = v_q;
      r2 := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '17:07'));
      v_res := pg_temp.ok(v_res, 'P3a a pergunta da ficha (qua 04/11 16:52, o Roberto amanhã no Lenine): o texto da §6.3 ("Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, qui 05/11 o dia todo — dia 3 de 6, pela minha estimativa. …"), chave ficha_estimativa:<pessoa>:<dia>, não crítica, de verdade, prazo qua 04/11 19:30, padrão e recomendação 1; o tique seguinte não repete',
        (r ->> 'perguntas')::int = 1 and (r ->> 'novas')::int = 1 and v_t = 'ficha_estimativa|t|f|ligado|t|1|1|t'
        and v_t2 = c_perg and (r2 ->> 'novas')::int = 0 and r2 -> 'pessoas' -> 0 ->> 'pergunta_id' = v_q::text
        and (select count(*) from public.agenda_perguntas q where q.tipo = 'ficha_estimativa') = 1,
        v_t || ' | ' || coalesce(v_t2, '-'));
      v_lin := public._agenda_linhas_do_fechamento(c_qua);
      -- (correção 2 da 7a, 20261031100985, os achados 15/18 de novo: a linha das perguntas do gestor com prazo vai com perda 76 —
      -- ganha o desempate das que perdem hoje)
      v_res := pg_temp.ok(v_res, 'P3b o fechamento das 17:30: a pergunta da ficha numa linha própria (pergunta, perda 76, com o pergunta_id, de verdade) — à frente do "dia" (70) e da pergunta de fato (30), que não a repete',
        exists (select 1 from jsonb_array_elements(v_lin) x where x ->> 'pergunta_id' = v_q::text and x ->> 'tipo' = 'pergunta'
                 and (x ->> 'perda')::int = 76 and x ->> 'modo' = 'ligado' and x ->> 'texto' = 'Agenda: ' || c_perg)
        and (select count(*) from jsonb_array_elements(v_lin) x where x ->> 'pergunta_id' = v_q::text) = 1,
        (select string_agg(x ->> 'tipo' || ':' || (x ->> 'perda'), ' ') from jsonb_array_elements(v_lin) x));
      -- não mostrada: às 19:30 a ficha fica segurada
      v_n := (select count(*) from public.whatsapp_send_queue);
      r := public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'P3c não mostrada: às 19:30 a ficha de qui 05/11 do Roberto fica recusada (veto), nada vai à fila; o que mudou conta ao dono (a ação equipe da vigia, no *o que mudou*: "Não mandei a ficha de qui 05/11 a Roberto (Lenine): …"); a pergunta fecha',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto' and (select count(*) from public.whatsapp_send_queue) = v_n
        and (select a.texto from public.agenda_acoes a where a.tipo = 'equipe' and a.origem = 'vigia' and a.executada
              and a.payee_id = v_rob and a.service_order_id = v_len and a.depois ->> 'motivo' = 'ficha_segurada') = c_acao
        and exists (select 1 from jsonb_array_elements(public._agenda_mudancas(c_qua, c_q05, true, true, null)) g
                     where g -> 'itens' ->> 0 = c_acao)
        and (select q.estado from public.agenda_perguntas q where q.id = v_q) = 'resolvida'
        and (select m.acao_id is not null from public.agenda_equipe_mensagens m where m.payee_id = v_rob and m.tipo = 'ficha'),
        pg_temp.equipe(v_rob) || ' | ' || coalesce((select string_agg(a.texto, ' | ') from public.agenda_acoes a where a.tipo = 'equipe'), '-'));
      r := public._agenda_rotina_confirmar(c_q05, pg_temp.em(c_q05, '07:45'));
      v_res := pg_temp.ok(v_res, 'P3d a confirmação da manhã de qui 05/11 também fica (recusada, veto): ela diria o dia de que o dono não soube; e o zero ficha_estimativa_sem_veto da saúde segue 0',
        pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto | confirmar 2026-11-05 recusada/veto'
        and (public.agenda_saude(c_q05, pg_temp.em(c_q05, '08:00')) -> 'gestor' ->> 'ficha_estimativa_sem_veto')::int = 0,
        pg_temp.equipe(v_rob));
      -- mostrada no fechamento de qui 05/11: a ficha de sex 06/11 sai às 19:30
      r := public._agenda_gestor_fichas(c_q05, pg_temp.em(c_q05, '16:52'));
      v_q2 := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      perform public.agenda_fechamento_registrar(c_q05,
        (select jsonb_agg(x) from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_q05)) x where x ->> 'pergunta_id' = v_q2::text),
        'fechamento', pg_temp.em(c_q05, '17:30'));
      v_n := (select count(*) from public.whatsapp_send_queue);
      r := public._agenda_rotina_ficha(c_q05, pg_temp.em(c_q05, '19:30'));
      v_res := pg_temp.ok(v_res, 'P3e mostrada no fechamento das 17:30 e não segurada: a ficha de sex 06/11 sai às 19:30 (enfileirada, na fila), sem ação ao dono; a pergunta fecha ("ela foi como eu disse")',
        pg_temp.equipe(v_rob) like '%ficha 2026-11-06 enfileirada' and (select count(*) from public.whatsapp_send_queue) = v_n + 1
        and (select count(*) from public.agenda_acoes a where a.tipo = 'equipe' and a.origem = 'vigia') = 1
        and (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q2)
            = 'resolvida:na hora da ficha você não a segurou: ela foi como eu disse'
        and (public.agenda_saude(c_q05, pg_temp.em(c_q05, '19:40')) -> 'gestor' ->> 'ficha_estimativa_sem_veto')::int = 0,
        pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- segurada (2) e o "mande" (1) pela palavra do dono
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r := public.agenda_decidir(v_q, 3::smallint, v_adm, 'whatsapp', 'três', c_qua, pg_temp.em(c_qua, '17:40'));
      r2 := public.agenda_decidir(v_q, 2::smallint, v_adm, 'whatsapp', 'segura', c_qua, pg_temp.em(c_qua, '17:40'));
      v_t := r ->> 'texto' || ' | ' || (r2 ->> 'texto');
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      perform public._agenda_rotina_confirmar(c_q05, pg_temp.em(c_q05, '07:45'));
      v_res := pg_temp.ok(v_res, 'P3f segurada (2): "Combinado: não mando a ficha de qui 05/11 para Roberto, nem a confirmação da manhã. Fale com Roberto." — a ficha e a confirmação da manhã ficam recusadas (veto), sem ação ao dono (ele sabe); a opção 3 não existe',
        v_t = 'Essa opção não existe. As opções são: 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele. | Combinado: não mando a ficha de qui 05/11 para Roberto, nem a confirmação da manhã. Fale com Roberto.'
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 recusada/veto | confirmar 2026-11-05 recusada/veto'
        and not exists (select 1 from public.agenda_acoes a where a.tipo = 'equipe' and a.origem = 'vigia')
        and (select q.estado || ':' || q.opcao_escolhida || ':' || q.mostrada_vezes || ':' || q.mostrada_via from public.agenda_perguntas q where q.id = v_q)
            = 'respondida:2:1:conversa',
        v_t || ' | ' || pg_temp.equipe(v_rob));
      r := public._agenda_gestor_fichas(c_q05, pg_temp.em(c_q05, '16:52'));
      v_q2 := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      r := public.agenda_decidir(v_q2, 1::smallint, v_adm, 'whatsapp', 'manda', c_q05, pg_temp.em(c_q05, '17:40'));
      perform public._agenda_rotina_ficha(c_q05, pg_temp.em(c_q05, '19:30'));
      v_res := pg_temp.ok(v_res, 'P3g o "mande" (1) pela conversa, sem a linha do fechamento: "Combinado: mando a ficha de sex 06/11 para Roberto." — quem responde viu (a mostrada conta) e a ficha sai às 19:30',
        r ->> 'texto' = 'Combinado: mando a ficha de sex 06/11 para Roberto.'
        and pg_temp.equipe(v_rob) like '%ficha 2026-11-06 enfileirada', r::text || ' | ' || pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o prazo pelo passo vetos: mostrada = vale a 1; não mostrada = fica aberta; a 2 nunca vale sem resposta
      r := public._agenda_gestor_fichas(c_s06, pg_temp.em(c_s06, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      v_t2 := r -> 'pessoas' -> 0 ->> 'texto';
      r2 := public._agenda_gestor_decidir(v_q, 2::smallint, null, 'prazo', null, c_s06, pg_temp.em(c_s06, '19:37'));
      r := public._agenda_gestor_vetos(c_s06, pg_temp.em(c_s06, '19:37'));
      v_t := (r ->> 'sem_mostrar') || ':' || (select q.estado from public.agenda_perguntas q where q.id = v_q);
      update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(c_s06, '17:30'), mostrada_via = 'fechamento'
       where id = v_q;
      r := public._agenda_gestor_vetos(c_s06, pg_temp.em(c_s06, '19:37'));
      v_res := pg_temp.ok(v_res, 'P3h o prazo (sex 06/11 19:30, a ficha de seg 09/11: "a ficha de segunda"): não mostrada, o passo vetos a deixa aberta; mostrada, vale a 1 ("sem resposta até sex 06/11 19:30: a ficha vai como eu disse"); a 2 não vale sem resposta',
        v_t2 = c_seg and v_t = '1:aberta' and (r ->> 'aplicadas')::int = 1
        and r2 ->> 'texto' = 'Essa opção não vale sem resposta: nada mudou.'
        and (select q.estado || ':' || q.resolvida_motivo from public.agenda_perguntas q where q.id = v_q)
            = 'resolvida:sem resposta até sex 06/11 19:30: a ficha vai como eu disse',
        v_t || ' | ' || r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o "como foi hoje?" das 17:00 de qui 05/11 (a confirmação da manhã saiu): sem o "mande", ele não leva a ficha protegida
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      perform public.agenda_fechamento_registrar(c_qua,
        (select jsonb_agg(x) from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_qua)) x
          where x ->> 'pergunta_id' = r -> 'pessoas' -> 0 ->> 'pergunta_id'), 'fechamento', pg_temp.em(c_qua, '17:30'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      perform public._agenda_rotina_confirmar(c_q05, pg_temp.em(c_q05, '07:45'));
      r := public._agenda_gestor_fichas(c_q05, pg_temp.em(c_q05, '16:52'));
      v_q := (r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid;
      begin
        perform public._agenda_rotina_como_foi(c_q05, pg_temp.em(c_q05, '17:00'));
        v_t := pg_temp.equipe(v_rob);
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      r2 := public.agenda_decidir(v_q, 1::smallint, v_adm, 'whatsapp', 'manda', c_q05, pg_temp.em(c_q05, '16:58'));
      perform public._agenda_rotina_como_foi(c_q05, pg_temp.em(c_q05, '17:00'));
      perform public._agenda_rotina_ficha(c_q05, pg_temp.em(c_q05, '19:30'));
      v_t2 := pg_temp.equipe(v_rob);
      v_res := pg_temp.ok(v_res, 'P3i o "como foi hoje?" das 17:00 (a confirmação da manhã saiu): sem o "mande" do dono ele vai sem a ficha protegida de amanhã (o dono ainda pode segurá-la até as 19:30); com o "mande", ela vai junto e as 19:30 não mandam outra',
        v_t = 'ficha 2026-11-05 enfileirada | confirmar 2026-11-05 enfileirada | como_foi 2026-11-05 enfileirada'
        and v_t2 = 'ficha 2026-11-05 enfileirada | confirmar 2026-11-05 enfileirada | como_foi 2026-11-05 enfileirada leva 2026-11-06'
        and (select m.texto like '%Amanhã%' or m.texto like '%amanhã%' from public.agenda_equipe_mensagens m
              where m.payee_id = v_rob and m.tipo = 'como_foi'),
        v_t || ' || ' || v_t2);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- só propor: a pergunta continua de verdade (das mensagens à equipe) e o dono responde; a de terça (sex 30/10, o João
      -- com o contato da rotina) pelo nome do dia
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_em, incluido_por)
      values (v_joao, true, pg_temp.em(c_qui, '10:00'), 'dono') on conflict (payee_id) do nothing;
      update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = pg_temp.em(c_qui, '18:00') where id;
      r := public._agenda_gestor_fichas(date '2026-10-30', pg_temp.em(date '2026-10-30', '16:52'));
      r2 := public.agenda_decidir((r -> 'pessoas' -> 0 ->> 'pergunta_id')::uuid, 1::smallint, v_adm, 'whatsapp', 'manda',
                                  date '2026-10-30', pg_temp.em(date '2026-10-30', '17:40'));
      v_res := pg_temp.ok(v_res, 'P3j com *gestor, só propor*, a proteção continua: a pergunta nasce de verdade ("Hoje às 19:30 a ficha de terça vai para João: Lenine, ter 03/11 o dia todo — dia 1 de 6, …", sex 30/10 com o Finados no meio) e o dono a responde',
        r -> 'pessoas' -> 0 ->> 'texto' = c_ter and r ->> 'modo' = 'ligado' and (r2 ->> 'ok')::boolean
        and r2 ->> 'texto' = 'Combinado: mando a ficha de ter 03/11 para João.', r::text || ' | ' || r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- fora da janela (o ligar de 01/10: a janela foi até qua 21/10): nada a perguntar e a ficha sai como antes
      update public.agenda_config set marcar_sozinho_desde = timestamptz '2026-10-01 16:46-03' where id;
      r := public._agenda_gestor_fichas(c_qua, pg_temp.em(c_qua, '16:52'));
      perform public._agenda_rotina_ficha(c_qua, pg_temp.em(c_qua, '19:30'));
      v_res := pg_temp.ok(v_res, 'P3k fora da janela de veto (o ligar de 01/10, ficha_veto_dias 21): o passo fichas pula ("fora da janela da ficha") e a ficha de qui 05/11 sai às 19:30 como antes',
        (r ->> 'pulado')::boolean and r ->> 'motivo' = 'fora da janela da ficha'
        and pg_temp.equipe(v_rob) = 'ficha 2026-11-05 enfileirada' and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'ficha_estimativa'),
        r::text || ' | ' || pg_temp.equipe(v_rob));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- as bordas da janela e quem fica de fora: o dono e o dia sem estimativa da pessoa
    v_res := pg_temp.ok(v_res, 'P3l a janela é contada pelo dia da ficha (de qui 29/10 a qua 18/11, como o zero da saúde); o dono e o dia sem alocação da pessoa pela estimativa sempre podem sair',
      not public._agenda_ficha_liberada(v_rob, c_q05, pg_temp.em(c_qua, '19:30'))
      and public._agenda_ficha_liberada(public._agenda_dono(null), date '2026-11-03', pg_temp.em(date '2026-10-30', '19:30'))
      and public._agenda_ficha_liberada(v_rob, date '2026-11-03', pg_temp.em(date '2026-10-30', '19:30'))
      and public._agenda_ficha_liberada(v_rob, date '2026-11-19', pg_temp.em(date '2026-11-18', '19:30'))
      and not public._agenda_ficha_liberada(v_rob, date '2026-11-18', pg_temp.em(date '2026-11-17', '19:30'))
      and exists (select 1 from public.agenda_alocacoes a where a.payee_id = v_rob and a.dia = date '2026-11-18' and a.duracao_fonte = 'orcamento')
      and exists (select 1 from public.agenda_alocacoes a where a.payee_id = v_rob and a.dia = date '2026-11-19' and a.duracao_fonte = 'orcamento'),
      null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── P4 e P5. As cópias e o de antes, byte a byte ───────────────────────────────────────────────────────────────
do $copias$
declare
  v_res  jsonb := '[]'::jsonb;
  v_c6   text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  v_eq   text := coalesce(current_setting('agenda_teste.mig_equipe_fase3', true), '');
  v_p9   text := coalesce(current_setting('agenda_teste.mig_revisao_fase7a', true), '');
  v_p7   text := coalesce(current_setting('agenda_teste.mig_rodada_fase7a', true), '');
  v_p1   text := coalesce(current_setting('agenda_teste.mig_base_fase7a', true), '');
  r      record;
  v_novo text;
  v_n    int;
  v_a    text;
  v_b    text;
  d      date;
  v_x    jsonb;
  v_y    jsonb;
  v_len  uuid;
begin
  if v_c6 = '' or v_eq = '' or v_p9 = '' or v_p7 = '' or v_p1 = '' then
    insert into _resultado values ('P4 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_cliente_registrar', 'public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid)', v_c6, '20261029100900', 3),
      ('_agenda_rotina_ficha', 'public._agenda_rotina_ficha(date, timestamptz)', v_eq, '20261026100300', 2),
      ('_agenda_rotina_como_foi', 'public._agenda_rotina_como_foi(date, timestamptz)', v_eq, '20261026100300', 1),
      ('_agenda_rotina_confirmar', 'public._agenda_rotina_confirmar(date, timestamptz)', v_eq, '20261026100300', 1),
      ('_agenda_gestor_decidir', 'public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', v_p9, '20261031100750', 2),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', v_p7, '20261031100600', 3),
      ('_agenda_modo_da_pergunta', 'public._agenda_modo_da_pergunta(text, text)', v_p1, '20261031100000', 1)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    -- (a correção da 7a, 20261031100980, recriou _agenda_linhas_do_fechamento: a cópia do P11 é conferida no texto da migration
    -- do P11, agenda_teste.mig_protecoes_fase7a)
    -- (a correção 2 da 7a, 20261031100985, recriou _agenda_rotina_ficha — a ficha de quem não tem telefone —: a mesma régua)
    if r.nome in ('_agenda_linhas_do_fechamento', '_agenda_rotina_ficha')
       and coalesce(current_setting('agenda_teste.mig_protecoes_fase7a', true), '') <> '' then
      v_novo := pg_temp.corpo(current_setting('agenda_teste.mig_protecoes_fase7a', true), r.nome);
    end if;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: \(7a P11', 'g');
    v_res := pg_temp.ok(v_res,
      format('P4 %s: sem os %s blocos "-- FASE 7: (7a P11", é o corpo de %s (a mais nova antes do P11)', r.nome, r.blocos, r.versao),
      v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_p11(v_novo) = pg_temp.corpo(r.fonte, r.nome),
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
             length(pg_temp.sem_p11(v_novo))));
  end loop;

  -- P5a o modo de cada tipo da lista fechada: o de antes, menos a ficha_estimativa
  execute replace(pg_temp.inteira(v_p1, '_agenda_modo_da_pergunta'), 'create or replace function public._agenda_modo_da_pergunta(',
                  'create function pg_temp.modo_antes(');
  begin
    update public.agenda_config set modo_equipe = 'sombra', modo_marcar_sozinho = 'ligado', modo_proposta = 'ligado' where id;
    select string_agg(t, ',' order by t) filter (where public._agenda_modo_da_pergunta(t, t || ':x') is distinct from pg_temp.modo_antes(t, t || ':x')),
           count(*)
      into v_a, v_n
      from (select unnest(regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g')) as t
              from pg_constraint c where c.conname = 'agenda_perguntas_tipo_check') x;
    v_res := pg_temp.ok(v_res, 'P5a o modo de quem faz cada tipo da lista fechada é o de antes, menos a ficha_estimativa (agora o das mensagens à equipe)',
      v_a = 'ficha_estimativa' and v_n >= 40, coalesce(v_a, '-') || ' de ' || v_n);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('P5b a P5d (o replay)', true, 'PULADO: sem agenda_teste.replay2910 (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  execute replace(pg_temp.inteira(v_p7, '_agenda_linhas_do_fechamento'), 'create or replace function public._agenda_linhas_do_fechamento(',
                  'create function pg_temp.linhas_antes(');
  execute replace(pg_temp.inteira(v_eq, '_agenda_rotina_ficha'), 'create or replace function public._agenda_rotina_ficha(',
                  'create function pg_temp.ficha_antes(');
  execute replace(pg_temp.inteira(v_eq, '_agenda_rotina_como_foi'), 'create or replace function public._agenda_rotina_como_foi(',
                  'create function pg_temp.como_foi_antes(');
  execute replace(pg_temp.inteira(v_eq, '_agenda_rotina_confirmar'), 'create or replace function public._agenda_rotina_confirmar(',
                  'create function pg_temp.confirmar_antes(');
  execute replace(pg_temp.inteira(v_c6, '_agenda_cliente_registrar'), 'create or replace function public._agenda_cliente_registrar(',
                  'create function pg_temp.registrar_antes(');
  begin
    perform pg_temp.fixtures();
    v_len := pg_temp.os('OS-00074');
    -- P5b as linhas do fechamento sem a pergunta da ficha (o gestor ligado, o Lenine marcado): iguais às de antes
    v_a := '';
    v_b := '';
    foreach d in array array[date '2026-10-29', date '2026-10-30', date '2026-11-04', date '2026-11-05'] loop
      v_a := v_a || public._agenda_linhas_do_fechamento(d)::text;
      v_b := v_b || pg_temp.linhas_antes(d)::text;
    end loop;
    v_res := pg_temp.ok(v_res, 'P5b sem a pergunta da ficha, as linhas do fechamento são as de antes, byte a byte (o gestor ligado, o Lenine e o Vanderlei marcados; qui 29/10, sex 30/10, qua 04 e qui 05/11)',
      v_a = v_b and length(v_a) > 200, md5(v_a) || ' / ' || md5(v_b));
    -- P5c as rotinas da equipe sem o ligar do gestor (marcar_sozinho_desde nulo): o mesmo que as de antes, de qua 04 a sex 06/11
    update public.agenda_config set marcar_sozinho_desde = null where id;
    v_x := '[]'::jsonb;
    v_y := '[]'::jsonb;
    begin
      foreach d in array array[date '2026-11-04', date '2026-11-05'] loop
        perform public._agenda_rotina_confirmar(d, pg_temp.em(d, '07:45'));
        perform public._agenda_rotina_como_foi(d, pg_temp.em(d, '17:00'));
        perform public._agenda_rotina_ficha(d, pg_temp.em(d, '19:30'));
      end loop;
      v_x := (select coalesce(jsonb_agg(jsonb_build_array(m.payee_id, m.dia, m.tipo, m.estado, m.recusa_motivo, m.texto, m.leva_ficha_de)
                                        order by m.payee_id, m.dia, m.tipo), '[]'::jsonb) from public.agenda_equipe_mensagens m);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      foreach d in array array[date '2026-11-04', date '2026-11-05'] loop
        perform pg_temp.confirmar_antes(d, pg_temp.em(d, '07:45'));
        perform pg_temp.como_foi_antes(d, pg_temp.em(d, '17:00'));
        perform pg_temp.ficha_antes(d, pg_temp.em(d, '19:30'));
      end loop;
      v_y := (select coalesce(jsonb_agg(jsonb_build_array(m.payee_id, m.dia, m.tipo, m.estado, m.recusa_motivo, m.texto, m.leva_ficha_de)
                                        order by m.payee_id, m.dia, m.tipo), '[]'::jsonb) from public.agenda_equipe_mensagens m);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'P5c sem o ligar do gestor, a ficha, a confirmação e o "como foi hoje?" de qua 04 e qui 05/11 são as de antes, byte a byte (as mesmas mensagens, estados e textos)',
      v_x = v_y and jsonb_array_length(v_x) >= 3, md5(v_x::text) || ' / ' || md5(v_y::text) || ' ' || jsonb_array_length(v_x));
    -- P5d o registro da mensagem ao cliente sem estimativa (os dias do dono): o de antes, byte a byte
    update public.os_planejamento set dias = 6, estimativa_fonte = 'dono', estimativa_em = pg_temp.em(date '2026-10-29', '17:00')
     where service_order_id = v_len;
    begin
      v_x := public._agenda_cliente_registrar('confirmar', null, v_len, date '2026-11-03', '{}'::jsonb, pg_temp.em(date '2026-10-30', '09:00'),
                                              null, 'rodada', null, pg_temp.em(date '2026-10-29', '17:10'));
      v_x := (v_x - 'id' - 'pergunta_id')
             || (select jsonb_build_object('base', m.base, 'aprovacao', m.aprovacao, 'texto', m.texto) from public.agenda_cliente_mensagens m
                  where m.id = (v_x ->> 'id')::uuid)
             || (select jsonb_build_object('perguntas', count(*)) from public.agenda_perguntas q where q.tipo = 'cliente_aprovar');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      v_y := pg_temp.registrar_antes('confirmar', null, v_len, date '2026-11-03', '{}'::jsonb, pg_temp.em(date '2026-10-30', '09:00'),
                                     null, 'rodada', null, pg_temp.em(date '2026-10-29', '17:10'));
      v_y := (v_y - 'id' - 'pergunta_id')
             || (select jsonb_build_object('base', m.base, 'aprovacao', m.aprovacao, 'texto', m.texto) from public.agenda_cliente_mensagens m
                  where m.id = (v_y ->> 'id')::uuid)
             || (select jsonb_build_object('perguntas', count(*)) from public.agenda_perguntas q where q.tipo = 'cliente_aprovar');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'P5d sem estimativa (os dias do dono), o registro da confirmação do Lenine é o de antes, byte a byte (a saída, a base, a aprovação e a pergunta ao dono)',
      v_x = v_y and v_x ? 'base', left(v_x::text, 300) || ' / ' || left(v_y::text, 300));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$copias$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
