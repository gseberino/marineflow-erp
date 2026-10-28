-- Prova do acabamento da Fase 5 na Agenda de Produção, Fase 6 (pacote P7, migration 20261029100700): o texto ao dono sem artigo
-- nem possessivo antes do nome e sem "ele"/"a ele", o M6 "só o fim muda" com o número de dias e o "peça sem data" sem a
-- repetição (spec-fase6 §5.7, §6.1 e §6.4).
-- bancada: depende de 20261029100950
--
--   A1 cada texto da §6.4 com a fixture (o SIM, o dia pedido, o acesso, o opt-out e os *desfaz* deles; as recusas de
--      cliente_avisar; a pergunta ao dono da resposta; a decisão da data que passou; o foco clientes; o cartão; o que eu teria
--      feito em teste; o botão "Pedir confirmação"), e o ralo (_agenda_cliente_sem_artigo) com a tabela dos pronomes
--   A2 os 2 textos ao cliente da §6.1: a forma fim com n = 1 e n = 3 (e o fim que não passa do dia dito, que não vira texto);
--      o aviso "peça sem data" sem a repetição, pela rodada; o risco da §9 (o registrado e não enviado com o texto de antes
--      sai "desatualizada") e o resto dos textos ao cliente igual (o X1 da Fase 5)
--   A3 nenhum "O <nome>", "ao <nome>", "do <nome>", "ele" nem "a ele" no que as funções devolvem e gravam ao dono com a
--      fixture inteira (o texto do cliente citado entre aspas fica de fora: é o que ele escreveu ou o que ele ouve); o
--      controle: a mesma varredura acha o texto de antes
--   A4 as cópias: as 12 recriadas só acrescentam os blocos "-- FASE 6:" (× a migration de onde cada uma foi copiada); as
--      portas de antes
--   A5 (correção C2, 20261029100950) a forma fim sem atraso para avisar: a recusa ao dono em palavras
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_acabamento.sql
--   A4 roda em qualquer lugar (as cópias só com as migrations como texto); o resto só na bancada (a fixture-fase6; fora
--   dela, PULADO). Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_tem text, p_quer text) returns jsonb language sql immutable as $f$
  select pg_temp.ok(p_res, p_nome, p_tem is not distinct from p_quer,
                    case when p_tem is distinct from p_quer then coalesce(p_tem, '(nulo)') end)
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;

-- Liga a mensagem ao cliente (o modo, todos os tipos e sem a aprovação dos primeiros dias).
create function pg_temp.ligar(p_modo text default 'ligado') returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = p_modo, cliente_aprovacao_dias = 0,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                       'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;

-- Uma mensagem da agenda já enviada ao cliente (o molde do agenda_fase5_respostas.sql).
create function pg_temp.enviada(p_cli uuid, p_os uuid, p_tipo text, p_dia date, p_em text, p_var text default null)
returns uuid language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, base,
                                               enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
  values (p_cli, p_os, p_tipo, p_var, 'rodada', p_dia, 'ligado', 'mensagem de teste (AG6P7)',
          case when p_dia is null then '{}'::jsonb else jsonb_build_object('dia_alvo', p_dia) end,
          pg_temp.em(p_em), pg_temp.em(p_em) + interval '9 hours', 'livre', 'enviada',
          'agenda-cliente:teste:' || gen_random_uuid(), pg_temp.em(p_em), pg_temp.em(p_em) - interval '1 hour')
  returning id
$f$;

-- A mensagem do cliente que chega (o que o webhook passa); o "hoje" de quem lê o relógio acompanha.
create function pg_temp.resp(p_fone text, p_body text, p_int text, p_expr text, p_em text, p_tipo text default 'text')
returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_em, 10), true);
  return public.agenda_resposta_do_cliente(p_fone, p_body, gen_random_uuid(), p_tipo, p_int, p_expr, pg_temp.em(p_em));
end $f$;

-- cliente_avisar como o dono (a ferramenta), num dia e hora.
create function pg_temp.prep(p_os text, p_tipo text, p_quando text default '2026-10-30 10:00', p_firme boolean default false)
returns jsonb language sql as $f$
  select public.agenda_cliente_preparar('aa000000-0000-4000-8000-000000000001', p_os, p_tipo, p_firme, 'avisa o cliente',
                                        left(p_quando, 10)::date, pg_temp.em(p_quando))
$f$;

-- Um tique da rodada do cliente, com o "hoje" de quem lê o relógio acompanhando.
create function pg_temp.vig(p_quando text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda_teste.hoje', left(p_quando, 10), true);
  return public.agenda_cliente_vigiar(left(p_quando, 10)::date, pg_temp.em(p_quando));
end $f$;

-- Os textos de um jsonb (todas as strings, em qualquer nível), cada um como uma saída [origem, os, texto].
create function pg_temp.textos(p_origem text, p_os uuid, p_j jsonb) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(jsonb_build_array(p_origem, p_os, s #>> '{}')), '[]'::jsonb)
    from jsonb_path_query(coalesce(p_j, 'null'::jsonb), 'strict $.** ? (@.type() == "string")') s
$f$;

-- O que a agenda gravou ao dono desde a fixture (as ações e as perguntas novas: as que não estão em _base), como saídas.
create temp table _base (id uuid primary key) on commit drop;
create function pg_temp.gravadas() returns jsonb language sql stable as $f$
  select coalesce(jsonb_agg(x.j), '[]'::jsonb) from (
    select jsonb_build_array('ação ' || a.tipo, a.service_order_id, a.texto) as j
      from public.agenda_acoes a where a.texto is not null and not exists (select 1 from _base b where b.id = a.id)
    union all
    select jsonb_build_array('pergunta ' || q.tipo, q.service_order_id, t.v)
      from public.agenda_perguntas q, lateral (values (q.texto), (q.resolvida_motivo)) t(v)
     where t.v is not null and not exists (select 1 from _base b where b.id = q.id)) x
$f$;

-- A3: o texto ao dono tem artigo antes do nome do cliente, ou "ele"? (o que está entre aspas é do cliente e fica de fora)
create function pg_temp.achado(p_texto text, p_nomes text[]) returns text language plpgsql immutable as $f$
declare
  v text := regexp_replace(coalesce(p_texto, ''), '"[^"]*"', '"…"', 'g');
  n text;
begin
  if v ~* '\mele\M' then
    return '"ele"';
  end if;
  foreach n in array p_nomes loop
    if v ~ ('(^|[^[:alpha:]])(O|ao|do) ' || n || '($|[^[:alpha:]])') then
      return format('artigo antes de %s', n);
    end if;
  end loop;
  return null;
end $f$;

-- O corpo de uma função numa migration (entre o "as $function$"/"as $$" que abre e o fecho), e as linhas sem os blocos
-- "-- FASE 6: … -- FASE 6: fim" (o fim é lido pelo prefixo).
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
create function pg_temp.sem_f6(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_c6 boolean := false;  -- CORREÇÃO FASE 6 (C2): dentro de um bloco da correção da Fase 6
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
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

-- ── A1–A3 (a fixture-fase6) ─────────────────────────────────────────────────────────────────────────────
do $a$
declare
  v_res  jsonb := '[]'::jsonb;
  v_said jsonb := '[]'::jsonb;   -- as saídas ao dono [origem, os, texto] (A3); fica de fora das subtransações desfeitas
  c_flav constant uuid := '05000000-0000-4000-8000-000000000104';
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_ven  constant uuid := '05000000-0000-4000-8000-000000000069';
  c_gia  constant uuid := '05000000-0000-4000-8000-000000000100';
  c_rob  constant uuid := '05000000-0000-4000-8000-000000000121';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_cli_flav constant uuid := 'c1000000-0000-4000-8000-000000000004';
  c_cli_nel  constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_cli_luc  constant uuid := 'c1000000-0000-4000-8000-000000000012';
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_f    constant text := '5547900000304';   -- o WhatsApp do Flávio
  c_n    constant text := '5547900000305';   -- o do Nelson
  c_l    constant text := '5547900000312';   -- o da Lucenira
  v_nomes text[];
  r  jsonb;
  r2 jsonb;
  x  jsonb;
  v_id  uuid;
  v_id2 uuid;
  v_p   uuid;
  v_t   text;
  v_ruins text;
  e jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('A1–A3 (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase6');
  insert into _base select a.id from public.agenda_acoes a union select q.id from public.agenda_perguntas q;
  -- os nomes como o dono lê (o 1º nome curto de cada cliente da fixture)
  v_nomes := array(select distinct public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                     from public.clients cl
                    where public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) ~ '^[[:alpha:]]{2,}$');

  -- ── A1a. O ralo: a tabela dos pronomes, com e sem a OS ──
  v_res := pg_temp.igual(v_res, 'A1a1 o ralo troca as frases com "ele" pela tabela (sem precisar da OS)',
    public._agenda_cliente_sem_artigo('Não respondi nada: não entendi o que ele quer; o dia que ele pediu; a data que ele ouviu; combine a entrega com ele; não mando mais nada a ele; não tenho como mandar a ele (telefone ou conversa); só ele pode pedir para voltar. Quando ele responder SIM, ok. Se você disse uma data a ele, me conte. O que foi dito a ele: nada. Ele confirmou ter 03/11; há 2 serviços esperando resposta dele.', null),
    'Não respondi nada: não entendi o pedido; o dia pedido; a data dita; combine a entrega com o cliente; não mando mais nada; não tenho como mandar (telefone ou conversa); só o cliente pode pedir para voltar. Quando a resposta for SIM, ok. Se você disse uma data, me conte. O que foi dito ao cliente: nada. O cliente confirmou ter 03/11; há 2 serviços esperando resposta do cliente.');
  v_res := pg_temp.igual(v_res, 'A1a2 com a OS, o artigo antes do nome sai como na C2, e o "ele" junto ("A data dita…", "Não mandei para Flávio: o cliente já recebeu…")',
    public._agenda_cliente_sem_artigo('O Flávio respondeu: a data que ele ouviu passou. Não mandei ao Flávio: ele já recebeu as mensagens que cabem; ele pediu para não receber mensagens; ele não escreveu para a HBR no último ano; ele tinha acabado de receber outra.', c_flav),
    'Flávio respondeu: a data dita passou. Não mandei para Flávio: o cliente já recebeu as mensagens que cabem; o cliente pediu para não receber mensagens; o cliente não escreveu para a HBR no último ano; o cliente tinha acabado de receber outra.');
  v_res := pg_temp.ok(v_res, 'A1a3 o texto sem nenhuma das frases não muda (nem o "dele" de outra pessoa, nem "telefone")',
    public._agenda_cliente_sem_artigo('Roberto disse que o barco dele está no telefone; Ele é outro.', null)
      = 'Roberto disse que o barco dele está no telefone; Ele é outro.'
    and public._agenda_cliente_sem_artigo(null, c_flav) is null, null);

  perform pg_temp.ligar();

  -- ── A1b. O SIM e o *desfaz* dele ──
  begin
    -- o desfazer vale 72 h (o máximo do CHECK) e o SIM chega no domingo: o *desfaz* ainda vale na terça, quando o dia começa
    update public.agenda_config set desfazer_validade = interval '72 hours' where id;
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-11-01 10:00');
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, r ->> 'texto'));
    v_res := pg_temp.igual(v_res, 'A1b1 o SIM: "Flávio confirmou ter 03/11." (a ação e o texto devolvido)', r ->> 'texto',
                           'Flávio confirmou ter 03/11.');
    v_res := pg_temp.igual(v_res, 'A1b2 a ação gravada é a mesma', (select a.texto from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid),
                           'Flávio confirmou ter 03/11.');
    -- o cartão e o foco com a confirmação (antes de desfazer)
    x := public._agenda_cliente_da_os(c_flav, date '2026-11-01');
    v_said := v_said || pg_temp.textos('cartão', c_flav, x);
    v_res := pg_temp.igual(v_res, 'A1b3 o cartão: "O cliente confirmou ter 03/11." (era "Ele confirmou …")', x ->> 'confirmado_texto',
                           'O cliente confirmou ter 03/11.');
    perform set_config('agenda.agora', pg_temp.em('2026-11-01 10:05')::text, true);
    r2 := public._agenda_ver_clientes(c_flav, date '2026-11-01');
    perform set_config('agenda.agora', '', true);
    v_said := v_said || jsonb_build_array(jsonb_build_array('foco', c_flav, r2 ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1b4 o foco da OS: "O que foi dito ao cliente: …" e "O cliente confirmou ter 03/11."',
      r2 ->> 'texto' like E'Mensagens ao cliente — Flávio (OS-00104):\nO que foi dito ao cliente: %\nO cliente confirmou ter 03/11.%'
      and r2 ->> 'texto' not like '%a ele%', r2 ->> 'texto');
    -- o *desfaz* do dia já começado (direto: o prazo do desfazer, até qua 04/11 10:00, ainda não passou e o dia já começou)
    x := public._agenda_desfazer_cliente((r ->> 'acao_id')::uuid, c_dono, 'whatsapp', date '2026-11-03', pg_temp.em('2026-11-03 14:00'));
    v_said := v_said || pg_temp.textos('desfazer', c_flav, x);
    v_res := pg_temp.igual(v_res, 'A1b5 o *desfaz* do dia que já começou: "… já começou o dia que Flávio confirmou."', x ->> 'texto',
                           'Não dá para desfazer: já começou o dia que Flávio confirmou.');
    x := public._agenda_desfazer_cliente((r ->> 'acao_id')::uuid, c_dono, 'whatsapp', date '2026-12-01', pg_temp.em('2026-12-01 10:00'));
    v_said := v_said || pg_temp.textos('desfazer', c_flav, x);
    v_res := pg_temp.igual(v_res, 'A1b6 o *desfaz* fora do prazo: "Não dá mais para desfazer o que Flávio respondeu: …"', x ->> 'texto',
                           'Não dá mais para desfazer o que Flávio respondeu: passou o prazo. Se quiser mudar, me diga o dia.');
    r2 := public.agenda_desfazer_dito(c_dono, 'Flávio', 'whatsapp', date '2026-11-01', pg_temp.em('2026-11-01 11:00'));
    v_said := v_said || jsonb_build_array(jsonb_build_array('desfazer', c_flav, r2 ->> 'texto'));
    v_res := pg_temp.igual(v_res, 'A1b7 *desfaz Flávio*: "Desfeito: a confirmação de Flávio (ter 03/11) sai; …"', r2 ->> 'texto',
                           'Desfeito: a confirmação de Flávio (ter 03/11) sai; o dia continua no plano, sem fixar.');
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1c. O dia pedido e o *desfaz* dele ──
  begin
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-29 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Infelizmente não vou poder', 'remarcar', null, '2026-10-29 10:00');
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1c1 o dia recusado: "Flávio pediu outro dia (ter 03/11 não dá): tirei o dia e remarquei para …" (a ação e o texto)',
      r ->> 'efeito' = 'replanejou'
      and r ->> 'texto' like 'Flávio pediu outro dia (ter 03/11 não dá): tirei o dia e remarquei para %. *desfaz Flávio* volta como estava.'
      and (select a.texto from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid) = r ->> 'texto', r::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, c_dono, 'whatsapp', date '2026-10-29', pg_temp.em('2026-10-29 10:30'));
    v_said := v_said || jsonb_build_array(jsonb_build_array('desfazer', c_flav, r2 ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1c2 o *desfaz*: "Desfeito: o pedido de Flávio sai; o serviço fica para …"',
      r2 ->> 'ok' = 'true' and r2 ->> 'texto' like 'Desfeito: o pedido de Flávio sai; o serviço fica para %.', r2::text);
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Não posso terça, pode ser sexta?', 'data', 'sexta', '2026-10-31 10:00');
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1c3 o dia pedido: "Flávio pediu sex 06/11: remarquei para …"',
      r ->> 'efeito' = 'replanejou' and r ->> 'texto' like 'Flávio pediu sex 06/11: remarquei para %. *desfaz Flávio* volta como estava.',
      r::text);
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1d. O acesso e o *desfaz* dele ──
  begin
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'A chave fica com o marinheiro, vaga 12', 'acesso', null, '2026-10-31 10:00');
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, r ->> 'texto'));
    v_res := pg_temp.igual(v_res, 'A1d1 o acesso: "Anotei o acesso que Flávio disse: "…"." (o que ele disse fica como escreveu)',
      (select a.texto from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid),
      'Anotei o acesso que Flávio disse: "A chave fica com o marinheiro, vaga 12".');
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, c_dono, 'dono', date '2026-10-31', pg_temp.em('2026-10-31 11:00'));
    v_said := v_said || jsonb_build_array(jsonb_build_array('desfazer', c_flav, r2 ->> 'texto'));
    v_res := pg_temp.igual(v_res, 'A1d2 o *desfaz*: "Desfeito: o acesso que Flávio disse saiu da OS."', r2 ->> 'texto',
                           'Desfeito: o acesso que Flávio disse saiu da OS.');
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1e. O opt-out (a ação e o que não se desfaz) ──
  begin
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Não quero mais receber essas mensagens', 'opt_out', null, '2026-10-31 10:00');
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1e1 o opt-out: "Flávio pediu para não receber mais mensagens: não mando mais nada." (a ação e o texto)',
      r ->> 'efeito' = 'opt_out' and r ->> 'texto' = 'Flávio pediu para não receber mais mensagens: não mando mais nada.'
      and (select a.texto from public.agenda_acoes a where a.id = (r ->> 'acao_id')::uuid) = r ->> 'texto', r::text);
    x := public._agenda_desfazer_cliente((r ->> 'acao_id')::uuid, c_dono, 'whatsapp', date '2026-10-31', pg_temp.em('2026-10-31 10:30'));
    v_said := v_said || pg_temp.textos('desfazer', c_flav, x);
    v_res := pg_temp.igual(v_res, 'A1e2 o opt-out não se desfaz: "… só o cliente pode pedir para voltar."', x ->> 'texto',
      'O pedido de Flávio para não receber mensagens não se desfaz por aqui: só o cliente pode pedir para voltar.');
    -- o cartão: a mensagem viva recusada pelo opt-out
    x := public._agenda_cliente_da_os(c_flav, date '2026-10-31');
    v_said := v_said || pg_temp.textos('cartão', c_flav, x);
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1f. A resposta que vai ao dono (a pergunta sem "ele") ──
  begin
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Pode ser dia 32?', 'data', 'dia 32', '2026-10-31 10:00');
    v_t := (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid);
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1f1 o dia que não entendi: "…: não entendi o dia pedido." (a pergunta e o texto)',
      r ->> 'efeito' = 'ao_dono' and v_t like 'Flávio respondeu "Pode ser dia 32?" à confirmação de ter 03/11: não entendi o dia pedido.%'
      and r ->> 'texto' = v_t, v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Pode ser hoje?', 'data', 'hoje', '2026-10-31 10:00');
    v_t := (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid);
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, v_t));
    v_res := pg_temp.ok(v_res, 'A1f2 o dia passado ou de hoje: "…: o dia pedido já passou ou é hoje."',
      v_t like '%: o dia pedido já passou ou é hoje.%', v_t);
    r := pg_temp.resp(c_f, 'Hmm, e aí?', 'outro', null, '2026-10-31 10:10');
    v_t := (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid);
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, v_t));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    r := pg_temp.resp(c_f, 'Hmm, e aí?', 'outro', null, '2026-10-31 10:10');
    v_t := (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid);
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, v_t));
    v_res := pg_temp.igual(v_res, 'A1f3 o que não entendi: "…: não entendi o pedido. …"', v_t,
      'Flávio respondeu "Hmm, e aí?" à confirmação de ter 03/11: não entendi o pedido. Não respondi nada; é com você.');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    v_id := pg_temp.enviada(c_cli_luc, c_luc, 'pronto', date '2026-10-30', '2026-10-30 15:30');
    r := pg_temp.resp(c_l, 'Ok', 'acordo', null, '2026-10-30 16:00');
    v_t := (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid);
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_luc, v_t));
    v_res := pg_temp.igual(v_res, 'A1f4 o "ok" ao "ficou pronto": "…: combine a entrega com o cliente. …"', v_t,
      'Lucenira respondeu "Ok" ao "ficou pronto": combine a entrega com o cliente. Não respondi nada; é com você.');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- duas OS do Flávio esperando resposta: ambígua
    v_id := pg_temp.enviada(c_cli_flav, c_flav, 'confirmar', date '2026-11-03', '2026-10-31 09:00', 'primeira');
    v_id2 := pg_temp.enviada(c_cli_flav, c_rob, 'confirmar', date '2026-11-04', '2026-10-31 09:05', 'primeira');
    r := pg_temp.resp(c_f, 'Sim', 'acordo', null, '2026-10-31 10:00');
    v_t := (select q.texto from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid);
    v_said := v_said || jsonb_build_array(jsonb_build_array('resposta', c_flav, v_t));
    v_res := pg_temp.ok(v_res, 'A1f5 duas OS esperando: "… esperando resposta do cliente …" (era "dele")',
      r ->> 'efeito' = 'ambigua' and v_t like '%há 2 serviços esperando resposta do cliente%' and v_t not like '%dele%', v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1g. cliente_avisar: as recusas ──
  begin
    r := pg_temp.prep('Lenine', 'confirmar');
    v_said := v_said || pg_temp.textos('preparar', null, r);
    v_res := pg_temp.igual(v_res, 'A1g1 sem telefone: "Lenine não tem telefone no cadastro: …"', r ->> 'texto',
                           'Lenine não tem telefone no cadastro: não tenho como mandar.');
    r := pg_temp.prep('Giancarlo', 'pode_atrasar');
    v_said := v_said || pg_temp.textos('preparar', c_gia, r);
    v_res := pg_temp.igual(v_res, 'A1g2 sem data dita: "Não há data dita para Giancarlo: … Se você disse uma data, me conte …"', r ->> 'texto',
      'Não há data dita para Giancarlo: sem data dita, não há atraso a avisar. Se você disse uma data, me conte ("falei pro Giancarlo que é dia 3").');
    r := pg_temp.prep('Nelson', 'material_chegou');
    v_said := v_said || pg_temp.textos('preparar', c_nel, r);
    v_res := pg_temp.igual(v_res, 'A1g3 o material: "O material de Nelson ainda não está todo na mão (…): …"', r ->> 'texto',
      'O material de Nelson ainda não está todo na mão (tem peça sem previsão de chegada): não digo data firme ao cliente. Quando chegar, me avise e eu preparo.');
    r := pg_temp.prep('Vanderlei', 'andamento');
    v_said := v_said || pg_temp.textos('preparar', c_ven, r);
    v_res := pg_temp.igual(v_res, 'A1g4 sem andamento: "O serviço de Vanderlei ainda não começou …"', r ->> 'texto',
      'O serviço de Vanderlei ainda não começou (ou não tem o fim no plano): não há andamento a contar.');
    r := pg_temp.prep('Nelson', 'pronto');
    v_said := v_said || pg_temp.textos('preparar', c_nel, r);
    r2 := pg_temp.prep('OS-00121', 'pronto');
    v_said := v_said || pg_temp.textos('preparar', c_rob, r2);
    v_res := pg_temp.ok(v_res, 'A1g5 não concluída e já entregue: "O serviço de Nelson ainda não está concluído.", "O serviço de Robson já foi entregue."',
      r ->> 'texto' = 'O serviço de Nelson ainda não está concluído.' and r2 ->> 'texto' = 'O serviço de Robson já foi entregue.',
      r::text || ' ' || r2::text);
    -- o Flávio ouviu ter 03 a qua 04/11 e o plano cabe: sem risco
    perform public._agenda_cliente_gravar_prometido(c_flav, 'firme', date '2026-11-03', date '2026-11-04', 'dono', null,
                                                    pg_temp.em('2026-10-29 10:00'), 'teste A1g');
    r := pg_temp.prep('Flávio', 'pode_atrasar');
    v_said := v_said || pg_temp.textos('preparar', c_flav, r);
    v_res := pg_temp.igual(v_res, 'A1g6 sem risco: "O plano de Flávio ainda cabe na data dita (qua 04/11): …" (era "do Flávio … que ele ouviu")',
      r ->> 'texto', 'O plano de Flávio ainda cabe na data dita (qua 04/11): não há atraso a avisar.');
    -- a data dita que passou (o Nelson ouviu qui 29/10)
    update public.os_planejamento set prometido_de = date '2026-10-29', prometido_ate = date '2026-10-29',
                                      prometido_original_ate = date '2026-10-29'
     where service_order_id = c_nel;
    r := pg_temp.prep('Nelson', 'pode_atrasar');
    v_said := v_said || pg_temp.textos('preparar', c_nel, r);
    v_res := pg_temp.igual(v_res, 'A1g7 a data dita que passou: "A data que Nelson ouviu (qui 29/10) já passou: …"', r ->> 'texto',
      'A data que Nelson ouviu (qui 29/10) já passou: um aviso escrito agora chega depois dela. Recomendo você ligar.');
    -- o opt-out (o Kalmar, pela OS)
    r := pg_temp.prep('OS-00032', 'confirmar');
    v_said := v_said || pg_temp.textos('preparar', null, r);
    v_res := pg_temp.igual(v_res, 'A1g8 o opt-out: "Kalmar pediu para não receber mensagens: não mando."', r ->> 'texto',
                           'Kalmar pediu para não receber mensagens: não mando.');
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1h. A decisão da data que passou (a pergunta sem mensagem) ──
  begin
    update public.os_planejamento set prometido_de = date '2026-10-29', prometido_ate = date '2026-10-29',
                                      prometido_original_ate = date '2026-10-29'
     where service_order_id = c_nel;
    r := pg_temp.vig('2026-10-30 10:00');
    v_p := (select q.id from public.agenda_perguntas q where q.chave = 'cliente_aviso:' || c_nel || ':2026-10-29');
    r := public.agenda_decidir(v_p, 2::smallint, c_dono, 'whatsapp', null, date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
    v_said := v_said || jsonb_build_array(jsonb_build_array('decidir', c_nel, r ->> 'texto'));
    v_res := pg_temp.igual(v_res, 'A1h1 a opção 2 sem aviso escrito: "… para Nelson: a data dita já passou …" (pelo ralo, sem recriar a decisão)',
      r ->> 'texto', 'Não há aviso escrito para mandar para Nelson: a data dita já passou e o aviso chegaria depois dela. Recomendo você ligar.');
    x := public._agenda_cliente_da_os(c_nel, date '2026-10-30');
    v_said := v_said || pg_temp.textos('cartão', c_nel, x);
    v_res := pg_temp.ok(v_res, 'A1h2 o cartão: o risco termina em " A data dita já passou."',
      x #>> '{prometido,risco_texto}' like '% A data dita já passou.', x #>> '{prometido,risco_texto}');
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1i. O foco clientes: o que foi dito e o que eu teria feito em teste ──
  begin
    perform set_config('agenda.agora', pg_temp.em('2026-10-30 10:00')::text, true);
    r := public._agenda_ver_clientes(c_nel, date '2026-10-30');
    v_said := v_said || jsonb_build_array(jsonb_build_array('foco', c_nel, r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1i1 o foco do Nelson: "O que foi dito ao cliente: qui 05/11 (data firme, …)."',
      r ->> 'texto' like E'Mensagens ao cliente — Nelson (OS-00112):\nO que foi dito ao cliente: qui 05/11 (data firme, %', r ->> 'texto');
    r := public._agenda_ver_clientes(c_gia, date '2026-10-30');
    v_said := v_said || jsonb_build_array(jsonb_build_array('foco', c_gia, r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1i2 sem nada dito: "O que foi dito ao cliente: nada ainda."',
      r ->> 'texto' like '%O que foi dito ao cliente: nada ainda.%', r ->> 'texto');
    -- em teste: a resposta do opt-out registrada na sombra ("eu teria parado as mensagens")
    perform pg_temp.ligar('sombra');
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, base,
                                                 enviar_em, valida_ate, aprovacao, estado, dedupe_key, criada_em)
    values (c_cli_nel, c_nel, 'confirmar', 'primeira', 'rodada', date '2026-11-05', 'sombra', 'mensagem de teste (AG6P7)',
            jsonb_build_object('dia_alvo', '2026-11-05'), pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 18:00'), 'livre',
            'registrada', 'agenda-cliente:teste:sombra-p7', pg_temp.em('2026-10-30 08:00'));
    r2 := pg_temp.resp(c_n, 'Não quero mais receber', 'opt_out', null, '2026-10-30 09:30');
    r := public._agenda_ver_clientes(c_nel, date '2026-10-30');
    perform set_config('agenda.agora', '', true);
    v_said := v_said || jsonb_build_array(jsonb_build_array('foco', c_nel, r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'A1i3 em teste: "• Em teste: Nelson respondeu "…" …: eu teria parado as mensagens" (sem artigo, sem "a ele")',
      r2 ->> 'efeito' = 'sombra'
      and r ->> 'texto' like E'%\n• Em teste: Nelson respondeu "Não quero mais receber" à confirmação de qui 05/11: eu teria parado as mensagens%'
      and r ->> 'texto' not like '%a ele%', r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'A1i4 o que eu teria feito: "eu teria parado as mensagens" (o resto igual)',
      public._agenda_cliente_teria_feito('opt_out', null) = 'eu teria parado as mensagens'
      and public._agenda_cliente_teria_feito('confirma', date '2026-11-03') = 'eu teria confirmado ter 03/11'
      and public._agenda_cliente_teria_feito('outro', null) = 'eu teria passado a você', null);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A1j. O botão "Pedir confirmação" ──
  begin
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._pedir_confirmacao(c_flav, c_dono, pg_temp.em('2026-10-30 10:00'));
    v_said := v_said || pg_temp.textos('botão', c_flav, r - 'mensagem');
    v_res := pg_temp.igual(v_res, 'A1j1 pela agenda: "Pedido de confirmação na fila para Flávio. Quando a resposta for SIM, a OS fica confirmada."',
      r ->> 'message', 'Pedido de confirmação na fila para Flávio. Quando a resposta for SIM, a OS fica confirmada.');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- o caminho antigo (a mensagem ao cliente desligada, como antes da Fase 5)
    perform pg_temp.ligar('desligado');
    perform set_config('agenda_teste.hoje', '2026-10-30', true);
    r := public._pedir_confirmacao(c_flav, c_dono, pg_temp.em('2026-10-30 10:00'));
    v_said := v_said || pg_temp.textos('botão', c_flav, r - 'mensagem');
    v_res := pg_temp.ok(v_res, 'A1j2 o caminho antigo: "Pedido de confirmação enviado a … Quando a resposta for SIM, a OS fica confirmada."',
      r ->> 'message' like 'Pedido de confirmação enviado a %. Quando a resposta for SIM, a OS fica confirmada.'
      or r ->> 'message' = 'Mensagem na fila (modo de teste: vai para o número de teste).', r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A2. Os 2 textos ao cliente (§6.1) ──
  v_res := pg_temp.igual(v_res, 'A2a a forma fim com n = 1 (o Vanderlei ouviu ter 03 a qua 04/11; o fim novo é qui 05/11): "… vai terminar um dia depois do previsto: …"',
    public._agenda_cliente_texto('pode_atrasar', 'remarcado', c_ven,
      '{"primeira": false, "forma": "fim", "dito_de": "2026-11-03", "dito_ate": "2026-11-04", "dia": "2026-11-03", "fim": "2026-11-05"}'::jsonb,
      date '2026-10-30'),
    'Vanderlei, o serviço no Mar Azul vai terminar um dia depois do previsto: agora fica de terça (03/11) até quinta (05/11). Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.');
  v_res := pg_temp.igual(v_res, 'A2b a forma fim com n = 3 (o fim novo é seg 09/11: qui 05, sex 06 e seg 09 são dias úteis): "… vai terminar 3 dias depois do previsto: …"',
    public._agenda_cliente_texto('pode_atrasar', 'remarcado', c_ven,
      '{"primeira": false, "forma": "fim", "dito_de": "2026-11-03", "dito_ate": "2026-11-04", "dia": "2026-11-03", "fim": "2026-11-09"}'::jsonb,
      date '2026-10-30'),
    'Vanderlei, o serviço no Mar Azul vai terminar 3 dias depois do previsto: agora fica de terça (03/11) até segunda (09/11). Desculpe pela mudança. Pode ser? Responda SIM ou me diga outro dia.');
  begin
    v_t := public._agenda_cliente_texto('pode_atrasar', 'remarcado', c_ven,
      '{"primeira": false, "forma": "fim", "dito_de": "2026-11-03", "dito_ate": "2026-11-05", "dia": "2026-11-03", "fim": "2026-11-05"}'::jsonb,
      date '2026-10-30');
  exception when sqlstate '22023' then
    v_t := 'erro 22023: ' || sqlerrm;
  end;
  v_res := pg_temp.igual(v_res, 'A2c o fim que não passa do dia dito (n = 0) não vira texto: 22023, como todo dado que falta', v_t,
    'erro 22023: Falta o fim novo depois do dia dito para a mensagem pode_atrasar ao cliente.');
  begin
    -- pela rodada: o Nelson (2 críticos sem previsão, o painel em 11/11) recebe o aviso sem data
    perform pg_temp.ligar();
    perform pg_temp.vig('2026-10-30 17:00');
    perform pg_temp.vig('2026-10-31 09:15');
    v_t := (select m.texto from public.agenda_cliente_mensagens m
             where m.service_order_id = c_nel and m.tipo = 'pode_atrasar' and m.variante = 'peca_sem_data');
    v_res := pg_temp.igual(v_res, 'A2d o aviso "peça sem data" pela rodada, sem a repetição', v_t,
      'Nelson, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então o serviço no seu veleiro, que estava para quinta (05/11), vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.');
    -- a mesma mensagem, registrada com o texto de antes (como ficaria uma registrada antes desta migration) e ainda não
    -- enviada: o risco da §9. A mensagem não muda depois de gravada: a de agora sai do caminho e a cópia entra com o texto velho
    v_id2 := (select m.id from public.agenda_cliente_mensagens m
               where m.service_order_id = c_nel and m.tipo = 'pode_atrasar' and m.variante = 'peca_sem_data');
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'segurada' where id = v_id2;
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de, faixa_ate,
                                                 prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao, estado,
                                                 dedupe_key, criada_em)
    select m.client_id, m.service_order_id, m.tipo, m.variante, m.origem, m.dia_alvo, m.faixa_de, m.faixa_ate, m.prometido_tipo,
           m.modo, 'Nelson, quero te avisar com antecedência: ainda faltam peças do serviço no seu veleiro sem data de chegada, então o serviço no seu veleiro, que estava para quinta (05/11), vai atrasar. Te digo a nova data assim que elas chegarem. Se isso atrapalhar algum plano seu, me diga.',
           m.base, m.enviar_em, m.valida_ate, 'livre', 'registrada', m.dedupe_key || ':antes-do-p7', m.criada_em
      from public.agenda_cliente_mensagens m where m.id = v_id2
    returning id into v_id;
    v_res := pg_temp.igual(v_res, 'A2e o risco da §9: o aviso registrado com o texto de antes e não enviado sai recusado como "desatualizada" (a regra não muda)',
      public._agenda_cliente_revalidar(v_id, pg_temp.em('2026-10-31 09:30')), 'desatualizada');
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- pelo dono, a data firme com o mesmo início (C2e): o Vanderlei ouviu ter 03 a qua 04/11
    perform pg_temp.ligar();
    update public.os_planejamento set prometido_tipo = 'firme', prometido_de = date '2026-11-03', prometido_ate = date '2026-11-04',
           prometido_original_ate = date '2026-11-04', prometido_fonte = 'dono', prometido_em = now()
     where service_order_id = c_ven;
    r := pg_temp.prep('OS-00069', 'pode_atrasar', '2026-10-30 10:00', true);
    v_said := v_said || pg_temp.textos('preparar', c_ven, r);
    v_res := pg_temp.ok(v_res, 'A2f cliente_avisar firme: "Pronto para Vanderlei, sai agora: "… vai terminar um dia depois do previsto: …""',
      r ->> 'texto' like 'Pronto para Vanderlei, sai agora: "Olá, Vanderlei! Aqui é o Gustavo, da HBR Marine Solutions. O serviço no Mar Azul vai terminar um dia depois do previsto: agora fica de terça (03/11) até quinta (05/11).%',
      r::text);
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── A3. A rodada inteira (ligada e em teste) e a varredura ──
  begin
    perform pg_temp.ligar();
    update public.agenda_config set cliente_aprovacao_dias = 3 where id;
    perform pg_temp.vig('2026-10-30 10:00');
    perform pg_temp.vig('2026-10-30 17:00');
    perform pg_temp.vig('2026-10-31 09:15');
    v_said := v_said || pg_temp.textos('fechamento', null, public._agenda_cliente_fechamento(date '2026-10-30'));
    perform set_config('agenda.agora', pg_temp.em('2026-10-31 09:30')::text, true);
    v_said := v_said || jsonb_build_array(jsonb_build_array('foco', null, public._agenda_ver_clientes(null, date '2026-10-31') ->> 'texto'));
    for v_id in select so.id from public.service_orders so where so.client_id is not null and so.status <> 'cancelled' loop
      v_said := v_said || pg_temp.textos('cartão', v_id, public._agenda_cliente_da_os(v_id, date '2026-10-31'));
      v_said := v_said || jsonb_build_array(jsonb_build_array('foco', v_id, public._agenda_ver_clientes(v_id, date '2026-10-31') ->> 'texto'));
    end loop;
    perform set_config('agenda.agora', '', true);
    r := public.agenda_cliente_decidir_dito(c_dono, 'segura', null, 'whatsapp', date '2026-10-31', pg_temp.em('2026-10-31 09:40'));
    v_said := v_said || jsonb_build_array(jsonb_build_array('segura', null, r ->> 'texto'));
    for v_t in select unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                   'pronto', 'pronto_lembrete', 'pos_servico']) loop
      for v_id in select so.id from public.service_orders so where so.client_id is not null and so.status <> 'cancelled'
                     and so.service_order_number like 'OS-%' loop
        begin
          r := public.agenda_cliente_preparar(c_dono, (select so.service_order_number from public.service_orders so where so.id = v_id),
                                              v_t, false, 'avisa o cliente', date '2026-10-31', pg_temp.em('2026-10-31 10:00'));
          v_said := v_said || pg_temp.textos('preparar', v_id, r);
        exception when others then null;
        end;
      end loop;
    end loop;
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.ligar('sombra');
    perform pg_temp.vig('2026-10-30 10:00');
    perform pg_temp.vig('2026-10-30 17:00');
    perform set_config('agenda.agora', pg_temp.em('2026-10-30 17:30')::text, true);
    v_said := v_said || jsonb_build_array(jsonb_build_array('foco', null, public._agenda_ver_clientes(null, date '2026-10-30') ->> 'texto'));
    perform set_config('agenda.agora', '', true);
    v_said := v_said || pg_temp.gravadas();
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  v_ruins := '';
  for e in select value from jsonb_array_elements(v_said) loop
    v_t := pg_temp.achado(e ->> 2, v_nomes);
    if v_t is not null then
      v_ruins := v_ruins || format(E'\n[%s] %s: %s', e ->> 0, v_t, left(e ->> 2, 300));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, format('A3a nenhum "O/ao/do <nome>", "ele" nem "a ele" nas %s saídas ao dono (respostas, ações, perguntas, recusas, foco, cartão, botão, fechamento, *segura*)',
                                    jsonb_array_length(v_said)),
                      v_ruins = '' and jsonb_array_length(v_said) > 200, nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'A3b o controle: a varredura acha o texto de antes (o artigo, o "ele", o "a ele") e deixa passar o que está entre aspas e o nome sem artigo',
    pg_temp.achado('O Flávio confirmou ter 03/11.', v_nomes) is not null
    and pg_temp.achado('Mando ao Nelson agora.', v_nomes) is not null
    and pg_temp.achado('A confirmação do Flávio sai.', v_nomes) is not null
    and pg_temp.achado('não mando mais nada a ele.', v_nomes) is not null
    and pg_temp.achado('Ele confirmou ter 03/11.', v_nomes) is not null
    and pg_temp.achado('Pronto para Nelson, sai agora: "O serviço do Nelson e ele"', v_nomes) is null
    and pg_temp.achado('Flávio confirmou ter 03/11; o barco dele; telefone.', v_nomes) is null
    and 'Flávio' = any (v_nomes) and 'Nelson' = any (v_nomes), array_to_string(v_nomes, ', '));

  perform pg_temp.gravar(v_res);
end
$a$;

-- ── A4. As cópias e as portas ───────────────────────────────────────────────────────────────────────────
do $a4$
declare
  v_c2  text := current_setting('agenda_teste.mig_correcao_rodada_fase5', true);
  v_c1  text := current_setting('agenda_teste.mig_correcao_resposta_fase5', true);
  v_res5 text := current_setting('agenda_teste.mig_respostas_fase5', true);
  v_lei text := current_setting('agenda_teste.mig_leituras_fase5', true);
  r record;
  v_src text;
  v_velho text[];
  v_novo text[];
  v_ruins text := '';
begin
  if coalesce(v_c2, '') = '' or coalesce(v_c1, '') = '' or coalesce(v_res5, '') = '' or coalesce(v_lei, '') = '' then
    insert into _resultado values ('A4 (as migrations da Fase 5 como texto)', true, 'PULADO: sem agenda_teste.mig_* (rode pela bancada)');
  else
    for r in
      select * from (values
        ('_agenda_cliente_sem_artigo', 'public._agenda_cliente_sem_artigo(text, uuid)', 'c2'),
        ('_agenda_cliente_texto', 'public._agenda_cliente_texto(text, text, uuid, jsonb, date)', 'c2'),
        ('agenda_cliente_preparar', 'public.agenda_cliente_preparar(uuid, text, text, boolean, text, date, timestamptz)', 'c2'),
        ('agenda_resposta_do_cliente', 'public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)', 'c2'),
        ('_agenda_cliente_da_os', 'public._agenda_cliente_da_os(uuid, date)', 'c2'),
        ('_agenda_cliente_confirmar_dia', 'public._agenda_cliente_confirmar_dia(uuid, uuid, text, date, timestamptz)', 'p4'),
        ('_agenda_cliente_anotar_acesso', 'public._agenda_cliente_anotar_acesso(uuid, uuid, text, date, timestamptz)', 'p4'),
        ('_agenda_cliente_pedido_de_dia', 'public._agenda_cliente_pedido_de_dia(uuid, uuid, daterange, date, text, text, date, timestamptz)', 'p4'),
        ('_agenda_desfazer_cliente', 'public._agenda_desfazer_cliente(uuid, uuid, text, date, timestamptz)', 'p4'),
        ('_agenda_ver_clientes', 'public._agenda_ver_clientes(uuid, date)', 'p5'),
        ('_agenda_cliente_teria_feito', 'public._agenda_cliente_teria_feito(text, date)', 'p5'),
        ('_pedir_confirmacao', 'public._pedir_confirmacao(uuid, uuid, timestamptz)', 'c1')
      ) t(nome, assinatura, fonte)
    loop
      v_src := pg_temp.corpo(case r.fonte when 'c2' then v_c2 when 'c1' then v_c1 when 'p4' then v_res5 else v_lei end, r.nome);
      v_velho := pg_temp.sem_f6(v_src);
      v_novo := pg_temp.sem_f6((select p.prosrc from pg_proc p where p.oid = r.assinatura::regprocedure));
      insert into _resultado select format('A4a a cópia de %s (de %s) só acrescenta os blocos "-- FASE 6: (P7)"', r.nome,
                                            case r.fonte when 'c2' then '20261028100800' when 'c1' then '20261028100700'
                                                         when 'p4' then '20261028100400' else '20261028100500' end),
        v_novo = v_velho and cardinality(v_velho) > 5
        and (select count(*) from regexp_matches(p.prosrc, '-- FASE 6: \(P7\)', 'g')) >= 1
        and (select count(*) from regexp_matches(v_src, '-- FASE 6:', 'g')) = 0,
        format('linhas %s × %s', array_length(v_novo, 1), array_length(v_velho, 1))
      from pg_proc p where p.oid = r.assinatura::regprocedure;
    end loop;
  end if;
  -- as portas de antes: as internas para ninguém (nem o service_role); as leituras para authenticated e service_role (nunca
  -- anon); a resposta só para o service_role; nenhuma virou security definer nem perdeu o search_path
  for r in select p.oid::regprocedure::text as f, p.proname, p.prosecdef, p.proconfig
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('_agenda_cliente_sem_artigo', '_agenda_cliente_texto', 'agenda_cliente_preparar',
                    'agenda_resposta_do_cliente', '_agenda_cliente_da_os', '_agenda_cliente_confirmar_dia', '_agenda_cliente_anotar_acesso',
                    '_agenda_cliente_pedido_de_dia', '_agenda_desfazer_cliente', '_agenda_ver_clientes', '_agenda_cliente_teria_feito',
                    '_pedir_confirmacao') loop
    if has_function_privilege('anon', r.f, 'execute')
       or (r.proname in ('_agenda_cliente_sem_artigo', '_agenda_cliente_da_os', '_agenda_cliente_confirmar_dia', '_agenda_cliente_anotar_acesso',
                         '_agenda_cliente_pedido_de_dia', '_agenda_desfazer_cliente', '_pedir_confirmacao')
           and (has_function_privilege('authenticated', r.f, 'execute') or has_function_privilege('service_role', r.f, 'execute')))
       or (r.proname in ('_agenda_cliente_texto', 'agenda_cliente_preparar', '_agenda_ver_clientes', '_agenda_cliente_teria_feito')
           and not (has_function_privilege('authenticated', r.f, 'execute') and has_function_privilege('service_role', r.f, 'execute')))
       or (r.proname = 'agenda_resposta_do_cliente'
           and (has_function_privilege('authenticated', r.f, 'execute') or not has_function_privilege('service_role', r.f, 'execute')))
       or r.prosecdef <> (r.proname in ('agenda_cliente_preparar', 'agenda_resposta_do_cliente', '_agenda_ver_clientes', '_pedir_confirmacao'))
       or coalesce(array_to_string(r.proconfig, ','), '') not like '%search_path=%' then
      v_ruins := v_ruins || r.f || ' ';
    end if;
  end loop;
  insert into _resultado values ('A4b as portas e a segurança de antes (internas para ninguém; leituras sem anon; a resposta só service_role; definer igual; search_path fixo)',
                                 v_ruins = '', nullif(v_ruins, ''));
end
$a4$;

-- ── A5. A correção C2 (20261029100950): o texto 6 ──────────────────────────────────────────────────────────
-- O *cliente_avisar* firme com a forma fim cujo fim novo não passa do dia que o cliente ouviu (n < 1): o dono recebe "Não
-- preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar.", e não o texto técnico do erro.
do $a5$
declare
  v_res jsonb := '[]'::jsonb;
  c_ven constant uuid := '05000000-0000-4000-8000-000000000069';
  r     jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('A5 a correção C2 do acabamento (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  -- a fixture-fase6 já foi carregada pelo bloco de cima (fora das subtransações); só a carrega quem roda este bloco sozinho
  if not exists (select 1 from public.service_orders so where so.id = c_ven) then
    execute current_setting('agenda_teste.fase6');
  end if;
  begin
    -- o Vanderlei ouviu ter 03 a qui 05/11 (firme), e o fim novo é qui 05/11: não passa do dia que ele ouviu (n = 0)
    perform pg_temp.ligar();
    update public.os_planejamento set prometido_tipo = 'firme', prometido_de = date '2026-11-03', prometido_ate = date '2026-11-05',
           prometido_original_ate = date '2026-11-05', prometido_fonte = 'dono', prometido_em = now()
     where service_order_id = c_ven;
    r := pg_temp.prep('OS-00069', 'pode_atrasar', '2026-10-30 10:00', true);
    v_res := pg_temp.ok(v_res, 'A5a (C2, texto 6) a forma fim sem atraso para avisar: "Não preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar." (sem o texto técnico do 22023), e nada registrado',
      r ->> 'ok' = 'false'
      and r ->> 'texto' = 'Não preparei: o fim novo não passa do dia que o cliente ouviu, então não há atraso para avisar.'
      and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_ven and m.tipo = 'pode_atrasar'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$a5$;
select teste, ok, detalhe from _resultado order by teste;

rollback;
