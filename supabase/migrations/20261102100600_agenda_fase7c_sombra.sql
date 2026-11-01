-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê" e as tarefas do dia), pacote P7: os 4 modos da etapa de desligado
-- para SOMBRA (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§R1 AG7-01, R5.5 linha 8, R5.7-1 e -9, §5.7, §10 passo 3 e "Desfazer", §16.9 "O que o
-- P8 muda no P7", §16.10 passo 3); nomes: fase7-registro.md §1 (os modos modo_habilidade, modo_lider, modo_habilidade_propor e
-- modo_tarefas; "a migration de dado da etapa põe sombra") e §3 (o nº 27 da ordem).
-- Respostas do dono de 29/10 (fase7-padroes.md, AG7-01 "ligar direto quando estiver pronto"): a publicação nunca liga às cegas —
-- este arquivo põe tudo em teste, e cada *ligar* é um UPDATE no MESMO dia, depois do pós-deploy verde e da 1ª rodada em teste sem erro,
-- pelo roteiro de fila-do-dono/fase77c-publicar.md (o "por quê", na linguagem do dono, em fila-do-dono/fase7c-oks.md).
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das migrations de estrutura da 7c
-- (20261102100000 .. 100550, e a correção 20261102100580/100590 se houver) e do deploy de task-automations, ai-agent, erp-mcp e
-- whatsapp-webhook (passos 2 e 3 de fila-do-dono/fase77c-publicar.md).
--
-- POR QUE: as migrations da 7c não mudam o modo. A 20261102100000 (P1) cria modo_habilidade, modo_lider e modo_habilidade_propor e a
-- 20261102100550 (P8) cria modo_tarefas, todos com a linha 'desligado' (o DEFAULT da coluna é 'sombra', mas a linha que já existe fica
-- 'desligado'). Desligado, tudo é o de antes, byte a byte (o motor, a violação, a escada da revisão, o fechamento inteiro, a ficha, o
-- "como foi", a resposta da equipe e as leituras); só o critério de cada alocação nova é gravado, em qualquer modo (é medida). Em
-- sombra:
--   · modo_habilidade e modo_lider: o motor escala como antes, byte a byte nas pessoas, nos dias, nos turnos e nas presenças; a
--     violação "falta quem o serviço pede" do publicado não nasce (só ligado); a escada da revisão da 7a é a de antes. A rodada de quem
--     faz o quê (task-automations, passo 0b2a, 1ª vez no dia a partir de habilidade_hora, 16:10: o tique das 16:15) confere o publicado
--     das próximas habilidade_conferir_semanas semanas com as regras novas e grava, no máximo 6 por dia, as ações de TESTE
--     (executada = false) "Em teste (quem faz o quê): …" — vão às linhas de teste do fechamento (o detalhe, nunca o texto do dono) e ao
--     foco *agenda quem faz* ("Em teste, hoje eu teria mudado: …");
--   · modo_habilidade_propor: na mesma rodada, o gestor propõe o que cada um faz pela grade e pelo técnico que o dono declarou (com a
--     equipe de hoje, só o Alex: "Alex instala sozinho (você disse que ele vem todo dia útil)") numa pergunta só, habilidade:equipe,
--     que nasce EM TESTE: o dono não a vê no fechamento (a linha (n) em teste vai ao detalhe), o prazo de veto não corre (só na
--     pergunta ligada e já mostrada) e a proposta nunca vale; o foco *agenda quem faz* a mostra com "(em teste, eu marcaria: …)";
--   · modo_tarefas: a rodada das etapas (task-automations, passo 0a, a cada tique) sincroniza as etapas das OS com dia marcado nas
--     próximas 2 semanas ou em andamento (os_tarefas, pelo roteiro ou pelas linhas do orçamento), congela o plano do dia em teste
--     (os_tarefas_dia: amanhã às 19:30, hoje no 1º tique), confere o que terminou (o *dia feito* do dono; sem palavra de ninguém, segue o
--     plano) e, 1ª vez no dia a partir de tarefas_hora (16:20: o tique das 16:30), grava a ação de TESTE com o que a ficha de amanhã
--     diria ("Em teste (o que cada um faz): …"); a pendente de 2 dias, o que não cabe até o prazo e a etapa de risco sem quem faça viram
--     ação de teste ou pergunta em teste. A ficha das 19:30, o "como foi" das 17:00 e a leitura da resposta da equipe saem como antes,
--     byte a byte; a linha "Etapas" do fechamento nasce em teste (o detalhe); só as leituras do dono mudam: *agenda* com a OS ganha
--     "Etapas (em teste: a equipe ainda não recebe): …" e "o que o Alex faz amanhã?", " — o que fazer: …".
--   Nada disso muda o plano (as alocações, com o critério), as propostas do motor, as ações que valem, as perguntas ligadas, as
--   etiquetas que valem, a disponibilidade, as mensagens à equipe ou ao cliente, a fila do WhatsApp nem as linhas do fechamento que o
--   dono lê (o teste N do agenda_fase7c_sombra.sql: o mesmo dia de rodadas com e sem este arquivo, sobre o estado de produção de hoje e
--   o de depois dos ligar da 7a e da 7b).
--
-- O QUE FAZ:
--   1. modo_habilidade, modo_lider, modo_habilidade_propor e modo_tarefas: cada um de 'desligado' para 'sombra', só o que está
--      'desligado' (como nasceu). NUNCA rebaixa 'ligado' nem mexe no que já está em 'sombra'.
--   Não toca os modos das Fases 1–6, da 7a e da 7b, nem número nenhum de agenda_config (habilidade_*, lider_espera_max_du, tarefas_*
--   ficam como as migrations de estrutura os criaram: são as respostas do dono, §15 e §16.13 da spec). atualizado_em/atualizado_por só
--   mudam na linha que mudou (atualizado_por = null: foi a migration, não uma pessoa).
--   ATENÇÃO (como a 7b; diferente da 7a, que guarda a data do ligar): a 7c não guarda quando um modo foi ligado; um modo que o dono
--   voltou a desligado DEPOIS de ligar voltaria a teste se este arquivo fosse rodado de novo. Ele roda uma vez (schema_migrations).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked -e "select modo_habilidade, modo_lider, modo_habilidade_propor, modo_tarefas,
--     (select count(*) from public.agenda_etiquetas) as etiquetas, (select count(*) from public.os_tarefas) as etapas
--     from public.agenda_config;"
--   Esperado: desligado nos 4; etapas 0 (com modo_tarefas desligado nada grava etapa); etiquetas 0, ou só as que o dono disse pela
--   conversa (o *grava* da equipe_habilidade grava em qualquer modo: origem dono).
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono, "OK passo 3 da Fase 7c"; ou pelo OK permanente "publicar em teste cada
-- etapa quando o pós-deploy der verde", passo 5 de fila-do-dono/fase77c-publicar.md):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261102100600_agenda_fase7c_sombra.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261102100600', 'agenda_fase7c_sombra');"
--   (o roteiro faz os dois pelo publicar/exec/aplicar.sh, que registra e para na 1ª falha)
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os 4 modos; os das Fases 1–6, da 7a e da 7b, para conferir que não mudaram);
--   · supabase/tests/agenda_fase7c_pos_deploy.sql: M2 "registrada (passo 5 feito)" e C2 com os 4 em sombra;
--   · no 1º tique depois das 16:15 e das 16:30 (um dia útil), publicar/exec/pos-vivo-fase7c.sql: a rodada habilidade do dia e o diário
--     das etapas sem erro.
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado'). A bancada NÃO aplica este arquivo
-- (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e supabase/tests/agenda_fase7c_sombra.sql
-- roda este arquivo numa subtransação desfeita (desligado → sombra nos 4; de novo não muda nada; ligado fica ligado; o efeito sobre o
-- estado de produção; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; nada é apagado). É UM comando só (o bloco abaixo, inteiro, do "with" ao ";"): copie-o para um arquivo e
-- rode com npx supabase@2.111.0 db query --linked -f <arquivo>. Ele só volta o que está em 'sombra' e diz quais ficaram ligados (o que já
-- foi ligado não muda: para parar, o modo dele para 'sombra' primeiro — o DESFAZER de publicar/exec/ligar-fase7c.sql e de
-- ligar-fase7c-tarefas.sql — e depois este). Na MESMA transação, a pergunta EM TESTE que ficou aberta (a habilidade:equipe da proposta
-- do gestor, quando modo_habilidade_propor termina desligado; as tarefa:prazo/tarefa:quem, quando modo_tarefas termina desligado) vira
-- descartada, com o motivo "a 7c voltou a desligado (DESFAZER da 20261102100600)": sem isso, com a 7c desligada, a linha (n) não a leva
-- e ela cairia na pergunta de fato (e) em teste, e o fechamento não seria o de antes. Se a 7c voltar a teste, a rodada pergunta de novo
-- (a aberta some, a proposta fica). O resto do que a sombra calculou — as etapas e o plano do dia em teste, as propostas do gestor que
-- nunca valeram, as ações de teste, as linhas das rodadas — fica como rastro e não vale para ninguém: com os 4 desligados nada disso é
-- lido.
--   with antes as (
--     select c.modo_habilidade, c.modo_lider, c.modo_habilidade_propor, c.modo_tarefas from public.agenda_config c where c.id
--   ), modos as (
--     update public.agenda_config set modo_habilidade = case when modo_habilidade = 'sombra' then 'desligado' else modo_habilidade end, modo_lider = case when modo_lider = 'sombra' then 'desligado' else modo_lider end, modo_habilidade_propor = case when modo_habilidade_propor = 'sombra' then 'desligado' else modo_habilidade_propor end, modo_tarefas = case when modo_tarefas = 'sombra' then 'desligado' else modo_tarefas end, atualizado_em = now(), atualizado_por = null
--      where id and 'sombra' in (modo_habilidade, modo_lider, modo_habilidade_propor, modo_tarefas)
--     returning 1
--   ), perguntas as (
--     update public.agenda_perguntas q set estado = 'descartada', resolvida_motivo = 'a 7c voltou a desligado (DESFAZER da 20261102100600)'
--      where q.estado = 'aberta' and q.modo = 'sombra'
--        and ((q.tipo = 'habilidade' and (select a.modo_habilidade_propor from antes a) <> 'ligado')
--             or (q.tipo = 'tarefa' and (select a.modo_tarefas from antes a) <> 'ligado'))
--     returning q.tipo
--   )
--   select (select count(*) from modos) as modos_desligados, (select count(*) from perguntas) as perguntas_em_teste_descartadas, coalesce((select concat_ws(', ', case when a.modo_habilidade = 'ligado' then 'modo_habilidade' end, case when a.modo_lider = 'ligado' then 'modo_lider' end, case when a.modo_habilidade_propor = 'ligado' then 'modo_habilidade_propor' end, case when a.modo_tarefas = 'ligado' then 'modo_tarefas' end) from antes a where 'ligado' in (a.modo_habilidade, a.modo_lider, a.modo_habilidade_propor, a.modo_tarefas)), 'nenhum') as ficam_ligados;
--
-- (Com os 4 de novo desligados, tudo volta ao de antes da 7c: o motor, a violação, a escada, o fechamento, a ficha, o "como foi", a
-- resposta e as leituras; a rodada de quem faz o quê só roda o prazo — que não age em pergunta em teste — e a medida; a rodada das etapas
-- devolve {rodou: false}. O critério das alocações continua gravado.)

-- 1. Os 4 modos da 7c: de desligado para sombra, cada um só se estiver desligado.
update public.agenda_config
   set modo_habilidade        = case when modo_habilidade = 'desligado' then 'sombra' else modo_habilidade end,
       modo_lider             = case when modo_lider = 'desligado' then 'sombra' else modo_lider end,
       modo_habilidade_propor = case when modo_habilidade_propor = 'desligado' then 'sombra' else modo_habilidade_propor end,
       modo_tarefas           = case when modo_tarefas = 'desligado' then 'sombra' else modo_tarefas end,
       atualizado_em          = now(),
       atualizado_por         = null
 where id
   and 'desligado' in (modo_habilidade, modo_lider, modo_habilidade_propor, modo_tarefas);

-- O estado depois (os 4 modos da 7c; os das Fases 1–6, da 7a e da 7b, para conferir que não mudaram).
select c.modo_habilidade, c.modo_lider, c.modo_habilidade_propor, c.modo_tarefas,
       c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_diaria, c.modo_material, c.modo_cliente,
       c.modo_aprendizado, c.modo_marcar_sozinho, c.modo_vaga_fechamento, c.modo_encaixe_aprovacao, c.modo_revisao_diaria,
       c.modo_compre_ate, c.marcar_sozinho_desde, c.modo_dias, c.modo_dupla, c.modo_sabado, c.modo_cadastro, c.modo_chamar,
       c.atualizado_em
  from public.agenda_config c;
