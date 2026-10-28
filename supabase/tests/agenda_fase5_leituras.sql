-- Prova da conversa do dono da Agenda de Produção, Fase 5 (pacote P5): o foco clientes (*agenda clientes*), as palavras
-- *manda cliente [nome]* e *segura cliente [nome]*, a ferramenta cliente_avisar (agenda_cliente_preparar: prepara, nunca
-- envia), a linha cliente do fechamento, o prometido e o serviço dito ao cliente no rascunho do planejar, e o que a
-- resposta do cliente mudou no "o que mudou" (migration 20261028100500).
-- bancada: depende de 20261028100500
--
--   L0  portas: as palavras e a ferramenta para authenticated e service_role (nunca anon), definer, conferem o
--       administrador; o foco definer (confere quem vê), a linha do fechamento e os textos invoker; search_path fixo
--   L1  o foco clientes: desligado; em teste (a sombra da rodada); ligado (esperando você, a mensagem inteira, o que não
--       consigo mandar); com a OS (o que foi dito); as respostas; a leitura desligada; o foco que não existe cita os 18
--   L2  *manda cliente* / *segura cliente*: fora de ligado; por nome; todas; o nome que não espera nada ("orçamento") não
--       muda nada; dois clientes com o mesmo nome; a decisão crítica não é por aqui; o *segura* da que ia sair sozinha
--   L3  cliente_avisar: sem material na mão (d09), sem data dita, sem telefone, a mudança no dia, a que já existe, a
--       preparada (pedida, nada na fila), a firme do plano, em teste e desligado
--   L4  a linha cliente do fechamento: em teste nada; a aprovação (perda 75, a 1ª inteira e "E mais"); o que sai sozinho
--       amanhã (perda 40); a mensagem longa cortada em 300 com "(*agenda clientes* mostra inteira)" (≤ 600)
--   L5  o rascunho: prometido firme e em faixa (conferido no trecho), o serviço dito ao cliente (≤ 40, sem valor), nada
--       muda antes do *grava*; o *grava* grava o prometido (fonte dono, o original só na 1ª vez) e o serviço
--   L6  determinismo (md5 2×): o foco, com e sem a OS, e as linhas do fechamento
--   L7  quem vê: o técnico recebe 42501 no foco, nas palavras e na ferramenta
--   L8  as cópias (agenda_ver, _agenda_linhas_do_fechamento, _agenda_mudancas, _agenda_rascunho_frase,
--       agenda_rascunho_planejar e _agenda_aplicar_planejar) só acrescentam os blocos "-- FASE 5:"
--   L9  o que mudou: a ação do pedido do cliente e o replano dela num grupo só (sem contar duas vezes); o acorde não é
--       mudança; a linha mudancas do fechamento
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_leituras.sql
--   L0 e L8 rodam em qualquer lugar (L8 só com as migrations antigas como texto); o resto só na bancada (a fixture-fase5;
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

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-31 10:00') = timestamptz '2026-10-31 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
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
-- FASE 6 (P8): tira também os blocos "-- FASE 6:" (agenda_ver foi recriada de novo em 20261029100800, com o bloco do
-- foco aprendizado fora dos da Fase 5).
create function pg_temp.sem_fase5(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE [56]:' and l !~ '^\s*-- FASE [56]: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE [56]: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- O foco clientes (com ou sem a OS), na hora do caso (agenda.agora).
create function pg_temp.ver(p_os text default null) returns text language sql stable as $f$
  select public.agenda_ver(null, null, null, 'clientes', p_os, null, false, date '2026-10-30') ->> 'texto'
$f$;

-- As palavras do dono (o dono da fixture: aa…01).
create function pg_temp.dito(p_acao text, p_alvo text, p_quando text default '2026-10-30 17:35') returns jsonb language sql as $f$
  select public.agenda_cliente_decidir_dito('aa000000-0000-4000-8000-000000000001', p_acao, p_alvo, 'whatsapp', date '2026-10-30',
                                            pg_temp.em(p_quando))
$f$;

-- A ferramenta cliente_avisar.
create function pg_temp.prep(p_os text, p_tipo text, p_firme boolean default false, p_quando text default '2026-10-30 17:30')
returns jsonb language sql as $f$
  select public.agenda_cliente_preparar('aa000000-0000-4000-8000-000000000001', p_os, p_tipo, p_firme, 'avisa o cliente',
                                        date '2026-10-30', pg_temp.em(p_quando))
$f$;

-- Liga a mensagem ao cliente com todos os tipos (a aprovação dos 3 primeiros dias continua: cliente_aprovacao_dias = 3).
create function pg_temp.ligar(p_modo text default 'ligado') returns void language sql as $f$
  update public.agenda_config
     set modo_leitura = 'ligado', modo_cliente = p_modo,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                       'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;

-- As mensagens ao cliente por OS, tipo, modo, estado e aprovação ("OS-00104 acesso ligado aguardando_dono pedida,…").
create function pg_temp.msgs() returns text language sql stable as $f$
  select coalesce(string_agg(x, ',' order by x), '')
    from (select so.service_order_number || ' ' || m.tipo || ' ' || m.modo || ' ' || m.estado || ' ' || m.aprovacao
                 || coalesce('/' || m.recusa_motivo, '') as x
            from public.agenda_cliente_mensagens m join public.service_orders so on so.id = m.service_order_id
           where m.id <> 'd5000000-0000-4000-8000-0000000000a1') y
$f$;

create function pg_temp.fila() returns int language sql stable as $f$
  select count(*)::int from public.whatsapp_send_queue where source = 'agenda-cliente' and status in ('pending', 'sending', 'sent')
$f$;

-- ── L0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $l0$
declare
  v_res jsonb := '[]'::jsonb;
  f text;
  v_ruins text := '';
  c_palavras constant text[] := array[
    'public.agenda_cliente_decidir_dito(uuid, text, text, text, date, timestamptz)',
    'public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz)'];
  c_leituras constant text[] := array[
    'public._agenda_ver_clientes(uuid, date)', 'public._agenda_cliente_fechamento(date)',
    'public._agenda_cliente_efeito_texto(text)', 'public._agenda_cliente_teria_feito(text, date)'];
begin
  foreach f in array c_palavras || c_leituras loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'L0a as palavras, a ferramenta, o foco, a linha do fechamento e os textos: authenticated e service_role, nunca anon',
                      v_ruins = '', nullif(v_ruins, ''));
  v_ruins := '';
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('agenda_cliente_decidir_dito', 'agenda_cliente_preparar', '_agenda_ver_clientes',
                                '_agenda_cliente_fechamento', '_agenda_cliente_efeito_texto', '_agenda_cliente_teria_feito')
              and (p.prosecdef <> (p.proname in ('agenda_cliente_decidir_dito', 'agenda_cliente_preparar', '_agenda_ver_clientes'))
                   or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%') loop
    v_ruins := v_ruins || f || ' ';
  end loop;
  v_res := pg_temp.ok(v_res, 'L0b security definer só as palavras, a ferramenta e o foco; todas com search_path fixo', v_ruins = '',
                      nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'L0c as recriadas mantêm as portas (agenda_ver, a linha do fechamento, o que mudou e o planejar: authenticated; o aplicar e a frase: só service_role)',
    has_function_privilege('authenticated', 'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'execute')
    and has_function_privilege('authenticated', 'public._agenda_linhas_do_fechamento(date)', 'execute')
    and has_function_privilege('authenticated', 'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)', 'execute')
    and has_function_privilege('authenticated', 'public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', 'execute')
    and has_function_privilege('service_role', 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_rascunho_frase(text, jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'execute'));
  v_res := pg_temp.ok(v_res, 'L0d o efeito e o "teria feito" como o dono lê',
    public._agenda_cliente_efeito_texto('replanejou') = 'pediu outro dia, e eu replanejei'
    and public._agenda_cliente_efeito_texto('ao_dono') = 'foi para você'
    and public._agenda_cliente_teria_feito('confirma', date '2026-11-03') = 'eu teria confirmado ter 03/11'
    and public._agenda_cliente_teria_feito('audio', null) = 'eu teria passado a você', null);
  perform pg_temp.gravar(v_res);
end
$l0$;

-- ── L1–L7, L9 (a fixture-fase5) ─────────────────────────────────────────────────────────────────────────
do $l1$
declare
  v_res jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec   constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_flav  constant uuid := '05000000-0000-4000-8000-000000000104';
  c_nel   constant uuid := '05000000-0000-4000-8000-000000000112';
  c_van   constant uuid := '05000000-0000-4000-8000-000000000069';
  c_cli_flav constant uuid := 'c1000000-0000-4000-8000-000000000004';
  r      jsonb;
  r2     jsonb;
  v_t    text;
  v_t2   text;
  v_ms   text;
  v_n    int;
  v_id   uuid;
  v_perg uuid;
  v_ger  text;
  v_nel  text;
  v_fech text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('L1–L7, L9 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase5');
  perform set_config('agenda_teste.hoje', '2026-10-30', true);
  perform set_config('agenda.agora', '2026-10-30 17:30-03', true);
  update public.agenda_config set modo_leitura = 'ligado' where id;

  -- ── L1a: desligado
  v_res := pg_temp.igual(v_res, 'L1a desligado: o foco diz que a agenda não fala com cliente', pg_temp.ver(),
                         'As mensagens ao cliente estão desligadas: a agenda não fala com cliente.');
  r := public.agenda_cliente_preparar(c_admin, 'Flávio', 'confirmar', false, 'manda a confirmação', date '2026-10-30',
                                      pg_temp.em('2026-10-30 17:30'));
  r2 := pg_temp.dito('manda', null);
  v_res := pg_temp.ok(v_res, 'L1b desligado: a ferramenta recusa e a palavra segue ao modelo (nao_achei); nada registrado',
    r ->> 'motivo' = 'desligada' and r2 ->> 'status' = 'nao_achei' and pg_temp.msgs() = '', r::text || r2::text);

  -- ── L1c: em teste (a rodada das 17:00 em sombra)
  begin
    perform pg_temp.ligar('sombra');
    perform public.agenda_cliente_vigiar(date '2026-10-30', pg_temp.em('2026-10-30 17:00'));
    v_res := pg_temp.igual(v_res, 'L1c em teste: "Em teste, eu teria mandado", sem resposta e o que não consigo mandar', pg_temp.ver(),
      E'Mensagens ao cliente (em teste: nada sai ainda):\nEm teste, eu teria mandado:\n• Lucenira: que o serviço ficou pronto (teria saído sex 30/10 às 17:00)\n• Flávio: a véspera com a pergunta do acesso (ter 03/11) (sairia amanhã às 09:00)\n• Nelson: o aviso de que pode atrasar (sairia amanhã às 09:00)\n• Rodrigo: a confirmação de qua 04/11 (sairia amanhã às 09:00)\n• Robson: a mensagem de pós-serviço (sairia ter 03/11 às 09:00)\nSem resposta:\n• Nelson: a confirmação de qui 05/11, mandada qui 22/10\nNão consigo mandar: Kalmar (pediu para não receber mensagens), Lenine (sem telefone no cadastro) e Rodrigo (não escreveu para a HBR no último ano; por ora só mando a quem já escreveu).');
    r := pg_temp.dito('manda', 'Nelson');
    v_res := pg_temp.igual(v_res, 'L2a em teste: *manda cliente* responde que nada sai ainda', r ->> 'texto',
                           'As mensagens ao cliente estão em teste: nada sai ainda.');
    r := pg_temp.prep('Flávio', 'confirmar');
    v_res := pg_temp.ok(v_res, 'L3h em teste: cliente_avisar diz o que teria preparado; nenhuma pergunta, nada na fila',
      r ->> 'texto' like 'Em teste (as mensagens ao cliente ainda não saem): eu teria preparado para Flávio, para sair agora: "Olá, Flávio! Aqui é o Gustavo%'
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'cliente_aprovar') and pg_temp.fila() = 0, r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'L4a em teste: nenhuma linha cliente no fechamento',
      not exists (select 1 from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-10-30')) l where l ->> 'tipo' = 'cliente'),
      null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── o estado ligado: todos os tipos, a aprovação dos primeiros dias (3) e a rodada das 17:00
  perform pg_temp.ligar('ligado');
  perform public.agenda_cliente_vigiar(date '2026-10-30', pg_temp.em('2026-10-30 17:00'));
  v_ger := pg_temp.ver();
  v_nel := pg_temp.ver('Nelson');
  v_res := pg_temp.igual(v_res, 'L1d ligado: o que a rodada registrou espera o dono (a pergunta dos 3 primeiros dias)', pg_temp.msgs(),
    'OS-00096 confirmar ligado aguardando_dono pedida,OS-00104 acesso ligado aguardando_dono pedida,OS-00112 pode_atrasar ligado aguardando_dono pedida,OS-00121 pos_servico ligado aguardando_dono pedida,OS-00122 pronto ligado aguardando_dono pedida');
  v_res := pg_temp.igual(v_res, 'L1e ligado: esperando você (a 1ª inteira; as outras encurtam para caber), o "não respondeu" no bloco dele, o que não consigo mandar', v_ger,
    E'Mensagens ao cliente:\nEsperando você:\n• Lucenira (ficou pronto), sai agora: "Olá, Lucenira! Aqui é o Gustavo, da HBR Marine Solutions. A troca das baterias está concluída. Quando fica bom para combinarmos a entrega?" — *manda cliente Lucenira* ou *segura cliente Lucenira*\n• Rodrigo (confirmação), sai amanhã às 09:00: "Olá, Rodrigo! Conseguimos encaixar o serviço na sua lancha para…" — *manda cliente Rodrigo*\n• Flávio (véspera, com a pergunta do acesso), sai amanhã às 09:00: "Bom dia, Flávio! Na terça (03/11) chegamos à tarde para a instalação…" — *manda cliente Flávio*\n• Nelson (aviso de atraso), sai amanhã às 09:01: "Nelson, quero te avisar com antecedência: ainda faltam peças sem data…" — *manda cliente Nelson*\n• Robson (pós-serviço), sai ter 03/11 às 09:00: "Olá, Robson! Tudo certo com o serviço no seu motorhome? Já deu para…" — *manda cliente Robson*\nSem resposta:\n• Nelson: a confirmação de qui 05/11, mandada qui 22/10\n(e mais 1 linha)');
  v_res := pg_temp.ok(v_res, 'L1f ligado: o foco cabe em texto_max (1000)', char_length(v_ger) <= 1000, char_length(v_ger)::text);
  v_res := pg_temp.igual(v_res, 'L1g com a OS: o que foi dito, a mensagem inteira e o sem resposta', v_nel,
    E'Mensagens ao cliente — Nelson (OS-00112):\nO que foi dito ao cliente: qui 05/11 (data firme, por mensagem da agenda em qui 22/10).\nEsperando você:\n• Nelson (aviso de atraso), sai amanhã às 09:01: "Nelson, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então o serviço no seu veleiro, que estava para quinta (05/11), vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga." — *manda cliente Nelson* ou *segura cliente Nelson*\nSem resposta:\n• Nelson: a confirmação de qui 05/11, mandada qui 22/10');
  v_t := pg_temp.ver('Lenine');
  v_res := pg_temp.ok(v_res, 'L1h com a OS sem telefone: "sem telefone no cadastro" e o que foi dito (nada ainda)',
    v_t like '%O que foi dito ao cliente: nada ainda.%' and v_t like '%Não consigo mandar: Lenine (sem telefone no cadastro).%', v_t);
  -- (Fase 6, P8) a lista ganhou aprendizado (os 19)
  v_res := pg_temp.ok(v_res, 'L1i o foco que não existe cita os 19 (com clientes)',
    pg_temp.como(null, 'service_role', $q$select public.agenda_ver(null, null, null, 'nada', null, null, false, date '2026-10-30')::text$q$)
      like 'erro 22023: agenda_ver: foco "nada" não existe (%, compras, fornecedores, clientes ou aprendizado)', null);
  begin
    update public.agenda_config set modo_leitura = 'desligado' where id;
    r := public.agenda_ver(null, null, null, 'clientes', null, null, false, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'L1j com a leitura desligada, o foco clientes diz que a agenda está desligada (como os outros)',
      r ->> 'rota' = 'desligada' and r ->> 'texto' = 'A agenda de produção está desligada agora.', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── L4: a linha cliente do fechamento (ligado)
  v_fech := (select l ->> 'texto' from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-10-30')) l
              where l ->> 'tipo' = 'cliente' and (l ->> 'perda')::int = 75);
  v_res := pg_temp.igual(v_res, 'L4b a aprovação no fechamento: perda 75, a 1ª inteira, "E mais 3" (as que saem até o próximo dia de janela; a de ter 03/11 não)', v_fech,
    'Mensagem para Lucenira (ficou pronto), sai agora: "Olá, Lucenira! Aqui é o Gustavo, da HBR Marine Solutions. A troca das baterias está concluída. Quando fica bom para combinarmos a entrega?". *manda cliente Lucenira* ou *segura cliente Lucenira*. E mais 3: *agenda clientes* mostra; *manda cliente* manda todas.');
  v_res := pg_temp.ok(v_res, 'L4c a linha cliente vem com o tipo, o modo ligado e a pergunta (o secretário conta a mostrada)',
    exists (select 1 from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-10-30')) l
             where l ->> 'tipo' = 'cliente' and l ->> 'modo' = 'ligado' and l ->> 'pergunta_id' is not null), null);
  begin
    -- a mensagem longa (o texto de 400): o texto dela cortado em 300 e "(*agenda clientes* mostra inteira)"
    update public.agenda_cliente_mensagens m set enviar_em = m.enviar_em + interval '1 day'
     where m.estado = 'aguardando_dono' and m.tipo = 'pronto';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:teste-longa', c_van, date '2026-11-03',
                date '2026-10-30', 'teste', 'ligado', pg_temp.em('2026-10-30 17:00'), pg_temp.em('2026-10-31 13:00'));
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, dia_alvo, modo, texto, base, enviar_em,
                                                 valida_ate, aprovacao, pergunta_id, estado, dedupe_key, criada_em)
    values ('c1000000-0000-4000-8000-000000000001', c_van, 'confirmar', 'rodada', date '2026-11-03', 'ligado',
            'Vanderlei, ' || repeat('palavra ', 70) || 'fim.', '{}'::jsonb, pg_temp.em('2026-10-30 17:10'), pg_temp.em('2026-10-31 13:00'),
            'pedida', v_perg, 'aguardando_dono', 'agenda-cliente:teste:longa', pg_temp.em('2026-10-30 17:00'));
    v_t := (select l ->> 'texto' from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-10-30')) l
             where l ->> 'tipo' = 'cliente' and (l ->> 'perda')::int = 75);
    v_res := pg_temp.ok(v_res, 'L4d a mensagem longa: o texto cortado em 300 com "(*agenda clientes* mostra inteira)", a linha ≤ 600',
      v_t like 'Mensagem para Vanderlei (confirmação), sai agora: "Vanderlei, palavra%…" (*agenda clientes* mostra inteira). *manda cliente Vanderlei* ou *segura cliente Vanderlei*. E mais 4:%'
      and char_length(v_t) <= 600, char_length(v_t)::text || ' ' || v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── L6: determinismo
  v_res := pg_temp.ok(v_res, 'L6 duas leituras seguidas dão o mesmo texto (md5): o foco, com a OS, e as linhas do fechamento',
    md5(pg_temp.ver()) = md5(v_ger) and md5(pg_temp.ver('Nelson')) = md5(v_nel)
    and md5(public._agenda_linhas_do_fechamento(date '2026-10-30')::text) = md5(public._agenda_linhas_do_fechamento(date '2026-10-30')::text),
    null);

  -- ── L7: quem vê
  v_res := pg_temp.ok(v_res, 'L7a o técnico: o foco, as palavras e a ferramenta recusam (42501)',
    pg_temp.como(c_tec, 'authenticated', $q$select public._agenda_ver_clientes(null, '2026-10-30') ->> 'texto'$q$) like 'erro 42501:%'
    and pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_cliente_decidir_dito(null, 'manda', null, 'painel', '2026-10-30', now())::text$q$) like 'erro 42501:%'
    and pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_cliente_preparar(null, 'Flávio', 'confirmar', false, 'x', '2026-10-30', now())::text$q$) like 'erro 42501:%',
    null);
  v_res := pg_temp.ok(v_res, 'L7b o administrador com login lê o mesmo foco que o WhatsApp',
    pg_temp.como(c_admin, 'authenticated', $q$select public.agenda_ver(null, null, null, 'clientes', null, null, false, '2026-10-30') ->> 'texto'$q$) = v_ger,
    pg_temp.como(c_admin, 'authenticated', $q$select public.agenda_ver(null, null, null, 'clientes', null, null, false, '2026-10-30') ->> 'texto'$q$));

  -- ── L3: cliente_avisar (ligado)
  r := pg_temp.prep('Nelson', 'material_chegou');
  v_res := pg_temp.igual(v_res, 'L3a sem o material todo na mão (d09): não prepara e diz o que falta', r ->> 'texto',
    'O material de Nelson ainda não está todo na mão (tem peça sem previsão de chegada): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.');
  r := pg_temp.prep('Giancarlo', 'pode_atrasar');
  v_res := pg_temp.igual(v_res, 'L3b sem data dita ao cliente: não há atraso a avisar', r ->> 'texto',
    'Não há data dita para Giancarlo: sem data dita, não há atraso a avisar. Se você disse uma data, me conte ("falei pro Giancarlo que é dia 3").');
  r := pg_temp.prep('Lenine', 'confirmar');
  r2 := pg_temp.prep('Flávio', 'mudanca_no_dia');
  v_res := pg_temp.ok(v_res, 'L3c sem telefone e a mudança no dia: não prepara',
    r ->> 'texto' = 'Lenine não tem telefone no cadastro: não tenho como mandar.' and r2 ->> 'motivo' = 'mudanca_no_dia',
    r::text || r2::text);
  r := pg_temp.prep('Nelson', 'pode_atrasar');
  v_res := pg_temp.ok(v_res, 'L3d a que a rodada já registrou: "Já está pronta, esperando você" (não duplica)',
    r ->> 'status' = 'ja_existe' and r ->> 'texto' like 'Já está pronta, esperando você (sai amanhã às 09:01): "Nelson, quero te avisar%". Para mandar: *manda cliente Nelson*.'
    and (select count(*) from public.agenda_cliente_mensagens m where m.service_order_id = c_nel and m.tipo = 'pode_atrasar') = 1,
    r ->> 'texto');
  v_ms := pg_temp.msgs();
  v_n := pg_temp.fila();
  r := pg_temp.prep('Flávio', 'confirmar');
  v_res := pg_temp.igual(v_res, 'L3e a preparada: o texto do banco e a palavra que manda', r ->> 'texto',
    'Pronto para Flávio, sai agora: "Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Conseguimos encaixar a instalação do compressor para terça (03/11), à tarde, com previsão de 2 dias de trabalho. Pode ser? Responda SIM para confirmar, ou me diga um dia melhor. A partir de agora te mando por aqui as novidades do serviço.". Para mandar: *manda cliente Flávio*.');
  v_res := pg_temp.ok(v_res, 'L3f a preparada fica esperando o dono (origem dono, pedida, com a pergunta); nada na fila',
    exists (select 1 from public.agenda_cliente_mensagens m join public.agenda_perguntas q on q.id = m.pergunta_id
             where m.service_order_id = c_flav and m.tipo = 'confirmar' and m.origem = 'dono' and m.aprovacao = 'pedida'
               and m.estado = 'aguardando_dono' and q.tipo = 'cliente_aprovar' and q.estado = 'aberta')
    and pg_temp.fila() = v_n, pg_temp.msgs());
  r := pg_temp.prep('Nelson', 'pode_atrasar', true);
  v_res := pg_temp.igual(v_res, 'L3g a firme sem o plano publicado: não prepara', r ->> 'texto',
    'Nelson não tem o plano publicado: não tenho data firme para dizer; vai a faixa.');
  begin
    -- a firme do plano: o Flávio ouviu seg 02/11 e o plano é ter 03/11 → o M6 remarcado com o dia do plano
    perform public._agenda_cliente_gravar_prometido(c_flav, 'firme', date '2026-11-02', date '2026-11-02', 'dono', null,
                                                    pg_temp.em('2026-10-29 10:00'), 'teste');
    r := pg_temp.prep('Flávio', 'pode_atrasar', true);
    v_res := pg_temp.ok(v_res, 'L3i a firme do plano: o aviso remarcado com o dia do plano, esperando o dono',
      r ->> 'texto' like 'Pronto para Flávio, sai hoje às 17:30: "Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. A instalação do compressor, que estava para segunda (02/11), precisou passar para terça (03/11), à tarde. Desculpe pela mudança.%'
      and exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_flav and m.tipo = 'pode_atrasar'
                   and m.variante = 'remarcado' and m.prometido_tipo = 'firme' and m.aprovacao = 'pedida'), r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── L2: as palavras (ligado)
  v_ms := pg_temp.msgs();
  v_n := pg_temp.fila();
  r := pg_temp.dito('manda', 'orçamento');
  v_res := pg_temp.ok(v_res, 'L2b "manda cliente orçamento": não achei, e nada muda (nem a fila)',
    r ->> 'status' = 'nao_achei' and r ->> 'texto' = 'Não achei mensagem esperando para "orçamento".'
    and pg_temp.msgs() = v_ms and pg_temp.fila() = v_n, r::text);
  r := pg_temp.dito('manda', 'Nelson');
  v_res := pg_temp.igual(v_res, 'L2c *manda cliente Nelson*: aprovada, sai na hora dela', r ->> 'texto', 'Mando para Nelson amanhã às 09:01.');
  v_res := pg_temp.ok(v_res, 'L2d o Nelson aprovado espera a hora (nada na fila ainda); a pergunta respondida pelo WhatsApp',
    exists (select 1 from public.agenda_cliente_mensagens m join public.agenda_perguntas q on q.id = m.pergunta_id
             where m.service_order_id = c_nel and m.tipo = 'pode_atrasar' and m.aprovacao = 'aprovada'
               and q.estado = 'respondida' and q.opcao_escolhida = 1 and q.respondida_via = 'whatsapp')
    and pg_temp.fila() = v_n, pg_temp.msgs());
  r := pg_temp.dito('segura', 'Flávio');
  v_res := pg_temp.ok(v_res, 'L2e *segura cliente Flávio*: as duas do Flávio (a véspera e a preparada) não saem',
    r ->> 'texto' like 'Segurei 2: as mensagens de Flávio não saem.'
    and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_flav and m.estado <> 'recusada'),
    r ->> 'texto');
  r := pg_temp.dito('segura', 'Nelson');
  v_res := pg_temp.ok(v_res, 'L2f *segura cliente Nelson* depois do *manda*: a aprovada que espera a hora também se segura',
    r ->> 'texto' = 'Segurei a mensagem de Nelson: ela não sai.'
    and exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_nel and m.tipo = 'pode_atrasar'
                 and m.estado = 'recusada' and m.recusa_motivo = 'segurada' and m.aprovacao = 'segurada'), r::text);
  begin
    -- dois clientes "Rodrigo" esperando: diga o sobrenome
    insert into public.clients (id, type, name, whatsapp) values ('c1000000-0000-4000-8000-0000000000f1', 'individual', 'Rodrigo Souza', '5547900000399');
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:teste-rodrigo', c_van, date '2026-11-03',
                date '2026-10-30', 'teste', 'ligado', pg_temp.em('2026-10-30 17:00'), pg_temp.em('2026-10-31 13:00'));
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, dia_alvo, modo, texto, base, enviar_em,
                                                 valida_ate, aprovacao, pergunta_id, estado, dedupe_key, criada_em)
    values ('c1000000-0000-4000-8000-0000000000f1', c_van, 'confirmar', 'rodada', date '2026-11-03', 'ligado', 'Rodrigo, teste.',
            '{}'::jsonb, pg_temp.em('2026-10-31 09:00'), pg_temp.em('2026-10-31 13:00'), 'pedida', v_perg, 'aguardando_dono',
            'agenda-cliente:teste:rodrigo', pg_temp.em('2026-10-30 17:00'));
    r := pg_temp.dito('manda', 'Rodrigo');
    r2 := pg_temp.dito('manda', 'Rodrigo Souza');
    v_res := pg_temp.ok(v_res, 'L2g dois clientes Rodrigo: pede o sobrenome (nada muda); com o sobrenome, só o dele',
      r ->> 'status' = 'ambiguo' and r ->> 'texto' = 'Tem 2 clientes "Rodrigo" esperando (Rodrigo e Rodrigo Souza): diga o sobrenome.'
      and (r2 ->> 'decididas')::int = 1 and r2 -> 'mensagens' ->> 0 = (select m.id::text from public.agenda_cliente_mensagens m
                                                                          where m.dedupe_key = 'agenda-cliente:teste:rodrigo'
                                                                            and m.aprovacao = 'aprovada')
      and exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = '05000000-0000-4000-8000-000000000096'
                   and m.aprovacao = 'pedida'), r::text || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o aviso que é decisão (cliente_aviso crítico): não é por aqui
    r := public._agenda_cliente_registrar('pode_atrasar', 'peca', c_nel, date '2026-11-16',
           jsonb_build_object('faixa_de', '2026-11-16', 'faixa_ate', '2026-11-17', 'peca_de', '2026-11-12', 'peca_ate', '2026-11-12',
                              'dito_de', '2026-11-05', 'dito_ate', '2026-11-05', 'chave', 'teste-critica'),
           pg_temp.em('2026-10-30 17:20'), pg_temp.em('2026-10-30 19:00'), 'rodada', 'segundo_atraso', pg_temp.em('2026-10-30 17:20'));
    r2 := pg_temp.dito('manda', 'Nelson');
    v_res := pg_temp.ok(v_res, 'L2h o aviso que é decisão: "Essa é uma decisão: responda pela conversa (opção 1, 2 ou 3)."; nada muda',
      r ->> 'aprovacao' = 'critica' and r2 ->> 'status' = 'decisao'
      and r2 ->> 'texto' = 'Essa é uma decisão: responda pela conversa (opção 1, 2 ou 3).'
      and exists (select 1 from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid and m.aprovacao = 'critica'),
      r::text || r2::text);
    v_t := pg_temp.ver('Nelson');
    v_res := pg_temp.ok(v_res, 'L1k o aviso que é decisão aparece em "Esperando você" como decisão', v_t like '%• Decisão: O serviço da OS-00112 de Nelson vai atrasar de novo%', v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  r := pg_temp.dito('manda', null);
  v_res := pg_temp.igual(v_res, 'L2i *manda cliente* (todas): as que ainda esperam', r ->> 'texto',
    'Mando para Lucenira agora. Mando para Rodrigo amanhã às 09:00. Mando para Robson ter 03/11 às 09:00.');
  v_res := pg_temp.ok(v_res, 'L2j só a da hora entrou na fila (a do Lucenira, agora); as outras esperam a hora; a do Rodrigo vai recusar sem conversa na saída',
    pg_temp.fila() = v_n + 1
    and not exists (select 1 from public.agenda_cliente_mensagens m where m.estado = 'aguardando_dono' and m.aprovacao = 'pedida'),
    pg_temp.msgs());
  r := pg_temp.dito('manda', null);
  v_res := pg_temp.igual(v_res, 'L2k *manda cliente* sem nada esperando', r ->> 'texto', 'Não tenho mensagem ao cliente esperando você.');

  -- ── L4e: o que sai sozinho amanhã (o tipo já liberado: cliente_aprovacao_dias = 0)
  begin
    update public.agenda_config set cliente_aprovacao_dias = 0 where id;
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'segurada', aprovacao = 'segurada',
                                               aprovada_em = coalesce(aprovada_em, now())
     where estado in ('registrada', 'aguardando_dono') and id <> 'd5000000-0000-4000-8000-0000000000a1';
    r := public._agenda_cliente_registrar('confirmar', 'seguinte', c_flav, date '2026-11-05', '{}'::jsonb, pg_temp.em('2026-10-31 09:00'),
                                          null, 'rodada', null, pg_temp.em('2026-10-30 17:00'));
    v_t := (select l ->> 'texto' from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-10-30')) l
             where l ->> 'tipo' = 'cliente' and (l ->> 'perda')::int = 40);
    v_res := pg_temp.igual(v_res, 'L4e o que sai sozinho amanhã: perda 40, com *segura cliente*', v_t,
      'Amanhã, a partir das 09:00, vou mandar: a confirmação de ter 03/11 para Flávio. Para não mandar: *segura cliente Flávio*.');
    r2 := pg_temp.dito('segura', 'Flávio', '2026-10-30 17:40');
    v_res := pg_temp.ok(v_res, 'L2l *segura cliente Flávio* segura a que ia sair sozinha',
      r2 ->> 'texto' = 'Segurei a mensagem de Flávio: ela não sai.'
      and exists (select 1 from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid and m.estado = 'recusada'
                   and m.recusa_motivo = 'segurada' and m.aprovacao = 'segurada'), r::text || r2::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── L9: o que mudou — a resposta do cliente e o replano dele num grupo só
  begin
    update public.agenda_config set cliente_aprovacao_dias = 0 where id;
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, base,
                                                 enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
    values (c_cli_flav, c_flav, 'confirmar', 'seguinte', 'rodada', date '2026-11-03', 'ligado', 'mensagem de teste (L9)',
            '{"dia_alvo": "2026-11-03"}'::jsonb, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 19:00'), 'livre', 'enviada',
            'agenda-cliente:teste:l9', pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'))
    returning id into v_id;
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'segurada', aprovacao = 'segurada',
                                               aprovada_em = now()
     where service_order_id = c_flav and estado = 'aguardando_dono';
    r := public.agenda_resposta_do_cliente('5547900000304', 'pode ser sexta?', gen_random_uuid(), 'text', 'data', 'sexta',
                                           pg_temp.em('2026-10-30 10:00'));
    select count(*) into v_n
      from jsonb_array_elements(public._agenda_mudancas(date '2026-10-24', date '2026-10-30', true, true, pg_temp.em('2026-10-30 17:30'))) g
     where g ->> 'os' = c_flav::text and g ->> 'tipo' = 'acao';
    v_t := (select g ->> 'itens' from jsonb_array_elements(public._agenda_mudancas(date '2026-10-24', date '2026-10-30', true, true,
                                                                                 pg_temp.em('2026-10-30 17:30'))) g
             where g ->> 'os' = c_flav::text and g ->> 'tipo' = 'acao');
    v_res := pg_temp.ok(v_res, 'L9a o pedido do cliente e o replano dele: um grupo só, com a frase do cliente (sem o *desfaz* em dobro), as duas ações contadas',
      r ->> 'efeito' = 'replanejou' and v_n = 1
      and v_t = '["Flávio pediu sex 06/11: remarquei para seg 09/11, o 1º dia que coube."]'
      and (select jsonb_array_length(g -> 'acao_ids') from jsonb_array_elements(public._agenda_mudancas(date '2026-10-24', date '2026-10-30',
             true, true, pg_temp.em('2026-10-30 17:30'))) g where g ->> 'os' = c_flav::text and g ->> 'tipo' = 'acao') = 2,
      coalesce(v_t, '(nada)') || ' ' || r::text);
    v_t := (select l ->> 'texto' from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-10-30')) l
             where l ->> 'tipo' = 'mudancas' and l ->> 'modo' = 'ligado');
    v_res := pg_temp.igual(v_res, 'L9b a linha mudancas do fechamento: o pedido do cliente uma vez, com o *desfaz*', v_t,
      'Agenda, mudei sozinho. Flávio pediu sex 06/11: remarquei para seg 09/11, o 1º dia que coube. *desfaz Flávio* volta como estava.');
    v_t := pg_temp.ver('Flávio');
    v_res := pg_temp.ok(v_res, 'L1l o foco com a OS mostra a resposta e o efeito ("Responderam")',
      v_t like E'%Responderam (7 dias):\n• Flávio respondeu "pode ser sexta?" à confirmação de ter 03/11: pediu outro dia, e eu replanejei%', v_t);
    -- o acorde da mensagem ao cliente (aviso ao dono) não é mudança
    perform public._agenda_cliente_acorde(c_nel, 'teste-acorde', 'A data que o Nelson ouviu passou.', date '2026-10-30',
                                          date '2026-10-30', null);
    v_res := pg_temp.ok(v_res, 'L9c o acorde da mensagem ao cliente não entra no que mudou',
      not exists (select 1 from jsonb_array_elements(public._agenda_mudancas(date '2026-10-24', date '2026-10-30', true, false, null)) g,
                         jsonb_array_elements_text(g -> 'itens') i where i like 'A data que o Nelson ouviu%'), null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── L5: o rascunho do prometido e do serviço dito ao cliente
  begin
    select count(*) into v_n from public.os_planejamento p where p.prometido_ate is not null;
    r := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Vanderlei', '{"prometido": "dia 3", "servico_cliente": "a revisão do motor"}',
                                         'falei pro Vanderlei que fica pra dia 3, pra ele é a revisão do motor', date '2026-10-30');
    v_res := pg_temp.igual(v_res, 'L5a a releitura: o que o dono disse ao cliente (firme) e o serviço como o cliente diz', r ->> 'item',
      'Vanderlei (OS-00069): você disse ao Vanderlei: ter 03/11 (data firme); o serviço, para o cliente: a revisão do motor');
    r := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Lenine', '{"prometido": "dia 5"}', 'falei pro Lenine que é dia 3', date '2026-10-30');
    r2 := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Lenine', '{"prometido": "entre 9 e 12/11"}',
                                          'falei pro Lenine que fica entre 9 e 12/11', date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'L5b o número fora do trecho recusa; a faixa ("entre 9 e 12/11") entra como faixa',
      r ->> 'texto' = 'Não achei "dia 5" no que você disse; me diga de novo.'
      and r2 ->> 'item' = 'Lenine (OS-00074): você disse ao Lenine: de seg 09/11 a qui 12/11 (uma faixa)', r::text || r2::text);
    r := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Nelson', '{"servico_cliente": "a instalação do painel solar e do inversor novo no barco"}',
                                         'pro cliente é a instalação do painel solar e do inversor novo no barco', date '2026-10-30');
    r2 := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Nelson', '{"servico_cliente": "a troca do painel por R$ 500"}',
                                          'pro cliente é a troca do painel por R$ 500', date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'L5c o serviço longo (mais de 40) e com valor recusam',
      r ->> 'motivo' = 'servico_longo' and r2 ->> 'motivo' = 'servico_proibido', r::text || r2::text);
    v_res := pg_temp.ok(v_res, 'L5d antes do *grava*, nada muda em os_planejamento',
      (select count(*) from public.os_planejamento p where p.prometido_ate is not null) = v_n
      and not exists (select 1 from public.os_planejamento p where p.servico_cliente = 'a revisão do motor'), null);
    r := public.agenda_rascunho_gravar(c_admin, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'L5e o *grava*: o prometido firme (fonte dono, o original na 1ª vez), a faixa e o serviço',
      (r ->> 'ok')::boolean
      and exists (select 1 from public.os_planejamento p where p.service_order_id = c_van and p.prometido_tipo = 'firme'
                   and p.prometido_de = date '2026-11-03' and p.prometido_ate = date '2026-11-03'
                   and p.prometido_original_ate = date '2026-11-03' and p.prometido_fonte = 'dono'
                   and p.servico_cliente = 'a revisão do motor')
      and exists (select 1 from public.os_planejamento p where p.service_order_id = '05000000-0000-4000-8000-000000000074'
                   and p.prometido_tipo = 'faixa' and p.prometido_de = date '2026-11-09' and p.prometido_ate = date '2026-11-12'),
      r::text);
    r := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Vanderlei', '{"prometido": "dia 4"}', 'falei pro Vanderlei que é dia 4',
                                         date '2026-10-30');
    r := public.agenda_rascunho_gravar(c_admin, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'L5f a 2ª promessa muda o prometido e guarda o original (03/11)',
      exists (select 1 from public.os_planejamento p where p.service_order_id = c_van and p.prometido_ate = date '2026-11-04'
                   and p.prometido_original_ate = date '2026-11-03'), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$l1$;

-- ── L8. As cópias só acrescentam os blocos "-- FASE 5:" ─────────────────────────────────────────────────
do $l8$
declare
  v_res jsonb := '[]'::jsonb;
  f record;
  v_ruins text := '';
  v_src text;
begin
  if coalesce(current_setting('agenda_teste.mig_leituras_fase4', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_acompanhamento_fase3', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_notas_pix_fase4', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_rascunho_fase2', true), '') = '' then
    insert into _resultado values ('L8 as cópias', true, 'PULADO: sem as migrations antigas como texto (rode pela bancada)');
    return;
  end if;
  for f in select * from (values
      ('agenda_ver', 'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'mig_leituras_fase4', 1),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', 'mig_acompanhamento_fase3', 1),
      ('_agenda_mudancas', 'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)', 'mig_notas_pix_fase4', 4),
      ('_agenda_rascunho_frase', 'public._agenda_rascunho_frase(text, jsonb)', 'mig_notas_pix_fase4', 1),
      ('agenda_rascunho_planejar', 'public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)', 'mig_rascunho_fase2', 3),
      ('_agenda_aplicar_planejar', 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', 'mig_rascunho_fase2', 4))
      as x(nome, sig, mig, blocos) loop
    v_src := (select p.prosrc from pg_proc p where p.oid = f.sig::regprocedure);
    if pg_temp.sem_fase5(v_src) is distinct from string_to_array(pg_temp.corpo(current_setting('agenda_teste.' || f.mig), f.nome), E'\n')
       or (select count(*) from regexp_matches(v_src, '-- FASE 5: fim', 'g')) <> f.blocos then
      v_ruins := v_ruins || f.nome || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'L8 as 6 cópias só acrescentam os blocos "-- FASE 5:" (o resto é o corpo da migration mais nova de cada uma)',
                      v_ruins = '', nullif(v_ruins, ''));
  perform pg_temp.gravar(v_res);
end
$l8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
