-- Agenda de Produção, Fase 2 ("O gestor de agenda"), pacote P6: os dois modos novos de desligado para SOMBRA (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase2.md (§3.1 princípio 6, §15 P6, §16 passo 4). Decisões do dono de 23/10
-- (Autonomia): a agenda nasce em sombra — calcula e grava o que faria, e não muda nada para ninguém.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das 6 migrations de estrutura da
-- Fase 2 (20261025100000..100500), das edge functions e do front (passos 1–3 de fila-do-dono/fase2-oks.md).
--
-- POR QUE: as migrations da Fase 2 não mudam os modos (agenda_config.modo_proposta e modo_vigia nasceram 'desligado' na
-- Fase 1). Desligado, a vigia de 15 min nem roda: não há como conferir, antes de ligar, o que a agenda teria feito. Em
-- sombra ela roda, monta a semana na quinta, grava as propostas (modo = 'sombra'), as perguntas e as ações que faria
-- (executada = false) — e nada muda para ninguém: nenhuma alocação vigente, nenhum status de OS, nenhuma data em
-- scheduled_*, nenhuma mensagem; o fechamento das 17:30 sai byte a byte como hoje (o que a agenda diria vai para
-- resumo_tarde.detalhe.agenda). São essas duas semanas de sombra que o dono confere antes do OK de ligar (passo 5).
--
-- O QUE FAZ: modo_proposta e modo_vigia de 'desligado' para 'sombra'. Só sai de 'desligado': NUNCA rebaixa 'ligado'
-- (se o dono já tiver ligado à mão, fica ligado) e não mexe no que já está em sombra. Não toca modo_leitura (é da
-- Fase 1), modo_equipe nem modo_cliente (Fases 3 e 5), nem número nenhum de agenda_config. atualizado_em/atualizado_por
-- só mudam na linha que mudou (atualizado_por = null: foi a migration, não uma pessoa).
--
-- ORDEM DE LIGAR (fila-do-dono/fase2-oks.md): 0. Fase 1 no ar → 1. 20261025100000..100500 → 2. edge functions →
-- 3. front → 4. ESTA → 5. duas semanas de sombra conferidas → 6. modo_proposta = 'ligado' (numa quinta antes das
-- 16:30) → 7. modo_vigia = 'ligado' (1 semana depois) → 8. desligar = voltar a 'sombra'.
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono):
--   npx supabase db query --linked -f supabase/migrations/20261025101000_agenda_fase2_sombra.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261025101000', 'agenda_fase2_sombra');"
--
-- PROVA (depois de aplicar, só leitura):
--   npx supabase db query --linked -f supabase/tests/agenda_fase2_pos_deploy.sql
--   (C: modo_proposta e modo_vigia = sombra; V: a vigia rodou nas últimas 2 h, a partir do 1º tique de 15 min)
--
-- IDEMPOTENTE: rodar de novo não muda nada (o WHERE só pega 'desligado'). A bancada NÃO aplica este arquivo
-- (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa.
--
-- DESFAZER (só se o dono pedir): voltar a 'desligado' para os dois. O que a sombra gravou (propostas, perguntas e ações
-- de sombra) fica como rastro e não vale para ninguém:
--   update public.agenda_config set modo_proposta = 'desligado', modo_vigia = 'desligado', atualizado_em = now(),
--          atualizado_por = null where id and modo_proposta = 'sombra' and modo_vigia = 'sombra';

update public.agenda_config
   set modo_proposta  = case when modo_proposta = 'desligado' then 'sombra' else modo_proposta end,
       modo_vigia     = case when modo_vigia    = 'desligado' then 'sombra' else modo_vigia    end,
       atualizado_em  = now(),
       atualizado_por = null
 where id
   and (modo_proposta = 'desligado' or modo_vigia = 'desligado');

select modo_leitura, modo_proposta, modo_vigia, modo_equipe, modo_cliente, versao_plano, atualizado_em
  from public.agenda_config;
