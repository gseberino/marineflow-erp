-- Agenda de Produção, Fase 7, etapa 7f ("falar só o que importa"), pacote P9 (o final): os 3 modos da equipe e do cliente (o previsto e a mudança, o convite e as
-- camadas do cliente) de desligado para SOMBRA (o dado). Molde: 20261109100900_agenda_fase7f_sombra.sql (o dado do P8, os outros 3 modos da 7f).
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md §5.8 e R8.2 (o dado nasce depois das estruturas dele), R8.6 (o freio), R8.8 (o peso), R8.13 e R8.14 (publicar em
-- teste pelo OK permanente, cada *ligar* pelo OK nomeado). Nomes: fase7-registro.md §1 (os 6 interruptores da 7f). Notas: notas-fase7f.md, seções P5, P6, P8 e P9.
-- Respostas do dono (diario-0811/respostas): ag7-ligar (AG7-01) "Ligar direto quando estiver pronto" — a publicação nunca liga às cegas: este arquivo põe em teste, e
-- cada *ligar* é um UPDATE no dia, pelo publicar/exec/ligar-fase7f.sql, depois do pós-deploy verde e do que a saúde mede (o "por quê", na linguagem do dono, em
-- fila-do-dono/fase7f-oks.md, itens 9, 10 e 11).
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão. Aplica DEPOIS de 20261109101000 (P5, a equipe), 20261109101100 (P6, o cliente) e 20261109101200 (P9, a semana que
-- mudou e a saúde): passo 2 de fila-do-dono/fase77f-publicar-final.md. Nenhuma função de borda muda com P5, P6 e P9.
--
-- A TRAVA (o bloco "do" logo abaixo, antes de qualquer UPDATE; a migration falha inteira e nada muda):
--   · recusa se algum dos 3 estiver LIGADO: o dado põe em teste e nunca rebaixa um ligado (ligado só pelo ligar-fase7f.sql, com o OK nomeado). Em 'sombra' ele já
--     está em teste, e o arquivo segue (rodar 2× é o mesmo que 1×);
--   · recusa se faltar alguma das funções do P5 (os 4 passos da equipe), do P6 (_agenda_cliente_semana e _agenda_cliente_camada) ou do P9 (_agenda_cliente_semana_mudou):
--     em teste sem o código, a saúde diria "em teste" de algo que não roda.
--
-- EM SOMBRA (com o freio de hoje, gestor_so_propor = true; e mesmo sem ele): nada sai a ninguém, e o que a equipe, o cliente e o dono recebem é o de antes, byte a byte.
--   · modo_equipe_previsto (o previsto da quinta e a mudança): a rodada comunicar registra em teste (a chave com ":sombra", estado registrada, nada à fila) — e hoje nem
--     isso: ninguém da rotina tem telefone (os passos devolvem {pulado: sem_telefone} na 1ª leitura).
--   · modo_equipe_convite: o mesmo; o Alex (o único da rotina) é o técnico declarado e nunca é convidado; o convite vencido só conta (teria).
--   · modo_cliente_camadas: o passo semana da rodada do cliente passa a rodar uma vez por dia, no 1º tique a partir de cliente_hora_preparo (17:00), e registra em teste
--     a semana da OS marcada pela estimativa (a ação nasce contada: fica no foco do cliente, fora do fechamento e do aviso); o M1, o M3/M7 e o M6 seguem os de hoje (as
--     regras novas só valem com as camadas ligadas de verdade). Hoje nenhuma OS da carteira recebe semana (a única com dia marcado já começou).
--   O que o dono passa a ver "em teste": a saúde da comunicação com os números da equipe e do cliente (agenda_saude().comunicacao.numeros.equipe/cliente) e, no foco
--   *agenda clientes*, "Ainda em teste: … semana prevista" e as ações "Em teste: eu teria mandado para <nome> a semana prevista do serviço (semana de dd/mm) …" quando
--   houver. Nada disso vai ao fechamento, ao aviso, à mensagem da quinta, a *agenda pendências* ou à fila.
--
-- O QUE FAZ:
--   1. modo_equipe_previsto, modo_equipe_convite e modo_cliente_camadas: cada um de 'desligado' para 'sombra', só o que está 'desligado'. NUNCA rebaixa 'ligado' (a trava
--      recusa antes) nem mexe no que já está em 'sombra'.
--   Não toca modo_bloco_agenda, modo_veto e modo_lote_dono (o dado 20261109100900); cliente_tipos_ligados NÃO ganha 'semana' (só o "OK semana prevista ao cliente"); o
--   freio (gestor_so_propor) fica como está; nenhum modo das Fases 1–6 nem de 7a–7d; número nenhum de agenda_config. atualizado_em/atualizado_por só mudam na linha que
--   mudou (atualizado_por = null: foi a migration, não uma pessoa).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked "select modo_equipe_previsto, modo_equipe_convite, modo_cliente_camadas, modo_bloco_agenda, modo_veto, modo_lote_dono,
--     gestor_so_propor, 'semana' = any (cliente_tipos_ligados) as semana_ligada from public.agenda_config;"
--   Esperado: os 3 desligados; bloco, prazo e lote em sombra (o dado 100900); gestor_so_propor true (o freio de hoje); semana_ligada false.
--
-- APLICAR (pelo OK permanente "publicar em teste cada etapa quando o pós-deploy der verde", passo 2 de fila-do-dono/fase77f-publicar-final.md):
--   PONTA=<a ponta> bash publicar/exec/aplicar.sh 20261109101900_agenda_fase7f_sombra_equipe_cliente   (aplica, registra em schema_migrations e para na 1ª falha)
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os 6 modos da 7f; o freio; cliente_tipos_ligados; os modos de antes, para conferir que não mudaram);
--   · supabase/tests/agenda_fase7f_pos_deploy_final.sql: M2 "registrada" e C1 com os 3 em sombra;
--   · no tique seguinte (seg a sáb): a rodada comunicar e a do cliente sem erro comunicar:% e cliente:%; agenda_saude() -> 'comunicacao' com zeros_ok.
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado'; sem nenhum, nem a hora). A bancada NÃO aplica este arquivo (scripts/bancada-agenda/bancada.mjs,
-- FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e supabase/tests/agenda_fase7f_final.sql o roda numa subtransação desfeita (desligado → sombra nos 3; os
-- outros 3 e o resto da linha iguais; de novo não muda nada; a trava com um ligado e sem as funções; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; nada é apagado). É UM comando só (do "with" ao ";", entre as marcas): copie-o para um arquivo e rode com
-- npx supabase@2.111.0 db query --linked -f <arquivo>. Ele só volta o que está em 'sombra' nos 3 e diz quais ficaram ligados: para parar um ligado, ele vai a 'sombra'
-- primeiro (o DESFAZER de publicar/exec/ligar-fase7f.sql) e depois este. Não mexe em mais nada: o que a sombra registrou (as mensagens ":sombra" da equipe e do cliente, as
-- ações contadas, as linhas das rodadas) fica como rastro. Com os 3 já desligados, não muda nada (nem a hora).
-- DESFAZER-INICIO
--   with antes as (
--     select c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas from public.agenda_config c where c.id
--   ), modos as (
--     update public.agenda_config set modo_equipe_previsto = case when modo_equipe_previsto = 'sombra' then 'desligado' else modo_equipe_previsto end, modo_equipe_convite = case when modo_equipe_convite = 'sombra' then 'desligado' else modo_equipe_convite end, modo_cliente_camadas = case when modo_cliente_camadas = 'sombra' then 'desligado' else modo_cliente_camadas end, atualizado_em = now(), atualizado_por = null
--      where id and 'sombra' in (modo_equipe_previsto, modo_equipe_convite, modo_cliente_camadas)
--     returning 1
--   )
--   select (select count(*) from modos) as modos_desligados, coalesce((select concat_ws(', ', case when a.modo_equipe_previsto = 'ligado' then 'modo_equipe_previsto' end, case when a.modo_equipe_convite = 'ligado' then 'modo_equipe_convite' end, case when a.modo_cliente_camadas = 'ligado' then 'modo_cliente_camadas' end) from antes a where 'ligado' in (a.modo_equipe_previsto, a.modo_equipe_convite, a.modo_cliente_camadas)), 'nenhum') as ficam_ligados;
-- DESFAZER-FIM
-- (Com os 3 de novo desligados, tudo volta ao de antes do dado: a rodada do cliente não chama o passo semana, os passos da equipe devolvem {pulado: desligado}, a saúde sem
-- os números da equipe e do cliente. As funções de P5, P6 e P9 ficam no banco: com os 3 desligados, nenhuma muda o que sai a ninguém.)

-- 0. A trava: nada de ligado, e o código dos 3 no banco.
do $trava$
declare
  c record;
  v_falta text[] := array[]::text[];
begin
  select modo_equipe_previsto, modo_equipe_convite, modo_cliente_camadas into c from public.agenda_config where id;
  if 'ligado' in (c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas) then
    raise exception 'O dado 20261109101900 põe em teste e não rebaixa um ligado: previsto %, convite %, camadas %. Nada mudou.',
      c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas using errcode = 'P0001';
  end if;
  select coalesce(array_agg(f), array[]::text[]) into v_falta
    from unnest(array['public._agenda_comunicar_previsto(date, timestamptz)', 'public._agenda_comunicar_mudancas_equipe(date, timestamptz)',
                      'public._agenda_comunicar_convites(date, timestamptz)', 'public._agenda_comunicar_convites_vencidos(date, timestamptz)',
                      'public._agenda_cliente_semana(date, timestamptz)', 'public._agenda_cliente_camada(uuid, date)',
                      'public._agenda_cliente_semana_mudou(uuid, jsonb, date, timestamptz, timestamptz, timestamptz)']) f
   where to_regprocedure(f) is null;
  if cardinality(v_falta) > 0 then
    raise exception 'O dado 20261109101900 vem depois de 20261109101000, 101100 e 101200: faltam %. Nada mudou.', array_to_string(v_falta, ', ') using errcode = 'P0001';
  end if;
end
$trava$;

-- 1. Os 3 modos da equipe e do cliente: de desligado para sombra, cada um só se estiver desligado.
update public.agenda_config
   set modo_equipe_previsto = case when modo_equipe_previsto = 'desligado' then 'sombra' else modo_equipe_previsto end,
       modo_equipe_convite  = case when modo_equipe_convite = 'desligado' then 'sombra' else modo_equipe_convite end,
       modo_cliente_camadas = case when modo_cliente_camadas = 'desligado' then 'sombra' else modo_cliente_camadas end,
       atualizado_em        = now(),
       atualizado_por       = null
 where id
   and 'desligado' in (modo_equipe_previsto, modo_equipe_convite, modo_cliente_camadas);

-- O estado depois (os 6 modos da 7f, o freio e a lista do cliente; os modos de antes, para conferir que não mudaram).
select c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas, c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono,
       c.gestor_so_propor, c.gestor_so_propor_em, 'semana' = any (c.cliente_tipos_ligados) as semana_ligada,
       c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_equipe, c.modo_cliente, c.modo_marcar_sozinho, c.modo_vaga_fechamento, c.modo_dias,
       c.modo_tarefas, c.modo_local_calendario, c.modo_mesmo_local, c.atualizado_em
  from public.agenda_config c;
