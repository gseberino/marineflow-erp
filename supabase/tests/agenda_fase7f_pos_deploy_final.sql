-- Conferência DEPOIS de publicar o pacote final da Fase 7f da Agenda de Produção (P5, a equipe; P6, o cliente; P9, a semana que mudou e a saúde; e o dado que põe os 3 modos em teste): as migrations
-- 20261109101000, 101100, 101200 e o dado 101900. Roteiro: fila-do-dono/fase77f-publicar-final.md. Spec: spec-fase7f.md §10, §11 (aceites 6 e 7), R8.13, R8.14; notas-fase7f.md, seções P5, P6 e P9.
-- bancada: depende de 20261109101200
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); termina em ROLLBACK. Das tabelas de mensagem, só contagens.
-- As versões conferem-se POR NOME, nunca por max(version): o retorno rápido publica 20261116* acima destas, e o aplicar.sh aplica fora de sequência de propósito.
-- Na bancada (scripts/bancada-agenda/rodar.mjs, que não aplica o dado 101900) o dado não é exigido: os 3 ficam desligados.
--
--   M  as 3 de estrutura registradas por nome; o dado 101900 registrado (na bancada, só mostra)
--   C  os 3 modos da equipe e do cliente em sombra (ligados só pelo OK nomeado, com o código no banco); bloco, prazo e lote como estão (em teste, ou ligados na ordem dos OKs); o freio (só mostra);
--      semana fora de cliente_tipos_ligados enquanto as camadas não ligam
--   F  cada uma das 37 funções de P5, P6 e P9 (23 recriadas e 14 novas): a assinatura, 1 por nome, security definer, volatilidade, search_path=public, as portas (anon e PUBLIC nunca) e o md5 do corpo
--      (sem CR); 1 assinatura de _agenda_equipe_registrar, a de 10 argumentos
--   E  nenhuma mensagem da equipe da 7f (previsto, mudança, convite) fora de teste, enquanto o modo dela não estiver ligado; nenhuma mensagem semana na fila, enquanto as camadas não ligarem
--   Z  agenda_saude().comunicacao com os 13 zeros em 0 e zeros_ok; os modos que ela lê = os da linha; os números da equipe e do cliente presentes em teste; agenda_saude().ok (com o dado)
--   S  nenhum erro cliente:% nem comunicar:% nas últimas 24 h; com o dado, a rodada do cliente dos últimos 30 min sem erro e com o passo semana chamado; a rodada comunicar dos últimos 30 min sem erro
--      (seg a sáb; no domingo só mostra)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do dado (passo 2) e do tique seguinte, no dia seguinte e antes de cada "ligar":
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7f_pos_deploy_final.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pf on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261109101900') as dado,
       coalesce(current_setting('agenda_teste.feriados', true), '') <> '' as bancada;

-- ── M. As migrations, por nome ────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v), exists (select 1 from supabase_migrations.schema_migrations m where m.version = v), null
  from unnest(array['20261109101000', '20261109101100', '20261109101200']) v;
insert into _resultado
select 'M2 o dado 20261109101900 (o previsto, o convite e as camadas em teste) registrado (na bancada, só mostra)',
       (select dado or bancada from _pf),
       case when (select dado from _pf) then 'registrado' else 'não registrado' end;

-- ── C. A configuração ─────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 os 3 modos com o valor do dado: com ele, previsto, convite e camadas em teste (ligados só pelo OK nomeado); sem ele, desligados',
       case when (select dado from _pf)
            then c.modo_equipe_previsto in ('sombra', 'ligado') and c.modo_equipe_convite in ('sombra', 'ligado') and c.modo_cliente_camadas in ('sombra', 'ligado')
            else array[c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas] <@ array['desligado'] end,
       format('previsto %s, convite %s, camadas %s', c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C2 bloco, prazo e lote como estão: em teste, ou ligados na ordem dos OKs (o lote e o prazo só com o bloco ligado); sem o dado da 7f núcleo, desligados',
       case when exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261109100900')
            then c.modo_bloco_agenda in ('sombra', 'ligado')
                 and (c.modo_lote_dono = 'sombra' or (c.modo_lote_dono = 'ligado' and c.modo_bloco_agenda = 'ligado'))
                 and (c.modo_veto = 'sombra' or (c.modo_veto = 'ligado' and c.modo_bloco_agenda = 'ligado'))
            else true end,
       format('bloco %s, prazo %s, lote %s', c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C3 semana fora de cliente_tipos_ligados enquanto as camadas não ligam (só o "OK semana prevista ao cliente" a põe)',
       not ('semana' = any (c.cliente_tipos_ligados)) or c.modo_cliente_camadas = 'ligado', array_to_string(c.cliente_tipos_ligados, ', ')
  from public.agenda_config c where c.id;
insert into _resultado
select 'C4 o freio — só mostra (com gestor_so_propor, o que ligar vale como em teste)', true, format('gestor_so_propor %s desde %s', c.gestor_so_propor, c.gestor_so_propor_em)
  from public.agenda_config c where c.id;

-- ── F. As funções ─────────────────────────────────────────────────────────────────────────────────
-- (assinatura, security definer, volatilidade, quem executa além do dono, o tipo, o md5 do corpo sem CR: gerado por f7f/p9/gerar9.mjs)
create temp table _pf_f (f text primary key, definer boolean not null, vol "char" not null, papeis text not null, tipo text not null, m text not null) on commit drop;
insert into _pf_f values
  ('_agenda_cliente_a_mensagem(text,text,date)', false, 's', 'authenticated service_role', 'recriada', '8a87cf75193e6d076899d58a1968dc52'),
  ('_agenda_cliente_atraso(date,timestamptz)', false, 'v', '', 'recriada', 'ee9c4aae6a55819f1ef482858db44328'),
  ('_agenda_cliente_camada(uuid,date)', false, 's', '', 'nova', 'a1eb203c7f49b9a560871503d4ec88ec'),
  ('_agenda_cliente_confirmar(date,timestamptz)', false, 'v', '', 'recriada', '0a78bff2ff610f8d83ac9e617b83a6e4'),
  ('_agenda_cliente_material(date,timestamptz)', false, 'v', '', 'recriada', 'a1e2d592117a08fcc188bd52058ba01c'),
  ('_agenda_cliente_o_que(text,date)', false, 's', 'authenticated service_role', 'recriada', '3295ebb90de4c6309d647a6092aaffa8'),
  ('_agenda_cliente_registrar(text,text,uuid,date,jsonb,timestamptz,timestamptz,text,text,timestamptz,uuid)', true, 'v', '', 'recriada', '6f7d670cb149c3b9df5c7f3331783691'),
  ('_agenda_cliente_revalidar(uuid,timestamptz)', true, 's', '', 'recriada', 'c16166497a20198f48c6ef634ab8f403'),
  ('_agenda_cliente_semana_mudou(uuid,jsonb,date,timestamptz,timestamptz,timestamptz)', false, 'v', '', 'nova', 'aa523e46eccbc98ec043960efff8e531'),
  ('_agenda_cliente_semana(date,timestamptz)', false, 'v', '', 'nova', 'b7f76c5a8c8e20e26b9122f1dcfb2bb5'),
  ('_agenda_cliente_texto(text,text,uuid,jsonb,date)', false, 's', 'authenticated service_role', 'recriada', '31800776bfe8156f9aade32adcae9c99'),
  ('_agenda_cliente_tipo_texto(text)', false, 'i', 'authenticated service_role', 'recriada', 'dd7f13b187dd650d0f777336476ace46'),
  ('_agenda_comunicar_convites_vencidos(date,timestamptz)', false, 'v', '', 'nova', '26d0fb09847018c414bae660c14ec8e4'),
  ('_agenda_comunicar_convites(date,timestamptz)', false, 'v', '', 'nova', '583533a1d222bf0d19dbcbfccd154fa4'),
  ('_agenda_comunicar_mudancas_equipe(date,timestamptz)', false, 'v', '', 'nova', '6bef893f260cae3609f46c2d7da9099a'),
  ('_agenda_comunicar_previsto(date,timestamptz)', false, 'v', '', 'nova', '522c834301755462d2369d12cbe0c478'),
  ('_agenda_dias_avisados(uuid,date,date,text)', false, 's', '', 'nova', 'c98a8edb8037c32830dcad30445c77db'),
  ('_agenda_dias_do_plano_da_pessoa(uuid,date,date,date)', false, 's', 'service_role', 'nova', '914200ef5658d6ca7198482f3f970a7f'),
  ('_agenda_equipe_convite_prazo(date)', false, 's', '', 'nova', 'c71d6bcdb4046f45ec7f796e7cb90646'),
  ('_agenda_equipe_ja_avisei(uuid,date,uuid)', false, 's', 'authenticated service_role', 'nova', '72945533cdbbe5afffa0fedca23ef2d9'),
  ('_agenda_equipe_mudanca_na_hora(uuid,date,timestamptz)', false, 'v', '', 'nova', 'e25f309b2539d0ea09fe4bf28975267d'),
  ('_agenda_equipe_previstas_hoje(uuid,date,timestamptz)', false, 's', 'service_role', 'recriada', '7e86318b5a6ba01f3b960a9a73debb3a'),
  ('_agenda_equipe_previsto_sozinho(uuid,date)', false, 's', 'service_role', 'nova', '3890366d7f595d95d750cb94ed0c5959'),
  ('_agenda_equipe_registrar(uuid,date,text,text,timestamptz,date,text,date[],uuid[],text)', true, 'v', '', 'recriada', '148f8368deca843de325a6800556a952'),
  ('_agenda_equipe_semana_da_pessoa(uuid,date,timestamptz,text)', false, 's', '', 'nova', 'bae9cfe1db140251877cccda85f760b1'),
  ('_agenda_rotina_acordes_da_equipe(date,timestamptz)', false, 'v', '', 'recriada', 'ae015c82c843ab919bb4f4904e3509e9'),
  ('_agenda_rotina_como_foi(date,timestamptz)', false, 'v', '', 'recriada', 'd3e8b6f77ecef723fd4a529979ea338f'),
  ('_agenda_rotina_ficha(date,timestamptz)', false, 'v', '', 'recriada', '592d7ce112fa55352963cce9262406b5'),
  ('_agenda_rotina_sem_resposta(date,timestamptz)', false, 'v', '', 'recriada', 'a54998819118aeb56307d7120a59b52e'),
  ('_agenda_saude_comunicacao(date,timestamptz)', true, 's', 'authenticated service_role', 'recriada', '6288e345b16e1692b39dd8032ec304ea'),
  ('_agenda_texto_do_acorde(uuid,date,date)', false, 's', 'authenticated service_role', 'recriada', 'fe74256e797060fa445369cc2eade6c8'),
  ('_agenda_ver_clientes(uuid,date)', true, 's', 'authenticated service_role', 'recriada', '450e268e59bef6f7194e2afcd8c5dc02'),
  ('agenda_cliente_preparar(uuid,text,text,boolean,text,date,timestamptz)', true, 'v', 'authenticated service_role', 'recriada', 'e34be333a30b0ac4e8cc2094c46920e8'),
  ('agenda_cliente_vigiar(date,timestamptz)', true, 'v', 'service_role', 'recriada', '3ab3111e7816abf924f366a5473723b6'),
  ('agenda_resposta_da_equipe(text,text,text,timestamptz)', true, 'v', 'service_role', 'recriada', 'f572cd9e2068d952b3c862be24c9d46a'),
  ('agenda_resposta_do_cliente(text,text,uuid,text,text,text,timestamptz)', true, 'v', 'service_role', 'recriada', 'ea0fee57dd0cdf739cc9d1feb4131abe'),
  ('agenda_saude(date,timestamptz)', false, 's', 'authenticated service_role', 'recriada', 'f8fce4dc30ff533daa172709a9b7b437');
insert into _resultado
select format('F1 %s (%s): existe, 1 por nome, %s, %s, search_path=public, executa: %s', r.f, r.tipo, case when r.definer then 'definer' else 'invoker' end,
              case r.vol when 'i' then 'immutable' when 's' then 'stable' else 'volatile' end, coalesce(nullif(r.papeis, ''), 'ninguém de fora')),
       p.oid is not null
       and (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) = 1
       and p.prosecdef = r.definer and p.provolatile = r.vol and 'search_path=public' = any (coalesce(p.proconfig, '{}'))
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('public', p.oid, 'execute')
       and has_function_privilege('authenticated', p.oid, 'execute') = (r.papeis like '%authenticated%')
       and has_function_privilege('service_role', p.oid, 'execute') = (r.papeis like '%service_role%'),
       case when p.oid is null then 'NÃO EXISTE'
            else format('assinaturas %s; definer %s; %s; %s; anon %s, public %s, authenticated %s, service_role %s',
                        (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname), p.prosecdef, p.provolatile, p.proconfig,
                        has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('public', p.oid, 'execute'),
                        has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute')) end
  from _pf_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select format('F2 %s: o corpo é o do pacote final (md5)', r.f), p.oid is not null and md5(replace(p.prosrc, chr(13), '')) = r.m,
       case when p.oid is null then 'NÃO EXISTE' when md5(replace(p.prosrc, chr(13), '')) <> r.m then 'md5 ' || md5(replace(p.prosrc, chr(13), '')) || ' ≠ ' || r.m end
  from _pf_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select 'F3 _agenda_equipe_registrar: 1 assinatura, a de 10 argumentos; a de 7 saiu',
       count(*) = 1 and bool_and(p.pronargs = 10)
       and to_regprocedure('public._agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text)') is null,
       string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_agenda_equipe_registrar';

-- ── E. Nada foi a ninguém ─────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'E1 nenhuma mensagem da equipe da 7f (previsto, mudança, convite) fora de teste, enquanto o modo dela não estiver ligado',
       count(*) filter (where e.tipo in ('previsto', 'mudanca') and c.modo_equipe_previsto <> 'ligado') = 0
       and count(*) filter (where e.tipo = 'convite' and c.modo_equipe_convite <> 'ligado') = 0,
       format('%s fora de teste', count(*))
  from public.agenda_config c
  left join public.agenda_equipe_mensagens e on e.tipo in ('previsto', 'mudanca', 'convite') and e.modo <> 'sombra'
 where c.id;
insert into _resultado
select 'E2 nenhuma mensagem semana na fila enquanto as camadas não ligarem', c.modo_cliente_camadas = 'ligado' or n.n = 0, format('%s na fila', n.n)
  from public.agenda_config c
 cross join (select count(*) n from public.whatsapp_send_queue q join public.agenda_cliente_mensagens m on m.id = q.source_ref_id where q.source = 'agenda-cliente' and m.tipo = 'semana') n
 where c.id;

-- ── Z. A saúde ────────────────────────────────────────────────────────────────────────────────────
create temp table _pf_z on commit drop as
select public.agenda_saude() as s, public.agenda_saude() -> 'comunicacao' as com, (select to_jsonb(c) from public.agenda_config c where c.id) as cfg;
insert into _resultado
select 'Z1 agenda_saude().comunicacao: os 13 zeros em 0 (os 6 do núcleo e os 7 da equipe e do cliente) e zeros_ok',
       coalesce((z.com ->> 'zeros_ok')::boolean, false)
       and (select count(*) from unnest(array['assumida_sem_prazo_mostrado', 'assumida_que_esperava', 'assumida_tipo_proibido', 'teto_passou_sem_motivo', 'bloco_grande', 'excecao_acima_do_teto',
                                              'equipe_fora_da_janela', 'equipe_acima_do_teto', 'ficha_sem_sim', 'mudanca_19h_repetida', 'dia_exato_cedo', 'promessa_mudou_sem_dono',
                                              'semana_como_dia_ouvido']) k where z.com ->> k = '0') = 13,
       left(z.com::text, 900)
  from _pf_z z;
insert into _resultado
select 'Z2 a saúde lê os 6 modos crus da linha',
       z.com -> 'modos' = jsonb_build_object('bloco', z.cfg ->> 'modo_bloco_agenda', 'lote', z.cfg ->> 'modo_lote_dono', 'veto', z.cfg ->> 'modo_veto',
                                             'previsto', z.cfg ->> 'modo_equipe_previsto', 'convite', z.cfg ->> 'modo_equipe_convite', 'camadas', z.cfg ->> 'modo_cliente_camadas'),
       (z.com -> 'modos')::text
  from _pf_z z;
insert into _resultado
select 'Z3 os números da equipe e do cliente aparecem com o modo deles fora de desligado (e só então)',
       (z.com -> 'numeros' ? 'equipe') = (z.cfg ->> 'modo_equipe_previsto' <> 'desligado' or z.cfg ->> 'modo_equipe_convite' <> 'desligado')
       and (z.com -> 'numeros' ? 'cliente') = (z.cfg ->> 'modo_cliente_camadas' <> 'desligado'),
       left((z.com -> 'numeros')::text, 400)
  from _pf_z z;
insert into _resultado
select 'Z4 agenda_saude().ok, com o dado no ar (na bancada, só mostra)', (select bancada or not dado from _pf) or coalesce((z.s ->> 'ok')::boolean, false), z.s ->> 'ok'
  from _pf_z z;

-- ── S. Sem erro, e o tique ────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'S1 nenhum erro da rodada do cliente nem da comunicar nas últimas 24 h (cliente:% e comunicar:%)', count(*) = 0,
       coalesce(string_agg(distinct e.context || '/' || e.action, ', '), 'nenhum')
  from public.app_error_logs e
 where e.last_seen_at >= now() - interval '24 hours'
   and ((e.context = 'agenda' and (e.action like 'cliente:%' or e.action like 'comunicar:%')) or (e.context = 'task-automations' and e.action = 'agenda:comunicar'));
insert into _resultado
select 'S2 a 1ª rodada do cliente depois do dado: nos últimos 30 min, sem erro, com o passo semana chamado (sem o dado, só mostra)',
       case when not (select dado from _pf) then true
            else exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'cliente' and r.rodou_em >= now() - interval '30 minutes' and r.erros = 0 and r.contagens ? 'semana') end,
       coalesce((select format('a última: %s, erros %s, %s ms, passo semana %s', r.rodou_em, r.erros, r.duracao_ms, r.contagens ? 'semana') from public.agenda_vigia_rodadas r where r.rotina = 'cliente'
                  order by r.rodou_em desc limit 1), 'ainda não rodou');
insert into _resultado
select 'S3 a rodada comunicar depois do dado: nos últimos 30 min, sem erro (no domingo, ou sem o dado, só mostra)',
       case when not (select dado from _pf) or extract(isodow from public._hoje_brt()) = 7 then true
            else exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'comunicar' and r.rodou_em >= now() - interval '30 minutes' and r.erros = 0) end,
       coalesce((select format('a última: %s, erros %s, %s ms', r.rodou_em, r.erros, r.duracao_ms) from public.agenda_vigia_rodadas r where r.rotina = 'comunicar'
                  order by r.rodou_em desc limit 1), 'ainda não rodou');

select teste, ok, detalhe from _resultado order by teste;

rollback;
