-- Prova das telas da Agenda de Produção, Fase 3 (pacote P7a; migration 20261026100600): a regra da porta que a tela lê
-- (_os_porta_regra e os_status_da_tela), as leituras da Semana, da Carteira, do cartão Plano e das linhas da grade, e as
-- duas escritas da tela (Corrigir dias e Desfazer).
-- bancada: depende de 20261026100600
--
-- Sobre a carteira da Fase 3 (scripts/bancada-agenda/fixture-fase3.sql: qui 29/10/2026, a semana de 03 a 06/11 publicada
-- pela vigia — Vanderlei (OS-00069) ter 03 a qui 05/11, o Roberto o dia todo, você abre e fecha; Flávio (OS-00104) ter 03
-- (você e o João à tarde) e qua 04/11 (de manhã); Rodrigo (OS-00096) qua 04/11 à tarde (você); Lenine (OS-00074) sex 06 a
-- ter 10/11; o Nelson (OS-00112) com a decisão "não cabe" aberta; seg 02/11 é Finados):
--   R  _os_porta_regra (sempre, sem dado): quem pode, as passagens recusadas e as que seguem para a porta
--   P  a porta lê a mesma regra: a frase da recusa é a de _os_porta_regra (o cliente que não liberou, o vendedor que conclui)
--   S  os_status_da_tela: o administrador, o técnico da OS, o técnico de fora, o vendedor; o orçamento (converte e passa por
--      aprovada); a concluída; sem login
--   W  agenda_tela_semana: os dias, as barras (a cor pela carga_max; esperado zero com uso = vermelho), os blocos, o livre,
--      as mudanças (sem o *desfaz*, com a ação do Desfazer), as decisões, a sombra, desligado, quem pode
--   C  agenda_tela_carteira: os 9 grupos em ordem, os cartões (idade, cor pelos limiares, próxima ação, quem trava), a
--      concluída pela porta sem entrega e a entrega que a tira, quem pode
--   L  os_plano_da_os: os marcos, a duração com a fonte, a presença, o material A–E, prometido × planejado, planejado ×
--      realizado com a diária "a confirmar"/"lançada" (sem valor), o Entregue, quem pode
--   E  agenda_equipe_da_grade: o dono primeiro, o login de cada um, quem pode
--   G  as escritas: Corrigir dias (meio em meio dia, o histórico, recusas) e Desfazer (a publicação tudo ou nada, a já
--      desfeita, quem pode)
--   V  a revisão da Fase 3: em andamento → aguardando pela tela com o motivo (R2), a assinatura que libera a OS que
--      aguardava o cliente (item 6), agendada → aberta pela tela fora de ligado (R2), o modo para qualquer login (R3), o
--      "vence hoje" de outro dia (item 5) e a semana passada sem "PPC"
-- Sempre (com ou sem a fixture):
--   J  portas: anon sem nada; as leituras e os_status_da_tela para authenticated e service_role; as escritas só
--      authenticated; a regra e o auxiliar das mudanças sem authenticated
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100600
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_telas.sql
--   Sem a fixture (produção) os cenários saem PULADO e só R e J rodam. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.igual(p_nome text, p_visto text, p_esperado text) returns void language sql as $f$
  insert into _resultado values (p_nome, p_visto is not distinct from p_esperado,
    case when p_visto is distinct from p_esperado then 'veio: ' || coalesce(p_visto, '(null)') end)
$f$;
create function pg_temp.ok(p_nome text, p_ok boolean, p_detalhe text default null) returns void language sql as $f$
  insert into _resultado values (p_nome, coalesce(p_ok, false), case when not coalesce(p_ok, false) then p_detalhe end)
$f$;
-- Revisão da Fase 3 (bloco V, desfeito no fim): os resultados numa lista, gravados depois do desfazer.
create function pg_temp.ok_em(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false),
                                                      case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
create function pg_temp.igual_em(p_res jsonb, p_nome text, p_visto text, p_esperado text) returns jsonb
language sql immutable as $f$
  select pg_temp.ok_em(p_res, p_nome, p_visto is not distinct from p_esperado, 'veio: ' || coalesce(p_visto, '(null)'))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou o erro.
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
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
-- A regra resumida: "tipo/recusa/fica: texto".
create function pg_temp.regra(p_de text, p_para text, p_via text, p_gestor boolean, p_tecnico boolean, p_vendedor boolean,
                              p_com_autor boolean default true, p_com_motivo boolean default false,
                              p_agenda_ligada boolean default false) returns text language sql as $f$
  select (r ->> 'tipo') || '/' || coalesce(r ->> 'recusa', '-') || '/' || coalesce(r ->> 'fica', '-') || ': '
         || coalesce(r ->> 'texto', '')
    from (select public._os_porta_regra(p_de, p_para, p_via, p_gestor, p_tecnico, p_vendedor, p_com_autor, p_com_motivo,
                                        p_agenda_ligada) as r) x
$f$;
-- Revisão da Fase 3 (R2): só faltou o motivo?
create function pg_temp.pede_motivo(p_de text, p_para text, p_via text, p_gestor boolean, p_tecnico boolean,
                                    p_com_motivo boolean default false) returns boolean language sql as $f$
  select coalesce((public._os_porta_regra(p_de, p_para, p_via, p_gestor, p_tecnico, false, true, p_com_motivo) ->> 'pede_motivo')::boolean, false)
$f$;

-- ── R. A regra (sempre: é IMMUTABLE e não lê dado) ──────────────────────────────────────────────────────
select pg_temp.igual('R1 o vendedor não conclui (mesma frase da porta)',
  pg_temp.regra('in_progress', 'completed', 'tela', false, false, true),
  'concluir/quem/-: Concluir é com o administrador ou o técnico da OS.');
select pg_temp.igual('R2 o técnico da OS conclui pela tela (segue para a porta: as cobranças são dado)',
  pg_temp.regra('in_progress', 'completed', 'tela', false, true, false), 'concluir/-/-: ');
select pg_temp.igual('R3 faturar é do administrador',
  pg_temp.regra('completed', 'invoiced', 'tela', false, true, false), 'encerrada/quem/-: Faturar e reabrir são com o administrador.');
select pg_temp.igual('R4 reabrir pelo administrador segue',
  pg_temp.regra('completed', 'in_progress', 'tela', true, false, false), 'encerrada/-/-: ');
select pg_temp.igual('R5 voltar a orçamento é recusado para todos',
  pg_temp.regra('scheduled', 'draft', 'tela', true, false, false),
  'agenda/passagem/false: Uma OS não volta a ser orçamento pela agenda.');
select pg_temp.igual('R6 aguardando o cliente → aberta pela tela: fica (o cliente não liberou)',
  pg_temp.regra('awaiting_client', 'open', 'tela', true, false, false),
  'agenda/passagem/true: O cliente ainda não liberou: a OS continua aguardando o cliente.');
select pg_temp.igual('R7 aguardando o cliente → aberta pelo dono segue',
  pg_temp.regra('awaiting_client', 'open', 'dono', true, false, false), 'agenda/-/-: ');
-- Revisão da Fase 3 (R2): a tela também, com o motivo — o administrador, o financeiro e o técnico da OS (não o vendedor).
select pg_temp.igual('R8 a OS em andamento volta a aguardar só com o motivo: pelo dono ou pela tela (gestor, técnico da OS)',
  pg_temp.regra('in_progress', 'awaiting_parts', 'dono', true, false, false, true, true)
  || ' | ' || pg_temp.regra('in_progress', 'awaiting_parts', 'dono', true, false, false, true, false)
  || ' | ' || pg_temp.regra('in_progress', 'awaiting_parts', 'tela', true, false, false, true, true)
  || ' | ' || pg_temp.regra('in_progress', 'awaiting_client', 'tela', false, true, false, true, true)
  || ' | ' || pg_temp.regra('in_progress', 'awaiting_client', 'tela', false, false, true, true, true)
  || ' | ' || pg_temp.regra('in_progress', 'awaiting_parts', 'assistente', true, false, false, true, true),
  'agenda/-/-:  | agenda/passagem/false: A OS já começou: só volta a aguardar quando você diz que parou e por quê.'
  || ' | agenda/-/-:  | agenda/-/-: '
  || ' | agenda/passagem/false: A OS já começou: só volta a aguardar quando você diz que parou e por quê.'
  || ' | agenda/passagem/false: A OS já começou: só volta a aguardar quando você diz que parou e por quê.');
select pg_temp.igual('R8b pede_motivo só quando o motivo é o que falta (dono; tela pelo gestor ou pelo técnico da OS)',
  concat_ws(' ', pg_temp.pede_motivo('in_progress', 'awaiting_parts', 'tela', true, false),
                 pg_temp.pede_motivo('in_progress', 'awaiting_client', 'tela', false, true),
                 pg_temp.pede_motivo('in_progress', 'awaiting_parts', 'dono', true, false),
                 pg_temp.pede_motivo('in_progress', 'awaiting_parts', 'tela', false, false),
                 pg_temp.pede_motivo('in_progress', 'awaiting_parts', 'assistente', true, false),
                 pg_temp.pede_motivo('in_progress', 'awaiting_parts', 'tela', true, false, true),
                 pg_temp.pede_motivo('in_progress', 'open', 'tela', true, false)),
  't t t f f f f');
select pg_temp.igual('R9 técnico de fora não muda nada; motor sem autor segue',
  pg_temp.regra('scheduled', 'in_progress', 'tela', false, false, false)
  || ' | ' || pg_temp.regra('scheduled', 'open', 'motor', false, false, false, false),
  'agenda/quem/-: Você não pode mudar o status desta OS. | agenda/-/-: ');
select pg_temp.igual('R10 o orçamento: a conversão é do administrador e do vendedor; sem converter, recusa',
  pg_temp.regra('draft', 'approved', 'tela', false, false, true)
  || ' | ' || pg_temp.regra('draft', 'approved', 'tela', false, true, false)
  || ' | ' || pg_temp.regra('draft', 'open', 'motor', false, false, false, false),
  'conversao/-/-:  | conversao/quem/-: Converter orçamento em OS é com o administrador ou o vendedor.'
  || ' | agenda/passagem/false: Isso ainda é orçamento: converta antes.');
select pg_temp.igual('R11 modelos com o número, o nome e os status (format)',
  format((public._os_porta_regra('cancelled', 'open', 'tela', true, false, false, true, false)) ->> 'texto', 'OS-00001', 'X (OS-00001)', 'cancelada', 'aberta')
  || ' | ' || format((public._os_porta_regra('open', 'open', 'tela', true, false, false, true, false)) ->> 'texto', 'OS-00001', 'X (OS-00001)', 'aberta', 'aberta')
  || ' | ' || format((public._os_porta_regra('in_progress', 'approved', 'tela', true, false, false, true, false)) ->> 'texto', 'OS-00001', 'X', 'em andamento', 'aprovada'),
  'A OS-00001 está cancelada: a agenda não muda o status dela. | X (OS-00001) já está aberta. | A OS já começou: não volta para aprovada.'
  -- revisão da Fase 3 (R2): a recusa diz o caminho certo
  || ' Se ela parou, passe para aguardando peças ou aguardando o cliente e diga o motivo.');
select pg_temp.igual('R12 a agendada pela tela com a agenda ligada não volta; pela vigia segue; em andamento igual segue (o início é dado)',
  pg_temp.regra('scheduled', 'approved', 'tela', true, false, false, true, false, true)
  || ' | ' || pg_temp.regra('scheduled', 'approved', 'vigia', false, false, false, false)
  || ' | ' || pg_temp.regra('in_progress', 'in_progress', 'tela', true, false, false),
  'agenda/passagem/false: A OS está agendada: para tirar da agenda, desmarque o dia. | agenda/-/-:  | agenda/-/-: ');
-- Revisão da Fase 3 (R2): com a agenda automática fora de ligado, o administrador ou o financeiro tira a OS de agendada pela
-- tela (a data é dele); o técnico da OS e o vendedor, não.
select pg_temp.igual('R13 agendada → aberta pela tela: o gestor sem a agenda ligada segue; o técnico e o vendedor, não',
  pg_temp.regra('scheduled', 'open', 'tela', true, false, false)
  || ' | ' || pg_temp.regra('scheduled', 'open', 'tela', false, true, false)
  || ' | ' || pg_temp.regra('scheduled', 'approved', 'tela', false, false, true),
  'agenda/-/-:  | agenda/passagem/false: A OS está agendada: para tirar da agenda, desmarque o dia.'
  || ' | agenda/passagem/false: A OS está agendada: para tirar da agenda, desmarque o dia.');
-- Revisão da Fase 3 (item 6): a assinatura do cliente libera a OS que aguardava o cliente (antes da Fase 3 ela a punha em
-- aprovada); os outros caminhos sem o dono continuam esperando.
select pg_temp.igual('R14 aguardando o cliente: a assinatura libera (aprovada e agendada); o motor não',
  pg_temp.regra('awaiting_client', 'approved', 'assinatura', false, false, false, false)
  || ' | ' || pg_temp.regra('awaiting_client', 'scheduled', 'assinatura', false, false, false, false)
  || ' | ' || pg_temp.regra('awaiting_client', 'approved', 'motor', false, false, false, false),
  'agenda/-/-:  | agenda/-/-:  | agenda/passagem/true: O cliente ainda não liberou: a OS continua aguardando o cliente.');

-- ── J. Portas (sempre) ──────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('J1 anon não executa nada novo',
  not has_function_privilege('anon', 'public._os_porta_regra(text, text, text, boolean, boolean, boolean, boolean, boolean, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.agenda_modo_da_proposta()', 'execute')
  and not has_function_privilege('anon', 'public.os_status_da_tela(uuid[])', 'execute')
  and not has_function_privilege('anon', 'public.agenda_tela_semana(date, date, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.agenda_tela_carteira(date)', 'execute')
  and not has_function_privilege('anon', 'public.os_plano_da_os(uuid, date)', 'execute')
  and not has_function_privilege('anon', 'public.agenda_equipe_da_grade(date)', 'execute')
  and not has_function_privilege('anon', 'public.os_planejar_pela_tela(uuid, numeric, date)', 'execute')
  and not has_function_privilege('anon', 'public.agenda_desfazer_pela_tela(uuid, date, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public._agenda_tela_mudancas(date, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)', 'execute'));
select pg_temp.ok('J2 as leituras e o que a porta aceita: authenticated e service_role',
  has_function_privilege('authenticated', 'public.os_status_da_tela(uuid[])', 'execute')
  and has_function_privilege('authenticated', 'public.agenda_tela_semana(date, date, timestamptz)', 'execute')
  and has_function_privilege('authenticated', 'public.agenda_tela_carteira(date)', 'execute')
  and has_function_privilege('authenticated', 'public.os_plano_da_os(uuid, date)', 'execute')
  and has_function_privilege('authenticated', 'public.agenda_equipe_da_grade(date)', 'execute')
  and has_function_privilege('service_role', 'public.agenda_tela_semana(date, date, timestamptz)', 'execute')
  and has_function_privilege('authenticated', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)', 'execute')
  -- revisão da Fase 3 (R3): o modo da agenda para qualquer login
  and has_function_privilege('authenticated', 'public.agenda_modo_da_proposta()', 'execute'));
select pg_temp.ok('J3 as escritas só pela tela (authenticated); a regra e o auxiliar das mudanças sem authenticated',
  has_function_privilege('authenticated', 'public.os_planejar_pela_tela(uuid, numeric, date)', 'execute')
  and has_function_privilege('authenticated', 'public.agenda_desfazer_pela_tela(uuid, date, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public._os_porta_regra(text, text, text, boolean, boolean, boolean, boolean, boolean, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public._agenda_tela_mudancas(date, timestamptz)', 'execute'));
select pg_temp.ok('J4 as leituras definer têm search_path fixo; a regra é IMMUTABLE',
  (select bool_and(p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=%') from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('os_status_da_tela', 'agenda_tela_semana', 'agenda_tela_carteira', 'os_plano_da_os',
                        'agenda_equipe_da_grade', 'os_planejar_pela_tela', 'agenda_desfazer_pela_tela',
                        'agenda_modo_da_proposta'))
  and (select p.provolatile = 'i' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_os_porta_regra'));
select pg_temp.ok('J5 a porta não tem mais as frases das passagens estáticas (uma fonte só: _os_porta_regra)',
  (select p.prosrc not like '%Uma OS não volta a ser orçamento%' and p.prosrc not like '%O cliente ainda não liberou%'
          and p.prosrc not like '%Concluir é com o administrador%' and p.prosrc like '%_os_porta_regra(%'
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'os_transicionar_status'));

-- ── Os cenários com a fixture (um bloco só, na ordem: primeiro o que só lê, depois o que escreve) ─────────
do $cenarios$
declare
  c_adm  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec  constant uuid := 'aa000000-0000-4000-8000-0000000000e1';
  c_fora constant uuid := 'aa000000-0000-4000-8000-0000000000e2';
  c_vend constant uuid := 'aa000000-0000-4000-8000-0000000000e3';
  v      text;
  v2     text;
  r      jsonb;
  c      jsonb;
  d3     jsonb;
  d5     jsonb;
  v_ids  text;
  v_acao uuid;
  v_ate  timestamptz;
  v_n    int;
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('S0 cenários (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase3');
  insert into public.app_users (id, full_name, email, role, active) values
    (c_tec, 'Téc Bancada', 'tec@bancada.invalid', 'technician', true),
    (c_fora, 'Fora Bancada', 'fora@bancada.invalid', 'technician', true),
    (c_vend, 'Vend Bancada', 'vend@bancada.invalid', 'seller', true);
  insert into public.service_order_technicians (service_order_id, user_id, role_in_order)
  values (pg_temp.os('69'), c_tec, 'technician');

  -- ── W. A Semana ──
  r := pg_temp.como(c_adm, 'authenticated', $q$select public.agenda_tela_semana('2026-11-03', '2026-11-03', '2026-11-03 10:00-03')::text$q$)::jsonb;
  perform pg_temp.igual('W1 o título, o resumo e os dias (seg a sex, com o feriado)',
    (r ->> 'titulo') || ' | ' || (r ->> 'resumo') || ' | '
    || (select string_agg((x ->> 'rotulo') || coalesce('=' || (x ->> 'feriado'), ''), ', ' order by o) from jsonb_array_elements(r -> 'dias') with ordinality t(x, o)),
    -- revisão da Fase 3: sem "PPC"; a semana passada (26 a 30/10) não tem dia conferido, então o resumo não fala dela
    'Semana de 03 a 06/11 (seg 02 é Finados) | comprometido 79% · livre 3 diárias | '
    || 'SEG 02/11=Finados, TER 03/11, QUA 04/11, QUI 05/11, SEX 06/11');
  d3 := r #> '{dias,1}';
  d5 := r #> '{dias,3}';
  perform pg_temp.igual('W2 os blocos da terça: OS · cliente · bem · pessoas · dia n de N',
    (select string_agg(concat_ws(' · ', b ->> 'numero', b ->> 'cliente', b ->> 'bem', b ->> 'pessoas_texto', b ->> 'dia_texto'), ' || ' order by o)
       from jsonb_array_elements(d3 -> 'blocos') with ordinality t(b, o)),
    'OS-00069 · Vanderlei · Mar Azul · você abre, Roberto o dia todo · dia 1 de 3 || OS-00104 · Flávio · Lancha · você, João · dia 1 de 2');
  perform pg_temp.igual('W3 as barras da terça e da quinta: o texto e a cor (verde ≤ carga_max, âmbar ≤ 100%)',
    (select string_agg((x ->> 'texto') || '=' || (x ->> 'cor'), ', ' order by o) from jsonb_array_elements(d3 -> 'pessoas') with ordinality t(x, o))
    || ' | ' || (select string_agg((x ->> 'texto') || '=' || (x ->> 'cor'), ', ' order by o) from jsonb_array_elements(d5 -> 'pessoas') with ordinality t(x, o)),
    'Gustavo 2/2=ambar, João 1/1=ambar, Roberto 2/2=ambar | Gustavo 1/2=verde, João 0/1=verde, Roberto 2/2=ambar');
  perform pg_temp.igual('W4 a última linha do dia: o livre',
    (d3 ->> 'livre_texto') || ' | ' || (d5 ->> 'livre_texto'), 'livre: João manhã | livre: você manhã, João dia todo');
  perform pg_temp.ok('W5 as decisões abertas com o como responder',
    (r #>> '{decisoes,0,texto}') like 'Decisão 1: Não cabe tudo até qui 05/11.%' and (r ->> 'como_responder') like 'Responda no WhatsApp:%',
    left((r -> 'decisoes')::text, 300));
  -- a cor sai de agenda_config; o João que não vem na terça e está no plano = vermelho
  update public.agenda_config set carga_max = 0.5 where id;
  insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
  values ('bb000000-0000-4000-8000-000000000003', daterange('2026-11-03', '2026-11-04'), 'indisponivel', 'dono', 'bancada');
  r := public.agenda_tela_semana('2026-11-03', '2026-11-03', '2026-11-03 10:00-03');
  perform pg_temp.igual('W6 a cor pelo agenda_config e o esperado zero com uso = vermelho',
    (select string_agg((x ->> 'texto') || '=' || (x ->> 'cor'), ', ' order by o) from jsonb_array_elements(r #> '{dias,1,pessoas}') with ordinality t(x, o))
    || ' | ' || (select string_agg((x ->> 'texto') || '=' || (x ->> 'cor'), ', ' order by o) from jsonb_array_elements(r #> '{dias,3,pessoas}') with ordinality t(x, o)),
    'Gustavo 2/2=ambar, João 1/0=vermelho, Roberto 2/2=ambar | Gustavo 1/2=verde, João 0/1=verde, Roberto 2/2=ambar');
  delete from public.agenda_disponibilidade where nota = 'bancada';
  update public.agenda_config set carga_max = default where id;
  -- as mudanças de ontem para hoje (a publicação da vigia de qui 29/10), sem o *desfaz*, com a ação do Desfazer
  r := public.agenda_tela_semana('2026-11-02', '2026-10-30', '2026-10-30 10:00-03');
  perform pg_temp.ok('W7 as mudanças: a publicação da semana numa linha, desfazível, sem o *desfaz semana*',
    jsonb_array_length(r -> 'mudancas') = 1 and r #>> '{mudancas,0,tipo}' = 'publicacao'
    and r #>> '{mudancas,0,texto}' like 'Publiquei a semana de 03 a 06/11%' and r #>> '{mudancas,0,texto}' not like '%desfaz%'
    and (r #>> '{mudancas,0,desfazivel}')::boolean and r #>> '{mudancas,0,acao_id}' is not null and r #>> '{mudancas,0,perda}' is null
    and (select a.tipo from public.agenda_acoes a where a.id = (r #>> '{mudancas,0,acao_id}')::uuid) = 'publicar',
    left((r -> 'mudancas')::text, 400));
  perform pg_temp.ok('W8 a semana de 02/11 vista de 30/10: os blocos do plano, o livre só de hoje em diante',
    jsonb_array_length(r #> '{dias,1,blocos}') = 2 and r #>> '{dias,1,livre_texto}' = 'livre: João manhã', left((r -> 'dias')::text, 300));
  update public.agenda_config set modo_proposta = 'sombra' where id;
  r := public.agenda_tela_semana('2026-11-03', '2026-11-03', '2026-11-03 10:00-03');
  perform pg_temp.igual('W9 em sombra: em teste, sem o publicado nem o livre de verdade',
    (r ->> 'em_teste') || ' | ' || (r ->> 'titulo') || ' | ' || coalesce(r ->> 'livre_de_verdade', '(sem)')
    || ' | ' || (select count(*) from jsonb_array_elements(r -> 'dias') x, jsonb_array_elements(x -> 'blocos') b)::text,
    'true | Em teste: ainda não montei esta semana. | (sem) | 0');
  update public.agenda_config set modo_proposta = 'desligado' where id;
  r := public.agenda_tela_semana('2026-11-03', '2026-11-03', '2026-11-03 10:00-03');
  perform pg_temp.igual('W10 desligado: só o título',
    (r ->> 'titulo') || ' | ' || (r -> 'dias')::text, 'A agenda automática está desligada: não há plano publicado. | []');
  update public.agenda_config set modo_proposta = 'ligado' where id;
  perform pg_temp.ok('W11 em ligado, o livre de verdade pela simulação',
    (public.agenda_tela_semana('2026-11-03', '2026-11-03', '2026-11-03 10:00-03') ->> 'livre_de_verdade') like 'Livre de verdade (pela simulação da agenda):%');
  perform pg_temp.igual('W12 o técnico não vê a semana de produção',
    pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_tela_semana('2026-11-03', '2026-11-03', '2026-11-03 10:00-03')::text$q$),
    'erro 42501: A agenda de produção é com o administrador.');
  perform pg_temp.ok('W13 o service_role vê (o assistente)',
    pg_temp.como(null, 'service_role', $q$select public.agenda_tela_semana('2026-11-03', '2026-11-03', '2026-11-03 10:00-03') ->> 'modo'$q$) = 'ligado');

  -- ── C. A Carteira (só leitura) ──
  r := pg_temp.como(c_adm, 'authenticated', $q$select public.agenda_tela_carteira('2026-11-03')::text$q$)::jsonb;
  perform pg_temp.igual('C1 os 9 grupos, em ordem, com o número',
    (select string_agg((g ->> 'chave') || '=' || (g ->> 'n'), ', ' order by o) from jsonb_array_elements(r -> 'grupos') with ordinality t(g, o)),
    'prontas_sem_data=1, material_com_data=1, material_sem_previsao=0, material_atrasado=0, aguardando_cliente=3, '
    || 'sem_estimativa=0, congeladas=0, em_execucao=0, concluidas_nao_entregues=0');
  perform pg_temp.igual('C2 os cartões: número, grupo, idade com a cor, próxima ação e quem trava',
    (select string_agg(concat_ws(' · ', x ->> 'numero', x ->> 'grupo', x ->> 'idade_texto', x ->> 'cor', x ->> 'proxima_acao',
                                 coalesce(x ->> 'quem_trava_texto', '-')), ' || ' order by o)
       from jsonb_array_elements(r -> 'cartoes') with ordinality t(x, o)),
    'OS-00100 · prontas_sem_data · há 14 dias úteis · laranja · entrar no plano da semana · - || '
    || 'OS-00112 · material_com_data · há 18 dias úteis · laranja · esperar "Painel Touch de Monitoramento e…" (ter 03/11) · trava: o fornecedor || '
    || 'OS-00032 · aguardando_cliente · há 118 dias úteis · vermelho · o cliente liberar · trava: o cliente || '
    || 'OS-00076 · aguardando_cliente · há 59 dias úteis · vermelho · o cliente liberar · trava: o cliente || '
    -- a OS-00033 tem a janela antiga (marcada): com data, só laranja
    || 'OS-00033 · aguardando_cliente · há 118 dias úteis · laranja · o cliente liberar · trava: o cliente');
  update public.agenda_config set carteira_laranja_du = 15, carteira_vermelho_du = 60 where id;
  r := public.agenda_tela_carteira('2026-11-03');
  perform pg_temp.igual('C3 a cor pelos limiares do agenda_config',
    (select string_agg((x ->> 'numero') || '=' || (x ->> 'cor'), ', ' order by o) from jsonb_array_elements(r -> 'cartoes') with ordinality t(x, o)),
    'OS-00100=normal, OS-00112=laranja, OS-00032=vermelho, OS-00033=laranja, OS-00076=laranja');
  update public.agenda_config set carteira_laranja_du = default, carteira_vermelho_du = default where id;
  perform pg_temp.igual('C5 o técnico não vê a carteira',
    pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_tela_carteira('2026-11-03')::text$q$),
    'erro 42501: A agenda de produção é com o administrador.');

  -- ── S. O que a porta aceita pela tela ──
  v_ids := format('array[%L, %L, %L]::uuid[]', pg_temp.os('32'), pg_temp.os('69'), pg_temp.os('83'));
  r := pg_temp.como(c_adm, 'authenticated', format('select public.os_status_da_tela(%s)::text', v_ids))::jsonb;
  perform pg_temp.igual('S1 administrador, aguardando o cliente: em andamento, peças e concluir (aberta e agendada não: o cliente não liberou)',
    (r -> pg_temp.os('32')::text)::text, '["in_progress", "awaiting_parts", "completed"]');
  perform pg_temp.igual('S2 administrador, agendada: em andamento, aguardar e concluir (aberta/aprovada não: desmarque o dia)',
    (r -> pg_temp.os('69')::text)::text, '["in_progress", "awaiting_parts", "awaiting_client", "completed"]');
  perform pg_temp.igual('S3 administrador, orçamento: converte (aprovada → o pedido); faturar não',
    (r -> pg_temp.os('83')::text)::text,
    '["approved", "scheduled", "open", "in_progress", "awaiting_parts", "awaiting_client", "completed"]');
  r := pg_temp.como(c_tec, 'authenticated', format('select public.os_status_da_tela(%s)::text', v_ids))::jsonb;
  perform pg_temp.igual('S4 técnico da OS: a dele muda e conclui; a de outro e o orçamento, nada',
    (r -> pg_temp.os('69')::text)::text || ' | ' || (r -> pg_temp.os('32')::text)::text || ' | ' || (r -> pg_temp.os('83')::text)::text,
    '["in_progress", "awaiting_parts", "awaiting_client", "completed"] | [] | []');
  r := pg_temp.como(c_vend, 'authenticated', format('select public.os_status_da_tela(%s)::text', v_ids))::jsonb;
  perform pg_temp.igual('S5 vendedor: muda status de agenda e converte, nunca conclui',
    (r -> pg_temp.os('69')::text)::text || ' | ' || (r -> pg_temp.os('83')::text)::text,
    '["in_progress", "awaiting_parts", "awaiting_client"] | ["approved", "scheduled", "open", "in_progress", "awaiting_parts", "awaiting_client"]');
  r := pg_temp.como(c_fora, 'authenticated', format('select public.os_status_da_tela(%s)::text', v_ids))::jsonb;
  perform pg_temp.igual('S6 técnico de fora: nada',
    (r -> pg_temp.os('32')::text)::text || (r -> pg_temp.os('69')::text)::text || (r -> pg_temp.os('83')::text)::text, '[][][]');
  perform pg_temp.ok('S7 sem login: 42501',
    pg_temp.como(null, 'service_role', format('select public.os_status_da_tela(%s)::text', v_ids)) like 'erro 42501%');

  -- ── P. A porta diz a frase da mesma regra ──
  r := public.os_transicionar_status(pg_temp.os('32'), 'open', 'tela', null, c_adm, null, '2026-11-03', '2026-11-03 10:00-03');
  perform pg_temp.igual('P1 a porta: aguardando o cliente → aberta pela tela fica, com a frase da regra',
    (r ->> 'ok') || '/' || (r ->> 'mudou') || ': ' || (r ->> 'texto'),
    'true/false: O cliente ainda não liberou: a OS continua aguardando o cliente.');
  perform pg_temp.igual('P2 a porta: o vendedor concluindo é 42501 com a frase da regra',
    pg_temp.como(c_vend, 'authenticated', format(
      $q$select public.os_transicionar_status(%L, 'completed', 'tela', null, null, null, '2026-11-03', '2026-11-03 10:00-03')::text$q$,
      pg_temp.os('104'))),
    'erro 42501: Concluir é com o administrador ou o técnico da OS.');

  -- ── E. As linhas da grade ──
  r := pg_temp.como(c_adm, 'authenticated', $q$select public.agenda_equipe_da_grade('2026-11-03')::text$q$)::jsonb;
  perform pg_temp.igual('E1 a equipe da grade: o dono primeiro, com o login de cada um',
    (select string_agg((x ->> 'nome_curto') || '=' || coalesce(x ->> 'app_user_id', 'sem login')
                       || case when (x ->> 'eh_dono')::boolean then ' (dono)' else '' end, ', ' order by o)
       from jsonb_array_elements(r) with ordinality t(x, o)),
    'Gustavo=aa000000-0000-4000-8000-000000000001 (dono), João=sem login, Roberto=aa000000-0000-4000-8000-000000000002');
  perform pg_temp.igual('E2 o técnico não lê a equipe (a tela volta às linhas de antes)',
    pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_equipe_da_grade('2026-11-03')::text$q$),
    'erro 42501: A agenda de produção é com o administrador.');

  -- ── L. O Plano antes da conclusão ──
  r := pg_temp.como(c_adm, 'authenticated', format($q$select public.os_plano_da_os(%L, '2026-11-04')::text$q$, pg_temp.os('69')))::jsonb;
  perform pg_temp.igual('L1 o Plano: os marcos, sem Entregue, a duração com a fonte, a presença, prometido × planejado',
    concat_ws(' | ', r #>> '{marcos,texto}', r ->> 'pode_entregar', r #>> '{duracao,texto}', r #>> '{duracao,fonte_texto}',
              r #>> '{presenca_dono,texto}', r #>> '{prometido_planejado,texto}'),
    'Entrada qua 29/07 · início — · conclusão — · entrega — | false | 3 dias: Roberto (dia todo) (você disse) | você disse | '
    || 'Você abre e fecha (pela regra) | O plano termina qui 05/11; o cliente não deu data.');
  perform pg_temp.igual('L2 o material por linha com o nível e o trecho',
    (select string_agg((i ->> 'nivel') || ' ' || (i ->> 'nivel_texto') || ' — ' || (i ->> 'trecho'), '; ' order by o)
       from jsonb_array_elements(r #> '{material,itens}') with ordinality t(i, o) where o <= 2),
    'A na mão — o material do Vanderlei chegou da Premel; A na mão — o material do Vanderlei chegou da Premel');
  perform pg_temp.igual('L3 planejado × realizado: os dias, quem vai e a diária (passado a confirmar, futuro nada; sem valor)',
    (select string_agg(concat_ws(' · ', x ->> 'rotulo', x ->> 'pessoas_texto', x ->> 'resultado_texto', coalesce(x ->> 'diaria', '-')), ' || ' order by o)
       from jsonb_array_elements(r -> 'planejado_realizado') with ordinality t(x, o)),
    'Ter 03/11 · você abre, Roberto o dia todo · sem conferência · a confirmar || '
    || 'Qua 04/11 · Roberto o dia todo · previsto · a confirmar || '
    || 'Qui 05/11 · você fecha, Roberto o dia todo · previsto · -');
  perform pg_temp.ok('L4 nada de dinheiro no Plano', r::text not like '%R$%' and r::text !~ '"valor[a-z_]*": [0-9]' and r::text not like '%valor_diaria%',
    left(r::text, 300));
  r := public.os_plano_da_os(pg_temp.os('112'), '2026-11-03');
  perform pg_temp.igual('L5 sem plano, com a data do cliente; o material com previsão (A e C)',
    concat_ws(' | ', coalesce(r #>> '{prometido_planejado,texto}', '(sem texto)'), r #>> '{material,estado}',
              (select string_agg(distinct i ->> 'nivel', '') from jsonb_array_elements(r #> '{material,itens}') i)),
    'O cliente precisa até qui 05/11; ainda não há plano. | previsto | AC');
  perform pg_temp.igual('L6 quem pode ver o Plano',
    pg_temp.como(c_tec, 'authenticated', format($q$select public.os_plano_da_os(%L, '2026-11-03')::text$q$, pg_temp.os('112')))
    || ' | ' || pg_temp.como(c_adm, 'authenticated', $q$select public.os_plano_da_os('05000000-0000-4000-8000-000000009999', '2026-11-03')::text$q$),
    'erro 42501: O plano da OS é com o administrador. | erro P0002: Não encontrei a OS.');

  -- ── G. Corrigir dias ──
  v := pg_temp.como(c_adm, 'authenticated', format($q$select public.os_planejar_pela_tela(%L, 2.5, '2026-11-03') ->> 'texto'$q$, pg_temp.os('100')));
  perform pg_temp.igual('G1 Corrigir dias: a frase', v, 'Duração gravada: 2,5 dias.');
  perform pg_temp.ok('G2 Corrigir dias: os_planejamento com a fonte dono e o histórico',
    (select pl.dias = 2.5 and pl.estimativa_fonte = 'dono' and pl.atualizado_por = c_adm
            and pl.historico -> -1 #>> '{depois,dias}' = '2.5' and pl.historico -> -1 ->> 'trecho' = 'Pela tela da OS: 2,5 dias.'
       from public.os_planejamento pl where pl.service_order_id = pg_temp.os('100')),
    (select left(pl.historico::text, 300) from public.os_planejamento pl where pl.service_order_id = pg_temp.os('100')));
  perform pg_temp.igual('G3 Corrigir dias: as recusas (meio em meio dia, orçamento, técnico)',
    pg_temp.como(c_adm, 'authenticated', format($q$select public.os_planejar_pela_tela(%L, 0.3, '2026-11-03')::text$q$, pg_temp.os('100')))
    || ' | ' || pg_temp.como(c_adm, 'authenticated', format($q$select public.os_planejar_pela_tela(%L, 1, '2026-11-03')::text$q$, pg_temp.os('83')))
    || ' | ' || pg_temp.como(c_tec, 'authenticated', format($q$select public.os_planejar_pela_tela(%L, 1, '2026-11-03')::text$q$, pg_temp.os('100'))),
    'erro 22023: A duração anda de meio em meio dia (por exemplo, 2 ou 2,5), até 60 dias. | '
    || 'erro 22023: Isso ainda é orçamento: a duração vale quando virar OS. | erro 42501: Só o administrador mexe na agenda.');

  -- ── G. O Desfazer da publicação da semana (tudo ou nada), numa subtransação desfeita na hora ──
  select a.id, a.desfazivel_ate into v_acao, v_ate from public.agenda_acoes a
   where a.tipo = 'publicar' and a.executada and a.desfeita_em is null order by a.criada_em, a.id limit 1;
  begin
    v := pg_temp.como(c_tec, 'authenticated', format($q$select public.agenda_desfazer_pela_tela(%L, '2026-10-30', %L)::text$q$,
                                                     v_acao, v_ate - interval '1 hour'));
    r := pg_temp.como(c_adm, 'authenticated', format($q$select public.agenda_desfazer_pela_tela(%L, '2026-10-30', %L)::text$q$,
                                                     v_acao, v_ate - interval '1 hour'))::jsonb;
    select count(*) into v_n from public.agenda_acoes a
     where a.proposta_id = (select a2.proposta_id from public.agenda_acoes a2 where a2.id = v_acao) and a.tipo = 'publicar'
       and a.desfeita_em is null;
    c := pg_temp.como(c_adm, 'authenticated', format($q$select public.agenda_desfazer_pela_tela(%L, '2026-10-30', %L)::text$q$,
                                                     v_acao, v_ate - interval '1 hour'))::jsonb;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.igual('G4 o técnico não desfaz', v, 'erro 42501: Só o administrador mexe na agenda.');
  perform pg_temp.ok('G5 o Desfazer da publicação: as 4 ações desfeitas (o que a vigia publicou volta)',
    coalesce((r ->> 'ok')::boolean, false) and jsonb_array_length(r -> 'acoes') = 4 and v_n = 0
    and (r ->> 'texto') like 'Desfiz a publicação da semana (4 mudanças):%', left(r::text, 400));
  perform pg_temp.ok('G6 de novo: nada muda e a frase diz (sem erro)', c ->> 'ok' = 'false' and c ->> 'texto' is not null, c::text);

  -- ── A conclusão pela porta: o que muda nas telas ──
  perform set_config('agenda.hoje', '2026-11-05', true);
  perform public.os_registrar_marco(pg_temp.os('69'), 'conclusao', 'dono', '2026-11-05 16:00-03', c_adm, 'concluiu', '2026-11-05', '2026-11-05 16:00-03');
  perform set_config('agenda.hoje', '', true);
  perform pg_temp.igual('S8 concluída: o administrador fatura e reabre; o técnico da OS, nada',
    pg_temp.como(c_adm, 'authenticated', format('select (public.os_status_da_tela(array[%L]::uuid[]) -> %L)::text', pg_temp.os('69'), pg_temp.os('69')))
    || ' | ' || pg_temp.como(c_tec, 'authenticated', format('select (public.os_status_da_tela(array[%L]::uuid[]) -> %L)::text', pg_temp.os('69'), pg_temp.os('69'))),
    '["in_progress", "awaiting_parts", "awaiting_client", "invoiced"] | []');
  r := public.agenda_tela_carteira('2026-11-06');
  c := (select x from jsonb_array_elements(r -> 'cartoes') x where x ->> 'grupo' = 'concluidas_nao_entregues');
  perform pg_temp.igual('C4 a concluída pela porta sem a entrega',
    concat_ws(' · ', c ->> 'numero', c ->> 'estado', c ->> 'idade_texto', c ->> 'proxima_acao', c ->> 'quem_trava_texto'),
    'OS-00069 · concluída qui 05/11, sem a entrega · há 1 dia útil · entregar ao cliente · trava: você');
  r := public.os_plano_da_os(pg_temp.os('69'), '2026-11-06');
  perform pg_temp.igual('L7 o Plano da concluída: a conclusão nos marcos e o Entregue',
    (r #>> '{marcos,texto}') || ' | ' || (r ->> 'pode_entregar'),
    'Entrada qua 29/07 · início — · conclusão qui 05/11 (68 dias úteis) · entrega — | true');
  r := public.os_registrar_marco(pg_temp.os('69'), 'entrega', 'tela', '2026-11-06 10:00-03', c_adm, null, '2026-11-06', '2026-11-06 10:00-03');
  perform pg_temp.ok('L8 o Entregue pela tela (os_registrar_marco, via tela): sai do Plano e da Carteira',
    coalesce((r ->> 'ok')::boolean, false)
    and (public.os_plano_da_os(pg_temp.os('69'), '2026-11-06') ->> 'pode_entregar')::boolean = false
    and not exists (select 1 from jsonb_array_elements(public.agenda_tela_carteira('2026-11-06') -> 'cartoes') x
                     where x ->> 'grupo' = 'concluidas_nao_entregues'), r::text);
end $cenarios$;

-- ── V. A revisão da Fase 3 com a carteira (R2, R3, item 5, item 6 e a semana passada; tudo desfeito no fim) ─────
do $revisao$
declare
  c_adm  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec  constant uuid := 'aa000000-0000-4000-8000-0000000000e1';
  c_vend constant uuid := 'aa000000-0000-4000-8000-0000000000e3';
  v      text;
  v2     text;
  r      jsonb;
  s      jsonb;
  v_cli  uuid;
  v_ves  uuid;
  -- os resultados vão numa variável: o bloco é desfeito no fim (a exceção P0099), e o que foi inserido em _resultado iria junto
  v_res  jsonb := '[]'::jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('V0 a revisão com a carteira (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  begin
    select so.client_id, so.vessel_id into v_cli, v_ves from public.service_orders so where so.id = pg_temp.os('69');
    insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status, labor_cost_total,
                                       parts_cost_total, grand_total, check_in_at, converted_to_os_at)
    values (pg_temp.os('901'), v_cli, v_ves, 'OS-00901', 'in_progress', 'approved', 0, 0, 0, '2026-11-03 08:00-03', '2026-10-20 10:00-03'),
           (pg_temp.os('902'), v_cli, v_ves, 'OS-00902', 'awaiting_client', 'approved', 0, 0, 0, null, '2026-10-20 10:00-03'),
           (pg_temp.os('903'), v_cli, v_ves, 'OS-00903', 'scheduled', 'approved', 0, 0, 0, null, '2026-10-20 10:00-03');
    insert into public.service_order_technicians (service_order_id, user_id, role_in_order)
    values (pg_temp.os('901'), c_tec, 'technician');

    -- V1 (R2) a tela oferece "em andamento → aguardando" e diz que pede o motivo: ao administrador e ao técnico da OS; ao
    -- vendedor, não.
    v := format('select public.os_status_da_tela(array[%L]::uuid[])::text', pg_temp.os('901'));
    r := pg_temp.como(c_adm, 'authenticated', v)::jsonb;
    s := pg_temp.como(c_tec, 'authenticated', v)::jsonb;
    v_res := pg_temp.igual_em(v_res, 'V1 em andamento: o gestor e o técnico da OS veem aguardar (com o motivo) e concluir; o vendedor, nada',
      (r -> pg_temp.os('901')::text)::text || ' ' || (r -> (pg_temp.os('901')::text || ':motivo'))::text
      || ' | ' || (s -> pg_temp.os('901')::text)::text || ' ' || (s -> (pg_temp.os('901')::text || ':motivo'))::text
      || ' | ' || coalesce((pg_temp.como(c_vend, 'authenticated', v)::jsonb -> pg_temp.os('901')::text)::text, '-'),
      '["awaiting_parts", "awaiting_client", "completed"] ["awaiting_parts", "awaiting_client"]'
      || ' | ["awaiting_parts", "awaiting_client", "completed"] ["awaiting_parts", "awaiting_client"] | []');

    -- V2 (R2) a porta pela tela: sem o motivo, nada muda e ela diz que pede; com o motivo, o técnico da OS passa a aguardar.
    v := pg_temp.como(c_tec, 'authenticated', format(
      $q$select public.os_transicionar_status(%L, 'awaiting_parts', 'tela', null, null, null, '2026-11-03', '2026-11-03 10:00-03', null)::text$q$,
      pg_temp.os('901')));
    v2 := pg_temp.como(c_tec, 'authenticated', format(
      $q$select (public.os_transicionar_status(%L, 'awaiting_parts', 'tela', 'falta material: o inversor não chegou', null, null,
                                              '2026-11-03', '2026-11-03 10:00-03', null) ->> 'texto')$q$,
      pg_temp.os('901')));
    v_res := pg_temp.ok_em(v_res, 'V2 a tela sem o motivo: nada muda, pede_motivo; com o motivo: aguardando peças, a frase com o motivo, origem tela',
      (v::jsonb ->> 'ok') = 'false' and (v::jsonb ->> 'pede_motivo') = 'true'
      and v2 = 'Vanderlei (OS-00901): de em andamento para aguardando peças — falta material: o inversor não chegou.'
      and (select so.status from public.service_orders so where so.id = pg_temp.os('901')) = 'awaiting_parts'
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('901') and a.tipo = 'status'
                                                     and a.origem = 'tela' and a.autor = c_tec
                                                     and a.motivo = 'falta material: o inversor não chegou'),
      v || ' | ' || v2);

    -- V3 (item 6) a assinatura do cliente (sem login) libera a OS que aguardava o cliente: aprovada.
    v := pg_temp.como(null, 'service_role', format(
      $q$select (public.os_transicionar_status(%L, 'approved', 'assinatura', null, null, null, '2026-11-03', '2026-11-03 10:00-03', null) ->> 'texto')$q$,
      pg_temp.os('902')));
    v_res := pg_temp.ok_em(v_res, 'V3 aguardando o cliente + a assinatura do cliente: aprovada (como antes da Fase 3)',
      (select so.status from public.service_orders so where so.id = pg_temp.os('902')) = 'approved'
      and v = 'Vanderlei (OS-00902): de aguardando o cliente para aprovada.', v);

    -- V4 (R2) agendada → aberta pela tela: com a agenda ligada, não (desmarque o dia), e a tela nem oferece; fora de ligado,
    -- o administrador tira, e a tela oferece.
    update public.agenda_config set modo_proposta = 'ligado' where id;
    v := pg_temp.como(c_adm, 'authenticated', format('select (public.os_status_da_tela(array[%L]::uuid[]) -> %L)::text', pg_temp.os('903'), pg_temp.os('903')));
    r := pg_temp.como(c_adm, 'authenticated', format(
      $q$select public.os_transicionar_status(%L, 'open', 'tela', null, null, null, '2026-11-03', '2026-11-03 10:00-03', null)::text$q$,
      pg_temp.os('903')))::jsonb;
    v_res := pg_temp.ok_em(v_res, 'V4 agenda ligada: agendada → aberta pela tela não é oferecida e a porta recusa (desmarque o dia)',
      v = '["in_progress", "awaiting_parts", "awaiting_client", "completed"]'
      and r ->> 'ok' = 'false' and r ->> 'texto' = 'A OS está agendada: para tirar da agenda, desmarque o dia.'
      and (select so.status from public.service_orders so where so.id = pg_temp.os('903')) = 'scheduled', v || ' | ' || r::text);
    update public.agenda_config set modo_proposta = 'desligado' where id;
    v := pg_temp.como(c_adm, 'authenticated', format('select (public.os_status_da_tela(array[%L]::uuid[]) -> %L)::text', pg_temp.os('903'), pg_temp.os('903')));
    v2 := pg_temp.como(c_adm, 'authenticated', format(
      $q$select (public.os_transicionar_status(%L, 'open', 'tela', null, null, null, '2026-11-03', '2026-11-03 10:00-03', null) ->> 'texto')$q$,
      pg_temp.os('903')));
    v_res := pg_temp.ok_em(v_res, 'V5 agenda desligada: o administrador vê e tira a OS de agendada pela tela (vai para a escolhida: aberta)',
      v = '["approved", "open", "in_progress", "awaiting_parts", "awaiting_client", "completed"]'
      and v2 = 'Vanderlei (OS-00903): de agendada para aberta.'
      and (select so.status from public.service_orders so where so.id = pg_temp.os('903')) = 'open', v || ' | ' || v2);
    update public.agenda_config set modo_proposta = 'ligado' where id;

    -- V6 (R3) o modo da agenda automática para qualquer login (agenda_config é fechada ao técnico: a leitura da tabela volta
    -- vazia, e o formulário achava que estava desligada).
    v := coalesce(pg_temp.como(c_tec, 'authenticated', 'select modo_proposta from public.agenda_config limit 1'), '(vazio)');
    v_res := pg_temp.ok_em(v_res, 'V6 agenda_modo_da_proposta: o técnico e o vendedor leem "ligado" (a tabela, para o técnico, não diz)',
      pg_temp.como(c_tec, 'authenticated', 'select public.agenda_modo_da_proposta()') = 'ligado'
      and pg_temp.como(c_vend, 'authenticated', 'select public.agenda_modo_da_proposta()') = 'ligado'
      and v is distinct from 'ligado', v);

    -- V7 (item 5) a conclusão do gestor de ter 03/11 vista na tela de qua 04/11: "vence ter 03/11", nunca "vence hoje".
    perform set_config('agenda.hoje', '2026-11-03', true);
    r := public.os_transicionar_status(pg_temp.os('74'), 'completed', 'equipe', 'O Roberto disse que terminou', null, null,
                                       '2026-11-03', '2026-11-03 17:20-03', null);
    perform set_config('agenda.hoje', '', true);
    v := (select string_agg(e ->> 'texto', ' || ') from jsonb_array_elements(public._agenda_tela_mudancas('2026-11-04', '2026-11-04 08:00-03')) e
           where e ->> 'tipo' = 'concluir');
    v2 := (select string_agg(e ->> 'texto', ' || ') from jsonb_array_elements(public._agenda_tela_mudancas('2026-11-03', '2026-11-03 18:00-03')) e
            where e ->> 'tipo' = 'concluir');
    v_res := pg_temp.ok_em(v_res, 'V7 a conclusão de ontem na tela: "vence ter 03/11" no lugar de "vence hoje"; no mesmo dia, "vence hoje"',
      (r ->> 'ok')::boolean and v like '%(vence ter 03/11)%' and v not like '%hoje%' and v2 like '%(vence hoje)%', v || ' | ' || v2);
    v_res := pg_temp.igual_em(v_res, 'V8 o ajudante único: outro dia vira a data, o mesmo dia fica',
      public._agenda_vence_no_dia('Saldo R$ 10,00 (vence hoje); o saldo passa a vencer hoje', '2026-11-03', '2026-11-04')
      || ' | ' || public._agenda_vence_no_dia('Saldo (vence hoje)', '2026-11-04', '2026-11-04'),
      'Saldo R$ 10,00 (vence ter 03/11); o saldo passa a vencer ter 03/11 | Saldo (vence hoje)');

    -- V9 a semana passada no resumo, em palavras do dono (sem "PPC"): o que agenda_ppc mediu.
    perform set_config('agenda.hoje', '2026-11-20', true);
    update public.agenda_alocacoes a set resultado = x.res, motivo = x.mot, resultado_via = 'tela'
      from (values ('69', date '2026-11-03', 'cumprido', null), ('104', date '2026-11-03', 'cumprido', null),
                   ('69', date '2026-11-04', 'nao_cumprido', 'imprevisto_tecnico')) x(os, dia, res, mot)
     where a.service_order_id = pg_temp.os(x.os) and a.dia = x.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
    perform set_config('agenda.hoje', '', true);
    s := public.agenda_ppc('2026-11-03', '2026-11-09');
    r := public.agenda_tela_semana('2026-11-09', '2026-11-09', '2026-11-09 10:00-03');
    v_res := pg_temp.ok_em(v_res, 'V9 o resumo diz "semana passada: N de M dias cumpridos" (o que agenda_ppc mediu), sem "PPC"',
      (s ->> 'cumpridos')::int > 0
      and r ->> 'resumo' like format('%%semana passada: %s de %s dias cumpridos', s ->> 'cumpridos',
                                     (s ->> 'cumpridos')::int + jsonb_array_length(s -> 'nao_cumpridos'))
      and r ->> 'resumo' not like '%PPC%', r ->> 'resumo');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end $revisao$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
