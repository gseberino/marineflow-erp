-- Prova da resposta do cliente da Agenda de Produção, Fase 5 (pacote P4): quem escreveu, a que mensagem responde, o que a
-- agenda faz sozinha (o SIM, o pedido de outro dia, o acesso, o opt-out) e o que vai ao dono, com o *desfaz*
-- (migration 20261028100400).
-- bancada: depende de 20261028100400
--
--   A0  portas: a resposta só para service_role; os efeitos, quem é o cliente, a data e o desfazer do cliente para ninguém
--       de fora (nem o service_role); o texto da mensagem para authenticated e service_role, nunca anon; security definer
--       só a resposta; search_path fixo
--   A1  identificação: desligado não lê; os 8 últimos dígitos; o dono e a equipe nunca são cliente; dois clientes no número
--       ou duas OS esperando = ambígua (ao dono, nada muda); sem mensagem esperando (velha, já respondida, de ninguém) não
--       consome; a mesma mensagem do WhatsApp de novo não muda nada
--   A2  sombra: registra a resposta (efeito sombra, com a intenção) e não consome; nada muda
--   A3  o SIM: "sim", "👍" e "ok" confirmam o M1 (o dia fixado, client_confirmed_*, a ação fixar com *desfaz*, o sino, a
--       mensagem respondida); "sim, mas…" não; *desfaz Flávio* volta tudo; a véspera e o acesso só registram; o aviso de
--       atraso é ciência e o remarcado confirma; o "ficou pronto" vai ao dono; o pós-serviço não faz nada; o dia que saiu do
--       plano não confirma
--   A4  o áudio NUNCA confirma (nem com "sim" no corpo): vai ao dono; a saúde conta 0 áudio que confirmou
--   A5  o dia pedido ("pode ser sexta?"): não antes de sex 06/11, ter 03/11 fora, o replano, o acorde, *desfaz*; hoje,
--       mais cedo que o combinado, o mesmo dia, o que não entendeu e a agenda automática desligada vão ao dono
--   A6  o dia recusado: "não vou poder" tira o dia da mensagem; "vou viajar até sexta" e "essa semana" tiram o período; o
--       dia que não é do serviço vai ao dono; o acorde só com o dia em até 1 dia útil (e a rodada o leva); o confirmado
--       movido mais de 2 dias úteis vira a pergunta crítica do motor
--   A7  o acesso: uma linha nova no fim de site_access (o que havia fica igual), acesso_ok_em, *desfaz*; o desfazer depois
--       da edição na tela recusa; o acesso ao "ficou pronto" vai ao dono
--   A8  reclamação (com acorde), negociação, acordo e pergunta vão ao dono, sem nada ao cliente
--   A9  opt-out: o cadastro marcado, as vivas recusadas (opt_out), a ação calada; não se desfaz
--   A10 a cópia de agenda_desfazer (× 20261027100400) só acrescenta os blocos "-- FASE 5:"
--   A11 a resposta depois das 48 h fecha a pergunta do "não respondeu"; antes, o passo sem_resposta não a pega
--   A12 desfazer direto o replano do pedido tira o pedido também; a mensagem enviada não se desmanda
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_respostas.sql
--   A0 e A10 rodam em qualquer lugar (A10 só com as migrations antigas como texto); o resto só na bancada (a fixture-fase5;
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

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-31 10:00') = timestamptz '2026-10-31 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;

-- Liga a mensagem ao cliente (o modo e todos os tipos; a aprovação dos primeiros dias não entra aqui).
create function pg_temp.ligar(p_modo text default 'ligado') returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = p_modo, cliente_aprovacao_dias = 0,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                       'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;

-- Uma mensagem da agenda já enviada ao cliente (o que a rodada e o envio teriam deixado): o dia que ela diz vai na base.
-- Em teste (p_modo sombra): registrada, com a hora em que teria saído.
create function pg_temp.enviada(p_cli uuid, p_os uuid, p_tipo text, p_dia date, p_em text, p_var text default null,
                                p_modo text default 'ligado', p_estado text default null) returns uuid language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, base,
                                               enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
  values (p_cli, p_os, p_tipo, p_var, 'rodada', p_dia, p_modo, 'mensagem de teste (AG5A)',
          case when p_dia is null then '{}'::jsonb else jsonb_build_object('dia_alvo', p_dia) end,
          pg_temp.em(p_em), pg_temp.em(p_em) + interval '9 hours', 'livre',
          coalesce(p_estado, case when p_modo = 'sombra' then 'registrada' else 'enviada' end),
          'agenda-cliente:teste:' || gen_random_uuid(),
          case when coalesce(p_estado, case when p_modo = 'sombra' then 'registrada' else 'enviada' end)
                    in ('enviada', 'respondida', 'sem_resposta') then pg_temp.em(p_em) end,
          pg_temp.em(p_em) - interval '1 hour')
  returning id
$f$;

-- A mensagem do cliente que chega: o que o webhook passa (a intenção e a expressão são as do leitor do TS, provadas no
-- reply-router_test.ts); o "hoje" de quem lê o relógio acompanha.
create function pg_temp.resp(p_fone text, p_body text, p_int text, p_expr text, p_em text, p_tipo text default 'text',
                             p_wa uuid default null) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_em, 10), true);
  return public.agenda_resposta_do_cliente(p_fone, p_body, coalesce(p_wa, gen_random_uuid()), p_tipo, p_int, p_expr,
                                           pg_temp.em(p_em));
end $f$;

-- Os dias publicados/fixados de uma OS: "2026-11-03 tarde fixada,…".
create function pg_temp.plano(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(x.d, ',' order by x.d), '')
    from (select distinct a.dia::text || ' ' || a.turno || ' ' || a.estado
                          || coalesce(' ' || a.fixado_por, '') as d
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') x
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
  v_f7 boolean := false;  -- FASE 7 (7a P7): dentro de um bloco da Fase 7
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    -- FASE 7 (7a P7): os blocos "-- FASE 7: … -- FASE 7: fim" também saem (a 20261031100600 recria agenda_desfazer e agenda_saude copiando a
    -- definição mais nova: só acréscimo; o R9 de agenda_fase7a_rodada.sql confere a cópia); o fim é lido pelo prefixo
    if not v_f7 and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_f7 := true; continue; end if;
    if v_f7 then
      if l ~ '^\s*-- FASE 7: fim' then v_f7 := false; end if;
      continue;
    end if;
    -- FASE 7 (7a P7): fim
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

-- ── A0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $a0$
declare
  v_res jsonb := '[]'::jsonb;
  f text;
  v_ninguem text[] := array[
    'public._agenda_clientes_do_telefone(text, timestamptz)', 'public._agenda_cliente_data_da_resposta(text, date, date)',
    'public._agenda_cliente_confirmar_dia(uuid, uuid, text, date, timestamptz)',
    'public._agenda_cliente_pedido_de_dia(uuid, uuid, daterange, date, text, text, date, timestamptz)',
    'public._agenda_cliente_anotar_acesso(uuid, uuid, text, date, timestamptz)',
    'public._agenda_cliente_restaurar_pedido(uuid, timestamptz)',
    'public._agenda_desfazer_cliente(uuid, uuid, text, date, timestamptz)'];
  v_ruins text := '';
begin
  v_res := pg_temp.ok(v_res, 'A0a a resposta do cliente: só service_role (nem authenticated, nem anon)',
    has_function_privilege('service_role', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)', 'execute')
    and pg_temp.como('authenticated', $q$select public.agenda_resposta_do_cliente('5547900000304', 'sim', null, 'text', 'acordo', null, now())::text$q$)
        like 'erro 42501:%');
  foreach f in array v_ninguem loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'A0b os efeitos, quem é o cliente, a data e o desfazer do cliente: ninguém de fora (nem o service_role)',
                      v_ruins = '', nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'A0c o service_role não chama um efeito direto (o caminho é a resposta e agenda_desfazer)',
    pg_temp.como('service_role', $q$select public._agenda_cliente_restaurar_pedido(gen_random_uuid(), now())::text$q$) like 'erro 42501:%'
    and pg_temp.como('service_role', $q$select public._agenda_clientes_do_telefone('5547900000304', now())::text$q$) like 'erro 42501:%');
  v_res := pg_temp.ok(v_res, 'A0d o texto da mensagem (_agenda_cliente_a_mensagem): authenticated e service_role, nunca anon; agenda_desfazer continua só do service_role',
    has_function_privilege('authenticated', 'public._agenda_cliente_a_mensagem(text, text, date)', 'execute')
    and has_function_privilege('service_role', 'public._agenda_cliente_a_mensagem(text, text, date)', 'execute')
    and not has_function_privilege('anon', 'public._agenda_cliente_a_mensagem(text, text, date)', 'execute')
    and has_function_privilege('service_role', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'execute'));
  v_ruins := '';
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('agenda_resposta_do_cliente', '_agenda_clientes_do_telefone', '_agenda_cliente_a_mensagem',
                                '_agenda_cliente_data_da_resposta', '_agenda_cliente_confirmar_dia', '_agenda_cliente_pedido_de_dia',
                                '_agenda_cliente_anotar_acesso', '_agenda_cliente_restaurar_pedido', '_agenda_desfazer_cliente')
              and (p.prosecdef <> (p.proname = 'agenda_resposta_do_cliente')
                   or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%') loop
    v_ruins := v_ruins || f || ' ';
  end loop;
  v_res := pg_temp.ok(v_res, 'A0e security definer só a resposta; todas com search_path fixo', v_ruins = '', nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'A0f o texto da mensagem como o dono lê',
    public._agenda_cliente_a_mensagem('confirmar', 'primeira', date '2026-11-03') = 'à confirmação de ter 03/11'
    and public._agenda_cliente_a_mensagem('pode_atrasar', 'peca', date '2026-11-12') = 'ao aviso de atraso'
    and public._agenda_cliente_a_mensagem('pode_atrasar', 'remarcado', date '2026-11-12') = 'à mudança de data (qui 12/11)'
    and public._agenda_cliente_a_mensagem('pronto', null, null) = 'ao "ficou pronto"',
    public._agenda_cliente_a_mensagem('acesso', null, date '2026-11-03'));
  perform pg_temp.gravar(v_res);
end
$a0$;

-- ── A1–A12 (a fixture-fase5) ────────────────────────────────────────────────────────────────────────────
do $a1$
declare
  v_res jsonb := '[]'::jsonb;
  c_flav     constant uuid := '05000000-0000-4000-8000-000000000104';
  c_nel      constant uuid := '05000000-0000-4000-8000-000000000112';
  c_rob      constant uuid := '05000000-0000-4000-8000-000000000121';
  c_luc      constant uuid := '05000000-0000-4000-8000-000000000122';
  c_kal1     constant uuid := '05000000-0000-4000-8000-000000000032';
  c_kal2     constant uuid := '05000000-0000-4000-8000-000000000033';
  c_dono_os  constant uuid := '05000000-0000-4000-8000-000000000123';
  c_cli_flav constant uuid := 'c1000000-0000-4000-8000-000000000004';
  c_cli_nel  constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_cli_rob  constant uuid := 'c1000000-0000-4000-8000-000000000007';
  c_cli_kal  constant uuid := 'c1000000-0000-4000-8000-000000000009';
  c_cli_luc  constant uuid := 'c1000000-0000-4000-8000-000000000012';
  c_dono     constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_f        constant text := '5547900000304';                 -- o WhatsApp do Flávio
  c_plano    constant text := '2026-11-03 tarde publicada,2026-11-04 manha publicada';
  r     jsonb;
  r2    jsonb;
  x     jsonb;
  v_id  uuid;
  v_id2 uuid;
  v_wa  uuid;
  v_n   int;
  v_t   text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('A1–A12 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');
  v_res := pg_temp.ok(v_res, 'A1z a fixture: o Flávio publicado em ter 03/11 à tarde e qua 04/11 de manhã, sem confirmação; a agenda automática e a vigia ligadas',
    pg_temp.plano(c_flav) = c_plano
    and (select client_confirmed_at is null from public.service_orders where id = c_flav)
    and (public._agenda_cfg()).modo_proposta = 'ligado' and (public._agenda_cfg()).modo_vigia = 'ligado',
    pg_temp.plano(c_flav));

  -- ── A1. Identificação ──
  v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
  r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
  v_res := pg_temp.ok(v_res, 'A1a desligado (a linha nasce assim): não lê — consumiu false, nenhuma resposta gravada, nada muda',
    r ->> 'consumiu' = 'false' and r ->> 'modo' = 'desligado'
    and not exists (select 1 from public.agenda_cliente_respostas) and pg_temp.plano(c_flav) = c_plano, r::text);
  perform pg_temp.ligar();
  begin
    r := pg_temp.resp('47 90000-0304', 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A1b os 8 últimos dígitos identificam o cliente (o número escrito de outro jeito)',
      r ->> 'consumiu' = 'true' and r ->> 'efeito' = 'confirmou', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o dono cadastrado como cliente (o Gustavo, com a OS concluída anteontem) e a equipe (o Roberto, no cadastro da Lucenira)
    update public.service_orders set check_out_at = pg_temp.em('2026-10-29 17:00') where id = c_dono_os;
    perform pg_temp.enviada('c1000000-0000-4000-8000-000000000013', c_dono_os, 'pos_servico', null, '2026-10-31 09:00');
    update public.clients set whatsapp = '5547900000001' where id = c_cli_luc;
    perform pg_temp.enviada(c_cli_luc, c_luc, 'pronto', null, '2026-10-31 09:00');
    r := pg_temp.resp('5547900000210', 'ok', 'acordo', null, '2026-10-31 10:00');
    r2 := pg_temp.resp('5547900000001', 'ok', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A1c o número do dono (login) e o da equipe (payee) nunca são cliente, mesmo cadastrados como cliente com OS e mensagem esperando',
      public._agenda_clientes_do_telefone('5547900000210', pg_temp.em('2026-10-31 10:00')) = '{}'::uuid[]
      and public._agenda_clientes_do_telefone('5547900000001', pg_temp.em('2026-10-31 10:00')) = '{}'::uuid[]
      and public._agenda_clientes_do_telefone(c_f, pg_temp.em('2026-10-31 10:00')) = array[c_cli_flav]
      and r ->> 'consumiu' = 'false' and r2 ->> 'consumiu' = 'false'
      and not exists (select 1 from public.agenda_cliente_respostas), r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- dois clientes no mesmo número (a Lucenira com o WhatsApp do Flávio)
    update public.clients set whatsapp = c_f where id = c_cli_luc;
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A1d dois clientes no número = ambígua: ao dono (cliente_resposta), nada confirmado, a mensagem segue esperando',
      r ->> 'consumiu' = 'true' and r ->> 'efeito' = 'ambigua' and pg_temp.plano(c_flav) = c_plano
      and (select estado from public.agenda_cliente_mensagens where id = v_id) = 'enviada'
      and exists (select 1 from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid and q.tipo = 'cliente_resposta'
                     and q.estado = 'aberta' and q.chave = 'cliente_resposta:' || (r ->> 'resposta_id')
                     and q.texto like 'Chegou "Sim" do número de Flávio, mas o número é de 2 clientes: não sei a qual mensagem é.%'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o Kalmar, com duas OS esperando a resposta
    perform pg_temp.enviada(c_cli_kal, c_kal1, 'vespera', date '2026-11-03', '2026-10-31 09:00');
    perform pg_temp.enviada(c_cli_kal, c_kal2, 'confirmar', date '2026-11-05', '2026-10-31 09:01');
    r := pg_temp.resp('5547900000309', 'ok', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A1e duas OS do mesmo cliente esperando = ambígua ("há 2 serviços esperando resposta do cliente")',
      r ->> 'efeito' = 'ambigua'
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid) like '%há 2 serviços esperando resposta do cliente%'
      and (select mensagem_id is null from public.agenda_cliente_respostas where id = (r ->> 'resposta_id')::uuid),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_wa := gen_random_uuid();
    r := pg_temp.resp('5547900000305', 'Sim', 'acordo', null, '2026-10-31 10:00');   -- o Nelson: a mensagem dele é de 22/10
    r2 := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-11-03 10:00');             -- a do Flávio passou das 72 h
    v_res := pg_temp.ok(v_res, 'A1f sem mensagem esperando (a do Nelson é de 22/10; a do Flávio passou de cliente_resposta_validade): não consome e não grava',
      r ->> 'consumiu' = 'false' and r ->> 'motivo' = 'sem_mensagem' and r2 ->> 'consumiu' = 'false'
      and not exists (select 1 from public.agenda_cliente_respostas), r::text || ' ' || r2::text);
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00', 'text', v_wa);
    r2 := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00', 'text', v_wa);
    x := pg_temp.resp(c_f, 'Obrigado!', 'outro', null, '2026-10-31 10:05');
    v_res := pg_temp.ok(v_res, 'A1g a mesma mensagem do WhatsApp de novo não muda nada (repetida); a 2ª mensagem depois do SIM não é lida (a da agenda já foi respondida)',
      r ->> 'efeito' = 'confirmou' and r2 ->> 'repetida' = 'true' and r2 ->> 'consumiu' = 'true'
      and x ->> 'consumiu' = 'false' and x ->> 'motivo' = 'sem_mensagem'
      and (select count(*) from public.agenda_cliente_respostas) = 1
      and (select count(*) from public.agenda_acoes a where a.origem = 'cliente' and a.tipo = 'fixar') = 1,
      r2::text || ' ' || x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A2. Sombra ──
  begin
    perform pg_temp.ligar('sombra');
    v_id2 := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:30', 'primeira', 'sombra');
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A2a sombra: registra a resposta à que teria saído (efeito sombra, intenção confirma) e não consome; nada fixado, nada confirmado, a mensagem igual',
      r ->> 'consumiu' = 'false' and r ->> 'efeito' = 'sombra' and r ->> 'intencao' = 'confirma'
      and exists (select 1 from public.agenda_cliente_respostas x where x.id = (r ->> 'resposta_id')::uuid and x.modo = 'sombra'
                     and x.efeito = 'sombra' and x.intencao = 'confirma' and x.mensagem_id = v_id2)
      and pg_temp.plano(c_flav) = c_plano
      and (select client_confirmed_at is null from public.service_orders where id = c_flav)
      and (select estado from public.agenda_cliente_mensagens where id = v_id2) = 'registrada'
      and (select estado from public.agenda_cliente_mensagens where id = v_id) = 'enviada'
      and not exists (select 1 from public.agenda_acoes a where a.origem = 'cliente'), r::text);
    r := pg_temp.resp(c_f, 'Não posso terça, pode ser sexta?', 'data', 'sexta', '2026-10-31 10:10');
    v_res := pg_temp.ok(v_res, 'A2b sombra: o pedido de outro dia também só registra (com a data convertida) e não mexe no plano',
      r ->> 'consumiu' = 'false' and r ->> 'intencao' = 'data'
      and (select data_dita from public.agenda_cliente_respostas where id = (r ->> 'resposta_id')::uuid) = date '2026-11-06'
      and pg_temp.plano(c_flav) = c_plano
      and (select nao_antes_de is null and bem_indisponivel = '{}'::datemultirange from public.os_planejamento where service_order_id = c_flav),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A3. O SIM ──
  begin
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A3a "Sim" ao M1 confirma: ter 03/11 fixado (cliente_confirmou), qua 04/11 igual, client_confirmed_for = ter 03/11 13:00, a ação fixar (origem cliente, *desfaz*), o sino, a mensagem respondida',
      r ->> 'consumiu' = 'true' and r ->> 'efeito' = 'confirmou' and r ->> 'texto' = 'Flávio confirmou ter 03/11.'
      and pg_temp.plano(c_flav) = '2026-11-03 tarde fixada cliente_confirmou,2026-11-04 manha publicada'
      and (select client_confirmed_for = pg_temp.em('2026-11-03 13:00') and client_confirmed_at = pg_temp.em('2026-10-31 10:00')
             from public.service_orders where id = c_flav)
      and exists (select 1 from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid and a.tipo = 'fixar' and a.origem = 'cliente'
                     and a.executada and a.desfazivel_ate = pg_temp.em('2026-10-31 10:00') + (public._agenda_cfg()).desfazer_validade
                     and a.depois ->> 'resposta_id' = r ->> 'resposta_id')
      and exists (select 1 from public.app_notifications n where n.type = 'agendamento_confirmado' and n.title = 'Flávio confirmou o atendimento')
      and (select estado = 'respondida' and resposta_id = (r ->> 'resposta_id')::uuid from public.agenda_cliente_mensagens where id = v_id)
      and (select efeito = 'confirmou' and acao_id = (r ->> 'acao_id')::uuid and intencao = 'confirma' and tipo_msg = 'text'
             from public.agenda_cliente_respostas where id = (r ->> 'resposta_id')::uuid),
      r::text || ' ' || pg_temp.plano(c_flav));
    r2 := public.agenda_desfazer_dito(c_dono, 'Flávio', 'whatsapp', date '2026-10-31', pg_temp.em('2026-10-31 11:00'));
    v_res := pg_temp.ok(v_res, 'A3b *desfaz Flávio* volta a confirmação: o dia de novo publicado (a fixada cancelada, a publicada igual criada), client_confirmed_* nulos, a ação desfeita',
      r2 ->> 'ok' = 'true' and r2 ->> 'texto' = 'Desfeito: a confirmação de Flávio (ter 03/11) sai; o dia continua no plano, sem fixar.'
      and pg_temp.plano(c_flav) = c_plano
      and (select client_confirmed_at is null and client_confirmed_for is null from public.service_orders where id = c_flav)
      and (select desfeita_em is not null from public.agenda_acoes where id = (r ->> 'acao_id')::uuid)
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_flav and a.estado = 'cancelada'
                     and a.cancelada_motivo = 'desfeito' and a.fixado_por = 'cliente_confirmou'),
      r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  foreach v_t in array array['👍', 'ok', 'Confirmo, obrigado'] loop
    begin
      r := pg_temp.resp(c_f, v_t, 'acordo', null, '2026-10-31 10:00');
      v_res := pg_temp.ok(v_res, format('A3c "%s" também confirma (a concordância curta de 30/09)', v_t),
        r ->> 'efeito' = 'confirmou' and pg_temp.plano(c_flav) like '2026-11-03 tarde fixada cliente_confirmou%', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
  end loop;
  begin
    r := pg_temp.resp(c_f, 'Sim, mas preciso ver o horário', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A3d "Sim, mas…" não confirma: vai ao dono ("parece que concorda, mas não é um SIM claro"); nada fixado',
      r ->> 'efeito' = 'ao_dono' and r ->> 'intencao' = 'acordo' and pg_temp.plano(c_flav) = c_plano
      and (select client_confirmed_at is null from public.service_orders where id = c_flav)
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          = 'Flávio respondeu "Sim, mas preciso ver o horário" à confirmação de ter 03/11: parece que concorda, mas não é um SIM claro. Não respondi nada; é com você.',
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- a véspera e o acesso: o SIM só registra
    update public.agenda_cliente_mensagens set estado = 'respondida' where id = v_id;
    v_id2 := pg_temp.enviada(c_cli_flav, c_flav, 'acesso', date '2026-11-03', '2026-10-31 09:05');
    r := pg_temp.resp(c_f, 'ok', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A3e o SIM à véspera com a pergunta do acesso só registra (confirmou, sem fixar e sem client_confirmed_*)',
      r ->> 'efeito' = 'confirmou' and r ->> 'mensagem_id' = v_id2::text and r -> 'acao_id' = 'null'::jsonb
      and pg_temp.plano(c_flav) = c_plano and (select client_confirmed_at is null from public.service_orders where id = c_flav)
      and (select estado from public.agenda_cliente_mensagens where id = v_id2) = 'respondida', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.enviada(c_cli_nel, c_nel, 'pode_atrasar', date '2026-11-12', '2026-10-31 09:00', 'peca');
    r := pg_temp.resp('5547900000305', 'Ok, obrigado', 'acordo', null, '2026-10-31 10:00');
    update public.agenda_cliente_mensagens set estado = 'respondida' where id = v_id;
    v_id2 := pg_temp.enviada(c_cli_flav, c_flav, 'pode_atrasar', date '2026-11-03', '2026-10-31 09:05', 'remarcado');
    r2 := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A3f o SIM ao aviso de atraso (peça) é ciência; ao aviso REMARCADO ("Pode ser? Responda SIM") confirma o dia novo, como o M1',
      r ->> 'efeito' = 'ciencia' and r2 ->> 'efeito' = 'confirmou'
      and pg_temp.plano(c_flav) like '2026-11-03 tarde fixada cliente_confirmou%', r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.enviada(c_cli_luc, c_luc, 'pronto', null, '2026-10-31 09:00');
    perform pg_temp.enviada(c_cli_rob, c_rob, 'pos_servico', null, '2026-10-31 09:00');
    r := pg_temp.resp('5547900000312', 'Ok', 'acordo', null, '2026-10-31 10:00');
    r2 := pg_temp.resp('5547900000307', 'ok', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A3g o "ok" ao "ficou pronto" vai ao dono (combine a entrega); ao pós-serviço não faz nada (a mensagem fica respondida)',
      r ->> 'efeito' = 'ao_dono'
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          = 'Lucenira respondeu "Ok" ao "ficou pronto": combine a entrega com o cliente. Não respondi nada; é com você.'
      and r2 ->> 'efeito' = 'nada' and r2 -> 'pergunta_id' = 'null'::jsonb
      and (select estado from public.agenda_cliente_mensagens where service_order_id = c_rob and tipo = 'pos_servico') = 'respondida',
      r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    update public.agenda_cliente_mensagens set estado = 'respondida' where id = v_id;
    perform pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-05', '2026-10-31 09:05', 'seguinte');
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A3h o SIM a um dia que saiu do plano (qui 05/11) não confirma nada: vai ao dono',
      r ->> 'efeito' = 'ao_dono' and pg_temp.plano(c_flav) = c_plano
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          like 'Flávio respondeu "Sim" à confirmação de qui 05/11: confirmou, mas esse dia (qui 05/11) não está mais no plano: confira.%',
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A4. O áudio ──
  begin
    r := pg_temp.resp(c_f, '[audio]', 'outro', null, '2026-10-31 10:00', 'audio');
    v_res := pg_temp.ok(v_res, 'A4a o áudio NUNCA confirma: vai ao dono ("respondeu por áudio … a transcrição está na conversa"), nada fixado',
      r ->> 'consumiu' = 'true' and r ->> 'efeito' = 'ao_dono' and r ->> 'intencao' = 'audio' and pg_temp.plano(c_flav) = c_plano
      and (select client_confirmed_at is null from public.service_orders where id = c_flav)
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          = 'Flávio respondeu por áudio à confirmação de ter 03/11; a transcrição está na conversa. Não respondi nada; é com você.',
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    r := pg_temp.resp(c_f, 'sim', 'acordo', null, '2026-10-31 10:00', 'audio');
    r2 := pg_temp.resp('5547900000305', 'sim', 'acordo', null, '2026-10-31 10:00', 'image');
    v_res := pg_temp.ok(v_res, 'A4b nem o áudio com "sim" no corpo confirma; a foto também vai ao dono; a saúde: audio_que_confirmou = 0',
      r ->> 'efeito' = 'ao_dono' and pg_temp.plano(c_flav) = c_plano
      and (public.agenda_saude(date '2026-10-31', pg_temp.em('2026-10-31 10:05')) -> 'cliente' ->> 'audio_que_confirmou') = '0',
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A5. O dia pedido ──
  begin
    r := pg_temp.resp(c_f, 'Não posso terça, pode ser sexta?', 'data', 'sexta', '2026-10-31 10:00');
    x := public._agenda_plano_da_os(c_flav, date '2026-10-31');
    v_res := pg_temp.ok(v_res, 'A5a "pode ser sexta?": não antes de sex 06/11 (o cliente pediu), ter 03/11 fora, replanejado de sex 06/11 em diante; a ação cliente com *desfaz* e o acorde (ter 03/11 é o próximo dia útil)',
      r ->> 'efeito' = 'replanejou' and r ->> 'intencao' = 'data'
      and (select nao_antes_de = date '2026-11-06' and nao_antes_motivo = 'o cliente pediu'
                  and bem_indisponivel @> date '2026-11-03' from public.os_planejamento where service_order_id = c_flav)
      and (x ->> 'proximo_dia')::date >= date '2026-11-06'
      and (select data_dita from public.agenda_cliente_respostas where id = (r ->> 'resposta_id')::uuid) = date '2026-11-06'
      and exists (select 1 from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid and a.tipo = 'cliente' and a.origem = 'cliente'
                     and a.executada and a.desfazivel_ate is not null and (a.depois ->> 'acorde')::boolean
                     and jsonb_array_length(a.depois -> 'replano_acoes') > 0
                     and a.texto = format('Flávio pediu sex 06/11: remarquei para %s%s. *desfaz Flávio* volta como estava.',
                                          public._dia_curto((x ->> 'proximo_dia')::date),
                                          case when (x ->> 'proximo_dia')::date > date '2026-11-06' then ', o 1º dia que coube' else '' end)),
      r::text || ' ' || x::text);
    x := public.agenda_cliente_vigiar(date '2026-10-31', pg_temp.em('2026-10-31 10:15'));
    v_res := pg_temp.ok(v_res, 'A5b a rodada seguinte leva o acorde do pedido ao dono (a mesma ação)',
      exists (select 1 from jsonb_array_elements(x -> 'acordes') e where e ->> 'acao_id' = r ->> 'acao_id'), (x -> 'acordes')::text);
    r2 := public.agenda_desfazer_dito(c_dono, 'Flávio', 'whatsapp', date '2026-10-31', pg_temp.em('2026-10-31 11:00'));
    v_res := pg_temp.ok(v_res, 'A5c *desfaz Flávio* volta tudo: o plano de ter 03/11 e qua 04/11, sem "não antes de" e sem dia fora',
      r2 ->> 'ok' = 'true' and r2 ->> 'texto' = 'Desfeito: o pedido de Flávio sai; o serviço fica para ter 03/11.'
      and pg_temp.plano(c_flav) = c_plano
      and (select nao_antes_de is null and nao_antes_motivo is null and bem_indisponivel = '{}'::datemultirange
             from public.os_planejamento where service_order_id = c_flav)
      and (select desfeita_em is not null from public.agenda_acoes where id = (r ->> 'acao_id')::uuid),
      r2::text || ' ' || pg_temp.plano(c_flav));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    r := pg_temp.resp(c_f, 'Pode ser hoje?', 'data', 'hoje', '2026-10-31 10:00');
    update public.agenda_cliente_mensagens set estado = 'enviada', resposta_id = null where id = v_id;
    r2 := pg_temp.resp(c_f, 'Pode ser segunda?', 'data', 'segunda', '2026-10-31 10:01');
    update public.agenda_cliente_mensagens set estado = 'enviada', resposta_id = null where id = v_id;
    x := pg_temp.resp(c_f, 'Pode ser terça mesmo?', 'data', 'terça', '2026-10-31 10:02');
    update public.agenda_cliente_mensagens set estado = 'enviada', resposta_id = null where id = v_id;
    v_t := pg_temp.resp(c_f, 'Pode ser no dia de São Nunca?', 'data', 'dia de são nunca', '2026-10-31 10:03') ->> 'pergunta_id';
    v_res := pg_temp.ok(v_res, 'A5d o dia pedido que é hoje, mais cedo que o combinado (seg 02/11), o mesmo dia ou que o banco não entende vai ao dono; nada muda',
      r ->> 'efeito' = 'ao_dono' and r2 ->> 'efeito' = 'ao_dono' and x ->> 'efeito' = 'ao_dono'
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid) like '%: o dia pedido já passou ou é hoje.%'
      and (select q.texto from public.agenda_perguntas q where q.id = (r2 ->> 'pergunta_id')::uuid) like '%: pediu um dia antes do combinado (seg 02/11).%'
      and (select q.texto from public.agenda_perguntas q where q.id = (x ->> 'pergunta_id')::uuid) like '%: falou do mesmo dia combinado.%'
      and (select q.texto from public.agenda_perguntas q where q.id = v_t::uuid) like '%: não entendi o dia pedido.%'
      and pg_temp.plano(c_flav) = c_plano
      and (select nao_antes_de is null and bem_indisponivel = '{}'::datemultirange from public.os_planejamento where service_order_id = c_flav),
      r::text || ' ' || r2::text || ' ' || x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    update public.agenda_config set modo_proposta = 'sombra' where id;
    r := pg_temp.resp(c_f, 'Pode ser sexta?', 'data', 'sexta', '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A5e com a agenda automática fora de ligado, o pedido de outro dia vai ao dono (remarque você); nada muda',
      r ->> 'efeito' = 'ao_dono'
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          like '%pediu outro dia, mas a agenda automática não está ligada: remarque você.%'
      and (select nao_antes_de is null from public.os_planejamento where service_order_id = c_flav), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A6. O dia recusado ──
  begin
    -- a mensagem de qui 29/10 (ter 03/11 está a mais de 1 dia útil: sem acorde)
    update public.agenda_cliente_mensagens set estado = 'respondida' where id = v_id;
    v_id2 := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-29 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Infelizmente não vou poder', 'remarcar', null, '2026-10-29 10:00');
    x := public._agenda_plano_da_os(c_flav, date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'A6a "não vou poder" sem dia: ter 03/11 fora (bem indisponível), o replano tira o dia; sem acorde (a mais de 1 dia útil)',
      r ->> 'efeito' = 'replanejou' and r ->> 'intencao' = 'remarcar'
      and (select bem_indisponivel = '{[2026-11-03,2026-11-04)}'::datemultirange and nao_antes_de is null
             from public.os_planejamento where service_order_id = c_flav)
      and pg_temp.plano(c_flav) not like '%2026-11-03%'
      and exists (select 1 from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid and not (a.depois ->> 'acorde')::boolean
                     and a.texto like 'Flávio pediu outro dia (ter 03/11 não dá): tirei o dia e remarquei para %. *desfaz Flávio* volta como estava.'),
      r::text || ' ' || pg_temp.plano(c_flav));
    -- A12a: desfazer DIRETO o replano (a ação do motor, pela tela): o pedido sai junto e a ação do cliente fica desfeita
    v_t := (select a.depois -> 'replano_acoes' ->> 0 from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid);
    r2 := public.agenda_desfazer(v_t::uuid, c_dono, 'dono', date '2026-10-29', pg_temp.em('2026-10-29 10:30'));
    v_res := pg_temp.ok(v_res, 'A12a desfazer direto o replano do pedido: o plano volta, o bem indisponível sai (a vigia não replaneja de novo) e a ação do cliente fica desfeita',
      r2 ->> 'ok' = 'true' and pg_temp.plano(c_flav) = c_plano
      and (select bem_indisponivel = '{}'::datemultirange from public.os_planejamento where service_order_id = c_flav)
      and (select desfeita_pela = (r2 ->> 'acao_id')::uuid from public.agenda_acoes where id = (r ->> 'acao_id')::uuid),
      r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    r := pg_temp.resp(c_f, 'Vou viajar até sexta', 'falta', 'até sexta', '2026-10-31 10:00');
    x := public._agenda_plano_da_os(c_flav, date '2026-10-31');
    v_res := pg_temp.ok(v_res, 'A6b "vou viajar até sexta": de hoje a sex 06/11 fora (os dois dias do serviço), replanejado depois; com o acorde',
      r ->> 'efeito' = 'replanejou' and r ->> 'intencao' = 'falta'
      and (select bem_indisponivel = '{[2026-10-31,2026-11-07)}'::datemultirange from public.os_planejamento where service_order_id = c_flav)
      and (x ->> 'proximo_dia')::date > date '2026-11-06'
      and (select (a.depois ->> 'acorde')::boolean and a.texto like 'Flávio pediu outro dia (sáb 31/10 a sex 06/11 não dá): tirei o dia%'
             from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid),
      r::text || ' ' || x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    r := pg_temp.resp(c_f, 'Essa semana não dá', 'remarcar', 'essa semana', '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A6c "essa semana não dá": do dia combinado (ter 03/11) ao domingo da mesma semana fora',
      r ->> 'efeito' = 'replanejou'
      and (select bem_indisponivel = '{[2026-11-03,2026-11-09)}'::datemultirange from public.os_planejamento where service_order_id = c_flav)
      and (public._agenda_plano_da_os(c_flav, date '2026-10-31') ->> 'proximo_dia')::date >= date '2026-11-09',
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    r := pg_temp.resp(c_f, 'Não dá pra amanhã', 'remarcar', 'amanhã', '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A6d o dia recusado que não é dia do serviço ("amanhã" no sábado = domingo) vai ao dono; nada muda',
      r ->> 'efeito' = 'ao_dono' and pg_temp.plano(c_flav) = c_plano
      and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid)
          like '%: disse que não dá dom 01/11, mas não é dia do serviço.%', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o Flávio já tinha confirmado ter 03/11 (o botão de 30/09): mover mais de 2 dias úteis é a decisão crítica do motor
    update public.service_orders set client_confirmed_at = pg_temp.em('2026-10-30 10:00'),
                                     client_confirmed_for = pg_temp.em('2026-11-03 13:00') where id = c_flav;
    r := pg_temp.resp(c_f, 'Vou viajar até sexta', 'falta', 'até sexta', '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A6e o que o cliente confirmou movido mais de 2 dias úteis vira a pergunta crítica do motor: "a decisão ficou com você"',
      r ->> 'efeito' = 'replanejou'
      and r ->> 'texto' = 'Flávio pediu outro dia (sáb 31/10 a sex 06/11 não dá): tirei o dia; a decisão ficou com você. *desfaz Flávio* volta como estava.'
      and exists (select 1 from public.agenda_perguntas q where q.service_order_id = c_flav and q.estado = 'aberta' and q.critica),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A7. O acesso ──
  begin
    r := pg_temp.resp(c_f, 'A chave fica com o marinheiro, vaga 12', 'acesso', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A7a o acesso dito vai para o campo da OS ("Cliente (31/10): …"), acesso_ok_em, a ação com *desfaz*; o contexto passa a saber o acesso',
      r ->> 'efeito' = 'anotou_acesso'
      and (select site_access from public.service_orders where id = c_flav) = 'Cliente (31/10): A chave fica com o marinheiro, vaga 12'
      and (select acesso_ok_em = pg_temp.em('2026-10-31 10:00') from public.os_planejamento where service_order_id = c_flav)
      and (public._agenda_cliente_contexto(c_flav, date '2026-10-31') ->> 'acesso_conhecido')::boolean
      and (select a.texto = 'Anotei o acesso que Flávio disse: "A chave fica com o marinheiro, vaga 12".' and a.desfazivel_ate is not null
             from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid),
      r::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, c_dono, 'dono', date '2026-10-31', pg_temp.em('2026-10-31 11:00'));
    v_res := pg_temp.ok(v_res, 'A7b *desfaz*: o campo e o acesso_ok_em voltam ao que eram',
      r2 ->> 'ok' = 'true' and r2 ->> 'texto' = 'Desfeito: o acesso que Flávio disse saiu da OS.'
      and (select site_access is null from public.service_orders where id = c_flav)
      and (select acesso_ok_em is null from public.os_planejamento where service_order_id = c_flav), r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    update public.service_orders set site_access = 'Portão azul, falar com o seu Zé' where id = c_flav;
    r := pg_temp.resp(c_f, 'Está no seco', 'acesso', null, '2026-10-31 10:00');
    v_t := (select site_access from public.service_orders where id = c_flav);
    -- a tela muda o campo depois
    update public.service_orders set site_access = v_t || ' (atualizado pela tela)' where id = c_flav;
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, c_dono, 'dono', date '2026-10-31', pg_temp.em('2026-10-31 11:00'));
    v_res := pg_temp.ok(v_res, 'A7c a linha entra no fim e o que havia fica igual; o desfazer depois da edição na tela recusa ("O acesso da OS mudou depois; confira na tela.") e não mexe',
      v_t = E'Portão azul, falar com o seu Zé\nCliente (31/10): Está no seco'
      and r2 ->> 'ok' = 'false' and r2 ->> 'texto' = 'O acesso da OS mudou depois; confira na tela.'
      and (select site_access from public.service_orders where id = c_flav) = v_t || ' (atualizado pela tela)'
      and (select desfeita_em is null from public.agenda_acoes where id = (r ->> 'acao_id')::uuid),
      r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.enviada(c_cli_luc, c_luc, 'pronto', null, '2026-10-31 09:00');
    r := pg_temp.resp('5547900000312', 'A chave fica na secretaria da marina', 'acesso', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A7d o acesso dito ao "ficou pronto" vai ao dono (não é mensagem de ir ao serviço); o campo não muda',
      r ->> 'efeito' = 'ao_dono' and (select site_access is null from public.service_orders where id = c_luc), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A8. Reclamação, negociação, acordo e pergunta: ao dono ──
  foreach v_t in array array['disputa|O compressor não funciona|parece reclamação', 'negociacao|Quanto fica?|é sobre preço ou pagamento',
                             'acordo|Fechado, pode vir|parece que concorda, mas não é um SIM claro',
                             'pergunta|Vocês vêm de manhã ou à tarde?|é uma pergunta'] loop
    begin
      r := pg_temp.resp(c_f, split_part(v_t, '|', 2), split_part(v_t, '|', 1), null, '2026-10-31 10:00');
      v_res := pg_temp.ok(v_res, format('A8 %s vai ao dono (cliente_resposta, %s), nada ao cliente, nada muda%s', split_part(v_t, '|', 1),
                                        split_part(v_t, '|', 3), case when v_t like 'disputa%' then '; com o acorde na hora' else '' end),
        r ->> 'efeito' = 'ao_dono' and r ->> 'intencao' = split_part(v_t, '|', 1)
        and (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid and q.tipo = 'cliente_resposta'
                and q.estado = 'aberta' and q.expira_em = pg_temp.em('2026-10-31 10:00') + interval '7 days')
            = format('Flávio respondeu "%s" à confirmação de ter 03/11: %s. Não respondi nada; é com você.', split_part(v_t, '|', 2),
                     split_part(v_t, '|', 3))
        and not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-cliente')
        and pg_temp.plano(c_flav) = c_plano
        and (select estado from public.agenda_cliente_mensagens where id = v_id) = 'respondida'
        and (exists (select 1 from public.agenda_acoes a where a.tipo = 'cliente' and a.executada and (a.depois ->> 'acorde')::boolean
                       and a.depois ->> 'pergunta_id' = r ->> 'pergunta_id' and a.id = (r ->> 'acao_id')::uuid)
             = (v_t like 'disputa%')),
        r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
  end loop;

  -- ── A9. Opt-out ──
  begin
    v_id2 := pg_temp.enviada(c_cli_flav, c_flav, 'vespera', date '2026-11-03', '2026-11-02 09:00', null, 'ligado', 'registrada');
    r := pg_temp.resp(c_f, 'PARAR', 'opt_out', null, '2026-10-31 10:00');
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, c_dono, 'dono', date '2026-10-31', pg_temp.em('2026-10-31 11:00'));
    v_res := pg_temp.ok(v_res, 'A9 opt-out: o cadastro marcado, a viva recusada (opt_out), a ação calada ao dono; não se desfaz por aqui',
      r ->> 'efeito' = 'opt_out' and r ->> 'texto' = 'Flávio pediu para não receber mais mensagens: não mando mais nada.'
      and (select opt_out_whatsapp from public.clients where id = c_cli_flav)
      and (select estado = 'recusada' and recusa_motivo = 'opt_out' from public.agenda_cliente_mensagens where id = v_id2)
      and r2 ->> 'ok' = 'false' and r2 ->> 'texto' like 'O pedido de Flávio para não receber mensagens não se desfaz por aqui: só o cliente pode pedir para voltar.'
      and not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-cliente'),
      r::text || ' ' || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A11. O "não respondeu" ──
  begin
    update public.agenda_cliente_mensagens set estado = 'respondida' where id = v_id;
    v_id2 := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-29 09:00', 'primeira');
    x := public._agenda_cliente_sem_resposta(date '2026-10-31', pg_temp.em('2026-10-31 09:30'));
    v_n := (select count(*) from public.agenda_perguntas q where q.chave = 'cliente_resposta:sem_resposta:' || v_id2 and q.estado = 'aberta');
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_res := pg_temp.ok(v_res, 'A11a a resposta depois das 48 h (a mensagem já sem_resposta, a pergunta aberta): a mensagem fica respondida e a pergunta do "não respondeu" se resolve',
      (x ->> 'sem_resposta')::int >= 1 and v_n = 1 and r ->> 'efeito' = 'confirmou'
      and (select estado = 'respondida' and resposta_id = (r ->> 'resposta_id')::uuid from public.agenda_cliente_mensagens where id = v_id2)
      and (select estado from public.agenda_perguntas q where q.chave = 'cliente_resposta:sem_resposta:' || v_id2) = 'resolvida',
      x::text || ' ' || r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    x := public._agenda_cliente_sem_resposta(date '2026-11-02', pg_temp.em('2026-11-02 10:00'));
    v_res := pg_temp.ok(v_res, 'A11b a resposta antes das 48 h: o passo sem_resposta não pega a mensagem (respondida, com resposta_id)',
      (select estado from public.agenda_cliente_mensagens where id = v_id) = 'respondida'
      and not exists (select 1 from public.agenda_perguntas q where q.chave = 'cliente_resposta:sem_resposta:' || v_id), x::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A12b. A mensagem enviada não se desmanda ──
  begin
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, depois, texto)
    values (date '2026-10-31', true, 'vigia', 'cliente', c_flav, array[c_flav], jsonb_build_object('mensagem_id', v_id),
            'Mandei ao Flávio a confirmação de ter 03/11.')
    returning id into v_id2;
    r := public.agenda_desfazer(v_id2, c_dono, 'dono', date '2026-10-31', pg_temp.em('2026-10-31 11:00'));
    v_res := pg_temp.ok(v_res, 'A12b a mensagem enviada não se desmanda ("Mensagem enviada não se desmanda.")',
      r ->> 'ok' = 'false' and r ->> 'texto' = 'Mensagem enviada não se desmanda.', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$a1$;

-- ── A10. A cópia de agenda_desfazer ─────────────────────────────────────────────────────────────────────
do $a10$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_detector_fase4', true), '');
  v_novo text;
begin
  if v_mig = '' then
    insert into _resultado values ('A10 a cópia de agenda_desfazer', true, 'PULADO: sem agenda_teste.mig_detector_fase4 (rode pela bancada)');
    return;
  end if;
  v_novo := (select p.prosrc from pg_proc p where p.oid = 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)'::regprocedure);
  v_res := pg_temp.ok(v_res, 'A10 a cópia de agenda_desfazer só acrescenta os 2 blocos "-- FASE 5:" (× 20261027100400, linha a linha, com os das Fases 3 e 4)',
    pg_temp.sem_fase5(v_novo) = string_to_array(pg_temp.corpo(v_mig, 'agenda_desfazer'), E'\n')
    and (select count(*) from regexp_matches(v_novo, '-- FASE 5: fim', 'g')) = 2
    and position('_agenda_desfazer_cliente' in v_novo) > 0 and position('_agenda_cliente_restaurar_pedido' in v_novo) > 0,
    format('linhas %s × %s', array_length(pg_temp.sem_fase5(v_novo), 1),
           array_length(string_to_array(pg_temp.corpo(v_mig, 'agenda_desfazer'), E'\n'), 1)));
  perform pg_temp.gravar(v_res);
end
$a10$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
