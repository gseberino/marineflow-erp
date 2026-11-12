-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P7: o dado. Os 4 interruptores da etapa de desligado para SOMBRA (em
-- teste) e a hora de onde as marcações passam a ser medidas. Molde: 20261111100900_agenda_fase7e_dado.sql (o dado da 7e).
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md §5.8 com R9.2 (o dado é a 20261112100990, depois das correções), R9.4-2 (marcacoes_desde: nada de antes entra
-- na medida), R9.6 (o freio), R9.13 (a linha P7) e R9.14 (a §10 reescrita: publicar em teste pelo OK permanente, cada *ligar* pelo OK nomeado). Notas:
-- notas-fase7g.md, seções P1 a P7. O roteiro dos OKs em linguagem do dono: fila-do-dono/fase7g-oks.md.
-- Resposta do dono (fase7-padroes.md, o Diário): AG7-01 "Ligar direto quando estiver pronto" — a publicação nunca liga às cegas: este arquivo põe em teste, e cada
-- *ligar* é um UPDATE no dia, com o OK nomeado, depois do pós-deploy verde e de 1 rodada explicar sem erro (R9.14); AG7-01 não passa por cima do freio.
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, coluna, DEFAULT, policy ou cron)
--   · os 4 modos em teste: o OK permanente do dono ("OK publicar em teste cada etapa quando o pós-deploy der verde").
-- NÃO APLICADA. Este arquivo existe para revisão. Aplica DEPOIS das 7 migrations de estrutura da 7g (20261112100000, 100100, 100200, 100300, 100400, 100500 e
-- 100600) e do deploy de task-automations, ai-agent e erp-mcp e do front. O P5b (20261112100450, "o espera o seu ok") ainda não existe: quando existir, ele aplica
-- antes deste e é quem põe ok_marcacao em veto_tipos (a §5.8 punha aqui; hoje o CHECK de veto_tipos recusaria um tipo de pergunta que não existe).
--
-- A TRAVA (o bloco "do" logo abaixo, antes de qualquer mudança; a migration falha inteira e nada muda): recusa se faltar o código da 7g no banco (uma função de
-- cada uma das 7 de estrutura; da 100600, os focos novos em agenda_ver). Em teste sem o código, a saúde e as rodadas diriam "em teste" de algo que não roda.
--
-- EM SOMBRA (com o freio de hoje, gestor_so_propor = true; e mesmo sem ele): nada sai a ninguém, e o motor, a vigia, a quinta e os textos ao dono, à equipe e ao
-- cliente são os de antes, byte a byte (o replay da carteira real do P7, f7g/p7/real.mjs). O que muda, de propósito, e só no que ninguém lê sem pedir:
--   · modo_porque: cada marcação nova grava o porquê (as suposições, o degrau e a zona na alocação e na ação; o item da proposta ganha a chave porque). A tela e
--     o cartão não mostram (só com ligado); a rodada explicar (depois de explicar_hora) registra as marcações do gestor e o desfecho de cada uma (agenda_marcacoes);
--   · modo_rebaixar: a rodada explicar mede, por tipo de OS, se o dono corrigiria o bastante para "esperar o seu ok"; só grava
--     agenda_tipos_os com teria = espera_ok (o nível nunca muda: isso é do P5b, com o ok do dono);
--   · modo_placar: a rodada explicar da quinta guarda o placar da semana em agenda_placar_semanas; a mensagem da quinta é a de antes;
--   · modo_explicar: as leituras (*como pensou*, *por que*, *placar* pela conversa; o *livre* de 4 semanas; o "se aprovar hoje" pelo encaixe) respondem o de antes
--     e calculam o novo em dados.teste, que o dono não lê;
--   · marcacoes_desde: a rodada explicar mede as marcações do gestor a partir da hora deste dado (as de antes, sem o porquê, não entram: R9.4-2).
--
-- O QUE FAZ:
--   1. modo_porque, modo_explicar, modo_placar e modo_rebaixar: cada um de 'desligado' para 'sombra', só o que está 'desligado' (como a 20261112100000 os deixou na
--      linha). NUNCA rebaixa 'ligado' nem mexe no que já está em 'sombra'. Nenhum interruptor é LIGADO aqui.
--   2. marcacoes_desde: a hora deste dado, só se ainda está nula (nunca move uma hora já gravada).
--   Não toca o freio (gestor_so_propor), veto_tipos, nenhum modo das Fases 1–6, de 7a–7f, nem os números da 7g (são da 20261112100000). atualizado_em/atualizado_por
--   só mudam se a linha mudou (atualizado_por = null: foi a migration, não uma pessoa).
--   ATENÇÃO (como a 7e): a 7g não guarda quando um modo foi ligado; um modo que o dono voltou a desligado DEPOIS de ligar voltaria a teste se este arquivo rodasse de
--   novo. Ele roda uma vez (schema_migrations).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked "select modo_porque, modo_explicar, modo_placar, modo_rebaixar, marcacoes_desde, gestor_so_propor from public.agenda_config;"
--   Esperado: desligado nos 4; marcacoes_desde nula; gestor_so_propor true (o freio de hoje).
--
-- APLICAR (pelo OK permanente):
--   PONTA=<a ponta> LOCK_TIMEOUT=5s bash publicar/exec/aplicar.sh 20261112100990_agenda_fase7g_modos   (aplica, registra em schema_migrations e para na 1ª falha)
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os 4 modos e marcacoes_desde; o freio e os modos de antes, para conferir que não mudaram);
--   · no dia seguinte, depois de explicar_hora: a rodada explicar sem erro (app_error_logs explicar:%) e agenda_saude() -> 'explicar' com zeros_ok.
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado' e a hora nula; sem nenhum, nem a hora). A bancada NÃO aplica este arquivo
-- (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e supabase/tests/agenda_fase7g_modos.sql o roda numa subtransação
-- desfeita (desligado → sombra nos 4 e a hora; o resto da linha igual; de novo não muda nada; ligado fica ligado; a hora gravada fica; a trava sem o código; o
-- DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; nada é apagado). É UM comando (do "with" ao ";"): copie as linhas entre as marcas para um arquivo e rode com
-- npx supabase@2.111.0 db query --linked -f <arquivo>. Ele só volta o que está em 'sombra' nos 4, e diz quais modos ficaram ligados: para parar um ligado, ele vai a
-- 'sombra' primeiro (o *desligar* do roteiro) e depois este. marcacoes_desde fica (R9.14): o que a sombra mediu (agenda_marcacoes, agenda_tipos_os, agenda_placar_semanas
-- e o porquê gravado nas alocações) fica como rastro; com os 4 desligados, a rodada explicar não roda e nada novo é gravado. Com os 4 já desligados, não muda nada
-- (nem a hora).
-- DESFAZER-INICIO
--   with antes as (
--     select c.modo_porque, c.modo_explicar, c.modo_placar, c.modo_rebaixar from public.agenda_config c where c.id
--   ), linha as (
--     update public.agenda_config set modo_porque = case when modo_porque = 'sombra' then 'desligado' else modo_porque end, modo_explicar = case when modo_explicar = 'sombra' then 'desligado' else modo_explicar end, modo_placar = case when modo_placar = 'sombra' then 'desligado' else modo_placar end, modo_rebaixar = case when modo_rebaixar = 'sombra' then 'desligado' else modo_rebaixar end, atualizado_em = now(), atualizado_por = null
--      where id and 'sombra' in (modo_porque, modo_explicar, modo_placar, modo_rebaixar)
--     returning 1
--   )
--   select (select count(*) from linha) as linha_mudou, coalesce((select concat_ws(', ', case when a.modo_porque = 'ligado' then 'modo_porque' end, case when a.modo_explicar = 'ligado' then 'modo_explicar' end, case when a.modo_placar = 'ligado' then 'modo_placar' end, case when a.modo_rebaixar = 'ligado' then 'modo_rebaixar' end) from antes a where 'ligado' in (a.modo_porque, a.modo_explicar, a.modo_placar, a.modo_rebaixar)), 'nenhum') as ficam_ligados;
-- DESFAZER-FIM
-- (Com os 4 de novo desligados, tudo volta ao de antes do dado: o motor sem gravar o porquê, a rodada explicar sem rodar, as leituras sem o dados.teste. As funções
-- da 7g ficam no banco: com os 4 desligados, elas dão o de antes da 7g.)

-- 0. A trava: o código da 7g no banco.
do $trava$
declare
  v_falta text[] := array[]::text[];
begin
  select coalesce(array_agg(f order by o), array[]::text[]) into v_falta
    from unnest(array['public._agenda_quem_marcou(text, text)', 'public._agenda_suposicoes_da_os(uuid, jsonb, jsonb, date)',
                      'public.agenda_como_pensei(date, date, timestamptz)', 'public._agenda_encaixe_simulado(jsonb, date)',
                      'public.agenda_explicar_rodar(date, timestamptz)', 'public.agenda_placar(date, date, timestamptz)']) with ordinality u(f, o)
   where to_regprocedure(f) is null;
  if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)')
                    and p.prosrc like '%-- FASE 7g: (7g P7%') then
    v_falta := v_falta || 'os focos novos em public.agenda_ver (20261112100600)'::text;
  end if;
  if cardinality(v_falta) > 0 then
    raise exception 'O dado 20261112100990 vem depois das 7 migrations de estrutura da 7g: faltam %. Nada mudou.', array_to_string(v_falta, ', ') using errcode = 'P0001';
  end if;
end
$trava$;

-- 1. Os 4 modos da etapa: de desligado para sombra, cada um só se estiver desligado; a hora da medida, só se ainda está nula.
update public.agenda_config
   set modo_porque     = case when modo_porque = 'desligado' then 'sombra' else modo_porque end,
       modo_explicar   = case when modo_explicar = 'desligado' then 'sombra' else modo_explicar end,
       modo_placar     = case when modo_placar = 'desligado' then 'sombra' else modo_placar end,
       modo_rebaixar   = case when modo_rebaixar = 'desligado' then 'sombra' else modo_rebaixar end,
       marcacoes_desde = coalesce(marcacoes_desde, now()),
       atualizado_em   = now(),
       atualizado_por  = null
 where id
   and ('desligado' in (modo_porque, modo_explicar, modo_placar, modo_rebaixar) or marcacoes_desde is null);

-- O estado depois (os 4 modos da 7g e a hora da medida, o freio; os modos de antes, para conferir que não mudaram).
select c.modo_porque, c.modo_explicar, c.modo_placar, c.modo_rebaixar, c.marcacoes_desde, c.gestor_so_propor, c.gestor_so_propor_em, c.modo_leitura, c.modo_proposta,
       c.modo_vigia, c.modo_marcar_sozinho, c.modo_veto, c.modo_lote_dono, c.modo_vies, c.modo_promessa, c.atualizado_em
  from public.agenda_config c;
