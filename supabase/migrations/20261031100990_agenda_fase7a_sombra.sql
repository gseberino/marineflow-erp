-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P7: os 5 modos do gestor da agenda de desligado para
-- SOMBRA (o dado).
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R1 AG7-01, §3.1 item 4, §9 P7, §10 passo 3); nomes: fase7-registro.md §1
-- (os modos marcar, vaga, encaixe, revisao e compre_ate; "a migration de dado da etapa põe sombra") e §3 (o nº 14 da ordem).
-- Respostas do dono de 29/10 (fase7-padroes.md, AG7-01 "ligar direto quando estiver pronto"): a publicação nunca liga às cegas
-- — este arquivo põe tudo em teste, e o *ligar* é um UPDATE no MESMO dia, depois do pós-deploy verde, da 1ª rodada do gestor sem
-- erro e do cadastro da equipe certo (AG7-03), pelo roteiro de fila-do-dono/fase7a-oks.md.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono. Aplica DEPOIS das 13 migrations de estrutura da 7a
-- (20261031100000..100950) e do deploy de ai-agent, erp-mcp e ai-daily-briefing (passos 1 e 2 de fila-do-dono/fase7a-oks.md).
--
-- POR QUE: as migrations da 7a não mudam o modo. A 20261031100000 (P1) cria os 5 modos com a linha 'desligado' (o DEFAULT da
-- coluna é 'sombra', mas a linha que já existe fica 'desligado'). Desligado, o job agenda-gestor não faz nada ({rodou: false}),
-- o fechamento não tem a linha do gestor e o foco *agenda gestor* diz que ele está desligado. Em sombra, todo dia útil às 16:52 o
-- gestor faz a conta do "eu marcaria assim" (o mesmo motor, com as regras ligadas só dentro da simulação) e grava no diário dele;
-- o fechamento das 17:30 mostra essa linha ao dono, e o foco mostra tudo — e nada muda no que a agenda faz: o portão das regras
-- (_agenda_gestor_regra) é falso fora da simulação, nenhuma alocação, proposta, ação ou mensagem nasce do gestor, e a vaga da
-- agenda no fechamento só aparece no detalhe (vaga_teria).
--
-- O QUE FAZ:
--   1. modo_marcar_sozinho, modo_vaga_fechamento, modo_encaixe_aprovacao, modo_revisao_diaria e modo_compre_ate: cada um de
--      'desligado' para 'sombra', só a linha que está 'desligado' E nunca foi ligada (marcar_sozinho_desde nulo: o ligar grava a
--      data). NUNCA rebaixa 'ligado' nem mexe no que já está em 'sombra'; não religa em teste a linha que o dono desligou depois
--      de ter ligado (marcar_sozinho_desde preenchido: "parar" vale).
--   Não toca os modos das Fases 1–6, a lista das regras (marcar_regras), *gestor, só propor* nem número nenhum de agenda_config.
--   atualizado_em/atualizado_por só mudam na linha que mudou (atualizado_por = null: foi a migration, não uma pessoa).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked -e "select modo_marcar_sozinho, modo_vaga_fechamento, modo_encaixe_aprovacao,
--     modo_revisao_diaria, modo_compre_ate, marcar_sozinho_desde from public.agenda_config;"
--   Esperado: desligado nos 5; marcar_sozinho_desde nulo.
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK nomeado do dono, "OK passo 3 da Fase 7a"):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100990_agenda_fase7a_sombra.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100990', 'agenda_fase7a_sombra');"
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os 5 modos);
--   · agenda_saude(): a chave gestor com os modos em sombra, zeros_ok true e erros_24h 0 (o teste só leitura do pós-deploy da
--     etapa, supabase/tests/agenda_fase7a_pos_deploy.sql, fica com o último pacote da 7a: ele confere as 13 migrations juntas);
--   · no 1º dia útil depois das 16:52, a linha de agenda_gestor_dia do dia com o texto_sombra.
--
-- IDEMPOTENTE: rodar de novo não muda nada (cada UPDATE só pega 'desligado' com marcar_sozinho_desde nulo). A bancada NÃO aplica
-- este arquivo (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e
-- supabase/tests/agenda_fase7a_sombra.sql roda este arquivo numa subtransação desfeita (desligado → sombra nos 5; de novo não muda
-- nada; ligado fica ligado; o desligado depois de ligar fica; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; o que a sombra calculou — o diário do gestor, agenda_gestor_dia — fica como rastro e não vale para
-- ninguém; nada é apagado). É UM comando só (o bloco do $desfaz$ abaixo, inteiro): copie-o para um arquivo e rode com
-- npx supabase@2.111.0 db query --linked -f <arquivo>. Ele só volta o que está em 'sombra': o que já foi ligado não muda (para
-- parar o que está ligado, "tudo na hora" da §10: *gestor, só propor*, ou o modo dele para 'sombra').
--   do $desfaz$
--   begin
--     update public.agenda_config set modo_marcar_sozinho = case when modo_marcar_sozinho = 'sombra' then 'desligado' else modo_marcar_sozinho end, modo_vaga_fechamento = case when modo_vaga_fechamento = 'sombra' then 'desligado' else modo_vaga_fechamento end, modo_encaixe_aprovacao = case when modo_encaixe_aprovacao = 'sombra' then 'desligado' else modo_encaixe_aprovacao end, modo_revisao_diaria = case when modo_revisao_diaria = 'sombra' then 'desligado' else modo_revisao_diaria end, modo_compre_ate = case when modo_compre_ate = 'sombra' then 'desligado' else modo_compre_ate end, atualizado_em = now(), atualizado_por = null where id and 'sombra' in (modo_marcar_sozinho, modo_vaga_fechamento, modo_encaixe_aprovacao, modo_revisao_diaria, modo_compre_ate);
--   end
--   $desfaz$;
--
-- (Com os 5 de novo desligados, o job agenda-gestor volta a {rodou: false}, a linha do gestor sai do fechamento e o foco *agenda
-- gestor* diz que ele está desligado.)

-- 1. Os 5 modos do gestor: de desligado (nunca ligado) para sombra, cada um só se estiver desligado.
update public.agenda_config
   set modo_marcar_sozinho    = case when modo_marcar_sozinho = 'desligado' then 'sombra' else modo_marcar_sozinho end,
       modo_vaga_fechamento   = case when modo_vaga_fechamento = 'desligado' then 'sombra' else modo_vaga_fechamento end,
       modo_encaixe_aprovacao = case when modo_encaixe_aprovacao = 'desligado' then 'sombra' else modo_encaixe_aprovacao end,
       modo_revisao_diaria    = case when modo_revisao_diaria = 'desligado' then 'sombra' else modo_revisao_diaria end,
       modo_compre_ate        = case when modo_compre_ate = 'desligado' then 'sombra' else modo_compre_ate end,
       atualizado_em          = now(),
       atualizado_por         = null
 where id
   and marcar_sozinho_desde is null
   and 'desligado' in (modo_marcar_sozinho, modo_vaga_fechamento, modo_encaixe_aprovacao, modo_revisao_diaria, modo_compre_ate);

-- O estado depois (os 5 modos e a data do ligar; o resto dos modos para conferir que não mudou).
select c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_diaria, c.modo_material, c.modo_cliente,
       c.modo_aprendizado, c.modo_marcar_sozinho, c.modo_vaga_fechamento, c.modo_encaixe_aprovacao, c.modo_revisao_diaria,
       c.modo_compre_ate, c.marcar_sozinho_desde, c.gestor_so_propor, c.atualizado_em
  from public.agenda_config c;
