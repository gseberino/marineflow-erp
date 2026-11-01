-- Prova da migration de dado da Fase 7c da Agenda de Produção (pacote P7; 20261102100600_agenda_fase7c_sombra.sql), que a bancada NÃO
-- aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a equipe de verdade (a variante real da fixture da
-- 7c: só o Alex, sem perfil e sem telefone, e o dono) — spec-fase7c §5.7, §10 passo 3, §16.9, §16.10 passo 3, R5.5 linha 8, R5.7-1 e -9.
-- bancada: depende de 20261102100550
--
--   S  os 4 modos da 7c: desligado → sombra (habilidade, lider, habilidade_propor, tarefas); o resto da linha igual (os modos das Fases
--      1–6, da 7a e da 7b, os números da 7c); de novo não muda nada (nem a hora); ligado nunca é rebaixado e teste fica teste; o dado
--      sozinho não escreve mais nada
--   N  um dia útil inteiro de rodadas (qui 05/11: os tiques das 16:15, 16:30, 16:45, 17:00 e 19:30 — as etapas, a rotina da equipe, quem
--      faz o quê, a vigia e o cliente — e o gestor das 16:53), rodado SEM e COM o dado, sobre o estado de produção de hoje (A: a 7a e a
--      7b em teste) e sobre o de depois dos ligar da 7a e da 7b (B: o gestor ligado, a dupla, o cadastro, quem chamar e o sábado ligados,
--      os dias em teste): com o dado, o plano (as alocações, com o critério), as propostas do motor, as ações que valem, as perguntas
--      ligadas, as mensagens à equipe e ao cliente, a fila do WhatsApp, a disponibilidade, o planejamento, o diário do gestor e as linhas
--      LIGADAS do fechamento (as que o dono lê) são as de sem o dado (R5.7-1); só nasce o que é de teste — a pergunta habilidade:equipe em
--      teste, a proposta do gestor que não vale ("Alex instala 2"), as ações de teste, as etapas e as linhas de teste do fechamento —, as
--      rodadas não erram e a sincronização das etapas só cria a linha da assinatura no planejamento
--   L  em teste, o dono LÊ o teste: o foco *agenda quem faz* com "(em teste, eu marcaria: você disse que ele vem todo dia útil)" e a OS
--      com etapa com "Etapas (em teste: a equipe ainda não recebe): …"
--   D  o DESFAZER do cabeçalho: um comando só (with … select), dois UPDATE (agenda_config e agenda_perguntas), nenhum DELETE; volta teste a
--      desligado e não mexe no ligado (diz quais ficam ligados); a pergunta em teste aberta vira descartada; com tudo desligado não muda
--      nada (nem a hora); depois de um dia em teste e do DESFAZER, o fechamento inteiro e as leituras do dono voltam a ser os de sem o
--      dado, a rodada das etapas devolve {rodou: false} e a de quem faz o quê só roda o prazo e a medida
--
-- (A comparação das linhas de pergunta do fechamento é pelas perguntas que cada linha leva, não pelo texto: na bancada, as perguntas que o
-- gestor abre no mesmo tique têm o mesmo criada_em — tudo roda numa transação só —, e a ordem entre elas, que escolhe qual vai inteira,
-- varia de uma rodada para outra mesmo sem o dado; o mesmo dia rodado duas vezes sem o dado já dá textos diferentes nessas linhas.)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto nem a fixture: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o
--   pós-deploy (supabase/tests/agenda_fase7c_pos_deploy.sql, só leitura). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create function pg_temp.res(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false),
                                                      case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.sem_ids(p text) returns text language sql immutable as $f$
  select regexp_replace(regexp_replace(coalesce(p, ''), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g'),
                        '"ms": [0-9]+', '"ms": N', 'g')
$f$;
-- A linha de agenda_config sem os 4 modos da 7c e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto_da_config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_habilidade' - 'modo_lider' - 'modo_habilidade_propor' - 'modo_tarefas' - 'atualizado_em' - 'atualizado_por'
    from public.agenda_config c
$f$;
create function pg_temp.modos() returns text language sql stable as $f$
  select concat_ws(' ', c.modo_habilidade, c.modo_lider, c.modo_habilidade_propor, c.modo_tarefas) from public.agenda_config c
$f$;
-- O que o dado sozinho não pode mexer (S e D).
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select count(*) from public.agenda_acoes),
    'perguntas', (select md5(coalesce(string_agg(to_jsonb(q)::text, '|' order by q.id), '')) from public.agenda_perguntas q),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'fila', (select count(*) from public.whatsapp_send_queue),
    'disponibilidade', (select md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '')) from public.agenda_disponibilidade d),
    'plano', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.service_order_id), '')) from public.os_planejamento p),
    'etiquetas', (select count(*) from public.agenda_etiquetas),
    'etapas', (select count(*) from public.os_tarefas) + (select count(*) from public.os_tarefas_dia),
    'rodadas', (select count(*) from public.agenda_vigia_rodadas))
$f$;
-- Um bloco de SQL do cabeçalho da migration: as linhas "--   …" depois da linha que começa com p_titulo, até a linha "--" que fecha.
create function pg_temp.bloco(p_mig text, p_titulo text) returns text language plpgsql immutable as $f$
declare
  v text;
  r text;
begin
  if position(E'\n' || p_titulo in p_mig) = 0 then return null; end if;
  v := substr(p_mig, position(E'\n' || p_titulo in p_mig) + 1);
  v := left(v, position(E'\n--\n' in v));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into r
    from regexp_split_to_table(v, E'\n') with ordinality t(l, n)
   where t.l like '--   %';
  return r;
end $f$;
-- Uma linha do fechamento, comparável: a de pergunta pelas perguntas que leva (o tipo e a chave, sem os ids gerados); as outras pelo texto.
create function pg_temp.linha(p jsonb) returns text language sql stable as $f$
  select case when p ->> 'tipo' = 'pergunta' then
           concat_ws('|', p ->> 'tipo', p ->> 'perda', p ->> 'modo',
                     (select string_agg(q.tipo || ':' || pg_temp.sem_ids(q.chave), ',' order by q.tipo || ':' || pg_temp.sem_ids(q.chave))
                        from public.agenda_perguntas q
                       where q.id::text in (select jsonb_array_elements_text(coalesce(p -> 'pergunta_ids', '[]'::jsonb))
                                            union select p ->> 'pergunta_id')))
         else concat_ws('|', p ->> 'tipo', p ->> 'perda', p ->> 'modo', pg_temp.sem_ids(p ->> 'texto'), pg_temp.sem_ids(p ->> 'texto_curto')) end
$f$;
-- A foto do que o dado não pode mudar (N), sem os ids gerados (a mesma rodada gera uuids novos a cada vez).
create function pg_temp.foto(p_dia date, p_os uuid) returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(concat_ws('|', a.service_order_id, a.payee_id, a.dia, a.turno, a.presenca, a.tipo, a.estado,
                     a.origem, a.cancelada_motivo, a.criterio, a.criterio_detalhe::text, a.resultado, a.duracao_fonte, a.motivos::text), E'\n'
                     order by concat_ws('|', a.service_order_id, a.payee_id, a.dia, a.turno, a.tipo, a.estado, a.criado_em)), ''))
                    from public.agenda_alocacoes a),
    'propostas', (select md5(coalesce(string_agg(pg_temp.sem_ids(concat_ws('|', p.escopo, p.periodo, p.modo, p.estado, p.criada_por, p.itens::text,
                     p.fora::text)), E'\n' order by p.criada_em, p.escopo, pg_temp.sem_ids(p.itens::text)), '')) from public.agenda_propostas p),
    'acoes_valem', (select md5(coalesce(string_agg(x.l, E'\n' order by x.l), '')) from (
                     select pg_temp.sem_ids(concat_ws('|', a.tipo, a.origem, a.service_order_id, a.texto, a.dia)) as l
                       from public.agenda_acoes a where a.executada) x),
    'acoes_teste', (select coalesce(jsonb_agg(a.tipo order by a.tipo), '[]') from public.agenda_acoes a where not a.executada),
    'acoes_teste_ok', (select coalesce(bool_and(a.tipo in ('habilidade', 'tarefa') and a.texto like 'Em teste%'), true)
                         from public.agenda_acoes a where not a.executada),
    'perguntas_ligadas', (select md5(coalesce(string_agg(x.l, E'\n' order by x.l), '')) from (
                           select pg_temp.sem_ids(concat_ws('|', q.tipo, q.chave, q.modo, q.estado, q.texto, q.mostrada_vezes, q.veto_ate)) as l
                             from public.agenda_perguntas q where q.modo = 'ligado') x),
    'perguntas_teste', (select coalesce(jsonb_agg(q.tipo || ' ' || q.estado || ' ' || split_part(q.chave, ':', 1) || ':' || split_part(q.chave, ':', 2)
                         order by q.tipo, q.chave), '[]') from public.agenda_perguntas q where q.modo <> 'ligado'),
    'equipe', (select md5(coalesce(string_agg(x.l, E'\n' order by x.l), '')) from (
                select concat_ws('|', m.payee_id, m.dia, m.tipo, m.modo, m.estado, m.recusa_motivo, m.texto, m.enviar_em) as l
                  from public.agenda_equipe_mensagens m) x),
    'n_equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select md5(coalesce(string_agg(x.l, E'\n' order by x.l), '')) from (
                 select concat_ws('|', m.client_id, m.service_order_id, m.tipo, m.modelo, m.modo, m.estado, m.aprovacao, m.texto, m.enviar_em) as l
                   from public.agenda_cliente_mensagens m) x),
    'n_cliente', (select count(*) from public.agenda_cliente_mensagens),
    'fila', (select md5(coalesce(string_agg(x.l, E'\n' order by x.l), '')) from (
              select concat_ws('|', w.phone_normalized, w.message, w.source, w.status, w.scheduled_for) as l from public.whatsapp_send_queue w) x),
    'n_fila', (select count(*) from public.whatsapp_send_queue),
    'disponibilidade', (select md5(coalesce(string_agg((to_jsonb(d) - 'id')::text, E'\n' order by (to_jsonb(d) - 'id')::text), ''))
                          from public.agenda_disponibilidade d),
    -- o planejamento de cada OS sem a assinatura das etapas; e as linhas vazias (só a assinatura: as que a sincronização cria)
    'plano', (select coalesce(jsonb_object_agg(p.service_order_id, md5((to_jsonb(p) - 'tarefas_assinatura' - 'tarefas_sincronizadas_em')::text)), '{}')
                from public.os_planejamento p),
    'plano_vazias', (select coalesce(jsonb_agg(p.service_order_id order by p.service_order_id), '[]') from public.os_planejamento p
                      where jsonb_strip_nulls(to_jsonb(p)) - 'service_order_id' - 'atualizado_em' - 'tarefas_assinatura' - 'tarefas_sincronizadas_em'
                            - 'historico' - 'bem_indisponivel' - 'exigencias_ditas' = '{}'::jsonb
                        and p.historico = '[]'::jsonb and p.exigencias_ditas = '{}'::jsonb and to_jsonb(p) -> 'bem_indisponivel' = '"{}"'::jsonb),
    'etiquetas', (select coalesce(jsonb_agg(py.name || ' ' || e.etiqueta || ' ' || e.nivel || ' ' || e.origem || ' ' || e.estado
                   order by py.name, e.etiqueta), '[]') from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id),
    'fechamento_ligado', (select md5(coalesce(string_agg(x.l, E'\n' order by x.l), '')) from (
                           select pg_temp.linha(l) as l from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) l
                            where l ->> 'modo' = 'ligado') x),
    'n_fechamento_ligado', (select count(*) from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) l where l ->> 'modo' = 'ligado'),
    'fechamento_teste', (select coalesce(jsonb_agg((l ->> 'tipo') || ' ' || left(l ->> 'texto', 60) order by l ->> 'tipo', l ->> 'texto'), '[]')
                          from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) l where l ->> 'modo' <> 'ligado'),
    'gestor_dia', (select md5(coalesce(string_agg(pg_temp.sem_ids(concat_ws('|', g.dia, g.texto_sombra, g.chamar::text, g.compras::text,
                     g.orcamentos::text)), E'\n' order by g.dia), '')) from public.agenda_gestor_dia g),
    'rodadas', (select coalesce(jsonb_agg(r.rotina order by r.rotina, r.rodou_em), '[]') from public.agenda_vigia_rodadas r where r.p_hoje = p_dia),
    'erros_rodadas', (select coalesce(sum(r.erros), 0) from public.agenda_vigia_rodadas r where r.p_hoje = p_dia),
    'habilidade_passos', (select coalesce(jsonb_agg(k order by k), '[]') from public.agenda_vigia_rodadas r, jsonb_object_keys(r.contagens) k
                           where r.p_hoje = p_dia and r.rotina = 'habilidade' and k not in ('modos', 'falhas')),
    'etapas', (select count(*) from public.os_tarefas),
    'erros_app', (select count(*) from public.app_error_logs e where e.context = 'agenda' and (e.action like 'habilidade:%' or e.action like 'tarefas:%')),
    'ver_os', (select public._agenda_ver_os(p_os, p_dia) ->> 'texto'),
    'foco', (select public.agenda_ver(p_foco => 'habilidades', p_hoje => p_dia) ->> 'texto'))
$f$;
-- Um dia útil de rodadas, como o task-automations (0a as etapas, a rotina da equipe, 0b2a quem faz o quê, a vigia e o cliente, a cada
-- tique) e o job do gestor (16:53): 16:15, 16:30 (o diário das etapas), 16:45, 17:00 (o "como foi") e 19:30 (a ficha e o congelamento).
create function pg_temp.dia(p_dia date) returns void language plpgsql as $f$
declare
  h text;
begin
  foreach h in array array['16:15', '16:30', '16:45', '17:00', '19:30'] loop
    perform public.agenda_tarefas_rodar(p_dia, pg_temp.em(p_dia, h));
    perform public.agenda_rotina_rodar(p_dia, pg_temp.em(p_dia, h));
    perform public.agenda_habilidade(p_dia, pg_temp.em(p_dia, h));
    perform public.agenda_vigiar(p_dia, pg_temp.em(p_dia, h));
    perform public.agenda_cliente_vigiar(p_dia, pg_temp.em(p_dia, h));
    if h = '16:45' then
      perform public.agenda_gestor_rodar(p_dia, pg_temp.em(p_dia, '16:53'));
    end if;
  end loop;
end
$f$;
-- O estado de produção: A, hoje (a 7a e a 7b em teste); B, depois dos ligar da 7a (ter 03/11 16:46) e da 7b (qua 04/11 16:31: o
-- cadastro, a dupla, quem chamar e o sábado; os dias em teste). A 7c desligada, como as migrations de estrutura a deixam.
create function pg_temp.estado(p_qual text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_vaga_fechamento = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_encaixe_aprovacao = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_revisao_diaria = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_compre_ate = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         marcar_sozinho_desde = case when p_qual = 'B' then timestamptz '2026-11-03 16:46-03' end,
         gestor_so_propor = false, gestor_so_propor_em = null,
         modo_dias = 'sombra',
         modo_dupla = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_sabado = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_cadastro = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_chamar = case when p_qual = 'B' then 'ligado' else 'sombra' end,
         modo_habilidade = 'desligado', modo_lider = 'desligado', modo_habilidade_propor = 'desligado', modo_tarefas = 'desligado'
   where id;
$f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase7c', true);
  v_res    jsonb := '[]'::jsonb;
  v_desf   text;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_lista  record;
  v_os     uuid;
  e        text;
  f0       jsonb;
  f1       jsonb;
  f2       jsonb;
  v_dif    text;
  v_tar    jsonb;
  v_hab    jsonb;
  v_nq     text;
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase7c', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261102100600 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase7c ou as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_desf := pg_temp.bloco(v_mig, '-- DESFAZER');

  -- a equipe de verdade: a variante real da fixture da 7c (só o Alex e o dono; a carteira de produção)
  perform set_config('agenda_teste.fase7b_equipe', 'real', true);
  execute current_setting('agenda_teste.fase7c');
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  -- a OS que ganha etapa em teste nos dois estados (o Paulo, em andamento)
  select so.id into strict v_os from public.service_orders so where so.service_order_number = 'OS-97001';

  -- ── S: a 1ª vez, a 2ª vez, o ligado ────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.estado('A');
    update public.agenda_config set atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S1 os 4 modos da 7c de desligado para sombra (habilidade, lider, habilidade_propor, tarefas)',
      pg_temp.modos() = 'sombra sombra sombra sombra', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S2 o resto da linha não muda (os modos das Fases 1–6, da 7a e da 7b, os números da 7c); atualizado_por nulo e a hora nova',
      pg_temp.resto_da_config() = v_resto and v_linha ->> 'atualizado_por' is null
      and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-11-01 12:00-03', pg_temp.resto_da_config()::text);
    v_res := pg_temp.res(v_res, 'S3 o dado sozinho não escreve mais nada: o plano, as propostas, as ações, as perguntas, as mensagens, a fila, a disponibilidade, o planejamento, as etiquetas, as etapas e as rodadas iguais',
      pg_temp.contagens() = v_cont, pg_temp.contagens()::text);
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 idempotente: a 2ª vez não muda nada (nem a hora)', (select to_jsonb(c) from public.agenda_config c) = v_linha, null);
    update public.agenda_config set modo_habilidade = 'ligado', modo_lider = 'sombra', modo_habilidade_propor = 'desligado',
                                    modo_tarefas = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5 nunca rebaixa ligado nem mexe no que está em teste; só o desligado vai a teste',
      pg_temp.modos() = 'ligado sombra sombra sombra', pg_temp.modos());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N e L: o mesmo dia útil sem e com o dado, nos estados A e B ────────────────────────────────────────────────────
  foreach e in array array['A', 'B'] loop
    begin
      perform pg_temp.estado(e);
      perform pg_temp.dia(date '2026-11-05');
      f0 := pg_temp.foto(date '2026-11-05', v_os);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    begin
      perform pg_temp.estado(e);
      execute v_mig;
      perform pg_temp.dia(date '2026-11-05');
      f1 := pg_temp.foto(date '2026-11-05', v_os);
      if e = 'A' then
        -- D6 (abaixo): o DESFAZER depois de um dia em teste, e o dia seguinte
        execute v_desf into v_lista;
        f2 := pg_temp.foto(date '2026-11-05', v_os);
        v_tar := public.agenda_tarefas_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:15'));
        v_hab := public.agenda_habilidade(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:15'));
        select string_agg(q.tipo || ' ' || q.modo || ' ' || q.estado || ' ' || coalesce(q.resolvida_motivo, '-'), '; ' order by q.chave) into v_nq
          from public.agenda_perguntas q where q.tipo in ('habilidade', 'tarefa');
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    select string_agg(k, ', ' order by k) into v_dif
      from unnest(array['alocacoes', 'propostas', 'acoes_valem', 'perguntas_ligadas', 'equipe', 'n_equipe', 'cliente', 'n_cliente', 'fila',
                        'n_fila', 'disponibilidade', 'gestor_dia', 'fechamento_ligado', 'n_fechamento_ligado']) k
     where f0 -> k is distinct from f1 -> k;
    v_res := pg_temp.res(v_res, format('N1%s (estado %s) com o dado, o mesmo dia dá o mesmo plano (as alocações, com o critério), as mesmas propostas do motor, as mesmas ações que valem e perguntas ligadas, as mesmas mensagens à equipe e ao cliente, a mesma fila, a mesma disponibilidade, o mesmo diário do gestor e as mesmas linhas ligadas do fechamento', lower(e), e),
      v_dif is null and (f1 ->> 'n_fila')::int = (f0 ->> 'n_fila')::int,
      concat_ws(' | ', 'diferem: ' || v_dif, f0::text, f1::text));
    select string_agg(k, ', ' order by k) into v_dif
      from jsonb_object_keys(f0 -> 'plano') k where (f0 -> 'plano' -> k) is distinct from (f1 -> 'plano' -> k);
    v_res := pg_temp.res(v_res, format('N2%s (estado %s) o planejamento de cada OS igual (fora a assinatura das etapas); as linhas novas são só da sincronização das etapas (vazias, com a assinatura)', lower(e), e),
      v_dif is null
      and not exists (select 1 from jsonb_object_keys(f1 -> 'plano') k
                       where not (f0 -> 'plano') ? k and not (f1 -> 'plano_vazias') @> to_jsonb(k)),
      concat_ws(' | ', 'diferem: ' || v_dif, f1 -> 'plano_vazias'));
    v_res := pg_temp.res(v_res, format('N3%s (estado %s) só nasce o que é de teste: a pergunta habilidade:equipe em teste, a proposta do gestor que não vale (Alex instala 2), as etapas e as linhas de teste do fechamento; nenhuma ação que vale nem pergunta ligada; sem o dado, nada disso', lower(e), e),
      f0 -> 'perguntas_teste' = '[]'::jsonb and f0 -> 'etiquetas' = '[]'::jsonb and f0 -> 'acoes_teste' = '[]'::jsonb
      and f0 -> 'fechamento_teste' = '[]'::jsonb and (f0 ->> 'etapas')::int = 0
      and f1 -> 'perguntas_teste' = '["habilidade aberta habilidade:equipe"]'::jsonb
      and f1 -> 'etiquetas' = '["Alex instala 2 gestor proposta"]'::jsonb
      and (f1 ->> 'acoes_teste_ok')::boolean and (f1 ->> 'etapas')::int > 0
      and jsonb_array_length(f1 -> 'fechamento_teste') >= 1
      and f1 -> 'fechamento_teste' ->> 0 like 'pergunta Agenda: Para não mandar ninguém sozinho em serviço de risco%',
      concat_ws(' | ', f1 -> 'perguntas_teste', f1 -> 'etiquetas', f1 -> 'acoes_teste', f1 ->> 'etapas', f1 -> 'fechamento_teste'));
    v_res := pg_temp.res(v_res, format('N4%s (estado %s) as rodadas: com o dado, a de quem faz o quê roda em teste (propor, prazo, conferir e medir) uma vez e a das etapas entra a cada tique; sem erro nenhum (nem em app_error_logs)', lower(e), e),
      (f1 ->> 'erros_rodadas')::int = 0 and (f0 ->> 'erros_rodadas')::int = 0 and (f1 ->> 'erros_app')::int = 0
      and f1 -> 'habilidade_passos' = '["conferir", "medir", "propor", "vetos"]'::jsonb
      and f0 -> 'habilidade_passos' = '["medir", "vetos"]'::jsonb
      and (select count(*) from jsonb_array_elements_text(f1 -> 'rodadas') x where x = 'habilidade') = 1
      and (select count(*) from jsonb_array_elements_text(f1 -> 'rodadas') x where x = 'tarefas') >= 1
      and (select count(*) from jsonb_array_elements_text(f0 -> 'rodadas') x where x = 'tarefas') = 0
      and (select jsonb_agg(x order by x) from jsonb_array_elements_text(f1 -> 'rodadas') x where x <> 'tarefas')
          = (select jsonb_agg(x order by x) from jsonb_array_elements_text(f0 -> 'rodadas') x),
      concat_ws(' | ', f0 -> 'rodadas', f1 -> 'rodadas', f1 -> 'habilidade_passos', f1 ->> 'erros_rodadas', f1 ->> 'erros_app'));
    v_res := pg_temp.res(v_res, format('L%s (estado %s) em teste, o dono lê o teste: *agenda quem faz* diz "(em teste: ainda escalo como antes)" e "Alex: instala sozinho (em teste, eu marcaria: você disse que ele vem todo dia útil)"; a OS do Paulo ganha "Etapas (em teste: a equipe ainda não recebe): …"; sem o dado, nem uma coisa nem outra', lower(e), e),
      f1 ->> 'foco' like 'Quem faz o quê (em teste: ainda escalo como antes):%'
      and position('• Alex: instala sozinho (em teste, eu marcaria: você disse que ele vem todo dia útil).' in f1 ->> 'foco') > 0
      and position('Etapas (em teste: a equipe ainda não recebe): 0 de 1 feitas.' in f1 ->> 'ver_os') > 0
      and position('Etapas' in f0 ->> 'ver_os') = 0
      and f1 ->> 'ver_os' like (f0 ->> 'ver_os') || E'\nEtapas (em teste: a equipe ainda não recebe): %'
      and f0 ->> 'foco' like 'Quem faz o quê (desligado%',
      concat_ws(' || ', f0 ->> 'foco', f1 ->> 'foco', f0 ->> 'ver_os', f1 ->> 'ver_os'));
    if e = 'A' then
      v_res := pg_temp.res(v_res, 'D6 depois de um dia em teste, o DESFAZER: os 4 desligados, a pergunta em teste descartada ("a 7c voltou a desligado"), e o fechamento inteiro (as linhas ligadas e as de teste) e a OS do Paulo voltam a ser os de sem o dado; no dia seguinte a rodada das etapas devolve {rodou: false} e a de quem faz o quê só roda o prazo e a medida',
        v_lista.modos_desligados = 1 and v_lista.perguntas_em_teste_descartadas = 1 and v_lista.ficam_ligados = 'nenhum'
        and v_nq = 'habilidade sombra descartada a 7c voltou a desligado (DESFAZER da 20261102100600)'
        and f2 -> 'fechamento_ligado' = f0 -> 'fechamento_ligado' and f2 -> 'n_fechamento_ligado' = f0 -> 'n_fechamento_ligado'
        and f2 -> 'fechamento_teste' = f0 -> 'fechamento_teste' and f2 ->> 'ver_os' = f0 ->> 'ver_os'
        and v_tar = '{"rodou": false, "modo": "desligado"}'::jsonb
        and coalesce((v_hab ->> 'rodou')::boolean, false)
        and (select jsonb_agg(k order by k) from jsonb_object_keys(v_hab -> 'contagens') k) = '["medir", "vetos"]'::jsonb,
        concat_ws(' | ', v_lista::text, v_nq, f2 -> 'fechamento_teste', v_tar::text, v_hab::text));
    end if;
  end loop;

  -- ── D: o DESFAZER do cabeçalho ─────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.res(v_res, 'D0 o cabeçalho tem o DESFAZER num comando só (with … select … ;): dois UPDATE (agenda_config e agenda_perguntas), nenhum DELETE',
    v_desf is not null and v_desf ~ '^\s*with antes as \(' and v_desf ~ ';\s*$'
    and (length(v_desf) - length(replace(v_desf, ';', ''))) = 1
    and (length(v_desf) - length(replace(v_desf, 'update public.', ''))) / length('update public.') = 2
    and position('update public.agenda_config' in v_desf) > 0 and position('update public.agenda_perguntas' in v_desf) > 0
    and position('delete' in lower(v_desf)) = 0, coalesce(v_desf, '(sem o bloco)'));
  begin
    perform pg_temp.estado('A');
    execute v_mig;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_desf into v_lista;
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta os 4 de sombra a desligado; o resto da linha, o plano, as mensagens e as perguntas ficam (nenhuma em teste aberta); atualizado_por nulo; o resultado diz nenhum ligado',
      pg_temp.modos() = 'desligado desligado desligado desligado' and pg_temp.resto_da_config() = v_resto
      and pg_temp.contagens() = v_cont and (select atualizado_por from public.agenda_config) is null
      and v_lista.modos_desligados = 1 and v_lista.perguntas_em_teste_descartadas = 0 and v_lista.ficam_ligados = 'nenhum',
      concat_ws(' | ', pg_temp.modos(), v_lista::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.estado('A');
    update public.agenda_config set modo_habilidade = 'ligado', modo_lider = 'ligado', modo_habilidade_propor = 'sombra',
                                    modo_tarefas = 'sombra' where id;
    execute v_desf into v_lista;
    v_res := pg_temp.res(v_res, 'D2 o DESFAZER não mexe no que já foi ligado (a escalação e o responsável ficam ligados) e diz quais ficam',
      pg_temp.modos() = 'ligado ligado desligado desligado' and v_lista.modos_desligados = 1
      and v_lista.ficam_ligados = 'modo_habilidade, modo_lider', concat_ws(' | ', pg_temp.modos(), v_lista::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.estado('A');
    update public.agenda_config set atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_cont := pg_temp.contagens();
    execute v_desf into v_lista;
    v_res := pg_temp.res(v_res, 'D3 o DESFAZER com tudo desligado não muda nada (nem a hora)',
      (select to_jsonb(c) from public.agenda_config c) = v_linha and pg_temp.contagens() = v_cont
      and v_lista.modos_desligados = 0 and v_lista.perguntas_em_teste_descartadas = 0 and v_lista.ficam_ligados = 'nenhum',
      (select to_jsonb(c) from public.agenda_config c)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a proposta de quem faz o quê ligada (a pergunta ligada) e a das etapas em teste: o DESFAZER descarta só a em teste das etapas
    perform pg_temp.estado('A');
    update public.agenda_config set modo_habilidade = 'sombra', modo_lider = 'sombra', modo_habilidade_propor = 'ligado',
                                    modo_tarefas = 'sombra' where id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, modo, criada_em)
    values ('tarefa', 'tarefa:quem:' || v_os, v_os, array[v_os], 'Em teste: Paulo: quem vai junto?', '[]'::jsonb, 'sombra', now());
    insert into public.agenda_perguntas (tipo, chave, texto, opcoes, modo, criada_em)
    values ('habilidade', 'habilidade:equipe:2026-11-05', 'Para não mandar ninguém sozinho…', '[]'::jsonb, 'ligado', now());
    execute v_desf into v_lista;
    select string_agg(q.tipo || ' ' || q.modo || ' ' || q.estado, '; ' order by q.tipo) into v_nq
      from public.agenda_perguntas q where q.tipo in ('habilidade', 'tarefa');
    v_res := pg_temp.res(v_res, 'D4 o DESFAZER descarta a pergunta em teste do modo que termina desligado (a das etapas) e deixa a ligada (a proposta de quem faz o quê, ligada, fica aberta)',
      pg_temp.modos() = 'desligado desligado ligado desligado' and v_lista.perguntas_em_teste_descartadas = 1
      and v_lista.ficam_ligados = 'modo_habilidade_propor' and v_nq = 'habilidade ligado aberta; tarefa sombra descartada',
      concat_ws(' | ', pg_temp.modos(), v_lista::text, v_nq));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o DESFAZER e o dado de novo: os 4 voltam a teste, e a rodada pergunta de novo (a descartada não volta)
    perform pg_temp.estado('A');
    execute v_mig;
    perform public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    execute v_desf into v_lista;
    execute v_mig;
    perform public.agenda_habilidade(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:15'));
    select string_agg(q.modo || ' ' || q.estado || ' ' || split_part(q.chave, ':', 3), '; ' order by q.criada_em, q.chave) into v_nq
      from public.agenda_perguntas q where q.tipo = 'habilidade';
    v_res := pg_temp.res(v_res, 'D5 depois do DESFAZER, o dado de novo põe os 4 em teste e a rodada do dia seguinte pergunta de novo (a pergunta descartada fica descartada; a proposta é a mesma)',
      pg_temp.modos() = 'sombra sombra sombra sombra'
      and v_nq = 'sombra descartada 2026-11-05; sombra aberta 2026-11-06'
      and (select count(*) from public.agenda_etiquetas e where e.origem = 'gestor' and e.estado = 'proposta') = 1,
      concat_ws(' | ', pg_temp.modos(), v_nq));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select x ->> 0, (x ->> 1)::boolean, x ->> 2 from jsonb_array_elements(v_res) x;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
