-- Agenda de Produção, Fase 1, pacote P7: a PRIMEIRA semeadura da disponibilidade da equipe (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§5.2, §10 passo 2). Depende de 20261024160000, 160100 e 160200.
--
-- ═══ GRAVA DADO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica POR ÚLTIMO, depois das 7 migrations
-- de estrutura da Fase 1 (160000..160600).
--
-- POR QUE: a capacidade que a agenda diz ao dono ("~5,4 diárias de equipe por semana, sem contar você") é a soma do
-- padrão de cada pessoa em agenda_disponibilidade. Sem esta semeadura a tabela nasce vazia e toda leitura diz que
-- ninguém da equipe tem padrão: a fila não anda e o "livre de verdade" não sai.
--
-- O QUE FAZ: só chama public.agenda_disponibilidade_semear() (160200), com o dia de Brasília de hoje, e mostra o
-- resultado. A função mede as diárias lançadas das últimas agenda_config.medicao_semanas semanas até a última diária
-- e cria uma linha por pessoa e dia da semana (origem 'historico'). NUNCA toca linha do dono ('dono'), do diarista
-- nem do agente. Nenhum número vem daqui: está tudo em agenda_config e nas diárias.
--
-- ESPERADO (conferido por SELECT em 24/10/2026: a última diária lançada em produção é sáb 17/10, nenhuma depois;
-- os números são os da carteira de 23/10, spec §5.2, que a fixture da bancada reproduz):
--   · Roberto: 5 linhas — seg 0,60 (3 de 5), ter 0,83 (5 de 6), qua/qui/sex 1,00 → 4,43 por semana;
--   · João: 4 linhas — ter 0,50, qua 0,67, qui 0,67, sex 0,50 (segunda 0 de 1: sem linha) → 2,33;
--   · Mickael: nada (última diária 18/09: fora da equipe recente pela regra, não pelo nome);
--   · o dono (sócio): nada (ele entra quando disser o padrão dele, origem 'dono').
--   → semeadas = 9, capacidade 6,77 × carga_max 0,80 = 5,41 comprometível ("~5,4").
--   Se o dono lançar diárias antes de aplicar, os números mudam (é medida, não constante): o resultado mostra
--   as linhas criadas, e supabase/tests/agenda_fase1_pos_deploy.sql confere a regra, não estes números.
--
-- ORDEM DE LIGAR (spec §10): Fase 0 aplicada (150000, 150100, 150200 e a faxina 153000 — em produção desde 23/10)
-- → 160000..160600 → ESTA → edge functions (task-automations, ai-agent, erp-mcp, whatsapp-webhook,
-- ai-daily-briefing) → front.
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono):
--   npx supabase db query --linked -f supabase/migrations/20261024161000_agenda_fase1_semente_dados.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024161000', 'agenda_fase1_semente_dados');"
--
-- PROVA (depois de aplicar, só leitura):
--   npx supabase db query --linked -f supabase/tests/agenda_fase1_pos_deploy.sql
--   (S1–S3: quem tem padrão é exatamente a equipe recente; ninguém fora dela; capacidade = Σ frequência × carga_max)
--
-- IDEMPOTENTE: a função não mexe em quem já tem o mesmo padrão (mantidas); rodar de novo no mesmo dia devolve
-- semeadas = 0. Rodar depois de novas diárias troca o padrão medido (substituidas), deixando o rastro em
-- substituida_em — é o mesmo que a semeadura faria, não um efeito colateral.
--
-- DESFAZER (só se o dono pedir): as linhas desta semeadura são as 'historico' vigentes; marcar substituida_em
-- = now() nelas zera a capacidade medida sem apagar nada:
--   update public.agenda_disponibilidade set substituida_em = now()
--    where origem = 'historico' and substituida_em is null;

select r ->> 'semeadas'      as semeadas,
       r ->> 'mantidas'      as mantidas,
       r ->> 'substituidas'  as substituidas,
       r ->> 'ultima_diaria' as ultima_diaria,
       r -> 'janela'         as janela,
       coalesce(r ->> 'motivo', '') as motivo,
       r -> 'linhas'         as linhas
  from (select public.agenda_disponibilidade_semear() as r) s;
