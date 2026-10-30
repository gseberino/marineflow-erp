-- Prova da correção de 29/10 da Agenda de Produção, pacote P4 (migration 20261030100300): o aviso do gestor ao dono.
-- bancada: depende de 20261030100300
--
-- O defeito (auditoria de 29/10, leitor "entrega"): a publicação da semana (qui 16:30) não gerava mensagem nenhuma; o
-- fechamento das 17:30 não tinha vaga para a agenda com 3 itens do secretário; as perguntas que destravam o plano nunca
-- contavam como mostradas; o *desfaz semana* venceria antes de o dono saber da publicação.
--
-- O cenário de HOJE é a fixture-2310.sql que a bancada sempre carrega com os modos ligados e a vigia de qui 29/10 às 16:30:
-- ela publica o que produção publicou (só a reserva do Lenine) e pergunta a peça do Lenine e os seus dias em campo. O dono
-- (Gustavo) com o assistente no WhatsApp. Por cima dela:
--   H  hoje: às 16:45 o aviso diz o que mudou (a publicação, com quem vai e os dias), o que ficou de fora e por quê, e as
--      perguntas da rodada de aprontar; vai à fila (source agenda-dono, a chave da rodada, o telefone do dono); a ação fica
--      contada (o fechamento das 17:30 não repete a semana); quando a fila manda, a ação conta na hora do envio, o prazo do
--      *desfaz semana* começa ali e as perguntas contam como mostradas; o tique seguinte não tem nada novo
--   I  idempotência: a mesma rodada não entra duas vezes; outra rodada com as mesmas mudanças não as conta de novo; a 2ª
--      trava (o gatilho da fila) recusa a linha por fora, a de um aviso já decidido, outro texto, outro telefone; a linha não
--      muda de texto
--   J  a janela: antes de 09:30, depois de 19:30 e no domingo o que mudou espera e sai junto na abertura; sábado sai; as
--      tentativas que cabem até 19:30; a linha que ficou na fila depois da janela falha e as mudanças voltam a "por contar";
--      a recusa do worker também devolve; a nova tentativa fora da janela falha; a 2ª trava recusa a linha que passaria
--   T  o teto e o modo: o 2º aviso do dia com teto 1 espera o dia seguinte; teto 0 = desligado (e o que estava na fila não
--      sai); fora de ligado nada; sem o dono no WhatsApp nada
--   Q  as perguntas uma vez por dia: o 2º aviso do dia não as repete; no dia seguinte voltam; o aviso que não saiu não conta
--   D  o gatilho da ação: o prazo do *desfaz* só ADIANTA pelo aviso (direto, ou para trás, recusa)
--   N  o que não muda: fora de ligado nada é gravado; as peças não gravam nada; o acorde continua contado à parte
-- Sempre (com ou sem as fixtures):
--   K  a cópia: _agenda_acoes_so_desfaz só acrescenta o bloco "-- CORREÇÃO 29/10 (P4):" (× 20261026100000)
--   P  portas: as 3 RPCs só o service_role; as peças de dentro, ninguém; a tabela só leitura TO authenticated; os gatilhos
--   C  os parâmetros novos (09:30, 19:30, 3, 2400) e os CHECKs; 'aviso' nas listas fechadas
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_correcao_2910_p4.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só K, P e C rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai (a fila da transação
--   desfeita nunca é lida pelo worker).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_visto text, p_esperado text) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, p_visto is not distinct from p_esperado,
           case when p_visto is distinct from p_esperado then 'veio: ' || coalesce(p_visto, '(null)') end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia, modo_leitura = 'ligado' where id
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
-- O dono com o assistente no WhatsApp (o 1º admin ativo; a regra de donoDoWhatsApp).
create function pg_temp.dono() returns void language sql as $f$
  update public.app_users set ai_whatsapp_enabled = true, phone_normalized = '5547900000210'
   where id = 'aa000000-0000-4000-8000-000000000001'
$f$;
-- O texto como o montador (_shared/agenda/aviso-do-gestor.ts) o junta quando cabe no teto: o cabeçalho, "• " + cada
-- mudança, o de fora, o rodapé, a linha em branco e as perguntas.
create function pg_temp.montar(p jsonb) returns text language sql immutable as $f$
  select (p ->> 'cabecalho')
         || (select string_agg(E'\n• ' || (m ->> 'texto'), '' order by o) from jsonb_array_elements(p -> 'mudancas') with ordinality t(m, o))
         || coalesce(E'\n' || (p ->> 'fora'), '') || coalesce(E'\n' || (p ->> 'rodape'), '')
         || coalesce(E'\n\n' || (p #>> '{perguntas,texto}'), '')
$f$;
create function pg_temp.ids(p jsonb) returns uuid[] language sql immutable as $f$
  select array(select x::uuid from jsonb_array_elements(p -> 'mudancas') m, jsonb_array_elements_text(m -> 'acao_ids') x)
$f$;
create function pg_temp.pids(p jsonb) returns uuid[] language sql immutable as $f$
  select array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p -> 'perguntas') = 'object'
                                                                  then p #> '{perguntas,pergunta_ids}' else '[]'::jsonb end) x)
$f$;
-- Um tique do aviso como o task-automations faz: as peças e, quando é para avisar, o enfileirar com o texto montado.
create function pg_temp.avisar(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
declare
  p jsonb := public.agenda_aviso_pecas(p_dia, pg_temp.em(p_dia, p_hora));
begin
  if not coalesce((p ->> 'avisar')::boolean, false) then
    return p || jsonb_build_object('enfileirou', false);
  end if;
  return public.agenda_aviso_enfileirar(pg_temp.montar(p), pg_temp.ids(p), pg_temp.pids(p), jsonb_typeof(p -> 'perguntas') = 'object',
                                        p_dia, pg_temp.em(p_dia, p_hora))
         || jsonb_build_object('pecas', p);
end $f$;
-- A fila mandou (o worker): as linhas agenda-dono pendentes saem na hora dada.
create function pg_temp.saiu(p_dia date, p_hora text) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(p_dia, p_hora), attempts = attempts + 1
   where source = 'agenda-dono' and status = 'pending'
$f$;
-- Uma mudança da vigia (remanejo) gravada como o motor grava: executada, desfazível pelo prazo da agenda.
create function pg_temp.mover(p_em timestamptz) returns uuid language sql as $f$
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, desfazivel_ate)
  select p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, 'vigia', 'mover', so.id, array[so.id],
         'Vanderlei (OS-00069): de qua 04/11 para qui 05/11.', p_em + (select c.desfazer_validade from public.agenda_config c where c.id)
    from public.service_orders so where so.service_order_number = 'OS-00069'
  returning id
$f$;
-- O erro de um comando: 'ok' ou "<sqlstate>[:<detail>]".
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_det text;
begin
  begin
    execute p_sql;
    raise exception 'desfaz' using errcode = 'P0098';
  exception
    when sqlstate 'P0098' then return 'ok';
    when others then
      get stacked diagnostics v_det = pg_exception_detail;
      return sqlstate || coalesce(':' || nullif(v_det, ''), '');
  end;
end $f$;
-- Uma consulta como um papel: o texto que volta ou "erro <sqlstate>".
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate;
  end;
  reset role;
  return v;
end $f$;

-- O corpo (entre as duas marcas $…$) de p_nome na migration p_mig.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_i int := position('create or replace function public.' || p_nome || '(' in v);
  v_tag text;
begin
  if v_i = 0 then return null; end if;
  v := substr(v, v_i);
  v_tag := substring(v from E'\nas (\\$[a-z_]*\\$)\n');
  v := substr(v, position(E'\nas ' || v_tag in v) + length(E'\nas ' || v_tag));
  return left(v, position(v_tag in v) - 1);
end $f$;
-- As linhas fora dos blocos "-- CORREÇÃO 29/10 (P4): … -- CORREÇÃO 29/10 (P4): fim".
create function pg_temp.sem_blocos(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and ltrim(l) like '-- CORREÇÃO 29/10 (P4):%' and ltrim(l) not like '-- CORREÇÃO 29/10 (P4): fim%' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if ltrim(l) like '-- CORREÇÃO 29/10 (P4): fim%' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- O retrato das tabelas que o aviso poderia tocar (linhas e md5), para provar que nada é gravado.
create function pg_temp.retrato() returns text language plpgsql as $f$
declare
  t text;
  v text := '';
  n bigint;
  h text;
begin
  foreach t in array array['agenda_acoes', 'agenda_perguntas', 'agenda_dono_avisos', 'whatsapp_send_queue'] loop
    execute format('select count(*), md5(coalesce(string_agg(x::text, ''|'' order by x::text), '''')) from public.%I x', t) into n, h;
    v := v || t || ':' || n || ':' || h || ' ';
  end loop;
  return v;
end $f$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $cenarios$
declare
  v_fix   boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000003')
                     and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000074');
  c_hoje   constant date := date '2026-10-29';
  c_sexta  constant date := date '2026-10-30';
  c_fone   constant text := '5547900000210';
  c_lenine constant uuid := '05000000-0000-4000-8000-000000000074';
  c_cab    constant text := 'Agenda — o que eu mudei sozinho:';
  c_rodape constant text := '*agenda plano* mostra tudo.';
  c_pub    constant text := 'Publiquei a semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme: Reserva Lenine '
                            || '(OS-00074): qui 05 a ter 10/11, João os 3 dias, Roberto os 3 dias — se você disser até qua 04/11 se '
                            || 'tem peça a comprar. *desfaz semana* volta como estava.';
  c_fora   constant text := 'Ficaram de fora 10: Giancarlo (sem lugar na equipe); Rodrigo OS-00096 (só com você); Vanderlei, Flávio e '
                            || 'Nelson (material); Kalmar OS-00032, Kalmar OS-00033 e Rodrigo OS-00076 (esperando o cliente); Robson '
                            || '(orçamento que não virou OS); MP (esperando o sinal).';
  c_mover  constant text := 'Vanderlei (OS-00069): de qua 04/11 para qui 05/11. *desfaz Vanderlei* volta como estava.';
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  p       jsonb;
  e       jsonb;
  x       jsonb;
  v_t     text;
  v_t2    text;
  v_acao  uuid;
  v_mov   uuid;
  v_ate   timestamptz;
  v_reg   record;
  v_fila  record;
  v_pids  uuid[];
  v_id    uuid;
begin
  if not v_fix then
    insert into _resultado values ('H–N cenários da correção P4', true,
      'PULADO: sem a fixture-2310 (rode pela bancada)');
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);

  -- ── H. Hoje: a vigia de qui 29/10 às 16:30 publica; o aviso das 16:45 conta ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    r := pg_temp.vigiar(c_hoje, '16:30');
    select a.id, a.desfazivel_ate into v_acao, v_ate from public.agenda_acoes a where a.tipo = 'publicar';
    v_t := (select y ->> 'texto' from jsonb_array_elements(public.agenda_textos_do_fechamento(c_hoje, null) -> 'linhas') y
             where y ->> 'tipo' = 'semana');
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '16:45'));
    v_res := pg_temp.ok(v_res, 'H1 às 16:45 o aviso conta a publicação da semana: o texto do *o que mudou* (quem vai, os dias, *desfaz semana*) e a ação dela',
      (p ->> 'avisar')::boolean and jsonb_array_length(p -> 'mudancas') = 1 and p #>> '{mudancas,0,texto}' = c_pub
      and pg_temp.ids(p) = array[v_acao], p::text);
    v_res := pg_temp.igual(v_res, 'H2 o que ficou de fora e por quê, curto (o porquê numa palavra; o número quando o nome se repete)',
      p ->> 'fora', c_fora);
    v_pids := array(select q.id from public.agenda_perguntas q
                     where q.estado = 'aberta' and q.modo = 'ligado'
                       and ((q.tipo = 'material_conferir' and q.service_order_id = c_lenine) or q.tipo = 'padrao_do_dono')
                     order by q.criada_em, q.id);
    v_res := pg_temp.ok(v_res, 'H3 no fim, as perguntas que destravam: o texto da rodada de aprontar, e as abertas que ele cobre (a peça do Lenine, os seus dias em campo)',
      p #>> '{perguntas,texto}' = public.agenda_aprontar(c_hoje) ->> 'texto'
      and p #>> '{perguntas,texto}' like '%• Lenine (OS-00074): tem peça a comprar?%'
      and p #>> '{perguntas,texto}' like '%• Você: semana que vem fica em campo quais dias?%'
      and cardinality(v_pids) = 2 and pg_temp.pids(p) = v_pids, (p -> 'perguntas')::text);
    v_res := pg_temp.ok(v_res, 'H4 o cabeçalho, o rodapé e o teto do banco; o texto montado cabe (o caso de hoje inteiro)',
      p ->> 'cabecalho' = c_cab and p ->> 'rodape' = c_rodape and (p ->> 'limite')::int = 2400
      and char_length(pg_temp.montar(p)) <= 2400 and p ->> 'rodada' = '2026-10-29T19:45:00+00:00',
      char_length(pg_temp.montar(p))::text);
    e := public.agenda_aviso_enfileirar(pg_temp.montar(p), pg_temp.ids(p), pg_temp.pids(p), true, c_hoje, pg_temp.em(c_hoje, '16:45'));
    select v.* into v_reg from public.agenda_dono_avisos v;
    select q.* into v_fila from public.whatsapp_send_queue q where q.source = 'agenda-dono';
    v_res := pg_temp.ok(v_res, 'H5 vai à fila: source agenda-dono, o telefone do dono, o texto montado, a chave da rodada, prioridade 1, às 16:45, 3 tentativas; o aviso registrado e enfileirado',
      (e ->> 'enfileirou')::boolean and (e ->> 'tentativas')::int = 3
      and (select count(*) from public.whatsapp_send_queue where source = 'agenda-dono') = 1
      and v_fila.phone_normalized = c_fone and v_fila.message = pg_temp.montar(p)
      and v_fila.dedupe_key = 'agenda-dono:aviso:20261029T194500.000000' and v_fila.priority = 1
      and v_fila.scheduled_for = pg_temp.em(c_hoje, '16:45') and v_fila.max_attempts = 3 and v_fila.status = 'pending'
      and v_fila.source_ref_id = v_reg.id and v_reg.fila_id = v_fila.id and v_reg.estado = 'enfileirada'
      and v_reg.rodada = pg_temp.em(c_hoje, '16:45') and v_reg.dia = c_hoje and v_reg.telefone = c_fone and v_reg.com_perguntas
      and v_reg.pergunta_ids = v_pids and v_reg.acao_ids = array[v_acao], e::text || ' | ' || to_jsonb(v_fila)::text);
    -- CORREÇÃO 29/10 (revisão, 20261030100500): o prazo do *desfaz* já conta do enfileirar (sex 30/10 16:45, não mais o da
    -- publicação, sex 16:30): o *desfaz* que o aviso promete vale desde que ele sai (agenda_correcao_2910_revisao.sql, D)
    v_res := pg_temp.ok(v_res, 'H6 a ação fica contada desde já (contada_via aviso, às 16:45); o prazo do *desfaz* conta daqui (sex 30/10 16:45; era o da publicação, sex 16:30)',
      (select contada_via = 'aviso' and contada_em = pg_temp.em(c_hoje, '16:45')
              and desfazivel_ate = case when to_regprocedure('public._agenda_aviso_espera_o_fechamento(timestamptz)') is null
                                        then v_ate else pg_temp.em(c_sexta, '16:45') end
         from public.agenda_acoes where id = v_acao)
      and v_ate = pg_temp.em(c_sexta, '16:30'), v_ate::text);
    v_t2 := (select y ->> 'texto' from jsonb_array_elements(public.agenda_textos_do_fechamento(c_hoje, null) -> 'linhas') y
              where y ->> 'tipo' = 'semana');
    v_res := pg_temp.ok(v_res, 'H7 o fechamento das 17:30 não repete a semana que o aviso já contou (antes do aviso ele tinha a linha "Agenda: publiquei a semana…")',
      v_t like 'Agenda: publiquei a semana de 03 a 06/11%' and v_t2 is null, coalesce(v_t, '(sem)') || ' → ' || coalesce(v_t2, '(sem)'));
    -- a fila manda às 16:50; o tique das 17:00 confere
    perform pg_temp.saiu(c_hoje, '16:50');
    x := public.agenda_aviso_conferir(pg_temp.em(c_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'H8 o que saiu conta na hora do envio (16:50) e o *desfaz semana* vale 24 horas a partir dali (sex 30/10 16:50); o aviso enviado',
      x = '{"enviados": 1, "recusados": 0, "devolvidas": 0}'::jsonb
      and (select contada_via = 'aviso' and contada_em = pg_temp.em(c_hoje, '16:50') and desfazivel_ate = pg_temp.em(c_sexta, '16:50')
             from public.agenda_acoes where id = v_acao)
      and (select estado = 'enviada' and enviada_em = pg_temp.em(c_hoje, '16:50') from public.agenda_dono_avisos),
      x::text || ' | ' || (select to_jsonb(a)::text from (select contada_em, desfazivel_ate from public.agenda_acoes where id = v_acao) a));
    v_res := pg_temp.ok(v_res, 'H9 as perguntas que foram na mensagem contam como mostradas (1 vez, às 16:50, pelo aviso)',
      (select bool_and(q.mostrada_vezes = 1 and q.mostrada_em = pg_temp.em(c_hoje, '16:50') and q.mostrada_via = 'aviso')
         from public.agenda_perguntas q where q.id = any (v_pids))
      and (select count(*) from public.agenda_perguntas q where q.mostrada_vezes > 0 and not (q.id = any (v_pids))) = 0,
      (select string_agg(q.tipo || ' ' || q.mostrada_vezes || ' ' || coalesce(q.mostrada_via, '-'), ', ') from public.agenda_perguntas q));
    v_res := pg_temp.ok(v_res, 'H10 sex 30/10 às 16:40 o *desfaz semana* ainda vale (sem o aviso teria vencido às 16:30, antes de o dono saber)',
      public.agenda_acao_desfazivel('semana', c_sexta, pg_temp.em(c_sexta, '16:40')) ->> 'status' = 'ok'
      and public.agenda_acao_desfazivel('semana', c_sexta, pg_temp.em(c_sexta, '16:55')) ->> 'status' <> 'ok',
      (public.agenda_acao_desfazivel('semana', c_sexta, pg_temp.em(c_sexta, '16:40')))::text);
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '17:00'));
    x := public.agenda_aviso_conferir(pg_temp.em(c_hoje, '17:15'));
    v_res := pg_temp.ok(v_res, 'H11 o tique seguinte não tem nada novo (nada_mudou); conferir de novo não refaz nada',
      p = '{"avisar": false, "motivo": "nada_mudou"}'::jsonb and x = '{"enviados": 0, "recusados": 0, "devolvidas": 0}'::jsonb
      and (select mostrada_vezes from public.agenda_perguntas where id = v_pids[1]) = 1, p::text || ' | ' || x::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── I. Idempotência e a 2ª trava ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '16:45'));
    e := public.agenda_aviso_enfileirar(pg_temp.montar(p), pg_temp.ids(p), pg_temp.pids(p), true, c_hoje, pg_temp.em(c_hoje, '16:45'));
    x := public.agenda_aviso_enfileirar(pg_temp.montar(p), pg_temp.ids(p), pg_temp.pids(p), true, c_hoje, pg_temp.em(c_hoje, '16:45'));
    v_res := pg_temp.ok(v_res, 'I1 a mesma rodada não entra duas vezes (ja_existe): 1 aviso, 1 linha na fila',
      x ->> 'motivo' = 'ja_existe' and x ->> 'id' = e ->> 'id' and not (x ->> 'enfileirou')::boolean
      and (select count(*) from public.agenda_dono_avisos) = 1
      and (select count(*) from public.whatsapp_send_queue where source = 'agenda-dono') = 1, x::text);
    x := public.agenda_aviso_enfileirar(pg_temp.montar(p), pg_temp.ids(p), pg_temp.pids(p), true, c_hoje, pg_temp.em(c_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'I2 outra rodada com as mesmas mudanças (já contadas) não entra (mudou): nada novo na fila',
      x ->> 'motivo' = 'mudou' and (select count(*) from public.agenda_dono_avisos) = 1
      and (select count(*) from public.whatsapp_send_queue where source = 'agenda-dono') = 1, x::text);
    v_id := (e ->> 'id')::uuid;
    v_t := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key)
                                     values (%L, 'Oi, aqui é a agenda.', 'agenda-dono', gen_random_uuid(), 'agenda-dono:por-fora')$q$, c_fone));
    v_t2 := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key)
                                      values (%L, %L, 'agenda-dono', %L, 'agenda-dono:de-novo')$q$, c_fone, pg_temp.montar(p), v_id));
    v_res := pg_temp.ok(v_res, 'I3 a 2ª trava recusa a linha por fora (sem aviso registrado) e a de um aviso já decidido (42501)',
      v_t = '42501' and v_t2 = '42501' and (select count(*) from public.whatsapp_send_queue where source = 'agenda-dono') = 1,
      v_t || ' / ' || v_t2);
    -- um aviso registrado agora (a decisão no meio): outro texto, outro telefone, a chave errada = recusados
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, telefone, enviar_em, dedupe_key)
    values (pg_temp.em(c_hoje, '17:00'), c_hoje, 'Agenda — o que eu mudei sozinho: teste.', array[gen_random_uuid()], c_fone,
            pg_temp.em(c_hoje, '17:00'), 'agenda-dono:aviso:teste')
    returning id into v_id;
    v_t := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key, scheduled_for)
                                     values (%L, 'Outro texto.', 'agenda-dono', %L, 'agenda-dono:aviso:teste', %L)$q$,
                                  c_fone, v_id, pg_temp.em(c_hoje, '17:00')))
             || ' / ' || pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key, scheduled_for)
                                     values ('5547911112222', 'Agenda — o que eu mudei sozinho: teste.', 'agenda-dono', %L, 'agenda-dono:aviso:teste', %L)$q$,
                                  v_id, pg_temp.em(c_hoje, '17:00')))
             || ' / ' || pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key, scheduled_for)
                                     values (%L, 'Agenda — o que eu mudei sozinho: teste.', 'agenda-dono', %L, 'outra-chave', %L)$q$,
                                  c_fone, v_id, pg_temp.em(c_hoje, '17:00')))
             || ' / ' || pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key, scheduled_for)
                                     values (%L, 'Agenda — o que eu mudei sozinho: teste.', 'agenda-dono', %L, 'agenda-dono:aviso:teste', %L)$q$,
                                  c_fone, v_id, pg_temp.em(c_hoje, '17:00')));
    v_res := pg_temp.igual(v_res, 'I4 a 2ª trava: outro texto, outro telefone (não é o do dono) e outra chave = 42501; o certo entra',
      v_t, '42501 / 42501 / 42501 / ok');
    v_t := pg_temp.erro_de(format($q$update public.whatsapp_send_queue set message = 'Trocado.' where id = %L$q$, e ->> 'fila_id'));
    v_res := pg_temp.igual(v_res, 'I5 a linha que entrou não muda de texto (42501)', v_t, '42501');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── J. A janela ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    v_t := concat_ws(' | ',
      (select p2 ->> 'motivo' || ':' || (p2 ->> 'janela') || ':' || (p2 ->> 'pendentes')
         from public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '07:30')) p2),
      (select p2 ->> 'motivo' from public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '09:29')) p2),
      (select (p2 ->> 'avisar') || ':' || (p2 #>> '{mudancas,0,texto}' = c_pub) from public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '09:30')) p2),
      (select (p2 ->> 'avisar') from public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '19:29')) p2),
      (select p2 ->> 'motivo' || ':' || (p2 ->> 'janela') from public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '19:30')) p2),
      (select p2 ->> 'motivo' || ':' || (p2 ->> 'janela') from public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '23:50')) p2),
      (select (p2 ->> 'avisar') from public.agenda_aviso_pecas(date '2026-10-31', pg_temp.em(date '2026-10-31', '10:00')) p2),
      (select p2 ->> 'motivo' || ':' || (p2 ->> 'janela') from public.agenda_aviso_pecas(date '2026-11-01', pg_temp.em(date '2026-11-01', '10:00')) p2));
    v_res := pg_temp.igual(v_res, 'J1 07:30 e 09:29 esperam (fora_da_janela, 1 pendente); 09:30 sai a publicação de ontem junto; até 19:29 sai, 19:30 e de madrugada não; sábado sai; domingo nunca',
      v_t, 'fora_da_janela:janela:1 | fora_da_janela | true:true | true | fora_da_janela:janela | fora_da_janela:janela | true | fora_da_janela:domingo');
    v_res := pg_temp.ok(v_res, 'J2 esperando a janela nada é gravado (nem aviso, nem fila, nem contada)',
      (select count(*) from public.agenda_dono_avisos) = 0 and (select count(*) from public.whatsapp_send_queue where source = 'agenda-dono') = 0
      and (select contada_em is null from public.agenda_acoes where tipo = 'publicar'), null);
    -- as tentativas que cabem até 19:30 (+5 min cada): às 19:20, 2; às 19:28, 1
    e := pg_temp.avisar(c_hoje, '19:20');
    v_t := (e ->> 'tentativas') || '/' || (select max_attempts from public.whatsapp_send_queue where source = 'agenda-dono')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    e := pg_temp.avisar(c_hoje, '19:28');
    v_res := pg_temp.igual(v_res, 'J3 as tentativas da fila (+5 min) ficam antes das 19:30: às 19:20, 2; às 19:28, 1',
      v_t || ' | ' || (e ->> 'tentativas'), '2/2 | 1');
    v_acao := (select id from public.agenda_acoes where tipo = 'publicar');
    -- o worker não mandou até o fim da janela: o tique das 19:45 falha a linha e devolve as mudanças
    x := public.agenda_aviso_conferir(pg_temp.em(c_hoje, '19:45'));
    v_res := pg_temp.ok(v_res, 'J4 a linha que ficou na fila depois da janela falha (o motivo na fila), o aviso fica recusado (janela) e a publicação volta a "por contar"',
      x = '{"enviados": 0, "recusados": 1, "devolvidas": 1}'::jsonb
      and (select status = 'failed' and failed_reason = 'agenda-dono: não saiu dentro da janela' from public.whatsapp_send_queue where source = 'agenda-dono')
      and (select estado = 'recusada' and recusa_motivo = 'janela' and devolvida_em = pg_temp.em(c_hoje, '19:45') from public.agenda_dono_avisos)
      and (select contada_em is null and contada_via is null from public.agenda_acoes where id = v_acao), x::text);
    p := public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '09:30'));
    x := public.agenda_aviso_conferir(pg_temp.em(c_sexta, '09:30'));
    v_res := pg_temp.ok(v_res, 'J5 no dia seguinte, na abertura da janela, a publicação sai de novo (e o devolvido não volta a devolver)',
      (p ->> 'avisar')::boolean and pg_temp.ids(p) = array[v_acao] and x = '{"enviados": 0, "recusados": 0, "devolvidas": 0}'::jsonb,
      p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    e := pg_temp.avisar(c_hoje, '16:45');
    v_acao := (select id from public.agenda_acoes where tipo = 'publicar');
    -- o worker recusou na hora de mandar (recusarNaFila: a linha falha e o aviso fica recusado)
    update public.whatsapp_send_queue set status = 'failed', failed_reason = 'agenda-dono: fora da janela na hora de enviar' where id = (e ->> 'fila_id')::uuid;
    update public.agenda_dono_avisos set estado = 'recusada', recusa_motivo = 'janela' where fila_id = (e ->> 'fila_id')::uuid and estado = 'enfileirada';
    x := public.agenda_aviso_conferir(pg_temp.em(c_hoje, '17:00'));
    e := pg_temp.avisar(c_hoje, '17:00');
    v_res := pg_temp.ok(v_res, 'J6 a recusa do worker também devolve as mudanças; o tique seguinte avisa de novo (outra rodada, outra chave)',
      x = '{"enviados": 0, "recusados": 1, "devolvidas": 1}'::jsonb and (e ->> 'enfileirou')::boolean
      and (select count(*) from public.agenda_dono_avisos) = 2
      and (select dedupe_key from public.whatsapp_send_queue where id = (e ->> 'fila_id')::uuid) = 'agenda-dono:aviso:20261029T200000.000000'
      and (select contada_via = 'aviso' and contada_em = pg_temp.em(c_hoje, '17:00') from public.agenda_acoes where id = v_acao), e::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    e := pg_temp.avisar(c_hoje, '19:20');
    -- a nova tentativa do worker (+10 min) cairia às 19:30: falha e a hora volta à de antes
    update public.whatsapp_send_queue set status = 'pending', attempts = 1, scheduled_for = pg_temp.em(c_hoje, '19:30')
     where id = (e ->> 'fila_id')::uuid;
    select q.* into v_fila from public.whatsapp_send_queue q where q.id = (e ->> 'fila_id')::uuid;
    v_res := pg_temp.ok(v_res, 'J7 a nova tentativa que passaria do fim da janela não sai: failed, e a hora volta à de antes',
      v_fila.status = 'failed' and v_fila.failed_reason = 'agenda-dono: a nova tentativa passaria do fim da janela'
      and v_fila.scheduled_for = pg_temp.em(c_hoje, '19:20'), to_jsonb(v_fila)::text);
    -- a 2ª trava recusa a linha cuja última tentativa cairia depois das 19:30
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, telefone, enviar_em, dedupe_key)
    values (pg_temp.em(c_hoje, '19:28'), c_hoje, 'Agenda — o que eu mudei sozinho: teste.', array[gen_random_uuid()], c_fone,
            pg_temp.em(c_hoje, '19:28'), 'agenda-dono:aviso:tarde')
    returning id into v_id;
    v_t := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key, scheduled_for, max_attempts)
                                     values (%L, 'Agenda — o que eu mudei sozinho: teste.', 'agenda-dono', %L, 'agenda-dono:aviso:tarde', %L, 3)$q$,
                                  c_fone, v_id, pg_temp.em(c_hoje, '19:28')));
    v_res := pg_temp.igual(v_res, 'J8 a 2ª trava recusa a linha com alguma tentativa depois do fim da janela (23514, janela)', v_t, '23514:janela');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── T. O teto e o modo ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    update public.agenda_config set gestor_aviso_dia_max = 1 where id;
    perform pg_temp.vigiar(c_hoje, '16:30');
    e := pg_temp.avisar(c_hoje, '16:45');
    v_mov := pg_temp.mover(pg_temp.em(c_hoje, '17:00'));
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '17:15'));
    x := public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '09:30'));
    v_res := pg_temp.ok(v_res, 'T1 com teto 1, o 2º aviso do dia espera (teto, 1 pendente) e sai no dia seguinte, só com o que não foi contado',
      (e ->> 'enfileirou')::boolean and p = '{"avisar": false, "motivo": "teto", "pendentes": 1}'::jsonb
      and (x ->> 'avisar')::boolean and pg_temp.ids(x) = array[v_mov] and x #>> '{mudancas,0,texto}' = c_mover
      and x -> 'fora' = 'null'::jsonb, p::text || ' | ' || x::text);
    -- teto 0: desligado; o que estava na fila não sai e volta a "por contar"
    update public.agenda_config set gestor_aviso_dia_max = 0 where id;
    v_t := concat_ws(' | ',
      public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '17:15')) ->> 'motivo',
      public.agenda_aviso_enfileirar('Agenda — teste.', array[v_mov], '{}'::uuid[], false, c_hoje, pg_temp.em(c_hoje, '17:15')) ->> 'motivo');
    x := public.agenda_aviso_conferir(pg_temp.em(c_hoje, '17:15'));
    v_res := pg_temp.ok(v_res, 'T2 gestor_aviso_dia_max = 0 desliga o aviso: as peças dizem desligado, o enfileirar recusa (modo), e o que estava na fila falha (o aviso saiu de ligado) e volta a "por contar"',
      v_t = 'desligado | modo' and x = '{"enviados": 0, "recusados": 1, "devolvidas": 1}'::jsonb
      and (select status = 'failed' and failed_reason = 'agenda-dono: o aviso do gestor saiu de ligado'
             from public.whatsapp_send_queue where id = (e ->> 'fila_id')::uuid)
      and (select recusa_motivo from public.agenda_dono_avisos where id = (e ->> 'id')::uuid) = 'modo'
      and (select contada_em is null from public.agenda_acoes where tipo = 'publicar'), v_t || ' | ' || x::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_hoje, '16:30');
    -- sem o dono no WhatsApp (a fixture não o liga)
    v_t := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '16:45')) ->> 'motivo';
    perform pg_temp.dono();
    perform pg_temp.modos('ligado', 'sombra');
    v_t := v_t || ' | ' || (public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '16:45')) ->> 'motivo');
    perform pg_temp.modos('sombra', 'ligado');
    v_t := v_t || ' | ' || (public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '16:45')) ->> 'motivo');
    v_res := pg_temp.igual(v_res, 'T3 sem o dono no WhatsApp: sem_dono; com a vigia ou a agenda automática fora de ligado: modo',
      v_t, 'sem_dono | modo | modo');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Q. As perguntas: uma vez por dia ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    e := pg_temp.avisar(c_hoje, '16:45');
    perform pg_temp.saiu(c_hoje, '16:50');
    perform public.agenda_aviso_conferir(pg_temp.em(c_hoje, '17:00'));
    v_mov := pg_temp.mover(pg_temp.em(c_hoje, '17:00'));
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '17:15'));
    v_res := pg_temp.ok(v_res, 'Q1 o 2º aviso do dia (o remanejo das 17:00) não repete as perguntas: só a mudança nova',
      (p ->> 'avisar')::boolean and p -> 'perguntas' = 'null'::jsonb and pg_temp.ids(p) = array[v_mov]
      and p #>> '{mudancas,0,texto}' = c_mover, p::text);
    e := pg_temp.avisar(c_hoje, '17:15');
    perform pg_temp.saiu(c_hoje, '17:20');
    perform public.agenda_aviso_conferir(pg_temp.em(c_hoje, '17:30'));
    perform pg_temp.mover(pg_temp.em(c_sexta, '09:00'));
    p := public.agenda_aviso_pecas(c_sexta, pg_temp.em(c_sexta, '09:30'));
    v_res := pg_temp.ok(v_res, 'Q2 no dia seguinte as perguntas voltam (o que ainda falta responder); a do Lenine foi mostrada 1 vez só ontem',
      jsonb_typeof(p -> 'perguntas') = 'object'
      and (select mostrada_vezes from public.agenda_perguntas where tipo = 'material_conferir' and service_order_id = c_lenine) = 1
      and (select count(*) from public.agenda_dono_avisos where estado = 'enviada') = 2
      and not (select com_perguntas from public.agenda_dono_avisos where rodada = pg_temp.em(c_hoje, '17:15')), p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    e := pg_temp.avisar(c_hoje, '19:28');
    perform public.agenda_aviso_conferir(pg_temp.em(c_hoje, '19:45'));
    perform pg_temp.mover(pg_temp.em(c_hoje, '17:00'));
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '19:00'));
    v_res := pg_temp.ok(v_res, 'Q3 o aviso que não saiu não conta: as perguntas não foram mostradas e voltam no aviso seguinte do mesmo dia',
      jsonb_typeof(p -> 'perguntas') = 'object'
      and (select count(*) from public.agenda_perguntas where mostrada_vezes > 0) = 0, p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D. O gatilho da ação: o prazo do *desfaz* só adianta pelo aviso ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    v_acao := (select id from public.agenda_acoes where tipo = 'publicar');
    v_t := pg_temp.erro_de(format($q$update public.agenda_acoes set desfazivel_ate = desfazivel_ate + interval '1 day' where id = %L$q$, v_acao));
    e := pg_temp.avisar(c_hoje, '16:45');
    v_t := v_t || ' / ' || pg_temp.erro_de(format($q$update public.agenda_acoes set desfazivel_ate = desfazivel_ate - interval '1 hour', contada_em = now() where id = %L$q$, v_acao))
           || ' / ' || pg_temp.erro_de(format($q$update public.agenda_acoes set desfazivel_ate = desfazivel_ate + interval '1 hour', texto = 'Trocado.' where id = %L$q$, v_acao))
           || ' / ' || pg_temp.erro_de(format($q$update public.agenda_acoes set desfazivel_ate = desfazivel_ate + interval '1 hour', contada_em = now() where id = %L$q$, v_acao));
    v_res := pg_temp.igual(v_res, 'D1 o prazo do *desfaz* não muda direto; contada pelo aviso só ADIANTA (para trás ou junto com outra coluna, recusa)',
      v_t, 'P0001 / P0001 / P0001 / ok');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N. O que não muda ──
  begin
    perform pg_temp.modos('sombra', 'sombra');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_hoje, '16:30');
    v_t := pg_temp.retrato();
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '16:45'));
    x := public.agenda_aviso_conferir(pg_temp.em(c_hoje, '16:45'));
    v_res := pg_temp.ok(v_res, 'N1 em teste (sombra) a vigia publica só a proposta: o aviso não conta nada (modo) e nada é gravado',
      p = '{"avisar": false, "motivo": "modo"}'::jsonb and x = '{"enviados": 0, "recusados": 0, "devolvidas": 0}'::jsonb
      and pg_temp.retrato() = v_t, p::text);
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_hoje, '16:30');
    v_t := pg_temp.retrato();
    p := public.agenda_aviso_pecas(c_hoje, pg_temp.em(c_hoje, '16:45'));
    v_res := pg_temp.ok(v_res, 'N2 as peças não gravam nada (o retrato das ações, perguntas, avisos e fila é o mesmo)',
      (p ->> 'avisar')::boolean and pg_temp.retrato() = v_t, null);
    e := pg_temp.avisar(c_hoje, '16:45');
    v_res := pg_temp.ok(v_res, 'N3 o aviso não gasta a cota do acorde (acordes_dia_max conta só contada_via acorde)',
      (e ->> 'enfileirou')::boolean
      and (select count(*) from public.agenda_acoes a where a.dia = c_hoje and a.contada_via = 'acorde') = 0
      and (select count(*) from public.agenda_acoes a where a.contada_via = 'aviso') = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$cenarios$;

-- ── F. A linha do que ficou de fora (sempre: só texto) ─────────────────────────────────────────────────────
do $f$
declare
  c_mp  constant uuid := '00000000-0000-4000-8000-0000000000a1';
  c_k1  constant uuid := '00000000-0000-4000-8000-0000000000a2';
  c_k2  constant uuid := '00000000-0000-4000-8000-0000000000a3';
  v_f   jsonb := jsonb_build_array(
    jsonb_build_object('os', c_k1, 'numero', 'OS-00032', 'cliente_curto', 'Kalmar', 'motivo', 'cliente'),
    jsonb_build_object('os', c_mp, 'numero', 'ORÇ-00095', 'cliente_curto', 'MP', 'motivo', 'sinal'),
    jsonb_build_object('os', c_k2, 'numero', 'OS-00033', 'cliente_curto', 'Kalmar', 'motivo', 'cliente'),
    jsonb_build_object('os', gen_random_uuid(), 'numero', 'OS-00130', 'cliente_curto', 'Giancarlo', 'motivo', 'fora_da_carteira'),
    jsonb_build_object('os', gen_random_uuid(), 'numero', 'OS-00200', 'cliente_curto', 'Zé', 'motivo', 'coisa_nova'));
  v text;
begin
  v := concat_ws(' | ',
    public._agenda_aviso_fora_texto(v_f, null),
    public._agenda_aviso_fora_texto(v_f, array[c_k1, c_k2]),
    public._agenda_aviso_fora_texto(jsonb_build_array(v_f -> 1), null),
    coalesce(public._agenda_aviso_fora_texto('[]'::jsonb, null), '(nada)'),
    coalesce(public._agenda_aviso_fora_texto(jsonb_build_array(v_f -> 1), array[c_mp]), '(nada)'));
  insert into _resultado values ('F1 o que ficou de fora: agrupado pelo porquê na ordem da proposta, o número quando o nome se repete, sem o que saiu da carteira nem o que mudou; 1 = "Ficou de fora"; nada = null',
    v = 'Ficaram de fora 4: Kalmar OS-00032 e Kalmar OS-00033 (esperando o cliente); MP (esperando o sinal); Zé (outro motivo).'
        || ' | Ficaram de fora 2: MP (esperando o sinal); Zé (outro motivo).'
        || ' | Ficou de fora: MP (esperando o sinal).'
        || ' | (nada) | (nada)', v);
end
$f$;

-- ── K. A cópia ───────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_t3 text := coalesce(current_setting('agenda_teste.mig_tabelas_fase3', true), '');
  v_fonte text;
  v_novo text;
begin
  if v_t3 = '' then
    insert into _resultado values ('K1 a cópia só acrescenta o bloco "-- CORREÇÃO 29/10 (P4):"', true,
      'PULADO: sem agenda_teste.mig_tabelas_fase3 (rode pela bancada)');
    return;
  end if;
  v_fonte := pg_temp.corpo(v_t3, '_agenda_acoes_so_desfaz');
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public._agenda_acoes_so_desfaz()'::regprocedure;
  insert into _resultado values (
    'K1 _agenda_acoes_so_desfaz: sem o bloco "-- CORREÇÃO 29/10 (P4):", é o corpo de 20261026100000 (com 1 bloco)',
    v_fonte is not null and pg_temp.sem_blocos(v_novo) = v_fonte
    and (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 29/10 \(P4\): fim', 'g')) = 1,
    format('fonte %s × novo sem blocos %s caracteres', length(v_fonte), length(pg_temp.sem_blocos(v_novo))));
end
$copia$;

-- ── P. Portas (sempre) ───────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values ('public.agenda_aviso_pecas(date, timestamptz)'),
                       ('public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz)'),
                       ('public.agenda_aviso_conferir(timestamptz)'))
insert into _resultado
select 'P1 as 3 RPCs do aviso: só o service_role (nem anon nem authenticated); security definer; search_path fixo',
       bool_and(not has_function_privilege('anon', f.sig, 'execute') and not has_function_privilege('authenticated', f.sig, 'execute')
                and has_function_privilege('service_role', f.sig, 'execute') and p.prosecdef
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'),
       string_agg(f.sig, ', ') filter (where not p.prosecdef)
  from f join pg_proc p on p.oid = f.sig::regprocedure;
with f(sig) as (values ('public._agenda_aviso_dono()'), ('public._agenda_aviso_ligado()'),
                       ('public._agenda_aviso_fora_da_janela(timestamptz, timestamptz)'), ('public._agenda_aviso_no_dia(date, uuid)'),
                       ('public._agenda_aviso_mudancas(date)'), ('public._agenda_aviso_fora_texto(jsonb, uuid[])'))
insert into _resultado
select 'P2 as peças de dentro do aviso: ninguém de fora (nem o service_role); invoker; search_path fixo',
       bool_and(not has_function_privilege('anon', f.sig, 'execute') and not has_function_privilege('authenticated', f.sig, 'execute')
                and not has_function_privilege('service_role', f.sig, 'execute') and not p.prosecdef
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'), null
  from f join pg_proc p on p.oid = f.sig::regprocedure;
insert into _resultado
select 'P3 agenda_dono_avisos: RLS ligada, uma policy só de leitura TO authenticated; anon sem privilégio; authenticated só lê',
       (select c.relrowsecurity from pg_class c where c.oid = 'public.agenda_dono_avisos'::regclass)
       and (select count(*) = 1 and bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT')
              from pg_policies p where p.schemaname = 'public' and p.tablename = 'agenda_dono_avisos')
       and not has_table_privilege('anon', 'public.agenda_dono_avisos', 'select')
       and not has_table_privilege('anon', 'public.agenda_dono_avisos', 'insert')
       and has_table_privilege('authenticated', 'public.agenda_dono_avisos', 'select')
       and not has_table_privilege('authenticated', 'public.agenda_dono_avisos', 'insert')
       and not has_table_privilege('authenticated', 'public.agenda_dono_avisos', 'update'),
       null;
insert into _resultado
select 'P4 os gatilhos da fila só para source agenda-dono (INSERT; e o UPDATE das colunas da linha); a tabela não apaga e só muda o estado',
       count(*) filter (where t.tgname = 'trg_agenda_fila_do_dono' and pg_get_triggerdef(t.oid) like '%BEFORE INSERT%'
                          and pg_get_triggerdef(t.oid) like '%''agenda-dono''%') = 1
       and count(*) filter (where t.tgname = 'trg_agenda_fila_do_dono_linha' and pg_get_triggerdef(t.oid) like '%BEFORE UPDATE OF%') = 1
       and (select count(*) from pg_trigger g where g.tgrelid = 'public.agenda_dono_avisos'::regclass and not g.tgisinternal
              and g.tgname in ('agenda_dono_avisos_nao_apaga', 'agenda_dono_avisos_so_muda')) = 2,
       string_agg(t.tgname, ', ')
  from pg_trigger t where t.tgrelid = 'public.whatsapp_send_queue'::regclass and not t.tgisinternal and t.tgname like 'trg_agenda_fila_do_dono%';
do $p5$
declare
  v text;
begin
  v := pg_temp.como('authenticated', $q$select public.agenda_aviso_pecas(date '2026-10-29', now())::text$q$)
       || ' / ' || pg_temp.como('anon', $q$select public.agenda_aviso_conferir(now())::text$q$)
       || ' / ' || pg_temp.como('authenticated', $q$select count(*)::text from public.agenda_dono_avisos$q$);
  insert into _resultado values ('P5 com login, as RPCs do aviso recusam (42501); a tabela lida pela policy (só administrador e financeiro)',
    v = 'erro 42501 / erro 42501 / 0', v);
end
$p5$;

-- ── C. Os parâmetros novos e as listas (sempre) ──────────────────────────────────────────────────────────
insert into _resultado
select 'C1 os parâmetros do aviso: 09:30, 19:30, 3 por dia, 2400 letras; NOT NULL com DEFAULT',
       c.gestor_aviso_inicio = time '09:30' and c.gestor_aviso_fim = time '19:30' and c.gestor_aviso_dia_max = 3
       and c.gestor_aviso_texto_max = 2400
       and (select bool_and(a.attnotnull and a.atthasdef) from pg_attribute a
             where a.attrelid = 'public.agenda_config'::regclass and a.attname like 'gestor_aviso_%' and not a.attisdropped
               -- (a pausa durante o fechamento é da revisão do lote, 20261030100500: agenda_correcao_2910_revisao.sql, C1)
               and a.attname not like 'gestor_aviso_pausa_%'
             having count(*) = 4),
       to_jsonb(c)::text
  from public.agenda_config c where c.id;
do $c2$
declare
  v text := '';
  r record;
begin
  for r in select * from (values
      ('gestor_aviso_inicio = time ''07:00''', 'agenda_config_gestor_aviso_inicio_check'),
      ('gestor_aviso_inicio = time ''11:30''', 'agenda_config_gestor_aviso_inicio_check'),
      ('gestor_aviso_fim = time ''16:30''', 'agenda_config_gestor_aviso_fim_check'),
      ('gestor_aviso_fim = time ''20:30''', 'agenda_config_gestor_aviso_fim_check'),
      ('gestor_aviso_dia_max = 7', 'agenda_config_gestor_aviso_dia_max_check'),
      ('gestor_aviso_dia_max = -1', 'agenda_config_gestor_aviso_dia_max_check'),
      ('gestor_aviso_texto_max = 500', 'agenda_config_gestor_aviso_texto_max_check'),
      ('gestor_aviso_texto_max = 5000', 'agenda_config_gestor_aviso_texto_max_check'),
      ('gestor_aviso_inicio = time ''07:30'', gestor_aviso_fim = time ''20:00'', gestor_aviso_dia_max = 0, gestor_aviso_texto_max = 4000', 'aceitou'))
      as x(sets, esperado) loop
    begin
      execute format('update public.agenda_config set %s where id', r.sets);
      raise exception 'desfaz' using errcode = 'P0099';
    exception
      when check_violation then
        declare
          v_c text;
        begin
          get stacked diagnostics v_c = constraint_name;
          v := v || case when v_c = r.esperado then '' else format('[%s: recusou por %s] ', r.sets, v_c) end;
        end;
      when sqlstate 'P0099' then
        v := v || case when r.esperado = 'aceitou' then '' else format('[%s: aceitou] ', r.sets) end;
    end;
  end loop;
  insert into _resultado values ('C2 os CHECKs recusam 07:00 e 11:30 de início, 16:30 e 20:30 de fim, 7 e −1 por dia, 500 e 5000 letras; aceitam os limites',
    v = '', nullif(v, ''));
end
$c2$;
do $c3$
declare
  v text;
begin
  v := pg_temp.erro_de($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, contada_em, contada_via)
                           values ('2026-10-29', true, 'vigia', 'mover', 'Mudei.', now(), 'aviso')$q$)
       || ' / ' || pg_temp.erro_de($q$insert into public.agenda_perguntas (tipo, chave, texto, modo, mostrada_via)
                                       values ('chegou', 'chegou:p4', 'Pergunta?', 'sombra', 'aviso')$q$)
       || ' / ' || pg_temp.erro_de($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, contada_em, contada_via)
                                       values ('2026-10-29', true, 'vigia', 'mover', 'Mudei.', now(), 'sms')$q$);
  insert into _resultado values ('C3 as listas fechadas aceitam ''aviso'' (contada_via e mostrada_via) e continuam recusando o resto',
    split_part(v, ':', 1) = 'ok / ok / 23514', v);
end
$c3$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
