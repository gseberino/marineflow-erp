-- Agenda de Produção, Fase 7, etapa 7e ("a margem que aprende"), pacote P8: o dado. Os 6 interruptores da etapa de desligado para SOMBRA (em teste) e o fornecedor medido
-- com 3 entregas, não 5. Molde: 20261109100900_agenda_fase7f_sombra.sql e 20261109101900_agenda_fase7f_sombra_equipe_cliente.sql (os dados da 7f).
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md §5.7 com R7.2 (o dado é a 20261111100900, depois das correções), R7.3-1 (modo_promessa fica em teste para sempre: AG7-32),
-- R7.3-3 (5 modos a ligar, não 6), R7.6 (o freio), R7.11 (fornecedor_n_min 3), R7.13 (a linha P8) e R7.14 (a §10 reescrita: publicar em teste pelo OK permanente, cada *ligar* pelo
-- OK nomeado). Nomes: fase7-registro.md §1. Notas: notas-fase7e.md, seções P1 a P8.
-- Respostas do dono (fase7-padroes.md, o Diário): AG7-29 "Ligar direto" — a publicação nunca liga às cegas: este arquivo põe em teste, e cada *ligar* é um UPDATE no dia, pelo
-- publicar/exec/ligar-fase7e.sql, depois do pós-deploy verde (o "por quê", na linguagem do dono, em fila-do-dono/fase7e-oks.md).
--
-- ═══ GRAVA DADO DE CONFIGURAÇÃO — OK NOMEADO ═══ (só dado e o DEFAULT de uma coluna; nenhuma função, tabela, policy ou cron)
--   · os 6 modos em teste: o OK permanente do dono ("OK publicar em teste cada etapa quando o pós-deploy der verde", passo 3 de fila-do-dono/fase77e-publicar.md);
--   · "OK fornecedor com 3 entregas" (§13, item 7; R7.14): o prazo e o atraso medidos de um fornecedor passam a valer com 3 entregas, e não 5. Hoje nenhum fornecedor tem 3
--     (R7.9: 2 de 20 linhas de material têm fornecedor): sem efeito por mais de 1 ano (R7.10-4).
-- NÃO APLICADA. Este arquivo existe para revisão. Aplica DEPOIS das 8 migrations de estrutura da 7e (20261111100000, 100100, 100200, 100300, 100350, 100400, 100500 e 100600) e do
-- deploy de ai-agent e erp-mcp (passos 1 e 2 de fila-do-dono/fase77e-publicar.md).
--
-- A TRAVA (o bloco "do" logo abaixo, antes de qualquer mudança; a migration falha inteira e nada muda): recusa se faltar o código da 7e no banco (uma função de cada uma das 8 de
-- estrutura, e a rodada do aprendizado com os passos da margem). Em teste sem o código, a saúde e o foco diriam "em teste" de algo que não roda.
--
-- EM SOMBRA (com o freio de hoje, gestor_so_propor = true; e mesmo sem ele): nada sai a ninguém, e o motor, a prontidão, a vigia, a rodada do cliente e os textos ao dono, à equipe e
-- ao cliente são os de antes, byte a byte (o replay da carteira real do P8, f7e/p8/real.mjs). O que muda, de propósito, e só onde o dono pede para ver:
--   · a rodada do aprendizado das 16:00 roda os 6 passos da margem em teste (o viés, a folga da semana, o prazo real, o tempo de compra, a folga da compra e a peça sem
--     fornecedor): grava em agenda_aprendizado só as linhas deles em teste ("medindo" com o que tem; hoje 0 OS conferidas). As medições (as compras e a marcação) já rodam desde o
--     passo 1, em qualquer modo;
--   · o foco aprendizado (*agenda aprendizado*, ou o assistente) ganha o bloco 8, "Margem", com as linhas de "nenhuma … ainda" e o "Em teste: …" (§6.2);
--   · o cartão da OS pode ganhar, em Duração, "Em teste: … eu marcaria N dias" (só com o viés medido e quando ele muda o número: hoje nenhuma OS) e o prazo real só para o
--     dono (só com o fator medido: hoje nenhuma). Ao cliente não se diz data de pronto (AG7-32): modo_promessa fica em teste para sempre, e o ligar-fase7e.sql o recusa;
--   · o puxar na véspera (às 17:37, a rodada do gestor) calcula em teste e grava só no diário do gestor (agenda_gestor_dia.sombra.puxar): nenhuma proposta, ação, alocação nem
--     mensagem (R7.7-1). Hoje 0 pessoas puxáveis (ninguém da rotina tem telefone);
--   · a carga da semana e a urgência em teste não mudam o motor: o teto da semana segue carga_max (R7.6); a saúde ganha a chave margem, que já existe desde o passo 1 e não muda de
--     um modo para o outro.
-- O fornecedor com 3 entregas muda só a conta do item fornecedor da Fase 6 (o mínimo de entregas para o medido valer) e as frases que dizem "de N entregas" no foco: na carteira de
-- hoje, nenhum fornecedor chega a 3 (o replay do P8 mede).
--
-- O QUE FAZ:
--   1. modo_vies, modo_folga_semana, modo_urgencia, modo_promessa, modo_tempo_compra e modo_folga_compra: cada um de 'desligado' para 'sombra', só o que está 'desligado' (como a
--      20261111100000 os criou na linha). NUNCA rebaixa 'ligado' nem mexe no que já está em 'sombra'. Nenhum interruptor é LIGADO aqui.
--   2. fornecedor_n_min: de 5 para 3, só se ainda é o de nascença (5: a 20261029100000); outro valor (o dono mudou) fica.
--   3. o DEFAULT de fornecedor_n_min passa a 3 (ALTER TABLE … SET DEFAULT: só o catálogo, instantâneo; trava agenda_config por um instante, ACCESS EXCLUSIVE: o aplicar.sh roda com
--      LOCK_TIMEOUT).
--   Não toca o freio (gestor_so_propor), modo_aprendizado, aprendizado_ligados, nenhum modo das Fases 1–6, de 7a–7d nem da 7f, nem os outros números da 7e (são as respostas do
--   dono, na 20261111100000). atualizado_em/atualizado_por só mudam se a linha mudou (atualizado_por = null: foi a migration, não uma pessoa).
--   ATENÇÃO (como a 7f): a 7e não guarda quando um modo foi ligado; um modo que o dono voltou a desligado DEPOIS de ligar voltaria a teste se este arquivo rodasse de novo. Ele roda
--   uma vez (schema_migrations).
--
-- PROVA ANTES (só leitura, antes de aplicar — o que vai mudar):
--   npx supabase@2.111.0 db query --linked "select modo_vies, modo_folga_semana, modo_urgencia, modo_promessa, modo_tempo_compra, modo_folga_compra, fornecedor_n_min,
--     (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'agenda_config' and column_name = 'fornecedor_n_min') as padrao,
--     gestor_so_propor, modo_aprendizado from public.agenda_config;"
--   Esperado: desligado nos 6; fornecedor_n_min 5, padrao 5; gestor_so_propor true (o freio de hoje); modo_aprendizado ligado.
--
-- APLICAR (pelo OK permanente, passo 3 de fila-do-dono/fase77e-publicar.md):
--   PONTA=<a ponta> LOCK_TIMEOUT=5s bash publicar/exec/aplicar.sh 20261111100900_agenda_fase7e_dado   (aplica, registra em schema_migrations e para na 1ª falha)
--
-- PROVA DEPOIS (só leitura):
--   · o SELECT do fim deste arquivo (os 6 modos, o fornecedor e o DEFAULT; o freio e os modos de antes, para conferir que não mudaram);
--   · supabase/tests/agenda_fase7e_pos_deploy.sql: M2 "registrado" e C2 com os 6 em teste e o fornecedor em 3;
--   · no dia seguinte, depois das 16:00: a rodada aprender sem erro (aprender:%) e com contagens.modos_margem em teste; agenda_saude() -> 'margem' com zeros_ok.
--
-- IDEMPOTENTE: rodar de novo não muda nada (o UPDATE só pega 'desligado' e o 5; sem nenhum, nem a hora; o DEFAULT já é 3). A bancada NÃO aplica este arquivo
-- (scripts/bancada-agenda/bancada.mjs, FORA_DA_BANCADA): lá cada teste liga o modo que precisa, e supabase/tests/agenda_fase7e_dado.sql o roda numa subtransação desfeita (desligado
-- → sombra nos 6, o 5 → 3 e o DEFAULT; o resto da linha igual; de novo não muda nada; ligado fica ligado; o 4 do dono fica; a trava sem o código; o DESFAZER abaixo).
--
-- DESFAZER (só se o dono pedir; nada é apagado). São DOIS comandos (do "with" ao 1º ";", e o "alter table" até o 2º): copie as linhas entre as marcas para um arquivo e rode com
-- npx supabase@2.111.0 db query --linked -f <arquivo>. O 1º só volta o que está em 'sombra' nos 6 e o 3 do fornecedor, e diz quais modos ficaram ligados: para parar um ligado, ele
-- vai a 'sombra' primeiro (o DESFAZER[<modo>] de publicar/exec/ligar-fase7e.sql) e depois este. O 2º volta o DEFAULT a 5. Não mexe em mais nada: o que a sombra mediu (as linhas
-- da margem em agenda_aprendizado, o diário do puxar) fica como rastro; com os 6 desligados, a rodada não roda os passos da margem e o foco não mostra o bloco 8. Com os 6 já
-- desligados e o fornecedor fora de 3, o 1º não muda nada (nem a hora).
-- DESFAZER-INICIO
--   with antes as (
--     select c.modo_vies, c.modo_folga_semana, c.modo_urgencia, c.modo_promessa, c.modo_tempo_compra, c.modo_folga_compra from public.agenda_config c where c.id
--   ), linha as (
--     update public.agenda_config set modo_vies = case when modo_vies = 'sombra' then 'desligado' else modo_vies end, modo_folga_semana = case when modo_folga_semana = 'sombra' then 'desligado' else modo_folga_semana end, modo_urgencia = case when modo_urgencia = 'sombra' then 'desligado' else modo_urgencia end, modo_promessa = case when modo_promessa = 'sombra' then 'desligado' else modo_promessa end, modo_tempo_compra = case when modo_tempo_compra = 'sombra' then 'desligado' else modo_tempo_compra end, modo_folga_compra = case when modo_folga_compra = 'sombra' then 'desligado' else modo_folga_compra end, fornecedor_n_min = case when fornecedor_n_min = 3 then 5 else fornecedor_n_min end, atualizado_em = now(), atualizado_por = null
--      where id and ('sombra' in (modo_vies, modo_folga_semana, modo_urgencia, modo_promessa, modo_tempo_compra, modo_folga_compra) or fornecedor_n_min = 3)
--     returning 1
--   )
--   select (select count(*) from linha) as linha_mudou, coalesce((select concat_ws(', ', case when a.modo_vies = 'ligado' then 'modo_vies' end, case when a.modo_folga_semana = 'ligado' then 'modo_folga_semana' end, case when a.modo_urgencia = 'ligado' then 'modo_urgencia' end, case when a.modo_promessa = 'ligado' then 'modo_promessa' end, case when a.modo_tempo_compra = 'ligado' then 'modo_tempo_compra' end, case when a.modo_folga_compra = 'ligado' then 'modo_folga_compra' end) from antes a where 'ligado' in (a.modo_vies, a.modo_folga_semana, a.modo_urgencia, a.modo_promessa, a.modo_tempo_compra, a.modo_folga_compra)), 'nenhum') as ficam_ligados;
--   alter table public.agenda_config alter column fornecedor_n_min set default 5;
-- DESFAZER-FIM
-- (Com os 6 de novo desligados, tudo volta ao de antes do dado: a rodada do aprendizado sem os passos da margem, o foco sem o bloco 8, o puxar sem rodar, o cartão sem as 2 linhas
-- novas; o fornecedor volta a pedir 5 entregas. As funções da 7e ficam no banco: com os 6 desligados, elas dão o de antes da 7e, fora as medições e a chave margem da saúde.)

-- 0. A trava: o código da 7e no banco.
do $trava$
declare
  v_falta text[] := array[]::text[];
begin
  select coalesce(array_agg(f order by o), array[]::text[]) into v_falta
    from unnest(array['public._agenda_margem_modo(text)', 'public._agenda_margem_em_uso(text, text)', 'public._agenda_aprender_vies(date, timestamptz)',
                      'public._agenda_carga_da_semana(date, boolean)', 'public._agenda_gestor_puxar(date, timestamptz)', 'public.agenda_promessa_da_os(uuid, date)',
                      'public._agenda_aprender_tempo_compra(date, timestamptz)', 'public._agenda_saude_margem(date, timestamptz)']) with ordinality u(f, o)
   where to_regprocedure(f) is null;
  if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.agenda_aprender(date, timestamptz)') and p.prosrc like '%-- FASE 7e: (7e P7%') then
    v_falta := v_falta || 'os passos da margem em public.agenda_aprender (20261111100600)'::text;
  end if;
  if cardinality(v_falta) > 0 then
    raise exception 'O dado 20261111100900 vem depois das 8 migrations de estrutura da 7e: faltam %. Nada mudou.', array_to_string(v_falta, ', ') using errcode = 'P0001';
  end if;
end
$trava$;

-- 1. O DEFAULT do fornecedor (só o catálogo; idempotente).
alter table public.agenda_config alter column fornecedor_n_min set default 3;

-- 2. Os 6 modos da etapa: de desligado para sombra, cada um só se estiver desligado; o fornecedor de 5 para 3, só se ainda é o de nascença.
update public.agenda_config
   set modo_vies         = case when modo_vies = 'desligado' then 'sombra' else modo_vies end,
       modo_folga_semana = case when modo_folga_semana = 'desligado' then 'sombra' else modo_folga_semana end,
       modo_urgencia     = case when modo_urgencia = 'desligado' then 'sombra' else modo_urgencia end,
       modo_promessa     = case when modo_promessa = 'desligado' then 'sombra' else modo_promessa end,
       modo_tempo_compra = case when modo_tempo_compra = 'desligado' then 'sombra' else modo_tempo_compra end,
       modo_folga_compra = case when modo_folga_compra = 'desligado' then 'sombra' else modo_folga_compra end,
       fornecedor_n_min  = case when fornecedor_n_min = 5 then 3 else fornecedor_n_min end,
       atualizado_em     = now(),
       atualizado_por    = null
 where id
   and ('desligado' in (modo_vies, modo_folga_semana, modo_urgencia, modo_promessa, modo_tempo_compra, modo_folga_compra) or fornecedor_n_min = 5);

-- O estado depois (os 6 modos da 7e, o fornecedor e o DEFAULT, o freio; os modos de antes, para conferir que não mudaram).
select c.modo_vies, c.modo_folga_semana, c.modo_urgencia, c.modo_promessa, c.modo_tempo_compra, c.modo_folga_compra, c.fornecedor_n_min,
       (select i.column_default from information_schema.columns i where i.table_schema = 'public' and i.table_name = 'agenda_config' and i.column_name = 'fornecedor_n_min') as fornecedor_n_min_padrao,
       c.gestor_so_propor, c.gestor_so_propor_em, c.modo_aprendizado, c.modo_leitura, c.modo_proposta, c.modo_vigia, c.modo_cliente, c.modo_marcar_sozinho,
       c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono, c.atualizado_em
  from public.agenda_config c;
