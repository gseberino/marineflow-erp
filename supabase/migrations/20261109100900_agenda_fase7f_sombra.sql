-- Agenda de Produção, Fase 7, etapa 7f ("falar só o que importa"), pacote P8: os 3 modos da etapa que já têm código (o formato da agenda no fechamento, o prazo nas
-- perguntas e o lote do dono) de desligado para SOMBRA (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md §5.8 (com R8.2: o dado é a 20261109100900, não a 100700), R8.6 (o freio), R8.8 (o peso), R8.13 (a linha P8) e R8.14 (a §10
-- reescrita: publicar em teste pelo OK permanente, cada *ligar* pelo OK nomeado). Nomes: fase7-registro.md §1 (os 6 interruptores da 7f) e §3 (a linha 52 da ordem).
-- Respostas do dono (fase7-padroes.md, diario-0811/respostas): AG7-01 "Ligar direto quando estiver pronto" — a publicação nunca liga às cegas: este arquivo põe em teste, e cada
-- *ligar* é um UPDATE no dia, pelo publicar/exec/ligar-fase7f.sql, depois do pós-deploy verde e do que a saúde mede (o "por quê", na linguagem do dono, em fila-do-dono/fase7f-oks.md).
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão. Aplica DEPOIS das 5 migrations de estrutura da 7f (20261109100000, 100100, 100200, 100300 e 100600) e do deploy de ai-agent,
-- erp-mcp, whatsapp-webhook, ai-daily-briefing e task-automations (passos 1 e 2 de fila-do-dono/fase77f-publicar.md).
--
-- POR QUE SÓ 3 (decisão do fio, 08/11, no lugar da §5.8, "os seis modo_* novos → sombra"): a 20261109100000 (P1) cria os 6 interruptores com a linha 'desligado' (o DEFAULT da
-- coluna é 'sombra', mas a linha que já existe fica 'desligado'). Só 3 têm código nas migrations da 7f: modo_bloco_agenda (P3), modo_veto (P2) e modo_lote_dono (P4).
-- modo_equipe_previsto, modo_equipe_convite e modo_cliente_camadas ficam 'desligado': só a coluna (P1), _agenda_fala_modo (P1) e a saúde da comunicação (P7) os leem, e os passos
-- deles (P5 e P6) não existem — a rodada comunicar diz "ainda não existe" nos 4 da equipe. Em sombra, a saúde diria "em teste" de algo que não roda. O dado do P5 e do P6,
-- quando vierem (com timestamp maior que o último aplicado, R8.2), põe os deles em sombra.
--
-- EM SOMBRA (com o freio de hoje, gestor_so_propor = true): nada sai a ninguém e o texto ao dono é o de antes, byte a byte.
--   · modo_bloco_agenda: os 3 textos da tarde (fechamento, revisão da semana e do mês) ficam os de antes; o bloco é calculado e vai só ao detalhe de resumo_tarde
--     (bloco_diria e bloco_seria, com as letras: é dali que a saúde conta "1 fechamento e 1 revisão em teste com o texto ≤ 1.000", o que o *ligar* do formato pede). O registro do
--     fechamento grava veto_teria_em pelo veto_diria da linha (medida).
--   · modo_veto: com o freio, ligado já seria sombra; em sombra nada vence. A rodada do gestor (_agenda_gestor_vetos) e o teto da rodada comunicar só gravam veto_teria_em.
--     Nenhuma linha escreve "Sem resposta até".
--   · modo_lote_dono: o aviso "Agenda — o que eu mudei sozinho:" sai como antes, a cada rodada que muda (o que o dono pediu em 29/10). A rodada comunicar grava em
--     contagens.lote_guardaria o que o lote teria guardado; na quinta, depois das 16:50, contagens.quinta.quinta_diria (a mensagem da semana que sairia). Nada vai à fila.
--   · A rodada comunicar (task-automations, passo 0e, a cada tique, seg a sáb; domingo não roda) passa a gravar 1 linha por tique em agenda_vigia_rodadas (rotina comunicar),
--     como a rotina e o material: ~96 por dia (com os 6 desligados ela não grava nada).
--   Nada disso muda o plano, as ações, as perguntas que o dono lê, a fila do WhatsApp, a equipe ou o cliente (o teste agenda_fase7f_sombra.sql e o replay da carteira real do
--   P8, f7f/p8/real.mjs: o fechamento, as perguntas, *agenda pendências*, o aviso e o que a rodada comunicar manda à fila, antes e depois deste arquivo, iguais).
--
-- O QUE FAZ:
--   1. modo_bloco_agenda, modo_veto e modo_lote_dono: cada um de 'desligado' para 'sombra', só o que está 'desligado' (como nasceu). NUNCA rebaixa 'ligado' nem mexe no que já
--      está em 'sombra'.
--   Não toca modo_equipe_previsto, modo_equipe_convite e modo_cliente_camadas; cliente_tipos_ligados NÃO ganha 'semana'; o freio (gestor_so_propor) fica como está; nenhum modo
--   das Fases 1–6 nem de 7a–7d; número nenhum de agenda_config (bloco_max_chars, veto_tipos, perguntas_abertas_max, dono_semana_* e os outros ficam como a 20261109100000 os
--   criou: são as respostas do dono). atualizado_em/atualizado_por só mudam na linha que mudou (atualizado_por = null: foi a migration, não uma pessoa).
--   ATENÇÃO (como a 7b e a 7c): a 7f não guarda quando um modo foi ligado; um modo que o dono voltou a desligado DEPOIS de ligar voltaria a teste se este arquivo fosse rodado de
--   novo. Ele roda uma vez (schema_migrations).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked "select modo_bloco_agenda, modo_veto, modo_lote_dono, modo_equipe_previsto, modo_equipe_convite, modo_cliente_camadas,
--     gestor_so_propor, 'semana' = any (cliente_tipos_ligados) as semana_ligada from public.agenda_config;"
--   Esperado: desligado nos 6; gestor_so_propor true (o freio de hoje); semana_ligada false.
--
-- APLICAR (pelo OK permanente "publicar em teste cada etapa quando o pós-deploy der verde", passo 3 de fila-do-dono/fase77f-publicar.md):
--   PONTA=<a ponta> bash publicar/exec/aplicar.sh 20261109100900_agenda_fase7f_sombra   (aplica, registra em schema_migrations e para na 1ª falha)
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os 6 modos da 7f; o freio; cliente_tipos_ligados; os modos de antes, para conferir que não mudaram);
--   · supabase/tests/agenda_fase7f_pos_deploy.sql: M2 "registrada (passo 3 feito)" e C2 com os 3 em sombra e os 3 desligados;
--   · no tique seguinte (seg a sáb): uma linha rotina comunicar em agenda_vigia_rodadas, erros 0; agenda_saude() -> 'comunicacao' com zeros_ok.
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado'; sem nenhum, nem a hora). A bancada NÃO aplica este arquivo (scripts/bancada-agenda/bancada.mjs,
-- FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e supabase/tests/agenda_fase7f_sombra.sql o roda numa subtransação desfeita (desligado → sombra nos 3; os outros 3 e
-- o resto da linha iguais; de novo não muda nada; ligado fica ligado; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; nada é apagado). É UM comando só (do "with" ao ";", entre as marcas): copie-o para um arquivo e rode com
-- npx supabase@2.111.0 db query --linked -f <arquivo>. Ele só volta o que está em 'sombra' nos 3 e diz quais ficaram ligados: para parar um ligado, ele vai a 'sombra' primeiro
-- (o DESFAZER de publicar/exec/ligar-fase7f.sql) e depois este. Não mexe em mais nada: o que a sombra mediu (veto_teria_em, as linhas da rodada comunicar, o bloco no detalhe de
-- resumo_tarde) fica como rastro e ninguém lê com os 6 desligados (a saúde da comunicação só lê os números com algum fora de desligado). Com os 3 já desligados, não muda nada
-- (nem a hora).
-- DESFAZER-INICIO
--   with antes as (
--     select c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono from public.agenda_config c where c.id
--   ), modos as (
--     update public.agenda_config set modo_bloco_agenda = case when modo_bloco_agenda = 'sombra' then 'desligado' else modo_bloco_agenda end, modo_veto = case when modo_veto = 'sombra' then 'desligado' else modo_veto end, modo_lote_dono = case when modo_lote_dono = 'sombra' then 'desligado' else modo_lote_dono end, atualizado_em = now(), atualizado_por = null
--      where id and 'sombra' in (modo_bloco_agenda, modo_veto, modo_lote_dono)
--     returning 1
--   )
--   select (select count(*) from modos) as modos_desligados, coalesce((select concat_ws(', ', case when a.modo_bloco_agenda = 'ligado' then 'modo_bloco_agenda' end, case when a.modo_veto = 'ligado' then 'modo_veto' end, case when a.modo_lote_dono = 'ligado' then 'modo_lote_dono' end) from antes a where 'ligado' in (a.modo_bloco_agenda, a.modo_veto, a.modo_lote_dono)), 'nenhum') as ficam_ligados;
-- DESFAZER-FIM
-- (Com os 3 de novo desligados, tudo volta ao de antes do dado: o fechamento sem o bloco no detalhe, nenhum veto_teria_em novo, a rodada comunicar devolve {rodou: false} sem gravar
-- linha. As funções da 7f ficam no banco; a ordem nova do "Também quero saber", o *agenda espera* e *agenda pendências* acima de 1.800 letras não dependem de modo.)

-- 1. Os 3 modos que têm código: de desligado para sombra, cada um só se estiver desligado.
update public.agenda_config
   set modo_bloco_agenda = case when modo_bloco_agenda = 'desligado' then 'sombra' else modo_bloco_agenda end,
       modo_veto         = case when modo_veto = 'desligado' then 'sombra' else modo_veto end,
       modo_lote_dono    = case when modo_lote_dono = 'desligado' then 'sombra' else modo_lote_dono end,
       atualizado_em     = now(),
       atualizado_por    = null
 where id
   and 'desligado' in (modo_bloco_agenda, modo_veto, modo_lote_dono);

-- O estado depois (os 6 modos da 7f, o freio e a lista do cliente; os modos de antes, para conferir que não mudaram).
select c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono, c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas,
       c.gestor_so_propor, c.gestor_so_propor_em, 'semana' = any (c.cliente_tipos_ligados) as semana_ligada,
       c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_cliente, c.modo_marcar_sozinho, c.modo_vaga_fechamento, c.modo_dias,
       c.modo_tarefas, c.modo_local_calendario, c.modo_mesmo_local, c.atualizado_em
  from public.agenda_config c;
