-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P7b: a rotina da equipe e a diária
-- automática de desligado para SOMBRA, e a lista de quem recebe a rotina (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§3.1 princípio 5, §3.3 d14, §15 P7, §16 passo 4). Decisões do dono de 23/10
-- (Rotina com a equipe; Autonomia): tudo nasce em sombra — calcula e grava o que faria, e nada sai para ninguém.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das 8 migrations de estrutura da
-- Fase 3 (20261026100000..100700), das edge functions e do front (passos 1–3 de fila-do-dono/fase3-oks.md) — e só com a
-- Fase 2 ligada (modo_proposta = 'ligado' há pelo menos 1 semana): sem plano publicado não há ficha nem diária a conferir, e
-- a sombra não teria o que mostrar.
--
-- POR QUE: as migrations da Fase 3 não mudam os modos. modo_equipe nasceu 'desligado' na Fase 1 e modo_diaria nasce
-- 'desligado' na linha (20261026100000): desligados, a rotina das 19:30, 07:45, 09:00 e 17:00 nem roda, e não há como
-- conferir, antes de ligar, o que ela teria mandado ao Roberto nem a diária que teria lançado. Em sombra ela roda: grava a
-- ficha, a confirmação e o "como foi hoje?" que mandaria (agenda_equipe_mensagens, estado 'registrada', modo 'sombra'), lê
-- as respostas sem efeito e registra a diária que lançaria (agenda_acoes tipo 'diaria', executada = false) — e nada sai:
-- nenhuma linha na fila do WhatsApp (o _agenda_equipe_enfileirar para no modo; o gatilho da fila recusa agenda-equipe fora
-- de 'ligado'), nenhum work_shifts, nenhuma resposta ao técnico, e a R10 (o lembrete de técnico de hoje) continua como está.
-- São essas duas semanas de sombra que o dono confere antes dos OKs de ligar (passos 7 e 8).
--
-- O QUE FAZ:
--   1. modo_equipe e modo_diaria de 'desligado' para 'sombra'. Só sai de 'desligado': NUNCA rebaixa 'ligado' (se o dono já
--      tiver ligado à mão, fica ligado) e não mexe no que já está em sombra. Não toca modo_leitura, modo_proposta e
--      modo_vigia (Fases 1 e 2), modo_cliente (Fase 5) nem número nenhum de agenda_config. atualizado_em/atualizado_por só
--      mudam na linha que mudou (atualizado_por = null: foi a migration, não uma pessoa).
--   2. A semente de agenda_equipe_contato pela regra da d14 (a mesma regra da equipe recente da Fase 1, mais o telefone): o
--      favorecido ATIVO da equipe (prestador, diarista ou funcionário — o sócio nunca), com perfil de diária vigente hoje
--      (work_profiles.modo_pagamento = 'diaria'), com telefone (10 dígitos ou mais em payees.phone) e com diária lançada nos
--      agenda_config.equipe_recente_dias dias até a última diária lançada. Entra com recebe_rotina = true e incluido_por
--      'regra'. Quem já está na lista não muda (on conflict do nothing): quem parou ("para de mandar") continua parado, e o
--      que o dono incluiu continua dele. Ninguém sai por aqui. Nome novo, depois disso, só pelo dono.
--
-- QUEM ENTRA (conferido por SELECT em 24/10/2026, sql/p7b_semente_contato, sem expor telefone; a última diária lançada em
-- produção é sex 23/10):
--   · Roberto — prestador, perfil de diária vigente, com telefone, última diária 23/10: ENTRA;
--   · João — prestador, perfil de diária vigente, diária em 17/10, SEM telefone no cadastro: fica de fora (o fechamento das
--     17:30 pergunta o dia dele ao dono);
--   · Mickael — com telefone, mas a última diária é de 18/09 (fora da equipe recente pela regra, não pelo nome): fica de fora;
--   · o dono (sócio): nunca.
--   Se o dono lançar diárias ou cadastrar telefone antes de aplicar, o resultado muda (é regra, não lista): o SELECT do fim
--   mostra quem entrou, e supabase/tests/agenda_fase3_pos_deploy.sql (E) confere que todo 'regra' cumpre a regra.
--
-- ORDEM DE LIGAR (fila-do-dono/fase3-oks.md): Fase 1 no ar → Fase 2 no ar com a proposta ligada há 1 semana → 1. as 8
-- migrations de estrutura da Fase 3 → 2. edge functions → 3. front → 4. ESTA → 5. duas semanas de sombra conferidas →
-- 6. avisar o Roberto → 7. modo_diaria = 'ligado' (OK nomeado: é dinheiro) → 8. modo_equipe = 'ligado' (OK nomeado: é
-- mensagem a uma pessoa; numa segunda ou terça antes das 17:00) → 9. desligar = voltar a 'sombra'.
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar e quem vai entrar na lista):
--   npx supabase db query --linked -e "select modo_proposta, modo_vigia, modo_equipe, modo_diaria, modo_cliente,
--     equipe_recente_dias from public.agenda_config; select split_part(p.name, ' ', 1) as nome,
--     exists (select 1 from public.agenda_equipe_contato c where c.payee_id = p.id) as ja_na_lista
--     from public.payees p where p.active and p.kind in ('prestador', 'diarista', 'funcionario')
--     and length(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')) >= 10
--     and exists (select 1 from public.work_profiles w where w.payee_id = p.id and w.modo_pagamento = 'diaria'
--                 and w.vigencia_inicio <= public._hoje_brt() and (w.vigencia_fim is null or w.vigencia_fim >= public._hoje_brt()))
--     and exists (select 1 from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
--                 where w.payee_id = p.id and ws.tipo = 'diaria' and ws.fracao > 0
--                   and ws.data >= (select max(x.data) from public.work_shifts x where x.tipo = 'diaria' and x.fracao > 0
--                                    and x.data <= public._hoje_brt())
--                                  - ((select c.equipe_recente_dias from public.agenda_config c) - 1));"
--   Esperado em 24/10: proposta ligado (passo 0), equipe desligado, diária desligado, cliente desligado; 1 nome (Roberto).
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono):
--   npx supabase db query --linked -f supabase/migrations/20261026101000_agenda_fase3_sombra.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026101000', 'agenda_fase3_sombra');"
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os modos e a lista da rotina, sem telefone);
--   · npx supabase db query --linked -f supabase/tests/agenda_fase3_pos_deploy.sql
--     (C: modo_equipe e modo_diaria = sombra; E: a lista pela regra; N: nada na fila da equipe, nenhuma diária lançada pela
--     agenda; S: os zeros obrigatórios de agenda_saude; a rotina rodou nas últimas 2 h, a partir do 1º tique de 15 min).
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado'; a semente é on conflict do nothing). A bancada NÃO
-- aplica este arquivo (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e
-- supabase/tests/agenda_fase3_sombra.sql roda este arquivo numa subtransação desfeita (desligado → sombra; de novo não muda
-- nada; ligado fica ligado; a semente pela regra; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; o que a sombra gravou — mensagens registradas e diárias em teste — fica como rastro e não vale
-- para ninguém; quem entrou pela regra fica marcado como parado, com o motivo, e não é apagado):
--   update public.agenda_config set modo_equipe = 'desligado', modo_diaria = 'desligado', atualizado_em = now(),
--          atualizado_por = null where id and modo_equipe = 'sombra' and modo_diaria = 'sombra';
--   update public.agenda_equipe_contato set recebe_rotina = false, parou_em = now(),
--          parou_motivo = 'desfeita a migration 20261026101000' where incluido_por = 'regra' and recebe_rotina;
--
-- Para INCLUIR de novo depois de desfazer (só o dono decide nome na lista):
--   update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = '<id>';

-- 1. Os modos: de desligado para sombra (nunca rebaixa ligado).
update public.agenda_config
   set modo_equipe    = case when modo_equipe = 'desligado' then 'sombra' else modo_equipe end,
       modo_diaria    = case when modo_diaria = 'desligado' then 'sombra' else modo_diaria end,
       atualizado_em  = now(),
       atualizado_por = null
 where id
   and (modo_equipe = 'desligado' or modo_diaria = 'desligado');

-- 2. A semente da lista da rotina pela regra da d14 (só quem ainda não está nela).
insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por)
select p.id, true, 'regra'
  from public.payees p
 cross join (select c.equipe_recente_dias,
                    (select max(ws.data) from public.work_shifts ws
                      where ws.tipo = 'diaria' and ws.fracao > 0 and ws.data <= public._hoje_brt()) as ultima
               from public.agenda_config c
              where c.id) u
 where u.ultima is not null
   and p.active
   and p.kind in ('prestador', 'diarista', 'funcionario')
   and length(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')) >= 10
   and exists (select 1 from public.work_profiles w
                where w.payee_id = p.id and w.modo_pagamento = 'diaria'
                  and w.vigencia_inicio <= public._hoje_brt()
                  and (w.vigencia_fim is null or w.vigencia_fim >= public._hoje_brt()))
   and exists (select 1 from public.work_shifts ws
                 join public.work_profiles w on w.id = ws.work_profile_id
                where w.payee_id = p.id and ws.tipo = 'diaria' and ws.fracao > 0
                  and ws.data between u.ultima - (u.equipe_recente_dias - 1) and u.ultima)
on conflict (payee_id) do nothing;

-- O estado depois (os modos e a lista da rotina, sem telefone).
select c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_diaria, c.modo_cliente, c.atualizado_em,
       (select coalesce(string_agg(split_part(p.name, ' ', 1) || ' (' || l.incluido_por
                                   || case when l.recebe_rotina then '' else ', parado' end || ')', ', '
                                   order by p.name), 'ninguém')
          from public.agenda_equipe_contato l join public.payees p on p.id = l.payee_id) as lista_da_rotina
  from public.agenda_config c;
