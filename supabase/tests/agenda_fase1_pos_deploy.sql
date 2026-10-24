-- Conferência DEPOIS de ligar a Agenda de Produção, Fase 1 (pacote P7): migrations 20261024160000..160600 + a
-- semente 20261024161000, e as edge functions (spec §10, passo 5).
-- bancada: depende de 20261024161000
--
-- SÓ LEITURA: nenhum INSERT, UPDATE ou DELETE em tabela do sistema (só na tabela temporária do resultado); as
-- leituras da agenda são STABLE e não gravam nada (N1 prova); termina em ROLLBACK. Não depende da fixture: vale
-- para a carteira de produção e para a da bancada.
--
--   M  as 8 versões da Fase 1 estão registradas em supabase_migrations.schema_migrations (sem isso o próximo
--      db push tenta aplicar de novo)
--   C  agenda_config: uma linha; modo_leitura válido (mostra qual); o que é das Fases 2–5 (proposta, vigia, equipe,
--      cliente) continua desligado; nenhum plano publicado (versao_plano 0)
--   T  as 6 tabelas: RLS ligada, policies só de leitura e TO authenticated, anon sem nada, authenticated só lê
--   F  funções: as RPCs do contrato existem; nenhuma agenda_*/os_*/_agenda_* executável por anon; as internas
--      (aplicar, sincronizar, semear) sem authenticated; as leituras são STABLE ou IMMUTABLE
--   S  semente: quem tem padrão medido ('historico' vigente) é exatamente a equipe recente (prestador com perfil de
--      trabalho vigente e diária nos agenda_config.equipe_recente_dias dias até a última diária) — quem saiu (o
--      Mickael) fica de fora pela regra; o sócio nunca; a capacidade é Σ frequência × carga_max
--   L  leituras: agenda_ver foco o_que_fazer devolve texto não vazio, dentro de texto_max, com os 5 blocos; a semana
--      também; OS que não existe = "Não encontrei"; duas leituras seguidas = o mesmo texto (md5); o fechamento lê o
--      mesmo modo da config
--   N  nada foi gravado pelas leituras (as 4 tabelas de fato e o rascunho, contados antes e depois)
--   E  app_error_logs sem erro da agenda (context 'agenda' ou action 'agenda:%') aberto nas últimas 24 horas
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 4 da spec §10 (migrations, semente, edge functions e front), com o OK do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase1_pos_deploy.sql
--   A partir do 2º dia, o E só fica verde se o motor de 15 min e os comandos não estiverem falhando.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261024160000', '20261024160100', '20261024160200', '20261024160300', '20261024160400',
                    '20261024160500', '20261024160600', '20261024161000']) v;

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 agenda_config tem exatamente uma linha', count(*) = 1, count(*)::text from public.agenda_config;

insert into _resultado
select 'C2 modo_leitura é um dos três (nasce sombra; ligado só com o OK depois de 3 fechamentos conferidos)',
       coalesce(bool_and(c.modo_leitura in ('desligado', 'sombra', 'ligado')), false),
       string_agg(c.modo_leitura, ', ')
  from public.agenda_config c;

insert into _resultado
select 'C3 o que é das Fases 2–5 continua desligado (proposta, vigia, equipe, cliente)',
       coalesce(bool_and(c.modo_proposta = 'desligado' and c.modo_vigia = 'desligado' and c.modo_equipe = 'desligado'
                         and c.modo_cliente = 'desligado'), false),
       string_agg(format('proposta %s, vigia %s, equipe %s, cliente %s', c.modo_proposta, c.modo_vigia, c.modo_equipe,
                         c.modo_cliente), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C4 nenhum plano publicado (versao_plano 0: o motor de proposta é da Fase 2)',
       coalesce(bool_and(c.versao_plano = 0), false), string_agg(c.versao_plano::text, ', ')
  from public.agenda_config c;

-- ── T. As 6 tabelas ─────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 %s existe, com RLS ligada', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t;

insert into _resultado
select format('T2 %s: policies só de leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t
  left join pg_policies p on p.schemaname = 'public' and p.tablename = t
 group by t;

insert into _resultado
select format('T3 %s: anon sem nada; authenticated só lê', t),
       to_regclass('public.' || t) is not null
       and not (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
                or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete'))
       and has_table_privilege('authenticated', 'public.' || t, 'select')
       and not (has_table_privilege('authenticated', 'public.' || t, 'insert')
                or has_table_privilege('authenticated', 'public.' || t, 'update')
                or has_table_privilege('authenticated', 'public.' || t, 'delete')),
       null
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t
 where to_regclass('public.' || t) is not null
union all
select format('T3 %s: anon sem nada; authenticated só lê', t), false, 'a tabela não existe'
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t
 where to_regclass('public.' || t) is null;

-- ── F. Funções ──────────────────────────────────────────────────────────────────────────────────────────
-- O contrato: o que as ferramentas, os comandos, o fechamento, o motor de 15 min e a tela de compras chamam.
insert into _resultado
select format('F1 %s existe', f), to_regprocedure('public.' || f) is not null, null
  from unnest(array[
    'agenda_ver(uuid,text,text,text,text,jsonb,boolean,date)',
    'agenda_rascunho_planejar(uuid,text,text,jsonb,text,date)',
    'agenda_rascunho_material(uuid,text,text,text[],text,text,text,numeric,boolean,text,date)',
    'agenda_rascunho_disponibilidade(uuid,text,text,text,text,boolean,text,date)',
    'agenda_rascunho_ler(uuid,date)',
    'agenda_rascunho_gravar(uuid,date)',
    'agenda_rascunho_descartar(uuid)',
    'agenda_textos_do_fechamento(date,date)',
    'os_material_sincronizar_carteira(date)',
    'get_os_purchase_needs(uuid)',
    'agenda_disponibilidade_semear(date)',
    'agenda_capacidade_semanal(date)',
    'os_prontidao(uuid,date)']) f;

-- O padrão de nomes da Fase 1 (em produção, antes dela, só _os_tecnico_nao_troca_cliente casava, sem anon).
insert into _resultado
select 'F2 nenhuma função da agenda (agenda_*, _agenda_*, os_*, _os_*, _autor_da_agenda, aplicar_os_material) executável por anon',
       count(*) > 0 and count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0,
       format('%s funções; com anon: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname ~ '^(_?agenda_|_?os_|_autor_da_agenda$|aplicar_os_material$)';

insert into _resultado
select 'F3 as internas (os três aplicar, salvar o rascunho, conferir o cargo, sincronizar, semear) só para service_role',
       count(*) > 0 and count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute')) = 0,
       format('%s funções; com authenticated: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('authenticated', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname ~ '^(_agenda_aplicar_|os_material_sincronizar|agenda_disponibilidade_semear$|_autor_da_agenda$|_agenda_rascunho_salvar$)';

insert into _resultado
select 'F4 as leituras (agenda_ver, prontidão, capacidade, fechamento) são STABLE ou IMMUTABLE: não gravam',
       count(*) = 6 and bool_and(p.provolatile in ('s', 'i')),
       string_agg(p.proname || ' ' || p.provolatile::text, ', ')
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('agenda_ver', 'os_prontidao', 'os_prontidao_carteira', 'agenda_capacidade_semanal',
                     'agenda_textos_do_fechamento', 'agenda_rascunho_ler');

-- ── S. A semente ────────────────────────────────────────────────────────────────────────────────────────
-- A equipe recente pela MESMA regra da semente (agenda_disponibilidade_semear, 160200): diária (pelo perfil de
-- trabalho) nos equipe_recente_dias dias até a última diária lançada, cadastro ativo de prestador/diarista/
-- funcionário e perfil de trabalho vigente hoje.
create temp table _equipe_recente on commit drop as
with cfg as (select * from public.agenda_config),
     ultima as (select max(ws.data) as u from public.work_shifts ws
                 where ws.tipo = 'diaria' and ws.fracao > 0 and ws.data <= public._hoje_brt())
select distinct p.id as payee_id, p.name
  from public.payees p, cfg, ultima
 where ultima.u is not null
   and p.active and p.kind in ('prestador', 'diarista', 'funcionario')
   and exists (select 1 from public.work_profiles wp
                where wp.payee_id = p.id and wp.vigencia_inicio <= public._hoje_brt()
                  and (wp.vigencia_fim is null or wp.vigencia_fim >= public._hoje_brt()))
   and exists (select 1 from public.work_shifts ws
                 join public.work_profiles wp on wp.id = ws.work_profile_id
                where wp.payee_id = p.id and ws.tipo = 'diaria' and ws.fracao > 0
                  and ws.data between ultima.u - (cfg.equipe_recente_dias - 1) and ultima.u);

create temp table _com_padrao on commit drop as
select distinct d.payee_id
  from public.agenda_disponibilidade d
 where d.origem = 'historico' and d.substituida_em is null;

insert into _resultado
select 'S1 há padrão medido (a semente rodou) quando há diária lançada',
       (select count(*) from _equipe_recente) = 0 or (select count(*) from _com_padrao) > 0,
       format('equipe recente: %s; com padrão: %s',
              coalesce((select string_agg(e.name, ', ' order by e.name) from _equipe_recente e), 'ninguém'),
              (select count(*) from _com_padrao));

insert into _resultado
select 'S2 ninguém fora da equipe recente tem padrão medido (quem saiu sai pela regra, não pelo nome)',
       count(*) = 0,
       coalesce(string_agg(coalesce(p.name, c.payee_id::text), ', '), 'ninguém')
  from _com_padrao c
  left join public.payees p on p.id = c.payee_id
 where c.payee_id not in (select e.payee_id from _equipe_recente e);

insert into _resultado
select 'S3 o sócio nunca tem padrão medido (ele entra quando disser o dele)',
       count(*) = 0, coalesce(string_agg(p.name, ', '), 'nenhum')
  from public.agenda_disponibilidade d
  join public.payees p on p.id = d.payee_id
 where d.origem = 'historico' and d.substituida_em is null and p.kind = 'socio';

insert into _resultado
select 'S4 padrão medido é por dia útil (seg–sex), turno nulo, frequência entre frequencia_minima e 1',
       count(*) filter (where not (d.dias_semana <@ '{1,2,3,4,5}'::smallint[] and cardinality(d.dias_semana) = 1
                                   and d.turno is null and d.situacao = 'disponivel'
                                   and d.frequencia between c.frequencia_minima and 1)) = 0,
       format('%s linhas', count(*))
  from public.agenda_disponibilidade d, public.agenda_config c
 where d.origem = 'historico' and d.substituida_em is null;

insert into _resultado
select 'S5 a capacidade é Σ frequência × carga_max (o único número que o dono lê)',
       (cap ->> 'conta_dono')::boolean
       or (abs((cap ->> 'diarias_semana')::numeric - soma) < 0.01
           and abs((cap ->> 'comprometivel')::numeric - soma * carga) < 0.01),
       format('diarias_semana %s, comprometivel %s; Σ frequência %s × carga %s', cap ->> 'diarias_semana',
              cap ->> 'comprometivel', round(soma, 4), carga)
  from (select public.agenda_capacidade_semanal() as cap,
               coalesce((select sum(d.frequencia) from public.agenda_disponibilidade d
                          where d.origem = 'historico' and d.substituida_em is null), 0) as soma,
               (select c.carga_max from public.agenda_config c) as carga) x;

-- ── L e N. Leituras de verdade, pela mesma RPC das ferramentas e dos comandos ───────────────────────────
create temp table _contagem on commit drop as
select 'antes' as quando,
       (select count(*) from public.os_planejamento) as plan,
       (select count(*) from public.os_planejamento_equipe) as equipe,
       (select count(*) from public.os_material) as mat,
       (select count(*) from public.agenda_disponibilidade) as disp,
       (select count(*) from public.agenda_rascunho) as rasc,
       (select coalesce(max(atualizado_em), 'epoch') from public.os_material) as mat_em;

-- O dono: o admin ligado ao sócio (a faxina da Fase 0 liga); sem ligação, o único admin ativo.
create temp table _leitura on commit drop as
with dono as (
  select coalesce(
    (select p.app_user_id from public.payees p join public.app_users u on u.id = p.app_user_id
      where p.kind = 'socio' and p.active and u.role = 'admin' and u.active order by p.created_at limit 1),
    (select u.id from public.app_users u where u.role = 'admin' and u.active order by u.created_at limit 1)) as id)
select dono.id as autor,
       public.agenda_ver(p_autor => dono.id, p_foco => 'o_que_fazer') as fazer,
       public.agenda_ver(p_autor => dono.id, p_foco => 'o_que_fazer') as fazer2,
       public.agenda_ver(p_autor => dono.id) as semana,
       public.agenda_ver(p_autor => dono.id, p_os => 'OS-99999') as inexistente,
       public.agenda_textos_do_fechamento(public._hoje_brt(), public.agenda_somar_du(public._hoje_brt(), 1)) as fechamento,
       (select c.texto_max from public.agenda_config c) as texto_max,
       (select c.modo_leitura from public.agenda_config c) as modo
  from dono;

insert into _contagem
select 'depois', (select count(*) from public.os_planejamento), (select count(*) from public.os_planejamento_equipe),
       (select count(*) from public.os_material), (select count(*) from public.agenda_disponibilidade),
       (select count(*) from public.agenda_rascunho),
       (select coalesce(max(atualizado_em), 'epoch') from public.os_material);

insert into _resultado
select 'L0 há um admin ativo para ler a agenda (o dono)', l.autor is not null, l.autor::text from _leitura l;

insert into _resultado
select 'L1 "o que eu tenho que fazer": ok, texto não vazio e dentro de texto_max',
       (l.fazer ->> 'ok')::boolean and length(l.fazer ->> 'texto') > 0 and length(l.fazer ->> 'texto') <= l.texto_max,
       format('%s caracteres (máx. %s): %s', length(l.fazer ->> 'texto'), l.texto_max, left(l.fazer ->> 'texto', 120))
  from _leitura l;

insert into _resultado
select 'L2 os 5 blocos, na ordem: Hoje, Travado esperando você (ou nada travado), Prontos, Em risco, Outras pendências',
       strpos(t, 'Hoje (') = 1
       and strpos(t, 'Outras pendências') > strpos(t, 'Hoje (')
       and strpos(t, 'Prontos sem data') > 0 and strpos(t, 'Outras pendências') > strpos(t, 'Prontos sem data'),
       left(t, 300)
  from (select l.fazer ->> 'texto' as t from _leitura l) x;

insert into _resultado
select 'L3 a semana: ok, texto não vazio e dentro de texto_max',
       (l.semana ->> 'ok')::boolean and length(l.semana ->> 'texto') > 0 and length(l.semana ->> 'texto') <= l.texto_max,
       left(l.semana ->> 'texto', 160)
  from _leitura l;

insert into _resultado
select 'L4 OS que não existe: "Não encontrei", sem inventar',
       not (l.inexistente ->> 'ok')::boolean and l.inexistente ->> 'texto' like 'Não encontrei%',
       l.inexistente ->> 'texto'
  from _leitura l;

insert into _resultado
select 'L5 a mesma pergunta duas vezes = o mesmo texto (md5)',
       md5(l.fazer ->> 'texto') = md5(l.fazer2 ->> 'texto'), md5(l.fazer ->> 'texto')
  from _leitura l;

insert into _resultado
select 'L6 o fechamento lê o mesmo modo da config (sombra = o Secretário só registra)',
       l.fechamento ->> 'modo' = l.modo, format('fechamento %s, config %s', l.fechamento ->> 'modo', l.modo)
  from _leitura l;

insert into _resultado
select 'N1 as leituras não gravaram nada (as 4 tabelas de fato e o rascunho)',
       a.plan = d.plan and a.equipe = d.equipe and a.mat = d.mat and a.disp = d.disp and a.rasc = d.rasc
       and a.mat_em = d.mat_em,
       format('antes %s/%s/%s/%s/%s, depois %s/%s/%s/%s/%s', a.plan, a.equipe, a.mat, a.disp, a.rasc,
              d.plan, d.equipe, d.mat, d.disp, d.rasc)
  from _contagem a, _contagem d
 where a.quando = 'antes' and d.quando = 'depois';

-- ── E. Erros da agenda no registro de erros ─────────────────────────────────────────────────────────────
-- Os comandos gravam context 'agenda' (action 'comando:<x>'); o motor de 15 min, action 'agenda:material'. O
-- fechamento das 17:30 não grava aqui: a leitura da agenda que falha só avisa no log da função e o fechamento sai
-- como na Fase 0 (conferir resumo_tarde.detalhe.agenda).
insert into _resultado
select 'E1 nenhum erro da agenda aberto nas últimas 24 horas (comandos e motor de 15 min)',
       count(*) = 0,
       coalesce(string_agg(format('%s/%s ×%s: %s', e.context, e.action, e.occurrences, left(e.message, 80)), ' | '),
                'nenhum')
  from public.app_error_logs e
 where e.resolved_at is null
   and e.last_seen_at > now() - interval '24 hours'
   and (e.context = 'agenda' or e.action like 'agenda:%');

select teste, ok, detalhe from _resultado order by teste;

rollback;
