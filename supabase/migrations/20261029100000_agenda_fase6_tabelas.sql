-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P1: a base — o modo e os parâmetros do aprendizado, os dias que o dono
-- disse no início da OS (dias_no_inicio) e a 1ª promessa ao cliente (prometido_primeiro_ate), as 2 tabelas do aprendizado (a
-- medida de cada OS concluída e os valores aprendidos) e as listas fechadas ampliadas.
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§3, §4). Decisões do dono 23/10 ("o auto-aprendizado é construído junto e
-- coleta dado desde o primeiro dia"; "a intervenção do dono ajusta a presença das OS parecidas"; d04, d05; dinheiro é do dono).
-- Depende das Fases 1 a 5 inteiras (20261024160000 .. 20261028100800).
--
-- ═══ DDL — OK NOMEADO ═══ (2 tabelas novas, vazias; 45 colunas novas em agenda_config — o modo, a lista e 43 parâmetros — e o
-- DEFAULT de modo_aprendizado; 4 colunas novas em os_planejamento, todas nulas; 3 listas fechadas ampliadas; a coluna gerada
-- critica com 'aprendizado'; 1 função de CHECK e 2 de gatilho)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f6p1/montar-migration.mjs (a parte escrita à mão
-- f6p1/parte-tabelas.sql, conferida: nenhuma função recriada, search_path fixo e REVOKE de public e anon em cada função nova).
-- Existe para revisão e espera o OK do dono.
--
-- POR QUE: a agenda passa a medir o que aconteceu (quanto cada OS levou de verdade contra o que o dono disse, o atraso de cada
-- fornecedor, a capacidade do dono, a pontualidade com o cliente) e a aprender com isso, sem IA: o banco mede, o banco calcula,
-- o banco usa. Esta migration só cria o lugar de cada coisa; quem mede é a 20261029100100 (P1) e quem aprende são as próximas
-- (100200 a 100800). O aprendizado nasce desligado; a migration de dado 20261029101000 (P8, OK nomeado) o põe em sombra.
--
-- O QUE MUDA:
--   1. agenda_config: modo_aprendizado (desligado | sombra | ligado; a linha fica 'desligado', o DEFAULT da coluna vira
--      'sombra', como nas Fases 2 a 5), aprendizado_ligados (os itens que, com o modo ligado, passam a valer; fora da lista
--      ficam em teste) e 43 parâmetros (a hora da rodada, a janela, a trava, os mínimos, os percentis, os limites de troca, a
--      capacidade do dono, o cliente, a revisão da carga, os gatilhos do planejador e as palavras da classe de serviço), cada
--      um com CHECK por nome. O DEFAULT é o único lugar do número.
--   2. os_planejamento: dias_no_inicio/_fonte/_em (os dias que o dono disse até o dia do check-in, congelados pela rodada:
--      a medida usa estes, não os que ele disser depois) e prometido_primeiro_ate (a 1ª data dita ao cliente, que nunca zera:
--      NOVO-agenda-44).
--   3. agenda_medidas_os (uma linha por OS concluída: a classe, os meios-dias planejados e os cumpridos, as diárias ligadas,
--      o fator, se vale e por que não, a pontualidade com o cliente e o aviso de atraso) e agenda_aprendizado (um valor
--      aprendido por item e chave: o padrão, o calculado, o em uso, o n e a amostra, o estado e o texto). Nenhuma se apaga;
--      a medida só muda inteira (versão + 1, com o histórico); do valor aprendido não mudam o item, a chave e o nível.
--   4. Listas fechadas: agenda_perguntas.tipo + aprendizado (CRÍTICA: a coluna gerada critica ganha o tipo);
--      agenda_acoes.tipo + aprendizado (a origem é vigia, que já existe); agenda_vigia_rodadas.rotina + aprender.
--   5. Portas: RLS ligada nas 2 tabelas; só leitura TO authenticated (admin/financeiro); revoke de public, anon e
--      authenticated; escrita só pelas funções security definer da 20261029100100 em diante (e por service_role).
--   6. O comentário de fator_promessa diz que ele não tem leitor (NOVO-agenda-43): o 1,5 que age é estouro_fator.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase6_base.sql e agenda_fase6_medicao.sql):
--   · aprendizado_em_uso_coerente: a spec pede (estado = 'em_uso') = (em_uso is not null). Assim, na pergunta (a troca grande
--     que espera o dono) e na trava ("fico com o de agora", o *desfaz*), o valor em uso teria de virar nulo — e o "fico com o de
--     agora" voltaria ao padrão, não ao de agora. O CHECK daqui: em uso tem valor; medindo e sombra não têm; pergunta e travado
--     guardam o que está valendo (pode ser nulo = o padrão). _agenda_aprendido (100100) devolve o valor nos três estados.
--   · classe_bens e classe_sistemas: as palavras são expressões regulares casadas no INÍCIO de palavra do texto normalizado
--     (_agenda_normal). O motor ganhou "motor(?! ?home)": sem isso, toda linha que diz "motorhome" seria "motor e gerador"
--     (conferido com as 31 linhas principais de produção, f6p1/q01_principais); o bem ganhou "motor home".
--   · As chaves das duas listas são fechadas (CHECK por _agenda_classe_pares_ok): as mesmas das colunas classe_bem e
--     classe_sistema de agenda_medidas_os. Chave nova pede ampliar as duas.
--
-- O QUE NÃO MUDA: nenhum comportamento até as próximas migrations. Nenhum cron, nenhuma tela, nenhuma função de borda; nenhuma
-- mensagem. A coluna critica só muda para o tipo novo (as 7 críticas de antes continuam). fator_promessa continua sem leitor.
--
-- ORDEM DE LIGAR: depois das Fases 1 a 5 inteiras aplicadas (fila-do-dono/fase1-oks.md … fase5-oks.md), de preferência no MESMO
-- passo delas (spec-fase6 §13, item 2: a medição começa na 1ª OS); antes de 20261029100100 (a medição, que lê as colunas novas).
-- Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase6_base.sql (begin/rollback; cada CHECK recusa uma linha errada, as tabelas
-- novas não se apagam e só mudam o permitido, RLS, anon sem privilégio, critica com aprendizado). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100000_agenda_fase6_tabelas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100000', 'agenda_fase6_tabelas');"
--
-- DESFAZER (só a estrutura; as tabelas vazias): nada a desfazer no comportamento. As colunas e as tabelas ficam (nunca apagar o
-- que a medição já escreveu); para parar a medição, a rodada (P6) respeita modo_aprendizado = 'desligado' só a partir do passo
-- 2 — a medição roda sempre, mas só escreve nas 2 tabelas desta migration e em os_planejamento.dias_no_inicio*.
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (os de lista fechada: drop if exists + add), create
-- table/index if not exists, create or replace function, drop trigger/policy if exists + create, SET EXPRESSION só quando a
-- expressão ainda não tem o tipo novo.

-- ── 0. A função do CHECK das palavras da classe ─────────────────────────────────────────────────────────
-- Uma lista de pares [chave, palavras], não vazia, com as chaves dentro da lista fechada e sem chave repetida. (CHECK não aceita
-- subconsulta; a função é IMMUTABLE e só olha o jsonb.)
create or replace function public._agenda_classe_pares_ok(p_lista jsonb, p_chaves text[])
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select jsonb_typeof(p_lista) = 'array' and jsonb_array_length(p_lista) > 0
         and not exists (select 1 from jsonb_array_elements(p_lista) e
                          where jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> 2
                             or jsonb_typeof(e -> 0) <> 'string' or jsonb_typeof(e -> 1) <> 'string'
                             or not ((e ->> 0) = any (p_chaves)) or btrim(e ->> 1) = '')
         and (select count(*) = count(distinct e ->> 0) from jsonb_array_elements(p_lista) e);
$function$;

comment on function public._agenda_classe_pares_ok(jsonb, text[]) is
  'Agenda de Produção (Fase 6): o CHECK de agenda_config.classe_bens e classe_sistemas — uma lista não vazia de pares [chave, palavras], com a chave dentro de p_chaves, sem repetir e com as palavras preenchidas.';

revoke all on function public._agenda_classe_pares_ok(jsonb, text[]) from public, anon;
grant execute on function public._agenda_classe_pares_ok(jsonb, text[]) to authenticated, service_role;

-- ── 1. O modo e os parâmetros do aprendizado ────────────────────────────────────────────────────────────
alter table public.agenda_config
  add column if not exists modo_aprendizado          text         not null default 'desligado',
  add column if not exists aprendizado_ligados       text[]       not null default '{}',
  add column if not exists aprender_hora             time         not null default '16:00',
  add column if not exists aprender_janela_dias      smallint     not null default 365,
  add column if not exists aprender_trava_dias       smallint     not null default 28,
  add column if not exists fator_n_min               smallint     not null default 6,
  add column if not exists fator_percentil           numeric(3,2) not null default 0.80,
  add column if not exists fator_amostra_max         smallint     not null default 20,
  add column if not exists fator_min                 numeric(3,2) not null default 1.00,
  add column if not exists fator_max                 numeric(3,2) not null default 2.50,
  add column if not exists fator_troca_max           numeric(3,2) not null default 0.30,
  add column if not exists mo_n_min                  smallint     not null default 6,
  add column if not exists mo_min                    numeric(8,2) not null default 300,
  add column if not exists mo_troca_max              numeric(3,2) not null default 0.25,
  add column if not exists presenca_n_min            smallint     not null default 4,
  add column if not exists presenca_intervencoes_min smallint     not null default 3,
  add column if not exists presenca_taxa_min         numeric(3,2) not null default 0.50,
  add column if not exists fornecedor_n_min          smallint     not null default 5,
  add column if not exists fornecedor_percentil      numeric(3,2) not null default 0.80,
  add column if not exists fornecedor_troca_max_du   smallint     not null default 3,
  add column if not exists capacidade_semanas        smallint     not null default 8,
  add column if not exists capacidade_semanas_min    smallint     not null default 4,
  add column if not exists capacidade_meios_min      smallint     not null default 2,
  add column if not exists capacidade_dono_min       numeric(3,2) not null default 0.40,
  add column if not exists capacidade_troca_max      numeric(3,2) not null default 0.20,
  add column if not exists capacidade_motivos        text[]       not null
    default '{equipe_faltou,urgencia_outra_os,trabalho_anterior,esqueci}',
  add column if not exists cliente_n_min             smallint     not null default 6,
  add column if not exists aviso_n_min               smallint     not null default 5,
  add column if not exists aviso_folga_max_du        smallint     not null default 5,
  add column if not exists aviso_troca_max_du        smallint     not null default 2,
  add column if not exists revisao_semanas           smallint     not null default 8,
  add column if not exists ppc_baixo                 numeric(3,2) not null default 0.60,
  add column if not exists ppc_baixo_semanas         smallint     not null default 3,
  add column if not exists carga_ppc_baixo           numeric(3,2) not null default 0.70,
  add column if not exists ppc_alto                  numeric(3,2) not null default 0.88,
  add column if not exists ppc_alto_semanas          smallint     not null default 4,
  add column if not exists carga_ppc_alto            numeric(3,2) not null default 0.85,
  add column if not exists solver_os_ativas          smallint     not null default 25,
  add column if not exists solver_pessoas            smallint     not null default 6,
  add column if not exists solver_curtas_dia         numeric(3,1) not null default 2.0,
  add column if not exists solver_descarte_pct       numeric(3,2) not null default 0.20,
  add column if not exists solver_semanas            smallint     not null default 4,
  add column if not exists solver_gatilhos_min       smallint     not null default 2,
  add column if not exists classe_bens               jsonb        not null
    default '[["rv","motorhome|motor home|camper|trailer|van|onibus"],["barco","lancha|veleiro|barco|catamara|iate|jet|escuna|traineira"]]',
  add column if not exists classe_sistemas           jsonb        not null
    default '[["diagnostico","diagnost"],["energia","litio|lifepo|bateria|inversor|usina|solar|dc ?-? ?dc|dc/dc|carregador|conversor|barramento|corrente continua|sistema eletrico"],["motor","motor(?! ?home)|gerador|propuls|seakeeper"],["conectividade","starlink|antena|roteador|multimid|camera|radio|gps"],["conforto","geladeira|refrigera|ar condicionado|aquecedor|fogao|inducao|gas"]]';

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_aprendizado_check',
       'check (modo_aprendizado in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_aprendizado_ligados_check',
       'check (aprendizado_ligados <@ array[''fator'', ''mo'', ''presenca'', ''fornecedor'', ''capacidade_dono'', ''aviso_cliente'', ''revisao'']::text[])'),
      ('agenda_config_aprender_hora_check',
       'check (aprender_hora >= time ''12:00'' and aprender_hora <= hora_do_plano)'),
      ('agenda_config_aprender_janela_dias_check',   'check (aprender_janela_dias between 90 and 730)'),
      ('agenda_config_aprender_trava_dias_check',    'check (aprender_trava_dias between 7 and 90)'),
      ('agenda_config_fator_n_min_check',            'check (fator_n_min between 3 and 20)'),
      ('agenda_config_fator_percentil_check',        'check (fator_percentil between 0.50 and 0.95)'),
      ('agenda_config_fator_amostra_max_check',      'check (fator_amostra_max between 6 and 60)'),
      ('agenda_config_fator_min_check',              'check (fator_min between 1.00 and 1.50 and fator_min < fator_max)'),
      ('agenda_config_fator_max_check',              'check (fator_max between 1.50 and 3.00)'),
      ('agenda_config_fator_troca_max_check',        'check (fator_troca_max between 0.10 and 1.00)'),
      ('agenda_config_mo_n_min_check',               'check (mo_n_min between 3 and 20)'),
      ('agenda_config_mo_min_check',                 'check (mo_min > 0)'),
      ('agenda_config_mo_troca_max_check',           'check (mo_troca_max between 0.05 and 0.50)'),
      ('agenda_config_presenca_n_min_check',         'check (presenca_n_min between 3 and 20)'),
      ('agenda_config_presenca_intervencoes_min_check', 'check (presenca_intervencoes_min between 2 and 10)'),
      ('agenda_config_presenca_taxa_min_check',      'check (presenca_taxa_min between 0.20 and 1.00)'),
      ('agenda_config_fornecedor_n_min_check',       'check (fornecedor_n_min between 3 and 20)'),
      ('agenda_config_fornecedor_percentil_check',   'check (fornecedor_percentil between 0.50 and 0.95)'),
      ('agenda_config_fornecedor_troca_max_du_check', 'check (fornecedor_troca_max_du between 1 and 10)'),
      ('agenda_config_capacidade_semanas_check',     'check (capacidade_semanas between 4 and 26)'),
      ('agenda_config_capacidade_semanas_min_check',
       'check (capacidade_semanas_min >= 2 and capacidade_semanas_min <= capacidade_semanas)'),
      ('agenda_config_capacidade_meios_min_check',   'check (capacidade_meios_min between 1 and 10)'),
      ('agenda_config_capacidade_dono_min_check',    'check (capacidade_dono_min between 0.20 and 0.80)'),
      ('agenda_config_capacidade_troca_max_check',   'check (capacidade_troca_max between 0.05 and 0.50)'),
      ('agenda_config_capacidade_motivos_check',
       'check (capacidade_motivos <@ array[''material'', ''cliente_ou_bem'', ''equipe_faltou'', ''trabalho_anterior'', ''informacao'', ''clima'', ''estimativa'', ''imprevisto_tecnico'', ''urgencia_outra_os'', ''esqueci'', ''concluida_antes'']::text[])'),
      ('agenda_config_cliente_n_min_check',          'check (cliente_n_min between 3 and 20)'),
      ('agenda_config_aviso_n_min_check',            'check (aviso_n_min between 3 and 20)'),
      ('agenda_config_aviso_folga_max_du_check',     'check (aviso_folga_max_du between 1 and 10)'),
      ('agenda_config_aviso_troca_max_du_check',     'check (aviso_troca_max_du between 1 and 5)'),
      ('agenda_config_revisao_semanas_check',        'check (revisao_semanas between 4 and 26)'),
      ('agenda_config_ppc_baixo_check',              'check (ppc_baixo > 0 and ppc_baixo < ppc_alto)'),
      ('agenda_config_ppc_alto_check',               'check (ppc_alto <= 1)'),
      ('agenda_config_ppc_baixo_semanas_check',      'check (ppc_baixo_semanas between 2 and 12)'),
      ('agenda_config_ppc_alto_semanas_check',       'check (ppc_alto_semanas between 2 and 12)'),
      ('agenda_config_carga_ppc_baixo_check',        'check (carga_ppc_baixo between 0.50 and 1.00)'),
      ('agenda_config_carga_ppc_alto_check',         'check (carga_ppc_alto between 0.50 and 1.00)'),
      ('agenda_config_solver_os_ativas_check',       'check (solver_os_ativas > 0)'),
      ('agenda_config_solver_pessoas_check',         'check (solver_pessoas > 0)'),
      ('agenda_config_solver_curtas_dia_check',      'check (solver_curtas_dia > 0)'),
      ('agenda_config_solver_descarte_pct_check',    'check (solver_descarte_pct between 0.05 and 0.50)'),
      ('agenda_config_solver_semanas_check',         'check (solver_semanas > 0)'),
      ('agenda_config_solver_gatilhos_min_check',    'check (solver_gatilhos_min between 1 and 4)'),
      ('agenda_config_classe_bens_check',
       'check (public._agenda_classe_pares_ok(classe_bens, array[''rv'', ''barco'']::text[]))'),
      ('agenda_config_classe_sistemas_check',
       'check (public._agenda_classe_pares_ok(classe_sistemas, array[''diagnostico'', ''energia'', ''motor'', ''conectividade'', ''conforto'']::text[]))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como as Fases 2 a 5: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem
-- a põe em sombra é a migration de dado 20261029101000, com OK nomeado.
alter table public.agenda_config alter column modo_aprendizado set default 'sombra';

comment on column public.agenda_config.modo_aprendizado is
  'Agenda de Produção (Fase 6): desligado = só a medição roda (as OS concluídas viram agenda_medidas_os); sombra = também calcula os valores aprendidos e os mostra como "em teste" no foco aprendizado, sem usar nenhum; ligado = os itens de aprendizado_ligados passam a valer (a troca pequena entra sozinha, com *desfaz aprendizado*; a grande vira pergunta crítica). Voltar a sombra devolve na hora o padrão de hoje em todo leitor (_agenda_aprendido confere o modo).';
comment on column public.agenda_config.aprendizado_ligados is
  'Agenda de Produção (Fase 6): os itens que valem com modo_aprendizado ligado — fator (o limiar do "estourou" e do risco de atraso), mo (R$ por diária na duração sugerida), presenca (o dono o dia todo numa classe), fornecedor (atraso e prazo medidos), capacidade_dono (a carga dele no motor), aviso_cliente (a folga da faixa do aviso de atraso), revisao (a carga de todos pelo plano cumprido e os gatilhos do planejador). Fora da lista = em teste.';
comment on column public.agenda_config.aprender_hora is 'Agenda de Produção (Fase 6): a rodada do aprendizado roda uma vez por dia, no 1º tique a partir desta hora (antes do plano das 16:30 e do fechamento).';
comment on column public.agenda_config.aprender_janela_dias is 'Agenda de Produção (Fase 6): só as OS concluídas nestes dias corridos entram na medida e no aprendizado.';
comment on column public.agenda_config.aprender_trava_dias is 'Agenda de Produção (Fase 6): depois do *desfaz aprendizado* ou do "fico com o de agora", a chave não troca por estes dias (salvo se o medido andar mais que o limite de troca a partir do valor recusado).';
comment on column public.agenda_config.fator_n_min is 'Agenda de Produção (Fase 6): medidas válidas mínimas numa classe para o fator dela valer (abaixo disso, só "medindo").';
comment on column public.agenda_config.fator_percentil is 'Agenda de Produção (Fase 6): o fator da classe é este percentil das medidas válidas mais recentes ("levam até 1,7× o combinado").';
comment on column public.agenda_config.fator_amostra_max is 'Agenda de Produção (Fase 6): as medidas válidas mais recentes que entram no fator e no R$ por diária.';
comment on column public.agenda_config.fator_min is 'Agenda de Produção (Fase 6): o fator aprendido nunca fica abaixo disto (o fator não encurta o plano).';
comment on column public.agenda_config.fator_max is 'Agenda de Produção (Fase 6): o fator aprendido nunca passa disto.';
comment on column public.agenda_config.fator_troca_max is 'Agenda de Produção (Fase 6): troca de fator até isto (em ×) entra sozinha; acima, pergunta.';
comment on column public.agenda_config.mo_n_min is 'Agenda de Produção (Fase 6): OS válidas com diarista mínimas para o R$ por diária medido valer.';
comment on column public.agenda_config.mo_min is 'Agenda de Produção (Fase 6): o R$ por diária medido nunca fica abaixo disto (nem acima de mo_por_diaria_preco).';
comment on column public.agenda_config.mo_troca_max is 'Agenda de Produção (Fase 6): troca do R$ por diária até esta fração do valor em uso entra sozinha; acima, pergunta.';
comment on column public.agenda_config.presenca_n_min is 'Agenda de Produção (Fase 6): OS válidas mínimas da classe para a presença aprendida valer.';
comment on column public.agenda_config.presenca_intervencoes_min is 'Agenda de Produção (Fase 6): OS da classe com intervenção do dono (foi sem estar no plano) mínimas para a presença aprendida.';
comment on column public.agenda_config.presenca_taxa_min is 'Agenda de Produção (Fase 6): a fração mínima das OS da classe com intervenção do dono para contar com ele o dia todo.';
comment on column public.agenda_config.fornecedor_n_min is 'Agenda de Produção (Fase 6): entregas medidas mínimas de um fornecedor para o atraso e o prazo medidos valerem.';
comment on column public.agenda_config.fornecedor_percentil is 'Agenda de Produção (Fase 6): o atraso (e o prazo) medido do fornecedor é este percentil das entregas.';
comment on column public.agenda_config.fornecedor_troca_max_du is 'Agenda de Produção (Fase 6): troca de atraso ou prazo do fornecedor até estes dias úteis entra sozinha; acima, pergunta.';
comment on column public.agenda_config.capacidade_semanas is 'Agenda de Produção (Fase 6): as semanas ISO completas que medem a capacidade do dono.';
comment on column public.agenda_config.capacidade_semanas_min is 'Agenda de Produção (Fase 6): semanas medidas mínimas para a capacidade do dono valer.';
comment on column public.agenda_config.capacidade_meios_min is 'Agenda de Produção (Fase 6): a semana conta na capacidade do dono só com pelo menos estes meios-dias dele no plano.';
comment on column public.agenda_config.capacidade_dono_min is 'Agenda de Produção (Fase 6): a carga do dono no motor nunca fica abaixo disto (o piso da capacidade medida).';
comment on column public.agenda_config.capacidade_troca_max is 'Agenda de Produção (Fase 6): troca da carga do dono até isto (fração da semana) entra sozinha; acima, pergunta.';
comment on column public.agenda_config.capacidade_motivos is 'Agenda de Produção (Fase 6): os motivos de "não cumprido" que pesam na capacidade do dono (a falta por ele). Material, cliente e chuva ficam fora da conta.';
comment on column public.agenda_config.cliente_n_min is 'Agenda de Produção (Fase 6): OS com 1ª promessa mínimas para a pontualidade com o cliente aparecer (só medida, nunca usada).';
comment on column public.agenda_config.aviso_n_min is 'Agenda de Produção (Fase 6): avisos de atraso enviados mínimos para a folga do aviso valer.';
comment on column public.agenda_config.aviso_folga_max_du is 'Agenda de Produção (Fase 6): a folga aprendida da faixa do aviso de atraso nunca passa destes dias úteis.';
comment on column public.agenda_config.aviso_troca_max_du is 'Agenda de Produção (Fase 6): troca da folga do aviso até estes dias úteis entra sozinha; acima, pergunta.';
comment on column public.agenda_config.revisao_semanas is 'Agenda de Produção (Fase 6): as semanas completas de plano cumprido que a revisão da carga lê.';
comment on column public.agenda_config.ppc_baixo is 'Agenda de Produção (Fase 6): plano cumprido abaixo disto por ppc_baixo_semanas seguidas → pergunta se a carga passa a carga_ppc_baixo.';
comment on column public.agenda_config.ppc_baixo_semanas is 'Agenda de Produção (Fase 6): semanas seguidas abaixo de ppc_baixo para perguntar.';
comment on column public.agenda_config.carga_ppc_baixo is 'Agenda de Produção (Fase 6): a carga recomendada quando o plano é cumprido pouco.';
comment on column public.agenda_config.ppc_alto is 'Agenda de Produção (Fase 6): plano cumprido acima disto por ppc_alto_semanas seguidas → pergunta se a carga passa a carga_ppc_alto.';
comment on column public.agenda_config.ppc_alto_semanas is 'Agenda de Produção (Fase 6): semanas seguidas acima de ppc_alto para perguntar.';
comment on column public.agenda_config.carga_ppc_alto is 'Agenda de Produção (Fase 6): a carga recomendada quando o plano é cumprido quase todo.';
comment on column public.agenda_config.solver_os_ativas is 'Agenda de Produção (Fase 6): gatilho do planejador mais forte — mais OS ativas que isto.';
comment on column public.agenda_config.solver_pessoas is 'Agenda de Produção (Fase 6): gatilho do planejador mais forte — mais pessoas na grade que isto.';
comment on column public.agenda_config.solver_curtas_dia is 'Agenda de Produção (Fase 6): gatilho do planejador mais forte — mais presenças curtas do dono por dia útil que isto.';
comment on column public.agenda_config.solver_descarte_pct is 'Agenda de Produção (Fase 6): gatilho do planejador mais forte — mais que esta fração das propostas descartadas.';
comment on column public.agenda_config.solver_semanas is 'Agenda de Produção (Fase 6): semanas seguidas com os gatilhos valendo para avisar (uma vez).';
comment on column public.agenda_config.solver_gatilhos_min is 'Agenda de Produção (Fase 6): gatilhos que precisam valer juntos para avisar.';
comment on column public.agenda_config.classe_bens is
  'Agenda de Produção (Fase 6): o bem da classe de serviço — pares [chave, palavras] em ordem; as palavras são expressões regulares casadas no início de palavra de vessels.asset_type normalizado (_agenda_normal). Nenhuma casa = outro.';
comment on column public.agenda_config.classe_sistemas is
  'Agenda de Produção (Fase 6): o sistema da classe de serviço — pares [chave, palavras] casados NESTA ORDEM (a 1ª que casa vence) no início de palavra da linha de serviço de maior valor normalizada. Nenhuma casa = geral ("outros serviços").';

comment on column public.agenda_config.fator_promessa is
  'Agenda de Produção (Fase 1): a folga da promessa ao cliente prevista no plano (fim + metade da duração). SEM LEITOR (NOVO-agenda-43): a M1 diz o início e os dias; o 1,5 que age é estouro_fator, e é ele que o fator de campo aprendido substitui (Fase 6).';

-- ── 2. Os dias que o dono disse no início da OS e a 1ª promessa ao cliente ──────────────────────────────
alter table public.os_planejamento
  add column if not exists dias_no_inicio         numeric(4,1) check (dias_no_inicio > 0 and dias_no_inicio * 2 = trunc(dias_no_inicio * 2)),
  add column if not exists dias_no_inicio_fonte   text check (dias_no_inicio_fonte in ('dono', 'aceita')),
  add column if not exists dias_no_inicio_em      date,
  add column if not exists prometido_primeiro_ate date;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.os_planejamento'::regclass and conname = 'dias_no_inicio_coerente') then
    alter table public.os_planejamento add constraint dias_no_inicio_coerente
      check ((dias_no_inicio is null) = (dias_no_inicio_fonte is null) and (dias_no_inicio is null) = (dias_no_inicio_em is null));
  end if;
end
$$;

comment on column public.os_planejamento.dias_no_inicio is
  'Agenda de Produção (Fase 6): os dias que o dono disse (ou aceitou) até o dia do check-in, congelados pela rodada do aprendizado (_agenda_aprender_congelar). A medida da OS compara o que aconteceu com estes, não com o que ele disser depois. Nenhum *grava* escreve aqui.';
comment on column public.os_planejamento.dias_no_inicio_fonte is 'Agenda de Produção (Fase 6): dono ou aceita (a sugestão do banco que o dono aceitou). A sugestão sem o dono nunca é congelada.';
comment on column public.os_planejamento.dias_no_inicio_em is 'Agenda de Produção (Fase 6): o dia do check-in (Brasília) a que dias_no_inicio se refere.';
comment on column public.os_planejamento.prometido_primeiro_ate is
  'Agenda de Produção (Fase 6, NOVO-agenda-44): a 1ª data dita ao cliente. Nunca zera — nem pelo aviso "ainda faltam peças sem data", que zera o prometido e o original. A pontualidade com o cliente é medida contra ela (coalesce com prometido_original_ate para a OS de antes da Fase 6).';

-- ── 3. As tabelas do aprendizado ────────────────────────────────────────────────────────────────────────

-- (1) Uma linha por OS concluída: o diário do aprendizado. NUNCA apagada; só muda inteira (versão + 1, com o histórico).
create table if not exists public.agenda_medidas_os (
  service_order_id       uuid primary key references public.service_orders(id) on delete cascade,
  classe_bem             text not null check (classe_bem in ('rv', 'barco', 'outro')),
  classe_sistema         text not null check (classe_sistema in ('diagnostico', 'energia', 'motor', 'conectividade', 'conforto', 'geral')),
  concluida_em           date not null,
  entregue_em            date,
  dias_no_inicio         numeric(4,1),
  dias_fonte             text check (dias_fonte in ('dono', 'aceita', 'sugerida')),
  meios_planejados       smallint,
  meios_cumpridos        numeric(5,1) not null default 0,
  meios_fora_do_plano    smallint not null default 0,
  meios_sem_registro     smallint not null default 0,
  diarias_ligadas        numeric(6,2) not null default 0,
  so_o_dono              boolean not null default false,
  mo                     numeric(12,2),
  fator                  numeric(4,2),
  valida                 boolean not null,
  motivo                 text check (motivo in ('sem_inicio', 'sem_dias_no_inicio', 'dias_sugeridos', 'sem_plano',
                                                'conferencia_incompleta', 'sem_diaria', 'reaberta')),
  prometido_primeiro_ate date,
  atraso_cliente_du      smallint,
  avisos_enviados        smallint not null default 0,
  aviso_faixa_ate        date,
  aviso_estouro_du       smallint,
  medida_em              timestamptz not null,
  versao                 smallint not null default 1,
  historico              jsonb not null default '[]'
                           check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  constraint medida_valida_sem_motivo check (valida = (motivo is null)),
  constraint medida_fator_so_valida   check (fator is null or valida),
  constraint medida_dias_coerente     check ((dias_no_inicio is null) = (dias_fonte is null))
);

create index if not exists agenda_medidas_os_concluida on public.agenda_medidas_os(concluida_em desc) where valida;

comment on table public.agenda_medidas_os is
  'Agenda de Produção (Fase 6): uma linha por OS concluída (agenda_medir_os) — a classe de campo (bem × sistema), os dias que o dono disse no início, os meios-dias planejados e os que aconteceram (cumprido 1, parcial 0,5, mais as diárias ligadas em dia sem alocação), as diárias ligadas, o fator (meios reais ÷ planejados), se a medida vale e por que não, a pontualidade com o cliente (a 1ª promessa contra a conclusão) e o último aviso de atraso. NUNCA apagada; só muda inteira, com versao + 1 e o que mudou no histórico.';
comment on column public.agenda_medidas_os.concluida_em is 'O dia da conclusão (check_out_at em Brasília).';
comment on column public.agenda_medidas_os.dias_fonte is 'dono ou aceita (os dias ditos até o check-in) ou sugerida (a duração sugerida pelo banco: a medida não vale).';
comment on column public.agenda_medidas_os.meios_planejados is 'dias_no_inicio × 2.';
comment on column public.agenda_medidas_os.meios_cumpridos is 'Os meios-dias que aconteceram: (dia, turno) distintos das alocações vigentes não reserva até a conclusão (cumprido 1, parcial 0,5, não cumprido 0), mais meios_fora_do_plano.';
comment on column public.agenda_medidas_os.meios_fora_do_plano is 'Das diárias ligadas à OS em dia sem alocação dela (fração 1 = 2 meios, 0,5 = 1).';
comment on column public.agenda_medidas_os.meios_sem_registro is 'Meios-dias vigentes da OS até a conclusão sem resultado (ou sem_registro): a conferência incompleta.';
comment on column public.agenda_medidas_os.diarias_ligadas is 'As diárias ligadas à OS (v_dias_por_os_e_pessoa: só diarista; o sócio nunca entra).';
comment on column public.agenda_medidas_os.so_o_dono is 'O plano da OS só com o dono (diagnóstico, comissionamento): vale sem diária ligada.';
comment on column public.agenda_medidas_os.mo is 'A mão de obra da OS (os_duracao_sugerida.mo).';
comment on column public.agenda_medidas_os.atraso_cliente_du is 'Dias úteis da conclusão depois da 1ª promessa (≤ 0 = no prazo).';
comment on column public.agenda_medidas_os.avisos_enviados is 'Avisos de atraso (pode_atrasar e nova_data) que saíram de verdade.';
comment on column public.agenda_medidas_os.aviso_faixa_ate is 'O fim da faixa do último aviso "pode atrasar" que saiu.';
comment on column public.agenda_medidas_os.aviso_estouro_du is 'Dias úteis da conclusão depois de aviso_faixa_ate.';
comment on column public.agenda_medidas_os.historico is '[{em, versao, antes, depois}] — o que mudou a cada nova versão (os 20 mais novos).';

-- (2) Um valor aprendido por item e chave. NUNCA apagado; o item, a chave e o nível não mudam.
create table if not exists public.agenda_aprendizado (
  id            uuid primary key default gen_random_uuid(),
  item          text not null check (item in ('fator', 'mo', 'presenca', 'fornecedor_atraso', 'fornecedor_prazo', 'capacidade_dono',
                                              'cliente_pontualidade', 'aviso_folga', 'carga', 'solver')),
  chave         text not null check (char_length(chave) between 1 and 60),
  nivel         text not null check (nivel in ('fina', 'sistema', 'bem', 'todas', 'fornecedor', 'dono', 'geral')),
  padrao        numeric(10,2),
  calculado     numeric(10,2),
  em_uso        numeric(10,2),
  n             smallint not null default 0,
  n_min         smallint not null,
  amostra       jsonb not null default '[]'
                  check (case when jsonb_typeof(amostra) = 'array' then jsonb_array_length(amostra) <= 60 else false end),
  detalhe       jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object'),
  estado        text not null default 'medindo' check (estado in ('medindo', 'sombra', 'em_uso', 'pergunta', 'travado')),
  texto         text check (char_length(texto) <= 400),
  calculado_em  timestamptz not null,
  em_uso_desde  timestamptz,
  travado_ate   date,
  travado_valor numeric(10,2),
  pergunta_id   uuid,
  acao_id       uuid,
  historico     jsonb not null default '[]'
                  check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  unique (item, chave),
  -- Em uso tem valor; medindo e sombra não têm; a pergunta e a trava guardam o que está valendo (nulo = o padrão). Ver
  -- "CORREÇÕES SOBRE A SPEC" no cabeçalho.
  constraint aprendizado_em_uso_coerente  check ((estado <> 'em_uso' or em_uso is not null)
                                                 and (estado not in ('medindo', 'sombra') or em_uso is null)),
  constraint aprendizado_travado_coerente check ((estado = 'travado') = (travado_ate is not null)),
  constraint aprendizado_pergunta_tem_id  check (estado <> 'pergunta' or pergunta_id is not null)
);

comment on table public.agenda_aprendizado is
  'Agenda de Produção (Fase 6): um valor aprendido por (item, chave) — fator por classe de campo, R$ por diária, presença do dono por classe, atraso e prazo por fornecedor, capacidade do dono, pontualidade com o cliente (só medida), folga do aviso, carga pelo plano cumprido e os gatilhos do planejador — com o padrão de hoje, o calculado, o em uso, o n, o mínimo, a amostra e o estado. Só _agenda_aprendizado_gravar escreve; todo leitor passa por _agenda_aprendido (nulo = o padrão de hoje). NUNCA apagado; item, chave e nível não mudam.';
comment on column public.agenda_aprendizado.chave is '''rv:energia'' (fina), ''sistema:energia'', ''bem:rv'', ''todas'', o id do fornecedor, ''dono'', ''gatilhos''.';
comment on column public.agenda_aprendizado.padrao is 'O valor de hoje (o parâmetro de agenda_config ou a regra), que vale enquanto nada está em uso.';
comment on column public.agenda_aprendizado.estado is 'medindo (n < n_min); sombra (tem n, mas o modo não é ligado ou o item não está na lista); em_uso; pergunta (a troca é grande e espera o dono; em_uso guarda o que vale até a resposta); travado (o dono desfez ou disse "fico com o de agora": vale até travado_ate, ou até o calculado andar mais que o limite de troca a partir de travado_valor).';
comment on column public.agenda_aprendizado.amostra is 'Os pontos da conta (as OS, as entregas, as semanas), até 60.';
comment on column public.agenda_aprendizado.detalhe is 'O que o texto precisa (p50, no prazo, semanas, gatilhos…).';
comment on column public.agenda_aprendizado.texto is 'A linha do foco aprendizado (≤ 400), do banco.';
comment on column public.agenda_aprendizado.historico is '[{em, antes, depois}] de em_uso, estado e calculado quando mudam (os 20 mais novos).';

-- ── 4. Os registros não se apagam e só mudam o permitido ────────────────────────────────────────────────
create or replace function public._agenda_medidas_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if new.service_order_id is distinct from old.service_order_id then
    raise exception 'A medida é da OS: a OS não muda.';
  end if;
  if new.versao is distinct from old.versao + 1
     or jsonb_array_length(new.historico) = 0
     or new.historico = old.historico then
    raise exception 'A medida só muda inteira: versão + 1 e o que mudou no histórico.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_medidas_so_muda() is
  'Agenda de Produção (Fase 6): gatilho BEFORE UPDATE de agenda_medidas_os — a OS não muda; toda mudança leva versao + 1 e uma entrada nova no histórico (agenda_medir_os).';

create or replace function public._agenda_aprendizado_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if (new.id, new.item, new.chave, new.nivel) is distinct from (old.id, old.item, old.chave, old.nivel) then
    raise exception 'O valor aprendido não muda de item, de chave nem de nível.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_aprendizado_so_muda() is
  'Agenda de Produção (Fase 6): gatilho BEFORE UPDATE de agenda_aprendizado — muda tudo menos id, item, chave e nível.';

drop trigger if exists agenda_medidas_os_nao_apaga on public.agenda_medidas_os;
create trigger agenda_medidas_os_nao_apaga before delete on public.agenda_medidas_os
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_medidas_os_so_muda on public.agenda_medidas_os;
create trigger agenda_medidas_os_so_muda before update on public.agenda_medidas_os
  for each row execute function public._agenda_medidas_so_muda();

drop trigger if exists agenda_aprendizado_nao_apaga on public.agenda_aprendizado;
create trigger agenda_aprendizado_nao_apaga before delete on public.agenda_aprendizado
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_aprendizado_so_muda on public.agenda_aprendizado;
create trigger agenda_aprendizado_so_muda before update on public.agenda_aprendizado
  for each row execute function public._agenda_aprendizado_so_muda();

-- ── 5. As listas fechadas ampliadas ─────────────────────────────────────────────────────────────────────
-- Perguntas: os 25 tipos da Fase 5 + aprendizado (CRÍTICA: a troca grande de um valor aprendido, a revisão da carga e os
-- gatilhos do planejador; nada muda sem a resposta).
alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_tipo_check;
alter table public.agenda_perguntas add constraint agenda_perguntas_tipo_check
  check (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono',
                  'conferencia','chegou','parada','estouro','duracao','material_conferir','padrao_do_dono',
                  'diaria','diaria_ligar','equipe_resposta','concluir','entrega',
                  'nfe_vincular','pix_material','previsao_fornecedor','fornecedor_cadastro','fornecedores_prazo',
                  'cliente_aprovar','cliente_aviso','cliente_resposta',
                  'aprendizado'));

-- A coluna gerada: aprendizado passa a ser crítica. SET EXPRESSION (Postgres 17+, o molde de 20261026100000 e 20261028100000)
-- mantém a coluna no lugar e reconstrói e revalida critica_tem_opcoes e critica_decidida com o mesmo nome. Só se a expressão
-- ainda não tem 'aprendizado' (rodar de novo não reescreve a tabela).
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''aprendizado''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_perguntas.critica: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_perguntas alter column critica set expression as
      (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono','diaria','cliente_aviso',
                'aprendizado'));
  end if;
end
$$;

comment on column public.agenda_perguntas.chave is
  'chegou:<os_material>:<previsao_ate>, conferencia:<dia>, nao_cabe:<os>:<versao>… — a mesma pergunta não abre duas vezes. Fase 4: fornecedor_cadastro:<fornecedor> e fornecedores_prazo (uma só), que o *grava* do prazo do fornecedor resolve. Fase 5: cliente_aprovar:<mensagem>, cliente_aviso:<os>:<dia_alvo>, cliente_resposta:<resposta>. Fase 6: aprendizado:<item>:<chave> (uma aberta por chave).';

alter table public.agenda_acoes drop constraint if exists agenda_acoes_tipo_check;
alter table public.agenda_acoes add constraint agenda_acoes_tipo_check
  check (tipo in ('publicar','criar','mover','cancelar','fixar','promover_reserva','soltar_reserva','status','resultado',
                  'desfazer','diaria','concluir','entregar','equipe','material','fornecedor','cliente',
                  'aprendizado'));

-- A rodada do aprendizado (P6: agenda_aprender) grava a rodada na mesma tabela. A agenda_saude já filtra por rotina.
alter table public.agenda_vigia_rodadas drop constraint if exists agenda_vigia_rodadas_rotina_check;
alter table public.agenda_vigia_rodadas add constraint agenda_vigia_rodadas_rotina_check
  check (rotina in ('vigia', 'rotina', 'material', 'cliente', 'aprender'));

comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor); Fase 5: cliente (as mensagens-modelo ao cliente); Fase 6: aprender (a medição e o aprendizado, uma vez por dia). As rodadas de antes são da vigia.';

-- ── 6. Portas: RLS, só leitura, escrita só pelas funções ────────────────────────────────────────────────
alter table public.agenda_medidas_os  enable row level security;
alter table public.agenda_aprendizado enable row level security;

drop policy if exists agenda_medidas_os_leitura on public.agenda_medidas_os;
create policy agenda_medidas_os_leitura on public.agenda_medidas_os
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_aprendizado_leitura on public.agenda_aprendizado;
create policy agenda_aprendizado_leitura on public.agenda_aprendizado
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_medidas_os, public.agenda_aprendizado from public, anon, authenticated;
grant select on table public.agenda_medidas_os, public.agenda_aprendizado to authenticated;
grant all on table public.agenda_medidas_os, public.agenda_aprendizado to service_role;

-- Funções de gatilho: sem grant a ninguém.
revoke all on function public._agenda_medidas_so_muda(), public._agenda_aprendizado_so_muda()
  from public, anon, authenticated;
