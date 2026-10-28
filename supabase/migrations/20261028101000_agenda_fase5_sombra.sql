-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P6: as mensagens ao cliente de desligado para SOMBRA (o
-- dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§0 item 2, §9 P6, §10 passo 3). Decisões do dono de 23/10 (Autonomia: o
-- gestor manda as mensagens-modelo ao cliente; "mensagem à equipe ou a cliente: só atrás do modo, que nasce sombra"): tudo
-- nasce em sombra — grava a mensagem que mandaria e não manda nada.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das 7 migrations de estrutura da
-- Fase 5 (20261028100000..100600), das edge functions (whatsapp-queue-worker, task-automations, whatsapp-webhook, ai-agent,
-- erp-mcp, ai-daily-briefing) e do front do cartão "Plano" (passos 1–2 de fila-do-dono/fase5-oks.md) — e só com as Fases 1
-- a 4 no ar, a agenda automática (modo_proposta) e a vigia (modo_vigia) ligadas: o plano publicado é a fonte das datas e a
-- vigia leva as perguntas ao fechamento; sem elas, a sombra não teria o que mostrar.
--
-- POR QUE: as migrations da Fase 5 não mudam o modo. modo_cliente existe desde a Fase 1 (20261024160000) e a linha está
-- 'desligado' (a 20261028100000 só trocou o DEFAULT da coluna para 'sombra'): desligada, a rodada do cliente só passa pela
-- fila (que não tem nada), e não há como conferir, antes de ligar, o que a agenda teria mandado a cada cliente nem como ela
-- teria lido as respostas. Em sombra ela roda: grava as mensagens que mandaria (agenda_cliente_mensagens, modo 'sombra',
-- estado 'registrada'), a ação "Em teste: eu teria mandado ao …" e as respostas dos clientes com o que teria feito (efeito
-- 'sombra') — e nada sai: nenhuma linha agenda-cliente na fila do WhatsApp (o _agenda_cliente_enfileirar para no modo; o
-- gatilho da fila recusa agenda-cliente fora de 'ligado'; o worker pergunta ao banco antes de mandar), nenhuma OS muda pela
-- resposta do cliente, e as palavras *manda cliente* / *segura cliente* respondem "As mensagens ao cliente estão em teste:
-- nada sai ainda.". O botão "Pedir confirmação" continua como hoje (a regra de 30/09) até a onda 2. São essas duas semanas
-- de sombra que o dono confere (*agenda clientes*, "Em teste, eu teria mandado…") antes dos OKs das ondas (passos 4–7).
--
-- O QUE FAZ:
--   1. modo_cliente de 'desligado' para 'sombra'. Só sai de 'desligado' E com cliente_tipos_ligados vazio (= a linha como
--      nasceu, nunca ligada): NUNCA rebaixa 'ligado', não mexe no que já está em 'sombra', e não religa em teste a linha que o
--      dono desligou depois de ter ligado ondas (cliente_tipos_ligados com tipos: "para as mensagens ao cliente" vale).
--   2. cliente_tipos_ligados fica '{}' (nenhuma onda: em sombra a lista não vale; cada onda é um UPDATE à parte, com o OK do
--      dono — passos 4 a 7).
--   Não toca modo_leitura, modo_proposta e modo_vigia (Fases 1 e 2), modo_equipe e modo_diaria (Fase 3), modo_material,
--   modo_detector e modo_fornecedor (Fase 4) nem número nenhum de agenda_config. atualizado_em/atualizado_por só mudam na
--   linha que mudou (atualizado_por = null: foi a migration, não uma pessoa).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase db query --linked -e "select modo_leitura, modo_proposta, modo_vigia, modo_cliente, cliente_tipos_ligados
--     from public.agenda_config;"
--   Esperado: leitura, proposta e vigia ligados (Fases 1 e 2); cliente desligado; tipos {}.
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono, "OK passo 3 da Fase 5"):
--   npx supabase db query --linked -f supabase/migrations/20261028101000_agenda_fase5_sombra.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028101000', 'agenda_fase5_sombra');"
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (o modo e a lista);
--   · npx supabase db query --linked -f supabase/tests/agenda_fase5_pos_deploy.sql
--     (C: modo_cliente em sombra; N: nada na fila agenda-cliente e nenhuma mensagem em ligado; S: os zeros de
--     agenda_saude().cliente; a rodada do cliente nas últimas 2 h, a partir do 1º tique de 15 min).
--   Os pós-deploy das Fases 1, 2 e 3 conferiam modo_cliente = 'desligado': com a 20261028101000 registrada eles aceitam a
--   sombra e deixam a conferência da Fase 5 com este pós-deploy (o mesmo jeito da Fase 3 com a equipe).
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado' com a lista vazia). A bancada NÃO aplica este
-- arquivo (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e
-- supabase/tests/agenda_fase5_sombra.sql roda este arquivo numa subtransação desfeita (desligado → sombra; de novo não muda
-- nada; ligado fica ligado; o desligado com ondas fica; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; o que a sombra gravou — mensagens registradas em teste, as ações "Em teste: …" e as
-- respostas com efeito 'sombra' — fica como rastro e não vale para ninguém; nada é apagado). É UM comando só (o bloco do
-- $desfaz$ abaixo, inteiro): copie-o para um arquivo e rode com npx supabase db query --linked -f <arquivo>. Ele só volta a
-- linha que está em 'sombra': a que já foi ligada não muda (para parar o que está ligado, "parar tudo na hora" da §10:
-- modo_cliente = 'desligado').
--   do $desfaz$
--   begin
--     update public.agenda_config set modo_cliente = 'desligado', atualizado_em = now(), atualizado_por = null where id and modo_cliente = 'sombra';
--   end
--   $desfaz$;
--
-- (Com a linha de novo desligada, a rodada do cliente só passa pela fila — que em sombra não tem linha agenda-cliente — e
-- as palavras seguem ao modelo, como antes da sombra.)

-- 1 e 2. O modo: de desligado (nunca ligado) para sombra; a lista das ondas fica vazia.
update public.agenda_config
   set modo_cliente          = 'sombra',
       cliente_tipos_ligados = '{}',
       atualizado_em         = now(),
       atualizado_por        = null
 where id
   and modo_cliente = 'desligado'
   and cliente_tipos_ligados = '{}';

-- O estado depois (o modo e a lista das ondas; o resto dos modos para conferir que não mudou).
select c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_diaria, c.modo_material, c.modo_detector,
       c.modo_fornecedor, c.modo_cliente, c.cliente_tipos_ligados, c.atualizado_em
  from public.agenda_config c;
