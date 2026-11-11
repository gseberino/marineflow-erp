-- Conferência DEPOIS de publicar a Fase 7e da Agenda de Produção ("a margem que aprende"): as 8 migrations de estrutura (20261111100000, 100100, 100200, 100300, 100350, 100400, 100500, 100600)
-- e o dado (20261111100900). Roteiro: fila-do-dono/fase77e-publicar.md. Spec: spec-fase7e.md §8.3 (agenda_fase7e_pos_deploy.sql), §11, R7.13, R7.14; notas-fase7e.md, seções P1 a P8.
-- bancada: depende de 20261111100600
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); termina em ROLLBACK. Nenhuma tabela de mensagem é lida.
-- As versões conferem-se POR NOME, nunca por max(version): o retorno rápido publicou 20261116* acima destas, e o aplicar.sh aplica fora de sequência de propósito.
-- Na bancada (scripts/bancada-agenda/rodar.mjs, que não aplica o dado 20261111100900) o dado não é exigido: os 6 ficam desligados e o fornecedor em 5.
--
--   M  as 8 de estrutura registradas por nome; o dado registrado (na bancada, só mostra)
--   C  as colunas novas (38 em agenda_config, 12 em os_planejamento, 12 em agenda_medidas_os) e a tabela agenda_medidas_compra (com RLS); o DEFAULT sombra dos 6;
--      os 6 modos: com o dado, em teste ou ligados pelo OK nomeado, e o prazo real e a folga da compra NUNCA ligados (AG7-32, R7.5-16); sem o dado, desligados; o fornecedor com 3 entregas
--      (linha e DEFAULT) com o dado; o freio (só mostra); a lista de itens do aprendizado com os 6 da margem
--   F  cada uma das 54 funções da 7e (25 recriadas e 29 novas): a assinatura, 1 por nome, security definer, volatilidade, search_path=public, as portas (anon e PUBLIC nunca) e o md5
--      do corpo (sem CR: o do replay, f7e/p8/gerar-sql.mjs)
--   Z  agenda_saude().margem: os zeros em 0 e zeros_ok; agenda_saude().ok (com o dado; na bancada só mostra)
--   S  nenhum erro aprender:% nem gestor:puxar nas últimas 24 h, e nenhum aberto; com o dado, a 1ª rodada do aprendizado com a margem, sem erro e com os 6 modos dela (antes dela, só mostra)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (sem o dado: C2 e C3 pedem os de antes), depois do dado (passo 3), no dia seguinte depois das 16:00 e antes de cada "ligar":
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pe on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261111100900') as dado,
       coalesce(current_setting('agenda_teste.feriados', true), '') <> '' as bancada;

-- ── M. As migrations, por nome ────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v), exists (select 1 from supabase_migrations.schema_migrations m where m.version = v), null
  from unnest(array['20261111100000', '20261111100100', '20261111100200', '20261111100300', '20261111100350', '20261111100400', '20261111100500', '20261111100600']) v;
insert into _resultado
select 'M2 o dado 20261111100900 (os 6 em teste, o fornecedor com 3 entregas) registrado (na bancada, só mostra)',
       (select dado or bancada from _pe), case when (select dado from _pe) then 'registrado' else 'não registrado' end;

-- ── C. A configuração e as colunas ────────────────────────────────────────────────────────────────
insert into _resultado
select format('C1 as colunas novas de %s (%s)', t.tab, t.n),
       (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tab and c.column_name = any (t.cols)) = t.n,
       format('%s de %s; faltam: %s', (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tab and c.column_name = any (t.cols)), t.n,
              coalesce((select string_agg(x, ', ') from unnest(t.cols) x where not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tab and c.column_name = x)), '—'))
  from (values ('agenda_config', 38, array['modo_vies', 'modo_folga_semana', 'modo_urgencia', 'modo_promessa', 'modo_tempo_compra', 'modo_folga_compra', 'credibilidade_k', 'vies_n_min', 'vies_min', 'vies_max', 'vies_corrige_dono', 'folga_dispersao_padrao', 'folga_percentil', 'folga_semanas', 'folga_semanas_min', 'folga_residuos_min', 'folga_meios_min', 'folga_semana_max', 'folga_semana_min', 'folga_semana_troca_max', 'carga_semana_min', 'carga_semana_max', 'folga_temporada_barco', 'folga_temporada_rv', 'urgencia_du', 'puxar_hora', 'puxar_quem', 'puxar_max_os', 'promessa_n_min', 'promessa_min', 'tempo_compra_n_min', 'tempo_compra_percentil', 'tempo_compra_max_du', 'folga_compra_n_min', 'folga_compra_percentil', 'folga_compra_max_du', 'prazo_sem_fornecedor_n_min', 'aprender_tempo_max']),
               ('os_planejamento', 12, array['estimativa_no_inicio_em', 'dp_bruto_no_inicio', 'pessoas_no_inicio', 'pm_plano_no_inicio', 'inicio_plano_no_inicio', 'prazo_plano_no_inicio', 'marcado_em', 'vies_marcado', 'vies_marcado_chave', 'tempo_compra_marcado', 'folga_compra_marcada', 'vies_dono_fixo']),
               ('agenda_medidas_os', 12, array['pm_reais', 'pm_estimados', 'estimativa_origem', 'razao_estimativa', 'pm_plano_dono', 'razao_dono', 'prazo_plano_du', 'prazo_real_du', 'razao_prazo', 'vies_marcado', 'compra_pendente', 'motivo_razao'])) t(tab, n, cols);
insert into _resultado
select 'C1b a tabela agenda_medidas_compra existe, com RLS ligada, e anon não lê',
       c.oid is not null and c.relrowsecurity and not has_table_privilege('anon', c.oid, 'select'), format('rls %s', c.relrowsecurity)
  from (select to_regclass('public.agenda_medidas_compra') as oid) x left join pg_class c on c.oid = x.oid;
insert into _resultado
select 'C2 os 6 modos: com o dado, em teste ou ligados pelo OK nomeado, e o prazo real e a folga da compra nunca ligados; sem o dado, desligados',
       case when (select dado from _pe)
            then array[c.modo_vies, c.modo_folga_semana, c.modo_urgencia, c.modo_tempo_compra] <@ array['sombra', 'ligado']
                 and c.modo_promessa = 'sombra' and c.modo_folga_compra = 'sombra'
            else array[c.modo_vies, c.modo_folga_semana, c.modo_urgencia, c.modo_promessa, c.modo_tempo_compra, c.modo_folga_compra] <@ array['desligado'] end,
       concat_ws(' ', c.modo_vies, c.modo_folga_semana, c.modo_urgencia, c.modo_promessa, c.modo_tempo_compra, c.modo_folga_compra)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C3 o DEFAULT dos 6 modos é sombra (a linha nasce desligada; o dado a põe em teste)',
       count(*) = 6 and bool_and(i.column_default like '''sombra''%'), string_agg(i.column_name || ' ' || coalesce(i.column_default, 'nulo'), '; ')
  from information_schema.columns i
 where i.table_schema = 'public' and i.table_name = 'agenda_config'
   and i.column_name in ('modo_vies', 'modo_folga_semana', 'modo_urgencia', 'modo_promessa', 'modo_tempo_compra', 'modo_folga_compra');
insert into _resultado
select 'C4 o fornecedor: com o dado, a linha fora de 5 (3, ou o que o dono pôs) e o DEFAULT 3; sem ele, 5 e 5',
       case when (select dado from _pe) then c.fornecedor_n_min <> 5 and i.column_default = '3' else c.fornecedor_n_min = 5 and i.column_default = '5' end,
       format('linha %s, DEFAULT %s', c.fornecedor_n_min, i.column_default)
  from public.agenda_config c
 cross join information_schema.columns i
 where c.id and i.table_schema = 'public' and i.table_name = 'agenda_config' and i.column_name = 'fornecedor_n_min';
insert into _resultado
select 'C5 o freio — só mostra (com gestor_so_propor, o que ligar vale como em teste: R7.6)', true, format('gestor_so_propor %s desde %s', c.gestor_so_propor, c.gestor_so_propor_em)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C6 a lista de itens do aprendizado aceita os 6 da margem (agenda_aprendizado_item_check)',
       (select count(*) from unnest(array['vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor']) x where pg_get_constraintdef(k.oid) like '%''' || x || '''%') = 6,
       left(pg_get_constraintdef(k.oid), 300)
  from pg_constraint k where k.conname = 'agenda_aprendizado_item_check';

-- ── F. As funções ─────────────────────────────────────────────────────────────────────────────────
-- (assinatura, security definer, volatilidade, quem executa além do dono, o tipo, o md5 do corpo sem CR: gerado por f7e/p8/gerar-sql.mjs, do replay com a 7f inteira, a 7e e o dado)
create temp table _pe_f (f text primary key, definer boolean not null, vol "char" not null, papeis text not null, tipo text not null, m text not null) on commit drop;
insert into _pe_f values
('_agenda_aplicar_planejar(uuid,uuid,jsonb,text,date)', true, 'v', 'service_role', 'recriada', 'fd08a82aab1fb97654c59601019f7b94'),
  ('_agenda_aprender_congelar_marcacao(date)', true, 'v', '', 'nova', '42bf1c30b8954bc4078d8ae2cae0d537'),
  ('_agenda_aprender_congelar(date)', true, 'v', '', 'recriada', 'afdf64b347efb383e793ab86d70d8b8c'),
  ('_agenda_aprender_folga_compra(date,timestamptz)', false, 'v', '', 'nova', '1f9422e15223e84c8697f38b0b527fcb'),
  ('_agenda_aprender_folga_semana(date,timestamptz)', true, 'v', '', 'nova', '93a3e3e8c2a8353dc77553341ab107c1'),
  ('_agenda_aprender_fornecedor(date,timestamptz)', false, 'v', '', 'recriada', '8ece3c97718901f743ac9f911b9858ba'),
  ('_agenda_aprender_medir_compras(date)', false, 'v', '', 'nova', '5d84202f1bfad078b1cf2b902c8b445c'),
  ('_agenda_aprender_prazo_sem_fornecedor(date,timestamptz)', false, 'v', '', 'nova', 'da8e11d0f8fe31c4292085efda5094e0'),
  ('_agenda_aprender_promessa(date,timestamptz)', true, 'v', '', 'nova', '6d45e2ba95a57badc4761d05029dae85'),
  ('_agenda_aprender_tempo_compra(date,timestamptz)', false, 'v', '', 'nova', 'f1f573c1f773852702b2ab09af63d621'),
  ('_agenda_aprender_vies(date,timestamptz)', true, 'v', '', 'nova', 'd8142e7ae71b404615d90d2958999026'),
  ('_agenda_aprendizado_gravar(text,text,text,numeric,integer,jsonb,numeric,jsonb,timestamptz)', true, 'v', '', 'recriada', 'd789d54bc702db6ceae891727c2e12e2'),
  ('_agenda_aprendizado_texto(text,text,jsonb)', false, 'i', 'authenticated service_role', 'recriada', '0ec75ea31c82bae3be7d792486203dd0'),
  ('_agenda_aprendizado_valor(text,numeric)', false, 'i', 'authenticated service_role', 'recriada', '3914f3cc8ebd6e60b36ae9f9599c8d6d'),
  ('_agenda_carga_da_semana(date,boolean)', false, 's', 'authenticated service_role', 'nova', 'e0f018c3fa63ab24684f4fcf34f41a91'),
  ('_agenda_contexto(date,date,date,uuid[],uuid[])', false, 's', 'service_role', 'recriada', 'f2a0ce283bae90e0ae2eddff8c6192ae'),
  ('_agenda_credibilidade(numeric,integer,numeric,integer)', false, 'i', 'authenticated service_role', 'nova', 'e845b614ad16272793b187c21281fe5c'),
  ('_agenda_desfazer_aprendizado(uuid,uuid,text,date,timestamptz)', true, 'v', '', 'recriada', '9f5dcb21ee6166dd45405fe1b23a7376'),
  ('_agenda_dias_com_vies(jsonb,numeric)', false, 's', 'authenticated service_role', 'nova', '583dbf7c10a906eab1a6efb1e06fd84b'),
  ('_agenda_gestor_compra_conta(uuid,date)', false, 's', '', 'recriada', 'd62bf9cb1a20c40bde2457b9d67e46a3'),
  ('_agenda_gestor_puxar(date,timestamptz)', true, 'v', '', 'nova', 'a045dbe267c80f6565ffcc83554874dd'),
  ('_agenda_margem_dono_e_pessoa(uuid)', false, 's', '', 'nova', '7bab068720600e4679a8254dce4b9a1b'),
  ('_agenda_margem_dp_bruto(uuid,jsonb)', false, 's', '', 'nova', '746ebf5d4bc6f8e120c8d916ca812b2b'),
  ('_agenda_margem_em_uso(text,text)', false, 's', 'authenticated service_role', 'nova', '1ed44961553cfef1549b1ded7b66c51d'),
  ('_agenda_margem_modo_cru(text)', false, 's', 'authenticated service_role', 'nova', 'ef31599027860662ea4a1490963685ea'),
  ('_agenda_margem_modo(text)', false, 's', 'authenticated service_role', 'nova', '0aa8397f4c80564a96f45ffc2ecd92a8'),
  ('_agenda_margem_tipo_os(uuid)', false, 's', '', 'nova', '2c911f9404952f8b9b5fa95e532f292a'),
  ('_agenda_material_critico(uuid)', false, 's', '', 'nova', '0d46605bc4e5ac75b082dc487fd282fb'),
  ('_agenda_medidas_compra_so_muda()', false, 'v', '', 'nova', '00ea139cdd72cb55a1a3c7a30bf3ed10'),
  ('_agenda_mudancas(date,date,boolean,boolean,timestamptz)', false, 's', 'authenticated service_role', 'recriada', 'f8b1db20dfe9348b66aecc3cc8d2d413'),
  ('_agenda_os_urgente(uuid,date)', false, 's', 'authenticated service_role', 'nova', '741a8ff20a7bb466fed93bb678dfcad2'),
  ('_agenda_prazo_do_fornecedor(uuid)', false, 's', 'authenticated service_role', 'recriada', '200f6f45b7049ca560c93d339666e93d'),
  ('_agenda_saude_margem(date,timestamptz)', true, 's', 'authenticated service_role', 'nova', 'cd8b8432bfa6251d531f1d3250bb3cd1'),
  ('_agenda_tempo_interno_compra(uuid)', false, 's', 'authenticated service_role', 'nova', 'ec504ef753a30795dbc169d430bb1868'),
  ('_agenda_temporada(date)', false, 's', 'authenticated service_role', 'nova', '6d199ecea2bd084cf5a1331c1dfe2d8d'),
  ('_agenda_validar_itens(jsonb,jsonb,date,timestamptz,boolean,jsonb)', false, 's', 'authenticated service_role', 'recriada', '70a9d91876d7df4de9b1cc6bfbb7f066'),
  ('_agenda_ver_aprendizado(date)', false, 's', 'authenticated service_role', 'recriada', 'ce30bcee5233ffb47007e62de9efc931'),
  ('_agenda_ver_fornecedores(date)', true, 's', 'authenticated service_role', 'recriada', 'c85a1c7f637f7322053560400ec3e6c9'),
  ('_agenda_ver_gestor(date)', false, 's', 'authenticated service_role', 'recriada', '03e37ff8e410d11eee2c398a2580418b'),
  ('_agenda_vies_da_os(uuid)', false, 's', 'authenticated service_role', 'nova', '93fd59e07e1a07921d46625d751a1016'),
  ('_agenda_vies_dono_da_os(uuid)', false, 's', 'authenticated service_role', 'nova', '8675702bd144bdbac0a13ca45d92ed26'),
  ('_agenda_z(numeric)', false, 'i', 'authenticated service_role', 'nova', '7dbc9e82fa95d48b51c6852958469f23'),
  ('agenda_aplicar(uuid,uuid[],text,uuid,uuid,date,timestamptz)', true, 'v', 'service_role', 'recriada', 'fd8da0c9591e257f7473457f7308871f'),
  ('agenda_aprender(date,timestamptz)', true, 'v', 'service_role', 'recriada', 'd663673837c3adda523130dffbc25cbd'),
  ('agenda_desfazer_dito(uuid,text,text,date,timestamptz)', true, 'v', 'authenticated service_role', 'recriada', 'f90e5d978ac75a1e05c56f2bb128042d'),
  ('agenda_medir_compra(uuid,date)', true, 'v', '', 'nova', '5a3d977ba281137a7ad263feb6dab92e'),
  ('agenda_medir_os(uuid,date)', true, 'v', '', 'recriada', '720f03c2185533e4adf414d36e6a44d8'),
  ('agenda_meios_da_os(uuid,date)', false, 's', 'authenticated service_role', 'recriada', '67edb2d07cc2ace11e12b60f4df39ea9'),
  ('agenda_promessa_da_os(uuid,date)', false, 's', 'authenticated service_role', 'nova', '201d616d27ffbcc750280748ccb71f75'),
  ('agenda_propor(text,date,date,uuid[],jsonb,boolean,text,uuid,date,timestamptz)', true, 'v', 'service_role', 'recriada', 'b22c2eab30b62c5ea912a742c13956ef'),
  ('agenda_saude(date,timestamptz)', false, 's', 'authenticated service_role', 'recriada', '989537a8ac0baae6ed4b46133be4aa1a'),
  ('os_duracao_sugerida(uuid)', false, 's', 'authenticated service_role', 'recriada', 'e557c1d9c5861bf61d25554c18ac6fad'),
  ('os_plano_da_os(uuid,date)', true, 's', 'authenticated service_role', 'recriada', 'b61e1cc95db65d7dcc5687a680a15f02'),
  ('os_prontidao(uuid,date)', false, 's', 'authenticated service_role', 'recriada', '08ddbe2ea14ae23c05d994fce513e2d3');
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
  from _pe_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select format('F2 %s: o corpo é o da 7e (md5)', r.f), p.oid is not null and md5(replace(p.prosrc, chr(13), '')) = r.m,
       case when p.oid is null then 'NÃO EXISTE' when md5(replace(p.prosrc, chr(13), '')) <> r.m then 'md5 ' || md5(replace(p.prosrc, chr(13), '')) || ' ≠ ' || r.m end
  from _pe_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);

-- ── Z. A saúde ────────────────────────────────────────────────────────────────────────────────────
create temp table _pe_z on commit drop as
select public.agenda_saude() as s, public.agenda_saude() -> 'margem' as mg;
insert into _resultado
select 'Z1 agenda_saude().margem: os zeros em 0 (o passo maior que o limite, fora dos limites, em uso com o interruptor fora, a carga fora, o puxar que cancelou, o puxar 2 vezes, a rodada do puxar atrasada, a medida de compra sem aprovação) e zeros_ok',
       coalesce((z.mg ->> 'zeros_ok')::boolean, false)
       and (select count(*) from unnest(array['passo_maior_que_o_limite', 'fora_dos_limites', 'em_uso_com_interruptor_fora', 'carga_semana_fora', 'puxar_cancelou', 'puxar_duas_vezes',
                                              'rodada_puxar_atrasada', 'medida_compra_sem_aprovacao']) k where z.mg ->> k = '0') = 8,
       left(coalesce(z.mg::text, 'sem a chave margem'), 900)
  from _pe_z z;
insert into _resultado
select 'Z2 agenda_saude().ok, com o dado no ar (na bancada, só mostra)', (select bancada or not dado from _pe) or coalesce((z.s ->> 'ok')::boolean, false), z.s ->> 'ok'
  from _pe_z z;

-- ── S. Sem erro, e a rodada das 16:00 ─────────────────────────────────────────────────────────────
insert into _resultado
select 'S1 nenhum erro da rodada do aprendizado nem do puxar nas últimas 24 h (aprender:% e gestor:puxar), e nenhum aberto', count(*) = 0,
       coalesce(string_agg(distinct e.action, ', '), 'nenhum')
  from public.app_error_logs e
 where e.context = 'agenda' and (e.action like 'aprender:%' or e.action = 'gestor:puxar')
   and (e.last_seen_at >= now() - interval '24 hours' or e.resolved_at is null);
insert into _resultado
select 'S2 a rodada do aprendizado com a margem (a 1ª depois do passo 1): sem erro, sem parar no relógio, e os 6 modos dela = os da linha (sem ela ainda, ou na bancada, só mostra)',
       case when (select bancada from _pe) or r.rodou_em is null then true
            else r.erros = 0 and not (r.contagens ? 'parou_no')
                 and r.contagens -> 'modos_margem' = (select jsonb_build_object('vies', c.modo_vies, 'folga_semana', c.modo_folga_semana, 'urgencia', c.modo_urgencia, 'promessa', c.modo_promessa,
                                                                                'tempo_compra', c.modo_tempo_compra, 'folga_compra', c.modo_folga_compra) from public.agenda_config c where c.id) end,
       coalesce(format('a última com a margem: %s, erros %s, %s ms, parou_no %s, modos %s', r.rodou_em, r.erros, r.duracao_ms, r.contagens ->> 'parou_no', r.contagens -> 'modos_margem'), 'ainda não rodou')
  from (select 1) u
  left join lateral (select x.rodou_em, x.erros, x.duracao_ms, x.contagens from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.contagens ? 'modos_margem'
                      order by x.rodou_em desc limit 1) r on true;

select teste, ok, detalhe from _resultado order by teste;

rollback;
