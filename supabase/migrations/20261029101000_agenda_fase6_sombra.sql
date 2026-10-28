-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P8: o aprendizado de desligado para SOMBRA (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§0 item 3, §5.8, §9 P8, §10 passo 3). Decisões do dono de 23/10 (o
-- aprendizado coleta dado desde o 1º dia; tudo nasce em sombra): em sombra a agenda calcula o que aprendeu e mostra ("hoje
-- seria 1,7×"), mas não usa nada.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das 9 migrations de estrutura da Fase 6
-- (20261029100000..100800) e do task-automations que chama a rodada (passos 1–2 de fila-do-dono/fase6-oks.md).
--
-- POR QUE: as migrations da Fase 6 não mudam o modo. A 20261029100000 cria modo_aprendizado com a linha 'desligado' (o DEFAULT
-- da coluna é 'sombra', mas a linha que já existe fica 'desligado'). Desligado, a rodada diária (agenda_aprender) só congela os
-- dias ditos no início e mede as OS concluídas: não calcula o fator, o fornecedor, a capacidade nem o cliente, e o foco
-- *agenda aprendizado* não tem o que mostrar. Em sombra ela calcula tudo e grava em agenda_aprendizado com o estado
-- 'sombra' — e nada muda no que a agenda faz: _agenda_aprendido devolve nulo fora de 'ligado' (vale o padrão de hoje),
-- nenhuma ação "aprendizado" entra no "o que mudou", nenhuma pergunta "aprendizado" vai ao dono, e nenhuma mensagem a
-- ninguém. São essas semanas em teste que o dono lê (*agenda aprendizado*, "Em teste: …") antes de cada OK de ligar (passo 4).
--
-- O QUE FAZ:
--   1. modo_aprendizado de 'desligado' para 'sombra'. Só sai de 'desligado' E com aprendizado_ligados vazio (= a linha como
--      nasceu, nunca ligada): NUNCA rebaixa 'ligado', não mexe no que já está em 'sombra', e não religa em teste a linha que o
--      dono desligou depois de ter ligado itens (aprendizado_ligados com itens: "parar até a medição" vale).
--   2. aprendizado_ligados fica '{}' (nenhum item: em sombra a lista não vale; cada item é um UPDATE à parte, com o OK do dono
--      — passo 4).
--   Não toca os outros modos (leitura, proposta, vigia, equipe, diária, material, detector, fornecedor, cliente) nem número
--   nenhum de agenda_config. atualizado_em/atualizado_por só mudam na linha que mudou (atualizado_por = null: foi a migration,
--   não uma pessoa).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase db query --linked -e "select modo_aprendizado, aprendizado_ligados from public.agenda_config;"
--   Esperado: desligado; {}.
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono, "OK passo 3 da Fase 6"):
--   npx supabase db query --linked -f supabase/migrations/20261029101000_agenda_fase6_sombra.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029101000', 'agenda_fase6_sombra');"
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (o modo e a lista);
--   · npx supabase db query --linked -f supabase/tests/agenda_fase6_pos_deploy.sql (o modo em sombra, as colunas, as funções,
--     agenda_saude().aprendizado com os zeros e nenhum app_error_logs aberto de aprender:%).
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado' com a lista vazia). A bancada NÃO aplica este
-- arquivo (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e
-- supabase/tests/agenda_fase6_sombra.sql roda este arquivo numa subtransação desfeita (desligado → sombra; de novo não muda
-- nada; ligado fica ligado; o desligado com itens fica; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; o que a sombra calculou — as linhas de agenda_aprendizado em 'sombra' e as medidas — fica
-- como rastro e não vale para ninguém; nada é apagado). É UM comando só (o bloco do $desfaz$ abaixo, inteiro): copie-o para
-- um arquivo e rode com npx supabase db query --linked -f <arquivo>. Ele só volta a linha que está em 'sombra': a que já foi
-- ligada não muda (para parar o que está ligado, "tudo na hora" da §10: modo_aprendizado = 'sombra').
--   do $desfaz$
--   begin
--     update public.agenda_config set modo_aprendizado = 'desligado', atualizado_em = now(), atualizado_por = null where id and modo_aprendizado = 'sombra';
--   end
--   $desfaz$;
--
-- (Com a linha de novo desligada, a rodada diária continua medindo as OS concluídas — spec §0 item 2 — e o foco *agenda
-- aprendizado* diz que o aprendizado está desligado.)

-- 1 e 2. O modo: de desligado (nunca ligado) para sombra; a lista dos itens fica vazia.
update public.agenda_config
   set modo_aprendizado    = 'sombra',
       aprendizado_ligados = '{}',
       atualizado_em       = now(),
       atualizado_por      = null
 where id
   and modo_aprendizado = 'desligado'
   and aprendizado_ligados = '{}';

-- O estado depois (o modo e a lista; o resto dos modos para conferir que não mudou).
select c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_diaria, c.modo_material, c.modo_detector,
       c.modo_fornecedor, c.modo_cliente, c.modo_aprendizado, c.aprendizado_ligados, c.atualizado_em
  from public.agenda_config c;
