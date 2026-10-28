-- Conferência DEPOIS de ligar a Agenda de Produção, Fase 5 (pacote P6; correções C1 e C2): migrations 20261028100000..100800, as edge
-- functions, o front do cartão "Plano" e (passo 3) a migration de dado 20261028101000 — modo_cliente em sombra —
-- fila-do-dono/fase5-oks.md, passos 1–3 (e de novo a cada onda, passos 4–7).
-- bancada: depende de 20261028100800
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só na tabela TEMPORÁRIA do resultado); agenda_saude, agenda_ver
-- e os_plano_da_os são STABLE e não gravam; termina em ROLLBACK. Na bancada (que não aplica a 20261028101000: lá o modo fica
-- como a linha está, desligado) ele passa do mesmo jeito.
--
--   M  as 9 versões de estrutura da Fase 5 (a 100700 e a 100800 são as correções C1 e C2) registradas em supabase_migrations.schema_migrations; a de dado (101000, a
--      sombra) é mostrada
--   C  agenda_config: as 26 colunas novas existem (cliente_pedido_max_du é da correção C1); modo_cliente: com a 101000 registrada, sombra (ou ligado, depois dos OKs
--      das ondas); sem ela, desligado; a sombra só com a agenda automática e a vigia ligadas (pré-requisito da §10); em
--      ligado, a lista das ondas não está vazia; a R15 (onda 2) é mostrada; (correção C2, regressão B4) ligado só depois de 14
--      dias de sombra (uma rodada do cliente em sombra há 14 dias ou mais — o roteiro da §10), provado na bancada
--      (C2b0); o motivo novo "entrega" na lista fechada da recusa (C5)
--   T  as 9 colunas novas de os_planejamento e as 2 tabelas novas: RLS ligada, policies só de leitura e TO authenticated,
--      anon sem nada, authenticated só lê
--   G  os gatilhos ligados: os 3 da fila do WhatsApp (as 2 travas e o envio) e os 4 das 2 tabelas (não apagam; só mudam no
--      que podem), e o do "não saiu" (correção C1: a mensagem aprovada pelo dono e recusada depois abre a pergunta)
--   F  as 89 funções da Fase 5 (novas e recriadas, P1–P6 e as correções C1 e C2) existem com as portas certas — nunca anon; as de tela para
--      authenticated e service_role; as do motor, do worker e do webhook só service_role; as internas para ninguém —, o
--      security definer de cada uma, nenhuma agenda_*/_agenda_*/os_* executável por anon, a agenda_ver com os 18 focos
--      (clientes) e o cartão com a chave cliente; (correção C2, B3) o índice da conversa e o d10 que o usa (F9)
--   N  em sombra nada sai: sem rodada do cliente em ligado, nada na fila agenda-cliente e nenhuma mensagem em ligado (só a
--      sombra registrada); toda linha agenda-cliente da fila tem a mensagem em ligado
--   S  agenda_saude().cliente: os 11 zeros obrigatórios; o modo que a saúde mostra é o da linha; a rodada do cliente nas
--      últimas 2 h (fora de desligado); nenhum erro cliente:% em 24 h nem aberto em app_error_logs
--   L  as leituras: o foco clientes devolve texto dentro de texto_max e o mesmo texto duas vezes (md5); o cartão de uma OS da
--      carteira traz a chave cliente com o modo da linha
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (estrutura), de novo DEPOIS do passo 3 (a migration de dado) e depois de cada onda de
--   fila-do-dono/fase5-oks.md, com o OK do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_pos_deploy.sql
--   S5 só fica verde depois do 1º tique de 15 min do task-automations com a sombra ligada.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd_sombra on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261028101000') as aplicada;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261028100000', '20261028100100', '20261028100200', '20261028100300', '20261028100400',
                    '20261028100500', '20261028100600', '20261028100700', '20261028100800']) v;

insert into _resultado
select 'M2 a migration de dado 20261028101000 (modo_cliente em sombra) — só mostra', true,
       case when (select aplicada from _pd_sombra) then 'registrada (passo 3 feito)' else 'não registrada (antes do passo 3)' end;

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('C1 agenda_config.%s existe (o DEFAULT é o único lugar do número)', c),
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = 'agenda_config' and k.column_name = c),
       null
  from unnest(array['modo_cliente', 'cliente_tipos_ligados', 'cliente_janela_inicio', 'cliente_janela_fim', 'cliente_sabado_fim',
                    'cliente_dia_max', 'cliente_semana_max', 'cliente_total_dia_max', 'cliente_intervalo_min_s',
                    'cliente_intervalo_max_s', 'cliente_aprovacao_dias', 'cliente_hora_toque', 'cliente_hora_preparo',
                    'cliente_confirmar_du', 'cliente_resposta_validade', 'cliente_sem_resposta_horas', 'cliente_atraso_na_hora_du',
                    'cliente_acesso_validade_dias', 'cliente_andamento_min_du', 'cliente_andamento_intervalo_dias',
                    'cliente_pronto_lembrete_dias', 'cliente_pos_dias', 'cliente_conversa_dias', 'cliente_conversa_viva_min',
                    'cliente_mesmo_tipo_horas', 'cliente_pedido_max_du']) c;

insert into _resultado
select 'C2 modo_cliente: com a 101000 registrada, sombra (ou ligado com o OK das ondas); sem ela, desligado',
       coalesce(bool_and(case when (select aplicada from _pd_sombra) then c.modo_cliente in ('sombra', 'ligado')
                              else c.modo_cliente = 'desligado' end), false),
       string_agg(format('cliente %s, ondas %s', c.modo_cliente, c.cliente_tipos_ligados), '; ')
  from public.agenda_config c;

-- (correção C2, regressão B4) ligado só depois das 2 semanas de sombra do roteiro (§10): uma rodada do cliente em sombra há
-- 14 dias ou mais. Depois da 101000 as Fases 1 a 3 não olham mais o modo do cliente (só este C2): sem isto, ligado no dia
-- seguinte passaria. Se o dono encurtar a sombra de propósito, esta linha acusa e o OK dele fica anotado no roteiro.
create function pg_temp.ligado_cedo() returns table (cedo boolean, detalhe text) language sql stable as $f$
  select c.modo_cliente = 'ligado'
         and not exists (select 1 from public.agenda_vigia_rodadas r
                          where r.rotina = 'cliente' and r.contagens ->> 'modo_cliente' = 'sombra'
                            and r.rodou_em <= now() - interval '14 days'),
         format('cliente %s; 1ª rodada em sombra: %s', c.modo_cliente,
                coalesce((select to_char(min(r.rodou_em) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
                            from public.agenda_vigia_rodadas r
                           where r.rotina = 'cliente' and r.contagens ->> 'modo_cliente' = 'sombra'), 'nenhuma'))
    from public.agenda_config c
$f$;

insert into _resultado
select 'C2b (correção C2, B4) ligado só depois de 14 dias de sombra (uma rodada do cliente em sombra há 14 dias ou mais)',
       not coalesce(bool_or(x.cedo), false), string_agg(x.detalhe, '; ')
  from pg_temp.ligado_cedo() x;

-- só na bancada (a fixture-fase5 existe): ligado sem a sombra acusa; com uma rodada em sombra de 15 dias atrás, não. Em
-- produção não grava nada: a linha diz PULADO.
do $c2b$
declare
  v1 boolean;
  v2 boolean;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('C2b0 a regra do ligado cedo, na bancada', true, 'PULADO: só na bancada');
    return;
  end if;
  begin
    update public.agenda_config set modo_cliente = 'ligado', cliente_tipos_ligados = array['pode_atrasar'] where id;
    select x.cedo into v1 from pg_temp.ligado_cedo() x;
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                             rotina, modo_equipe, modo_diaria)
    select now() - interval '15 days', (now() - interval '15 days')::date, now() - interval '15 days', c.modo_proposta, c.modo_vigia,
           jsonb_build_object('modo_cliente', 'sombra'), 0, 1, 'cliente', c.modo_equipe, c.modo_diaria
      from public.agenda_config c;
    select x.cedo into v2 from pg_temp.ligado_cedo() x;
    insert into _resultado values ('C2b0 a regra do ligado cedo, na bancada: ligado sem sombra acusa; com a sombra de 15 dias, não',
                                   v1 and not v2, format('sem sombra %s; com sombra %s', v1, v2));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
end
$c2b$;

insert into _resultado
select 'C5 (correção C2) a recusa da mensagem ao cliente tem o motivo "entrega" (o provedor não entregou) na lista fechada',
       coalesce(bool_and(pg_get_constraintdef(k.oid) like '%entrega%'), false), null
  from pg_constraint k
 where k.conrelid = 'public.agenda_cliente_mensagens'::regclass and k.conname = 'agenda_cliente_mensagens_recusa_motivo_check';

insert into _resultado
select 'C3 a mensagem ao cliente fora de desligado só com a agenda automática e a vigia ligadas (pré-requisito da §10)',
       coalesce(bool_and(c.modo_cliente = 'desligado' or (c.modo_proposta = 'ligado' and c.modo_vigia = 'ligado')), false),
       string_agg(format('cliente %s; proposta %s, vigia %s, leitura %s', c.modo_cliente, c.modo_proposta, c.modo_vigia,
                         c.modo_leitura), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C4 em ligado, ao menos uma onda na lista (ligado sem tipo = tudo em teste: confira se era isso); a R15 só sai com confirmar (onda 2) — só mostra a R15',
       coalesce(bool_and(c.modo_cliente <> 'ligado' or cardinality(c.cliente_tipos_ligados) > 0), false),
       string_agg(format('ondas %s; R15 %s', c.cliente_tipos_ligados,
                         case when c.modo_cliente = 'ligado' and 'confirmar' = any (c.cliente_tipos_ligados)
                              then 'desligada pela agenda (onda 2)' else 'como hoje' end), '; ')
  from public.agenda_config c;

-- ── T. As colunas e as tabelas ──────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 os_planejamento.%s existe', c),
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = 'os_planejamento' and k.column_name = c),
       null
  from unnest(array['prometido_tipo', 'prometido_de', 'prometido_ate', 'prometido_original_ate', 'prometido_em',
                    'prometido_fonte', 'prometido_mensagem_id', 'servico_cliente', 'acesso_ok_em']) c;

insert into _resultado
select format('T2 %s existe, com RLS ligada', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['agenda_cliente_mensagens', 'agenda_cliente_respostas']) t;

insert into _resultado
select format('T3 %s: policies só de leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['agenda_cliente_mensagens', 'agenda_cliente_respostas']) t
  left join pg_policies p on p.schemaname = 'public' and p.tablename = t
 group by t;

insert into _resultado
select format('T4 %s: anon sem nada; authenticated só lê', t),
       to_regclass('public.' || t) is not null
       and not (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
                or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete'))
       and has_table_privilege('authenticated', 'public.' || t, 'select')
       and not (has_table_privilege('authenticated', 'public.' || t, 'insert')
                or has_table_privilege('authenticated', 'public.' || t, 'update')
                or has_table_privilege('authenticated', 'public.' || t, 'delete')),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['agenda_cliente_mensagens', 'agenda_cliente_respostas']) t;

-- ── G. Os gatilhos ──────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('G1 gatilho %s em %s ligado', g.nome, g.tabela),
       exists (select 1 from pg_trigger tg
                where tg.tgrelid = to_regclass('public.' || g.tabela) and tg.tgname = g.nome and not tg.tgisinternal
                  and tg.tgenabled = 'O'),
       null
  from (values ('whatsapp_send_queue', 'trg_agenda_fila_do_cliente'), ('whatsapp_send_queue', 'trg_agenda_fila_do_cliente_linha'),
               ('whatsapp_send_queue', 'trg_agenda_cliente_enviada'),
               ('agenda_cliente_mensagens', 'agenda_cliente_mensagens_nao_apaga'),
               ('agenda_cliente_mensagens', 'agenda_cliente_mensagens_so_muda'),
               ('agenda_cliente_respostas', 'agenda_cliente_respostas_nao_apaga'),
               ('agenda_cliente_respostas', 'agenda_cliente_respostas_so_muda'),
               -- correção C1: o aviso de "não saiu" da mensagem aprovada pelo dono e recusada depois
               ('agenda_cliente_mensagens', 'trg_agenda_cliente_recusada')) g(tabela, nome);

insert into _resultado
select 'G2 as travas da fila do cliente só olham agenda-cliente; o gatilho do envio, agenda-cliente e agenda-confirmacao',
       coalesce(bool_and(case tg.tgname when 'trg_agenda_cliente_enviada'
                                        then pg_get_triggerdef(tg.oid) like '%agenda-cliente%' and pg_get_triggerdef(tg.oid) like '%agenda-confirmacao%'
                                        else pg_get_triggerdef(tg.oid) like '%agenda-cliente%'
                                             and pg_get_triggerdef(tg.oid) not like '%agenda-confirmacao%' end), false)
       and count(*) = 3,
       string_agg(tg.tgname, ', ')
  from pg_trigger tg
 where tg.tgrelid = to_regclass('public.whatsapp_send_queue') and not tg.tgisinternal
   and tg.tgname in ('trg_agenda_fila_do_cliente', 'trg_agenda_fila_do_cliente_linha', 'trg_agenda_cliente_enviada');

-- ── F. As funções ───────────────────────────────────────────────────────────────────────────────────────
-- As 89 funções que as migrations da Fase 5 (e as correções C1 e C2) criam ou recriam, com a porta de cada uma (tela = authenticated e
-- service_role; servico = só service_role; interna = ninguém, nem service_role: só outra função a chama por dentro;
-- gatilho = só o gatilho) e se é security definer. Nunca anon.
create temp table _pd_funcoes (f text primary key, quem text not null, definer boolean not null) on commit drop;
insert into _pd_funcoes values
('_agenda_aplicar_planejar(uuid,uuid,jsonb,text,date)', 'servico', true),
('_agenda_cliente_a_mensagem(text,text,date)', 'tela', false),
('_agenda_cliente_acorde(uuid,text,text,date,date,uuid)', 'interna', false),
('_agenda_cliente_andamento(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_anotar_acesso(uuid,uuid,text,date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_atraso(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_avisar_recusa()', 'gatilho', true),
('_agenda_cliente_cancelar(uuid,text,text)', 'interna', false),
('_agenda_cliente_confirmar(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_confirmar_dia(uuid,uuid,text,date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_contexto(uuid,date)', 'tela', false),
('_agenda_cliente_conversou(uuid,timestamp with time zone)', 'interna', false),
('_agenda_cliente_da_os(uuid,date)', 'interna', false),
('_agenda_cliente_data_da_resposta(text,date,date)', 'interna', false),
('_agenda_cliente_decidir(uuid,smallint,uuid,text,text,timestamp with time zone)', 'interna', true),
('_agenda_cliente_dia(date)', 'tela', false),
('_agenda_cliente_dia_a_confirmar(uuid,timestamp with time zone)', 'interna', false),
('_agenda_cliente_dia_de_janela(date)', 'tela', false),
('_agenda_cliente_dia_relativo(date,date)', 'tela', false),
('_agenda_cliente_dia_seguinte(date)', 'tela', false),
('_agenda_cliente_efeito_texto(text)', 'tela', false),
('_agenda_cliente_enfileirar(uuid,timestamp with time zone)', 'interna', true),
('_agenda_cliente_enviada()', 'gatilho', true),
('_agenda_cliente_faixa(date,date,boolean)', 'tela', false),
('_agenda_cliente_fechamento(date)', 'tela', false),
('_agenda_cliente_fila(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_fim_da_janela(date,integer)', 'tela', false),
('_agenda_cliente_fora_da_janela(timestamp with time zone,timestamp with time zone)', 'tela', false),
('_agenda_cliente_gravar_prometido(uuid,text,date,date,text,uuid,timestamp with time zone,text)', 'interna', true),
('_agenda_cliente_ja_registra(date,date,timestamp with time zone)', 'tela', false),
('_agenda_cliente_janela(uuid,date)', 'tela', false),
('_agenda_cliente_material(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_mensagens_so_muda()', 'gatilho', false),
('_agenda_cliente_motivo_texto(text)', 'interna', true),
('_agenda_cliente_mudanca_no_dia(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_no_periodo(uuid,date,date,uuid)', 'interna', false),
('_agenda_cliente_o_que(text,date)', 'tela', false),
('_agenda_cliente_outra_conversa(uuid[],text,timestamp with time zone,timestamp with time zone)', 'interna', true),
('_agenda_cliente_ouviu(uuid,date,timestamp with time zone)', 'tela', false),
('_agenda_cliente_erro_da_os(text,uuid,text,text,date)', 'interna', false),
('_agenda_cliente_sem_artigo(text,uuid)', 'interna', false),
('_agenda_cliente_tirar_prometido(uuid,uuid,timestamp with time zone,text)', 'interna', true),
('_agenda_cliente_pedido_de_dia(uuid,uuid,daterange,date,text,text,date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_perguntar(text,text,uuid,date,date,text,text,timestamp with time zone,timestamp with time zone)', 'interna', false),
('_agenda_cliente_pos_servico(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_prometer(uuid,timestamp with time zone)', 'interna', true),
('_agenda_cliente_prometer_confirmacao(uuid,timestamp with time zone,timestamp with time zone)', 'interna', true),
('_agenda_cliente_pronto(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_proximo_toque(timestamp with time zone)', 'tela', false),
('_agenda_cliente_quando(integer,timestamp with time zone,timestamp with time zone,uuid)', 'interna', false),
('_agenda_cliente_quando_texto(timestamp with time zone,timestamp with time zone)', 'tela', false),
('_agenda_cliente_registrar(text,text,uuid,date,jsonb,timestamp with time zone,timestamp with time zone,text,text,timestamp with time zone,uuid)', 'interna', true),
('_agenda_cliente_respostas_so_muda()', 'gatilho', false),
('_agenda_cliente_restaurar_pedido(uuid,timestamp with time zone)', 'interna', false),
('_agenda_cliente_revalidar(uuid,timestamp with time zone)', 'interna', true),
('_agenda_cliente_risco(uuid,date)', 'tela', false),
('_agenda_cliente_sem_mensagem(uuid)', 'interna', false),
('_agenda_cliente_sem_resposta(date,timestamp with time zone)', 'interna', false),
('_agenda_cliente_telefone(uuid)', 'tela', false),
('_agenda_cliente_teria_feito(text,date)', 'tela', false),
('_agenda_cliente_texto(text,text,uuid,jsonb,date)', 'tela', false),
('_agenda_cliente_texto_do_aviso(text,text,uuid,jsonb,date)', 'interna', false),
('_agenda_cliente_texto_proibido(text)', 'tela', false),
('_agenda_cliente_tipo_liberado(text)', 'tela', false),
('_agenda_cliente_tipo_texto(text)', 'tela', false),
('_agenda_cliente_toque(date)', 'tela', false),
('_agenda_cliente_ultimo_fim(date)', 'tela', false),
('_agenda_cliente_vespera(date)', 'tela', false),
('_agenda_clientes_do_telefone(text,timestamp with time zone)', 'interna', false),
('_agenda_desfazer_cliente(uuid,uuid,text,date,timestamp with time zone)', 'interna', false),
('_agenda_fila_do_cliente()', 'gatilho', true),
('_agenda_linhas_do_fechamento(date)', 'tela', false),
('_agenda_mudancas(date,date,boolean,boolean,timestamp with time zone)', 'tela', false),
('_agenda_rascunho_frase(text,jsonb)', 'servico', false),
('_agenda_ver_clientes(uuid,date)', 'tela', true),
('_pedir_confirmacao(uuid,uuid,timestamp with time zone)', 'interna', true),
('agenda_cliente_decidir_dito(uuid,text,text,text,date,timestamp with time zone)', 'tela', true),
('agenda_cliente_pode_sair(uuid,timestamp with time zone)', 'servico', true),
('agenda_cliente_preparar(uuid,text,text,boolean,text,date,timestamp with time zone)', 'tela', true),
('agenda_cliente_vigiar(date,timestamp with time zone)', 'servico', true),
('agenda_decidir(uuid,smallint,uuid,text,text,date,timestamp with time zone)', 'servico', true),
('agenda_desfazer(uuid,uuid,text,date,timestamp with time zone)', 'servico', true),
('agenda_rascunho_planejar(uuid,text,text,jsonb,text,date)', 'tela', true),
('agenda_resposta_do_cliente(text,text,uuid,text,text,text,timestamp with time zone)', 'servico', true),
('agenda_saude(date,timestamp with time zone)', 'tela', false),
('agenda_ver(uuid,text,text,text,text,jsonb,boolean,date)', 'tela', false),
('os_plano_da_os(uuid,date)', 'tela', true),
('pedir_confirmacao_do_agendamento(uuid,uuid)', 'tela', true),
('registrar_confirmacao_do_cliente(text,text,uuid)', 'servico', true);

insert into _resultado
select 'F1 as 89 funções da Fase 5 existem (82 dos pacotes + 4 da correção C1 + 3 da C2)', count(*) = 89 and count(to_regprocedure('public.' || k.f)) = 89,
       coalesce(string_agg(k.f, ', ') filter (where to_regprocedure('public.' || k.f) is null), 'todas')
  from _pd_funcoes k;

insert into _resultado
select 'F2 nenhuma delas executável por anon',
       count(*) filter (where has_function_privilege('anon', to_regprocedure('public.' || k.f), 'execute')) = 0,
       coalesce(string_agg(k.f, ', ') filter (where has_function_privilege('anon', to_regprocedure('public.' || k.f), 'execute')), 'nenhuma')
  from _pd_funcoes k where to_regprocedure('public.' || k.f) is not null;

insert into _resultado
select format('F3 as portas: %s', case k.quem when 'tela' then 'as de tela e conversa (as palavras, a ferramenta, o foco, o cartão) para authenticated e service_role'
                                      when 'servico' then 'as do motor, do worker e do webhook (a rodada, a resposta do cliente, o pode_sair) só service_role'
                                      when 'interna' then 'as internas para ninguém, nem service_role (só outra função as chama)'
                                      else 'os gatilhos sem authenticated' end),
       coalesce(bool_and(case k.quem
         when 'tela' then has_function_privilege('authenticated', p, 'execute') and has_function_privilege('service_role', p, 'execute')
         when 'servico' then not has_function_privilege('authenticated', p, 'execute') and has_function_privilege('service_role', p, 'execute')
         when 'interna' then not has_function_privilege('authenticated', p, 'execute') and not has_function_privilege('service_role', p, 'execute')
         else not has_function_privilege('authenticated', p, 'execute') end), false),
       coalesce(string_agg(k.f, ', ') filter (where not case k.quem
         when 'tela' then has_function_privilege('authenticated', p, 'execute') and has_function_privilege('service_role', p, 'execute')
         when 'servico' then not has_function_privilege('authenticated', p, 'execute') and has_function_privilege('service_role', p, 'execute')
         when 'interna' then not has_function_privilege('authenticated', p, 'execute') and not has_function_privilege('service_role', p, 'execute')
         else not has_function_privilege('authenticated', p, 'execute') end), 'todas')
  from _pd_funcoes k cross join lateral (select to_regprocedure('public.' || k.f) as p) x
 where x.p is not null
 group by k.quem;

insert into _resultado
select 'F4 security definer só as que precisam (e todas com search_path fixo)',
       coalesce(bool_and(pp.prosecdef = k.definer and coalesce(array_to_string(pp.proconfig, ','), '') like '%search_path=%'), false),
       coalesce(string_agg(k.f, ', ') filter (where pp.prosecdef <> k.definer
                                                 or coalesce(array_to_string(pp.proconfig, ','), '') not like '%search_path=%'), 'todas')
  from _pd_funcoes k join pg_proc pp on pp.oid = to_regprocedure('public.' || k.f);

insert into _resultado
select 'F5 nenhuma função da agenda (agenda_*, _agenda_*, os_*, _os_*) executável por anon',
       count(*) > 0 and count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0,
       format('%s funções; com anon: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(_?agenda_|_?os_)';

insert into _resultado
select 'F6 a agenda_ver aceita o foco clientes e a mensagem do foco que não existe cita os 18',
       p.prosrc like '%''compras'', ''fornecedores'', ''clientes'') then%'
       and p.prosrc like '%comissao, equipe, compras, fornecedores ou clientes)%',
       null
  from pg_proc p where p.oid = to_regprocedure('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)');

insert into _resultado
select 'F8 (correção C1) o botão é a casca: pedir_confirmacao_do_agendamento chama _pedir_confirmacao com now(); o webhook novo só depois da 100700',
       p.prosrc like '%return public._pedir_confirmacao(p_os, p_autor, now());%', null
  from pg_proc p where p.oid = to_regprocedure('public.pedir_confirmacao_do_agendamento(uuid, uuid)');

insert into _resultado
select 'F7 o cartão "Plano" (os_plano_da_os) traz a chave cliente (_agenda_cliente_da_os)',
       p.prosrc like '%''cliente'', public._agenda_cliente_da_os(p_os, p_hoje),%', null
  from pg_proc p where p.oid = to_regprocedure('public.os_plano_da_os(uuid, date)');

-- (correção C2, regressão B3) o d10 (_agenda_cliente_conversou) tem o índice das mensagens recebidas pela chave do telefone,
-- e a consulta dele pode usá-lo (com a varredura sequencial desligada só nesta conferência, o plano usa o índice)
insert into _resultado
select 'F9 (correção C2, B3) o índice agenda_wa_recebidas_por_chave existe (as recebidas pela chave do telefone)',
       exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.indexname = 'agenda_wa_recebidas_por_chave'
                  and i.indexdef like '%_agenda_chave_telefone(phone_normalized)%' and i.indexdef like '%inbound%'),
       null;
create temp table _pd_plano (linha text) on commit drop;
do $f9$
declare
  l text;
begin
  set local enable_seqscan = off;
  for l in execute $q$explain select 1 from public.clients c join public.whatsapp_messages w
                         on public._agenda_chave_telefone(w.phone_normalized)
                            in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
                      where c.id = '00000000-0000-0000-0000-000000000000'::uuid and w.direction = 'inbound'
                        and w.occurred_at <= now() and w.occurred_at > now() - interval '365 days'$q$ loop
    insert into _pd_plano values (l);
  end loop;
  set local enable_seqscan = on;
end
$f9$;
insert into _resultado
select 'F9b (correção C2, B3) a consulta do d10 pode usar o índice (sem Seq Scan em whatsapp_messages)',
       coalesce(bool_or(linha like '%agenda_wa_recebidas_por_chave%') and not bool_or(linha like '%Seq Scan on whatsapp_messages%'), false),
       string_agg(btrim(linha), ' / ')
  from _pd_plano;

-- ── N. Em sombra nada sai ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'N1 o cliente nunca ligado (nenhuma rodada do cliente em ligado): nada na fila agenda-cliente e nenhuma mensagem em ligado',
       exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'cliente' and r.contagens ->> 'modo_cliente' = 'ligado')
       or c.modo_cliente = 'ligado'
       or (not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-cliente')
           and not exists (select 1 from public.agenda_cliente_mensagens m where m.modo = 'ligado')),
       format('fila agenda-cliente %s; mensagens em ligado %s; registradas em teste %s',
              (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-cliente'),
              (select count(*) from public.agenda_cliente_mensagens m where m.modo = 'ligado'),
              (select count(*) from public.agenda_cliente_mensagens m where m.modo = 'sombra'))
  from public.agenda_config c;

insert into _resultado
select 'N2 toda linha agenda-cliente da fila tem a mensagem dela, registrada em ligado',
       count(*) filter (where m.id is null or m.modo <> 'ligado') = 0,
       format('%s linha(s); sem a mensagem em ligado: %s', count(*), count(*) filter (where m.id is null or m.modo <> 'ligado'))
  from public.whatsapp_send_queue q
  left join public.agenda_cliente_mensagens m on m.id = q.source_ref_id
 where q.source = 'agenda-cliente';

-- ── S. A saúde da mensagem ao cliente ───────────────────────────────────────────────────────────────────
create temp table _saude on commit drop as select public.agenda_saude() as s;

insert into _resultado
select format('S1 cliente.%s = 0', k), (s #>> array['cliente', k])::int = 0, s #>> array['cliente', k]
  from _saude, unnest(array['fora_da_janela', 'em_feriado_ou_domingo', 'acima_do_teto', 'intervalo_curto', 'com_texto_proibido',
                            'na_fila_em_sombra', 'sem_aprovacao_no_periodo', 'critica_sem_decisao',
                            'vespera_com_os_aguardando_peca', 'aviso_depois_da_data', 'audio_que_confirmou']) k;

insert into _resultado
select 'S2 o modo e as ondas que a saúde mostra são os da linha',
       s #>> '{cliente,modo}' = c.modo_cliente and s #> '{cliente,tipos_ligados}' = to_jsonb(c.cliente_tipos_ligados),
       (s -> 'cliente' -> 'modo')::text || ' ' || (s #> '{cliente,tipos_ligados}')::text
  from _saude, public.agenda_config c;

insert into _resultado
select 'S3 a saúde ok (os zeros das Fases 2 a 5 juntos)', (s ->> 'ok')::boolean, s ->> 'ok'
  from _saude;

insert into _resultado
select 'S4 nenhum erro da mensagem ao cliente (cliente:%) nas últimas 24 h', coalesce((s #>> '{cliente,erros_24h}')::int, 0) = 0,
       s #>> '{cliente,erros_24h}'
  from _saude;

insert into _resultado
select 'S5 a rodada do cliente rodou nas últimas 2 h (fora de desligado; desligada ela não grava rodada)',
       coalesce((s #>> '{cliente,rodou_nas_ultimas_2h}')::boolean, false) or c.modo_cliente = 'desligado',
       format('última rodada %s', coalesce(s #>> '{cliente,ultima_rodada}', 'nenhuma'))
  from _saude, public.agenda_config c;

insert into _resultado
select 'S6 nenhum erro da mensagem ao cliente (context agenda, action cliente:%; agenda:cliente%) aberto em app_error_logs',
       count(*) = 0, coalesce(string_agg(e.action || ': ' || left(e.message, 80), ' | '), 'nenhum')
  from public.app_error_logs e
 where e.resolved_at is null
   and ((e.context = 'agenda' and e.action like 'cliente:%') or e.action like 'agenda:cliente%');

-- ── L. As leituras ──────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_leituras on commit drop as
select public.agenda_ver(p_foco => 'clientes') as cli, public.agenda_ver(p_foco => 'clientes') as cli2,
       (select c.texto_max from public.agenda_config c) as texto_max,
       (select c.modo_leitura from public.agenda_config c) as leitura;

insert into _resultado
select 'L1 o foco clientes devolve texto dentro de texto_max (com a leitura desligada: "a agenda de produção está desligada")',
       case when l.leitura = 'desligado' then l.cli ->> 'rota' = 'desligada'
            else (l.cli ->> 'ok')::boolean and length(l.cli ->> 'texto') between 1 and l.texto_max end,
       format('%s caracteres', length(l.cli ->> 'texto'))
  from _pd_leituras l;

insert into _resultado
select 'L2 duas leituras seguidas do foco clientes = o mesmo texto (md5)',
       md5(coalesce(l.cli ->> 'texto', '')) = md5(coalesce(l.cli2 ->> 'texto', '')), null
  from _pd_leituras l;

insert into _resultado
select 'L3 o cartão de uma OS da carteira traz a chave cliente com o modo da linha (sem OS com cliente na carteira: só mostra)',
       x.os is null or (x.cartao -> 'cliente' ->> 'modo') = c.modo_cliente,
       coalesce(x.numero || ': ' || left((x.cartao -> 'cliente')::text, 200), 'nenhuma OS com cliente na carteira')
  from public.agenda_config c
  left join lateral (
    select so.id as os, so.service_order_number as numero, public.os_plano_da_os(so.id) as cartao
      from public.service_orders so
     where so.client_id is not null and so.merged_into_id is null
       and so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
     order by so.service_order_number limit 1) x on true;

select teste, ok, detalhe from _resultado order by teste;

rollback;
