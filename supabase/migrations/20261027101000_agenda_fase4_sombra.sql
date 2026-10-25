-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P6: os três modos do material de desligado
-- para SOMBRA, e o original da previsão das linhas que já tinham previsão antes do gatilho (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§3.1 princípio 5, §9 P6, §10 passo 3, §11 aceite 5). Decisões do dono de
-- 23/10 (Autonomia; "pede ao fornecedor que confirme o prazo (modelo)"): tudo nasce em sombra — calcula e grava o que faria,
-- e nada sai para ninguém.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO E DE MEDIÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das 7 migrations de estrutura da
-- Fase 4 (20261027100000..100600), das edge functions (email-imap, acompanhar-conversas, task-automations,
-- whatsapp-queue-worker, ai-agent, erp-mcp) e do front das telas de compra (passos 1–2 de fila-do-dono/fase4-oks.md) — e só
-- com as Fases 1, 2 e 3 no ar e a vigia da Fase 2 ligada (modo_vigia = 'ligado'): sem elas, não há carteira acompanhada nem
-- fechamento onde as perguntas apareceriam depois.
--
-- POR QUE: as migrations da Fase 4 não mudam os modos. modo_material, modo_detector e modo_fornecedor nascem 'desligado'
-- na linha (20261027100000): desligados, a rodada do material nem roda (o task-automations não chama o banco), e não há
-- como conferir, antes de ligar, o que ela teria perguntado ao dono (de qual serviço é a nota, o Pix), o que o detector
-- teria lido na conversa do fornecedor nem a mensagem que teria mandado ao fornecedor. Em sombra ela roda: grava as
-- remessas, as perguntas (modo 'sombra': nunca aparecem no fechamento nem na carona), os sinais do detector com o que faria
-- (para medir a precisão) e a mensagem ao fornecedor que mandaria (agenda_fornecedor_mensagens, estado 'registrada', modo
-- 'sombra') — e nada sai: nenhuma linha na fila do WhatsApp (o _agenda_fornecedor_enfileirar para no modo; o gatilho da
-- fila recusa agenda-fornecedor fora de 'ligado'; o worker confere a janela), nenhuma OS muda (a nota e o detector só
-- mudam a linha em 'ligado'), nenhuma compra, pagamento, OC ou cotação. São essas duas semanas de sombra que o dono confere
-- antes dos OKs de ligar (passos 5, 6 e 7, um OK para cada modo).
--
-- O QUE FAZ:
--   1. modo_material, modo_detector e modo_fornecedor de 'desligado' para 'sombra'. Só sai de 'desligado': NUNCA rebaixa
--      'ligado' (se o dono já tiver ligado à mão, fica ligado) e não mexe no que já está em sombra. Não toca modo_leitura,
--      modo_proposta e modo_vigia (Fases 1 e 2), modo_equipe e modo_diaria (Fase 3), modo_cliente (Fase 5) nem número
--      nenhum de agenda_config. atualizado_em/atualizado_por só mudam na linha que mudou (atualizado_por = null: foi a
--      migration, não uma pessoa).
--   2. O original da previsão das linhas que já tinham previsão ANTES do gatilho do original (20261027100000): a linha de
--      os_material com previsao_ate e sem previsao_original (gravada pelas Fases 1–3 antes da Fase 4 e não mexida depois)
--      ganha previsao_original = a previsão de agora, previsao_original_fonte pela regra do gatilho (a da previsão; sem ela,
--      a do fato informado; sem as duas, 'oc'), previsao_original_em nulo (não se sabe quando foi — a mesma regra que a
--      20261027100000 usou para o original sem fonte) e a marca evidencia.original_herdado = '20261027101000'. Sem isso,
--      agenda_saude().material.previsao_sem_original (um zero obrigatório) fica acima de 0 durante toda a sombra por causa
--      de linhas antigas, e a conferência de sexta não serve. NÃO muda previsão, situação, data nem fonte da linha: só a
--      medição (Fase 6: prometido × real) passa a ter de onde partir. A linha que já tem original não é tocada.
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase db query --linked -e "select modo_leitura, modo_proposta, modo_vigia, modo_equipe, modo_diaria,
--     modo_material, modo_detector, modo_fornecedor from public.agenda_config;
--     select count(*) as linhas_sem_original from public.os_material
--      where previsao_ate is not null and previsao_original is null;"
--   Esperado: leitura, proposta e vigia ligados (Fases 1 e 2); material, detector e fornecedor desligados; e o número de
--   linhas antigas com previsão e sem original (o passo 2 grava o original delas; depois tem de dar 0).
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono):
--   npx supabase db query --linked -f supabase/migrations/20261027101000_agenda_fase4_sombra.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027101000', 'agenda_fase4_sombra');"
--   Depois, rodar email-imap?remessas=1 até "nada a reler" (as notas dos últimos remessa_dias dias viram remessa).
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os modos e as linhas com previsão sem original — tem de ser 0);
--   · npx supabase db query --linked -f supabase/tests/agenda_fase4_pos_deploy.sql
--     (M: os três modos em sombra; S: os zeros obrigatórios de agenda_saude().material — previsao_sem_original = 0 —; N:
--     nada na fila do fornecedor e nenhuma OS mudada pela nota ou pela conversa; a rodada do material nas últimas 2 h, a
--     partir do 1º tique de 15 min).
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE dos modos só pega 'desligado'; o do original só pega a linha sem
-- original). A bancada NÃO aplica este arquivo (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o
-- modo que precisa, e supabase/tests/agenda_fase4_sombra.sql roda este arquivo numa subtransação desfeita (desligado →
-- sombra; de novo não muda nada; ligado fica ligado; o original herdado; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; o que a sombra gravou — remessas, perguntas em teste, sinais e mensagens registradas — fica
-- como rastro e não vale para ninguém; o original herdado sai das linhas que esta migration marcou, e só delas):
--   update public.agenda_config set modo_material = 'desligado', modo_detector = 'desligado', modo_fornecedor = 'desligado', atualizado_em = now(), atualizado_por = null where id and modo_material = 'sombra' and modo_detector = 'sombra' and modo_fornecedor = 'sombra';
--   select set_config('agenda.desfazer_material', 'on', true);
--   update public.os_material set previsao_original = null, previsao_original_fonte = null, evidencia = evidencia - 'original_herdado' where evidencia ->> 'original_herdado' = '20261027101000' and previsao_original_em is null;
--   select set_config('agenda.desfazer_material', '', true);
--
-- (A chave local agenda.desfazer_material é a do desfazer do material: só ela deixa o gatilho do original apagar um
-- original. Ela vale até o fim da transação e é desligada na última linha.)

-- 1. Os modos: de desligado para sombra (nunca rebaixa ligado).
update public.agenda_config
   set modo_material   = case when modo_material = 'desligado' then 'sombra' else modo_material end,
       modo_detector   = case when modo_detector = 'desligado' then 'sombra' else modo_detector end,
       modo_fornecedor = case when modo_fornecedor = 'desligado' then 'sombra' else modo_fornecedor end,
       atualizado_em   = now(),
       atualizado_por  = null
 where id
   and (modo_material = 'desligado' or modo_detector = 'desligado' or modo_fornecedor = 'desligado');

-- 2. O original da previsão das linhas antigas (a regra da fonte é a do gatilho _os_material_previsao_original).
update public.os_material
   set previsao_original       = previsao_ate,
       previsao_original_fonte = coalesce(previsao_fonte,
                                          case when fonte in ('dono', 'fornecedor', 'nfe', 'pix') then fonte end, 'oc'),
       previsao_original_em    = null,
       evidencia               = evidencia || jsonb_build_object('original_herdado', '20261027101000')
 where previsao_ate is not null
   and previsao_original is null;

-- O estado depois (os modos e as linhas com previsão sem original, que tem de ser 0).
select c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_diaria, c.modo_material, c.modo_detector,
       c.modo_fornecedor, c.atualizado_em,
       (select count(*) from public.os_material m where m.previsao_ate is not null and m.previsao_original is null)
         as previsao_sem_original,
       (select count(*) from public.os_material m where m.evidencia ->> 'original_herdado' = '20261027101000')
         as original_herdado
  from public.agenda_config c;
