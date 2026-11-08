-- Prova das perguntas da Agenda de Produção, Fase 7f (pacote P2): quem pode vencer, a linha, a ordem, o que destrava, o prazo, o teto, a rodada comunicar e a volta do que ficou
-- com o padrão (migration 20261109100100; spec-fase7f §3.2, §5.2, §6.2, §6.3, §8.3 e R8.4, R8.5-7 a 11, R8.6, R8.7, R8.8, R8.12, R8.13).
-- bancada: depende de 20261109100100
--
--   P1   destrava e a ordem: o dono primeiro, a crítica que perde amanhã antes dele; OS sem linha, sem base, só reserva; a régua da sexta
--   P2   a linha de cada chave, byte a byte, com o prazo valendo, com o freio, em sombra e desligado; título, não a pergunta inteira; "conto" sem alocação; até 220 letras
--   P3   o prazo só com a pergunta mostrada antes dele: a da carona, a mostrada depois e a sem prazo não vencem
--   P4   vencer efeito nada (resolvida, ação assumir, texto); P4f a crítica nascida do motor vence com a recomendada, sem autor nenhum, e o *desfaz* volta; P4n o que nunca vence;
--        P4b ok = false e erro viram sem_padrao, sem repetir; P4c o prometido que surgiu depois; P4d o padrao_do_dono respeita AG7-37; P4e o efeito opcao até o carimbo
--   P5   o teto: as mais velhas que podem vencer, nunca a que espera, nunca muda a agenda
--   P6   sombra só veto_teria_em; P6b o freio é igual a sombra, em agenda_gestor_rodar e na rodada comunicar; desligado, nada
--   P7   agenda_desfazer da assumir: a frase, a pergunta nova, o estado depois; P7b sem OS não tem *desfaz <nome>*; janela de 2 dias úteis
--   P8   a rodada: 2× = 1×; domingo; desligado; sem vetos; sem statement_timeout; o relógio entre os passos; query_canceled; erro de um passo
--   P9   as cópias só mudam nos blocos
--   P10  as portas: quem alcança o quê, com as funções sem grant vindo de função definer
--   P11  Decisão N = n de agenda_decisoes_abertas, com a ordem nova, e a resposta pelo mesmo número até o *grava*
--   P12  a ação assumir no *o que mudou*, uma frase só, e fora do aviso
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela sai PULADO: tudo aqui usa a fixture da 7f, que nunca roda em produção.
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
create function pg_temp.lanca(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'aceitou';
exception when others then
  return sqlstate;
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7f: … -- FASE 7f: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7f(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7f:' and l !~ '^\s*-- FASE 7f: fim' then 1
                                                when l ~ '^\s*-- FASE 7f: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7f: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_perguntas_fase7f', true), '') <> ''
$f$;
create function pg_temp.q(p_c text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-0000000005' || p_c)::uuid $f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-000000097' || p_n)::uuid $f$;
-- O prazo valendo: modo_veto ligado, sem o freio.
create function pg_temp.vale() returns void language sql as $f$
  update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = false, modo_proposta = 'ligado' where id
$f$;
create function pg_temp.linha(p_q uuid, p_hoje date default date '2026-11-10', p_agora timestamptz default timestamptz '2026-11-10 17:30-03') returns text language sql stable as $f$
  select public._agenda_pergunta_linha(p_q, p_hoje, p_agora) ->> 'texto'
$f$;
-- A rodada do prazo às 18:05 de ter 10/11.
create function pg_temp.vence(p_hoje date default date '2026-11-10', p_agora timestamptz default timestamptz '2026-11-10 18:05-03') returns jsonb language sql as $f$
  select public._agenda_gestor_vetos(p_hoje, p_agora)
$f$;
create function pg_temp.est(p_q uuid) returns text language sql stable as $f$
  select q.estado || ':' || coalesce(q.assumida_por, '-') from public.agenda_perguntas q where q.id = p_q
$f$;
-- Uma pergunta ligada, com o texto no formato real da vigia, que passa pelos 2 gatilhos.
create function pg_temp.perg(p_tipo text, p_chave text, p_os uuid, p_texto text, p_opcoes jsonb default '[]', p_rec smallint default null, p_criada timestamptz default timestamptz '2026-11-09 09:00-03')
returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, modo, criada_em)
  values (p_tipo, p_chave, p_os, case when p_os is null then '{}'::uuid[] else array[p_os] end, p_texto, p_opcoes, p_rec, 'ligado', p_criada)
  returning id
$f$;
-- Mostrada com o prazo, às 17:30 da véspera.
create function pg_temp.mostra(p_q uuid, p_prazo timestamptz default timestamptz '2026-11-10 18:00-03') returns void language sql as $f$
  update public.agenda_perguntas set veto_ate = p_prazo, mostrada_vezes = mostrada_vezes + 1, mostrada_em = p_prazo - interval '1 day', mostrada_via = 'fechamento' where id = p_q
$f$;
-- A crítica do Giancarlo pelo caminho real: o dono disse que precisa até qui 12/11, e o motor, ao montar a OS na seg 09/11, não acha lugar: a pergunta sai de agenda_propor, com as opções, o efeito, a espera,
-- a recomendação e a versão do plano. A recomendada é o atraso. Só o service_order_id e os dias vêm daqui: nenhuma coluna da pergunta é digitada.
create function pg_temp.critica() returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  update public.agenda_config set modo_proposta = 'ligado' where id;
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, precisa_ate, material_conferido_em)
  values (pg_temp.os('305'), 8, 'dono', timestamptz '2026-11-09 09:00-03', date '2026-11-12', timestamptz '2026-11-09 09:00-03');
  perform public.agenda_propor('replano', null, null, array[pg_temp.os('305')], '{}'::jsonb, true, 'vigia', null, date '2026-11-09', timestamptz '2026-11-09 16:00-03');
  select q.id into strict v from public.agenda_perguntas q
   where q.tipo = 'nao_cabe' and q.service_order_id = pg_temp.os('305') and q.estado = 'aberta' and q.proposta_id is not null;
  return v;
end $f$;
-- Uma crítica à mão, para os casos em que o motor não tem como chegar lá sem um cenário inteiro: mesma forma, com a opção 1 recomendada.
create function pg_temp.critica_mao(p_tipo text, p_chave text, p_os uuid, p_os_ids uuid[]) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo, criada_em)
  values (p_tipo, p_chave, p_os, p_os_ids, date '2026-11-20', 'Isso muda o plano. 1) Passa. 2) Fica.', '[{"n": 1, "texto": "Passa"}, {"n": 2, "texto": "Fica"}]', 1, 'ligado', timestamptz '2026-11-09 09:00-03')
  returning id
$f$;
-- A pergunta do gestor na forma real de produção (estimativa, 3 opções, recomendação 2, sem opcao_padrao), posta em veto_tipos para o efeito opcao ter por onde passar. Nenhum tipo
-- não crítico com efeito opcao está em veto_tipos no padrão: é assim que o caminho opcao, a recusa e o prometido se provam sem crítica vencer.
create function pg_temp.estimativa(p_os uuid, p_chave text default null, p_rec smallint default 2) returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  update public.agenda_config set veto_tipos = veto_tipos || '{estimativa}' where id and not 'estimativa' = any (veto_tipos);
  v := pg_temp.perg('estimativa', coalesce(p_chave, 'estimativa:' || p_os), p_os,
    'Por quantos dias eu marco? 1) 4 dias. 2) 6 dias. 3) Me diga.',
    '[{"n": 1, "texto": "4 dias", "efeito": {"dias": 4, "feito": "marquei 4 dias"}}, {"n": 2, "texto": "6 dias", "efeito": {"dias": 6, "feito": "marquei 6 dias"}}, {"n": 3, "texto": "Me diga", "efeito": {"dizer": true}}]'::jsonb,
    p_rec);
  perform pg_temp.mostra(v);
  return v;
end $f$;

-- ── 0. A fixture ────────────────────────────────────────────────────────────────────────────────────
do $p0$
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P0 a fixture', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  perform set_config('agenda.hoje', '2026-11-10', true);
  execute current_setting('agenda_teste.fase7f');
  perform set_config('agenda.hoje', '2026-11-10', true);
  perform pg_temp.gravar(pg_temp.ok('[]', 'P0 a fixture: as 8 abertas', (select count(*) = 8 from public.agenda_perguntas q where q.estado = 'aberta'), null));
end
$p0$;

-- ── P1. O que destrava e a ordem ────────────────────────────────────────────────────────────────────
do $p1$
declare
  r      jsonb := '[]';
  v_q    public.agenda_perguntas;
  v_d    numeric;
  v_o    jsonb;
  v_sup  uuid := 'f7f00000-0000-4000-8000-0000000007a1';
  v_id   uuid;
  v_ids  uuid[];
  v_t    int;
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 17:30-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('01');
    r := pg_temp.ok(r, 'P1a destrava: perguntas_primeiro = 9999 (padrao_do_dono)', public._agenda_destrava(v_q, c_h) = 9999, null);
    v_id := pg_temp.perg('dias_semana', 'dias_semana:p1a', null, 'Quais dias?');
    select * into v_q from public.agenda_perguntas where id = v_id;
    r := pg_temp.ok(r, 'P1a2 destrava: dias_semana também (AG7-02)', public._agenda_destrava(v_q, c_h) = 9999, null);

    select * into v_q from public.agenda_perguntas where id = pg_temp.q('07');
    v_d := (public.os_duracao_sugerida(pg_temp.os('305')) ->> 'dias_realista')::numeric;
    r := pg_temp.ok(r, 'P1b destrava: OS fora do plano, sem linha em os_planejamento = meios-dias realistas + 10 (Giancarlo)',
      v_d > 0 and public._agenda_destrava(v_q, c_h) = round(v_d * 2) + 10, format('dias %s, destrava %s', v_d, public._agenda_destrava(v_q, c_h)));
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('02');
    r := pg_temp.ok(r, 'P1c destrava: OS com compromisso vigente = 0 (Nelson)', public._agenda_destrava(v_q, c_h) = 0, null);

    -- só reserva: fora do plano
    perform set_config('agenda.hoje', '2026-11-10', true);
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('07');
    v_d := public._agenda_destrava(v_q, c_h);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, condicao, condicao_tipo, condicao_ate)
    select pg_temp.os('305'), (select id from public.payees where name = 'Alex' and active), date '2026-11-20', 'manha', 'turno', 'reserva', 'publicada', 'motor', 'condicionada', 'material', 'material', date '2026-11-19';
    r := pg_temp.ok(r, 'P1d destrava: OS só com reserva conta como fora do plano', public._agenda_destrava(v_q, c_h) = v_d, null);

    -- sem base: nulo não vira 10 nem derruba a conta
    update public.service_order_services set line_total = 0, unit_price_snapshot = 0 where service_order_id = pg_temp.os('305');
    update public.service_orders set grand_total = 0 where id = pg_temp.os('305');
    r := pg_temp.ok(r, 'P1e destrava: sem os dias realistas a OS não conta: 0, não nulo nem 10 (R8.12-2)',
      (public.os_duracao_sugerida(pg_temp.os('305')) ->> 'dias_realista') is null and public._agenda_destrava(v_q, c_h) = 0,
      format('%s; %s', public.os_duracao_sugerida(pg_temp.os('305')) ->> 'dias_realista', public._agenda_destrava(v_q, c_h)));
    update public.service_order_services set line_total = 900000000, unit_price_snapshot = 900000000 where service_order_id = pg_temp.os('305');
    update public.service_orders set grand_total = 900000000 where id = pg_temp.os('305');
    r := pg_temp.ok(r, 'P1f destrava: presa em 9998', public._agenda_destrava(v_q, c_h) = 9998, public._agenda_destrava(v_q, c_h)::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    -- o fornecedor sem OS: as OS da carteira com item que falta desse fornecedor
    insert into public.suppliers (id, name, display_name, active) values (v_sup, 'Correa Peças', 'Correa', true);
    update public.os_material set fornecedor_id = v_sup, fornecedor_nome = null where id = md5('f7f:material:306')::uuid;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'cliente' where service_order_id = pg_temp.os('306');
    v_id := pg_temp.perg('fornecedor_cadastro', 'fornecedor_cadastro:' || v_sup, null, 'O fornecedor Correa está sem cidade no cadastro. Como você compra desse fornecedor?');
    select * into v_q from public.agenda_perguntas where id = v_id;
    v_d := (public.os_duracao_sugerida(pg_temp.os('306')) ->> 'dias_realista')::numeric;
    r := pg_temp.ok(r, 'P1g destrava: fornecedor sem OS = as OS com item que falta dele', public._agenda_destrava(v_q, c_h) = round(v_d * 2) + 10, public._agenda_destrava(v_q, c_h)::text);
    v_id := pg_temp.perg('fornecedor_cadastro', 'fornecedor_cadastro:' || gen_random_uuid(), null, 'O fornecedor de outro está sem cidade.');
    select * into v_q from public.agenda_perguntas where id = v_id;
    r := pg_temp.ok(r, 'P1h destrava: outro fornecedor sem item = 0 (nada calculável)', public._agenda_destrava(v_q, c_h) = 0, null);
    select * into v_q from public.agenda_perguntas where chave = 'fornecedor_cadastro:' || v_sup;
    update public.os_material set situacao = 'comprado' where id = md5('f7f:material:306')::uuid;
    r := pg_temp.ok(r, 'P1h2 destrava: item que já foi comprado não conta: não falta o prazo para comprar', public._agenda_destrava(v_q, c_h) = 0, null);
    update public.os_material set situacao = 'falta' where id = md5('f7f:material:306')::uuid;
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('04');
    v_t := public._agenda_destrava(v_q, c_h);
    r := pg_temp.ok(r, 'P1i destrava: fornecedores_prazo sem fornecedor na chave = todas as com item que falta de quem não tem modalidade', v_t >= round(v_d * 2) + 10, v_t::text);
    update public.suppliers set modalidade = 'balcao', prazo_fonte = 'dono' where id = v_sup;
    r := pg_temp.ok(r, 'P1j destrava: fornecedor com a modalidade dita não conta', v_t - public._agenda_destrava(v_q, c_h) = round(v_d * 2) + 10, null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    update public.agenda_perguntas set destrava = 50 where id = pg_temp.q('05');
    update public.agenda_perguntas set destrava = 50 where id = pg_temp.q('04');
    update public.agenda_perguntas set destrava = 80 where id = pg_temp.q('03');
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-11 18:00-03' where id = pg_temp.q('05');
    v_o := public.agenda_perguntas_em_ordem(c_h, c_a);
    v_ids := array(select (e ->> 'id')::uuid from jsonb_array_elements(v_o) e order by (e ->> 'ordem')::int);
    r := pg_temp.ok(r, 'P1k a ordem: a crítica que perde até amanhã antes do dono; o dono; destrava; veto_ate; criada_em',
      v_ids = array[pg_temp.q('06'), pg_temp.q('01'), pg_temp.q('03'), pg_temp.q('05'), pg_temp.q('04'), pg_temp.q('02'), pg_temp.q('07'), pg_temp.q('08')],
      (select string_agg(right(x::text, 2), ',') from unnest(v_ids) x));
    r := pg_temp.ok(r, 'P1l a saída: os campos de §5.2, na ordem, com a espera de agora',
      (v_o -> 0 ->> 'tipo') = 'nao_cabe' and (v_o -> 0 ->> 'os')::uuid = pg_temp.os('304') and (v_o -> 0 ->> 'veto_espera') = 'cliente' and (v_o -> 0 ->> 'ordem') = '1'
      and (v_o -> 2 ->> 'destrava') = '80' and (v_o -> 2 ->> 'padrao_chave') = 'sem_peca' and (v_o -> 2 ->> 'linha') like 'Lenine: marquei sem peça%', v_o ->> 2);
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo, criada_em)
    values ('nao_cabe', 'nao_cabe:p1k2', pg_temp.os('303'), array[pg_temp.os('303')], c_h, 'Não cabe hoje. 1) Passa. 2) Fica.', '[{"n": 1, "texto": "Passa"}, {"n": 2, "texto": "Fica"}]', 1, 'ligado', c_a)
    returning id into v_id;
    v_ids := array(select (e ->> 'id')::uuid from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_h, c_a)) e order by (e ->> 'ordem')::int);
    r := pg_temp.ok(r, 'P1k2 entre as críticas de cima, a que perde primeiro, mesmo mais nova', v_ids[1] = v_id and v_ids[2] = pg_temp.q('06'), null);
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, modo, criada_em)
    values ('parada', 'parada:p1k3', pg_temp.os('306'), array[pg_temp.os('306')], c_h, 'Não crítica que perde hoje.', 'ligado', c_a);
    v_ids := array(select (e ->> 'id')::uuid from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_h, c_a)) e order by (e ->> 'ordem')::int);
    r := pg_temp.ok(r, 'P1k3 só a crítica sobe por perder amanhã: a não crítica fica depois do dono',
      array_position(v_ids, (select q.id from public.agenda_perguntas q where q.chave = 'parada:p1k3')) > array_position(v_ids, pg_temp.q('01')), null);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'parada:p1k3';
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_id;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = pg_temp.q('06');
    v_id := pg_temp.perg('nao_cabe', 'nao_cabe:p1m', pg_temp.os('306'), 'Não cabe, sem dia de perda. 1) Passa. 2) Fica.', '[{"n": 1, "texto": "Passa"}, {"n": 2, "texto": "Fica"}]', 1::smallint);
    v_ids := array(select (e ->> 'id')::uuid from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_h, c_a)) e order by (e ->> 'ordem')::int);
    r := pg_temp.ok(r, 'P1m crítica com perda_em nula não entra no grupo de cima nem some (R8.12-2)',
      v_ids[1] = pg_temp.q('01') and v_id = any (v_ids), null);
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo, criada_em)
    values ('nao_cabe', 'nao_cabe:p1n', pg_temp.os('303'), array[pg_temp.os('303')], date '2026-11-16', 'Não cabe na segunda. 1) Passa. 2) Fica.', '[{"n": 1, "texto": "Passa"}, {"n": 2, "texto": "Fica"}]', 1, 'ligado', c_a)
    returning id into v_id;
    v_ids := array(select (e ->> 'id')::uuid from jsonb_array_elements(public.agenda_perguntas_em_ordem(date '2026-11-13', timestamptz '2026-11-13 17:30-03')) e order by (e ->> 'ordem')::int);
    r := pg_temp.ok(r, 'P1n na sexta, "amanhã" é a segunda: a crítica que perde seg 16/11 vem antes do dono', array_position(v_ids, v_id) < array_position(v_ids, pg_temp.q('01')), null);
    v_ids := array(select (e ->> 'id')::uuid from jsonb_array_elements(public.agenda_perguntas_em_ordem(date '2026-11-12', timestamptz '2026-11-12 17:30-03')) e order by (e ->> 'ordem')::int);
    r := pg_temp.ok(r, 'P1o na quinta, a mesma crítica de seg 16/11 não é "amanhã": vem depois do dono', array_position(v_ids, v_id) > array_position(v_ids, pg_temp.q('01')), null);
    insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, criada_em) values ('conferencia', 'conferencia:p1', c_h, 'Como foi?', 'ligado', c_a),
      ('parada', 'parada:p1:sombra', null, 'Em teste.', 'sombra', c_a);
    insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em, expira_em) values ('parada', 'parada:p1:vencida', 'Vencida.', 'ligado', c_a - interval '9 days', c_a - interval '1 hour');
    r := pg_temp.ok(r, 'P1p fora da lista: conferencia, a em sombra e a expirada',
      jsonb_array_length(public.agenda_perguntas_em_ordem(c_h, c_a)) = 9, jsonb_array_length(public.agenda_perguntas_em_ordem(c_h, c_a))::text);
    r := pg_temp.ok(r, 'P1q sem o dia ou a hora: 22004',
      pg_temp.lanca($q$select public.agenda_perguntas_em_ordem(null, now())$q$) = '22004' and pg_temp.lanca($q$select public.agenda_perguntas_em_ordem(current_date, null)$q$) = '22004', null);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where estado = 'aberta';
    r := pg_temp.ok(r, 'P1q2 sem pergunta aberta, a lista é vazia; sem o dia, 22004 do mesmo jeito', public.agenda_perguntas_em_ordem(c_h, c_a) = '[]'::jsonb
      and pg_temp.lanca($q$select public.agenda_perguntas_em_ordem(null, now())$q$) = '22004', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    r := pg_temp.ok(r, 'P1r _agenda_comunicar_destrava: antes das 07:00, nada',
      public._agenda_comunicar_destrava(c_h, timestamptz '2026-11-10 06:50-03') ->> 'motivo' = 'cedo' and (select destrava from public.agenda_perguntas where id = pg_temp.q('07')) = 0, null);
    v_o := public._agenda_comunicar_destrava(c_h, timestamptz '2026-11-10 07:15-03');
    r := pg_temp.ok(r, 'P1s _agenda_comunicar_destrava: grava só o que mudou, nas ligadas',
      (v_o ->> 'atualizadas')::int >= 2 and (select destrava from public.agenda_perguntas where id = pg_temp.q('01')) = 9999 and (select destrava from public.agenda_perguntas where id = pg_temp.q('07')) > 10, v_o::text);
    r := pg_temp.ok(r, 'P1t _agenda_comunicar_destrava: de novo, 0: nada a escrever', public._agenda_comunicar_destrava(c_h, timestamptz '2026-11-10 07:30-03') ->> 'atualizadas' = '0', null);
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, modo) values ('parada', 'parada:p1t:sombra', pg_temp.os('305'), array[pg_temp.os('305')], 'Em teste.', 'sombra');
    v_o := public._agenda_comunicar_destrava(c_h, timestamptz '2026-11-10 07:45-03');
    r := pg_temp.ok(r, 'P1t2 a pergunta em sombra fica de fora', v_o ->> 'atualizadas' = '0' and (select destrava from public.agenda_perguntas where chave = 'parada:p1t:sombra') = 0, v_o::text);
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    select now(), c_h, c_a, 'ligado', 'ligado', '{"destrava": {"atualizadas": 3}}', 0, 1, 'comunicar', 'ligado', 'ligado';
    update public.agenda_perguntas set destrava = 0 where id = pg_temp.q('07');
    r := pg_temp.ok(r, 'P1u com a rodada do dia gravada, o passo não refaz: 1 vez por dia',
      public._agenda_comunicar_destrava(c_h, timestamptz '2026-11-10 15:15-03') ->> 'motivo' = 'já rodou hoje' and (select destrava from public.agenda_perguntas where id = pg_temp.q('07')) = 0, null);
    r := pg_temp.ok(r, 'P1v no dia seguinte, refaz', (public._agenda_comunicar_destrava(date '2026-11-11', timestamptz '2026-11-11 07:15-03') ->> 'atualizadas')::int >= 1, null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p1$;

-- ── P2. A linha de cada chave ───────────────────────────────────────────────────────────────────────
do $p2$
declare
  r      jsonb := '[]';
  v_id   uuid;
  v_id2  uuid;
  v_ids  uuid[] := '{}';
  v_l    jsonb;
  v_t    text;
  v_sup  uuid := 'f7f00000-0000-4000-8000-0000000007a2';
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 17:30-03';
  c_ate  constant text := 'Sem resposta até qua 11/11 às 18:00';
  x      record;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.vale();
    -- Sem o prazo gravado, para todas valerem o mesmo: qua 11/11 às 18:00 (as 2 mostradas na fixture já têm o de hoje)
    r := pg_temp.ok(r, 'P2a abre_e_fecha, com o prazo valendo', pg_temp.linha(pg_temp.q('01')) =
      'Você: Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e… ' || c_ate || ', continuo contando você só para abrir e fechar.', pg_temp.linha(pg_temp.q('01')));
    r := pg_temp.ok(r, 'P2b estimativa com alocação: "marquei", com os dias do plano; o prazo gravado', pg_temp.linha(pg_temp.q('02')) =
      'Nelson: marquei 3 dias pela estimativa (ter 17 a qui 19/11). Sem resposta até ter 10/11 às 18:00, fica assim; se for outro número, me diga os dias.', pg_temp.linha(pg_temp.q('02')));
    r := pg_temp.ok(r, 'P2c sem_peca com alocação', pg_temp.linha(pg_temp.q('03')) =
      'Lenine: marquei sem peça a comprar. Sem resposta até ter 10/11 às 18:00, fica assim; se faltar peça, me diga qual.', pg_temp.linha(pg_temp.q('03')));
    r := pg_temp.ok(r, 'P2d prazo_padrao sem 1 fornecedor: o padrão só para quem não tem outro (AG7-06)', pg_temp.linha(pg_temp.q('04')) =
      'A Correa não tem prazo de entrega cadastrado, e há compra dela na carteira. Conto 7 dias úteis para quem não tem outro prazo. ' || c_ate || ', fica assim.', pg_temp.linha(pg_temp.q('04')));
    r := pg_temp.ok(r, 'P2e como_esta: o nome já está no título, não repete', pg_temp.linha(pg_temp.q('05')) =
      'A OS do Vanderlei (motorhome, Instalação de carregador) está parada há 4 dias úteis, com… Deixo como está no plano. ' || c_ate || ', fica assim.', pg_temp.linha(pg_temp.q('05')));
    r := pg_temp.ok(r, 'P2f espera cliente: sem prazo, com o motivo', pg_temp.linha(pg_temp.q('06')) =
      'Decisão 1: O serviço do Flávio (lancha, Revisão do piloto automático) não cabe mais em qua 11/11 com… Isto espera você: mexe no dia que o cliente já sabe.', pg_temp.linha(pg_temp.q('06')));
    r := pg_temp.ok(r, 'P2g crítica que pode vencer: o que fica e o prazo, como as outras, e até 220: o título cede', pg_temp.linha(pg_temp.q('07')) =
      'Decisão 2: O serviço do Giancarlo (lancha, Troca do GPS) não cabe nas 2… Recomendo a opção 1: Passa para a semana seguinte, sem mudar o que já está marcado. ' || c_ate || ', fico com a opção 1.'
      and char_length(pg_temp.linha(pg_temp.q('07'))) <= 220, pg_temp.linha(pg_temp.q('07')));
    r := pg_temp.ok(r, 'P2h espera dinheiro: o título, sem prazo', pg_temp.linha(pg_temp.q('08')) =
      'Decisão 3: A diária do Roberto de seg 09/11 ficou sem a OS ligada, e ela entra no custo do Vanderlei…', pg_temp.linha(pg_temp.q('08')));

    v_id := pg_temp.perg('chegou', 'chegou:p2:2026-11-11', pg_temp.os('306'), 'Tadeu (OS-F6): "Placa solar" tinha previsão para qua 11/11. Chegou?');
    r := pg_temp.ok(r, 'P2i nao_chegou, com o texto real da vigia', pg_temp.linha(v_id) =
      'Tadeu (OS-F6): "Placa solar" tinha previsão para qua 11/11. Conto que ainda não chegou. ' || c_ate || ', fica assim.', pg_temp.linha(v_id));
    v_id := pg_temp.perg('duracao', 'duracao:p2', pg_temp.os('305'), 'Quantos dias leva Giancarlo (OS-F5), e com quem? Guardei lugar a partir de sex 13/11; preciso saber até qui 12/11.');
    r := pg_temp.ok(r, 'P2j estimativa sem alocação: "conto", nunca "marquei" (R8.12-9)',
      pg_temp.linha(v_id) like 'Giancarlo: conto % pela estimativa. ' || c_ate || ', fica assim; se for outro número, me diga os dias.' and pg_temp.linha(v_id) not like '%marquei%', pg_temp.linha(v_id));
    v_id2 := pg_temp.perg('duracao', 'duracao:p2j2', pg_temp.os('303'), 'Quantos dias leva Vanderlei (OS-F3)?');
    r := pg_temp.ok(r, 'P2j2 estimativa com alocação só no passado: "conto"; os dias que ficaram para trás não são marcados',
      pg_temp.linha(v_id2, date '2026-11-30', timestamptz '2026-11-30 17:30-03') like 'Vanderlei: conto %', pg_temp.linha(v_id2, date '2026-11-30', timestamptz '2026-11-30 17:30-03'));
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, condicao, condicao_tipo, condicao_ate)
    select pg_temp.os('305'), (select id from public.payees where name = 'Alex' and active), date '2026-11-20', 'manha', 'turno', 'reserva', 'publicada', 'motor', 'condicionada', 'material', 'material', date '2026-11-19';
    r := pg_temp.ok(r, 'P2j3 só reserva não é marcado: "conto"', pg_temp.linha(v_id) like 'Giancarlo: conto %', pg_temp.linha(v_id));
    update public.service_order_services set line_total = 0, unit_price_snapshot = 0 where service_order_id = pg_temp.os('305');
    update public.service_orders set grand_total = 0 where id = pg_temp.os('305');
    r := pg_temp.ok(r, 'P2j4 sem os dias: o título, sem inventar número nem "marquei"', pg_temp.linha(v_id) =
      'Quantos dias leva Giancarlo (OS-F5), e com quem? Guardei lugar a partir de sex 13/11… ' || c_ate || ', fica assim; se for outro número, me diga os dias.', pg_temp.linha(v_id));
    v_id := pg_temp.perg('material_conferir', 'material_conferir:p2', pg_temp.os('305'), 'Giancarlo (OS-F5) tem peça a comprar? Guardei lugar a partir de sex 13/11; preciso saber até qui 12/11.');
    r := pg_temp.ok(r, 'P2k sem_peca sem alocação: "conto"', pg_temp.linha(v_id) =
      'Giancarlo: conto sem peça a comprar. ' || c_ate || ', fica assim; se faltar peça, me diga qual.', pg_temp.linha(v_id));
    update public.os_planejamento set dias = 4 where service_order_id = pg_temp.os('301');
    r := pg_temp.ok(r, 'P2b2 estimativa: os dias vêm de os_planejamento quando há linha', pg_temp.linha(pg_temp.q('02')) like 'Nelson: marquei 4 dias pela estimativa%', pg_temp.linha(pg_temp.q('02')));
    update public.os_planejamento set dias = 3 where service_order_id = pg_temp.os('301');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, duracao_fonte)
    select pg_temp.os('306'), (select id from public.payees where name = 'Rafael' and active), d::date, 'manha', 'turno', 'execucao', 'publicada', 'motor', c_a, 'orcamento'
      from unnest(array['2026-11-24', '2026-11-26', '2026-11-30', '2026-12-02', '2026-12-04', '2026-12-09']) d;
    v_id := pg_temp.perg('duracao', 'duracao:p2b3', pg_temp.os('306'), 'Quantos dias leva Tadeu (OS-F6)?');
    r := pg_temp.ok(r, 'P2b3 estimativa com os dias espalhados: sem a lista, para não passar de 220', pg_temp.linha(v_id) like 'Tadeu: marquei % pela estimativa. Sem resposta%' and char_length(pg_temp.linha(v_id)) <= 220, pg_temp.linha(v_id));
    insert into public.suppliers (id, name, display_name, active, modalidade, prazo_fonte, prazo_dias_uteis) values (v_sup, 'Kamell Peças', 'Kamell', true, 'balcao', 'dono', 3);
    v_id := pg_temp.perg('fornecedor_cadastro', 'fornecedor_cadastro:' || v_sup, null, 'Sem cidade no cadastro. Como você compra desse fornecedor e em quantos dias chega?');
    r := pg_temp.ok(r, 'P2l prazo_padrao com 1 fornecedor: o nome e o prazo dele, não o padrão',
      pg_temp.linha(v_id) = format('Kamell: Sem cidade no cadastro. Conto %s. ', public._agenda_plural((public._agenda_prazo_do_fornecedor(v_sup) ->> 'du')::int, 'dia útil', 'dias úteis')) || c_ate || ', fica assim.'
      and (public._agenda_prazo_do_fornecedor(v_sup) ->> 'du')::int <> 7, pg_temp.linha(v_id));
    insert into public.suppliers (id, name, display_name, active, modalidade, prazo_fonte, prazo_dias_corridos) values ('f7f00000-0000-4000-8000-0000000007a3', 'Importadora Tal', 'Tal', true, 'importacao', 'dono', 45);
    v_id := pg_temp.perg('fornecedor_cadastro', 'fornecedor_cadastro:f7f00000-0000-4000-8000-0000000007a3', null, 'Sem cidade no cadastro. Como você compra desse fornecedor e em quantos dias chega?');
    r := pg_temp.ok(r, 'P2l2 importado: dias corridos, nunca o padrão de dias úteis', pg_temp.linha(v_id) = 'Tal: Sem cidade no cadastro. Conto 45 dias corridos. ' || c_ate || ', fica assim.', pg_temp.linha(v_id));
    v_id := pg_temp.perg('estouro', 'estouro:p2:6', pg_temp.os('303'), 'Vanderlei (OS-F3) já teve 6 dias de serviço e o combinado era 2 dias. O que falta?');
    r := pg_temp.ok(r, 'P2m como_esta, com o texto real: "Vanderlei (OS-F3)…" sem o nome duas vezes', pg_temp.linha(v_id) =
      'Vanderlei (OS-F3) já teve 6 dias de serviço e o combinado era 2 dias. Deixo como está no plano. ' || c_ate || ', fica assim.', pg_temp.linha(v_id));
    v_id := pg_temp.perg('bem_livre', 'bem_livre:p2', pg_temp.os('305'), 'A lancha do Giancarlo está livre esta semana? Sem isso eu não marco.');
    r := pg_temp.ok(r, 'P2n espera tipo (relógio próprio): o título, sem prazo', pg_temp.linha(v_id) = 'A lancha do Giancarlo está livre esta semana? Sem isso eu não marco.', pg_temp.linha(v_id));
    v_id := pg_temp.perg('reavaliar', 'reavaliar:p2', pg_temp.os('305'), 'Reavalio o Giancarlo. Mudou algo?');
    r := pg_temp.ok(r, 'P2o sem padrão: o título, sem prazo', pg_temp.linha(v_id) = 'Reavalio o Giancarlo.', pg_temp.linha(v_id));
    update public.agenda_perguntas set veto_espera = 'dono' where id = pg_temp.q('04');
    r := pg_temp.ok(r, 'P2p espera dono (*agenda espera*): o título, sem prazo', pg_temp.linha(pg_temp.q('04')) =
      'A Correa não tem prazo de entrega cadastrado, e há compra dela na carteira.' and public._agenda_pergunta_linha(pg_temp.q('04'), c_h, c_a) ->> 'veto_ate' is null, pg_temp.linha(pg_temp.q('04')));

    -- o prazo que já está gravado e o que passou
    v_l := public._agenda_pergunta_linha(pg_temp.q('02'), c_h, c_a);
    r := pg_temp.ok(r, 'P2q veto_ate da saída = o gravado, o mesmo que está no texto', (v_l ->> 'veto_ate')::timestamptz = timestamptz '2026-11-10 18:00-03', v_l::text);
    v_l := public._agenda_pergunta_linha(pg_temp.q('05'), c_h, c_a);
    r := pg_temp.ok(r, 'P2r sem prazo gravado: o que valeria mostrada agora, o mesmo do texto', (v_l ->> 'veto_ate')::timestamptz = timestamptz '2026-11-11 18:00-03' and not v_l ? 'veto_diria', v_l::text);
    v_id := pg_temp.perg('parada', 'parada:p2:7a', pg_temp.os('303'), 'Vanderlei (OS-F3) está em andamento e não andou desde sex 30/10. Parou?');
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-09 18:00-03' where id = v_id;
    v_l := public._agenda_pergunta_linha(v_id, c_h, c_a);
    r := pg_temp.ok(r, 'P2s prazo que passou sem nunca ter sido mostrado: vale o novo', (v_l ->> 'veto_ate')::timestamptz = timestamptz '2026-11-11 18:00-03' and v_l ->> 'texto' like '%' || c_ate || ',%', v_l::text);
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = timestamptz '2026-11-09 12:00-03' where id = v_id;
    v_l := public._agenda_pergunta_linha(v_id, c_h, c_a);
    r := pg_temp.ok(r, 'P2t prazo que passou depois de mostrado: fica o gravado', (v_l ->> 'veto_ate')::timestamptz = timestamptz '2026-11-09 18:00-03', v_l::text);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_id;
    r := pg_temp.ok(r, 'P2u pergunta fechada: sem prazo', public._agenda_pergunta_linha(v_id, c_h, c_a) ->> 'veto_ate' is null and pg_temp.linha(v_id) not like '%Sem resposta%', pg_temp.linha(v_id));
    r := pg_temp.ok(r, 'P2v pergunta que não existe: P0002, nunca uma linha vazia; sem o dia: 22004',
      pg_temp.lanca(format('select public._agenda_pergunta_linha(%L, current_date, now())', gen_random_uuid())) = 'P0002'
      and pg_temp.lanca(format('select public._agenda_pergunta_linha(%L, null, now())', pg_temp.q('01'))) = '22004'
      and pg_temp.lanca(format('select public._agenda_pergunta_linha(%L, current_date, null)', pg_temp.q('01'))) = '22004', null);

    -- o tamanho, no pior caso: nome de 30, título de 90, número de 2 algarismos
    update public.clients set name = 'Anaximandro Vasconcellos' || repeat('x', 40) where id = (select client_id from public.service_orders where id = pg_temp.os('305'));
    v_id := pg_temp.perg('parada', 'parada:p2:longa', pg_temp.os('305'), repeat('Texto real que passa bem de noventa letras antes do primeiro ponto final da pergunta ', 3) || '. Parou?');
    r := pg_temp.ok(r, 'P2w 220 letras no pior caso, com o prazo inteiro no texto',
      char_length('Decisão 12: ' || pg_temp.linha(v_id)) <= 220 and pg_temp.linha(v_id) like '%' || c_ate || ', fica assim.', format('%s: %s', char_length(pg_temp.linha(v_id)), pg_temp.linha(v_id)));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- todas as abertas, em todo modo: até 220, título e não a pergunta inteira, as palavras proibidas (a varredura confere antes que há texto, e reprova um texto plantado)
  begin
    for x in select * from (values ('ligado, sem o freio', 'ligado', false), ('ligado, com o freio', 'ligado', true), ('sombra', 'sombra', false), ('desligado', 'desligado', false)) t(rot, modo, freio) loop
      update public.agenda_config set modo_veto = x.modo, gestor_so_propor = x.freio where id;
      select string_agg(l, E'\n') into v_t from (select pg_temp.linha(q.id) as l from public.agenda_perguntas q where q.estado = 'aberta') y;
      r := pg_temp.ok(r, format('P2x as 8 linhas, %s: texto de verdade, até 220, sem a pergunta inteira, sem palavra proibida', x.rot),
        char_length(coalesce(v_t, '')) > 400
        and (select bool_and(char_length(l) between 20 and 220) from regexp_split_to_table(v_t, E'\n') l)
        and v_t !~ 'O que eu faço\?|1\) ' and v_t !~* '(proposta|veto|lote|classe|zona|destrava|ppc|\mdu\M)', left(v_t, 200));
    end loop;
    r := pg_temp.ok(r, 'P2y a varredura morde: o mesmo filtro reprova um texto plantado',
      'Sem resposta o lote vence' ~* '(proposta|veto|lote|classe|zona|destrava|ppc|\mdu\M)' and 'em 3 du' ~* '(proposta|veto|lote|classe|zona|destrava|ppc|\mdu\M)', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- cada chave com o freio e em sombra: a mesma linha sem o prazo; quem registra não acha prazo; veto_diria só em sombra
  begin
    v_ids := array[pg_temp.q('01'), pg_temp.q('02'), pg_temp.q('03'), pg_temp.q('04'), pg_temp.q('05')];
    for x in select * from (values ('o freio', 'ligado', true), ('sombra', 'sombra', false)) t(rot, modo, freio) loop
      update public.agenda_config set modo_veto = x.modo, gestor_so_propor = x.freio where id;
      r := pg_temp.ok(r, format('P2z com %s: as 5 chaves sem "Sem resposta", veto_ate nulo, veto_diria com o que seria', x.rot),
        (select bool_and(l ->> 'texto' not like '%Sem resposta%' and l ->> 'veto_ate' is null and l ->> 'veto_diria' is not null and char_length(l ->> 'texto') > 20)
           from (select public._agenda_pergunta_linha(i, c_h, c_a) as l from unnest(v_ids) i) y), null);
    end loop;
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = true where id;
    r := pg_temp.ok(r, 'P2z1 abre_e_fecha, com o freio', pg_temp.linha(pg_temp.q('01')) =
      'Você: Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e… Por enquanto conto você só para abrir e fechar.', pg_temp.linha(pg_temp.q('01')));
    r := pg_temp.ok(r, 'P2z2 estimativa, com o freio', pg_temp.linha(pg_temp.q('02')) = 'Nelson: marquei 3 dias pela estimativa (ter 17 a qui 19/11). Se for outro número, me diga os dias.', pg_temp.linha(pg_temp.q('02')));
    r := pg_temp.ok(r, 'P2z3 sem_peca, com o freio', pg_temp.linha(pg_temp.q('03')) = 'Lenine: marquei sem peça a comprar. Se faltar peça, me diga qual.', pg_temp.linha(pg_temp.q('03')));
    r := pg_temp.ok(r, 'P2z4 prazo_padrao, com o freio', pg_temp.linha(pg_temp.q('04')) =
      'A Correa não tem prazo de entrega cadastrado, e há compra dela na carteira. Conto 7 dias úteis para quem não tem outro prazo.', pg_temp.linha(pg_temp.q('04')));
    r := pg_temp.ok(r, 'P2z5 como_esta, com o freio', pg_temp.linha(pg_temp.q('05')) =
      'A OS do Vanderlei (motorhome, Instalação de carregador) está parada há 4 dias úteis, com… Deixo como está no plano.', pg_temp.linha(pg_temp.q('05')));
    v_id := pg_temp.perg('chegou', 'chegou:p2f:2026-11-11', pg_temp.os('306'), 'Tadeu (OS-F6): "Placa solar" tinha previsão para qua 11/11. Chegou?');
    r := pg_temp.ok(r, 'P2z6 nao_chegou, com o freio', pg_temp.linha(v_id) = 'Tadeu (OS-F6): "Placa solar" tinha previsão para qua 11/11. Conto que ainda não chegou.', pg_temp.linha(v_id));
    r := pg_temp.ok(r, 'P2z7 com o freio, a crítica recomenda e não promete prazo; a que espera segue igual',
      pg_temp.linha(pg_temp.q('07')) like '%Recomendo a opção 1: Passa para a semana seguinte, sem mudar o que já está marcado.' and pg_temp.linha(pg_temp.q('07')) not like '%Sem resposta%'
      and pg_temp.linha(pg_temp.q('06')) like '%Isto espera você: mexe no dia que o cliente já sabe.', pg_temp.linha(pg_temp.q('07')));
    update public.agenda_config set modo_veto = 'desligado', gestor_so_propor = false where id;
    v_l := public._agenda_pergunta_linha(pg_temp.q('02'), c_h, c_a);
    r := pg_temp.ok(r, 'P2z8 desligado: sem prazo e sem veto_diria', v_l ->> 'veto_ate' is null and not v_l ? 'veto_diria' and v_l ->> 'texto' not like '%Sem resposta%', v_l::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p2$;

-- ── P3. O prazo só com a pergunta mostrada antes dele ───────────────────────────────────────────────
do $p3$
declare
  r    jsonb := '[]';
  v    jsonb;
  v_id uuid;
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.vale();
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-10 18:00-03', mostrada_vezes = 2, mostrada_em = timestamptz '2026-11-10 18:01-03', mostrada_via = 'aviso' where id = pg_temp.q('05');
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P3a a mostrada DEPOIS do prazo não vence', pg_temp.est(pg_temp.q('05')) = 'aberta:-', v::text);
    r := pg_temp.ok(r, 'P3b a nunca mostrada, sem prazo, não vence (fornecedores_prazo)', pg_temp.est(pg_temp.q('04')) = 'aberta:-', null);
    r := pg_temp.ok(r, 'P3c as 2 mostradas com o prazo escrito vencem', pg_temp.est(pg_temp.q('02')) = 'resolvida:prazo' and pg_temp.est(pg_temp.q('03')) = 'resolvida:prazo' and v ->> 'assumidas' = '2', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    v := pg_temp.vence(date '2026-11-10', timestamptz '2026-11-10 17:59-03');
    r := pg_temp.ok(r, 'P3d antes do prazo, nada', pg_temp.est(pg_temp.q('02')) = 'aberta:-' and not v ? 'assumidas', v::text);
    v := pg_temp.vence(date '2026-11-10', timestamptz '2026-11-10 18:00-03');
    r := pg_temp.ok(r, 'P3e no minuto do prazo, vence (§5.2: veto_ate <= p_agora)', pg_temp.est(pg_temp.q('02')) = 'resolvida:prazo', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    -- a carona (parada) tem mostrada_vezes 1 e nenhum prazo; a da conversa com prazo nulo também
    perform pg_temp.vence();
    r := pg_temp.ok(r, 'P3f a da carona, mostrada sem prazo, não vence: o relógio não começou', pg_temp.est(pg_temp.q('05')) = 'aberta:-'
      and (select veto_ate is null and carona_em is not null and mostrada_vezes = 1 from public.agenda_perguntas where id = pg_temp.q('05')), null);
    -- pergunta em modo sombra, com prazo e mostrada
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, modo, veto_ate, mostrada_vezes, mostrada_em, mostrada_via)
    values ('parada', 'parada:p3:sombra', pg_temp.os('303'), array[pg_temp.os('303')], 'Em teste.', 'sombra', timestamptz '2026-11-10 18:00-03', 1, timestamptz '2026-11-09 17:30-03', 'fechamento') returning id into v_id;
    perform pg_temp.vence();
    r := pg_temp.ok(r, 'P3g a pergunta em modo sombra não vence', pg_temp.est(v_id) = 'aberta:-', null);
    -- com a opção já dita
    v_id := pg_temp.perg('chegou', 'chegou:p3', pg_temp.os('306'), 'Chegou?', '[{"n": 1, "texto": "Sim"}, {"n": 2, "texto": "Não"}]', null);
    perform pg_temp.mostra(v_id);
    update public.agenda_perguntas set opcao_escolhida = 1 where id = v_id;
    perform pg_temp.vence();
    r := pg_temp.ok(r, 'P3h com a opção já dita pelo dono, o prazo não vale mais', pg_temp.est(v_id) = 'aberta:-', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o interruptor de quem pergunta, como no bloco do 7a: a vigia em teste não fecha pergunta da vigia, e a linha não promete
    perform pg_temp.vale();
    update public.agenda_config set modo_vigia = 'sombra' where id;
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P3i quem fez a pergunta em teste: não vence, e a linha não escreve prazo', pg_temp.est(pg_temp.q('02')) = 'aberta:-'
      and public._agenda_pergunta_linha(pg_temp.q('02'), date '2026-11-10', timestamptz '2026-11-10 17:30-03') ->> 'veto_ate' is null
      and pg_temp.linha(pg_temp.q('02')) not like '%Sem resposta%', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p3$;

-- ── P4. Vencer ──────────────────────────────────────────────────────────────────────────────────────
do $p4$
declare
  r      jsonb := '[]';
  v      jsonb;
  v_q    public.agenda_perguntas;
  v_a    public.agenda_acoes;
  v_ver  bigint;
  v_id   uuid;
  v_id2  uuid;
  v_n    int;
  v_lg   int;
  v_ch   text;
  v_disp int;
  v_cap  text;
  v_txt  text;
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 18:05-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  -- P4: efeito nada
  begin
    perform pg_temp.vale();
    v_ver := (select versao_plano from public.agenda_config where id);
    v_n := (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada'));
    v := pg_temp.vence();
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('02');
    select * into v_a from public.agenda_acoes a where a.pergunta_id = pg_temp.q('02') and a.tipo = 'assumir';
    r := pg_temp.ok(r, 'P4a efeito nada: resolvida, com o motivo e o carimbo',
      v_q.estado = 'resolvida' and v_q.assumida_por = 'prazo' and v_q.assumida_em = c_a and v_q.respondida_em is null and v_q.respondida_via is null
      and v_q.resolvida_motivo = 'Sem resposta até ter 10/11 às 18:00: ficaram os 3 dias pela estimativa.', v_q.resolvida_motivo);
    r := pg_temp.ok(r, 'P4b2 a ação assumir: origem vigia, executada, da OS, com o que a pergunta tinha',
      v_a.origem = 'vigia' and v_a.executada and v_a.service_order_id = pg_temp.os('301') and not v_a.critica and v_a.dia = c_h
      and v_a.antes ->> 'pergunta_id' = pg_temp.q('02')::text and v_a.antes ->> 'tipo' = 'duracao' and v_a.antes ->> 'chave' like 'duracao:%' and v_a.antes ->> 'texto' = v_q.texto, v_a.antes::text);
    r := pg_temp.ok(r, 'P4c o texto da ação (§6.3), com a OS: *desfaz Nelson*', v_a.texto = 'Nelson: sem resposta até ter 10/11 às 18:00, ficaram os 3 dias pela estimativa. *desfaz Nelson* volta a pergunta.', v_a.texto);
    r := pg_temp.ok(r, 'P4c2 efeito nada não mexe no plano', (select versao_plano from public.agenda_config where id) = v_ver
      and (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')) = v_n, null);
    r := pg_temp.ok(r, 'P4d a de Flávio (espera cliente) e a diária (dinheiro) não vencem, nem com o prazo nelas', pg_temp.est(pg_temp.q('06')) = 'aberta:-' and pg_temp.est(pg_temp.q('08')) = 'aberta:-', null);
    r := pg_temp.ok(r, 'P4e a saída da rodada: as chaves do 7a e as novas', v ->> 'assumidas' = '2' and v ->> 'teria' = '0' and v ->> 'recusadas' = '0' and v ? 'aplicadas' and v ? 'sem_mostrar', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P4f: a crítica nascida do motor vence com a recomendada (AG7-15, §3.2)
  begin
    perform pg_temp.vale();
    update public.clients set name = 'Geraldo' where name ilike 'Giancarlo%' and id <> (select client_id from public.service_orders where id = pg_temp.os('305'));
    v_id := pg_temp.critica();
    select * into v_q from public.agenda_perguntas where id = v_id;
    r := pg_temp.ok(r, 'P4f0 (controle) ela nasceu do motor: proposta, versão, opções com efeito e espera, recomendação; sem espera; efeito opcao',
      v_q.critica and v_q.proposta_id is not null and v_q.versao_base is not null and v_q.recomendacao = 1 and v_q.padrao_efeito = 'opcao' and v_q.padrao_chave = 'recomendacao' and v_q.veto_espera is null
      and v_q.opcoes -> 0 -> 'efeito' ? 'restricoes' and v_q.opcoes -> 0 -> 'espera' <> '{}'::jsonb and pg_temp.est(pg_temp.q('07')) like 'descartada:%', left(to_jsonb(v_q)::text, 300));
    r := pg_temp.ok(r, 'P4f0b antes de mostrar com prazo, não vence: o relógio não começou', pg_temp.vence() ->> 'assumidas' = '2', null);
    r := pg_temp.ok(r, 'P4f0c e segue aberta', pg_temp.est(v_id) = 'aberta:-', null);
    perform pg_temp.mostra(v_id);
    r := pg_temp.ok(r, 'P4f0d a linha diz o que fica e o prazo', pg_temp.linha(v_id, c_h, timestamptz '2026-11-10 17:30-03') =
      format('Decisão %s: Giancarlo: Não cabe tudo até qui 12/11. Recomendo a opção 1: Giancarlo (OS-F5) atrasa: termina ter 24/11 em vez de qui 12/11. Sem resposta até ter 10/11 às 18:00, fico com a opção 1.',
             public._agenda_pergunta_linha(v_id, c_h, timestamptz '2026-11-10 17:30-03') ->> 'n'), pg_temp.linha(v_id, c_h, timestamptz '2026-11-10 17:30-03'));
    v_ver := (select versao_plano from public.agenda_config where id);
    v := pg_temp.vence();
    select * into v_q from public.agenda_perguntas where id = v_id;
    r := pg_temp.ok(r, 'P4f1 venceu com a recomendada: respondida pelo prazo, com a frase do prazo, sem ninguém em respondida_por, com o carimbo',
      v_q.estado = 'respondida' and v_q.opcao_escolhida = 1 and v_q.respondida_via = 'prazo' and v_q.respondida_por is null and v_q.respondida_em = c_a and v_q.assumida_por = 'prazo' and v_q.assumida_em = c_a
      and v_q.resposta = 'Sem resposta até ter 10/11 às 18:00: fiquei com a opção 1.' and v ->> 'assumidas' = '1' and v ->> 'recusadas' = '0', v::text);
    select * into v_a from public.agenda_acoes a where a.pergunta_id = v_id;
    r := pg_temp.ok(r, 'P4f2 a ação é crítica, com pergunta_id, desfazível, da vigia e sem autor, e mudou o plano de verdade',
      v_a.critica and v_a.origem = 'vigia' and v_a.autor is null and v_a.executada and v_a.desfazivel_ate > c_a and cardinality(v_a.alocacoes_criadas) > 0 and v_a.service_order_id = pg_temp.os('305')
      and (select versao_plano from public.agenda_config where id) <> v_ver and (select count(*) from public.agenda_acoes a where a.pergunta_id = v_id) = 1, to_jsonb(v_a)::text);
    r := pg_temp.ok(r, 'P4f3 nenhum autor falso na proposta: criada pela vigia, sem autor, sem quem decidiu',
      (select p.criada_por = 'vigia' and p.autor is null and p.decidida_por is null and p.estado = 'aplicada' from public.agenda_propostas p where p.id = v_a.proposta_id), null);
    r := pg_temp.ok(r, 'P4f4 nada fica como dito pelo dono: dia não fixado por ele, estimativa como estava',
      not exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas) and a.fixado_por = 'dono')
      and (select pl.estimativa_fonte = 'dono' and pl.dias = 8 from public.os_planejamento pl where pl.service_order_id = pg_temp.os('305')), null);
    select string_agg(public._agenda_mudanca_texto(g, false), ' | ') into v_txt
      from jsonb_array_elements(public._agenda_mudancas(c_h - 6, c_h, true, true, null)) g where g::text like '%Giancarlo%';
    r := pg_temp.ok(r, 'P4f5 o dono lê a mudança no *o que mudou*, com o *desfaz*, sem dizer que foi ele',
      v_txt like '%Giancarlo%' and v_txt like '%*desfaz Giancarlo* volta como estava.%' and v_txt !~* '(você (disse|pediu|decidiu|escolheu|mandou|aprovou)|como (pediu|disse)|decidiu|escolheu|dono)' and v_a.texto !~* '(você (disse|pediu|decidiu|escolheu|mandou|aprovou)|como (pediu|disse)|decidiu|escolheu|dono)', v_txt);
    r := pg_temp.ok(r, 'P4f5b e ela vai no aviso, que só conta motor e vigia', exists (select 1 from jsonb_array_elements(public._agenda_aviso_mudancas(c_h)) g where g -> 'acao_ids' ? v_a.id::text), null);
    v := public.agenda_desfazer_dito(pg_temp.adm(), 'Giancarlo', 'whatsapp', date '2026-11-11', c_a + interval '3 hours');
    r := pg_temp.ok(r, 'P4f6 *desfaz Giancarlo* volta como o texto promete: os dias saem, e a ação fica desfeita',
      v ->> 'ok' = 'true' and v ->> 'texto' = 'Desfeito. A decisão sobre o Giancarlo volta a ficar com você.' and not public._agenda_os_tem_dia(pg_temp.os('305'), date '2026-11-11')
      and (select a.desfeita_em is not null from public.agenda_acoes a where a.id = v_a.id), v::text);
    select * into v_q from public.agenda_perguntas q where q.tipo = 'nao_cabe' and q.service_order_id = pg_temp.os('305') and q.estado = 'aberta';
    r := pg_temp.ok(r, 'P4f7 a decisão volta ao dono como pergunta nova, sem prazo: não vence de novo sem ser mostrada',
      v_q.id is not null and v_q.id <> v_id and v_q.veto_ate is null and v_q.veto_espera is null and v_q.mostrada_vezes = 0 and v_q.opcoes = (select q.opcoes from public.agenda_perguntas q where q.id = v_id), left(to_jsonb(v_q)::text, 300));
    r := pg_temp.ok(r, 'P4f8 a volta tem autor de verdade: quem desfez foi o dono, e isso sim fica em desfeita_por', (select a.desfeita_por = pg_temp.adm() from public.agenda_acoes a where a.id = v_a.id), null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- a agenda mudou depois da pergunta: ok = false vira sem_padrao, com a régua de agenda_decidir
  begin
    perform pg_temp.vale();
    v_id := pg_temp.critica();
    perform pg_temp.mostra(v_id);
    -- outra OS toma o lugar, e a conta da opção 1 passa a terminar em outro dia
    update public.os_planejamento set dias = 20 where service_order_id = pg_temp.os('305');
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'cliente' where id = md5('f7f:aloc:306:alex:2026-11-23:tarde')::uuid;
    r := pg_temp.ok(r, 'P4g0 (controle) a versão do plano andou desde a pergunta', (select q.versao_base from public.agenda_perguntas q where q.id = v_id) <> (select versao_plano from public.agenda_config where id), null);
    v_lg := (select count(*) from public.app_error_logs where action = 'gestor:vetos');
    v := pg_temp.vence();
    select * into v_q from public.agenda_perguntas where id = v_id;
    r := pg_temp.ok(r, 'P4g1 a agenda mudou: ok = false, a pergunta fica aberta, com sem_padrao, sem carimbo e sem ação', v_q.estado = 'aberta' and v_q.veto_espera = 'sem_padrao' and v_q.assumida_por is null and v ->> 'recusadas' = '1'
      and not exists (select 1 from public.agenda_acoes a where a.pergunta_id = v_id), v::text);
    r := pg_temp.ok(r, 'P4g2 registra 1 vez', (select count(*) from public.app_error_logs where action = 'gestor:vetos') = v_lg + 1
      and exists (select 1 from public.app_error_logs e where e.action = 'gestor:vetos' and e.message like '%A agenda mudou desde a pergunta%'), null);
    v := pg_temp.vence(c_h, c_a + interval '15 minutes');
    r := pg_temp.ok(r, 'P4g3 não repete no tique seguinte', not v ? 'recusadas' and (select count(*) from public.app_error_logs where action = 'gestor:vetos') = v_lg + 1, v::text);
    r := pg_temp.ok(r, 'P4g4 a saída: a linha não promete mais prazo, e o dono ainda responde pelo número', pg_temp.linha(v_id, c_h, c_a) not like '%Sem resposta%' and (public._agenda_pergunta_linha(v_id, c_h, c_a) ->> 'n') is not null, pg_temp.linha(v_id, c_h, c_a));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P4n: o que nunca vence, cada um com a crítica nascida do motor ou na mesma forma, mostrada com o prazo, com tudo o mais a favor
  begin
    perform pg_temp.vale();
    v_id := pg_temp.critica();
    perform pg_temp.mostra(v_id);
    update public.os_planejamento set prometido_tipo = 'faixa', prometido_de = date '2026-11-16', prometido_ate = date '2026-11-27', prometido_em = c_a - interval '1 hour', prometido_fonte = 'dono'
     where service_order_id = pg_temp.os('305');
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n1 prometido surgido depois do nascimento: a crítica do motor não vence, com a foto ainda nula', pg_temp.est(v_id) = 'aberta:-' and (select veto_espera is null from public.agenda_perguntas where id = v_id)
      and not exists (select 1 from public.agenda_acoes a where a.pergunta_id = v_id) and pg_temp.linha(v_id, c_h, c_a) like '%Isto espera você: mexe no dia que o cliente já sabe.', pg_temp.linha(v_id, c_h, c_a));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    v_id := pg_temp.critica_mao('atraso_longo', 'atraso_longo:p4n2', pg_temp.os('305'), array[pg_temp.os('305'), pg_temp.os('306')]);
    perform pg_temp.mostra(v_id);
    insert into public.os_planejamento (service_order_id, prometido_tipo, prometido_de, prometido_ate, prometido_em, prometido_fonte, atualizado_por)
    values (pg_temp.os('306'), 'faixa', date '2026-11-23', date '2026-11-28', c_a, 'dono', pg_temp.adm());
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n2 o prometido na 2ª OS de os_ids também segura a crítica', pg_temp.est(v_id) = 'aberta:-' and not exists (select 1 from public.agenda_acoes a where a.pergunta_id = v_id), v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    -- ficha enviada: o Roberto tem qui 12/11 no Lenine
    v_id := pg_temp.critica_mao('atraso_longo', 'atraso_longo:p4n3', pg_temp.os('302'), array[pg_temp.os('302')]);
    perform pg_temp.mostra(v_id);
    r := pg_temp.ok(r, 'P4n3a (controle) sem nada dito à equipe, a crítica pode vencer', (select public._agenda_pergunta_espera(q, date '2026-11-10') is null from public.agenda_perguntas q where q.id = v_id), null);
    insert into public.agenda_equipe_mensagens (id, payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (md5('f7f:ficha:p4n3')::uuid, (select id from public.payees where name = 'Roberto' and active), date '2026-11-12', 'ficha', 'ligado', 'Roberto, amanhã: 8h no motorhome do Lenine.',
            timestamptz '2026-11-09 19:30-03', 'enfileirada', 'agenda-equipe:ficha:roberto:2026-11-12');
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n3 dia com ficha enviada: não vence, e a linha diz que a equipe já sabe', pg_temp.est(v_id) = 'aberta:-' and not exists (select 1 from public.agenda_acoes a where a.pergunta_id = v_id)
      and pg_temp.linha(v_id, c_h, c_a) like '%Isto espera você: mexe no dia que a equipe já sabe.', pg_temp.linha(v_id, c_h, c_a));
    -- a mesma ficha, nas 2 formas em que a OS pode estar na pergunta
    v_id2 := pg_temp.critica_mao('atraso_longo', 'atraso_longo:p4n3b', pg_temp.os('305'), array[pg_temp.os('305'), pg_temp.os('302')]);
    r := pg_temp.ok(r, 'P4n3b o dia dito na 2ª OS de os_ids também segura', (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id2) = 'equipe', null);
    v_id2 := pg_temp.critica_mao('atraso_longo', 'atraso_longo:p4n3c', pg_temp.os('302'), array[pg_temp.os('305')]);
    r := pg_temp.ok(r, 'P4n3c o dia dito na OS principal, fora de os_ids, também segura', (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id2) = 'equipe', null);
    -- cancelada e reserva não foram ditas: o dia some da conta
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'cliente' where service_order_id = pg_temp.os('302') and payee_id = (select id from public.payees where name = 'Roberto' and active) and dia = date '2026-11-12';
    r := pg_temp.ok(r, 'P4n3d a alocação cancelada não segura: o dia dito saiu do plano', (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) is null, null);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, condicao, condicao_tipo, condicao_ate)
    select pg_temp.os('302'), (select id from public.payees where name = 'Roberto' and active), date '2026-11-12', 'tarde', 'turno', 'reserva', 'publicada', 'motor', 'condicionada', 'material', 'material', date '2026-11-11';
    r := pg_temp.ok(r, 'P4n3e a reserva não segura: nunca foi dita a ninguém', (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) is null, null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    -- dia que o cliente ouviu: Tadeu confirmou seg 23/11, sem prometido gravado
    v_id := pg_temp.critica_mao('atraso_longo', 'atraso_longo:p4n4', pg_temp.os('306'), array[pg_temp.os('306')]);
    perform pg_temp.mostra(v_id);
    update public.service_orders set client_confirmed_for = timestamptz '2026-11-23 08:00-03' where id = pg_temp.os('306');
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n4 dia avisado ao cliente: não vence, sem prometido nenhum', pg_temp.est(v_id) = 'aberta:-' and not exists (select 1 from public.agenda_acoes a where a.pergunta_id = v_id)
      and (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) = 'cliente', v::text);
    -- a reserva nunca foi dita a ninguém, e o dia que já passou não conta
    r := pg_temp.ok(r, 'P4n4b o dia já passado não segura', (select public._agenda_pergunta_espera(q, date '2026-11-24') from public.agenda_perguntas q where q.id = v_id) is null, null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    v_id := pg_temp.critica_mao('remarcar_confirmado', 'remarcar_confirmado:p4n5', pg_temp.os('305'), array[pg_temp.os('305')]);
    perform pg_temp.mostra(v_id);
    v_id2 := pg_temp.critica_mao('dia_avisado', 'dia_avisado:p4n6', pg_temp.os('305'), array[pg_temp.os('305')]);
    perform pg_temp.mostra(v_id2);
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n5 remarcar_confirmado nunca vence', pg_temp.est(v_id) = 'aberta:-' and (select veto_espera = 'cliente' from public.agenda_perguntas where id = v_id), v::text);
    r := pg_temp.ok(r, 'P4n6 o tipo dia_avisado nunca vence: fora de veto_tipos', pg_temp.est(v_id2) = 'aberta:-' and (select veto_espera = 'tipo' from public.agenda_perguntas where id = v_id2), null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    perform pg_temp.mostra(pg_temp.q('06'));
    perform pg_temp.mostra(pg_temp.q('08'));
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n7 a de Flávio (prometido firme) e a diária (dinheiro), mostradas com prazo, não vencem', pg_temp.est(pg_temp.q('06')) = 'aberta:-' and pg_temp.est(pg_temp.q('08')) = 'aberta:-', v::text);
    v := public.agenda_decidir(pg_temp.q('06'), 1::smallint, null, 'prazo', 'pelo prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4n8 a última porta: agenda_decidir pelo prazo recusa a que espera, chamada direto', v ->> 'ok' = 'false' and v ->> 'texto' = 'Essa pergunta espera você: nada mudou.' and pg_temp.est(pg_temp.q('06')) = 'aberta:-', v::text);
    v := public.agenda_decidir(pg_temp.q('08'), 1::smallint, null, 'prazo', 'pelo prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4n9 a diária também, antes do desvio dela', v ->> 'ok' = 'false' and pg_temp.est(pg_temp.q('08')) = 'aberta:-', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    v_id := pg_temp.critica();
    perform pg_temp.mostra(v_id);
    v := public.agenda_decidir(v_id, 1::smallint, pg_temp.adm(), 'prazo', 'pelo prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4n10 o canal prazo não aceita autor: não grava o dono como quem decidiu', v ->> 'ok' = 'false' and pg_temp.est(v_id) = 'aberta:-' and (select respondida_por is null from public.agenda_perguntas where id = v_id), v::text);
    update public.agenda_config set veto_tipos = array_remove(veto_tipos, 'nao_cabe') where id;
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n11 tipo que saiu de veto_tipos depois de nascer: não vence', pg_temp.est(v_id) = 'aberta:-' and (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) = 'tipo', v::text);
    update public.agenda_config set veto_tipos = veto_tipos || '{nao_cabe}', modo_proposta = 'sombra' where id;
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n12 modo de quem pergunta fora de ligado: não vence', pg_temp.est(v_id) = 'aberta:-' and (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) = 'teste', v::text);
    update public.agenda_config set modo_proposta = 'ligado' where id;
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o freio: a crítica do motor, mostrada e vencida: 0 ações, o plano igual, as perguntas iguais fora veto_teria_em
    perform pg_temp.vale();
    v_id := pg_temp.critica();
    perform pg_temp.mostra(v_id);
    update public.agenda_config set gestor_so_propor = true where id;
    v_ver := (select versao_plano from public.agenda_config where id);
    v_n := (select count(*) from public.agenda_acoes);
    v_txt := (select md5(string_agg((to_jsonb(q) - 'veto_teria_em' - 'destrava')::text, '|' order by q.id)) from public.agenda_perguntas q);
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4n13 com o freio, a crítica vencida: só veto_teria_em, 0 ações, md5 igual, o plano igual', v ->> 'teria' = '3' and v ->> 'assumidas' = '0'
      and (select veto_teria_em = c_a from public.agenda_perguntas where id = v_id) and (select count(*) from public.agenda_acoes) = v_n and (select versao_plano from public.agenda_config where id) = v_ver
      and (select md5(string_agg((to_jsonb(q) - 'veto_teria_em' - 'destrava')::text, '|' order by q.id)) from public.agenda_perguntas q) = v_txt, v::text);
    v := public.agenda_decidir(v_id, 1::smallint, null, 'prazo', 'pelo prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4n14 com o freio, a porta recusa também', v ->> 'ok' = 'false' and pg_temp.est(v_id) = 'aberta:-', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- o teto só fecha efeito nada: a crítica fica, mesmo a que pode vencer pelo prazo
  begin
    perform pg_temp.vale();
    perform pg_temp.mostra(pg_temp.q('07'));
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P4k o teto não aplica opção: fecha as 3 mais velhas de efeito nada, e a crítica fica, mesmo podendo vencer pelo prazo',
      pg_temp.est(pg_temp.q('07')) = 'aberta:-' and pg_temp.est(pg_temp.q('06')) = 'aberta:-' and pg_temp.est(pg_temp.q('08')) = 'aberta:-' and v ->> 'assumidas' = '3' and pg_temp.est(pg_temp.q('01')) = 'resolvida:teto', v::text);
    -- só sobram críticas e quem espera acima do teto: ele passa, e diz quantas
    update public.agenda_config set perguntas_abertas_max = 3 where id;
    update public.agenda_perguntas set veto_espera = 'dono' where id in (pg_temp.q('04'), pg_temp.q('05'));
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P4k2 só críticas e quem espera acima do teto: ninguém fecha', v ->> 'assumidas' = '0' and v ->> 'acima_do_teto' = '2' and pg_temp.est(pg_temp.q('07')) = 'aberta:-', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    update public.agenda_config set veto_tipos = array_remove(veto_tipos, 'duracao') where id;
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4k3 a lista mudou depois de a pergunta nascer: fora de veto_tipos hoje não vence', pg_temp.est(pg_temp.q('02')) = 'aberta:-' and pg_temp.est(pg_temp.q('03')) = 'resolvida:prazo'
      and (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = pg_temp.q('02')) = 'tipo', v::text);
    v := public._agenda_pergunta_assumir(pg_temp.q('06'), 'prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4k4 a porta de dentro relê: chamada direto na que espera, não assume', v ->> 'assumida' = 'false' and v ->> 'motivo' = 'cliente' and pg_temp.est(pg_temp.q('06')) = 'aberta:-', v::text);
    v := public._agenda_pergunta_assumir(pg_temp.q('03'), 'prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4k6 a fechada não assume de novo', v ->> 'assumida' = 'false' and v ->> 'motivo' = 'fechada' and (select count(*) from public.agenda_acoes a where a.pergunta_id = pg_temp.q('03')) = 1, v::text);
    r := pg_temp.ok(r, 'P4k7 o caminho que não existe: 22023', pg_temp.lanca(format('select public._agenda_pergunta_assumir(%L, ''x'', current_date, now())', pg_temp.q('05'))) = '22023'
      and pg_temp.lanca(format('select public._agenda_pergunta_assumir(%L, null, current_date, now())', pg_temp.q('05'))) = '22023', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    r := pg_temp.ok(r, 'P4l o canal: inválido e nulo seguem 22023',
      pg_temp.lanca(format($s$select public.agenda_decidir(%L, 1::smallint, null, 'x', 't', %L, %L)$s$, pg_temp.q('07'), c_h, c_a)) = '22023'
      and pg_temp.lanca(format($s$select public.agenda_decidir(%L, 1::smallint, null, null, 't', %L, %L)$s$, pg_temp.q('07'), c_h, c_a)) = '22023', null);
    -- com o freio, nada passa pela porta, nem o que não é crítico
    v_id := pg_temp.estimativa(pg_temp.os('305'));
    update public.agenda_config set gestor_so_propor = true where id;
    v := public.agenda_decidir(v_id, 2::smallint, null, 'prazo', 'pelo prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4l2 agenda_decidir pelo prazo com o freio: a porta recusa, nada mudou', v ->> 'ok' = 'false' and v ->> 'texto' = 'Essa pergunta espera você: nada mudou.' and pg_temp.est(v_id) = 'aberta:-', v::text);
    update public.agenda_config set gestor_so_propor = false, modo_veto = 'sombra' where id;
    v := public.agenda_decidir(v_id, 2::smallint, null, 'prazo', 'pelo prazo', c_h, c_a);
    r := pg_temp.ok(r, 'P4l3 e em sombra', v ->> 'ok' = 'false' and v ->> 'texto' = 'Essa pergunta espera você: nada mudou.' and pg_temp.est(v_id) = 'aberta:-', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P4b: a recusa tem saída (R8.5-9)
  begin
    perform pg_temp.vale();
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    v_id := pg_temp.estimativa(pg_temp.os('305'), null, 3::smallint);  -- a opção "Me diga" não vale sem resposta: _agenda_gestor_decidir devolve ok = false
    r := pg_temp.ok(r, 'P4b0 (controle) a pergunta do efeito opcao pode vencer: a regra deixa', (select public._agenda_pergunta_espera(q, date '2026-11-10') is null and q.padrao_efeito = 'opcao' from public.agenda_perguntas q where q.id = v_id), null);
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:vetos');
    v := pg_temp.vence();
    select * into v_q from public.agenda_perguntas where id = v_id;
    r := pg_temp.ok(r, 'P4b1 ok = false: a pergunta fica aberta, com veto_espera = sem_padrao, sem carimbo', v_q.estado = 'aberta' and v_q.veto_espera = 'sem_padrao' and v_q.assumida_por is null and v ->> 'recusadas' = '1', v::text);
    r := pg_temp.ok(r, 'P4b2a registra 1 vez em gestor:vetos', (select count(*) from public.app_error_logs where action = 'gestor:vetos') = v_n + 1, null);
    v := pg_temp.vence(c_h, c_a + interval '15 minutes');
    r := pg_temp.ok(r, 'P4b3 não tenta de novo no tique seguinte: sem recusa, sem log', not v ? 'recusadas' and (select count(*) from public.app_error_logs where action = 'gestor:vetos') = v_n + 1, v::text);
    r := pg_temp.ok(r, 'P4b4 a saída: a linha não promete mais prazo, e ela segue respondível pelo número',
      pg_temp.linha(v_id, c_h, c_a) like 'Decisão %: Por quantos dias eu marco?%' and pg_temp.linha(v_id, c_h, c_a) not like '%Sem resposta%'
      and public._agenda_pergunta_linha(v_id, c_h, c_a) ->> 'veto_ate' is null
      and (public._agenda_pergunta_linha(v_id, c_h, c_a) ->> 'n') is not null, pg_temp.linha(v_id, c_h, c_a));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    -- a exceção dentro do passo: 1 pergunta não derruba a rodada, e não repete
    create or replace function public._agenda_pergunta_assumir(p_pergunta uuid, p_por text, p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
    begin
      if p_pergunta = pg_temp.q('02') then raise exception 'estourou' using errcode = 'P0001'; end if;
      return jsonb_build_object('assumida', true);
    end $f$;
    v_n := (select count(*) from public.app_error_logs where action = 'gestor:vetos');
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4b5 erro numa pergunta: registra, vira sem_padrao, e a seguinte roda',
      v ->> 'recusadas' = '1' and v ->> 'erros' = '1' and v ->> 'assumidas' = '1' and (select veto_espera from public.agenda_perguntas where id = pg_temp.q('02')) = 'sem_padrao'
      and (select count(*) from public.app_error_logs where action = 'gestor:vetos') = v_n + 1, v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    -- opção nula: nunca agenda_decidir(null) (R8.12-2)
    v_id := pg_temp.perg('chegou', 'chegou:p4:nula', pg_temp.os('305'), 'Forçada.');
    perform set_config('agenda.backfill_padrao', 'on', true);
    update public.agenda_perguntas set padrao_efeito = 'opcao', padrao_chave = 'recomendacao' where id = v_id;
    perform set_config('agenda.backfill_padrao', '', true);
    perform pg_temp.mostra(v_id);
    create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null, p_via text default 'whatsapp', p_trecho text default null, p_hoje date default public._hoje_brt(), p_agora timestamptz default now()) returns jsonb language plpgsql as $f$
    begin
      raise exception 'agenda_decidir foi chamada com opção %', p_opcao using errcode = 'P0001';
    end $f$;
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4b6 efeito opcao sem opção de verdade: sem_padrao, e agenda_decidir nem é chamada',
      (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) = 'sem_padrao' and pg_temp.est(v_id) = 'aberta:-' and coalesce(v ->> 'erros', '0') = '0', v::text);
    v_id2 := pg_temp.perg('chegou', 'chegou:p4:fora', pg_temp.os('305'), 'Forçada.', '[]', 1::smallint);
    perform set_config('agenda.backfill_padrao', 'on', true);
    update public.agenda_perguntas set padrao_efeito = 'opcao', padrao_chave = 'recomendacao' where id = v_id2;
    perform set_config('agenda.backfill_padrao', '', true);
    perform pg_temp.mostra(v_id2);
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4b7 efeito opcao com a opção fora das opções: sem_padrao, e agenda_decidir nem é chamada',
      (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id2) = 'sem_padrao' and pg_temp.est(v_id2) = 'aberta:-' and coalesce(v ->> 'erros', '0') = '0', v::text);
    v_id2 := pg_temp.perg('chegou', 'chegou:p4:sem', pg_temp.os('305'), 'Forçada.');
    perform set_config('agenda.backfill_padrao', 'on', true);
    update public.agenda_perguntas set padrao_efeito = null, padrao_chave = null where id = v_id2;
    perform set_config('agenda.backfill_padrao', '', true);
    perform pg_temp.mostra(v_id2);
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4b8 sem padrão nenhum (a aberta de antes do backfill): não vence', (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id2) = 'sem_padrao' and pg_temp.est(v_id2) = 'aberta:-', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P4c: o prometido que surgiu depois de a pergunta nascer
  begin
    perform pg_temp.vale();
    r := pg_temp.ok(r, 'P4c0 (controle) a do Giancarlo nasceu sem prometido', (select veto_espera is null from public.agenda_perguntas where id = pg_temp.q('07')) and pg_temp.linha(pg_temp.q('07'), c_h, c_a) like '%fico com a opção 1.', null);
    insert into public.os_planejamento (service_order_id, prometido_tipo, prometido_de, prometido_ate, prometido_em, prometido_fonte, atualizado_por)
    values (pg_temp.os('305'), 'firme', date '2026-11-20', date '2026-11-20', c_a, 'dono', pg_temp.adm());
    r := pg_temp.ok(r, 'P4c1 na crítica, a linha passa a dizer que espera o cliente, com a foto ainda nula',
      (select veto_espera is null from public.agenda_perguntas where id = pg_temp.q('07')) and pg_temp.linha(pg_temp.q('07'), c_h, c_a) like '%Isto espera você: mexe no dia que o cliente já sabe.', pg_temp.linha(pg_temp.q('07'), c_h, c_a));
    r := pg_temp.ok(r, 'P4c2a e a ordem também', (select e ->> 'veto_espera' from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_h, c_a)) e where e ->> 'id' = pg_temp.q('07')::text) = 'cliente', null);
    -- o efeito opcao que pode vencer: a mesma OS
    v_id := pg_temp.estimativa(pg_temp.os('305'));
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4c3 pergunta que nasceu depois... (foto nula) com prometido na OS: não vence, e a linha não promete prazo',
      pg_temp.est(v_id) = 'aberta:-' and (select veto_espera is null from public.agenda_perguntas where id = v_id) and pg_temp.linha(v_id, c_h, c_a) like '%Isto espera você%', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    -- nasce sem nada dito; o prometido chega na 2ª OS da pergunta depois de ela nascer
    v_id := pg_temp.estimativa(pg_temp.os('305'), null, 3::smallint);
    r := pg_temp.ok(r, 'P4c4 (controle) sem prometido a pergunta passa pela regra, e vira recusa por outro motivo', (select public._agenda_pergunta_espera(q, date '2026-11-10') is null from public.agenda_perguntas q where q.id = v_id), null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    update public.agenda_config set veto_tipos = veto_tipos || '{estimativa}' where id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, modo, criada_em)
    values ('estimativa', 'estimativa:p4c5', pg_temp.os('305'), array[pg_temp.os('305'), pg_temp.os('306')], 'Por quantos dias eu marco? 1) 4 dias. 2) 6 dias.',
            '[{"n": 1, "texto": "4 dias"}, {"n": 2, "texto": "6 dias"}]', 2, 'ligado', timestamptz '2026-11-09 09:00-03') returning id into v_id;
    perform pg_temp.mostra(v_id);
    insert into public.os_planejamento (service_order_id, prometido_tipo, prometido_de, prometido_ate, prometido_em, prometido_fonte, atualizado_por)
    values (pg_temp.os('306'), 'faixa', date '2026-11-23', date '2026-11-28', c_a, 'dono', pg_temp.adm());
    v_lg := (select count(*) from public.app_error_logs);
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P4c5 o prometido na 2ª OS de os_ids também segura, e sem linha de log: não é erro, é regra',
      pg_temp.est(v_id) = 'aberta:-' and (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) = 'cliente'
      and (select count(*) from public.app_error_logs) = v_lg, v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    update public.agenda_config set veto_tipos = veto_tipos || '{estimativa}' where id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, modo, criada_em)
    values ('estimativa', 'estimativa:p4c7', pg_temp.os('305'), array[pg_temp.os('306')], 'Por quantos dias eu marco? 1) 4 dias. 2) 6 dias.',
            '[{"n": 1, "texto": "4 dias"}, {"n": 2, "texto": "6 dias"}]', 2, 'ligado', timestamptz '2026-11-09 09:00-03') returning id into v_id;
    insert into public.os_planejamento (service_order_id, prometido_tipo, prometido_de, prometido_ate, prometido_em, prometido_fonte, atualizado_por)
    values (pg_temp.os('305'), 'faixa', date '2026-11-23', date '2026-11-28', c_a, 'dono', pg_temp.adm());
    r := pg_temp.ok(r, 'P4c7 o prometido na OS principal, fora de os_ids, também segura', (select public._agenda_pergunta_espera(q, date '2026-11-10') from public.agenda_perguntas q where q.id = v_id) = 'cliente', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    -- o efeito nada não muda dia: Nelson tem faixa prometida, e a §6.3 é ele
    r := pg_temp.ok(r, 'P4c6 efeito nada com prometido vence: não mexe em dia nenhum (§6.3)',
      (select pl.prometido_tipo = 'faixa' from public.os_planejamento pl where pl.service_order_id = pg_temp.os('301'))
      and (select public._agenda_pergunta_espera(q, date '2026-11-10') is null from public.agenda_perguntas q where q.id = pg_temp.q('02')), null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P4d: padrao_do_dono e AG7-37
  begin
    perform pg_temp.vale();
    perform pg_temp.mostra(pg_temp.q('01'));
    v_disp := (select count(*) from public.agenda_disponibilidade d where d.payee_id = public._agenda_dono(null));
    v_cap := (select coalesce(string_agg(k.payee_id::text || k.dia::text, ','), '') from public.agenda_capacidade(date '2026-11-16', date '2026-11-20', c_h) k where k.payee_id = public._agenda_dono(null));
    r := pg_temp.ok(r, 'P4d0 (controle) o padrão do dono: abre_e_fecha, efeito nada, pode vencer', (select q.padrao_chave = 'abre_e_fecha' and q.padrao_efeito = 'nada' and public._agenda_pergunta_espera(q, date '2026-11-10') is null from public.agenda_perguntas q where q.id = pg_temp.q('01')), null);
    v := pg_temp.vence();
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('01');
    select * into v_a from public.agenda_acoes a where a.pergunta_id = pg_temp.q('01') and a.tipo = 'assumir';
    r := pg_temp.ok(r, 'P4d1 AG7-37: venceu e não grava linha do dono em agenda_disponibilidade (nada de dias em campo)',
      v_q.estado = 'resolvida' and (select count(*) from public.agenda_disponibilidade d where d.payee_id = public._agenda_dono(null)) = v_disp, format('%s linhas', v_disp));
    r := pg_temp.ok(r, 'P4d2 AG7-37: a capacidade do dono é a mesma: só para abrir e fechar, nunca inteiro',
      (select coalesce(string_agg(k.payee_id::text || k.dia::text, ','), '') from public.agenda_capacidade(date '2026-11-16', date '2026-11-20', c_h) k where k.payee_id = public._agenda_dono(null)) = v_cap, null);
    r := pg_temp.ok(r, 'P4d3 AG7-37: a frase diz o padrão, sem "marquei", e sem nome de OS no *desfaz*',
      v_a.texto = 'Você: sem resposta até ter 10/11 às 18:00, continuo contando você só para abrir e fechar. *desfaz* mostra a lista.' and v_a.service_order_id is null, v_a.texto);
    r := pg_temp.ok(r, 'P4d4 o motivo gravado diz o mesmo', v_q.resolvida_motivo = 'Sem resposta até ter 10/11 às 18:00: continuo contando você só para abrir e fechar.', v_q.resolvida_motivo);
    r := pg_temp.ok(r, 'P4d5 a variável que muda o padrão do dono não foi ligada', coalesce(current_setting('agenda.dias_padrao_do_dono', true), '') = '', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    v_disp := (select count(*) from public.agenda_disponibilidade d where d.payee_id = public._agenda_dono(null));
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P4d6 AG7-37 pelo teto também: fechou e não grava linha do dono',
      pg_temp.est(pg_temp.q('01')) = 'resolvida:teto' and (select count(*) from public.agenda_disponibilidade d where d.payee_id = public._agenda_dono(null)) = v_disp
      and (select a.texto from public.agenda_acoes a where a.pergunta_id = pg_temp.q('01')) = 'Você: havia mais de 5 perguntas abertas; continuo contando você só para abrir e fechar. *desfaz* mostra a lista.',
      (select a.texto from public.agenda_acoes a where a.pergunta_id = pg_temp.q('01')));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P4e: o efeito opcao até o carimbo, pelo caminho de verdade
  begin
    perform pg_temp.vale();
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    v_ch := public._agenda_gestor_perguntas_da_os(pg_temp.os('305'), c_h, c_a, true) ->> 'chave';
    if v_ch is null then
      create or replace function public._agenda_gestor_perguntas_da_os(p_os uuid, p_hoje date, p_agora timestamptz, p_seco boolean) returns jsonb language sql as $f$
        select jsonb_build_object('chave', 'estimativa:p4e')
      $f$;
      v_ch := 'estimativa:p4e';
    end if;
    v_id := pg_temp.estimativa(pg_temp.os('305'), v_ch);
    v := pg_temp.vence();
    select * into v_q from public.agenda_perguntas where id = v_id;
    r := pg_temp.ok(r, 'P4e1 efeito opcao: decide pelo canal prazo a opção padrão, e o carimbo vem depois', v_q.estado in ('resolvida', 'respondida') and v_q.opcao_escolhida = 2 and v_q.assumida_por = 'prazo' and v_q.assumida_em = c_a and v ->> 'assumidas' = '3' and v ->> 'recusadas' = '0', v::text);
    r := pg_temp.ok(r, 'P4e2 a estimativa gravada veio da opção, com o *desfaz* dela', (select pl.dias = 6 from public.os_planejamento pl where pl.service_order_id = pg_temp.os('305'))
      and exists (select 1 from public.agenda_acoes a where a.pergunta_id = v_id and a.tipo = 'estimar'), null);
    r := pg_temp.ok(r, 'P4e3 quem decide é o sistema: respondida_por nulo', v_q.respondida_por is null, null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- o canal prazo de agenda_decidir, sem autor: respondida_via e resposta
  begin
    perform pg_temp.vale();
    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_proposta = 'ligado' where id;
    v_id := pg_temp.estimativa(pg_temp.os('305'));
    v := public.agenda_decidir(v_id, 3::smallint, null, 'prazo', 'Sem resposta', c_h, c_a);
    r := pg_temp.ok(r, 'P4e4 o canal prazo passa pela conferência de agenda_decidir e chega a quem decide', v ->> 'texto' = 'Essa opção não vale sem resposta: nada mudou.', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p4$;

-- ── P5. O teto ──────────────────────────────────────────────────────────────────────────────────────
do $p5$
declare
  r     jsonb := '[]';
  v     jsonb;
  v_id  uuid;
  v_n   int;
  c_h   constant date := date '2026-11-10';
  c_a   constant timestamptz := timestamptz '2026-11-10 18:05-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.vale();
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P5a 8 abertas, teto 5: as 3 mais velhas que podem vencer', v ->> 'assumidas' = '3' and v ->> 'acima_do_teto' = '0' and v ->> 'teria' = '0'
      and pg_temp.est(pg_temp.q('01')) = 'resolvida:teto' and pg_temp.est(pg_temp.q('02')) = 'resolvida:teto' and pg_temp.est(pg_temp.q('03')) = 'resolvida:teto'
      and pg_temp.est(pg_temp.q('04')) = 'aberta:-' and pg_temp.est(pg_temp.q('05')) = 'aberta:-', v::text);
    r := pg_temp.ok(r, 'P5b nunca a que espera: Flávio, a crítica e a diária', pg_temp.est(pg_temp.q('06')) = 'aberta:-' and pg_temp.est(pg_temp.q('07')) = 'aberta:-' and pg_temp.est(pg_temp.q('08')) = 'aberta:-', null);
    r := pg_temp.ok(r, 'P5c o texto do teto (§6.3)', (select a.texto from public.agenda_acoes a where a.pergunta_id = pg_temp.q('02')) = 'Nelson: havia mais de 5 perguntas abertas; ficaram os 3 dias pela estimativa. *desfaz Nelson* volta a pergunta.',
      (select a.texto from public.agenda_acoes a where a.pergunta_id = pg_temp.q('02')));
    r := pg_temp.ok(r, 'P5d o motivo gravado', (select q.resolvida_motivo from public.agenda_perguntas q where q.id = pg_temp.q('02')) = 'Havia mais de 5 perguntas abertas: ficaram os 3 dias pela estimativa.', null);
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P5e 2× = 1×: dentro do teto, nada', v = '{"assumidas": 0, "teria": 0, "acima_do_teto": 0}'::jsonb and (select count(*) from public.agenda_acoes where tipo = 'assumir') = 3, v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    update public.agenda_perguntas set veto_espera = 'dono' where id in (pg_temp.q('01'), pg_temp.q('02'), pg_temp.q('03'), pg_temp.q('04'), pg_temp.q('05'));
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P5f se todas esperam, o teto passa, e diz quantas sobraram (AG7-24)', v ->> 'assumidas' = '0' and v ->> 'acima_do_teto' = '3', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id in (pg_temp.q('03'), pg_temp.q('04'));
    insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, criada_em) values ('conferencia', 'conferencia:p5a', c_h, 'Como foi?', 'ligado', c_a), ('conferencia', 'conferencia:p5b', c_h - 1, 'Como foi?', 'ligado', c_a);
    insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em, expira_em) values ('parada', 'parada:p5:vencida', 'Vencida.', 'ligado', timestamptz '2026-10-01 09:00-03', c_a - interval '1 hour');
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P5g 6 que valem: a conferencia e a expirada não contam (e a expirada, a mais velha, não é a escolhida)',
      v ->> 'assumidas' = '1' and pg_temp.est(pg_temp.q('01')) = 'resolvida:teto'
      and (select estado from public.agenda_perguntas where chave = 'parada:p5:vencida') = 'aberta', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id in (pg_temp.q('04'), pg_temp.q('05'), pg_temp.q('08'));
    r := pg_temp.ok(r, 'P5h no teto, exatas 5, nada', public._agenda_comunicar_teto(c_h, c_a) ->> 'assumidas' = '0' and pg_temp.est(pg_temp.q('01')) = 'aberta:-', null);
    update public.agenda_config set perguntas_abertas_max = 4 where id;
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P5i o teto vem do parâmetro, e o texto também', v ->> 'assumidas' = '1'
      and (select a.texto from public.agenda_acoes a where a.pergunta_id = pg_temp.q('01')) like '%havia mais de 4 perguntas abertas%', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    -- só efeito nada: a opção que o dono nunca leu não se aplica pelo teto
    update public.agenda_perguntas set veto_espera = 'dono' where id in (pg_temp.q('01'), pg_temp.q('02'), pg_temp.q('03'), pg_temp.q('04'), pg_temp.q('05'));
    update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
    v_id := pg_temp.estimativa(pg_temp.os('305'));
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P5j o teto nunca aplica opção: a estimativa pode vencer pelo prazo, não pelo teto', pg_temp.est(v_id) = 'aberta:-' and v ->> 'assumidas' = '0' and (select public._agenda_pergunta_espera(q, date '2026-11-10') is null from public.agenda_perguntas q where q.id = v_id), v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- com um erro numa pergunta, a rodada segue e registra
    perform pg_temp.vale();
    create or replace function public._agenda_pergunta_assumir(p_pergunta uuid, p_por text, p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
    begin
      if p_pergunta = pg_temp.q('01') then raise exception 'estourou' using errcode = 'P0001'; end if;
      return jsonb_build_object('assumida', true);
    end $f$;
    v_n := (select count(*) from public.app_error_logs where action = 'comunicar:teto');
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P5k erro numa pergunta: registra em comunicar:teto e segue', v ->> 'assumidas' = '2' and (select count(*) from public.app_error_logs where action = 'comunicar:teto') = v_n + 1, v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p5$;

-- ── P6. Sombra, freio, desligado ────────────────────────────────────────────────────────────────────
do $p6$
declare
  r      jsonb := '[]';
  v      jsonb;
  v_md5  text;
  v_n    int;
  v_ver  bigint;
  x      record;
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 18:05-03';
  -- tudo o que importa de uma pergunta, menos a coluna da medição
  c_q    constant text := $s$select md5(string_agg(to_jsonb(q) - 'veto_teria_em' - 'destrava' #>> '{}', '|' order by q.id)) from public.agenda_perguntas q$s$;
begin
  if not pg_temp.na_bancada() then return; end if;
  for x in select * from (values ('P6', 'sombra', false, 'modo_veto em sombra'), ('P6b', 'ligado', true, 'ligado com *gestor, só propor*')) t(n, modo, freio, rot) loop
    begin
      update public.agenda_config set modo_veto = x.modo, gestor_so_propor = x.freio where id;
      execute c_q into v_md5;
      v_n := (select count(*) from public.agenda_acoes);
      v_ver := (select versao_plano from public.agenda_config where id);
      v := pg_temp.vence();
      r := pg_temp.ok(r, format('%sa %s: o prazo vencido não decide nada: só veto_teria_em', x.n, x.rot),
        v ->> 'teria' = '2' and v ->> 'assumidas' = '0'
        and (select count(*) from public.agenda_perguntas q where q.veto_teria_em = c_a) = 2
        and (select count(*) from public.agenda_acoes) = v_n and (select versao_plano from public.agenda_config where id) = v_ver, v::text);
      r := pg_temp.ok(r, format('%sb %s: as perguntas, fora veto_teria_em, ficam iguais, byte a byte', x.n, x.rot), (select md5(string_agg(to_jsonb(q) - 'veto_teria_em' - 'destrava' #>> '{}', '|' order by q.id)) from public.agenda_perguntas q) = v_md5, null);
      v := pg_temp.vence(c_h, c_a + interval '15 minutes');
      r := pg_temp.ok(r, format('%sc %s: de novo, a 1ª hora fica, e a saída é a de antes', x.n, x.rot),
        (select count(*) from public.agenda_perguntas q where q.veto_teria_em = c_a) = 2 and not v ? 'teria', v::text);
      r := pg_temp.ok(r, format('%sd %s: as 2 seguem abertas', x.n, x.rot), pg_temp.est(pg_temp.q('02')) = 'aberta:-' and pg_temp.est(pg_temp.q('03')) = 'aberta:-', null);
      v := public._agenda_comunicar_teto(c_h, c_a);
      r := pg_temp.ok(r, format('%se %s: o teto também só marca, nas 3 mais velhas, sem contar 2× quem já tinha', x.n, x.rot),
        v ->> 'assumidas' = '0' and v ->> 'teria' = '1' and v ->> 'acima_do_teto' = '3'
        and (select count(*) from public.agenda_perguntas q where q.veto_teria_em is not null) = 3 and (select count(*) from public.agenda_acoes) = v_n, v::text);
      raise exception using errcode = 'P0001', message = '__desfaz__';
    exception when sqlstate 'P0001' then
      if sqlerrm <> '__desfaz__' then raise; end if;
    end;
  end loop;

  begin
    -- em sombra a medição usa a mesma regra de quem vence: quem espera não "teria vencido"
    update public.agenda_config set modo_veto = 'sombra', gestor_so_propor = false where id;
    perform pg_temp.mostra(pg_temp.q('07'));
    perform pg_temp.mostra(pg_temp.q('06'));
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P6f em sombra, a crítica que pode vencer entra na medição; a que espera o cliente, não', (select q.veto_teria_em is null from public.agenda_perguntas q where q.id = pg_temp.q('06'))
      and (select q.veto_teria_em is not null from public.agenda_perguntas q where q.id = pg_temp.q('07')) and v ->> 'teria' = '3', v::text);
    update public.agenda_perguntas set veto_espera = 'dono' where id in (pg_temp.q('01'), pg_temp.q('04'));
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P6g em sombra, o teto também não marca quem espera: pula para a que pode vencer', (select q.veto_teria_em is null from public.agenda_perguntas q where q.id = pg_temp.q('01'))
      and (select q.veto_teria_em is not null from public.agenda_perguntas q where q.id = pg_temp.q('05')) and v ->> 'teria' = '1', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    -- a rodada de verdade, com o freio: a mesma que o pg_cron chama
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = true, modo_marcar_sozinho = 'ligado', modo_compre_ate = 'sombra' where id;
    v := public.agenda_gestor_rodar(c_h, c_a);
    r := pg_temp.ok(r, 'P6b2 agenda_gestor_rodar com o freio: vetos só teria; nada fechou',
      v #>> '{contagens,vetos,teria}' = '2' and v #>> '{contagens,vetos,assumidas}' = '0' and pg_temp.est(pg_temp.q('02')) = 'aberta:-'
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'assumir'), left(v::text, 600));
    v := public.agenda_comunicar_rodar(c_h, c_a);
    r := pg_temp.ok(r, 'P6b3 agenda_comunicar_rodar com o freio: nada fechou', (v ->> 'rodou')::boolean and v #>> '{contagens,teto,assumidas}' = '0'
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'assumir') and pg_temp.est(pg_temp.q('01')) = 'aberta:-', (v -> 'contagens')::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    update public.agenda_config set modo_veto = 'desligado', gestor_so_propor = false where id;
    v := pg_temp.vence();
    r := pg_temp.ok(r, 'P6c desligado: nem veto_teria_em, e a saída é a de antes', not exists (select 1 from public.agenda_perguntas q where q.veto_teria_em is not null)
      and not v ? 'teria' and not v ? 'assumidas' and not v ? 'recusadas', v::text);
    v := public._agenda_comunicar_teto(c_h, c_a);
    r := pg_temp.ok(r, 'P6d desligado: o teto não conta nada', v ->> 'pulado' = 'true', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    -- o freio solto depois: o que venceu durante o freio estava escrito para o dono, e cai no tique seguinte
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = true where id;
    perform pg_temp.vence();
    update public.agenda_config set gestor_so_propor = false where id;
    v := pg_temp.vence(c_h, c_a + interval '15 minutes');
    r := pg_temp.ok(r, 'P6e soltar o freio: fecha só o que tinha o prazo escrito e mostrado', v ->> 'assumidas' = '2' and pg_temp.est(pg_temp.q('02')) = 'resolvida:prazo' and pg_temp.est(pg_temp.q('05')) = 'aberta:-', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p6$;

-- ── P7. A volta ─────────────────────────────────────────────────────────────────────────────────────
do $p7$
declare
  r      jsonb := '[]';
  v      jsonb;
  v_q    public.agenda_perguntas;
  v_a    public.agenda_acoes;
  v_ant  public.agenda_perguntas;
  v_id   uuid;
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 18:05-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  -- da frase do dono ao estado depois
  begin
    perform pg_temp.vale();
    -- Nelson existe 3 vezes na carteira do replay; Tadeu, 1: é com ele que a frase vai até o fim. O nome ambíguo tem saída: o resolvedor pergunta qual.
    v_id := pg_temp.perg('duracao', 'duracao:' || pg_temp.os('306'), pg_temp.os('306'), 'Quantos dias leva Tadeu (OS-F6), e com quem? Guardei lugar a partir de seg 23/11; preciso saber até sex 20/11.');
    perform pg_temp.mostra(v_id);
    perform pg_temp.vence();
    v := public.agenda_desfazer_dito(pg_temp.adm(), 'Nelson', 'whatsapp', date '2026-11-11', timestamptz '2026-11-11 09:00-03');
    r := pg_temp.ok(r, 'P7a0 *desfaz Nelson* com 3 Nelsons na carteira: pergunta qual, e nada muda', v ->> 'ok' = 'false' and v ->> 'status' = 'ambiguo' and v ->> 'texto' like 'Qual Nelson:%OS-F1%', v::text);
    select * into v_ant from public.agenda_perguntas where id = v_id;
    v := public.agenda_desfazer_dito(pg_temp.adm(), 'Tadeu', 'whatsapp', date '2026-11-11', timestamptz '2026-11-11 09:00-03');
    r := pg_temp.ok(r, 'P7a *desfaz Tadeu*: a frase da §6.3', v ->> 'ok' = 'true' and v ->> 'texto' = 'Desfeito: a pergunta sobre Tadeu volta a esperar você.', v::text);
    select * into v_q from public.agenda_perguntas where chave = v_ant.chave and estado = 'aberta';
    r := pg_temp.ok(r, 'P7c a pergunta volta: nova, mesma chave, tipo, OS e texto, com o padrão e sem prazo',
      v_q.id is not null and v_q.id <> v_ant.id and v_q.tipo = 'duracao' and v_q.service_order_id = pg_temp.os('306') and v_q.texto = v_ant.texto and v_q.modo = 'ligado'
      and v_q.padrao_chave = 'estimativa' and v_q.veto_espera is null and v_q.veto_ate is null and v_q.mostrada_vezes = 0 and v_q.assumida_por is null, to_jsonb(v_q)::text);
    r := pg_temp.ok(r, 'P7d a fechada fica como foi', pg_temp.est(v_ant.id) = 'resolvida:prazo', null);
    select * into v_a from public.agenda_acoes where pergunta_id = v_ant.id and tipo = 'assumir';
    r := pg_temp.ok(r, 'P7e a ação fica desfeita, pela ação desfazer do dono', v_a.desfeita_em = timestamptz '2026-11-11 09:00-03' and v_a.desfeita_por = pg_temp.adm()
      and (select a.tipo = 'desfazer' and a.origem = 'dono' and a.desfaz_a = v_a.id and a.service_order_id = pg_temp.os('306') from public.agenda_acoes a where a.id = v_a.desfeita_pela), null);
    v := public.agenda_desfazer(v_a.id, pg_temp.adm(), 'dono', date '2026-11-11', timestamptz '2026-11-11 09:01-03');
    r := pg_temp.ok(r, 'P7f desfazer de novo: recusa', v ->> 'ok' = 'false' and v ->> 'texto' = 'Isso já foi desfeito.', v::text);
    perform pg_temp.mostra(v_q.id, timestamptz '2026-11-12 18:00-03');
    v := pg_temp.vence(date '2026-11-12', timestamptz '2026-11-12 18:05-03');
    r := pg_temp.ok(r, 'P7g a pergunta que voltou pode vencer de novo: só depois de mostrada com prazo', v ->> 'assumidas' = '1' and pg_temp.est(v_q.id) = 'resolvida:prazo', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P7b: a janela de 2 dias úteis às 18:00
  begin
    perform pg_temp.vale();
    perform pg_temp.vence();
    select * into v_a from public.agenda_acoes where pergunta_id = pg_temp.q('02') and tipo = 'assumir';
    r := pg_temp.ok(r, 'P7b1 janela: assumida ter 18:05 = até qui 18:00, não 24 h', v_a.desfazivel_ate = timestamptz '2026-11-12 18:00-03', v_a.desfazivel_ate::text);
    v := public.agenda_desfazer(v_a.id, pg_temp.adm(), 'dono', date '2026-11-12', timestamptz '2026-11-12 18:01-03');
    r := pg_temp.ok(r, 'P7b2 depois da janela: recusa com saída, e nada muda', v ->> 'ok' = 'false' and v ->> 'texto' = 'Não dá mais para reabrir a pergunta: passou o prazo. Se quiser mudar, me diga com as suas palavras.'
      and pg_temp.est(pg_temp.q('02')) = 'resolvida:prazo' and (select desfeita_em is null from public.agenda_acoes where id = v_a.id)
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'duracao' and q.estado = 'aberta'), v::text);
    v := public.agenda_desfazer(v_a.id, pg_temp.adm(), 'dono', date '2026-11-12', timestamptz '2026-11-12 17:59-03');
    r := pg_temp.ok(r, 'P7b3 no último minuto da janela, volta', v ->> 'ok' = 'true', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    v_id := pg_temp.perg('parada', 'parada:p7:sexta', pg_temp.os('303'), 'Vanderlei (OS-F3) está em andamento e não andou desde sex 30/10. Parou?');
    perform pg_temp.mostra(v_id, timestamptz '2026-11-13 18:00-03');
    perform pg_temp.vence(date '2026-11-13', timestamptz '2026-11-13 18:05-03');
    r := pg_temp.ok(r, 'P7b4 janela: assumida sex 18:05 = até ter 18:00: o fim de semana não come o prazo',
      (select a.desfazivel_ate from public.agenda_acoes a where a.pergunta_id = v_id) = timestamptz '2026-11-17 18:00-03', (select a.desfazivel_ate::text from public.agenda_acoes a where a.pergunta_id = v_id));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- P7b: sem OS, sem *desfaz <nome>*
  begin
    perform pg_temp.vale();
    perform pg_temp.mostra(pg_temp.q('04'));
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id in (pg_temp.q('02'), pg_temp.q('03'));
    perform pg_temp.vence();
    select * into v_a from public.agenda_acoes where pergunta_id = pg_temp.q('04') and tipo = 'assumir';
    r := pg_temp.ok(r, 'P7b5 sem OS: a ação não promete *desfaz <nome>*', v_a.texto = 'Sem resposta até ter 10/11 às 18:00, fiquei com 7 dias úteis para quem não tem outro prazo. *desfaz* mostra a lista.' and v_a.service_order_id is null
      and v_a.texto !~ '\*desfaz [^*]+\*', v_a.texto);
    v := public.agenda_desfazer_dito(pg_temp.adm(), 'Correa', 'whatsapp', date '2026-11-11', timestamptz '2026-11-11 15:00-03');
    r := pg_temp.ok(r, 'P7b6 (por isso) *desfaz Correa* não acha nada: nenhuma OS tem esse nome', v ->> 'ok' = 'false' and pg_temp.est(pg_temp.q('04')) = 'resolvida:prazo', v::text);
    v := public.agenda_desfazer_dito(pg_temp.adm(), null, 'whatsapp', date '2026-11-11', timestamptz '2026-11-11 15:00-03');
    r := pg_temp.ok(r, 'P7b7 *desfaz* sozinho, com uma só: reabre', v ->> 'ok' = 'true' and v ->> 'texto' = 'Desfeito: a pergunta sobre os fornecedores volta a esperar você.'
      and exists (select 1 from public.agenda_perguntas q where q.chave = 'fornecedores_prazo:correa' and q.estado = 'aberta'), v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    perform pg_temp.mostra(pg_temp.q('04'));
    perform pg_temp.vence();
    v := public.agenda_desfazer_dito(pg_temp.adm(), null, 'whatsapp', date '2026-11-11', timestamptz '2026-11-11 15:00-03');
    r := pg_temp.ok(r, 'P7b8 *desfaz* sozinho, com mais de uma: mostra a lista, com a sem OS pelo próprio texto', v ->> 'status' = 'ambiguo' and v ->> 'texto' like 'Qual?%fornecedores%' or (v ->> 'status' = 'ambiguo' and v ->> 'texto' like 'Qual?%prazo%'), v::text);
    r := pg_temp.ok(r, 'P7b9 a lista não fecha nada', pg_temp.est(pg_temp.q('04')) = 'resolvida:prazo' and pg_temp.est(pg_temp.q('02')) = 'resolvida:prazo', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- o padrão do dono volta sem dias, e a validade que passou não volta vencida
  begin
    perform pg_temp.vale();
    perform pg_temp.mostra(pg_temp.q('01'));
    update public.agenda_perguntas set expira_em = timestamptz '2026-11-10 23:00-03' where id = pg_temp.q('01');
    perform pg_temp.vence();
    v_id := (select a.id from public.agenda_acoes a where a.pergunta_id = pg_temp.q('01'));
    v := public.agenda_desfazer(v_id, pg_temp.adm(), 'dono', date '2026-11-11', timestamptz '2026-11-11 09:00-03');
    r := pg_temp.ok(r, 'P7h a do dono: a frase, e a validade que passou não volta vencida', v ->> 'texto' = 'Desfeito: a pergunta sobre os seus dias em campo volta a esperar você.'
      and (select q.expira_em > timestamptz '2026-11-11 09:00-03' from public.agenda_perguntas q where q.id = (v ->> 'pergunta_id')::uuid), v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    perform pg_temp.vence();
    v_id := (select a.id from public.agenda_acoes a where a.pergunta_id = pg_temp.q('02') and a.tipo = 'assumir');
    select * into v_ant from public.agenda_perguntas where id = pg_temp.q('02');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, modo) values ('duracao', v_ant.chave, pg_temp.os('301'), array[pg_temp.os('301')], 'A vigia perguntou de novo.', 'ligado');
    v := public.agenda_desfazer(v_id, pg_temp.adm(), 'dono', date '2026-11-11', timestamptz '2026-11-11 09:00-03');
    r := pg_temp.ok(r, 'P7i se a vigia já perguntou de novo, nada duplica, e o texto continua verdade', v ->> 'ok' = 'true' and v ->> 'pergunta_id' is null
      and (select count(*) from public.agenda_perguntas q where q.chave = v_ant.chave and q.estado = 'aberta') = 1, v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = pg_temp.q('03');
    perform pg_temp.vence();
    v := public.agenda_acao_desfazivel('a ultima', date '2026-11-11', timestamptz '2026-11-11 09:00-03');
    r := pg_temp.ok(r, 'P7j *desfaz a última* acha a assumir', (select a.tipo from public.agenda_acoes a where a.id = (v ->> 'acao_id')::uuid) = 'assumir', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p7$;

-- ── P8. A rodada ────────────────────────────────────────────────────────────────────────────────────
do $p8$
declare
  r      jsonb := '[]';
  v      jsonb;
  w      jsonb;
  v_n    int;
  v_src  text;
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 18:05-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.vale();
    v_n := (select count(*) from public.agenda_vigia_rodadas where rotina = 'comunicar');
    v := public.agenda_comunicar_rodar(c_h, c_a);
    -- (7f P5) com 20261109101000 os passos da equipe existem: o previsto pula fora do dia, e o dos convites vencidos não acha nenhum ({vencidos: 0}, a 1ª leitura)
    r := pg_temp.ok(r, 'P8a a rodada: destrava e teto rodam, o da quinta (P4) pula fora do dia, os do P5 pulam por não existir (ou, com o P5, pulam ou não acham nada), e grava 1 linha',
      (v ->> 'rodou')::boolean and v #>> '{contagens,teto,assumidas}' = '3' and v #> '{contagens,destrava}' ? 'atualizadas'
      and v #>> '{contagens,quinta,pulado}' = 'true' and v #>> '{contagens,previsto,pulado}' = 'true'
      and (v #>> '{contagens,convites_vencidos,pulado}' = 'true' or v #> '{contagens,convites_vencidos}' = '{"vencidos": 0}'::jsonb)
      and (select count(*) from public.agenda_vigia_rodadas where rotina = 'comunicar') = v_n + 1 and v -> 'avisos' = '[]'::jsonb and v -> 'falhas' = '[]'::jsonb and v ->> 'parou_no' is null, v::text);
    r := pg_temp.ok(r, 'P8b sem o passo vetos (R8.5-8)', not v -> 'contagens' ? 'vetos', null);
    r := pg_temp.ok(r, 'P8c a linha da rodada: rotina, modos, duração', (select x.duracao_ms >= 0 and x.contagens -> 'modos' ->> 'veto' = 'ligado' and x.erros = 0 from public.agenda_vigia_rodadas x where x.rotina = 'comunicar' order by x.rodou_em desc limit 1), null);
    w := public.agenda_comunicar_rodar(c_h, c_a + interval '15 minutes');
    r := pg_temp.ok(r, 'P8d 2× = 1×: a 2ª não assume nada, e o destrava já foi', w #>> '{contagens,teto,assumidas}' = '0' and w #>> '{contagens,destrava,pulado}' = 'true' and (select count(*) from public.agenda_acoes where tipo = 'assumir') = 3, w::text);
    w := pg_temp.vence(c_h, c_a + interval '15 minutes');
    r := pg_temp.ok(r, 'P8e o prazo depois do teto: nada repetido', not w ? 'assumidas', w::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    v := pg_temp.vence();
    w := pg_temp.vence(c_h, c_a + interval '1 minute');
    r := pg_temp.ok(r, 'P8f o prazo 2× = 1×: as ações são as mesmas, e o tique ocioso devolve as chaves de antes', v ->> 'assumidas' = '2' and not w ? 'assumidas' and not w ? 'teria'
      and (select count(*) from public.agenda_acoes where tipo = 'assumir') = 2, w::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    v := public.agenda_comunicar_rodar(date '2026-11-15', timestamptz '2026-11-15 18:05-03');
    r := pg_temp.ok(r, 'P8g domingo: nada', v = '{"rodou": false, "motivo": "domingo"}'::jsonb and pg_temp.est(pg_temp.q('01')) = 'aberta:-', v::text);
    update public.agenda_config set modo_bloco_agenda = 'desligado', modo_veto = 'desligado', modo_lote_dono = 'desligado', modo_equipe_previsto = 'desligado', modo_equipe_convite = 'desligado', modo_cliente_camadas = 'desligado' where id;
    v_n := (select count(*) from public.agenda_vigia_rodadas where rotina = 'comunicar');
    v := public.agenda_comunicar_rodar(c_h, c_a);
    r := pg_temp.ok(r, 'P8h os 6 desligados: nada, nem a linha', (v ->> 'rodou')::boolean is false and (select count(*) from public.agenda_vigia_rodadas where rotina = 'comunicar') = v_n, v::text);
    r := pg_temp.ok(r, 'P8i sem o dia ou a hora: 22023', pg_temp.lanca($q$select public.agenda_comunicar_rodar(null, now())$q$) = '22023' and pg_temp.lanca($q$select public.agenda_comunicar_rodar(current_date, null)$q$) = '22023', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  r := pg_temp.ok(r, 'P8j sem set statement_timeout na definição (R8.5-7): nenhuma função nova prende configuração além do search_path',
    (select bool_and(p.proconfig = array['search_path=public']) and count(*) = 9 from pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in ('_agenda_pergunta_espera', '_agenda_pergunta_frases', '_agenda_pergunta_linha', '_agenda_pergunta_assumir', '_agenda_destrava', '_agenda_comunicar_destrava', '_agenda_comunicar_teto', 'agenda_perguntas_em_ordem', 'agenda_comunicar_rodar')),
    (select string_agg(p.proname || ':' || p.proconfig::text, ', ') from pg_proc p where p.proname = 'agenda_comunicar_rodar'));

  v_src := (select p.prosrc from pg_proc p where p.oid = 'public._agenda_gestor_vetos(date, timestamptz)'::regprocedure);
  r := pg_temp.ok(r, 'P8j2 as travas do bloco novo na ordem do achado 13: agenda_plano, depois agenda_vetos, e só antes da 1ª que aplica (uma conexão só não prova espera)',
    array_length(regexp_split_to_array(v_src, 'hashtext\(''agenda_plano''\)'), 1) = 3 and array_length(regexp_split_to_array(v_src, 'hashtext\(''agenda_vetos''\)'), 1) = 3
    and position('if not v_trava then' in split_part(v_src, 'FASE 7f: (7f P2, §5.2', 2)) < position('agenda_plano' in split_part(v_src, 'FASE 7f: (7f P2, §5.2', 2))
    and position('agenda_plano' in split_part(v_src, 'FASE 7f: (7f P2, §5.2', 2)) < position('agenda_vetos' in split_part(v_src, 'FASE 7f: (7f P2, §5.2', 2)), null);

  begin
    -- 1 passo que falha não derruba os outros
    perform pg_temp.vale();
    create or replace function public._agenda_comunicar_quinta(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
    begin
      raise exception 'estourou' using errcode = 'P0001';
    end $f$;
    -- (7f P5) o passo previsto existe desde 20261109101000: o dublê é create or replace, como o da quinta (P4)
    create or replace function public._agenda_comunicar_previsto(p_hoje date, p_agora timestamptz) returns jsonb language sql as $f$ select '{"ok": 1}'::jsonb $f$;
    v_n := (select count(*) from public.app_error_logs where action = 'comunicar:quinta');
    v := public.agenda_comunicar_rodar(c_h, c_a);
    r := pg_temp.ok(r, 'P8k erro de um passo: registra em comunicar:<passo>, a linha sai, e o passo seguinte roda',
      v ->> 'erros' = '1' and v -> 'falhas' -> 0 ->> 'passo' = 'quinta' and v #>> '{contagens,previsto,ok}' = '1' and v ->> 'parou_no' is null
      and (select count(*) from public.app_error_logs where action = 'comunicar:quinta') = v_n + 1
      and (select x.erros from public.agenda_vigia_rodadas x where x.rotina = 'comunicar' order by x.rodou_em desc limit 1) = 1, v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- query_canceled: para, registra, grava a rodada com parou_no; o passo seguinte não roda
    perform pg_temp.vale();
    create or replace function public._agenda_comunicar_quinta(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
    begin
      raise exception 'canceling statement due to statement timeout' using errcode = '57014';
    end $f$;
    -- (7f P5) o passo previsto existe desde 20261109101000: o dublê é create or replace, como o da quinta (P4)
    create or replace function public._agenda_comunicar_previsto(p_hoje date, p_agora timestamptz) returns jsonb language sql as $f$ select '{"ok": 1}'::jsonb $f$;
    v := public.agenda_comunicar_rodar(c_h, c_a);
    r := pg_temp.ok(r, 'P8l query_canceled (57014): parou_no, a linha da rodada sai, e o passo seguinte não roda', v ->> 'parou_no' = 'quinta' and not v -> 'contagens' ? 'previsto'
      and (select x.contagens ->> 'parou_no' from public.agenda_vigia_rodadas x where x.rotina = 'comunicar' order by x.rodou_em desc limit 1) = 'quinta', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o relógio entre os passos: 5 s é o mínimo do CHECK
    perform pg_temp.vale();
    update public.agenda_config set comunicar_tempo_max = interval '5 seconds' where id;
    create or replace function public._agenda_comunicar_quinta(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
    begin
      perform pg_sleep(5.2);
      return '{"demorou": true}'::jsonb;
    end $f$;
    -- (7f P5) o passo previsto existe desde 20261109101000: o dublê é create or replace, como o da quinta (P4)
    create or replace function public._agenda_comunicar_previsto(p_hoje date, p_agora timestamptz) returns jsonb language sql as $f$ select '{"ok": 1}'::jsonb $f$;
    v := public.agenda_comunicar_rodar(c_h, c_a);
    r := pg_temp.ok(r, 'P8m passou de comunicar_tempo_max entre 2 passos: para, grava parou_no = o que não rodou, sem erro', v ->> 'parou_no' = 'previsto' and v #>> '{contagens,quinta,demorou}' = 'true' and not v -> 'contagens' ? 'previsto' and v ->> 'erros' = '0', v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- avisos: o que a quinta (P4) devolver
    perform pg_temp.vale();
    create or replace function public._agenda_comunicar_quinta(p_hoje date, p_agora timestamptz) returns jsonb language sql as $f$ select '{"avisos": [{"texto": "a semana"}]}'::jsonb $f$;
    v := public.agenda_comunicar_rodar(c_h, c_a);
    r := pg_temp.ok(r, 'P8n avisos = o que o passo da quinta devolve', v -> 'avisos' = '[{"texto": "a semana"}]'::jsonb, v::text);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p8$;

-- ── P9. As cópias ───────────────────────────────────────────────────────────────────────────────────
do $p9$
declare
  r     jsonb := '[]';
  v_mig text := current_setting('agenda_teste.mig_perguntas_fase7f', true);
  v_or  text;
  x     record;
begin
  if coalesce(v_mig, '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P9 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)'));
    return;
  end if;
  for x in select * from (values
      ('_agenda_gestor_vetos', 'agenda_teste.mig_correcao_fase7a', 'public._agenda_gestor_vetos(date, timestamptz)'),
      ('agenda_decidir', 'agenda_teste.mig_combinar_fase7d', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)'),
      ('agenda_desfazer', 'agenda_teste.mig_correcao4_fase7d', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)')) t(nome, gui, assin) loop
    v_or := current_setting(x.gui, true);
    if coalesce(v_or, '') = '' then
      r := pg_temp.ok(r, format('P9a %s: a origem como texto', x.nome), false, 'falta ' || x.gui);
      continue;
    end if;
    r := pg_temp.ok(r, format('P9a %s: tirados os blocos da 7f, a origem, byte a byte', x.nome),
      char_length(pg_temp.corpo(v_or, x.nome)) > 500 and pg_temp.sem_7f(pg_temp.corpo(v_mig, x.nome)) = replace(pg_temp.corpo(v_or, x.nome), E'\r\n', E'\n'), null);
    r := pg_temp.ok(r, format('P9b %s: a viva é a desta migration', x.nome),
      (select replace(p.prosrc, E'\r\n', E'\n') from pg_proc p where p.oid = x.assin::regprocedure) = pg_temp.corpo(v_mig, x.nome), null);
    r := pg_temp.ok(r, format('P9c %s: o tirador morde: a cópia tem bloco da 7f', x.nome), pg_temp.corpo(v_mig, x.nome) like '%-- FASE 7f:%', null);
  end loop;
  r := pg_temp.ok(r, 'P9d agenda_decisoes_abertas e _agenda_ver_decisoes não mudam nesta migration (R8.7)',
    position('function public.agenda_decisoes_abertas(' in v_mig) = 0 and position('function public._agenda_ver_decisoes(' in v_mig) = 0, null);
  r := pg_temp.ok(r, 'P9e o que o retorno lê fica de fora: nem agenda_resolver_os, nem o rascunho, nem os_carteira, nem _agenda_cliente_contexto; nenhuma escrita em agenda_disponibilidade',
    position('function public.agenda_resolver_os(' in v_mig) = 0 and position('function public.agenda_rascunho_' in v_mig) = 0 and position('function public.os_carteira(' in v_mig) = 0
    and position('function public._agenda_cliente_contexto(' in v_mig) = 0 and position('function public.agenda_data_dita(' in v_mig) = 0 and position('function public._agenda_data_conferida(' in v_mig) = 0
    and split_part(v_mig, '-- ── 9. As recriadas', 1) !~* '(insert into|update|delete from)\s+public\.agenda_disponibilidade', null);
  r := pg_temp.ok(r, 'P9e2 agenda_propor e agenda_aplicar não mudam, nem de corpo nem de grant: a decisão pelo prazo não abre caminho novo para eles',
    position('function public.agenda_propor(' in v_mig) = 0 and position('function public.agenda_aplicar(' in v_mig) = 0
    and v_mig !~* 'on function[^;]*public\.agenda_(propor|aplicar)\(' , null);
  r := pg_temp.ok(r, 'P9f sem alter table nem dado: só funções', v_mig !~* '^\s*alter\s+table' and v_mig !~* '\ninsert into public\.agenda_config', null);
  perform pg_temp.gravar(r);
end
$p9$;

-- ── P10. As portas ──────────────────────────────────────────────────────────────────────────────────
do $p10$
declare
  r      jsonb := '[]';
  v_tec  uuid;
  v_adm  uuid := pg_temp.adm();
  v_id   uuid;
  v      text;
  x      record;
  c_args constant text := $s$date '2026-11-10', timestamptz '2026-11-10 17:30-03'$s$;
begin
  if not pg_temp.na_bancada() then return; end if;
  v_tec := 'aa000000-0000-4000-8000-0000000000ff';  -- login que não é admin nem financeiro
  -- sem grant a ninguém: nem service_role
  for x in select * from (values
      ('_agenda_padrao_da_pergunta', $q$select public._agenda_padrao_da_pergunta('parada', false, null, '[]', null)::text$q$),
      ('_agenda_zona', $q$select public._agenda_zona(null, null, date '2026-11-10', date '2026-11-10')$q$),
      ('_agenda_classe_da_saida', $q$select public._agenda_classe_da_saida('linha', null, date '2026-11-10', now())::text$q$),
      ('_agenda_pergunta_linha', format('select public._agenda_pergunta_linha(%L, date ''2026-11-10'', now())::text', pg_temp.q('01'))),
      ('_agenda_pergunta_espera', format('select public._agenda_pergunta_espera(q, date ''2026-11-10'') from public.agenda_perguntas q where q.id = %L', pg_temp.q('01'))),
      ('_agenda_pergunta_frases', format('select public._agenda_pergunta_frases(q, date ''2026-11-10'')::text from public.agenda_perguntas q where q.id = %L', pg_temp.q('01'))),
      ('_agenda_pergunta_assumir', format('select public._agenda_pergunta_assumir(%L, ''prazo'', date ''2026-11-10'', now())::text', pg_temp.q('02'))),
      ('_agenda_destrava', format('select public._agenda_destrava(q, date ''2026-11-10'')::text from public.agenda_perguntas q where q.id = %L', pg_temp.q('01'))),
      ('_agenda_comunicar_destrava', 'select public._agenda_comunicar_destrava(' || c_args || ')::text'),
      ('_agenda_comunicar_teto', 'select public._agenda_comunicar_teto(' || c_args || ')::text'),
      ('_agenda_gestor_vetos', 'select public._agenda_gestor_vetos(' || c_args || ')::text')) t(nome, sql) loop
    r := pg_temp.ok(r, format('P10a %s: service_role, authenticated e anon não alcançam', x.nome),
      pg_temp.como(null, 'service_role', x.sql) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', x.sql) like 'erro 42501%' and pg_temp.como(null, 'anon', x.sql) like 'erro 42501%',
      format('%s | %s | %s', pg_temp.como(null, 'service_role', x.sql), pg_temp.como(v_tec, 'authenticated', x.sql), pg_temp.como(null, 'anon', x.sql)));
  end loop;
  r := pg_temp.ok(r, 'P10b nenhum grant direto: só o dono da função executa as 11',
    not exists (select 1 from pg_proc p, unnest(array['service_role', 'authenticated', 'anon']) papel
                 where p.pronamespace = 'public'::regnamespace
                   and p.proname in ('_agenda_padrao_da_pergunta', '_agenda_zona', '_agenda_classe_da_saida', '_agenda_pergunta_linha', '_agenda_pergunta_espera', '_agenda_pergunta_frases',
                                     '_agenda_pergunta_assumir', '_agenda_destrava', '_agenda_comunicar_destrava', '_agenda_comunicar_teto', '_agenda_gestor_vetos')
                   and has_function_privilege(papel, p.oid, 'execute')), null);

  v := format('select jsonb_array_length(public.agenda_perguntas_em_ordem(%s))::text', c_args);
  r := pg_temp.ok(r, 'P10c agenda_perguntas_em_ordem: anon não; técnico 42501; o service_role passa, e por dentro alcança a linha e o padrão sem grant nenhum',
    pg_temp.como(null, 'anon', v) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', v) like 'erro 42501%' and pg_temp.como(null, 'service_role', v) = '8',
    format('%s | %s | %s', pg_temp.como(null, 'anon', v), pg_temp.como(v_tec, 'authenticated', v), pg_temp.como(null, 'service_role', v)));
  r := pg_temp.ok(r, 'P10c3 agenda_perguntas_em_ordem: anon nem tem o grant; a porta de dentro é a 2ª barreira', not has_function_privilege('anon', 'public.agenda_perguntas_em_ordem(date, timestamptz)', 'execute'), null);
  r := pg_temp.ok(r, 'P10c2 agenda_perguntas_em_ordem: authenticated sem login de verdade não passa pelo buraco do uid nulo', pg_temp.como(null, 'authenticated', v) like 'erro 42501%', pg_temp.como(null, 'authenticated', v));
  r := pg_temp.ok(r, 'P10d agenda_perguntas_em_ordem: o administrador passa', pg_temp.como(pg_temp.adm(), 'authenticated', v) = '8', pg_temp.como(pg_temp.adm(), 'authenticated', v));
  begin
    update public.app_users set role = 'financial' where id = v_adm;
    r := pg_temp.ok(r, 'P10e agenda_perguntas_em_ordem: o financeiro passa', pg_temp.como(v_adm, 'authenticated', v) = '8', pg_temp.como(v_adm, 'authenticated', v));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  r := pg_temp.ok(r, 'P10f agenda_perguntas_em_ordem é definer com search_path, e agenda_comunicar_rodar também',
    (select bool_and(p.prosecdef and p.proconfig = array['search_path=public']) and count(*) = 2 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('agenda_perguntas_em_ordem', 'agenda_comunicar_rodar')), null);
  v := format('select (public.agenda_comunicar_rodar(%s) ->> ''rodou'')', c_args);
  r := pg_temp.ok(r, 'P10g agenda_comunicar_rodar: só o service_role', pg_temp.como(null, 'anon', v) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', v) like 'erro 42501%' and pg_temp.como(pg_temp.adm(), 'authenticated', v) like 'erro 42501%', null);
  begin
    perform pg_temp.vale();
    v := pg_temp.como(null, 'service_role', v);
    r := pg_temp.ok(r, 'P10h o service_role roda a rodada, que alcança destrava e teto por dentro: 3 assumidas, sem 42501',
      v = 'true' and (select x2.contagens #>> '{teto,assumidas}' = '3' and x2.erros = 0 from public.agenda_vigia_rodadas x2 where x2.rotina = 'comunicar' order by x2.rodou_em desc limit 1), v);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a rodada do gestor, a de verdade, como service_role: o bloco novo alcança a espera, as frases e o assumir, que não têm grant, porque a rodada é definer
    perform pg_temp.vale();
    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_compre_ate = 'sombra' where id;
    v := format('select public.agenda_gestor_rodar(%s)::text', c_args);
    r := pg_temp.ok(r, 'P10h2 agenda_gestor_rodar: anon e técnico não', pg_temp.como(null, 'anon', v) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', v) like 'erro 42501%', null);
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-10 17:00-03', mostrada_vezes = 1, mostrada_em = timestamptz '2026-11-09 17:30-03', mostrada_via = 'fechamento' where id = pg_temp.q('05');
    v := pg_temp.como(null, 'service_role', v);
    r := pg_temp.ok(r, 'P10h3 agenda_gestor_rodar como service_role: o prazo roda por dentro da porta definer, sem 42501', v::jsonb #>> '{contagens,vetos,assumidas}' = '1' and pg_temp.est(pg_temp.q('05')) = 'resolvida:prazo'
      and v::jsonb #>> '{contagens,vetos,erros}' = '0', left(v, 400));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- a crítica nascida do motor, como service_role: a rodada aplica sem autor, e ninguém mais alcança os 2 de dentro
    perform pg_temp.vale();
    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_compre_ate = 'sombra' where id;
    v_id := pg_temp.critica();
    perform pg_temp.mostra(v_id);
    v := pg_temp.como(null, 'service_role', format('select public.agenda_gestor_rodar(%s)::text', $s$date '2026-11-10', timestamptz '2026-11-10 18:05-03'$s$));
    r := pg_temp.ok(r, 'P10h4 a crítica vence pela rodada como service_role: sem 42501, sem autor em nenhuma das 3 tabelas',
      v::jsonb #>> '{contagens,vetos,erros}' = '0' and pg_temp.est(v_id) = 'respondida:prazo'
      and (select a.autor is null and a.critica and a.origem = 'vigia' from public.agenda_acoes a where a.pergunta_id = v_id)
      and (select p.autor is null and p.decidida_por is null from public.agenda_propostas p join public.agenda_acoes a on a.proposta_id = p.id where a.pergunta_id = v_id)
      and (select q.respondida_por is null from public.agenda_perguntas q where q.id = v_id), left(v, 400));
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  for x in select * from (values
      ('agenda_aplicar', format('select public.agenda_aplicar(%L, null, ''vigia'', null, null, date ''2026-11-10'', now())::text', gen_random_uuid())),
      ('agenda_decidir', format('select public.agenda_decidir(%L, 1::smallint, null, ''prazo'', ''t'', date ''2026-11-10'', now())::text', pg_temp.q('07')))) t(nome, sql) loop
    r := pg_temp.ok(r, format('P10h5 %s pela origem do prazo: anon, técnico e o login do administrador não alcançam; quem alcança é o service_role, como antes', x.nome),
      pg_temp.como(null, 'anon', x.sql) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', x.sql) like 'erro 42501%' and pg_temp.como(pg_temp.adm(), 'authenticated', x.sql) like 'erro 42501%'
      and has_function_privilege('service_role', format('public.%s', case x.nome when 'agenda_aplicar' then 'agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz)' else 'agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)' end), 'execute'), null);
  end loop;
  r := pg_temp.ok(r, 'P10h6 agenda_propor: anon não alcança, e a porta não mudou', not has_function_privilege('anon', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'execute'), null);
  begin
    -- a porta da decisão pelo prazo continua só no service_role, como antes, e o desfazer também
    v := format('select public.agenda_decidir(%L, 1::smallint, null, ''prazo'', ''t'', %s)::text', pg_temp.q('07'), c_args);
    r := pg_temp.ok(r, 'P10i agenda_decidir pelo canal prazo: anon e técnico não chegam; o administrador pelo login também não',
      pg_temp.como(null, 'anon', v) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', v) like 'erro 42501%' and pg_temp.como(pg_temp.adm(), 'authenticated', v) like 'erro 42501%', null);
    v := format('select public.agenda_desfazer(%L, null, ''dono'', date ''2026-11-10'', now())::text', 'f7f00000-0000-4000-8000-000000000601');
    r := pg_temp.ok(r, 'P10j agenda_desfazer: a porta de antes', pg_temp.como(null, 'anon', v) like 'erro 42501%' and pg_temp.como(v_tec, 'authenticated', v) like 'erro 42501%', null);
    r := pg_temp.ok(r, 'P10k _agenda_fala_modo: anon não, como no P1', pg_temp.como(null, 'anon', $q$select public._agenda_fala_modo('veto')$q$) like 'erro 42501%', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p10$;

-- ── P11. Decisão N = n ──────────────────────────────────────────────────────────────────────────────
do $p11$
declare
  r      jsonb := '[]';
  v_o    jsonb;
  v_dec  jsonb;
  v      jsonb;
  v_id   uuid;
  v_n    int;
  v_ruim text;
  c_h    constant date := date '2026-11-10';
  c_a    constant timestamptz := timestamptz '2026-11-10 17:40-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.vale();
    -- a régua nova: a ordem é outra, e o número continua o de agenda_decisoes_abertas. A não crítica com opções entra depois das críticas.
    v_id := pg_temp.estimativa(pg_temp.os('306'));
    update public.agenda_perguntas set destrava = 500 where id = pg_temp.q('08');
    update public.agenda_perguntas set destrava = 400 where id = v_id;
    v_o := public.agenda_perguntas_em_ordem(c_h, c_a);
    v_dec := public.agenda_decisoes_abertas(c_a);
    r := pg_temp.ok(r, 'P11a (controle) a ordem nova NÃO é a do n: a diária (n 3) vem antes da do Giancarlo (n 2)',
      (select string_agg(coalesce(e ->> 'n', '-'), ',' order by (e ->> 'ordem')::int) from jsonb_array_elements(v_o) e) = '1,-,3,4,-,-,-,-,2'
      or (select array_agg((e ->> 'n')::int order by (e ->> 'ordem')::int) filter (where e ->> 'n' is not null) from jsonb_array_elements(v_o) e) <>
         (select array_agg((e ->> 'n')::int order by (e ->> 'n')::int) from jsonb_array_elements(v_dec) e),
      (select string_agg(coalesce(e ->> 'n', '-'), ',' order by (e ->> 'ordem')::int) from jsonb_array_elements(v_o) e));
    select string_agg(e ->> 'linha', ' | ') into v_ruim
      from jsonb_array_elements(v_o) e
      left join jsonb_array_elements(v_dec) d on d ->> 'id' = e ->> 'id'
     where (d is null and e ->> 'linha' like 'Decisão %')
        or (d is not null and e ->> 'linha' not like format('Decisão %s: %%', d ->> 'n'))
        or (e ->> 'n')::int is distinct from (d ->> 'n')::int;
    r := pg_temp.ok(r, 'P11b toda linha: "Decisão N:" é o n de agenda_decisoes_abertas; quem não tem número não ganha "Decisão"', v_ruim is null and jsonb_array_length(v_dec) = 4, v_ruim);
    r := pg_temp.ok(r, 'P11c a trava do "1" do TS reconhece a linha (AGENDA_NUMERADA_NA_CONVERSA: Decisão \d+:)',
      (select e ->> 'linha' from jsonb_array_elements(v_o) e where e ->> 'id' = pg_temp.q('08')::text) ~ 'Decisão \d+:', null);
    r := pg_temp.ok(r, 'P11d a régua da 7d: a não crítica com opções tem número, depois das críticas', (select (d ->> 'n')::int from jsonb_array_elements(v_dec) d where d ->> 'id' = v_id::text) = 4, null);
    -- da frase ao *grava*: "na decisão 2, a opção 1", o número que o texto imprime
    v_n := (select (e ->> 'n')::int from jsonb_array_elements(v_o) e where e ->> 'linha' like '%Giancarlo%' and e ->> 'tipo' = 'nao_cabe');
    v := public.agenda_rascunho_aplicar(pg_temp.adm(), 'whatsapp', null, null, v_n::text, '1', format('na decisão %s, a opção 1', v_n), c_h, c_a);
    r := pg_temp.ok(r, 'P11e a resposta pelo número impresso cai na pergunta certa: a releitura é a do Giancarlo', v_n = 2 and v ->> 'ok' = 'true' and v ->> 'releitura' like '%Giancarlo%', v::text);
    perform set_config('agenda.agora', c_a::text, true);
    v := public.agenda_rascunho_gravar(pg_temp.adm(), c_h);
    r := pg_temp.ok(r, 'P11f até o *grava*: agenda_decidir responde pelo mesmo número: a do Giancarlo, opção 1, e as outras seguem abertas',
      (select q.estado = 'respondida' and q.opcao_escolhida = 1 and q.respondida_via = 'whatsapp' from public.agenda_perguntas q where q.id = pg_temp.q('07'))
      and pg_temp.est(pg_temp.q('06')) = 'aberta:-' and pg_temp.est(pg_temp.q('08')) = 'aberta:-', v::text);
    perform set_config('agenda.agora', '', true);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  begin
    perform pg_temp.vale();
    -- a numeração muda quando uma decisão fecha: a linha acompanha, com a mesma hora
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = pg_temp.q('06');
    r := pg_temp.ok(r, 'P11g fechou a 1: a do Giancarlo passa a ser a Decisão 1, no texto e na lista', pg_temp.linha(pg_temp.q('07'), c_h, c_a) like 'Decisão 1: %'
      and (select (d ->> 'n')::int from jsonb_array_elements(public.agenda_decisoes_abertas(c_a)) d where d ->> 'id' = pg_temp.q('07')::text) = 1, pg_temp.linha(pg_temp.q('07'), c_h, c_a));
    update public.agenda_perguntas set expira_em = c_a + interval '1 hour' where id = pg_temp.q('07');
    r := pg_temp.ok(r, 'P11h com a hora: a pergunta que expira sai do número e do texto juntos',
      pg_temp.linha(pg_temp.q('08'), c_h, c_a + interval '2 hours') like 'Decisão 1: %' and pg_temp.linha(pg_temp.q('07'), c_h, c_a + interval '2 hours') not like 'Decisão%', null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p11$;

-- ── P12. A ação assumir no que o dono lê ────────────────────────────────────────────────────────────
do $p12$
declare
  r     jsonb := '[]';
  v     jsonb;
  v_t   text;
  c_h   constant date := date '2026-11-10';
  c_a   constant timestamptz := timestamptz '2026-11-10 18:05-03';
begin
  if not pg_temp.na_bancada() then return; end if;
  begin
    perform pg_temp.vale();
    perform pg_temp.vence();
    select string_agg(public._agenda_mudanca_texto(g, false), ' | ') into v_t
      from jsonb_array_elements(public._agenda_mudancas(c_h - 6, c_h, true, true, null)) g
     where g::text like '%sem resposta até%';
    r := pg_temp.ok(r, 'P12a *o que mudou*: a frase da ação, uma vez, sem o "volta como estava" de novo',
      v_t like '%Nelson: sem resposta até ter 10/11 às 18:00, ficaram os 3 dias pela estimativa. *desfaz Nelson* volta a pergunta.%' and v_t not like '%volta como estava%', v_t);
    r := pg_temp.ok(r, 'P12b fora do aviso do gestor (R8.5): _agenda_aviso_mudancas não conta a assumir',
      not exists (select 1 from jsonb_array_elements(public._agenda_aviso_mudancas(c_h)) g where g::text like '%sem resposta até%'), null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.vale();
    perform pg_temp.mostra(pg_temp.q('01'));
    perform pg_temp.mostra(pg_temp.q('04'));
    perform pg_temp.vence();
    select string_agg(public._agenda_mudanca_texto(g, false), ' | ') into v_t
      from jsonb_array_elements(public._agenda_mudancas(c_h - 6, c_h, true, true, null)) g
     where g::text like '%mostra a lista%';
    r := pg_temp.ok(r, 'P12c as 2 sem OS, cada uma com a sua frase, sem "*desfaz *" com o nome vazio',
      v_t like '%Você: sem resposta até ter 10/11 às 18:00, continuo contando você só para abrir e fechar. *desfaz* mostra a lista.%'
      and v_t like '%fiquei com 7 dias úteis para quem não tem outro prazo%' and v_t not like '%*desfaz *%' and v_t not like '%volta como estava%', v_t);
    r := pg_temp.ok(r, 'P12d o que mudou e a saúde leem o tipo novo sem erro', (public.agenda_ver(null, null, null, 'mudancas', null, null, false, c_h) ->> 'ok')::boolean
      and public.agenda_saude(c_h, c_a) is not null, null);
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$p12$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
