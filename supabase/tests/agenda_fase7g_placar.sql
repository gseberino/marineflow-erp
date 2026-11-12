-- Prova do placar da semana, do motivo ferramenta e da chave explicar da saúde, Fase 7g (pacote P6; migration 20261112100500; spec-fase7g §5.6, §6.5, §8.3
-- agenda_fase7g_placar.sql, §11 e o bloco R9: R9.4-3, R9.5-12 a 15, 17 e 27, R9.12, R9.13 — "Q1 com razao_estimativa; Q2 com linha sem dado e o mínimo; Q4 só
-- na mensagem própria, com 2.400 e a paridade TS × SQL da peça placar; Q5 com agenda_conferir_dia").
-- bancada: depende de 20261112100500
--
-- O cenário (pg_temp.cenario_q): a semana medida é de seg 01 a sáb 06/03/2027 (longe da fixture: só o que o cenário põe cai nela), hoje é qui 11/03/2027.
-- Cada OS (OS-Q<nome>, motorhome) tem a sua pessoa. As marcações vão direto em agenda_marcacoes (a forma que o P5 grava), as ações com a zona e o degrau
-- gravados, os meios-dias publicados com o resultado, as medidas da 7e, os itens com o "compre até", as mensagens da fila (só contagem) e os tipos de OS.
--
--   Q0  o catálogo: as 7 novas (volatilidade, definer, search_path, portas); a migration cria as 7 e recria só as 6; tiradas as marcas da 7g, cada recriada
--       é a origem, byte a byte, e a viva é a desta migration
--   Q1  cada chave do §5.6 no cenário (a estimativa por razao_estimativa com motivo_razao nulo; o 1º da OS na aprovação; a zona sem cliente, dono, publicar
--       nem desfeita); a cobertura pela diferença (Q7); as perguntas pela diferença; nada arredondado
--   Q2  o texto e a linha do §6.5 byte a byte; a mensagem só com as linhas com dado; o sem dado; o erro; o freio; o corte; o mínimo (linhas); 22023
--   Q3  o guardado: desligado nada; 1 vez; 2× = 1×; mudou = versão + 1 e histórico; a leitura usa o guardado da semana fechada; a rodada explicar chama
--   Q4  a quinta (só a mensagem própria): desligado e sombra = o de antes, byte a byte; ligado = o placar antes das perguntas, no teto de 2.400; abaixo do
--       mínimo, nada; com o lote ligado, a peça nas peças; a paridade TS × SQL (Q4p: o mesmo texto de aviso-do-gestor_test.ts); enviado_em
--   Q5  o motivo ferramenta: as palavras (a paridade com MOTIVOS_DO_DIA e MOTIVOS_DO_ANDAMENTO), o texto, *dia não carro* até o *grava* (agenda_conferir_dia)
--       e a pergunta "hoje ou ontem?"; as palavras de antes iguais; capacidade_motivos sem ele
--   Q6  a saúde: a chave explicar zerada; cada violação forçada = 1 e o ok cai; a porta
--   Q7  reserva nunca conta (na cobertura e nos dias perdidos)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_placar.sql
--   Seguro em produção: termina em ROLLBACK. O que usa o cenário ou a migration como texto só roda na bancada (fora dela sai PULADO).
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
-- Uma consulta como um papel (e um login): o texto que volta ou "erro <sqlstate>: <mensagem>" (o molde de agenda_fase7g_correcoes.sql).
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
-- O corpo de uma função no texto de uma migration (o prosrc) e o corpo sem as marcas da 7g (linha a linha: "-- FASE 7g:" … "-- FASE 7g: fim" e "-- (7g …"
-- … "-- (7g: fim)", as linhas de abrir e de fechar saem junto).
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.sem7g(p text) returns text language plpgsql immutable as $f$
declare
  l      text;
  fora   text[] := '{}';
  dentro boolean := false;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not dentro and l ~ '^\s*-- (FASE 7g:|\(7g )' and l !~ '^\s*-- (FASE 7g: fim|\(7g: fim\))' then dentro := true; continue; end if;
    if dentro then
      if l ~ '^\s*-- (FASE 7g: fim|\(7g: fim\))' then dentro := false; end if;
      continue;
    end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;

-- O cenário: ids pelo md5 de '7g6:…'.
create function pg_temp.o(p_n text) returns uuid language sql immutable as $f$ select md5('7g6:os:' || p_n)::uuid $f$;
create function pg_temp.p(p_n text) returns uuid language sql immutable as $f$ select md5('7g6:payee:' || p_n)::uuid $f$;
create function pg_temp.nova_os(p_n text) returns uuid language plpgsql as $f$
declare
  v_os  uuid := pg_temp.o(p_n);
  v_cli uuid := md5('7g6:cli:' || p_n)::uuid;
  v_bem uuid := md5('7g6:bem:' || p_n)::uuid;
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', 'Cliente ' || p_n);
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at)
  values (v_os, 'OS-Q' || p_n, v_cli, v_bem, 'open', 'approved', 'repair', timestamptz '2027-02-15 10:00-03', timestamptz '2027-02-15 10:00-03',
          timestamptz '2027-02-16 09:00-03');
  insert into public.payees (id, name, kind, active) values (pg_temp.p(p_n), 'Teo ' || p_n, 'prestador', true);
  return v_os;
end $f$;
-- Uma ação executada na OS p_n (a zona e o degrau gravados, como o gatilho do P2 os deixa).
create function pg_temp.acao(p_k text, p_n text, p_origem text, p_tipo text, p_em timestamptz, p_zona text default null, p_degrau text default null,
                             p_criadas uuid[] default '{}') returns uuid language plpgsql as $f$
declare
  v_id uuid := md5('7g6:acao:' || p_k)::uuid;
begin
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas,
                                   antes, depois, texto, zona, degrau)
  values (v_id, p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, p_origem, p_tipo, pg_temp.o(p_n), array[pg_temp.o(p_n)], p_criadas, '{}',
          '{}'::jsonb, '{}'::jsonb, 'Ação de teste ' || p_k, p_zona, p_degrau);
  return v_id;
end $f$;
-- Uma marcação como o P5 a grava (a ação dela também): quem, quando marcou, quando aprovou, o 1º dia, o desfecho, os ajustes, conferida, a classe.
create function pg_temp.marc(p_k text, p_n text, p_quem text, p_em timestamptz, p_aprov timestamptz, p_de date, p_desf text, p_desf_em timestamptz,
                             p_ajustes text[] default '{}', p_conf boolean default false, p_classe text default 'rv:energia') returns void language plpgsql as $f$
declare
  v_a uuid := pg_temp.acao(p_k, p_n, case when p_quem = 'dono' then 'dono' else 'vigia' end, 'criar', p_em);
begin
  insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, duracao_fonte, de, ate, meios, pessoas, marcada_em,
                                       primeiro_inicio, aprovada_em, desfecho, ajustes, desfecho_em, conferida)
  values (v_a, pg_temp.o(p_n), p_quem, case when p_quem = 'dono' then 'dono' else 'vigia' end, 'criar', p_classe, 'orcamento', p_de, p_de, 2,
          array[pg_temp.p(p_n)], p_em, (p_de::timestamp + interval '8 hours') at time zone 'America/Sao_Paulo', p_aprov, p_desf, p_ajustes, p_desf_em, p_conf);
end $f$;
-- Um meio-dia publicado da pessoa da OS p_n (publicado bem antes), com o resultado e o motivo.
create function pg_temp.meio(p_k text, p_n text, p_dia date, p_turno text, p_tipo text default 'execucao', p_res text default null, p_motivo text default null)
returns uuid language plpgsql as $f$
declare
  v_id uuid := md5('7g6:aloc:' || p_k)::uuid;
begin
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em,
                                       duracao_fonte, criterio, criado_em, resultado, motivo, resultado_em)
  values (v_id, pg_temp.o(p_n), pg_temp.p(p_n), p_dia, p_turno, 'turno', p_tipo, case when p_tipo = 'reserva' then 'teto' end, 'publicada', 'motor',
          timestamptz '2027-02-20 10:00-03', 'orcamento', 'unico', timestamptz '2027-02-20 10:00-03', p_res, p_motivo,
          case when p_res is not null then (p_dia::timestamp + interval '18 hours') at time zone 'America/Sao_Paulo' end);
  return v_id;
end $f$;

create function pg_temp.cenario_q() returns void language plpgsql as $f$
begin
  -- o dia de quem age (o resultado é de dia que já chegou: _agenda_hoje)
  perform set_config('agenda.hoje', '2027-03-11', true);
  perform pg_temp.nova_os(n) from unnest(array['m1', 'm2', 'm3', 'm4', 'm5', 'm6', 'm7', 'z', 'x', 'y', 'w', 'e1', 'e2', 'e3', 'e4', 'e5', 'c', 'r']) n;
  -- as marcações (o período é de 01 a 06/03/2027)
  perform pg_temp.marc('m1', 'm1', 'gestor', timestamptz '2027-03-01 09:00-03', timestamptz '2027-03-01 08:48-03', date '2027-03-04', 'aceita',
                       timestamptz '2027-03-04 08:00-03', '{}', true);
  perform pg_temp.marc('m1b', 'm1', 'gestor', timestamptz '2027-03-03 11:00-03', timestamptz '2027-03-01 08:48-03', date '2027-03-09', 'aberta', null);
  perform pg_temp.marc('m2', 'm2', 'gestor', timestamptz '2027-03-02 10:00-03', timestamptz '2027-03-02 09:51-03', date '2027-03-05', 'aceita',
                       timestamptz '2027-03-05 08:00-03');
  perform pg_temp.marc('m3', 'm3', 'gestor', timestamptz '2027-03-03 10:00-03', null, date '2027-03-08', 'ajustada', timestamptz '2027-03-04 15:00-03',
                       '{dia}', false, 'rv:conforto');
  perform pg_temp.marc('m4', 'm4', 'gestor', timestamptz '2027-02-22 10:00-03', null, date '2027-03-02', 'desfeita', timestamptz '2027-03-01 10:00-03');
  perform pg_temp.marc('m5', 'm5', 'gestor', timestamptz '2027-02-23 10:00-03', null, date '2027-03-03', 'remarcada', timestamptz '2027-03-02 10:00-03');
  perform pg_temp.marc('m6', 'm6', 'dono', timestamptz '2027-03-03 12:00-03', null, date '2027-03-10', null, null);
  perform pg_temp.marc('m7', 'm7', 'gestor', timestamptz '2027-03-04 10:00-03', null, date '2027-03-15', 'aberta', null);
  -- as ações que mexeram no plano, com a zona gravada
  perform pg_temp.acao('z1', 'z', 'vigia', 'mover', timestamptz '2027-03-02 10:00-03', 'firme', 'pessoa');
  perform pg_temp.acao('z2', 'z', 'vigia', 'mover', timestamptz '2027-03-03 10:00-03', 'livre', 'dia');
  perform pg_temp.acao('z3', 'z', 'motor', 'reparar', timestamptz '2027-03-04 10:00-03', 'livre', 'data');
  perform pg_temp.acao('z4', 'z', 'vigia', 'mover', timestamptz '2027-03-04 11:00-03', 'travada', 'dia');      -- desfeita: não conta
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, desfaz_a)
  values (md5('7g6:acao:z4d')::uuid, timestamptz '2027-03-04 12:00-03', date '2027-03-04', true, 'dono', 'desfazer', pg_temp.o('z'), array[pg_temp.o('z')],
          'Desfeito: teste', md5('7g6:acao:z4')::uuid);
  update public.agenda_acoes set desfeita_em = timestamptz '2027-03-04 12:00-03', desfeita_pela = md5('7g6:acao:z4d')::uuid where id = md5('7g6:acao:z4')::uuid;
  perform pg_temp.acao('z5', 'z', 'vigia', 'publicar', timestamptz '2027-03-04 13:00-03', 'firme', null);      -- publicar: não conta
  perform pg_temp.acao('z6', 'z', 'cliente', 'mover', timestamptz '2027-03-04 14:00-03', 'travada', 'dia');    -- do cliente: não conta
  perform pg_temp.acao('z7', 'z', 'dono', 'mover', timestamptz '2027-03-04 15:00-03', 'travada', 'dia');       -- do dono: não conta
  perform pg_temp.acao('z8', 'z', 'vigia', 'mover', timestamptz '2027-03-08 10:00-03', 'travada', 'dia');      -- fora do período
  -- os meios-dias: X cumpriu 01/03; Y não cumpriu 02/03 (chuva) e cumpriu em parte 03/03 (ferramenta); W sem conferência 04/03; a reserva de Y com chuva
  perform pg_temp.meio('x1', 'x', date '2027-03-01', 'manha', 'execucao', 'cumprido');
  perform pg_temp.meio('x2', 'x', date '2027-03-01', 'tarde', 'execucao', 'cumprido');
  perform pg_temp.meio('y1', 'y', date '2027-03-02', 'manha', 'execucao', 'nao_cumprido', 'clima');
  perform pg_temp.meio('y2', 'y', date '2027-03-03', 'manha', 'execucao', 'parcial', 'ferramenta');
  perform pg_temp.meio('w1', 'w', date '2027-03-04', 'manha', 'execucao');
  perform pg_temp.meio('r1', 'r', date '2027-03-05', 'tarde', 'reserva', 'nao_cumprido', 'clima');
  -- a medida da 7e: 3 no período (1,00; 1,25; 1,50), 1 sem razão (motivo_razao), 1 nas 8 semanas (2,00)
  insert into public.agenda_medidas_os (service_order_id, classe_bem, classe_sistema, concluida_em, valida, medida_em, razao_estimativa, motivo_razao)
  values (pg_temp.o('e1'), 'rv', 'energia', date '2027-03-02', true, timestamptz '2027-03-02 18:00-03', 1.00, null),
         (pg_temp.o('e2'), 'rv', 'energia', date '2027-03-03', true, timestamptz '2027-03-03 18:00-03', 1.25, null),
         (pg_temp.o('e3'), 'rv', 'energia', date '2027-03-05', true, timestamptz '2027-03-05 18:00-03', 1.50, null),
         (pg_temp.o('e4'), 'rv', 'energia', date '2027-03-04', true, timestamptz '2027-03-04 18:00-03', null, 'sem_inicio'),
         (pg_temp.o('e5'), 'rv', 'energia', date '2027-01-20', true, timestamptz '2027-01-20 18:00-03', 2.00, null);
  -- os itens com o "compre até": 3 críticos no período (1 no prazo, 1 atrasado, 1 sem comprar), 1 não crítico, 1 fora do período
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, critico, compre_ate, comprado_em, compre_ate_base)
  select x.id, pg_temp.o('c'), 'dono', x.d, 1, x.cr, x.ca, x.co, '{"teste": true}'::jsonb
    from (values (md5('7g6:mat:1')::uuid, 'Inversor', true, date '2027-03-02', date '2027-03-01'),
                 (md5('7g6:mat:2')::uuid, 'Bateria', true, date '2027-03-03', date '2027-03-04'),
                 (md5('7g6:mat:3')::uuid, 'Cabo', true, date '2027-03-05', null::date),
                 (md5('7g6:mat:4')::uuid, 'Abraçadeira', false, date '2027-03-02', null),
                 (md5('7g6:mat:5')::uuid, 'Fusível', true, date '2027-03-10', null)) x(id, d, cr, ca, co);
  -- a fila (só contagem; o texto é de teste): ao dono 3 (agenda-dono 2, o acorde 1), à equipe 1, a clientes 2 (agenda-confirmacao é do cliente), ao fornecedor 1;
  -- o R10 e o manual não são da agenda; 1 ao dono fora do período. As linhas entram sem os gatilhos da fila (as travas de quem pode pôr na fila: aqui só se
  -- conta o que já está nela)
  set local session_replication_role = replica;
  insert into public.whatsapp_send_queue (phone_normalized, message, source, status, created_at, sent_at)
  select '5547999990000', 'teste', s, 'sent', e, e
    from (values ('agenda-dono', timestamptz '2027-03-01 17:00-03'), ('agenda-dono', timestamptz '2027-03-04 17:00-03'),
                 ('agenda', timestamptz '2027-03-02 09:00-03'), ('agenda-equipe', timestamptz '2027-03-03 07:00-03'),
                 ('agenda-cliente', timestamptz '2027-03-03 10:00-03'), ('agenda-confirmacao', timestamptz '2027-03-05 10:00-03'),
                 ('agenda-fornecedor', timestamptz '2027-03-05 11:00-03'), ('agenda-r10', timestamptz '2027-03-05 07:00-03'),
                 ('manual', timestamptz '2027-03-05 08:00-03'), ('agenda-dono', timestamptz '2027-03-08 17:00-03')) t(s, e);
  set local session_replication_role = origin;
  -- os tipos de OS (P5): energia em teste esperaria o ok; conforto fica sozinho
  insert into public.agenda_tipos_os (classe, nivel, teria, n, corrigidas, calculado_em, texto)
  values ('rv:energia', 'sozinho', 'espera_ok', 4, 3, timestamptz '2027-03-04 16:40-03',
          'Em teste: nas OS de energia em motorhome eu passaria a esperar o seu ok (você corrigiu 3 de 4).'),
         ('rv:conforto', 'sozinho', 'sozinho', 1, 1, timestamptz '2027-03-04 16:40-03', null)
  on conflict (classe) do update set nivel = excluded.nivel, teria = excluded.teria, texto = excluded.texto;
end $f$;

-- Os números do §6.5 (o exemplo) e os do "sem dado" (o freio, nada na semana).
create function pg_temp.n_exemplo() returns jsonb language sql immutable as $f$
  select '{"freio": false, "cobertura": {"prontas": 10, "com_data": 8, "pct": 80},
           "aprovacao": {"n": 3, "du_mediana": 4, "gestor_n": 3, "minutos_mediana": 12},
           "marcacoes": {"gestor": 6, "dono": 1},
           "correcoes": {"aceita": 4, "ajustada": 1, "desfeita": 1, "conferidas": 0,
                         "ajustes": {"duracao": 0, "pessoa": 0, "dia": 1, "tirou": 0, "material": 0}, "por_classe": {}},
           "zonas": {"travada": 0, "firme": 2, "livre": 3, "firme_du": 10, "degraus": {"pessoa": 1, "turno": 0, "dia": 2, "data": 1, "tirou": 0}},
           "ppc": {"compromissos": 10, "cumpridos": 8, "conferidos": 10, "ppc": 0.8},
           "estimativa": {"n": 3, "mediana": 1.25, "ate_8_semanas": {"n": 3, "mediana": 1.25}},
           "compras": {"com_prazo": 4, "no_prazo": 3, "vencidas": 1},
           "perguntas": {"abertas": 4, "idade_max_du": 3, "idade_media_du": 2, "assumidas": 1, "respondidas": 2},
           "mensagens": {"dono": 12, "equipe": 5, "cliente": 2, "fornecedor": 0, "dias_uteis": 5, "por_dia": {"dono": 2.4, "equipe": 1, "cliente": 0.4}},
           "perdidos": {"clima_meios": 2, "ferramenta_meios": 1},
           "tipos": {"espera_ok": [], "teria": [{"classe": "rv:energia", "texto": "Em teste: nas OS de energia em motorhome eu passaria a esperar o seu ok (você corrigiu 3 de 4)."}]},
           "incompleto": false}'::jsonb
$f$;
create function pg_temp.n_vazio() returns jsonb language sql immutable as $f$
  select '{"freio": true, "cobertura": {"prontas": 0, "com_data": 0, "pct": null},
           "aprovacao": {"n": 0, "du_mediana": null, "gestor_n": 0, "minutos_mediana": null},
           "marcacoes": {"gestor": 0, "dono": 0},
           "correcoes": {"aceita": 0, "ajustada": 0, "desfeita": 0, "conferidas": 0,
                         "ajustes": {"duracao": 0, "pessoa": 0, "dia": 0, "tirou": 0, "material": 0}, "por_classe": {}},
           "zonas": {"travada": 0, "firme": 0, "livre": 0, "firme_du": 10, "degraus": {"pessoa": 0, "turno": 0, "dia": 0, "data": 0, "tirou": 0}},
           "ppc": {"compromissos": 0, "cumpridos": 0, "conferidos": 0, "ppc": null},
           "estimativa": {"n": 0, "mediana": null, "ate_8_semanas": {"n": 0, "mediana": null}},
           "compras": {"com_prazo": 0, "no_prazo": 0, "vencidas": 0},
           "perguntas": {"abertas": 0, "idade_max_du": null, "idade_media_du": null, "assumidas": 0, "respondidas": 0},
           "mensagens": {"dono": 0, "equipe": 0, "cliente": 0, "fornecedor": 0, "dias_uteis": 5, "por_dia": {"dono": 0, "equipe": 0, "cliente": 0}},
           "perdidos": {"clima_meios": 0, "ferramenta_meios": 0}, "tipos": {"espera_ok": [], "teria": []}, "incompleto": false}'::jsonb
$f$;
-- O que a 1ª quinta diria hoje (R9.4-3): 3 linhas com dado, o mínimo.
create function pg_temp.n_tres() returns jsonb language sql immutable as $f$
  select pg_temp.n_vazio() || '{"freio": false, "cobertura": {"prontas": 5, "com_data": 1, "pct": 20}, "compras": {"com_prazo": 7, "no_prazo": 4, "vencidas": 3},
                                "perguntas": {"abertas": 7, "idade_max_du": 5, "idade_media_du": 3, "assumidas": 0, "respondidas": 0}}'::jsonb
$f$;

-- ── Q0. O catálogo e a migration ─────────────────────────────────────────────────────────────────────
do $q0$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
  v_mig text := coalesce(current_setting('agenda_teste.mig_placar_fase7g', true), '');
  x     record;
begin
  select string_agg(p.proname || ':' || p.provolatile::text || ':' || case when p.prosecdef then 'definer' else 'invoker' end
                    || ':' || case when coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%' then 'sp' else 'sem_sp' end,
                    ',' order by p.proname collate "C") into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_agenda_placar_periodo', '_agenda_mensagens_da_agenda', '_agenda_placar_numeros', '_agenda_placar_texto', 'agenda_placar',
                       '_agenda_explicar_placar', '_agenda_saude_explicar');
  v_res := pg_temp.igual(v_res, 'Q0a as 7 novas: a leitura e a saúde definer; o guardado volátil; o texto IMMUTABLE; o resto STABLE; todas com search_path', v,
    '_agenda_explicar_placar:v:invoker:sp,_agenda_mensagens_da_agenda:s:invoker:sp,_agenda_placar_numeros:s:invoker:sp,_agenda_placar_periodo:s:invoker:sp,'
    || '_agenda_placar_texto:i:invoker:sp,_agenda_saude_explicar:s:definer:sp,agenda_placar:s:definer:sp');
  select string_agg(f || ':' || r, ',' order by f collate "C", r collate "C") into v
    from unnest(array['public._agenda_placar_periodo(date, date)', 'public._agenda_mensagens_da_agenda(date, date)', 'public._agenda_placar_numeros(date, date, date)',
                      'public._agenda_placar_texto(jsonb, date, date, text, integer)', 'public._agenda_explicar_placar(date, timestamptz)',
                      'public.agenda_placar(date, date, timestamptz)', 'public._agenda_saude_explicar(date, timestamptz)']) f,
         unnest(array['anon', 'authenticated', 'service_role']) r
   where has_function_privilege(r, f, 'execute');
  v_res := pg_temp.igual(v_res, 'Q0b as portas: anon nenhuma; authenticated só a leitura e a saúde (definer, porta dentro); service_role as 7', v,
    'public._agenda_explicar_placar(date, timestamptz):service_role,public._agenda_mensagens_da_agenda(date, date):service_role,'
    || 'public._agenda_placar_numeros(date, date, date):service_role,public._agenda_placar_periodo(date, date):service_role,'
    || 'public._agenda_placar_texto(jsonb, date, date, text, integer):service_role,public._agenda_saude_explicar(date, timestamptz):authenticated,'
    || 'public._agenda_saude_explicar(date, timestamptz):service_role,public.agenda_placar(date, date, timestamptz):authenticated,'
    || 'public.agenda_placar(date, date, timestamptz):service_role');
  if v_mig = '' or coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_lote_fase7f', true), '') = '' or coalesce(current_setting('agenda_teste.mig_rodada_fase7e', true), '') = '' then
    v_res := pg_temp.ok(v_res, 'Q0c a migration e as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
  else
    select string_agg(m[1], ',' order by m[1] collate "C") into v
      from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    v_res := pg_temp.igual(v_res, 'Q0c a migration cria as 7 novas e recria só as 6 (sem agenda_bloco_do_fechamento, R9.5-14)', v,
      '_agenda_comunicar_quinta,_agenda_explicar_placar,_agenda_lote_texto,_agenda_mensagens_da_agenda,_agenda_motivo_dito,_agenda_motivo_texto,'
      || '_agenda_placar_numeros,_agenda_placar_periodo,_agenda_placar_texto,_agenda_saude_explicar,agenda_conferir_dia,agenda_placar,agenda_saude');
    for x in select * from (values
        ('_agenda_motivo_dito', 'public._agenda_motivo_dito(text)', 'mig_conferencia_fase2', 1),
        ('_agenda_motivo_texto', 'public._agenda_motivo_texto(text)', 'mig_conferencia_fase2', 1),
        ('agenda_conferir_dia', 'public.agenda_conferir_dia(uuid, text, text, text, text, date, timestamptz)', 'mig_conferencia_fase2', 1),
        ('_agenda_lote_texto', 'public._agenda_lote_texto(jsonb)', 'mig_lote_fase7f', 1),
        ('_agenda_comunicar_quinta', 'public._agenda_comunicar_quinta(date, timestamptz)', 'mig_lote_fase7f', 3),
        ('agenda_saude', 'public.agenda_saude(date, timestamptz)', 'mig_rodada_fase7e', 1)) t(nome, assin, mig, marcas) loop
      v_res := pg_temp.ok(v_res, format('Q0d %s: tirada a marca da 7g, é a origem (%s), byte a byte', x.nome, x.mig),
        char_length(pg_temp.corpo(current_setting('agenda_teste.' || x.mig), x.nome)) > 100
        and pg_temp.sem7g(pg_temp.corpo(v_mig, x.nome)) = replace(pg_temp.corpo(current_setting('agenda_teste.' || x.mig), x.nome), E'\r\n', E'\n'), null);
      v_res := pg_temp.ok(v_res, format('Q0e %s: a viva é a desta migration, com %s marca(s) da 7g', x.nome, x.marcas),
        (select replace(p.prosrc, E'\r\n', E'\n') from pg_proc p where p.oid = x.assin::regprocedure) = pg_temp.corpo(v_mig, x.nome)
        and (select count(*) from regexp_matches(pg_temp.corpo(v_mig, x.nome), '-- (FASE 7g: fim|\(7g: fim\))', 'g')) = x.marcas, null);
    end loop;
    -- em agenda_saude, a marca da 7g vem depois do último "(7e: fim)" e antes de return v_gr (R9.5-17)
    v := pg_temp.corpo(v_mig, 'agenda_saude');
    v_res := pg_temp.ok(v_res, 'Q0f agenda_saude: a linha da 7g depois do último (7e: fim), antes de return v_gr',
      position(E'  -- (7e: fim)\n  -- (7g P6' in v) > 0 and position(E'  -- (7g: fim)\n  return v_gr;' in v) > 0, null);
  end if;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('Q0 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$q0$;

-- ── Q2. O texto e a linha (só a função, com os números dados) ─────────────────────────────────────────
do $q2$
declare
  v_res jsonb := '[]'::jsonb;
  c_de  constant date := date '2026-11-09';
  c_ate constant date := date '2026-11-14';
  c_tit constant text := 'Placar da semana de 09 a 14/11 (números do sistema):';
  c_ex  constant text[] := array[
    '• Serviços prontos com data firme: 8 de 10 (80%). Da aprovação à data: 4 dias úteis (3 OS); marquei em 12 minutos depois de aprovar.',
    '• Marquei 6, você marcou 1. Das minhas: 4 ficaram como fiz (nenhuma conferida), 1 você ajustou (o dia), 1 você desfez.',
    '• Mudanças: nenhuma em dia já avisado, 2 nos próximos 10 dias úteis, 3 mais à frente.',
    '• Plano cumprido: 8 de 10 dias de serviço (80%).',
    '• O real ficou em 1,3× o que estimei (3 OS concluídas).',
    '• Compras: 3 de 4 feitas até o "compre até".',
    '• Perguntas abertas: 4 (a mais antiga com 3 dias úteis).',
    '• Mensagens por dia: 2,4 a você, 1 à equipe, 0,4 a clientes.',
    '• Dias perdidos: chuva 1 dia, ferramenta ou carro meio dia.',
    '• Em teste: nas OS de energia em motorhome eu passaria a esperar o seu ok (você corrigiu 3 de 4).'];
  v_c   jsonb;
  v_m   jsonb;
  v     jsonb;
  v_t   text;
begin
  -- Q2a o exemplo do §6.5, completo e mensagem, byte a byte; a linha do §6.5; 9 linhas com dado (sem as mensagens)
  v_c := public._agenda_placar_texto(pg_temp.n_exemplo(), c_de, c_ate, 'completo', 1000);
  v_m := public._agenda_placar_texto(pg_temp.n_exemplo(), c_de, c_ate, 'mensagem', 1000);
  v_res := pg_temp.igual(v_res, 'Q2a o texto completo do exemplo do §6.5, byte a byte', v_c ->> 'texto', array_to_string(c_tit || c_ex, E'\n'));
  v_res := pg_temp.igual(v_res, 'Q2b a mensagem: as mesmas linhas (todas com dado) e "Detalhe em *agenda placar*." no fim', v_m ->> 'texto',
    array_to_string(c_tit || c_ex || 'Detalhe em *agenda placar*.'::text, E'\n'));
  v_res := pg_temp.igual(v_res, 'Q2c a linha do §6.5, byte a byte (≤ 300)', v_c ->> 'linha',
    'Placar 09 a 14/11: 8 de 10 prontos com data; marquei 6, você corrigiu 2; plano cumprido 80%; compras 3 de 4 no prazo. Detalhe em *agenda placar*.');
  v_res := pg_temp.ok(v_res, 'Q2d 9 linhas com dado (as mensagens não contam para o mínimo, R9.4-3); a mesma linha nos 2 modos',
    (v_c ->> 'linhas')::int = 9 and (v_m ->> 'linhas')::int = 9 and v_c ->> 'linha' = v_m ->> 'linha', v_c ->> 'linhas');
  -- Q2e o sem dado: o freio na 1ª linha; no completo, todas as linhas com o "sem dado"; na mensagem, só o freio; 0 linhas com dado; a linha sem números
  v_c := public._agenda_placar_texto(pg_temp.n_vazio(), c_de, c_ate, 'completo', 1000);
  v_m := public._agenda_placar_texto(pg_temp.n_vazio(), c_de, c_ate, 'mensagem', 1000);
  v_res := pg_temp.igual(v_res, 'Q2e o completo sem dado, com o freio na 1ª linha (R9.4-3), byte a byte', v_c ->> 'texto', array_to_string(array[c_tit,
    '• Com *gestor, só propor*, não marquei nada sozinho nesta semana.', '• Serviços prontos com data firme: nenhum serviço pronto.',
    '• Marcações: nenhuma na semana.', '• Mudanças: nenhuma na semana.', '• Plano cumprido: sem dia marcado firme na semana.',
    '• O real × estimado: nenhuma OS concluída medida.', '• Compras: nenhum "compre até" na semana.', '• Perguntas abertas: nenhuma.',
    '• Mensagens: nenhuma da agenda na semana.', '• Dias perdidos: nenhum por chuva nem por ferramenta ou carro.'], E'\n'));
  v_res := pg_temp.ok(v_res, 'Q2f a mensagem sem dado: só o freio (a linha sem dado sai, R9.4-3); 0 linhas com dado; a linha diz que não há números',
    v_m ->> 'texto' = array_to_string(array[c_tit, '• Com *gestor, só propor*, não marquei nada sozinho nesta semana.', 'Detalhe em *agenda placar*.'], E'\n')
    and (v_m ->> 'linhas')::int = 0 and v_m ->> 'linha' = 'Placar 09 a 14/11: sem números na semana. Detalhe em *agenda placar*.', v_m::text);
  -- Q2g sem o freio, sem a 1ª linha; com o freio e uma marcação minha, também sem (não diria o que não aconteceu, R9.12-9)
  v_t := public._agenda_placar_texto(pg_temp.n_vazio() || '{"freio": false}', c_de, c_ate, 'completo', 1000) ->> 'texto';
  v := public._agenda_placar_texto(pg_temp.n_vazio() || '{"marcacoes": {"gestor": 1, "dono": 0}}', c_de, c_ate, 'completo', 1000);
  v_res := pg_temp.ok(v_res, 'Q2g o freio só sem marcação minha: sem o freio, ou com 1 marcação minha, a linha do freio não aparece',
    position('gestor, só propor' in v_t) = 0 and position('gestor, só propor' in (v ->> 'texto')) = 0 and position('• Marquei 1.' in (v ->> 'texto')) > 0, v ->> 'texto');
  -- Q2h o erro numa chave: "não consegui contar agora" no completo; fora da mensagem; incompleto não muda o resto
  v_c := public._agenda_placar_texto(pg_temp.n_exemplo() || '{"compras": {"erro": true}, "incompleto": true}', c_de, c_ate, 'completo', 1000);
  v_m := public._agenda_placar_texto(pg_temp.n_exemplo() || '{"compras": {"erro": true}, "incompleto": true}', c_de, c_ate, 'mensagem', 1000);
  v_res := pg_temp.ok(v_res, 'Q2h o erro numa chave: "Compras: não consegui contar agora." no completo, fora da mensagem e da linha; 8 linhas com dado',
    position('• Compras: não consegui contar agora.' in (v_c ->> 'texto')) > 0 and position('Compras' in (v_m ->> 'texto')) = 0
    and position('compras' in (v_c ->> 'linha')) = 0 and (v_c ->> 'linhas')::int = 8, v_c::text);
  -- Q2i o corte de baixo para cima: tipos, mensagens, perguntas, dias perdidos, compras, estimativa…; nunca a cobertura nem as marcações
  v_t := array_to_string(c_tit || c_ex[1:9] || 'Detalhe em *agenda placar*.'::text, E'\n');
  v_m := public._agenda_placar_texto(pg_temp.n_exemplo(), c_de, c_ate, 'mensagem', char_length(v_t));
  v_res := pg_temp.igual(v_res, 'Q2i passou do teto por pouco: sai a linha dos tipos, e só ela', v_m ->> 'texto', v_t);
  v_t := array_to_string(c_tit || c_ex[1:6] || c_ex[9:9] || 'Detalhe em *agenda placar*.'::text, E'\n');
  v_m := public._agenda_placar_texto(pg_temp.n_exemplo(), c_de, c_ate, 'mensagem', char_length(v_t));
  v_res := pg_temp.igual(v_res, 'Q2j mais curto: saem os tipos, as mensagens e as perguntas (os dias perdidos ficam, na ordem do §6.5)', v_m ->> 'texto', v_t);
  v_m := public._agenda_placar_texto(pg_temp.n_exemplo(), c_de, c_ate, 'mensagem', 400);
  v_res := pg_temp.ok(v_res, 'Q2k no menor teto do texto (400): ficam a cobertura e as marcações; cabe; as linhas com dado continuam 9 (o mínimo não depende do corte)',
    char_length(v_m ->> 'texto') <= 400 and position(c_ex[1] in (v_m ->> 'texto')) > 0 and position(c_ex[2] in (v_m ->> 'texto')) > 0
    and position('Compras' in (v_m ->> 'texto')) = 0 and (v_m ->> 'linhas')::int = 9, v_m ->> 'texto');
  -- Q2l o que a 1ª quinta diria hoje (R9.4-3): 3 linhas, o mínimo
  v_m := public._agenda_placar_texto(pg_temp.n_tres(), c_de, c_ate, 'mensagem', 1000);
  v_res := pg_temp.igual(v_res, 'Q2l o que a 1ª quinta diria hoje (R9.4-3): 3 linhas com dado, a mensagem só com elas',
    (v_m ->> 'texto') || ' | ' || (v_m ->> 'linhas'),
    array_to_string(array[c_tit, '• Serviços prontos com data firme: 1 de 5 (20%).', '• Compras: 4 de 7 feitas até o "compre até".',
                          '• Perguntas abertas: 7 (a mais antiga com 5 dias úteis).', 'Detalhe em *agenda placar*.'], E'\n') || ' | 3');
  -- Q2m o mês diferente no título; a linha nunca passa de 300; o modo errado = 22023
  v_t := public._agenda_placar_texto(pg_temp.n_vazio(), date '2026-10-26', date '2026-10-31', 'completo', 1000) ->> 'texto';
  v_res := pg_temp.ok(v_res, 'Q2m o título com o mês de cada lado quando muda (28/10 a 02/11); dentro do mês, só no fim',
    left(public._agenda_placar_texto(pg_temp.n_vazio(), date '2026-10-28', date '2026-11-02', 'completo', 1000) ->> 'texto', 55)
      = 'Placar da semana de 28/10 a 02/11 (números do sistema):' and left(v_t, 52) = 'Placar da semana de 26 a 31/10 (números do sistema):', v_t);
  begin
    perform public._agenda_placar_texto(pg_temp.n_vazio(), c_de, c_ate, 'outro', 1000);
    v_res := pg_temp.ok(v_res, 'Q2n o modo fora de mensagem e completo = 22023', false, 'passou');
  exception when sqlstate '22023' then
    v_res := pg_temp.ok(v_res, 'Q2n o modo fora de mensagem e completo = 22023', true, null);
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('Q2 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$q2$;

-- ── Q1, Q3 e Q7. Os números, o guardado e a reserva ─────────────────────────────────────────────────
do $q1$
declare
  v_res   jsonb := '[]'::jsonb;
  c_de    constant date := date '2027-03-01';
  c_ate   constant date := date '2027-03-06';
  c_hoje  constant date := date '2027-03-11';
  v       jsonb;
  v0      jsonb;
  v1      jsonb;
  v_r     jsonb;
  v_n     int;
  v_os    uuid;
  i       int := 0;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(jsonb_build_array(jsonb_build_array('Q1 os números', true, 'PULADO: fora da bancada (rode pela bancada)')));
    return;
  end if;
  begin
    perform pg_temp.cenario_q();
    update public.agenda_config set gestor_so_propor = false, placar_janela = 'semana_passada' where id;
    v := public._agenda_placar_numeros(c_de, c_ate, c_hoje);
    -- Q1a as marcações: 5 minhas no período (m1, a 2ª de m1, m2, m3, m7), 1 do dono; m4 e m5 são de antes
    v_res := pg_temp.igual(v_res, 'Q1a marcacoes: 5 minhas e 1 do dono marcadas no período', (v -> 'marcacoes')::text, '{"dono": 1, "gestor": 5}');
    -- Q1b o que o dono corrigiu: aceitas 2 (1 conferida), ajustada 1 (o dia), desfeita 1; a remarcada não conta; por classe
    v_res := pg_temp.igual(v_res, 'Q1b correcoes: as minhas decididas no período (a remarcada fora), conferidas = as aceitas com meio-dia conferido, por classe',
      (v -> 'correcoes')::text,
      '{"aceita": 2, "ajustes": {"dia": 1, "tirou": 0, "pessoa": 0, "duracao": 0, "material": 0}, "ajustada": 1, "desfeita": 1, "conferidas": 1, '
      || '"por_classe": {"rv:energia": {"n": 3, "corrigidas": 1}, "rv:conforto": {"n": 1, "corrigidas": 1}}}');
    -- Q1c da aprovação à data: o 1º da OS (a 2ª marcação de m1 fora); 3 dias úteis; 10,5 minutos (12 e 9); nada arredondado
    v_res := pg_temp.igual(v_res, 'Q1c aprovacao: só a 1ª marcação de cada OS; dias úteis da aprovação ao 1º dia; os minutos, sem arredondar',
      (v -> 'aprovacao')::text, '{"n": 2, "gestor_n": 2, "du_mediana": 3, "minutos_mediana": 10.5}');
    -- Q1d as zonas: firme 1 (pessoa), livre 2 (dia, data); a desfeita, o publicar, a do cliente, a do dono e a de fora do período não entram
    v_res := pg_temp.igual(v_res, 'Q1d zonas: as minhas ações que mexeram no plano no período (sem publicar, desfeita, cliente nem dono), pela zona e pelo degrau',
      (v -> 'zonas')::text,
      '{"firme": 1, "livre": 2, "degraus": {"dia": 1, "data": 1, "tirou": 0, "turno": 0, "pessoa": 1}, "travada": 0, "firme_du": '
      || (select c.cliente_semana_du from public.agenda_config c where c.id) || '}');
    -- Q1e o plano cumprido pela agenda_ppc: (X, 01) cumprido, (Y, 02) e (Y, 03) não, (W, 04) sem conferência; a reserva fora
    v_res := pg_temp.igual(v_res, 'Q1e ppc: compromissos 4, cumpridos 1, conferidos 3 (o sem conferência fora da conta), ppc = 1/3 sem arredondar',
      (v -> 'ppc')::text, (jsonb_build_object('compromissos', 4, 'cumpridos', 1, 'conferidos', 3, 'ppc', trim_scale(1::numeric / 3)))::text);
    -- Q1f a estimativa da 7e: razao_estimativa com motivo_razao nulo (R9.4-3), não o fator; 3 no período (mediana 1,25) e 4 nas 8 semanas (1,375)
    v_res := pg_temp.igual(v_res, 'Q1f estimativa: razao_estimativa com motivo_razao nulo; a mediana no período e nas 8 semanas, sem arredondar',
      (v -> 'estimativa')::text, '{"n": 3, "mediana": 1.25, "ate_8_semanas": {"n": 4, "mediana": 1.375}}');
    v_res := pg_temp.igual(v_res, 'Q1g compras: os críticos com "compre até" no período (o não crítico e o de fora, não); no prazo = comprado até a data',
      (v -> 'compras')::text, '{"no_prazo": 1, "vencidas": 2, "com_prazo": 3}');
    v_res := pg_temp.igual(v_res, 'Q1h mensagens pelo source (R9.5-12): agenda-confirmacao é do cliente, o acorde é do dono; R10 e manual fora; por dia útil (5)',
      (v -> 'mensagens')::text,
      '{"dono": 3, "equipe": 1, "cliente": 2, "por_dia": {"dono": 0.6, "equipe": 0.2, "cliente": 0.4}, "enviadas": {"dono": 3, "equipe": 1, "cliente": 2, "fornecedor": 1}, '
      || '"dias_uteis": 5, "fornecedor": 1}');
    v_res := pg_temp.igual(v_res, 'Q1i perdidos: chuva 1 meio-dia (não cumprido), ferramenta meio meio-dia (parcial); a reserva com chuva não conta (Q7)',
      (v -> 'perdidos')::text, '{"clima_meios": 1, "ferramenta_meios": 0.5}');
    v_res := pg_temp.igual(v_res, 'Q1j tipos: a classe que em teste esperaria o ok, com o texto do P5; nenhuma em espera (o nível é do P5b)',
      (v -> 'tipos' -> 'teria')::text || ' ' || (v -> 'tipos' -> 'espera_ok')::text,
      '[{"texto": "Em teste: nas OS de energia em motorhome eu passaria a esperar o seu ok (você corrigiu 3 de 4).", "classe": "rv:energia"}] []');
    v_res := pg_temp.ok(v_res, 'Q1k o freio e o incompleto: sem freio, nada falhou', v ->> 'freio' = 'false' and v ->> 'incompleto' = 'false', v::text);
    -- Q1l as perguntas pela diferença: 2 abertas em ligado (uma de 03/03), a conferência e a em sombra não contam
    v0 := v -> 'perguntas';
    perform public._agenda_vigia_perguntar('estouro', '7g6:q1', pg_temp.o('m1'), null, null, null, 'Pergunta de teste um.', 'ligado', timestamptz '2027-03-03 10:00-03');
    perform public._agenda_vigia_perguntar('estouro', '7g6:q2', pg_temp.o('m2'), null, null, null, 'Pergunta de teste dois.', 'ligado', timestamptz '2027-03-10 10:00-03');
    perform public._agenda_vigia_perguntar('conferencia', '7g6:q3', pg_temp.o('m3'), null, date '2027-03-10', null, 'Pergunta de teste três.', 'ligado', timestamptz '2027-03-01 10:00-03');
    perform public._agenda_vigia_perguntar('estouro', '7g6:q4', pg_temp.o('m4'), null, null, null, 'Pergunta de teste quatro.', 'sombra', timestamptz '2027-03-01 10:00-03');
    v1 := public._agenda_placar_numeros(c_de, c_ate, c_hoje) -> 'perguntas';
    v_res := pg_temp.ok(v_res, 'Q1l perguntas: + 2 abertas em ligado (a conferência e a em sombra não); a mais antiga das minhas com 6 dias úteis (03/03 a 11/03)',
      (v1 ->> 'abertas')::int = (v0 ->> 'abertas')::int + 2 and (v1 ->> 'idade_max_du')::int >= 6
      and public.agenda_du_entre(date '2027-03-03', c_hoje) = 6, v0::text || ' → ' || v1::text);

    -- Q7 e a cobertura pela diferença: uma reserva para cada OS da carteira não muda nada; um meio-dia firme dá data a todas as prontas
    v0 := public._agenda_placar_numeros(c_de, c_ate, c_hoje) -> 'cobertura';
    for v_os in select c.service_order_id from public.os_carteira(c_hoje) c order by c.service_order_id loop
      i := i + 1;
      insert into public.payees (id, name, kind, active) values (md5('7g6:cob:' || i)::uuid, 'Cob ' || i, 'prestador', true);
      insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, duracao_fonte,
                                           criterio, criado_em)
      values (md5('7g6:cobr:' || i)::uuid, v_os, md5('7g6:cob:' || i)::uuid, date '2027-03-15', 'manha', 'turno', 'reserva', 'teto', 'publicada', 'motor',
              timestamptz '2027-03-01 10:00-03', 'orcamento', 'unico', timestamptz '2027-03-01 10:00-03');
    end loop;
    v1 := public._agenda_placar_numeros(c_de, c_ate, c_hoje) -> 'cobertura';
    v_res := pg_temp.ok(v_res, 'Q7a reserva nunca conta como data firme: uma reserva em cada OS da carteira e a cobertura fica igual',
      v1 = v0 and (v0 ->> 'prontas')::int > 0, v0::text || ' → ' || v1::text);
    i := 0;
    for v_os in select c.service_order_id from public.os_carteira(c_hoje) c order by c.service_order_id loop
      i := i + 1;
      insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte, criterio, criado_em)
      values (md5('7g6:cobc:' || i)::uuid, v_os, md5('7g6:cob:' || i)::uuid, date '2027-03-16', 'manha', 'turno', 'execucao', 'publicada', 'motor',
              timestamptz '2027-03-01 10:00-03', 'orcamento', 'unico', timestamptz '2027-03-01 10:00-03');
    end loop;
    v1 := public._agenda_placar_numeros(c_de, c_ate, c_hoje) -> 'cobertura';
    v_res := pg_temp.ok(v_res, 'Q1m cobertura: com um meio-dia firme de p_ate em diante em cada OS, todas as prontas têm data (pct 100); prontas igual',
      (v1 ->> 'prontas') = (v0 ->> 'prontas') and (v1 ->> 'com_data') = (v1 ->> 'prontas') and (v1 ->> 'pct')::numeric = 100, v0::text || ' → ' || v1::text);

    -- Q3 o guardado
    update public.agenda_config set modo_placar = 'desligado' where id;
    v_r := public._agenda_explicar_placar(c_hoje, timestamptz '2027-03-11 16:40-03');
    v_res := pg_temp.ok(v_res, 'Q3a desligado: nada guardado', v_r = '{"guardado": false, "modo": "desligado"}'::jsonb
      and not exists (select 1 from public.agenda_placar_semanas s where s.semana = c_de), v_r::text);
    v_res := pg_temp.igual(v_res, 'Q3b a leitura desligada: {modo: desligado}', public.agenda_placar(null, c_hoje, timestamptz '2027-03-11 16:40-03')::text,
      '{"modo": "desligado"}');
    update public.agenda_config set modo_placar = 'sombra' where id;
    v_r := public._agenda_explicar_placar(c_hoje, timestamptz '2027-03-11 16:40-03');
    v := (select to_jsonb(s) from public.agenda_placar_semanas s where s.semana = c_de);
    v_res := pg_temp.ok(v_res, 'Q3c em sombra, guarda a semana passada (01 a 06/03): versão 1, modo sombra, os números da conta, o texto completo e a linha',
      v_r ->> 'guardado' = 'true' and v ->> 'versao' = '1' and v ->> 'modo' = 'sombra' and v ->> 'de' = '2027-03-01' and v ->> 'ate' = '2027-03-06'
      and v -> 'numeros' = public._agenda_placar_numeros(c_de, c_ate, c_hoje)
      and v ->> 'texto' = public._agenda_placar_texto(v -> 'numeros', c_de, c_ate, 'completo', 1000) ->> 'texto' and v ->> 'enviado_em' is null, v_r::text);
    v_r := public._agenda_explicar_placar(c_hoje, timestamptz '2027-03-11 16:55-03');
    v_res := pg_temp.ok(v_res, 'Q3d 2× = 1×: nada mudou, nada gravado (a mesma versão e a mesma hora)',
      v_r ->> 'igual' = 'true' and (select to_jsonb(s) from public.agenda_placar_semanas s where s.semana = c_de) = v, v_r::text);
    update public.agenda_config set modo_placar = 'ligado' where id;
    v_r := public._agenda_explicar_placar(c_hoje, timestamptz '2027-03-11 17:10-03');
    v1 := (select to_jsonb(s) from public.agenda_placar_semanas s where s.semana = c_de);
    v_res := pg_temp.ok(v_res, 'Q3e mudou (o modo): versão 2 e uma entrada no histórico com a versão de antes',
      v_r ->> 'versao' = '2' and v1 ->> 'versao' = '2' and v1 ->> 'modo' = 'ligado' and jsonb_array_length(v1 -> 'historico') = 1
      and v1 #>> '{historico,0,versao}' = '1' and v1 #>> '{historico,0,modo}' = 'sombra', v1::text);
    -- a leitura: a semana fechada usa o guardado; em sombra, "Em teste: "; o histórico tem as semanas de antes
    update public.agenda_placar_semanas s set numeros = pg_temp.n_exemplo(), versao = 3, calculado_em = timestamptz '2027-03-11 17:20-03',
                                              historico = s.historico || '[{"versao": 2}]'::jsonb where s.semana = c_de;
    v := public.agenda_placar(null, c_hoje, timestamptz '2027-03-11 17:30-03');
    v_res := pg_temp.ok(v_res, 'Q3f a leitura da semana fechada usa os números guardados (os da mensagem), em ligado sem "Em teste"',
      v ->> 'guardado' = 'true' and v -> 'numeros' = pg_temp.n_exemplo() and left(v ->> 'texto', 28) = 'Placar da semana de 01 a 06/' and v ->> 'modo' = 'ligado'
      and (v ->> 'linhas')::int = 9, left(v::text, 300));
    update public.agenda_config set modo_placar = 'sombra' where id;
    v := public.agenda_placar(date '2027-03-08', c_hoje, timestamptz '2027-03-11 17:30-03');
    v_res := pg_temp.ok(v_res, 'Q3g a semana de agora (não fechou): a conta de agora, em sombra com "Em teste: "; o histórico tem a semana guardada de antes',
      v ->> 'guardado' = 'false' and left(v ->> 'texto', 10) = 'Em teste: ' and v ->> 'de' = '2027-03-08' and jsonb_array_length(v -> 'historico') = 1
      and v #>> '{historico,0,semana}' = '2027-03-01', left(v::text, 300));
    -- a rodada explicar chama o passo no dia do plano (P5: _agenda_explicar_placar existindo); fora dele, não
    update public.agenda_config set modo_porque = 'desligado', modo_rebaixar = 'desligado', modo_placar = 'sombra' where id;
    v_r := public.agenda_explicar_rodar(date '2027-03-10', timestamptz '2027-03-10 16:40-03');
    v_res := pg_temp.ok(v_res, 'Q3h a rodada explicar, fora do dia do plano, só com o placar: nada a rodar, sem linha',
      v_r = '{"rodou": false, "nada": true}'::jsonb, v_r::text);
    v_r := public.agenda_explicar_rodar(date '2027-03-18', timestamptz '2027-03-18 16:40-03');
    v_res := pg_temp.ok(v_res, 'Q3i no dia do plano, a rodada roda o passo placar e guarda a semana de 08 a 13/03 (sem erro, 1 linha)',
      v_r ->> 'rodou' = 'true' and (v_r ->> 'erros')::int = 0 and v_r #>> '{contagens,placar,guardado}' = 'true'
      and exists (select 1 from public.agenda_placar_semanas s where s.semana = date '2027-03-08')
      and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = date '2027-03-18') = 1, v_r::text);
    raise exception using errcode = 'PQ001';
  exception when sqlstate 'PQ001' then
    null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('Q1 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$q1$;

-- ── Q4. A quinta (a mensagem própria, R9.5-27) ───────────────────────────────────────────────────────
-- Q4p: a peça placar junta como o montador. As peças e o texto são os MESMOS de _shared/agenda/aviso-do-gestor_test.ts ("placar: o texto é o mesmo que o
-- banco junta…"): os dois lados conferem o mesmo texto, letra a letra.
with p(pecas, placar) as (values
  (jsonb_build_object('avisar', true, 'semana', true, 'rodada', '2026-11-12T20:00:00+00:00', 'dia', '2026-11-12', 'limite', 2400,
     'cabecalho', 'Agenda — o que eu mudei sozinho:',
     'mudancas', jsonb_build_array(
        jsonb_build_object('texto', 'Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava.', 'acao_ids', jsonb_build_array('e513491a-ed1b-4636-9185-44294948343f')),
        jsonb_build_object('texto', 'Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.', 'acao_ids', jsonb_build_array('0b1c6a35-7d0e-4c55-9a51-6f2b8c1d2e30'))),
     'fora', 'Ficou de fora: MP (esperando o sinal).', 'rodape', '*agenda plano* mostra tudo.',
     'perguntas', jsonb_build_object('texto', E'Para a semana que vem preciso de:\n· Decisão 2: O serviço do Giancarlo (lancha, Troca do GPS) não cabe nas 2… Recomendo a opção 1: Passa para a semana seguinte, sem mudar o que já está marcado.\n· Você: Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e… Por enquanto conto você só para abrir e fechar.\n(e mais 3 em *agenda pendências*)\nPode ser um áudio só, citando o nome do cliente.',
                                     'pergunta_ids', jsonb_build_array('6037294c-834c-48b0-9943-6d41d85453ec', 'e452fa40-581c-41af-a037-2adc6297b971'))),
   jsonb_build_object('texto', E'Placar da semana de 02 a 07/11 (números do sistema):\n• Serviços prontos com data firme: 1 de 5 (20%).\n• Compras: 4 de 7 feitas até o "compre até".\n• Perguntas abertas: 7 (a mais antiga com 5 dias úteis).\nDetalhe em *agenda placar*.',
                      'linha', 'Placar 02 a 07/11: 1 de 5 prontos com data; compras 4 de 7 no prazo. Detalhe em *agenda placar*.')))
insert into _resultado
select 'Q4p a peça placar (R9.5-27): _agenda_lote_texto junta como o montador — o corpo, a linha em branco, o placar, a linha em branco e as perguntas; sem a peça, o de antes',
       public._agenda_lote_texto(p.pecas || jsonb_build_object('placar', p.placar))
         = E'Agenda — o que eu mudei sozinho:\n• Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava.\n• Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.\nFicou de fora: MP (esperando o sinal).\n*agenda plano* mostra tudo.\n\n'
           || (p.placar ->> 'texto') || E'\n\n' || (p.pecas #>> '{perguntas,texto}')
       and public._agenda_lote_texto(p.pecas || jsonb_build_object('placar', jsonb_build_object('texto', '  '))) = public._agenda_lote_texto(p.pecas)
       and public._agenda_lote_texto((p.pecas || jsonb_build_object('placar', p.placar)) - 'perguntas')
           = public._agenda_lote_texto(p.pecas - 'perguntas') || E'\n\n' || (p.placar ->> 'texto'),
       public._agenda_lote_texto(p.pecas || jsonb_build_object('placar', p.placar))
  from p;

do $q4$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-11-19';
  c_agora constant timestamptz := timestamptz '2026-11-19 17:00-03';
  c_sem   constant date := date '2026-11-09';
  v0      jsonb;
  v1      jsonb;
  v2      jsonb;
  v_pl    text;
  v_t0    text;
  v_esp   text;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(jsonb_build_array(jsonb_build_array('Q4 a quinta', true, 'PULADO: fora da bancada (rode pela bancada)')));
    return;
  end if;
  begin
    -- a quinta da 7f em sombra (o lote em sombra: quinta_diria), na mensagem própria, com uma pergunta aberta (para ela ter o que dizer)
    update public.agenda_config set dono_semana_aviso = 'propria', modo_lote_dono = 'sombra', modo_placar = 'desligado', placar_min_linhas = 3 where id;
    perform public._agenda_vigia_perguntar('estouro', '7g6:q4:p', null, null, null, null, 'Quantos dias para o serviço de teste?', 'ligado',
                                           timestamptz '2026-11-17 10:00-03');
    -- o placar guardado da semana de 09 a 14/11, com os números do exemplo do §6.5 (9 linhas com dado)
    insert into public.agenda_placar_semanas (semana, de, ate, modo, numeros, texto, linha, calculado_em)
    values (c_sem, c_sem, date '2026-11-14', 'ligado', pg_temp.n_exemplo(), 'texto guardado', 'linha guardada', timestamptz '2026-11-19 16:40-03');
    v_pl := public._agenda_placar_texto(pg_temp.n_exemplo(), c_sem, date '2026-11-14', 'mensagem', (select c.texto_max from public.agenda_config c where c.id)) ->> 'texto';
    v0 := public._agenda_comunicar_quinta(c_hoje, c_agora);
    v_t0 := v0 #>> '{quinta_diria,texto}';
    update public.agenda_config set modo_placar = 'sombra' where id;
    v1 := public._agenda_comunicar_quinta(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'Q4a desligado e sombra: a quinta é a de antes, byte a byte (o placar não vai; a sombra está na tabela)',
      v_t0 is not null and length(v_t0) > 0 and v1 = v0 and position('Placar' in v_t0) = 0, left(v0::text, 300));
    update public.agenda_config set modo_placar = 'ligado' where id;
    v2 := public._agenda_comunicar_quinta(c_hoje, c_agora);
    v_esp := case when position(E'\n\nPara a semana que vem preciso de:' in v_t0) > 0
                  then replace(v_t0, E'\n\nPara a semana que vem preciso de:', E'\n\n' || v_pl || E'\n\nPara a semana que vem preciso de:')
                  else v_t0 || E'\n\n' || v_pl end;
    v_res := pg_temp.ok(v_res, 'Q4b ligado: a mensagem de antes com o placar (só as linhas com dado) antes de "Para a semana que vem preciso de:"; o resto igual',
      v2 #>> '{quinta_diria,texto}' = v_esp and position(E'\n\nPara a semana que vem preciso de:' in v_t0) > 0
      and (v2 -> 'quinta_diria') - 'texto' - 'caracteres' - 'cabe' = (v0 -> 'quinta_diria') - 'texto' - 'caracteres' - 'cabe', v2::text);
    v_res := pg_temp.ok(v_res, 'Q4c no teto da quinta (gestor_aviso_texto_max, 2.400, R8.5-13): cabe; quem corta é o montador (o placar cede primeiro)',
      (v2 #>> '{quinta_diria,cabe}')::boolean and (v2 #>> '{quinta_diria,caracteres}')::int <= 2400
      and (select c.gestor_aviso_texto_max from public.agenda_config c where c.id) = 2400, v2 #>> '{quinta_diria,caracteres}');
    -- abaixo do mínimo: 2 linhas com dado não vão (a rodada guardou igual)
    update public.agenda_placar_semanas set numeros = pg_temp.n_tres() - 'perguntas' || '{"perguntas": {"abertas": 0}}', versao = 2,
                                            historico = '[{"versao": 1}]', calculado_em = timestamptz '2026-11-19 16:41-03' where semana = c_sem;
    v1 := public._agenda_comunicar_quinta(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'Q4d abaixo de placar_min_linhas (2 de 3): a quinta não leva o placar (a de antes, byte a byte)', v1 = v0, v1::text);
    update public.agenda_config set placar_min_linhas = 2 where id;
    v1 := public._agenda_comunicar_quinta(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'Q4e com placar_min_linhas 2, as mesmas 2 linhas vão', position('• Compras: 4 de 7' in (v1 #>> '{quinta_diria,texto}')) > 0, v1::text);
    -- com o lote ligado de verdade: as peças levam o placar ({texto, linha}) para o montador
    update public.agenda_config set modo_lote_dono = 'ligado', modo_bloco_agenda = 'ligado', gestor_so_propor = false, placar_min_linhas = 3 where id;
    update public.agenda_placar_semanas set numeros = pg_temp.n_exemplo(), versao = 3, historico = '[{"versao": 1}, {"versao": 2}]',
                                            calculado_em = timestamptz '2026-11-19 16:42-03' where semana = c_sem;
    v1 := public._agenda_comunicar_quinta(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'Q4f com o lote ligado: a peça placar nas peças, {texto (a mensagem), linha}, antes das perguntas no montador',
      v1 #>> '{avisos,0,placar,texto}' = v_pl
      and v1 #>> '{avisos,0,placar,linha}' = public._agenda_placar_texto(pg_temp.n_exemplo(), c_sem, date '2026-11-14', 'mensagem', 1000) ->> 'linha', left(v1::text, 400));
    -- enviado_em: depois que a fila mandou (o ramo "já saiu", estado enviada), só se o texto que saiu tem o placar; uma vez; fora de ligado, nada
    -- (a quinta seguinte, 26/11: o placar da semana de 16 a 21/11 guardado, e o texto que saiu sem ele)
    insert into public.agenda_placar_semanas (semana, de, ate, modo, numeros, texto, linha, calculado_em)
    values (date '2026-11-16', date '2026-11-16', date '2026-11-21', 'ligado', pg_temp.n_exemplo(), 'texto guardado', 'linha guardada', timestamptz '2026-11-26 16:40-03');
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, telefone, enviar_em, estado, enviada_em, dedupe_key)
    values (timestamptz '2026-11-26 17:00-03', date '2026-11-26', 'Agenda — a semana que vem:' || E'\n\n' || 'Placar 16 a 21/11: outra coisa.',
            array[md5('7g6:aviso')::uuid], '5547999990000', timestamptz '2026-11-26 17:00-03', 'enviada', timestamptz '2026-11-26 17:16-03',
            'agenda-dono:semana:2026-11-26');
    perform public._agenda_comunicar_quinta(date '2026-11-26', timestamptz '2026-11-26 17:30-03');
    v_res := pg_temp.ok(v_res, 'Q4g o texto que saiu sem o placar (nem o texto nem a linha): enviado_em fica nulo',
      (select s.enviado_em from public.agenda_placar_semanas s where s.semana = date '2026-11-16') is null, null);
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, telefone, enviar_em, estado, enviada_em, dedupe_key)
    values (c_agora, c_hoje, 'Agenda — a semana que vem:' || E'\n\n' || v_pl, array[md5('7g6:aviso')::uuid], '5547999990000',
            c_agora, 'enviada', timestamptz '2026-11-19 17:16-03', 'agenda-dono:semana:' || c_hoje::text);
    update public.agenda_config set modo_placar = 'sombra' where id;
    perform public._agenda_comunicar_quinta(c_hoje, timestamptz '2026-11-19 17:30-03');
    v_res := pg_temp.ok(v_res, 'Q4h em sombra, nem com o placar no texto: enviado_em fica nulo',
      (select s.enviado_em from public.agenda_placar_semanas s where s.semana = c_sem) is null, null);
    update public.agenda_config set modo_placar = 'ligado' where id;
    v1 := public._agenda_comunicar_quinta(c_hoje, timestamptz '2026-11-19 17:30-03');
    v_res := pg_temp.ok(v_res, 'Q4i ligado, o texto que saiu com o placar: enviado_em = a hora do envio (sem versão nova); o retorno do "já saiu" é o de antes',
      (select s.enviado_em from public.agenda_placar_semanas s where s.semana = c_sem) = timestamptz '2026-11-19 17:16-03'
      and (select s.versao from public.agenda_placar_semanas s where s.semana = c_sem) = 3 and v1 = '{"ja_saiu": true, "estado": "enviada"}'::jsonb, v1::text);
    perform public._agenda_comunicar_quinta(c_hoje, timestamptz '2026-11-19 17:45-03');
    v_res := pg_temp.ok(v_res, 'Q4j de novo: enviado_em não muda (uma vez)',
      (select s.enviado_em from public.agenda_placar_semanas s where s.semana = c_sem) = timestamptz '2026-11-19 17:16-03', null);
    raise exception using errcode = 'PQ001';
  exception when sqlstate 'PQ001' then
    null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('Q4 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$q4$;

-- ── Q5. O motivo ferramenta (AG7-27) ─────────────────────────────────────────────────────────────────
-- A paridade SQL × TS: as palavras de MOTIVOS_DO_DIA (_shared/agenda/comandos.ts) e de MOTIVOS_DO_ANDAMENTO (_shared/agenda/rpc-das-ferramentas.ts), com o
-- código que o TS espera — a mesma lista que comandos_test.ts e rpc-das-ferramentas_test.ts conferem do lado do TS.
with p(palavra, codigo) as (values
  ('material', 'material'), ('cliente', 'cliente_ou_bem'), ('equipe', 'equipe_faltou'), ('anterior', 'trabalho_anterior'), ('informacao', 'informacao'),
  ('clima', 'clima'), ('estimativa', 'estimativa'), ('imprevisto', 'imprevisto_tecnico'), ('urgencia', 'urgencia_outra_os'), ('esqueci', 'esqueci'),
  ('ferramenta', 'ferramenta'), ('carro', 'ferramenta'))
insert into _resultado
select 'Q5a a paridade SQL × TS: cada palavra de MOTIVOS_DO_DIA e MOTIVOS_DO_ANDAMENTO dá o código do TS em _agenda_motivo_dito (12 palavras)',
       count(*) = 12 and bool_and(public._agenda_motivo_dito(p.palavra) is not distinct from p.codigo),
       string_agg(p.palavra || '→' || coalesce(public._agenda_motivo_dito(p.palavra), 'null'), ', ') filter (where public._agenda_motivo_dito(p.palavra) is distinct from p.codigo)
  from p;
insert into _resultado
select 'Q5b as palavras do AG7-27 (ferramentas, sem carro, veículo, faltou ferramenta, faltou carro) dão ferramenta; "faltou" sozinho segue equipe; o código também',
       public._agenda_motivo_dito('ferramentas') = 'ferramenta' and public._agenda_motivo_dito('sem carro') = 'ferramenta'
       and public._agenda_motivo_dito('Veículo') = 'ferramenta' and public._agenda_motivo_dito('faltou ferramenta') = 'ferramenta'
       and public._agenda_motivo_dito('faltou carro') = 'ferramenta' and public._agenda_motivo_dito('faltou') = 'equipe_faltou'
       and public._agenda_motivo_dito('FERRAMENTA') = 'ferramenta' and public._agenda_motivo_dito('caro') is null, null;
insert into _resultado
select 'Q5c o texto: ferramenta = "ferramenta ou carro"; os 11 de antes iguais',
       public._agenda_motivo_texto('ferramenta') = 'ferramenta ou carro'
       and array(select public._agenda_motivo_texto(c) from unnest(array['material', 'cliente_ou_bem', 'equipe_faltou', 'trabalho_anterior', 'informacao', 'clima',
                                                                         'estimativa', 'imprevisto_tecnico', 'urgencia_outra_os', 'esqueci', 'concluida_antes']) c)
           = array['material', 'cliente', 'equipe', 'trabalho anterior', 'informação', 'chuva', 'estimativa', 'imprevisto', 'urgência em outra OS', 'esqueci',
                   'terminou antes'], null;
insert into _resultado
select 'Q5d capacidade_motivos continua sem ferramenta (não é falta do dono, §3.1 item 12)',
       not ('ferramenta' = any (c.capacidade_motivos)), array_to_string(c.capacidade_motivos, ',')
  from public.agenda_config c where c.id;

do $q5$
declare
  v_res   jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_hoje  constant date := date '2027-03-10';
  c_agora constant timestamptz := timestamptz '2027-03-10 15:00-03';
  v_r     jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(jsonb_build_array(jsonb_build_array('Q5 o dia não carro', true, 'PULADO: fora da bancada (rode pela bancada)')));
    return;
  end if;
  begin
    -- a frase do dono até o grava (R9.12-5): *dia não carro* → o TS manda o código ferramenta (comandos_test.ts); a palavra também serve
    update public.agenda_config set modo_proposta = 'ligado' where id;
    perform pg_temp.nova_os('q5');
    perform pg_temp.meio('q5m', 'q5', c_hoje, 'manha');
    perform public._agenda_vigia_perguntar('conferencia', '7g6:q5:conf', pg_temp.o('q5'), null, c_hoje - 1, null, 'Como foi ontem?', 'ligado',
                                           timestamptz '2027-03-09 18:00-03');
    -- a conferência de ontem aberta e hoje com plano: a pergunta "hoje ou ontem?" diz *dia não ferramenta* (antes, "imprevisto")
    v_r := public.agenda_conferir_dia(c_admin, 'nao_cumprido', 'carro', null, 'whatsapp', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'Q5e "dia não carro" com a conferência de ontem aberta: pergunta o dia com *dia não ferramenta hoje* ou *… ontem*; nada muda',
      v_r ->> 'pede' = 'dia' and v_r ->> 'texto' like '%*dia não ferramenta hoje* ou *dia não ferramenta ontem*.'
      and (select a.resultado from public.agenda_alocacoes a where a.id = md5('7g6:aloc:q5m')::uuid) is null, v_r::text);
    -- o grava: hoje, com a palavra; o meio-dia fica não cumprido por ferramenta
    v_r := public.agenda_conferir_dia(c_admin, 'nao_cumprido', 'carro', 'hoje', 'whatsapp', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'Q5f "dia não carro hoje" grava: o meio-dia de hoje fica não cumprido, motivo ferramenta (o CHECK aceita, o texto diz "ferramenta ou carro")',
      (select a.resultado || ':' || a.motivo from public.agenda_alocacoes a where a.id = md5('7g6:aloc:q5m')::uuid) = 'nao_cumprido:ferramenta', v_r::text);
    raise exception using errcode = 'PQ001';
  exception when sqlstate 'PQ001' then
    null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('Q5 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$q5$;

-- ── Q6. A saúde: a chave explicar ────────────────────────────────────────────────────────────────────
do $q6$
declare
  v_res   jsonb := '[]'::jsonb;
  c_tec   constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v       jsonb;
  v_t     text;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(jsonb_build_array(jsonb_build_array('Q6 a saúde', true, 'PULADO: fora da bancada (rode pela bancada)')));
    return;
  end if;
  begin
    perform pg_temp.cenario_q();
    update public.agenda_config set modo_porque = 'desligado', modo_rebaixar = 'desligado', modo_placar = 'desligado', marcacoes_desde = null,
                                    correcao_janela_du = 3, explicar_hora = '16:35' where id;
    -- Q6a zerada: os modos desligados, nenhum zero acende (mesmo com marcação aberta antiga e sem rodada)
    v := public._agenda_saude_explicar(date '2027-03-11', timestamptz '2027-03-11 18:00-03');
    v_res := pg_temp.ok(v_res, 'Q6a a chave explicar zerada com os modos desligados (os zeros olham o modo deles): zeros_ok e os 5 zeros = 0',
      v ->> 'zeros_ok' = 'true' and (v - 'zeros_ok' - 'numeros'
        -- FASE 7g: (7g P5b) os 2 zeros do ok do dono (20261112100700), também 0 (agenda_fase7g_ok_do_dono.sql K4r, K11a a K11c acendem cada um)
        - 'ok_sem_pergunta' - 'nivel_sem_aviso') = '{"erros_dia": 0, "placar_atrasado": 0, "rodada_atrasada": 0, "rebaixar_sem_veto": 0, "marcacao_aberta_vencida": 0}'::jsonb
        and coalesce(v ->> 'ok_sem_pergunta', '0') = '0' and coalesce(v ->> 'nivel_sem_aviso', '0') = '0', v::text);
        -- FASE 7g: fim
    v_res := pg_temp.ok(v_res, 'Q6b agenda_saude tem a chave explicar (a mesma da função)',
      public.agenda_saude(date '2027-03-11', timestamptz '2027-03-11 18:00-03') -> 'explicar' = v, null);
    -- Q6c placar_atrasado: em sombra, na quinta, depois de explicar_hora + 1 h, sem a semana guardada = 1; antes da hora, outro dia ou com a semana = 0
    update public.agenda_config set modo_placar = 'sombra' where id;
    v_t := (public._agenda_saude_explicar(date '2027-03-11', timestamptz '2027-03-11 18:00-03') ->> 'placar_atrasado')
           || (public._agenda_saude_explicar(date '2027-03-11', timestamptz '2027-03-11 17:30-03') ->> 'placar_atrasado')
           || (public._agenda_saude_explicar(date '2027-03-10', timestamptz '2027-03-10 18:00-03') ->> 'placar_atrasado');
    perform public._agenda_explicar_placar(date '2027-03-11', timestamptz '2027-03-11 16:40-03');
    v_t := v_t || (public._agenda_saude_explicar(date '2027-03-11', timestamptz '2027-03-11 18:00-03') ->> 'placar_atrasado');
    v_res := pg_temp.igual(v_res, 'Q6c placar_atrasado: 1 sem a semana guardada às 18:00 da quinta; 0 às 17:30, na quarta e com a semana guardada', v_t, '1000');
    v := public.agenda_saude(date '2027-03-11', timestamptz '2027-03-11 18:00-03');
    update public.agenda_config set modo_placar = 'desligado' where id;
    -- Q6d marcacao_aberta_vencida: com o porquê em sombra, a aberta de 04/03 (+ 3 dias úteis = 09/03) já venceu em 11/03; a de 03/03 (a 2ª de m1) também
    update public.agenda_config set modo_porque = 'sombra' where id;
    v_t := (public._agenda_saude_explicar(date '2027-03-11', timestamptz '2027-03-11 10:00-03') ->> 'marcacao_aberta_vencida')
           || (public._agenda_saude_explicar(date '2027-03-09', timestamptz '2027-03-09 10:00-03') ->> 'marcacao_aberta_vencida');
    v_res := pg_temp.igual(v_res, 'Q6d marcacao_aberta_vencida: as 2 abertas vencidas em 11/03; em 09/03, só a de 03/03 (03/03 + 3 dias úteis = 08/03)', v_t, '21');
    -- Q6e rodada_atrasada: com o porquê em sombra, terça 18:00 sem rodada explicar = 1; às 17:00, no domingo ou com a rodada = 0
    v_t := (public._agenda_saude_explicar(date '2027-03-09', timestamptz '2027-03-09 18:00-03') ->> 'rodada_atrasada')
           || (public._agenda_saude_explicar(date '2027-03-09', timestamptz '2027-03-09 17:00-03') ->> 'rodada_atrasada')
           || (public._agenda_saude_explicar(date '2027-03-07', timestamptz '2027-03-07 18:00-03') ->> 'rodada_atrasada');
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    select timestamptz '2027-03-09 16:40-03', date '2027-03-09', timestamptz '2027-03-09 16:40-03', c.modo_proposta, c.modo_vigia, '{}', 0, 0, 'explicar',
           c.modo_equipe, c.modo_diaria from public.agenda_config c where c.id;
    v_t := v_t || (public._agenda_saude_explicar(date '2027-03-09', timestamptz '2027-03-09 18:00-03') ->> 'rodada_atrasada');
    v_res := pg_temp.igual(v_res, 'Q6e rodada_atrasada: 1 na terça 18:00 sem rodada; 0 às 17:00, no domingo e com a rodada de hoje', v_t, '1000');
    update public.agenda_config set modo_porque = 'desligado' where id;
    -- Q6f rebaixar_sem_veto: o rebaixar ligado com o veto fora de ligado = 1
    update public.agenda_config set modo_rebaixar = 'ligado', modo_veto = 'sombra' where id;
    v_t := public._agenda_saude_explicar(date '2027-03-09', timestamptz '2027-03-09 10:00-03') ->> 'rebaixar_sem_veto';
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = false where id;
    v_t := v_t || (public._agenda_saude_explicar(date '2027-03-09', timestamptz '2027-03-09 10:00-03') ->> 'rebaixar_sem_veto');
    v_res := pg_temp.igual(v_res, 'Q6f rebaixar_sem_veto: 1 com o veto em sombra; 0 com o veto ligado (sem o freio)', v_t, '10');
    update public.agenda_config set modo_rebaixar = 'desligado' where id;
    -- Q6g erros_dia: um erro explicar:% de hoje = 1; o de 2 dias atrás e o de outra ação não contam
    insert into public.app_error_logs (fingerprint, source, level, context, action, message, last_seen_at)
    values ('7g6:e1', 'db', 'error', 'agenda', 'explicar:placar', 'teste', timestamptz '2027-03-09 09:00-03'),
           ('7g6:e2', 'db', 'error', 'agenda', 'explicar:placar', 'teste', timestamptz '2027-03-07 09:00-03'),
           ('7g6:e3', 'db', 'error', 'agenda', 'aprender:vies', 'teste', timestamptz '2027-03-09 09:00-03');
    v := public._agenda_saude_explicar(date '2027-03-09', timestamptz '2027-03-09 10:00-03');
    v_res := pg_temp.ok(v_res, 'Q6g erros_dia: o erro explicar:% de 1 dia = 1, e o zeros_ok cai', v ->> 'erros_dia' = '1' and v ->> 'zeros_ok' = 'false', v::text);
    v_res := pg_temp.ok(v_res, 'Q6h com um zero aceso, o ok da saúde cai (a chave explicar entra no ok, como comunicacao e margem)',
      public.agenda_saude(date '2027-03-09', timestamptz '2027-03-09 10:00-03') ->> 'ok' = 'false'
      and public.agenda_saude(date '2027-03-09', timestamptz '2027-03-09 10:00-03') #>> '{explicar,zeros_ok}' = 'false', null);
    -- Q6i a porta: o técnico com login, 42501; o admin com login lê
    v_t := pg_temp.como(c_tec, 'authenticated', 'select public._agenda_saude_explicar(date ''2027-03-09'', timestamptz ''2027-03-09 10:00-03'')::text');
    v_res := pg_temp.ok(v_res, 'Q6i o técnico com login não lê a saúde nem o placar: 42501',
      v_t like 'erro 42501%' and pg_temp.como(c_tec, 'authenticated', 'select public.agenda_placar(null, date ''2027-03-11'', timestamptz ''2027-03-11 17:00-03'')::text') like 'erro 42501%', v_t);
    v_t := pg_temp.como(c_admin, 'authenticated', 'select public._agenda_saude_explicar(date ''2027-03-09'', timestamptz ''2027-03-09 10:00-03'') ->> ''erros_dia''');
    v_res := pg_temp.igual(v_res, 'Q6j o admin com login lê a saúde', v_t, '1');
    raise exception using errcode = 'PQ001';
  exception when sqlstate 'PQ001' then
    null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('Q6 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$q6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
