-- Agenda de Produção, Fase 7, etapa 7b ("os dias de verdade de quem trabalha e a dupla pela tarefa"), pacote P5: os 5 modos da etapa
-- de desligado para SOMBRA (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase7b.md (§R1 AG7-01, §R4.3(b) o DESFAZER da dupla, §R4.7 o dado com 5 modos, §5.5, §10
-- passo 3); nomes: fase7-registro.md §1 (os modos modo_dias, modo_dupla, modo_sabado, modo_cadastro e modo_chamar; "a migration de dado
-- da etapa põe sombra") e §3 (o nº 20 da ordem).
-- Respostas do dono de 29/10 (fase7-padroes.md, AG7-01 "ligar direto quando estiver pronto"): a publicação nunca liga às cegas
-- — este arquivo põe tudo em teste, e cada *ligar* é um UPDATE no MESMO dia, depois do pós-deploy verde, pelo roteiro de
-- fila-do-dono/fase7b-oks.md.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das migrations de estrutura da 7b
-- (20261101100000 .. 100500, e a 100800/100850 se houver) e do deploy de task-automations, ai-agent, erp-mcp e do front (passos 1 e
-- 2 de fila-do-dono/fase7b-oks.md).
--
-- POR QUE: as migrations da 7b não mudam o modo. A 20261101100000 (P1) cria os 5 modos com a linha 'desligado' (o DEFAULT da coluna é
-- 'sombra', mas a linha que já existe fica 'desligado'). Desligado, tudo é o de antes, byte a byte. Em sombra:
--   · modo_dias: a pergunta da semana fica só registrada (nada sai à equipe), a do dono nasce em teste, e o dono em campo conta pela
--     metade (dono_carga_max 0,50, AG7-02: a meia capacidade confirmada não espera o OK dos textos à equipe, R4.5);
--   · modo_dupla: a dupla pela tarefa só ACRESCENTA a 2ª pessoa onde ela cabe sem atrasar (d8); a dupla que o dono disse no início ou no
--     fim espera a 2ª pessoa (R4.3(b)); o cartão da OS mostra "Em teste: eu marcaria …";
--   · modo_sabado: o sábado de manhã sai só como linha "Em teste" (nenhuma alocação no sábado);
--   · modo_cadastro: a chamada da equipe, o telefone e o contato nascem em teste; a regra d14 só conta;
--   · modo_chamar: a sugestão de quem chamar aparece só no foco *agenda gestor*, com "Em teste:" (o P6).
--
-- O QUE FAZ:
--   1. modo_dias, modo_dupla, modo_sabado, modo_cadastro e modo_chamar: cada um de 'desligado' para 'sombra', só o que está
--      'desligado'. NUNCA rebaixa 'ligado' nem mexe no que já está em 'sombra'.
--   Não toca os modos das Fases 1–6 e da 7a, nem número nenhum de agenda_config. atualizado_em/atualizado_por só mudam na linha que
--   mudou (atualizado_por = null: foi a migration, não uma pessoa).
--   ATENÇÃO (diferente da 7a, que guarda a data do ligar): a 7b não guarda quando um modo foi ligado; um modo que o dono voltou a
--   desligado DEPOIS de ligar voltaria a teste se este arquivo fosse rodado de novo. Ele roda uma vez (schema_migrations).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked -e "select modo_dias, modo_dupla, modo_sabado, modo_cadastro, modo_chamar,
--     (select count(*) from public.os_planejamento where dupla_dita in ('inicio', 'fim')) as ditas_em_parte from public.agenda_config;"
--   Esperado: desligado nos 5; ditas_em_parte 0 (com modo_dupla desligado o rascunho recusa a dupla no início ou no fim).
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono, "OK passo 3 da Fase 7b"):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261101100900_agenda_fase7b_sombra.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261101100900', 'agenda_fase7b_sombra');"
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os 5 modos);
--   · supabase/tests/agenda_fase7b_pos_deploy.sql: C2 com os 5 em sombra; S1 com os zeros de agenda_saude().equipe_dias.
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado'). A bancada NÃO aplica este arquivo
-- (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e
-- supabase/tests/agenda_fase7b_sombra.sql roda este arquivo numa subtransação desfeita (desligado → sombra nos 5; de novo não muda nada;
-- ligado fica ligado; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; nada é apagado). É UM comando só (o bloco abaixo, inteiro, do "with" ao ";"): copie-o para um arquivo
-- e rode com npx supabase@2.111.0 db query --linked -f <arquivo>. Ele só volta o que está em 'sombra' (o que já foi ligado não muda:
-- para parar o que está ligado, o modo dele para 'sombra' primeiro, §10). E (R4.3(b)) quando o modo_dupla volta de teste a desligado,
-- na MESMA transação, a dupla que o dono disse só no início ou no fim do serviço passa a "o tempo todo" (sem o modo, o motor não
-- enxerga a dupla em parte do serviço e mandaria 1 pessoa onde o dono disse 2): dupla_dita todos, dupla_meios nulo, o motivo "dupla
-- em parte do serviço desligada: vai em dupla o tempo todo", com o antes e o depois no histórico da OS. O resultado lista essas OS.
--   with antes as (
--     select c.modo_dupla from public.agenda_config c where c.id
--   ), modos as (
--     update public.agenda_config set modo_dias = case when modo_dias = 'sombra' then 'desligado' else modo_dias end, modo_dupla = case when modo_dupla = 'sombra' then 'desligado' else modo_dupla end, modo_sabado = case when modo_sabado = 'sombra' then 'desligado' else modo_sabado end, modo_cadastro = case when modo_cadastro = 'sombra' then 'desligado' else modo_cadastro end, modo_chamar = case when modo_chamar = 'sombra' then 'desligado' else modo_chamar end, atualizado_em = now(), atualizado_por = null
--      where id and 'sombra' in (modo_dias, modo_dupla, modo_sabado, modo_cadastro, modo_chamar)
--     returning 1
--   ), ditas as (
--     update public.os_planejamento p set dupla_dita = 'todos', dupla_meios = null, dupla_motivo = 'dupla em parte do serviço desligada: vai em dupla o tempo todo', dupla_em = now(), historico = public._os_material_historico(p.historico, jsonb_build_object('em', (now() at time zone 'America/Sao_Paulo')::date, 'autor', null, 'trecho', 'DESFAZER da 20261101100900: a dupla em parte do serviço desligada', 'antes', jsonb_build_object('dupla', p.dupla_dita, 'dupla_meios', p.dupla_meios), 'depois', jsonb_build_object('dupla', 'todos'))), atualizado_em = now(), atualizado_por = null
--      where p.dupla_dita in ('inicio', 'fim') and (select a.modo_dupla from antes a) = 'sombra'
--     returning p.service_order_id
--   )
--   select (select count(*) from modos) as modos_desligados, coalesce((select string_agg(so.service_order_number, ', ' order by so.service_order_number) from ditas d join public.service_orders so on so.id = d.service_order_id), 'nenhuma') as dupla_passou_a_todos;
--
-- (Com os 5 de novo desligados, tudo volta ao de antes da 7b, byte a byte: a pergunta da semana não nasce, o motor não põe dupla por
-- meio-dia, o cartão da OS sai sem o bloco Equipe e a saúde conta os zeros da 7b em 0.)

-- 1. Os 5 modos da 7b: de desligado para sombra, cada um só se estiver desligado.
update public.agenda_config
   set modo_dias     = case when modo_dias = 'desligado' then 'sombra' else modo_dias end,
       modo_dupla    = case when modo_dupla = 'desligado' then 'sombra' else modo_dupla end,
       modo_sabado   = case when modo_sabado = 'desligado' then 'sombra' else modo_sabado end,
       modo_cadastro = case when modo_cadastro = 'desligado' then 'sombra' else modo_cadastro end,
       modo_chamar   = case when modo_chamar = 'desligado' then 'sombra' else modo_chamar end,
       atualizado_em = now(),
       atualizado_por = null
 where id
   and 'desligado' in (modo_dias, modo_dupla, modo_sabado, modo_cadastro, modo_chamar);

-- O estado depois (os 5 modos; os da 7a e das Fases 1–6 para conferir que não mudaram).
select c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_diaria, c.modo_material, c.modo_cliente,
       c.modo_aprendizado, c.modo_marcar_sozinho, c.modo_encaixe_aprovacao, c.modo_revisao_diaria, c.modo_compre_ate,
       c.modo_dias, c.modo_dupla, c.modo_sabado, c.modo_cadastro, c.modo_chamar, c.atualizado_em
  from public.agenda_config c;
