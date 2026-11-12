-- Conferência DEPOIS de publicar a Fase 7g da Agenda de Produção ("mostrar como pensou e provar o trabalho"): as 8 migrations de estrutura (20261112100000, 100100, 100200,
-- 100300, 100400, 100500, 100600, 100700) e o dado (20261112100990). Roteiro: fila-do-dono/fase77g-publicar.md. Spec: spec-fase7g.md §8.3 (agenda_fase7g_pos_deploy.sql), §11, R9.14;
-- notas-fase7g.md, seções P1 a P7, P5b e "Fechamento".
-- bancada: depende de 20261112100700
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); agenda_saude é STABLE; termina em ROLLBACK. Nenhuma tabela de mensagem é lida
-- (agenda_cliente_mensagens e agenda_cliente_respostas só pela FORMA, no catálogo: nenhuma linha).
-- As versões conferem-se POR NOME, nunca por max(version): a 7g (20261112100*) entra DEPOIS de 20261112200000, 20261112300000, 20261113100000 e das 20261116* a 20270105*, que já
-- estão no ar, e o aplicar.sh aplica fora de sequência de propósito.
-- Na bancada (scripts/bancada-agenda/rodar.mjs, que não aplica o dado 20261112100990) o dado não é exigido: os 4 ficam desligados, marcacoes_desde nula e veto_tipos sem ok_marcacao.
--
--   M  as 8 de estrutura registradas por nome; o dado registrado (na bancada, só mostra)
--   C  as colunas novas (22 em agenda_config, com 21 CHECKs; 2 em agenda_alocacoes, 2 em agenda_acoes, 3 em os_planejamento); os 4 modos: com o dado, em teste ou ligados pelo OK
--      nomeado, marcacoes_desde gravada e ok_marcacao em veto_tipos; sem ele, os 4 desligados, marcacoes_desde nula e veto_tipos sem ok_marcacao; o DEFAULT sombra dos 4; o freio
--      intacto (o que a 7g grava não mexe nele: gestor_so_propor_em é de antes do dado, ou mudou por uma ação gestor do dono depois dele)
--   T  as 3 tabelas novas (RLS ligada, anon não lê); as 5 listas fechadas com o que a 7g somou; a critica das perguntas com ok_marcacao
--   F  cada uma das 59 funções da 7g (22 recriadas e 37 novas): a assinatura, 1 por nome, security definer, volatilidade, search_path=public, as portas (anon e PUBLIC nunca) e o md5
--      do corpo (sem CR) da ponta final; e as 22 recriadas, tiradas as marcas da 7g, = o corpo de antes da 7g (o que estava no ar em 12/11, conferido por q0.sh). Os 34 UPDATE/DELETE
--      das 9 migrations têm WHERE (pg_safeupdate; varrido no texto por f7g/fech/sem-where.mjs, que pega o "delete from _agenda_cliente_alvo;" de antes da 20261112300000): o F2
--      prende o corpo varrido
--   Z  agenda_saude().explicar: os zeros em 0 e zeros_ok; agenda_saude().ok (na bancada, só mostra)
--   E  nenhum erro da rodada explicar nas últimas 24 h e nenhum aberto (agenda explicar:% e task-automations agenda:explicar); os outros erros da agenda nas últimas 24 h (só mostra:
--      o roteiro compara com o número do passo 0)
--   K  as tabelas do cliente intactas: nenhuma função da 7g escreve agenda_cliente_mensagens nem agenda_cliente_respostas nem muda cliente_resposta_validade; a forma das 2 tabelas
--      (colunas, CHECKs, gatilhos, policies) e cliente_resposta_validade iguais às de produção em 12/11 (na bancada, só mostra)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (sem o dado: C2 pede os de antes), depois do dado (passo 3), no dia seguinte depois das 16:35 e antes de cada "ligar":
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pg on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261112100990') as dado,
       coalesce(current_setting('agenda_teste.feriados', true), '') <> '' as bancada;

-- ── M. As migrations, por nome ────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v), exists (select 1 from supabase_migrations.schema_migrations m where m.version = v), null
  from unnest(array['20261112100000', '20261112100100', '20261112100200', '20261112100300', '20261112100400', '20261112100500', '20261112100600', '20261112100700']) v;
insert into _resultado
select 'M2 o dado 20261112100990 (os 4 em teste, marcacoes_desde, ok_marcacao em veto_tipos) registrado (na bancada, só mostra)',
       (select dado or bancada from _pg), case when (select dado from _pg) then 'registrado' else 'não registrado' end;

-- ── C. A configuração e as colunas ────────────────────────────────────────────────────────────────
insert into _resultado
select format('C1 as colunas novas de %s (%s)', t.tab, t.n),
       (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tab and c.column_name = any (t.cols)) = t.n,
       format('%s de %s; faltam: %s', (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tab and c.column_name = any (t.cols)), t.n,
              coalesce((select string_agg(x, ', ') from unnest(t.cols) x where not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tab and c.column_name = x)), '—'))
  from (values ('agenda_config', 22, array['modo_porque', 'modo_explicar', 'modo_placar', 'modo_rebaixar', 'porque_motivos_max', 'origens_do_dono', 'livre_semanas', 'como_pensei_perguntas',
                                           'como_pensei_itens_max', 'correcao_janela_du', 'rebaixar_janela_semanas', 'rebaixar_n_min', 'rebaixar_taxa', 'rebaixar_amostra', 'voltar_n',
                                           'rebaixar_trava_dias', 'explicar_hora', 'placar_janela', 'placar_semanas_hist', 'marcacoes_desde', 'placar_min_linhas', 'explicar_tempo_max']),
               ('agenda_alocacoes', 2, array['suposicoes', 'degrau']),
               ('agenda_acoes', 2, array['zona', 'degrau']),
               ('os_planejamento', 3, array['espera_ok_desde', 'ok_do_dono_em', 'ok_do_dono_via'])) t(tab, n, cols);
insert into _resultado
select 'C1b os CHECKs de agenda_config da 7g: 21 (marcacoes_desde é a única das 22 sem CHECK), e os 2 de os_planejamento (ok_do_dono_via e os_planejamento_ok_coerente)',
       (select count(*) from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.contype = 'c'
           and exists (select 1 from unnest(array['modo_porque', 'modo_explicar', 'modo_placar', 'modo_rebaixar', 'porque_motivos_max', 'origens_do_dono', 'livre_semanas', 'como_pensei_perguntas',
                                                   'como_pensei_itens_max', 'correcao_janela_du', 'rebaixar_janela_semanas', 'rebaixar_n_min', 'rebaixar_taxa', 'rebaixar_amostra', 'voltar_n',
                                                   'rebaixar_trava_dias', 'explicar_hora', 'placar_janela', 'placar_semanas_hist', 'placar_min_linhas', 'explicar_tempo_max']) x
                        where k.conname = 'agenda_config_' || x || '_check')) = 21
       and exists (select 1 from pg_constraint k where k.conrelid = 'public.os_planejamento'::regclass and k.conname = 'os_planejamento_ok_coerente')
       and exists (select 1 from pg_constraint k where k.conrelid = 'public.os_planejamento'::regclass and pg_get_constraintdef(k.oid) like '%ok_do_dono_via%prazo%'),
       format('%s CHECKs com o nome agenda_config_<coluna>_check', (select count(*) from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.contype = 'c'
           and k.conname = any (select 'agenda_config_' || x || '_check' from unnest(array['modo_porque', 'modo_explicar', 'modo_placar', 'modo_rebaixar', 'porque_motivos_max', 'origens_do_dono',
               'livre_semanas', 'como_pensei_perguntas', 'como_pensei_itens_max', 'correcao_janela_du', 'rebaixar_janela_semanas', 'rebaixar_n_min', 'rebaixar_taxa', 'rebaixar_amostra', 'voltar_n',
               'rebaixar_trava_dias', 'explicar_hora', 'placar_janela', 'placar_semanas_hist', 'placar_min_linhas', 'explicar_tempo_max']) x)));
insert into _resultado
select 'C2 os 4 modos: com o dado, em teste ou ligados pelo OK nomeado, marcacoes_desde gravada e ok_marcacao em veto_tipos; sem ele, desligados, marcacoes_desde nula e veto_tipos sem ok_marcacao',
       case when (select dado from _pg)
            then array[c.modo_porque, c.modo_explicar, c.modo_placar, c.modo_rebaixar] <@ array['sombra', 'ligado'] and c.marcacoes_desde is not null
                 and 'ok_marcacao' = any (c.veto_tipos)
            else array[c.modo_porque, c.modo_explicar, c.modo_placar, c.modo_rebaixar] <@ array['desligado'] and c.marcacoes_desde is null
                 and not ('ok_marcacao' = any (c.veto_tipos)) end,
       format('porque %s, explicar %s, placar %s, rebaixar %s; marcacoes_desde %s; veto_tipos %s', c.modo_porque, c.modo_explicar, c.modo_placar, c.modo_rebaixar,
              coalesce(c.marcacoes_desde::text, 'nula'), c.veto_tipos)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C3 o DEFAULT dos 4 modos é sombra (a linha nasce desligada; o dado a põe em teste)',
       count(*) = 4 and bool_and(i.column_default like '''sombra''%'), string_agg(i.column_name || ' ' || coalesce(i.column_default, 'nulo'), '; ')
  from information_schema.columns i
 where i.table_schema = 'public' and i.table_name = 'agenda_config' and i.column_name in ('modo_porque', 'modo_explicar', 'modo_placar', 'modo_rebaixar');
insert into _resultado
select 'C4 o freio intacto: o que a 7g grava (só o dado) não mexe em gestor_so_propor; ele é de antes do dado, ou mudou depois por uma ação gestor (a palavra do dono); sem o dado, só mostra',
       case when not (select dado from _pg) or c.marcacoes_desde is null then true
            else c.gestor_so_propor_em is null or c.gestor_so_propor_em <= c.marcacoes_desde
                 or exists (select 1 from public.agenda_acoes a where a.tipo = 'gestor' and a.criada_em >= c.marcacoes_desde) end,
       format('gestor_so_propor %s desde %s; o dado em %s', c.gestor_so_propor, coalesce(c.gestor_so_propor_em::text, 'nulo'), coalesce(c.marcacoes_desde::text, '—'))
  from public.agenda_config c where c.id;

-- ── T. As tabelas e as listas ─────────────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 a tabela %s existe, com RLS ligada, e anon não lê', t.tab),
       c.oid is not null and c.relrowsecurity and not has_table_privilege('anon', c.oid, 'select'), format('rls %s', c.relrowsecurity)
  from (values ('agenda_marcacoes'), ('agenda_tipos_os'), ('agenda_placar_semanas')) t(tab)
  left join pg_class c on c.oid = to_regclass('public.' || t.tab);
insert into _resultado
select format('T2 a lista %s aceita %s', x.nome, x.valor), coalesce(pg_get_constraintdef(k.oid) like '%''' || x.valor || '''%', false), left(coalesce(pg_get_constraintdef(k.oid), 'NÃO EXISTE'), 300)
  from (values ('agenda_alocacoes_motivo_check', 'ferramenta'), ('agenda_vigia_rodadas_rotina_check', 'explicar'), ('agenda_perguntas_tipo_check', 'ok_marcacao'),
               ('agenda_alocacoes_condicao_tipo_check', 'ok_do_dono'), ('agenda_acoes_tipo_check', 'nivel')) x(nome, valor)
  left join pg_constraint k on k.conname = x.nome;
insert into _resultado
select 'T3 a critica das perguntas (coluna gerada) conta ok_marcacao', coalesce(pg_get_expr(d.adbin, d.adrelid) like '%ok_marcacao%', false), left(coalesce(pg_get_expr(d.adbin, d.adrelid), 'sem expressão'), 300)
  from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica';

-- ── F. As funções ─────────────────────────────────────────────────────────────────────────────────
-- (assinatura, security definer, volatilidade, quem executa além do dono, o tipo, o md5 do corpo sem CR da ponta final e, nas recriadas, o md5 do corpo de antes da 7g: gerados por
-- f7g/fech/gerar-pos.mjs, do PGlite com a 7g inteira e do texto das migrations; o de antes conferido contra a produção de 12/11 por q0.sh, sql/wf7g_fech_md5_prod)
create temp table _pg_f (f text primary key, definer boolean not null, vol "char" not null, papeis text not null, tipo text not null, m text not null, m_antes text) on commit drop;
insert into _pg_f values
-- {{F}} (gerado por f7g/fech/gerar-pos.mjs)
('_agenda_acoes_porque()', true, 'v', '', 'nova', '796e81fca7e5b52c624a383b6f5497b9', null),
('_agenda_alocacoes_imutavel()', false, 'v', 'service_role', 'recriada', '906fa27edeb54f45ba9a2447b0b19e59', '112b4e2ed6640e4bb2a102d90f134b1b'),
('_agenda_alocacoes_porque()', false, 'v', '', 'nova', 'c6bf5d0a59443b0e6d71cb93e6f4250c', null),
('_agenda_classe_da_os(jsonb,jsonb,date,boolean,boolean)', false, 's', 'authenticated service_role', 'recriada', '9b4134d631d5b151a292599a7cf35f01', '06aa24fb0049f269d39787434c3aceeb'),
('_agenda_comunicar_quinta(date,timestamp with time zone)', false, 'v', '', 'recriada', 'd6462bacf16a5e5537bfe4f280e574f3', 'cc24667a155f6ec825485ec686cfb83c'),
('_agenda_condicao_da_reserva(uuid,text,date,jsonb,date)', false, 's', 'authenticated service_role', 'recriada', 'd7425af7f5088fd9326dc5025023aad5', '63b22e85a316102edad939f2e57ae53c'),
('_agenda_criterio_texto(text)', false, 'i', 'service_role', 'nova', '2554490278696c05f31914371a16efd1', null),
('_agenda_data_com_relacao(jsonb,text,text,date)', false, 's', 'service_role', 'nova', '2534d0228e580eb1bb4f9e97f5e003f8', null),
('_agenda_degrau_texto(text)', false, 'i', 'service_role', 'nova', 'ff2b931304025c935fc74d671df09b41', null),
('_agenda_degrau(jsonb,jsonb,date,date,date)', false, 'i', 'service_role', 'nova', 'e763c870b9dab1edc1fad6f194439a33', null),
('_agenda_desfazer_nivel(uuid,uuid,text,date,timestamp with time zone)', false, 'v', 'service_role', 'nova', 'c9f843bae110da6a5b3dfbe264e5ecb3', null),
('_agenda_duracao_fonte_texto(text,numeric,numeric,text)', false, 'i', 'service_role', 'nova', '271521715adaa4bd396ed46a6672d066', null),
('_agenda_encaixe_simulado(jsonb,date)', true, 's', 'authenticated service_role', 'nova', '6c852e5fb98a93699b90d72ce2703ddc', null),
('_agenda_entrada_simulada_da_os(uuid,date)', true, 's', 'authenticated service_role', 'nova', 'd879ffe7abe8fedddb56f5c67662805d', null),
('_agenda_espera_ok(uuid)', false, 's', 'authenticated service_role', 'nova', '849a6a8bfeb0a017a6e4960e8f2c1201', null),
('_agenda_explicar_marcacoes(date,timestamp with time zone)', false, 'v', 'service_role', 'nova', '89330fd272b4830631a06d56305849ad', null),
('_agenda_explicar_ok(date,timestamp with time zone)', false, 'v', 'service_role', 'nova', 'f7ad3c52b42c9eb58eda001b1bbc0645', null),
('_agenda_explicar_placar(date,timestamp with time zone)', false, 'v', 'service_role', 'nova', 'c21c51ebbbe91856fdaf12719c9434a3', null),
('_agenda_explicar_tipos(date,timestamp with time zone)', false, 'v', 'service_role', 'nova', '30dc031a8bbdc20a5cadc0d7f9972e34', null),
('_agenda_lote_texto(jsonb)', false, 'i', '', 'recriada', '081fb17703908d5ea0918e03f6c4ffcc', 'd36af4a7c0177eeaf8f8cb07f1a37960'),
('_agenda_marcacao_desfecho(uuid,uuid,date)', false, 's', 'service_role', 'nova', 'e6dea29c53de1e1cf53afa446e9708b4', null),
('_agenda_marcacoes_so_muda()', false, 'v', '', 'nova', '9cca9eebb3ef148a10c496bf5c4777cd', null),
('_agenda_mensagens_da_agenda(date,date)', false, 's', 'service_role', 'nova', '8d6c37385b10beca238b5ae9f9bc11f1', null),
('_agenda_modo_da_pergunta(text,text)', false, 's', 'service_role', 'recriada', '812a2d19055a377bca46f330dcc20e58', '40a78627108f025a6caaa035df768927'),
('_agenda_motivo_dito(text)', false, 'i', 'authenticated service_role', 'recriada', '5bcf9742d732150215ddcf5a5e7746ff', 'c6d11975b998f80ed20e44221dba4c8f'),
('_agenda_motivo_texto(text)', false, 'i', 'authenticated service_role', 'recriada', '8ebb77538bc521688b41101e36565f42', 'e83650d34e2c15dd698e4c2656b13209'),
('_agenda_ok_decidir(uuid,smallint,uuid,text,text,date,timestamp with time zone)', false, 'v', 'service_role', 'nova', '829222d0fa60d59b7be086a48ed5921b', null),
('_agenda_padrao_da_pergunta(text,boolean,uuid,jsonb,smallint,uuid[])', false, 's', '', 'recriada', '2272cbcfc068b02849da69aec9e6edb6', '4c2024d1cb4ed7f252e09adaa7351615'),
('_agenda_placar_numeros(date,date,date)', false, 's', 'service_role', 'nova', '2ef8581df0b259c77cfd29f0a9e81155', null),
('_agenda_placar_periodo(date,date)', false, 's', 'service_role', 'nova', '99d8ed984c08cfa39b174eaf5146233f', null),
('_agenda_placar_so_muda()', false, 'v', '', 'nova', '3f707a32d75df1d5b714e0afa3f25361', null),
('_agenda_placar_texto(jsonb,date,date,text,integer)', false, 'i', 'service_role', 'nova', 'f43ff3cfc367d5d0b2393ee52d23d6b0', null),
('_agenda_porque_da_os(uuid,date,timestamp with time zone)', true, 's', 'authenticated service_role', 'nova', 'b25261435b91ff328b9fa85ad58b73e5', null),
('_agenda_porque_fonte(uuid,date)', false, 's', 'service_role', 'nova', 'ef34dd64432aebd01eb8fa3dfe56c453', null),
('_agenda_porque_linha(uuid,jsonb,date)', false, 's', 'service_role', 'nova', 'ff8aa8f39868e80d2a299bdcc5e45e44', null),
('_agenda_quem_marcou(text,text)', false, 's', 'service_role', 'nova', '97f87d185bd670cc676a456551899f4d', null),
('_agenda_relacao_dita(text,text)', false, 'i', 'service_role', 'nova', '3b1281cf4be3ccb73a92bfe8eda7aaf0', null),
('_agenda_saude_explicar(date,timestamp with time zone)', true, 's', 'authenticated service_role', 'nova', '9556c3af8d6a7eeb4dd26714bb682cf0', null),
('_agenda_suposicao_texto(text,jsonb)', false, 'i', 'service_role', 'nova', '98c21a21209eb7160ab9401233a0afa4', null),
('_agenda_suposicoes_da_os(uuid,jsonb,jsonb,date)', false, 's', 'service_role', 'nova', '9bacf3a440f6bbc0effa33ff40cc8c1b', null),
('_agenda_suposicoes_validas(jsonb)', false, 'i', 'service_role', 'nova', 'd5008e77547ed837279047be9886bee7', null),
('_agenda_tipos_os_so_muda()', false, 'v', '', 'nova', 'dc3669dfe0c57d1e3fd39017a00cc918', null),
('_agenda_zona_mais_severa(text[])', false, 'i', 'service_role', 'nova', '202cfe362d3a4c606222029140184e39', null),
('agenda_como_pensei(date,date,timestamp with time zone)', true, 's', 'authenticated service_role', 'nova', '38f7c5e8285a2fdbf881feacebf10048', null),
('agenda_conferir_dia(uuid,text,text,text,text,date,timestamp with time zone)', true, 'v', 'authenticated service_role', 'recriada', 'af2dec4694ebd16b5e5e676f683dd434', '0b47265e5022191567afc729ec956e3f'),
('agenda_ctp(uuid,date)', false, 's', 'authenticated service_role', 'recriada', '4017e20481027122c5a84e84437c8295', 'd7760665552fa30a76b34c30f3ecf605'),
('agenda_decidir(uuid,smallint,uuid,text,text,date,timestamp with time zone)', true, 'v', 'service_role', 'recriada', 'd37364b37b95e2733daf956328afee81', '108125fc0e603c9f9077d019f6767809'),
('agenda_desfazer_dito(uuid,text,text,date,timestamp with time zone)', true, 'v', 'authenticated service_role', 'recriada', '8525354458f6b39f682457bab7f02ff2', 'f90e5d978ac75a1e05c56f2bb128042d'),
('agenda_desfazer(uuid,uuid,text,date,timestamp with time zone)', true, 'v', 'service_role', 'recriada', '0ed024c32d0a85231956c7c659a4a8cd', '7a138b9382d5fc4289de0b770a70fa55'),
('agenda_encaixe_do_novo(numeric,jsonb,text,date)', true, 's', 'authenticated service_role', 'recriada', '11b70fa5103546871a3d43830f40561e', 'e9333e07be2808185c3351698e50930c'),
('agenda_explicar_rodar(date,timestamp with time zone)', true, 'v', 'service_role', 'nova', 'd14614e07446027c5431bebeb516c7dc', null),
('agenda_livre_de_verdade(date,timestamp with time zone)', true, 's', 'authenticated service_role', 'recriada', '460d3586af0a90caa56f4cd4d27e6891', '79b284f05d99aadb3099649138e7d520'),
('agenda_placar(date,date,timestamp with time zone)', true, 's', 'authenticated service_role', 'nova', 'e3ea41f86a93fbcba4dd8cbd3553cb4f', null),
('agenda_propor(text,date,date,uuid[],jsonb,boolean,text,uuid,date,timestamp with time zone)', true, 'v', 'service_role', 'recriada', '14b33120e6c711617bf26098eeb71758', 'b22c2eab30b62c5ea912a742c13956ef'),
('agenda_rascunho_marcar(uuid,text,text,text,text,text,text,date,timestamp with time zone)', true, 'v', 'authenticated service_role', 'recriada', '74e30b13b04edd5ce9169b1ac236b981', 'd73ebf1c9f55537b5ad20887bb144d39'),
('agenda_saude(date,timestamp with time zone)', false, 's', 'authenticated service_role', 'recriada', 'cd5841fef06b30a0e0802c9aabc232eb', '989537a8ac0baae6ed4b46133be4aa1a'),
('agenda_tela_semana(date,date,timestamp with time zone)', true, 's', 'authenticated service_role', 'recriada', '86867202cfc683c7d6ebf60104c8754f', '469bd10a3cf5e57784a0dbb1e086dce3'),
('agenda_ver(uuid,text,text,text,text,jsonb,boolean,date)', false, 's', 'authenticated service_role', 'recriada', 'c3f95c4ff09210a0ca221d910513e9f3', 'ca961e991cf9ad83388b758c0b429dbf'),
('os_plano_da_os(uuid,date)', true, 's', 'authenticated service_role', 'recriada', 'c6c049d16b6cdbe81048b175d5ed419a', 'b61e1cc95db65d7dcc5687a680a15f02')
-- {{F}} fim
;
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
  from _pg_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select format('F2 %s: o corpo é o da ponta final da 7g (md5 sem CR)', r.f), p.oid is not null and md5(replace(p.prosrc, chr(13), '')) = r.m,
       case when p.oid is null then 'NÃO EXISTE' when md5(replace(p.prosrc, chr(13), '')) <> r.m then 'md5 ' || md5(replace(p.prosrc, chr(13), '')) || ' ≠ ' || r.m end
  from _pg_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
-- as recriadas, tiradas as marcas da 7g ("-- FASE 7g: …" até "-- FASE 7g: fim"; "-- (7g …" até "-- (7g: fim)"), linha a linha: o corpo de antes da 7g, byte a byte (a 7g só acrescenta).
-- A regra é a do pg_temp.sem_7g do F2 de agenda_fase7e_pos_deploy.sql.
create function pg_temp.sem_7g(p text) returns text language plpgsql immutable as $f$
declare
  l      text;
  fora   text[] := '{}';
  dentro boolean := false;
begin
  foreach l in array string_to_array(p, E'\n') loop
    if not dentro and l ~ '^\s*-- (FASE 7g:|\(7g )' and l !~ '^\s*-- (FASE 7g: fim|\(7g: fim\))' then dentro := true; continue; end if;
    if dentro then
      if l ~ '^\s*-- (FASE 7g: fim|\(7g: fim\))' then dentro := false; end if;
      continue;
    end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;
insert into _resultado
select format('F3 %s (recriada): sem as marcas da 7g, o corpo de antes dela (md5)', r.f), p.oid is not null and md5(pg_temp.sem_7g(replace(p.prosrc, chr(13), ''))) = r.m_antes,
       case when p.oid is null then 'NÃO EXISTE' when md5(pg_temp.sem_7g(replace(p.prosrc, chr(13), ''))) <> r.m_antes
            then 'md5 ' || md5(pg_temp.sem_7g(replace(p.prosrc, chr(13), ''))) || ' ≠ ' || r.m_antes end
  from _pg_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where r.tipo = 'recriada';
-- ── Z. A saúde ────────────────────────────────────────────────────────────────────────────────────
create temp table _pg_z on commit drop as
select public.agenda_saude() as s, public.agenda_saude() -> 'explicar' as ex;
insert into _resultado
select 'Z1 agenda_saude().explicar: os zeros em 0 (placar_atrasado, marcacao_aberta_vencida, rebaixar_sem_veto, rodada_atrasada, erros_dia, ok_sem_pergunta, nivel_sem_aviso) e zeros_ok',
       coalesce((z.ex ->> 'zeros_ok')::boolean, false)
       and (select count(*) from unnest(array['placar_atrasado', 'marcacao_aberta_vencida', 'rebaixar_sem_veto', 'rodada_atrasada', 'erros_dia', 'ok_sem_pergunta', 'nivel_sem_aviso']) k
             where z.ex ->> k = '0') = 7,
       left(coalesce(z.ex::text, 'sem a chave explicar'), 900)
  from _pg_z z;
insert into _resultado
select 'Z2 agenda_saude().ok (na bancada, só mostra)', (select bancada from _pg) or coalesce((z.s ->> 'ok')::boolean, false), z.s ->> 'ok'
  from _pg_z z;

-- ── E. Sem erro ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'E1 nenhum erro da rodada explicar nas últimas 24 h (agenda explicar:% e task-automations agenda:explicar), e nenhum aberto', count(*) = 0,
       coalesce(string_agg(distinct e.context || ' ' || e.action, ', '), 'nenhum')
  from public.app_error_logs e
 where ((e.context = 'agenda' and e.action like 'explicar:%') or (e.context = 'task-automations' and e.action = 'agenda:explicar'))
   and (e.last_seen_at >= now() - interval '24 hours' or e.resolved_at is null);
insert into _resultado
select 'E2 os outros erros da agenda e das edges que a 7g publica nas últimas 24 h (só mostra: compare com o número do passo 0 do roteiro)', true,
       format('%s: %s', count(*), coalesce(string_agg(distinct e.context || ' ' || e.action, ', '), 'nenhum'))
  from public.app_error_logs e
 where e.context in ('agenda', 'task-automations', 'ai-agent', 'erp-mcp', 'whatsapp-webhook')
   and not ((e.context = 'agenda' and e.action like 'explicar:%') or (e.context = 'task-automations' and e.action = 'agenda:explicar'))
   and e.last_seen_at >= now() - interval '24 hours';

-- ── K. As tabelas do cliente intactas ─────────────────────────────────────────────────────────────
insert into _resultado
select 'K1 nenhuma função da 7g escreve agenda_cliente_mensagens nem agenda_cliente_respostas, nem muda cliente_resposta_validade', count(*) = 0,
       coalesce(string_agg(r.f, ', '), 'nenhuma')
  from _pg_f r
  join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?agenda_cliente_(mensagens|respostas)\M'
    or p.prosrc ~* 'cliente_resposta_validade\s*=';
create temp table _pg_k on commit drop as
select t.tab,
       md5(coalesce((select string_agg(format('%s %s %s %s', a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull, coalesce(pg_get_expr(d.adbin, d.adrelid), '-')), '|' order by a.attname)
              from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = to_regclass('public.' || t.tab) and a.attnum > 0 and not a.attisdropped), '')) as colunas,
       md5(coalesce((select string_agg(k.conname || ' ' || pg_get_constraintdef(k.oid), '|' order by k.conname) from pg_constraint k where k.conrelid = to_regclass('public.' || t.tab)), '')) as checks,
       md5(coalesce((select string_agg(g.tgname || ' ' || pg_get_triggerdef(g.oid), '|' order by g.tgname) from pg_trigger g where g.tgrelid = to_regclass('public.' || t.tab) and not g.tgisinternal), '')) as gatilhos,
       md5(coalesce((select string_agg(p.polname || ' ' || coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''), '|' order by p.polname)
                       from pg_policy p where p.polrelid = to_regclass('public.' || t.tab)), '')) as policies,
       t.colunas as e_colunas, t.checks as e_checks, t.gatilhos as e_gatilhos, t.policies as e_policies
  from (values ('agenda_cliente_mensagens', '93e069f69e707b466377855406ad11a8', '2878a833f3811cf95ff3c15c99002e97', 'd01286a49b2d49db894135bc3291434d', '7bd7ae5b91314965a595494daa0427ea'),
               ('agenda_cliente_respostas', 'aa1dfff41cd8bc081a59b2d23988fe4b', 'aaaa8fe5d0bed141b2c3b8502a4985bb', 'cbb074879757692f15b9446d9ab26dc8', 'd0cdbf6f7816c99a7d713ca2668df9d7'))
       t(tab, colunas, checks, gatilhos, policies);
insert into _resultado
select format('K2 a forma de %s (colunas, CHECKs, gatilhos, policies) = a de produção em 12/11, antes da 7g (na bancada, só mostra)', k.tab),
       (select bancada from _pg) or (k.colunas = k.e_colunas and k.checks = k.e_checks and k.gatilhos = k.e_gatilhos and k.policies = k.e_policies),
       format('colunas %s, checks %s, gatilhos %s, policies %s', k.colunas = k.e_colunas, k.checks = k.e_checks, k.gatilhos = k.e_gatilhos, k.policies = k.e_policies)
  from _pg_k k;
insert into _resultado
select 'K3 cliente_resposta_validade = 72 h e o DEFAULT 72 h, como em produção em 12/11 (o que a 7g não toca)',
       c.cliente_resposta_validade = interval '72 hours' and coalesce(i.column_default, '') like '''72:00:00''%',
       format('%s (DEFAULT %s)', c.cliente_resposta_validade, i.column_default)
  from public.agenda_config c
 cross join information_schema.columns i
 where c.id and i.table_schema = 'public' and i.table_name = 'agenda_config' and i.column_name = 'cliente_resposta_validade';

select teste, ok, detalhe from _resultado order by teste;

rollback;
