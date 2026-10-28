-- Prova da rodada do cliente da Agenda de Produção, Fase 5 (pacote P3): a rodada, os passos que decidem qual mensagem-
-- modelo vai a quem e quando, o risco da data dita, a aprovação dos 3 primeiros dias, as críticas, a decisão do dono e a
-- saúde (migration 20261028100300).
-- bancada: depende de 20261028100300
--
--   R0  portas: a rodada só para service_role; os passos, a decisão, o cancelar e o acorde para ninguém de fora (nem o
--       service_role); as leituras (as horas, o risco, o ouviu) para authenticated e service_role, nunca anon; security
--       definer só a rodada e a decisão; search_path fixo
--   R1  orquestração: desligado = só o passo fila ({rodou: false}, nada registrado, nenhuma rodada gravada); sombra = só
--       registra (a chave :sombra, nada na fila); um passo que falha não derruba os outros (app_error_logs cliente:<passo>);
--       agenda_vigia_rodadas com rotina cliente
--   R2  confirmar (o Flávio): nada às 10:00; às 17:00 um toque só em sáb 31/10 09:00, o acesso (M4), o texto exato; com o
--       acesso conhecido, a confirmação 'unico'; o par normal (o Lenine, D = sex 06/11): a confirmação de ter 03/11 09:00
--       registrada na véspera às 17:00, a véspera de qui 05/11 registrada na qua 04/11 às 17:00; a véspera pulada quando a
--       confirmação saiu há menos de 2 dias
--   R3  o material chegou (M3) × a nova data (M7) (o Vanderlei): o texto; sem sinal de espera, nada; o M3 substitui a
--       confirmação e a véspera do mesmo dia
--   R4  o aviso de atraso (o Nelson): nasce no 1º tique a partir das 17:00 do dia do risco (e não às 10:00) e sai na manhã
--       seguinte; com o prometido a até 2 dias úteis, na hora; a data dita que passou (ou que passaria antes do aviso) não
--       sai e vira a pergunta crítica "passou" (uma vez, com o acorde); o 2º atraso e o atraso longo viram pergunta crítica;
--       o aviso velho sai do caminho quando o risco muda; o risco nunca vem com a data vencida sem passou
--   R5  a mudança no dia (M10): o *choveu* com o dia que o cliente ouviu; a véspera do dia novo não repete; sem decisão =
--       o acorde ao dono e nada ao cliente; o dia tirado a pedido do cliente não manda nada
--   R6  o andamento (o 1º dia às 18:00 "começamos hoje"; à noite, "começamos ontem" na manhã seguinte; o semanal), o "ficou
--       pronto" (só depois da conclusão), o lembrete (3 dias depois, pulando o feriado) e o pós-serviço (entre 09 e 11 de
--       segunda a sexta; depois disso, o próximo dia útil), cada um uma vez
--   R7  a aprovação: o tipo novo pede (cliente_aprovar, o texto ao dono, nada na fila); 3 dias aprovados = livre; o "segura"
--       e a preparada pelo dono não contam; a pedida sem resposta vence (e a pergunta junto)
--   R8  o tipo fora das ondas, com o modo ligado, fica em teste (sombra)
--   R9  idempotência: o mesmo tique de novo não duplica mensagem, fila, ação nem pergunta
--   R10 agenda_decidir: cliente_aprovar 1 (manda) e 2 (segura); cliente_aviso 1 (você liga), 2 (manda; com o teto cheio não
--       sai) e 3 (não avisa); a opção que não existe; em teste nada sai; a pergunta sem mensagem (a data passou)
--   R11 agenda_saude().cliente: os zeros e o ok; forçar cada violação dá 1 e o ok cai
--   R12 as cópias de agenda_decidir (× 20261026100300) e agenda_saude (× 20261027100500) só mudam nos blocos "-- FASE 5:"
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_rodada.sql
--   R0 e R12 rodam em qualquer lugar (R12 só com as migrations antigas como texto); o resto só na bancada (a fixture-fase5;
--   fora dela, PULADO). Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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

-- p_sql (que devolve um valor) como o papel p_papel: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.hora(p_t timestamptz) returns text language sql immutable as $f$
  select to_char(p_t at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
$f$;

-- Liga a mensagem ao cliente (o modo, os tipos — todos, se null — e os dias de aprovação).
create function pg_temp.ligar(p_modo text default 'ligado', p_tipos text[] default null, p_aprov int default 0) returns void
language sql as $f$
  update public.agenda_config
     set modo_cliente = p_modo, cliente_aprovacao_dias = p_aprov,
         cliente_tipos_ligados = coalesce(p_tipos, array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                          'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                          'pos_servico', 'mudanca_no_dia'])
   where id
$f$;

-- Um tique da rodada, com o "hoje" de quem lê o relógio (_hoje_brt) acompanhando.
create function pg_temp.vig(p_quando text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_quando, 10), true);
  return public.agenda_cliente_vigiar(left(p_quando, 10)::date, pg_temp.em(p_quando));
end $f$;

-- As mensagens de uma OS (sem a do Nelson de 22/10, da fixture): [{tipo, variante, modo, estado, motivo, aprovacao,
-- enviar, texto}] na ordem em que nasceram.
create function pg_temp.msgs(p_os uuid, p_tipo text default null) returns jsonb language sql stable as $f$
  select coalesce(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'variante', m.variante, 'modo', m.modo, 'estado', m.estado,
                                               'motivo', m.recusa_motivo, 'aprovacao', m.aprovacao,
                                               'enviar', pg_temp.hora(m.enviar_em), 'texto', m.texto, 'id', m.id,
                                               'dia_alvo', m.dia_alvo, 'prometido_tipo', m.prometido_tipo,
                                               'valida', pg_temp.hora(m.valida_ate), 'pergunta_id', m.pergunta_id,
                                               'chave', m.dedupe_key)
                            order by m.criada_em, m.id), '[]'::jsonb)
    from public.agenda_cliente_mensagens m
   where m.service_order_id = p_os and (p_tipo is null or m.tipo = p_tipo)
     and m.id <> 'd5000000-0000-4000-8000-0000000000a1'
$f$;
create function pg_temp.n_fila() returns int language sql stable as $f$
  select count(*)::int from public.whatsapp_send_queue q where q.source = 'agenda-cliente'
$f$;
create function pg_temp.n_msgs() returns int language sql stable as $f$
  select count(*)::int from public.agenda_cliente_mensagens m where m.id <> 'd5000000-0000-4000-8000-0000000000a1'
$f$;
create function pg_temp.pergunta(p_id uuid) returns jsonb language sql stable as $f$
  select to_jsonb(q) from public.agenda_perguntas q where q.id = p_id
$f$;

-- Uma mensagem posta à mão (o que um tique de antes teria deixado: enviada, enfileirada…).
create function pg_temp.falsa(p_cli uuid, p_os uuid, p_tipo text, p_chave text, p_em text, p_estado text default 'enviada',
                              p_aprov text default 'aprovada', p_origem text default 'rodada', p_modo text default 'ligado',
                              p_base jsonb default '{}', p_var text default null, p_texto text default 'mensagem de teste (AG5R)',
                              p_dia date default null)
returns uuid language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, base,
                                               enviar_em, valida_ate, aprovacao, aprovada_em, estado, recusa_motivo, dedupe_key,
                                               enviada_em, fila_id, criada_em)
  values (p_cli, p_os, p_tipo, p_var, p_origem, p_dia, p_modo, p_texto, p_base, pg_temp.em(p_em), pg_temp.em(p_em) + interval '9 hours',
          p_aprov, case when p_aprov in ('aprovada', 'segurada') then pg_temp.em(p_em) end, p_estado,
          case when p_estado = 'recusada' then 'segurada' end, p_chave,
          case when p_estado in ('enviada', 'respondida', 'sem_resposta') then pg_temp.em(p_em) end,
          case when p_estado = 'enfileirada' then gen_random_uuid() end, pg_temp.em(p_em))
  returning id
$f$;

-- O corpo de uma função numa migration (entre "as $function$" e "$function$;").
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'as $function$\n' in v) + length(E'as $function$'));
  return left(v, position(E'\n$function$;' in v));
end $f$;
-- O corpo sem os blocos "-- FASE 5: … -- FASE 5: fim" (linhas).
create function pg_temp.sem_fase5(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    -- FASE 6 (P6): também os blocos "-- FASE 6: … -- FASE 6: fim" (agenda_desfazer, agenda_decidir e agenda_saude foram
    -- recriadas de novo em 20261029100600, só com blocos da Fase 6 fora dos da Fase 5)
    if not v_bloco and l ~ '^\s*-- FASE [56]:' and l !~ '^\s*-- FASE [56]: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE [56]: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- ── R0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $r0$
declare
  v_res jsonb := '[]'::jsonb;
  f text;
  v_ninguem text[] := array[
    'public._agenda_cliente_material(date, timestamptz)', 'public._agenda_cliente_confirmar(date, timestamptz)',
    'public._agenda_cliente_atraso(date, timestamptz)', 'public._agenda_cliente_mudanca_no_dia(date, timestamptz)',
    'public._agenda_cliente_andamento(date, timestamptz)', 'public._agenda_cliente_pronto(date, timestamptz)',
    'public._agenda_cliente_pos_servico(date, timestamptz)', 'public._agenda_cliente_sem_resposta(date, timestamptz)',
    'public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz)',
    'public._agenda_cliente_cancelar(uuid, text, text)', 'public._agenda_cliente_acorde(uuid, text, text, date, date, uuid)'];
  v_leitura text[] := array[
    'public._agenda_cliente_toque(date)', 'public._agenda_cliente_proximo_toque(timestamptz)',
    'public._agenda_cliente_dia_seguinte(date)', 'public._agenda_cliente_vespera(date)', 'public._agenda_cliente_ultimo_fim(date)',
    'public._agenda_cliente_ja_registra(date, date, timestamptz)', 'public._agenda_cliente_risco(uuid, date)',
    'public._agenda_cliente_ouviu(uuid, date, timestamptz)'];
  v_ruins text := '';
begin
  v_res := pg_temp.ok(v_res, 'R0a a rodada do cliente: só service_role (nem authenticated, nem anon)',
    has_function_privilege('service_role', 'public.agenda_cliente_vigiar(date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_cliente_vigiar(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_cliente_vigiar(date, timestamptz)', 'execute')
    and pg_temp.como('authenticated', $q$select public.agenda_cliente_vigiar(date '2026-10-30', now())::text$q$) like 'erro 42501:%');
  foreach f in array v_ninguem loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'R0b os passos, a decisão, o cancelar e o acorde: ninguém de fora (nem o service_role)', v_ruins = '',
                      nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'R0c o service_role não decide nem roda um passo direto (o caminho é a rodada e agenda_decidir)',
    pg_temp.como('service_role', $q$select public._agenda_cliente_decidir(gen_random_uuid(), 1::smallint)::text$q$) like 'erro 42501:%'
    and pg_temp.como('service_role', $q$select public._agenda_cliente_atraso(date '2026-10-30', now())::text$q$) like 'erro 42501:%');
  v_ruins := '';
  foreach f in array v_leitura loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'R0d as leituras (as horas, o risco, o ouviu): authenticated e service_role, nunca anon', v_ruins = '',
                      nullif(v_ruins, ''));
  v_ruins := '';
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('agenda_cliente_vigiar', '_agenda_cliente_decidir', '_agenda_cliente_material',
                                '_agenda_cliente_confirmar', '_agenda_cliente_atraso', '_agenda_cliente_mudanca_no_dia',
                                '_agenda_cliente_andamento', '_agenda_cliente_pronto', '_agenda_cliente_pos_servico',
                                '_agenda_cliente_sem_resposta', '_agenda_cliente_cancelar', '_agenda_cliente_acorde',
                                '_agenda_cliente_toque', '_agenda_cliente_proximo_toque', '_agenda_cliente_dia_seguinte',
                                '_agenda_cliente_vespera', '_agenda_cliente_ultimo_fim', '_agenda_cliente_ja_registra',
                                '_agenda_cliente_risco', '_agenda_cliente_ouviu')
              and (p.prosecdef <> (p.proname in ('agenda_cliente_vigiar', '_agenda_cliente_decidir'))
                   or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%') loop
    v_ruins := v_ruins || f || ' ';
  end loop;
  v_res := pg_temp.ok(v_res, 'R0e security definer só a rodada e a decisão; todas com search_path fixo', v_ruins = '',
                      nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'R0f agenda_decidir continua só do service_role; agenda_saude de authenticated e service_role, nunca anon',
    has_function_privilege('service_role', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'execute')
    and has_function_privilege('authenticated', 'public.agenda_saude(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_saude(date, timestamptz)', 'execute'));
  perform pg_temp.gravar(v_res);
end
$r0$;

-- ── R1–R4 (a fixture-fase5) ─────────────────────────────────────────────────────────────────────────────
do $r1$
declare
  v_res jsonb := '[]'::jsonb;
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_van  constant uuid := '05000000-0000-4000-8000-000000000069';
  c_len  constant uuid := '05000000-0000-4000-8000-000000000074';
  c_rod  constant uuid := '05000000-0000-4000-8000-000000000096';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_cli_nel constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_cli_van constant uuid := 'c1000000-0000-4000-8000-000000000001';
  c_cli_rod constant uuid := 'c1000000-0000-4000-8000-000000000006';
  c_painel constant uuid := md5('peca:112:4')::uuid;
  -- correção C2 da Fase 5 (item 8): o Nelson tem 2 críticos sem previsão (e o painel em 11/11): o aviso é o "sem data"
  c_m6 constant text := 'Nelson, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então o serviço no seu veleiro, que estava para quinta (05/11), vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.';
  r     jsonb;
  r2    jsonb;
  x     jsonb;
  v_n   int;
  v_id  uuid;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('R1–R4 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  -- a fixture e tudo o que o bloco faz são desfeitos no fim (o próximo bloco a roda de novo)
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── R1. Orquestração ──
  r := pg_temp.vig('2026-10-30 17:00');
  v_res := pg_temp.ok(v_res, 'R1a desligado (a linha nasce assim): {rodou: false}, o passo fila rodou, nada registrado, nenhuma rodada gravada',
    r ->> 'rodou' = 'false' and r ->> 'modo' = 'desligado' and r ? 'fila' and pg_temp.n_msgs() = 0 and pg_temp.n_fila() = 0
    and not exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'cliente'), r::text);
  begin
    perform pg_temp.ligar('sombra');
    r := pg_temp.vig('2026-10-30 17:00');
    x := pg_temp.msgs(c_flav);
    v_res := pg_temp.ok(v_res, 'R1b sombra: rodou, a mensagem só registrada (modo sombra, a chave :sombra, a ação "Em teste"), nada na fila; a rodada gravada (rotina cliente, sem erros)',
      r ->> 'rodou' = 'true' and r ->> 'modo' = 'sombra' and jsonb_array_length(x) = 1 and x -> 0 ->> 'modo' = 'sombra'
      and x -> 0 ->> 'estado' = 'registrada' and x -> 0 ->> 'chave' like '%:sombra' and pg_temp.n_fila() = 0
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'cliente' and not a.executada
                     and a.depois ->> 'mensagem_id' = x -> 0 ->> 'id' and a.texto like 'Em teste: eu teria mandado para Flávio%')
      and (select count(*) from public.agenda_vigia_rodadas v where v.rotina = 'cliente' and v.erros = 0
             and v.contagens ->> 'modo_cliente' = 'sombra') = 1,
      r::text || ' ' || x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    execute $q$create or replace function public._agenda_cliente_atraso(p_hoje date, p_agora timestamptz) returns jsonb
               language plpgsql set search_path to 'public' as $x$ begin raise exception 'quebrei de propósito (AG5R)'; end $x$$q$;
    r := pg_temp.vig('2026-10-30 17:00');
    v_res := pg_temp.ok(v_res, 'R1c um passo que falha (o atraso) não derruba os outros: erros 1, a falha com o passo, app_error_logs cliente:atraso; a confirmação do Flávio registrada',
      (r ->> 'erros')::int = 1 and r -> 'falhas' -> 0 ->> 'passo' = 'atraso'
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'cliente:atraso')
      and jsonb_array_length(pg_temp.msgs(c_flav)) = 1 and jsonb_array_length(pg_temp.msgs(c_nel)) = 0
      and (select v.erros from public.agenda_vigia_rodadas v where v.rotina = 'cliente' order by v.rodou_em desc limit 1) = 1,
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R2. A confirmação, a véspera e o acesso ──
  begin
    perform pg_temp.ligar();
    r := pg_temp.vig('2026-10-30 10:00');
    v_res := pg_temp.ok(v_res, 'R2a às 10:00 de sex 30/10 nada ao Flávio (o toque é de sábado: só se registra a partir das 17:00)',
      jsonb_array_length(pg_temp.msgs(c_flav)) = 0, pg_temp.msgs(c_flav)::text);
    r := pg_temp.vig('2026-10-30 17:00');
    x := pg_temp.msgs(c_flav);
    v_res := pg_temp.ok(v_res, 'R2b às 17:00 um toque só ao Flávio: o acesso (M4, o acesso desconhecido) em sáb 31/10 às 09:00, válido até o fim da janela de sábado, com a assinatura (a 1ª mensagem)',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'acesso' and x -> 0 ->> 'enviar' = '31/10 09:00'
      and x -> 0 ->> 'valida' = '31/10 13:00' and x -> 0 ->> 'estado' = 'registrada' and x -> 0 ->> 'dia_alvo' = '2026-11-03'
      and x -> 0 ->> 'prometido_tipo' = 'firme'
      and x -> 0 ->> 'texto' = 'Bom dia, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Na terça (03/11) chegamos à tarde para a instalação do compressor. Para não perdermos a viagem: onde o seu motorhome vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.',
      x::text);
    -- sábado 09:00: o passo fila manda
    r := pg_temp.vig('2026-10-31 09:00');
    v_res := pg_temp.ok(v_res, 'R2c sáb 31/10 09:00: o passo fila enfileira o toque do Flávio',
      pg_temp.msgs(c_flav) -> 0 ->> 'estado' = 'enfileirada', pg_temp.msgs(c_flav)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.service_orders set site_access = 'A chave fica na portaria' where id = c_flav;
    r := pg_temp.vig('2026-10-30 17:00');
    x := pg_temp.msgs(c_flav);
    v_res := pg_temp.ok(v_res, 'R2d com o acesso conhecido, o toque único é a confirmação (M1 unico)',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'confirmar' and x -> 0 ->> 'variante' = 'unico'
      and x -> 0 ->> 'enviar' = '31/10 09:00'
      and x -> 0 ->> 'texto' like 'Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. A instalação do compressor fica para terça (03/11), à tarde%. Pode ser? Responda SIM, ou me diga se algo mudou.',
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    r := pg_temp.vig('2026-11-02 16:45');
    v_n := jsonb_array_length(pg_temp.msgs(c_len));
    r := pg_temp.vig('2026-11-02 17:00');
    x := pg_temp.msgs(c_len);
    v_res := pg_temp.ok(v_res, 'R2e o Lenine (D = sex 06/11): a confirmação de ter 03/11 09:00 (D − 3 dias úteis) registrada na véspera, a partir das 17:00 (às 16:45, nada); a véspera ainda não',
      v_n = 0 and jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'confirmar' and x -> 0 ->> 'variante' = 'primeira'
      and x -> 0 ->> 'enviar' like '03/11 09:0%' and x -> 0 ->> 'dia_alvo' = '2026-11-06', x::text);
    r := pg_temp.vig('2026-11-03 09:15');
    v_res := pg_temp.ok(v_res, 'R2f na hora, a confirmação do Lenine (sem telefone no cadastro) é recusada sem_telefone; nada na fila dele',
      pg_temp.msgs(c_len) -> 0 ->> 'estado' = 'recusada' and pg_temp.msgs(c_len) -> 0 ->> 'motivo' = 'sem_telefone', pg_temp.msgs(c_len)::text);
    r := pg_temp.vig('2026-11-04 17:00');
    x := pg_temp.msgs(c_len);
    v_res := pg_temp.ok(v_res, 'R2g a véspera do Lenine (qui 05/11 às 09:00) registrada na qua 04/11 às 17:00: o acesso (M4), "Amanhã"',
      jsonb_array_length(x) = 2 and x -> 1 ->> 'tipo' = 'acesso' and x -> 1 ->> 'enviar' like '05/11 09:0%'
      and x -> 1 ->> 'texto' like 'Bom dia, Lenine! Aqui é o Gustavo, da HBR Marine Solutions. Amanhã chegamos %', x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    -- o Rodrigo (D = qua 04/11): a confirmação foi para ele na segunda às 10:00 (posta à mão); a véspera de ter 03/11 pula
    perform pg_temp.falsa(c_cli_rod, c_rod, 'confirmar', 'agenda-cliente:r2h', '2026-11-02 10:00', p_dia => date '2026-11-04',
                          p_base => '{"dia_alvo": "2026-11-04"}', p_var => 'seguinte');
    r := pg_temp.vig('2026-11-02 17:00');
    v_res := pg_temp.ok(v_res, 'R2h a véspera não sai quando a confirmação saiu há menos de 2 dias corridos',
      (r #>> '{contagens,confirmar,vespera_pulada}')::int >= 1
      and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_rod and m.tipo in ('vespera', 'acesso')),
      r #>> '{contagens,confirmar}');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R3. O material chegou (M3) × a nova data (M7) ──
  begin
    perform pg_temp.ligar();
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-30'
     where service_order_id = c_van and situacao not in ('na_mao', 'dispensado');
    -- sem sinal de que ele esperava pelo material: nada pelo passo material
    r := pg_temp.vig('2026-10-30 10:00');
    v_n := jsonb_array_length(pg_temp.msgs(c_van));
    perform public._agenda_cliente_gravar_prometido(c_van, 'condicional', date '2026-11-03', date '2026-11-06', 'dono', null,
                                                    pg_temp.em('2026-10-29 10:00'), 'teste (AG5R)');
    r := pg_temp.vig('2026-10-30 10:15');
    x := pg_temp.msgs(c_van);
    v_res := pg_temp.ok(v_res, 'R3a o material do Vanderlei chegou e ele ouviu uma data condicional: o material chegou (M3) na hora, com o dia do plano; sem sinal de espera, nada',
      v_n = 0 and jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'material_chegou' and x -> 0 ->> 'enviar' = '30/10 10:15'
      and x -> 0 ->> 'estado' = 'enfileirada' and x -> 0 ->> 'valida' = '31/10 13:00'
      and x -> 0 ->> 'texto' = 'Olá, Vanderlei! Aqui é o Gustavo, da HBR Marine Solutions. Boa notícia: o material do serviço no Mar Azul chegou e já foi conferido. Podemos começar terça (03/11), o dia todo? Responda SIM, ou me diga um dia melhor.',
      x::text);
    r := pg_temp.vig('2026-10-30 17:00');
    v_res := pg_temp.ok(v_res, 'R3b o M3 substitui a confirmação e a véspera do mesmo dia (nada mais ao Vanderlei às 17:00)',
      jsonb_array_length(pg_temp.msgs(c_van)) = 1, pg_temp.msgs(c_van)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-30'
     where service_order_id = c_van and situacao not in ('na_mao', 'dispensado');
    perform pg_temp.falsa(c_cli_van, c_van, 'pode_atrasar', 'agenda-cliente:r3c', '2026-10-27 10:00', p_var => 'peca');
    r := pg_temp.vig('2026-10-30 10:15');
    x := pg_temp.msgs(c_van, 'nova_data');
    v_res := pg_temp.ok(v_res, 'R3c com o aviso de atraso enviado antes, é a nova data (M7), sem a assinatura (ele já recebeu)',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'estado' = 'enfileirada'
      and x -> 0 ->> 'texto' = 'Vanderlei, agora com data firme: o serviço no Mar Azul fica para terça (03/11), o dia todo. Desculpe pela mudança e obrigado pela paciência. Responda SIM para confirmar, ou me diga se precisa de outro dia.',
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R4. O aviso de atraso (o Nelson ouviu qui 05/11; o painel agora chega qua 11/11) ──
  begin
    perform pg_temp.ligar();
    r := pg_temp.vig('2026-10-30 10:00');
    v_res := pg_temp.ok(v_res, 'R4a às 10:00 o risco já existe, mas o aviso espera o fechamento (o prometido vence em mais de 2 dias úteis)',
      jsonb_array_length(pg_temp.msgs(c_nel)) = 0 and (r #>> '{contagens,atraso,esperando_fechamento}')::int = 1, r #>> '{contagens,atraso}');
    r := pg_temp.vig('2026-10-30 17:00');
    x := pg_temp.msgs(c_nel);
    v_res := pg_temp.ok(v_res, 'R4b no 1º tique a partir das 17:00 o aviso (M6 peça sem data: há crítico sem previsão — correção C2, item 8) nasce para sáb 31/10 09:00, válido até o fim de qui 05/11, sem prometido (não diz data), não crítico (6 dias úteis), com o texto do modelo',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'pode_atrasar' and x -> 0 ->> 'variante' = 'peca_sem_data'
      and x -> 0 ->> 'enviar' like '31/10 09:0%' and x -> 0 ->> 'valida' = '05/11 19:00' and x -> 0 ->> 'aprovacao' = 'livre'
      and x -> 0 ->> 'prometido_tipo' is null and x -> 0 ->> 'dia_alvo' = '2026-11-12' and x -> 0 ->> 'texto' = c_m6,
      x::text);
    -- o risco muda (a peça vai para qua 18/11): o aviso velho sai do caminho e nasce o novo (crítico: 11 dias úteis)
    update public.os_material set previsao_ate = date '2026-11-18' where service_order_part_id = c_painel;
    r := pg_temp.vig('2026-10-30 17:15');
    x := pg_temp.msgs(c_nel);
    v_res := pg_temp.ok(v_res, 'R4c a peça mudou de novo antes de o aviso sair: o velho fica recusada/desatualizada; o novo (19 a 20/11) nasce como pergunta crítica (atraso longo)',
      jsonb_array_length(x) = 2 and x -> 0 ->> 'estado' = 'recusada' and x -> 0 ->> 'motivo' = 'desatualizada'
      and x -> 1 ->> 'dia_alvo' = '2026-11-19' and x -> 1 ->> 'aprovacao' = 'critica' and x -> 1 ->> 'estado' = 'aguardando_dono',
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.os_planejamento set prometido_de = date '2026-11-03', prometido_ate = date '2026-11-03',
                                      prometido_original_ate = date '2026-11-03'
     where service_order_id = c_nel;
    r := pg_temp.vig('2026-10-30 10:00');
    x := pg_temp.msgs(c_nel);
    v_res := pg_temp.ok(v_res, 'R4d o prometido vence em até 2 dias úteis (ter 03/11): registra na hora (10:00), e é crítico (ter 03 → sex 13/11 = 8 dias úteis: atraso longo)',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'enviar' = '30/10 10:00' and x -> 0 ->> 'aprovacao' = 'critica'
      and pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'texto' like 'O serviço da OS-00112 de Nelson vai atrasar 10 dias (ter 03/11 → qui 12 e sex 13/11): recomendo você ligar.%',
      x::text || ' ' || coalesce(pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'texto', ''));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.agenda_config set atraso_longo_dias = 10 where id;
    update public.os_planejamento set prometido_de = date '2026-11-03', prometido_ate = date '2026-11-03',
                                      prometido_original_ate = date '2026-11-03'
     where service_order_id = c_nel;
    r := pg_temp.vig('2026-10-30 10:00');
    x := pg_temp.msgs(c_nel);
    v_res := pg_temp.ok(v_res, 'R4e o mesmo, com o atraso longo em 10 dias úteis: o aviso sai sozinho na hora (enfileirado às 10:00)',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'aprovacao' = 'livre' and x -> 0 ->> 'estado' = 'enfileirada'
      and x -> 0 ->> 'enviar' = '30/10 10:00', x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.os_planejamento set prometido_de = date '2026-10-29', prometido_ate = date '2026-10-29',
                                      prometido_original_ate = date '2026-10-29'
     where service_order_id = c_nel;
    x := public._agenda_cliente_risco(c_nel, date '2026-10-30');
    r := pg_temp.vig('2026-10-30 10:00');
    r2 := pg_temp.vig('2026-10-30 10:15');
    v_res := pg_temp.ok(v_res, 'R4f a data dita já passou (qui 29/10): o risco vem com passou; nada ao cliente; a pergunta crítica "passou" uma vez (o tique seguinte não repete), com o acorde ao dono',
      (x ->> 'passou')::boolean and (x ->> 'risco')::boolean and jsonb_array_length(pg_temp.msgs(c_nel)) = 0
      and (select count(*) from public.agenda_perguntas q where q.chave = 'cliente_aviso:' || c_nel || ':2026-10-29') = 1
      and (select q.critica and q.texto like 'A data que Nelson ouviu (qui 29/10) passou sem aviso. Recomendo você ligar hoje. 1) Você liga%'
             from public.agenda_perguntas q where q.chave = 'cliente_aviso:' || c_nel || ':2026-10-29')
      and jsonb_array_length(r -> 'acordes') = 1 and r -> 'acordes' -> 0 ->> 'texto' like 'A data que Nelson ouviu (qui 29/10) passou sem aviso%'
      and (r2 #>> '{contagens,atraso,passou}')::int = 0,
      x::text || ' ' || (r -> 'acordes')::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    -- o prometido é hoje e já passou da janela: o aviso só sairia amanhã — depois da data
    update public.os_planejamento set prometido_de = date '2026-10-30', prometido_ate = date '2026-10-30',
                                      prometido_original_ate = date '2026-10-30'
     where service_order_id = c_nel;
    r := pg_temp.vig('2026-10-30 19:30');
    v_res := pg_temp.ok(v_res, 'R4g o aviso que só sairia depois da data dita (hoje, às 19:30) não sai: a pergunta "passou"',
      jsonb_array_length(pg_temp.msgs(c_nel)) = 0
      and exists (select 1 from public.agenda_perguntas q where q.chave = 'cliente_aviso:' || c_nel || ':2026-10-30'), r #>> '{contagens,atraso}');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    perform pg_temp.falsa(c_cli_nel, c_nel, 'pode_atrasar', 'agenda-cliente:r4h', '2026-10-27 10:00', p_var => 'peca');
    r := pg_temp.vig('2026-10-30 17:00');
    x := pg_temp.msgs(c_nel, 'pode_atrasar');
    v_res := pg_temp.ok(v_res, 'R4h já houve um aviso de atraso enviado: o novo é o 2º atraso (pergunta crítica, o texto "vai atrasar de novo")',
      jsonb_array_length(x) = 2 and x -> 1 ->> 'aprovacao' = 'critica'
      and pg_temp.pergunta((x -> 1 ->> 'pergunta_id')::uuid) ->> 'texto' = 'O serviço da OS-00112 de Nelson vai atrasar de novo (qui 05/11 → qui 12 e sex 13/11). É o 2º atraso: recomendo você ligar. 1) Você liga e eu não mando nada (recomendo); 2) Eu mando o aviso escrito; 3) Não aviso agora.',
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.os_material set previsao_ate = date '2026-11-20' where service_order_part_id = c_painel;
    r := pg_temp.vig('2026-10-30 17:00');
    x := pg_temp.msgs(c_nel);
    v_res := pg_temp.ok(v_res, 'R4i a previsão em sex 20/11 (a faixa nova seg 23 e ter 24/11, 13 dias úteis): atraso longo (pergunta crítica, "vai atrasar 19 dias")',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'aprovacao' = 'critica' and x -> 0 ->> 'dia_alvo' = '2026-11-23'
      and pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'texto' like 'O serviço da OS-00112 de Nelson vai atrasar 19 dias (qui 05/11 → seg 23 e ter 24/11): recomendo você ligar.%',
      x::text || ' ' || coalesce(pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'texto', ''));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- o risco nunca vem com a data vencida sem passou (todas as OS da carteira com um prometido em qualquer dia)
  begin
    v_n := 0;
    for v_id in select k.service_order_id from public.os_carteira(date '2026-10-30') k loop
      perform public._agenda_cliente_gravar_prometido(v_id, 'firme', date '2026-10-20', date '2026-10-20', 'dono', null,
                                                      pg_temp.em('2026-10-19 10:00'), 'teste (AG5R)');
      x := public._agenda_cliente_risco(v_id, date '2026-10-30');
      if x is not null and coalesce((x ->> 'risco')::boolean, false) and not coalesce((x ->> 'passou')::boolean, false) then
        v_n := v_n + 1;
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'R4j com a data dita vencida (20/10), nenhuma OS da carteira tem risco sem passou', v_n = 0, v_n::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r1$;

-- ── R5–R9 (a fixture-fase5) ─────────────────────────────────────────────────────────────────────────────
do $r5$
declare
  v_res jsonb := '[]'::jsonb;
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_len  constant uuid := '05000000-0000-4000-8000-000000000074';
  c_rob  constant uuid := '05000000-0000-4000-8000-000000000121';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_dono_os constant uuid := '05000000-0000-4000-8000-000000000123';
  c_cli_dono constant uuid := 'c1000000-0000-4000-8000-000000000013';
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  r     jsonb;
  x     jsonb;
  v_n   int;
  v_a   jsonb;
  v_b   jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('R5–R9 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  -- a fixture e tudo o que o bloco faz são desfeitos no fim (o próximo bloco a roda de novo)
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── R5. A mudança no dia (M10) ──
  begin
    perform pg_temp.ligar();
    -- o Flávio confirmou ter 03/11 (o "sim" do botão)
    update public.service_orders set client_confirmed_for = timestamptz '2026-11-03 13:00-03' where id = c_flav;
    perform set_config('agenda_teste.hoje', '2026-11-03', true);
    perform public.agenda_choveu(c_dono, null, 'whatsapp', date '2026-11-03', pg_temp.em('2026-11-03 10:00'));
    r := pg_temp.vig('2026-11-03 10:15');
    x := pg_temp.msgs(c_flav);
    v_res := pg_temp.ok(v_res, 'R5a choveu hoje no dia que o Flávio ouviu: a mudança no dia (M10 clima) com o dia novo do plano (qua 04/11), "hoje"; a véspera do dia novo não repete',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'mudanca_no_dia' and x -> 0 ->> 'variante' = 'clima'
      and x -> 0 ->> 'dia_alvo' = '2026-11-04' and x -> 0 ->> 'estado' = 'enfileirada'
      and x -> 0 ->> 'chave' = 'agenda-cliente:mudanca_no_dia:' || c_flav || ':2026-11-03'
      and x -> 0 ->> 'texto' = 'Bom dia, Flávio. Aqui é o Gustavo, da HBR Marine Solutions. Com a chuva de hoje não dá para trabalhar no seu motorhome com segurança. Podemos passar para quarta (04/11), pela manhã? Responda SIM ou me diga outro dia.'
      and (r #>> '{contagens,confirmar,vespera_pulada}')::int >= 1,
      x::text || ' ' || (r -> 'contagens')::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.service_orders set client_confirmed_for = timestamptz '2026-11-03 13:00-03' where id = c_flav;
    perform set_config('agenda_teste.hoje', '2026-11-02', true);
    -- a equipe saiu e a agenda não achou outro dia (a decisão está com o dono): os dias do Flávio cancelados, nenhum no lugar
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em('2026-11-02 10:00'), cancelada_motivo = 'pessoa'
     where service_order_id = c_flav and estado in ('publicada', 'fixada');
    r := pg_temp.vig('2026-11-02 10:15');
    v_res := pg_temp.ok(v_res, 'R5b sem dia novo (a decisão com o dono): nada ao Flávio; o acorde "Flávio esperava a equipe amanhã: a decisão está com você; recomendo ligar." (uma ação executada, devolvida pela rodada)',
      jsonb_array_length(pg_temp.msgs(c_flav)) = 0 and (r #>> '{contagens,mudanca_no_dia,sem_decisao}')::int = 1
      and jsonb_array_length(r -> 'acordes') = 1
      and r -> 'acordes' -> 0 ->> 'texto' = 'Flávio esperava a equipe amanhã: a decisão está com você; recomendo ligar.'
      and exists (select 1 from public.agenda_acoes a where a.id = (r -> 'acordes' -> 0 ->> 'acao_id')::uuid and a.executada
                    and a.tipo = 'cliente' and (a.depois ->> 'acorde')::boolean),
      r::text);
    r := pg_temp.vig('2026-11-02 10:30');
    v_res := pg_temp.ok(v_res, 'R5c o mesmo dia perdido no tique seguinte não cria outra ação de acorde',
      (select count(*) from public.agenda_acoes a where a.tipo = 'cliente' and a.service_order_id = c_flav) = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.service_orders set client_confirmed_for = timestamptz '2026-11-03 13:00-03' where id = c_flav;
    perform set_config('agenda_teste.hoje', '2026-11-02', true);
    -- o cliente avisou que o motorhome vai estar fora: o dia sai a pedido dele (cancelada_motivo cliente)
    update public.os_planejamento set bem_indisponivel = '{[2026-11-02,2027-01-31)}' where service_order_id = c_flav;
    perform public.agenda_replanejar(array[c_flav], 'o motorhome vai estar fora', 'vigia', date '2026-11-02', pg_temp.em('2026-11-02 10:00'));
    r := pg_temp.vig('2026-11-02 10:15');
    v_res := pg_temp.ok(v_res, 'R5d o dia tirado a pedido do cliente (o bem fora): nenhuma mudança no dia, nenhum acorde',
      jsonb_array_length(pg_temp.msgs(c_flav, 'mudanca_no_dia')) = 0 and (r #>> '{contagens,mudanca_no_dia,sem_decisao}')::int = 0
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'cliente' and a.service_order_id = c_flav and a.executada),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R6. O andamento, o "ficou pronto", o lembrete e o pós-serviço ──
  begin
    perform pg_temp.ligar();
    perform set_config('agenda_teste.hoje', '2026-11-03', true);
    perform public.agenda_registrar_dia(c_dono, date '2026-11-03', 'cumprido', null, c_flav, null, 'dia_feito', null,
                                        date '2026-11-03', pg_temp.em('2026-11-03 17:30'));
    r := pg_temp.vig('2026-11-03 17:45');
    x := pg_temp.msgs(c_flav, 'andamento');
    v_res := pg_temp.ok(v_res, 'R6a o 1º dia feito do Flávio (2 dias): o andamento às 18:00 do mesmo dia, "começamos hoje"',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'variante' = 'primeiro_dia' and x -> 0 ->> 'enviar' = '03/11 18:00'
      and x -> 0 ->> 'texto' = 'Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Começamos hoje a instalação do compressor. Seguimos com a previsão de terminar quarta (04/11).',
      x::text);
    r := pg_temp.vig('2026-11-03 18:00');
    v_res := pg_temp.ok(v_res, 'R6b uma vez só (o tique seguinte não repete)', jsonb_array_length(pg_temp.msgs(c_flav, 'andamento')) = 1, null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    perform set_config('agenda_teste.hoje', '2026-11-03', true);
    perform public.agenda_registrar_dia(c_dono, date '2026-11-03', 'cumprido', null, c_flav, null, 'dia_feito', null,
                                        date '2026-11-03', pg_temp.em('2026-11-03 19:20'));
    r := pg_temp.vig('2026-11-03 19:30');
    x := pg_temp.msgs(c_flav, 'andamento');
    v_res := pg_temp.ok(v_res, 'R6c o dia anotado à noite: o andamento vai na manhã seguinte (qua 04/11 08:00), "começamos ontem"',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'enviar' = '04/11 08:00'
      and x -> 0 ->> 'texto' like '%Começamos ontem a instalação do compressor.%', x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    update public.agenda_config set cliente_andamento_min_du = 2, cliente_andamento_intervalo_dias = 3 where id;
    perform set_config('agenda_teste.hoje', '2026-11-06', true);
    perform public.agenda_registrar_dia(c_dono, date '2026-11-06', 'cumprido', null, c_len, null, 'dia_feito', null,
                                        date '2026-11-06', pg_temp.em('2026-11-06 17:30'));
    r := pg_temp.vig('2026-11-09 09:15');
    x := pg_temp.msgs(c_len, 'andamento');
    v_res := pg_temp.ok(v_res, 'R6d o semanal (a OS de mais de cliente_andamento_min_du dias, a cada cliente_andamento_intervalo_dias): a chave da semana ISO, "1 de 3 dias feitos"',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'variante' = 'semanal'
      and x -> 0 ->> 'chave' = 'agenda-cliente:andamento:' || c_len || ':2026-S46'
      and x -> 0 ->> 'texto' = 'Olá, Lenine! Aqui é o Gustavo, da HBR Marine Solutions. Seguimos com o serviço no Brisa: 1 de 3 dias feitos, previsão de terminar terça (10/11).',
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    r := pg_temp.vig('2026-10-30 10:00');
    v_n := jsonb_array_length(pg_temp.msgs(c_luc));
    r := pg_temp.vig('2026-10-30 15:15');
    x := pg_temp.msgs(c_luc);
    v_res := pg_temp.ok(v_res, 'R6e o "ficou pronto" da Lucenira (concluída hoje às 15:00): às 10:00 nada; às 15:15, na hora, válido até o fim do 2º dia de janela (sáb 31/10)',
      v_n = 0 and jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'pronto' and x -> 0 ->> 'enviar' = '30/10 15:15'
      and x -> 0 ->> 'estado' = 'enfileirada' and x -> 0 ->> 'valida' = '31/10 13:00'
      and x -> 0 ->> 'texto' = 'Olá, Lucenira! Aqui é o Gustavo, da HBR Marine Solutions. A troca das baterias está concluída. Quando fica bom para combinarmos a entrega?',
      x::text);
    -- saiu
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-30 15:16')
     where source = 'agenda-cliente' and source_ref_id = (x -> 0 ->> 'id')::uuid;
    r := pg_temp.vig('2026-11-02 16:45');
    v_n := jsonb_array_length(pg_temp.msgs(c_luc, 'pronto_lembrete'));
    r := pg_temp.vig('2026-11-02 17:00');
    x := pg_temp.msgs(c_luc, 'pronto_lembrete');
    v_res := pg_temp.ok(v_res, 'R6f o lembrete 3 dias depois (seg 02/11 é Finados: ter 03/11 às 09:00), registrado na véspera às 17:00, uma vez',
      v_n = 0 and jsonb_array_length(x) = 1 and x -> 0 ->> 'enviar' like '03/11 09:0%'
      and x -> 0 ->> 'texto' = 'Lucenira, só para combinarmos a entrega da sua lancha: qual dia fica bom pra você?', x::text);
    r := pg_temp.vig('2026-11-03 09:15');
    v_res := pg_temp.ok(v_res, 'R6g o lembrete não se repete', jsonb_array_length(pg_temp.msgs(c_luc, 'pronto_lembrete')) = 1, null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    r := pg_temp.vig('2026-10-30 10:00');
    x := pg_temp.msgs(c_rob);
    v_res := pg_temp.ok(v_res, 'R6h o pós-serviço do Robson (entregue sex 23/10; o 5º dia, qua 28/10, já passou): hoje, entre 09 e 11, na hora',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'tipo' = 'pos_servico' and x -> 0 ->> 'enviar' like '30/10 10:0%'
      and x -> 0 ->> 'chave' = 'agenda-cliente:pos_servico:' || c_rob || ':pos'
      and x -> 0 ->> 'texto' like 'Olá, Robson! Aqui é o Gustavo, da HBR Marine Solutions. Tudo certo com %Se preferir não receber estas mensagens, é só responder PARAR.',
      x::text);
    r := pg_temp.vig('2026-10-30 10:15');
    v_res := pg_temp.ok(v_res, 'R6i uma por OS', jsonb_array_length(pg_temp.msgs(c_rob)) = 1, null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    r := pg_temp.vig('2026-10-30 12:00');
    x := pg_temp.msgs(c_rob);
    v_res := pg_temp.ok(v_res, 'R6j depois das 11:00 o pós-serviço vai ao próximo dia útil de janela, às 09:00 (ter 03/11: seg é Finados)',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'enviar' like '03/11 09:0%' and x -> 0 ->> 'estado' = 'registrada', x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar();
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
    values ('inbound', '5547900000307', 'text', 'Oi! (AG5R)', pg_temp.em('2026-10-29 18:00'), 'received');
    r := pg_temp.vig('2026-10-30 10:00');
    v_res := pg_temp.ok(v_res, 'R6k o Robson escreveu ontem: o pós-serviço espera (nada registrado)',
      jsonb_array_length(pg_temp.msgs(c_rob)) = 0 and (r #>> '{contagens,pos_servico,esperando_o_cliente}')::int = 1, r #>> '{contagens,pos_servico}');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R7. A aprovação dos 3 primeiros dias ──
  begin
    perform pg_temp.ligar(p_aprov => 3);
    r := pg_temp.vig('2026-10-30 10:00');
    x := pg_temp.msgs(c_rob);
    v_res := pg_temp.ok(v_res, 'R7a o tipo novo pede o dono: o pós-serviço do Robson esperando (pedida), a pergunta cliente_aprovar com o texto ao dono; nada dele na fila',
      jsonb_array_length(x) = 1 and x -> 0 ->> 'aprovacao' = 'pedida' and x -> 0 ->> 'estado' = 'aguardando_dono'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-cliente' and q.source_ref_id = (x -> 0 ->> 'id')::uuid)
      and pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'tipo' = 'cliente_aprovar'
      and pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'texto'
          = format('Mensagem para Robson (pós-serviço), sai agora: "%s". *manda cliente Robson* ou *segura cliente Robson*.', x -> 0 ->> 'texto'),
      x::text || ' ' || coalesce(pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'texto', ''));
    -- sem resposta até o fim da validade (o 3º dia de janela do envio: ter 03/11 19:00): vence, com a pergunta
    r := pg_temp.vig('2026-11-03 19:15');
    x := pg_temp.msgs(c_rob);
    v_res := pg_temp.ok(v_res, 'R7b a pedida sem resposta do dono vence (recusada/vencida, a aprovação vencida) e a pergunta junto; nada saiu',
      x -> 0 ->> 'estado' = 'recusada' and x -> 0 ->> 'motivo' = 'vencida' and x -> 0 ->> 'aprovacao' = 'vencida'
      and pg_temp.pergunta((x -> 0 ->> 'pergunta_id')::uuid) ->> 'estado' = 'vencida'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-cliente' and q.source_ref_id = (x -> 0 ->> 'id')::uuid),
      x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(p_aprov => 3);
    -- 3 dias distintos com o pós-serviço aprovado pelo dono (outras OS, da rodada, em ligado)
    perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pos_servico', 'agenda-cliente:r7:' || n, '2026-10-0' || n || ' 10:00')
       from generate_series(1, 3) n;
    r := pg_temp.vig('2026-10-30 10:00');
    v_res := pg_temp.ok(v_res, 'R7c com 3 dias aprovados o pós-serviço sai sozinho (livre, na fila)',
      pg_temp.msgs(c_rob) -> 0 ->> 'aprovacao' = 'livre' and pg_temp.msgs(c_rob) -> 0 ->> 'estado' = 'enfileirada', pg_temp.msgs(c_rob)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(p_aprov => 3);
    perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pos_servico', 'agenda-cliente:r7:' || n, '2026-10-0' || n || ' 10:00')
       from generate_series(1, 2) n;
    perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pos_servico', 'agenda-cliente:r7:3', '2026-10-03 10:00', 'recusada', 'segurada');
    perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pos_servico', 'agenda-cliente:r7:4', '2026-10-04 10:00', p_origem => 'dono');
    r := pg_temp.vig('2026-10-30 10:00');
    v_res := pg_temp.ok(v_res, 'R7d 2 dias aprovados + 1 segurado + 1 preparado pelo dono: ainda pede (o "segura" e a preparada não contam)',
      pg_temp.msgs(c_rob) -> 0 ->> 'aprovacao' = 'pedida', pg_temp.msgs(c_rob)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R8. O tipo fora das ondas fica em teste ──
  begin
    perform pg_temp.ligar(p_tipos => array['pode_atrasar']);
    r := pg_temp.vig('2026-10-30 15:15');
    r := pg_temp.vig('2026-10-30 17:00');
    v_res := pg_temp.ok(v_res, 'R8 em ligado só com o aviso de atraso nas ondas: o "ficou pronto" da Lucenira e o acesso do Flávio em teste (sombra, nada na fila); o aviso do Nelson em ligado',
      pg_temp.msgs(c_luc) -> 0 ->> 'modo' = 'sombra' and pg_temp.msgs(c_flav) -> 0 ->> 'modo' = 'sombra'
      and pg_temp.msgs(c_nel) -> 0 ->> 'modo' = 'ligado'
      and not exists (select 1 from public.whatsapp_send_queue q join public.agenda_cliente_mensagens m on m.id = q.source_ref_id
                       where q.source = 'agenda-cliente' and m.modo <> 'ligado'),
      pg_temp.msgs(c_luc)::text || ' ' || pg_temp.msgs(c_nel)::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R9. Idempotência ──
  begin
    perform pg_temp.ligar(p_aprov => 3);
    r := pg_temp.vig('2026-10-30 17:00');
    v_a := jsonb_build_object('msgs', pg_temp.n_msgs(), 'fila', pg_temp.n_fila(),
                              'acoes', (select count(*) from public.agenda_acoes a where a.tipo = 'cliente'),
                              'perguntas', (select count(*) from public.agenda_perguntas q where q.tipo like 'cliente%'));
    r := pg_temp.vig('2026-10-30 17:00');
    r := pg_temp.vig('2026-10-30 17:15');
    v_b := jsonb_build_object('msgs', pg_temp.n_msgs(), 'fila', pg_temp.n_fila(),
                              'acoes', (select count(*) from public.agenda_acoes a where a.tipo = 'cliente'),
                              'perguntas', (select count(*) from public.agenda_perguntas q where q.tipo like 'cliente%'));
    v_res := pg_temp.ok(v_res, 'R9 o mesmo tique de novo (e o seguinte) não duplica mensagem, fila, ação nem pergunta',
      v_a = v_b and (v_a ->> 'msgs')::int >= 3, v_a::text || ' × ' || v_b::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r5$;

-- ── R10–R11 (a fixture-fase5) ───────────────────────────────────────────────────────────────────────────
do $r10$
declare
  v_res jsonb := '[]'::jsonb;
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_rob  constant uuid := '05000000-0000-4000-8000-000000000121';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_dono_os constant uuid := '05000000-0000-4000-8000-000000000123';
  c_cli_dono constant uuid := 'c1000000-0000-4000-8000-000000000013';
  c_cli_nel constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_cli_luc constant uuid := 'c1000000-0000-4000-8000-000000000012';
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  r     jsonb;
  x     jsonb;
  v_p   uuid;
  v_id  uuid;
  s     jsonb;
  k     text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('R10–R11 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  -- a fixture e tudo o que o bloco faz são desfeitos no fim (o próximo bloco a roda de novo)
  begin
  execute current_setting('agenda_teste.fase5');

  -- ── R10. agenda_decidir ──
  begin
    perform pg_temp.ligar(p_aprov => 3);
    r := pg_temp.vig('2026-10-30 10:00');
    v_p := (pg_temp.msgs(c_rob) -> 0 ->> 'pergunta_id')::uuid;
    r := public.agenda_decidir(v_p, 1::smallint, c_dono, 'whatsapp', 'manda cliente Robson', date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    x := pg_temp.msgs(c_rob);
    v_res := pg_temp.ok(v_res, 'R10a cliente_aprovar 1: "Mando para Robson agora.", a mensagem aprovada (aprovada_por o dono) e na fila; a pergunta respondida (opção 1, as palavras)',
      r ->> 'ok' = 'true' and r ->> 'texto' = 'Mando para Robson agora.' and x -> 0 ->> 'aprovacao' = 'aprovada'
      and x -> 0 ->> 'estado' = 'enfileirada'
      and (select m.aprovada_por from public.agenda_cliente_mensagens m where m.id = (x -> 0 ->> 'id')::uuid) = c_dono
      and pg_temp.pergunta(v_p) ->> 'estado' = 'respondida' and pg_temp.pergunta(v_p) ->> 'opcao_escolhida' = '1'
      and pg_temp.pergunta(v_p) ->> 'resposta' = 'manda cliente Robson',
      r::text || ' ' || x::text);
    r := public.agenda_decidir(v_p, 1::smallint, c_dono, 'whatsapp', null, date '2026-10-30', pg_temp.em('2026-10-30 10:06'));
    v_res := pg_temp.ok(v_res, 'R10b a mesma pergunta de novo: "Essa pergunta já foi respondida ou resolvida."',
      r ->> 'ok' = 'false' and r ->> 'texto' = 'Essa pergunta já foi respondida ou resolvida.', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(p_aprov => 3);
    r := pg_temp.vig('2026-10-30 10:00');
    v_p := (pg_temp.msgs(c_rob) -> 0 ->> 'pergunta_id')::uuid;
    r := public.agenda_decidir(v_p, 2::smallint, c_dono, 'whatsapp', 'segura cliente Robson', date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    x := pg_temp.msgs(c_rob);
    v_res := pg_temp.ok(v_res, 'R10c cliente_aprovar 2: "Segurei a mensagem de Robson: ela não sai." (recusada/segurada, nada na fila)',
      r ->> 'texto' = 'Segurei a mensagem de Robson: ela não sai.' and x -> 0 ->> 'estado' = 'recusada'
      and x -> 0 ->> 'motivo' = 'segurada' and x -> 0 ->> 'aprovacao' = 'segurada' and pg_temp.n_fila() = 0, r::text || ' ' || x::text);
    r := public.agenda_decidir(v_p, 3::smallint, c_dono, 'whatsapp', null, date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    v_res := pg_temp.ok(v_res, 'R10d depois de respondida, nada mais muda', r ->> 'ok' = 'false', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(p_aprov => 3);
    r := pg_temp.vig('2026-10-30 10:00');
    v_p := (pg_temp.msgs(c_rob) -> 0 ->> 'pergunta_id')::uuid;
    r := public.agenda_decidir(v_p, 3::smallint, c_dono, 'whatsapp', null, date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    v_res := pg_temp.ok(v_res, 'R10e cliente_aprovar com opção que não existe: recusa, a pergunta continua aberta',
      r ->> 'ok' = 'false' and r ->> 'texto' like 'Essa opção não existe.%' and pg_temp.pergunta(v_p) ->> 'estado' = 'aberta', r::text);
    perform pg_temp.ligar('sombra', p_aprov => 3);
    r := public.agenda_decidir(v_p, 1::smallint, c_dono, 'whatsapp', null, date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    v_res := pg_temp.ok(v_res, 'R10f com o modo em teste: "As mensagens ao cliente estão em teste: nada sai ainda." e nada muda',
      r ->> 'ok' = 'false' and r ->> 'texto' = 'As mensagens ao cliente estão em teste: nada sai ainda.'
      and pg_temp.pergunta(v_p) ->> 'estado' = 'aberta' and pg_temp.n_fila() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- o aviso crítico (o 2º atraso do Nelson às 17:00, para sáb 09:00): as três opções
  for k in select unnest(array['1', '2', '3']) loop
    begin
      perform pg_temp.ligar(p_aprov => 0);
      perform pg_temp.falsa(c_cli_nel, c_nel, 'pode_atrasar', 'agenda-cliente:r10', '2026-10-27 10:00', p_var => 'peca');
      r := pg_temp.vig('2026-10-30 17:00');
      x := pg_temp.msgs(c_nel, 'pode_atrasar') -> 1;
      v_p := (x ->> 'pergunta_id')::uuid;
      r := public.agenda_decidir(v_p, k::smallint, c_dono, 'whatsapp', 'opção ' || k, date '2026-10-30', pg_temp.em('2026-10-30 17:05'));
      x := pg_temp.msgs(c_nel, 'pode_atrasar') -> 1;
      v_res := pg_temp.ok(v_res, format('R10g cliente_aviso %s: %s', k, case k when '1' then 'você liga (segurada, nada sai) e a ação crítica fica na trilha'
                                                              when '2' then 'manda (aprovada; sai no tique de sáb 09:00 — "Mando para Nelson amanhã às 09:0x.")'
                                                              else 'não avisa agora (segurada)' end),
        r ->> 'ok' = 'true'
        and r ->> 'texto' like case k when '1' then 'Combinado: você liga para Nelson; eu não mando nada.'
                                      when '2' then 'Mando para Nelson amanhã às 09:0_.' else 'Combinado: não aviso Nelson agora.' end
        and x ->> 'aprovacao' = case k when '2' then 'aprovada' else 'segurada' end
        and x ->> 'estado' = case k when '2' then 'aguardando_dono' else 'recusada' end
        and exists (select 1 from public.agenda_acoes a where a.pergunta_id = v_p and a.critica and a.executada and a.tipo = 'cliente'
                      and a.origem = 'dono')
        and pg_temp.pergunta(v_p) ->> 'opcao_escolhida' = k,
        r::text || ' ' || x::text);
      if k = '2' then
        r := pg_temp.vig('2026-10-31 09:00');
        v_res := pg_temp.ok(v_res, 'R10h a opção 2 sai no tique da hora (sáb 31/10 09:00: enfileirada)',
          pg_temp.msgs(c_nel, 'pode_atrasar') -> 1 ->> 'estado' = 'enfileirada', pg_temp.msgs(c_nel)::text);
      end if;
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
  end loop;
  begin
    perform pg_temp.ligar(p_aprov => 0);
    -- o prometido de ter 03/11 (na hora e crítico, às 10:00) e o Nelson já com uma mensagem hoje: a opção 2 não sai (teto)
    update public.os_planejamento set prometido_de = date '2026-11-03', prometido_ate = date '2026-11-03',
                                      prometido_original_ate = date '2026-11-03'
     where service_order_id = c_nel;
    r := pg_temp.vig('2026-10-30 10:00');
    v_p := (pg_temp.msgs(c_nel, 'pode_atrasar') -> 0 ->> 'pergunta_id')::uuid;
    perform pg_temp.falsa(c_cli_nel, c_nel, 'andamento', 'agenda-cliente:r10i', '2026-10-30 10:01', 'enfileirada', p_var => 'semanal');
    r := public.agenda_decidir(v_p, 2::smallint, c_dono, 'whatsapp', null, date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    v_res := pg_temp.ok(v_res, 'R10i cliente_aviso 2 com o teto do dia cheio: não sai, e o texto diz ("Não mandei para Nelson: o cliente já recebeu as mensagens que cabem … Recomendo ligar." — o motivo pela correção C2)',
      r ->> 'ok' = 'true' and r ->> 'texto' like 'Não mandei para Nelson: o cliente já recebeu as mensagens que cabem (no máximo 1 por dia e 3 por semana). Recomendo ligar.'
      and pg_temp.msgs(c_nel, 'pode_atrasar') -> 0 ->> 'estado' = 'recusada', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar(p_aprov => 0);
    update public.os_planejamento set prometido_de = date '2026-10-29', prometido_ate = date '2026-10-29',
                                      prometido_original_ate = date '2026-10-29'
     where service_order_id = c_nel;
    r := pg_temp.vig('2026-10-30 10:00');
    v_p := (select q.id from public.agenda_perguntas q where q.chave = 'cliente_aviso:' || c_nel || ':2026-10-29');
    r := public.agenda_decidir(v_p, 2::smallint, c_dono, 'whatsapp', null, date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    v_res := pg_temp.ok(v_res, 'R10j a pergunta "passou" (sem mensagem) com a opção 2: nada sai, "Não há aviso escrito para mandar para Nelson: …"',
      r ->> 'ok' = 'true' and r ->> 'texto' like 'Não há aviso escrito para mandar para Nelson: a data dita já passou%'
      and pg_temp.pergunta(v_p) ->> 'estado' = 'respondida' and jsonb_array_length(pg_temp.msgs(c_nel)) = 0
      and not exists (select 1 from public.whatsapp_send_queue q join public.agenda_cliente_mensagens m on m.id = q.source_ref_id
                       where q.source = 'agenda-cliente' and m.service_order_id = c_nel), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── R11. agenda_saude().cliente ──
  begin
    perform pg_temp.ligar(p_aprov => 0);
    r := pg_temp.vig('2026-10-30 10:00');
    r := pg_temp.vig('2026-10-30 17:00');
    s := public.agenda_saude(date '2026-10-30', pg_temp.em('2026-10-30 17:05'));
    v_res := pg_temp.ok(v_res, 'R11a agenda_saude().cliente: o modo, as ondas, os tipos liberados, a rodada, as mensagens por tipo; os zeros; o ok',
      s ->> 'ok' = 'true' and s #>> '{cliente,modo}' = 'ligado' and jsonb_array_length(s #> '{cliente,tipos_liberados}') = 11
      and (s #>> '{cliente,rodou_nas_ultimas_2h}')::boolean and s #> '{cliente,mensagens_7d,por_tipo}' ? 'pos_servico'
      and (s #>> '{cliente,fora_da_janela}')::int = 0 and (s #>> '{cliente,em_feriado_ou_domingo}')::int = 0
      and (s #>> '{cliente,acima_do_teto}')::int = 0 and (s #>> '{cliente,intervalo_curto}')::int = 0
      and (s #>> '{cliente,com_texto_proibido}')::int = 0 and (s #>> '{cliente,na_fila_em_sombra}')::int = 0
      and (s #>> '{cliente,sem_aprovacao_no_periodo}')::int = 0 and (s #>> '{cliente,critica_sem_decisao}')::int = 0
      and (s #>> '{cliente,vespera_com_os_aguardando_peca}')::int = 0 and (s #>> '{cliente,aviso_depois_da_data}')::int = 0
      and (s #>> '{cliente,audio_que_confirmou}')::int = 0 and s #> '{cliente,metricas}' ? 'idas_perdidas_por_acesso_90d',
      (s -> 'cliente' || jsonb_build_object('ok', s -> 'ok'))::text);
    -- cada violação forçada (numa subtransação) dá 1 e o ok cai
    for k in select unnest(array['fora_da_janela', 'em_feriado_ou_domingo', 'acima_do_teto', 'intervalo_curto', 'com_texto_proibido',
                                 'na_fila_em_sombra', 'sem_aprovacao_no_periodo', 'critica_sem_decisao',
                                 'vespera_com_os_aguardando_peca', 'aviso_depois_da_data', 'audio_que_confirmou']) loop
      begin
        if k in ('fora_da_janela', 'em_feriado_ou_domingo') then
          -- o "ficou pronto" da Lucenira (marcado para hoje) saiu no domingo
          update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-11-01 10:00')
           where source = 'agenda-cliente' and source_ref_id = (pg_temp.msgs(c_luc) -> 0 ->> 'id')::uuid;
        elsif k = 'acima_do_teto' then
          perform pg_temp.falsa(c_cli_luc, c_luc, 'pronto', 'agenda-cliente:r11:' || n, '2026-10-30 1' || n || ':00', 'enfileirada')
             from generate_series(1, 2) n;
        elsif k = 'intervalo_curto' then
          update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-30 10:00:10')
           where source = 'agenda-cliente' and source_ref_id = (pg_temp.msgs(c_luc) -> 0 ->> 'id')::uuid;
          update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-30 10:00:20')
           where source = 'agenda-cliente' and source_ref_id = (pg_temp.msgs(c_rob) -> 0 ->> 'id')::uuid;
        elsif k = 'com_texto_proibido' then
          perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pronto', 'agenda-cliente:r11:pix', '2026-10-30 10:00', 'recusada', 'segurada',
                                p_texto => 'Gustavo, manda o pix (AG5R)');
        elsif k = 'na_fila_em_sombra' then
          perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pronto', 'agenda-cliente:r11:sombra', '2026-10-30 10:00', 'enfileirada', 'livre',
                                p_modo => 'sombra');
        elsif k = 'sem_aprovacao_no_periodo' then
          update public.agenda_config set cliente_aprovacao_dias = 3 where id;
          perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pronto', 'agenda-cliente:r11:livre', '2026-10-30 10:00', 'enviada', 'livre');
        elsif k = 'critica_sem_decisao' then
          perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pode_atrasar', 'agenda-cliente:r11:critica', '2026-10-30 10:00', 'enviada',
                                'critica', p_modo => 'sombra', p_var => 'peca');
        elsif k = 'vespera_com_os_aguardando_peca' then
          perform pg_temp.falsa(c_cli_dono, c_dono_os, 'vespera', 'agenda-cliente:r11:vespera', '2026-10-30 10:00',
                                p_base => '{"status": "awaiting_parts"}');
        elsif k = 'aviso_depois_da_data' then
          perform pg_temp.falsa(c_cli_dono, c_dono_os, 'pode_atrasar', 'agenda-cliente:r11:depois', '2026-10-30 10:00',
                                p_base => '{"prometido_ate": "2026-10-29"}', p_var => 'peca');
        else
          insert into public.agenda_cliente_respostas (client_id, service_order_id, recebida_em, tipo_msg, intencao, efeito, modo)
          values (c_cli_dono, c_dono_os, pg_temp.em('2026-10-30 10:00'), 'audio', 'confirma', 'confirmou', 'ligado');
        end if;
        s := public.agenda_saude(date '2026-10-30', pg_temp.em('2026-10-30 17:05'));
        v_res := pg_temp.ok(v_res, 'R11b forçar ' || k || ' dá ' || case when k = 'acima_do_teto' then 'o teto acusado' else '1' end || ' e o ok cai',
          case when k = 'acima_do_teto' then (s #>> array['cliente', k])::int >= 1 else (s #>> array['cliente', k])::int = 1 end
          and s ->> 'ok' = 'false',
          k || ' = ' || coalesce(s #>> array['cliente', k], 'null') || ', ok ' || coalesce(s ->> 'ok', 'null'));
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
    end loop;
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r10$;

-- ── R12. As cópias de agenda_decidir e agenda_saude só mudam nos blocos "-- FASE 5:" ─────────────────────
do $r12$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig3 text := coalesce(current_setting('agenda_teste.mig_equipe_fase3', true), '');
  v_mig4 text := coalesce(current_setting('agenda_teste.mig_vigia_fornecedor_fase4', true), '');
  v_novo text;
begin
  if v_mig3 = '' or v_mig4 = '' then
    insert into _resultado values ('R12 as cópias de agenda_decidir e agenda_saude', true,
                                   'PULADO: sem agenda_teste.mig_equipe_fase3 / mig_vigia_fornecedor_fase4 (rode pela bancada)');
    return;
  end if;
  v_novo := (select p.prosrc from pg_proc p where p.oid = 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)'::regprocedure);
  v_res := pg_temp.ok(v_res, 'R12a a cópia de agenda_decidir só acrescenta o bloco "-- FASE 5:" (× 20261026100300, linha a linha)',
    pg_temp.sem_fase5(v_novo) = string_to_array(pg_temp.corpo(v_mig3, 'agenda_decidir'), E'\n')
    and (select count(*) from regexp_matches(v_novo, '-- FASE 5: fim', 'g')) = 1,
    format('linhas %s × %s', array_length(pg_temp.sem_fase5(v_novo), 1),
           array_length(string_to_array(pg_temp.corpo(v_mig3, 'agenda_decidir'), E'\n'), 1)));
  v_novo := (select p.prosrc from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure);
  v_res := pg_temp.ok(v_res, 'R12b a cópia de agenda_saude só acrescenta os 3 blocos "-- FASE 5:" (× 20261027100500, linha a linha, com os blocos das Fases 3 e 4)',
    pg_temp.sem_fase5(v_novo) = string_to_array(pg_temp.corpo(v_mig4, 'agenda_saude'), E'\n')
    and (select count(*) from regexp_matches(v_novo, '-- FASE 5: fim', 'g')) = 3,
    format('linhas %s × %s', array_length(pg_temp.sem_fase5(v_novo), 1),
           array_length(string_to_array(pg_temp.corpo(v_mig4, 'agenda_saude'), E'\n'), 1)));
  perform pg_temp.gravar(v_res);
end
$r12$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
