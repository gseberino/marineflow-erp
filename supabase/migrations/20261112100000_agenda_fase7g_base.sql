-- Agenda de Produção, Fase 7, etapa 7g ("Mostrar como pensou e provar o trabalho"), pacote P1: a base — os 4 interruptores e os 18 parâmetros da etapa, o lugar
-- do porquê na alocação e na ação, as 3 tabelas (as marcações medidas, o nível do tipo de OS e o placar da semana), as 2 listas que somam um valor e as peças
-- pequenas do porquê (quem marcou, o degrau, a zona mais severa e os textos da fonte da duração, das suposições, do critério e do degrau).
-- Spec: scratchpad agenda-pesquisa/spec-fase7g.md (§4, §5.1, §6.1, §8.1, §8.3 agenda_fase7g_base.sql e o bloco R9, que vale sobre o corpo: R9.2, R9.3-1, R9.4-1,
-- R9.4-2, R9.4-4, R9.5-5, R9.5-8, R9.12-12, R9.13); nomes: fase7-registro.md; respostas do dono: fase7-padroes.md (AG7-25 rebaixar; AG7-26 placar; AG7-27 o motivo
-- ferramenta; AG7-28 1 motivo; AG7-33 os dois números da duração; AG7-18 o local pelo nome).
-- Depende das Fases 1 a 6, das etapas 7a a 7d, da 7f inteira e da 7e até o P3 (última: 20261111100200). NÃO recria nenhuma função de antes: só acrescenta.
--
-- ═══ DDL — OK NOMEADO ═══ (22 colunas novas em agenda_config — 4 interruptores e 18 parâmetros — e o DEFAULT dos 4 interruptores; 2 colunas novas em
-- agenda_alocacoes e 2 em agenda_acoes; 3 tabelas novas com RLS e 6 gatilhos; 2 listas fechadas pelo ampliador; 21 CHECKs novos por nome em agenda_config, 2 em
-- agenda_alocacoes e 2 em agenda_acoes; 2 índices; 11 funções novas, 3 delas de gatilho)
-- NÃO APLICADA. Existe para revisão e espera o OK. Nada aqui é copiado de outra migration: só colunas, tabelas, CHECKs e funções novas.
--
-- POR QUE: a agenda não guarda por que marcou, não mede o que o dono corrige e não leva placar nenhum. Esta migration só cria o lugar: os interruptores (nascem
-- desligados na linha), os parâmetros, as colunas que vão guardar o porquê na hora da decisão (nulas = de antes da 7g), as tabelas que os pacotes seguintes
-- enchem e as peças de texto que eles juntam. Quem usa são os pacotes seguintes (20261112100100 em diante), sempre atrás dos interruptores.
--
-- O QUE MUDA:
--   1. agenda_config: modo_porque, modo_explicar, modo_placar e modo_rebaixar, desligado | sombra | ligado; a linha fica 'desligado' e o DEFAULT vira 'sombra'
--      (como de 7a a 7e); quem os põe em sombra é a migration de dado 20261112100990, com OK nomeado. Os 15 parâmetros da §4.1 (porque_motivos_max 1, AG7-28;
--      origens_do_dono; livre_semanas 4; como_pensei_*; correcao_janela_du; os 6 do rebaixar, AG7-25; explicar_hora 16:35; placar_janela, AG7-26;
--      placar_semanas_hist) e os 3 do R9: marcacoes_desde (nula; o dado grava a hora dele: nada de antes entra na medida, R9.4-2), placar_min_linhas 3 (R9.4-3)
--      e explicar_tempo_max 15 s (R9.5-8). CHECK por nome em cada um, menos marcacoes_desde (nula e sem limite: 21 CHECKs para as 22 colunas); o de
--      origens_do_dono é a lista de agenda_acoes.origem lida do CHECK vivo no dia da migration.
--   2. agenda_alocacoes: suposicoes (jsonb NULA, sem DEFAULT: nula = marcada antes da 7g ou com modo_porque desligado; [] = sem suposição; R9.4-1) e degrau.
--      agenda_acoes: zona e degrau. Nascem nulas em todas as linhas; nada as escreve aqui (o P2 escreve, no INSERT).
--   3. agenda_marcacoes (nova): uma linha por (ação executada, OS) que criou meio-dia que não é reserva, com o desfecho da do gestor e conferida (R9.4-2: algum
--      meio-dia cumprido ou parcial na hora do desfecho; o silêncio não é aceite). tipo_acao tem 7 valores (+ reparar e reestimar, R9.4-2).
--      agenda_tipos_os (nova): o nível de cada classe de campo (o P5 grava só teria e texto; o P5b, o nível). agenda_placar_semanas (nova): o placar guardado.
--      Não se apagam direto: a marcação sai em cascata com a OS (WHEN pg_trigger_depth() = 0 no gatilho de apagar, R9.12-12: sem isso a OS aberta com
--      marcação não sairia mais pela tela). A marcação só muda o desfecho, uma vez, de aberta para decidida (versão + 1 e histórico); o tipo de OS muda tudo
--      menos a classe (o SET NULL da ação passa); o placar muda inteiro (versão + 1 e histórico) e enviado_em vai de nulo a um valor uma vez.
--   4. agenda_alocacoes.motivo ganha ferramenta (AG7-27: "faltou ferramenta ou carro"); agenda_vigia_rodadas.rotina ganha explicar. Pelo ampliador da 7a.
--      capacidade_motivos continua a lista de antes (ferramenta não é falta do dono). As listas do ok do dono (ok_marcacao, ok_do_dono, nivel) e as colunas
--      espera_ok_desde/ok_do_dono_* de os_planejamento são do P5b (R9.4-4), não daqui.
--   5. Funções novas: _agenda_suposicoes_validas (o CHECK), _agenda_quem_marcou, _agenda_degrau, _agenda_zona_mais_severa e os 4 textos (_agenda_duracao_fonte_texto,
--      com p_texto_vies do AG7-33; _agenda_suposicao_texto; _agenda_criterio_texto, com os 10 critérios do CHECK do 7c, R9.5-5; _agenda_degrau_texto); e os
--      gatilhos _agenda_marcacoes_so_muda, _agenda_tipos_os_so_muda e _agenda_placar_so_muda. Nada de antes as chama.
--
-- O QUE NÃO MUDA: nenhuma função de antes é recriada; nenhuma linha é escrita (as colunas novas nascem nulas, as tabelas vazias). As listas de antes continuam com
-- os mesmos valores, na mesma ordem (as 2 só somam no fim).
--
-- ORDEM DE LIGAR (spec R9.14): depois da 7f inteira e da 7e inteira publicadas; antes de 20261112100100 (P2), que lê as colunas novas. À noite, depois das 21:00,
-- logo depois de um tique, com LOCK_TIMEOUT=5s: há ALTER TABLE em agenda_config, agenda_alocacoes e agenda_acoes. Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7g_base.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261112100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261112100000_agenda_fase7g_base.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261112100000', 'agenda_fase7g_base');"
--
-- DESFAZER (só com os interruptores desligados e nada usando; os pacotes seguintes gravam nestas colunas e tabelas):
--   drop table if exists public.agenda_marcacoes, public.agenda_tipos_os, public.agenda_placar_semanas;
--   drop function if exists public._agenda_marcacoes_so_muda(), public._agenda_tipos_os_so_muda(), public._agenda_placar_so_muda(),
--     public._agenda_quem_marcou(text, text), public._agenda_degrau(jsonb, jsonb, date, date, date), public._agenda_degrau_texto(text),
--     public._agenda_zona_mais_severa(text[]), public._agenda_suposicao_texto(text, jsonb), public._agenda_duracao_fonte_texto(text, numeric, numeric, text),
--     public._agenda_criterio_texto(text);
--   alter table public.agenda_acoes drop constraint if exists agenda_acoes_zona_check, drop constraint if exists agenda_acoes_degrau_check,
--     drop column if exists zona, drop column if exists degrau;
--   alter table public.agenda_alocacoes drop constraint if exists alocacao_suposicoes_validas, drop constraint if exists alocacao_degrau_check,
--     drop column if exists suposicoes, drop column if exists degrau;
--   drop function if exists public._agenda_suposicoes_validas(jsonb);
--   (agenda_config: drop dos 21 CHECKs e das 22 colunas; agenda_alocacoes_motivo_check e agenda_vigia_rodadas_rotina_check: recriar sem ferramenta e sem explicar,
--    só com nenhuma linha que os use.)
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (só cria o que falta), o ampliador (soma só o que falta), create table if not exists,
-- create index if not exists, drop trigger if exists + create, drop policy if exists + create, create or replace function, revoke/grant e comment.

-- ── 1. agenda_config: os interruptores e os parâmetros ──────────────────────────────────────────────
alter table public.agenda_config
  -- os interruptores: a linha fica 'desligado' até a migration de dado 20261112100990 (o molde de 7a a 7e); o DEFAULT passa a 'sombra' abaixo
  add column if not exists modo_porque             text         not null default 'desligado',
  add column if not exists modo_explicar           text         not null default 'desligado',
  add column if not exists modo_placar             text         not null default 'desligado',
  add column if not exists modo_rebaixar           text         not null default 'desligado',   -- AG7-25
  -- o porquê
  add column if not exists porque_motivos_max      smallint     not null default 1,             -- AG7-28
  add column if not exists origens_do_dono         text[]       not null default '{dono,assistente,tela}',
  -- as leituras
  add column if not exists livre_semanas           smallint     not null default 4,
  add column if not exists como_pensei_perguntas   smallint     not null default 3,
  add column if not exists como_pensei_itens_max   smallint     not null default 5,
  -- as marcações e o rebaixamento
  add column if not exists correcao_janela_du      smallint     not null default 10,
  add column if not exists rebaixar_janela_semanas smallint     not null default 8,             -- AG7-25
  add column if not exists rebaixar_n_min          smallint     not null default 3,             -- AG7-25
  add column if not exists rebaixar_taxa           numeric(3,2) not null default 0.50,          -- AG7-25
  add column if not exists rebaixar_amostra        smallint     not null default 6,             -- AG7-25
  add column if not exists voltar_n                smallint     not null default 3,             -- AG7-25
  add column if not exists rebaixar_trava_dias     smallint     not null default 28,
  -- a rodada e o placar
  add column if not exists explicar_hora           time         not null default '16:35',       -- antes da revisão (16:45, 7a) e da mensagem da quinta (16:50, 7f)
  add column if not exists placar_janela           text         not null default 'semana_passada', -- AG7-26
  add column if not exists placar_semanas_hist     smallint     not null default 8,
  -- R9.4-2: só entra na medida a ação criada desde aqui (nula até o dado 20261112100990, que grava a hora dele)
  add column if not exists marcacoes_desde         timestamptz,
  -- R9.4-3: abaixo disso a quinta não leva placar (a rodada grava igual)
  add column if not exists placar_min_linhas       smallint     not null default 3,
  -- R9.5-8: o relógio da rodada explicar, conferido entre os passos (o molde de aprender_tempo_max)
  add column if not exists explicar_tempo_max      interval     not null default '15 seconds';

-- Como de 7a a 7e: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem a põe em sombra é a migration de
-- dado 20261112100990, com OK nomeado.
alter table public.agenda_config
  alter column modo_porque   set default 'sombra',
  alter column modo_explicar set default 'sombra',
  alter column modo_placar   set default 'sombra',
  alter column modo_rebaixar set default 'sombra';

-- origens_do_dono: não vazia, sem nulo e dentro da lista de agenda_acoes.origem. CHECK não lê outra tabela: a lista é lida do CHECK vivo (o molde de
-- _agenda_ampliar_lista, que só amplia) e escrita aqui como texto. Se a lista de origens crescer depois, esta continua a de hoje (mais estreita, nunca mais larga).
do $$
declare
  r       record;
  v_def   text;
  v_lista text[];
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conrelid = 'public.agenda_acoes'::regclass and c.conname = 'agenda_acoes_origem_check' and c.contype = 'c';
  if v_def is null then
    raise exception 'Fase 7g P1: o CHECK agenda_acoes_origem_check não existe; origens_do_dono não tem contra o que conferir.' using errcode = '42704';
  end if;
  select array_agg(replace(m[1], '''''', '''') order by o) into v_lista
    from regexp_matches(v_def, '''((?:[^'']|'''')*)''', 'g') with ordinality t(m, o);
  for r in
    select * from (values
      ('agenda_config_modo_porque_check',             'check (modo_porque in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_explicar_check',           'check (modo_explicar in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_placar_check',             'check (modo_placar in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_rebaixar_check',           'check (modo_rebaixar in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_porque_motivos_max_check',      'check (porque_motivos_max between 0 and 3)'),
      ('agenda_config_origens_do_dono_check',
       format('check (cardinality(origens_do_dono) > 0 and array_position(origens_do_dono, null) is null and origens_do_dono <@ %L::text[])', v_lista)),
      ('agenda_config_livre_semanas_check',           'check (livre_semanas between 2 and 8)'),
      ('agenda_config_como_pensei_perguntas_check',   'check (como_pensei_perguntas between 1 and 5)'),
      ('agenda_config_como_pensei_itens_max_check',   'check (como_pensei_itens_max between 3 and 10)'),
      ('agenda_config_correcao_janela_du_check',      'check (correcao_janela_du between 3 and 20)'),
      ('agenda_config_rebaixar_janela_semanas_check', 'check (rebaixar_janela_semanas between 4 and 26)'),
      ('agenda_config_rebaixar_n_min_check',          'check (rebaixar_n_min between 2 and 10)'),
      ('agenda_config_rebaixar_taxa_check',           'check (rebaixar_taxa between 0.20 and 0.90)'),
      -- a amostra nunca é menor que o mínimo que decide
      ('agenda_config_rebaixar_amostra_check',        'check (rebaixar_amostra between rebaixar_n_min and 20)'),
      ('agenda_config_voltar_n_check',                'check (voltar_n between 2 and 10)'),
      ('agenda_config_rebaixar_trava_dias_check',     'check (rebaixar_trava_dias between 7 and 90)'),
      -- o placar tem de estar guardado antes da mensagem da quinta (dono_semana_hora, 7f)
      ('agenda_config_explicar_hora_check',           'check (explicar_hora >= ''12:00'' and explicar_hora < dono_semana_hora)'),
      ('agenda_config_placar_janela_check',           'check (placar_janela in (''semana_passada'', ''ultimos_7_dias''))'),
      ('agenda_config_placar_semanas_hist_check',     'check (placar_semanas_hist between 4 and 26)'),
      ('agenda_config_placar_min_linhas_check',       'check (placar_min_linhas between 1 and 10)'),
      -- abaixo dos 30 s de statement_timeout do service_role, senão o relógio nunca dispara antes do corte (R9.5-8, o molde de aprender_tempo_max)
      ('agenda_config_explicar_tempo_max_check',
       'check (explicar_tempo_max between interval ''5 seconds'' and interval ''25 seconds'')')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.agenda_config.modo_porque is
  'Agenda de Produção (Fase 7g): o porquê gravado na hora da decisão (as suposições, a fonte, o degrau na alocação; a zona e o degrau na ação) e as marcações medidas. Sombra grava e não mostra; ligado mostra na tela e nas leituras. Não lê o freio: grava o que acontecer (R9.6).';
comment on column public.agenda_config.modo_explicar is
  'Agenda de Produção (Fase 7g): as leituras novas (como pensei, o porquê da OS, o livre de 4 semanas e o "se aprovar hoje" pelo encaixe). Sombra: as leituras de antes, com a nova em dados.teste. Ligar não exige o freio solto (R9.14).';
comment on column public.agenda_config.modo_placar is
  'Agenda de Produção (Fase 7g, AG7-26): o placar da semana. Sombra calcula, guarda e responde com "Em teste:"; ligado vai na mensagem da quinta da 7f (que depende do lote ligado).';
comment on column public.agenda_config.modo_rebaixar is
  'Agenda de Produção (Fase 7g, AG7-25): o tipo de OS com muita correção volta a esperar o ok do dono. Sombra só calcula o que seria (teria e texto); ligado é do P5b e só age com modo_veto e modo_marcar_sozinho ligados e a linha crua (R9.6).';
comment on column public.agenda_config.porque_motivos_max is 'Agenda de Produção (Fase 7g, AG7-28 "1, o principal"): quantas suposições o texto de cada marcação diz, além da fonte da duração. 0..3.';
comment on column public.agenda_config.origens_do_dono is
  'Agenda de Produção (Fase 7g): as origens de ação que contam como marcação do dono (_agenda_quem_marcou); o resto é do gestor. Não vazia e dentro da lista de agenda_acoes.origem do dia da migration.';
comment on column public.agenda_config.livre_semanas is 'Agenda de Produção (Fase 7g): quantas semanas o *livre* mostra com modo_explicar ligado. 2..8.';
comment on column public.agenda_config.como_pensei_perguntas is 'Agenda de Produção (Fase 7g): quantas perguntas o "como pensei" leva em "Preciso de você". 1..5.';
comment on column public.agenda_config.como_pensei_itens_max is 'Agenda de Produção (Fase 7g): quantas marcações o "como pensei" lista antes do "(e mais N…)". 3..10.';
comment on column public.agenda_config.correcao_janela_du is 'Agenda de Produção (Fase 7g): dias úteis sem 1º dia depois dos quais a marcação aberta conta como aceita. 3..20.';
comment on column public.agenda_config.rebaixar_janela_semanas is 'Agenda de Produção (Fase 7g, AG7-25): as semanas olhadas para a amostra do tipo de OS. 4..26.';
comment on column public.agenda_config.rebaixar_n_min is 'Agenda de Produção (Fase 7g, AG7-25): o mínimo de marcações decididas no tipo de OS para o rebaixar decidir. 2..10.';
comment on column public.agenda_config.rebaixar_taxa is 'Agenda de Produção (Fase 7g, AG7-25): a fração corrigida (ajustada + desfeita) que faz o tipo de OS esperar o ok. 0,20..0,90.';
comment on column public.agenda_config.rebaixar_amostra is 'Agenda de Produção (Fase 7g, AG7-25): quantas marcações decididas mais novas entram na amostra. rebaixar_n_min..20.';
comment on column public.agenda_config.voltar_n is 'Agenda de Produção (Fase 7g, AG7-25): quantas aceitas seguidas fazem o tipo de OS voltar a marcar sozinho. 2..10.';
comment on column public.agenda_config.rebaixar_trava_dias is 'Agenda de Produção (Fase 7g): depois do *desfaz espera*, por quantos dias o tipo de OS não volta a esperar o ok. 7..90.';
comment on column public.agenda_config.explicar_hora is 'Agenda de Produção (Fase 7g): a partir desta hora a rodada explicar faz a parte diária. De 12:00 até antes de dono_semana_hora (o placar guardado antes da mensagem da quinta).';
comment on column public.agenda_config.placar_janela is 'Agenda de Produção (Fase 7g, AG7-26): a semana medida no placar — semana_passada (a semana ISO anterior, completa) ou ultimos_7_dias.';
comment on column public.agenda_config.placar_semanas_hist is 'Agenda de Produção (Fase 7g): quantas semanas guardadas o *agenda placar* compara. 4..26.';
comment on column public.agenda_config.marcacoes_desde is
  'Agenda de Produção (Fase 7g, R9.4-2): só entra em agenda_marcacoes a ação criada desde aqui. Nula até a migration de dado 20261112100990, que grava a hora dela: o plano de antes da 7g não vira aceite no placar.';
comment on column public.agenda_config.placar_min_linhas is 'Agenda de Produção (Fase 7g, R9.4-3): com menos linhas com dado (sem contar mensagens), a quinta não leva placar; a rodada grava igual. 1..10.';
comment on column public.agenda_config.explicar_tempo_max is 'Agenda de Produção (Fase 7g, R9.5-8): o tempo da rodada explicar, conferido entre os passos; passou daí, ela pula o resto. 5..25 s, abaixo do corte de 30 s do service_role.';

-- ── 2. O lugar do porquê: agenda_alocacoes e agenda_acoes ───────────────────────────────────────────
-- R9.4-1: suposicoes nula, sem DEFAULT (nula = de antes da 7g ou com modo_porque desligado; [] = sem suposição). A fonte da duração já existe (duracao_fonte, 7a)
-- e o critério da pessoa também (criterio, 7c): não se duplicam aqui.
-- O CHECK das suposições (§5.1): nula passa (de antes da 7g); senão uma lista de até 12 objetos, cada um com codigo da lista do §3.1 item 3 e detalhe objeto.
-- A lista mora só aqui: um código novo entra neste array e no texto (_agenda_suposicao_texto).
create or replace function public._agenda_suposicoes_validas(p jsonb)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p is null then true
    when jsonb_typeof(p) <> 'array' then false
    when jsonb_array_length(p) > 12 then false
    else not exists (
      select 1 from jsonb_array_elements(p) e
       where jsonb_typeof(e) <> 'object'
          or jsonb_typeof(e -> 'codigo') is distinct from 'string'
          or (e ->> 'codigo') <> all (array['prazo_padrao_peca', 'quanto_falta_padrao', 'local_suposto', 'bem_disponivel', 'disponibilidade_suposta',
                                            'compra_interna_padrao', 'sinal_a_cobrar', 'duracao_orcamento', 'uma_pessoa', 'peca_nao_segura', 'sem_peca',
                                            'dono_abre_fecha'])
          or jsonb_typeof(e -> 'detalhe') is distinct from 'object')
  end;
$function$;

comment on function public._agenda_suposicoes_validas(jsonb) is
  'Agenda de Produção (Fase 7g, P1; §5.1, R9.4-1): o CHECK de agenda_alocacoes.suposicoes. Nula = true (marcada antes da 7g). Senão: lista de até 12 objetos, cada um com codigo (texto) na lista do §3.1 item 3 e detalhe (objeto). IMMUTABLE, invoker. O CHECK roda como quem escreve: execute só para service_role (que grava direto; a definer roda como o dono); authenticated não grava agenda_alocacoes (só select, Fase 2) e fica sem porta (§3.1 item 13).';

alter table public.agenda_alocacoes
  add column if not exists suposicoes jsonb,
  add column if not exists degrau     text;
alter table public.agenda_acoes
  add column if not exists zona   text,
  add column if not exists degrau text;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('public.agenda_alocacoes', 'alocacao_suposicoes_validas', 'check (public._agenda_suposicoes_validas(suposicoes))'),
      ('public.agenda_alocacoes', 'alocacao_degrau_check',       'check (degrau in (''pessoa'', ''turno'', ''dia'', ''data'', ''tirou''))'),
      ('public.agenda_acoes',     'agenda_acoes_zona_check',     'check (zona in (''travada'', ''firme'', ''livre''))'),
      ('public.agenda_acoes',     'agenda_acoes_degrau_check',   'check (degrau in (''pessoa'', ''turno'', ''dia'', ''data'', ''tirou''))')
    ) as c(tabela, nome, regra)
  loop
    if not exists (select 1 from pg_constraint where conrelid = r.tabela::regclass and conname = r.nome) then
      execute format('alter table %s add constraint %I %s', r.tabela, r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.agenda_alocacoes.suposicoes is
  'Agenda de Produção (Fase 7g, R9.4-1): o que o motor supôs na hora de marcar, [{codigo, detalhe}] na ordem do §3.1 item 3 (_agenda_suposicoes_validas). NULA = marcada antes da 7g ou com modo_porque desligado; [] = sem suposição. Só nasce no INSERT (P2).';
comment on column public.agenda_alocacoes.degrau is
  'Agenda de Produção (Fase 7g): o degrau de reparo da alocação que substituiu outra (pessoa, turno, dia, data ou tirou; _agenda_degrau). Nulo = marcação nova. Só nasce no INSERT (P2).';
comment on column public.agenda_acoes.zona is
  'Agenda de Produção (Fase 7g): a zona mais severa (travada > firme > livre, _agenda_zona da 7f) do dia mais cedo que a ação tocou. Só nasce no INSERT (P2); o gatilho de "só desfaz" já não a deixa mudar.';
comment on column public.agenda_acoes.degrau is
  'Agenda de Produção (Fase 7g): o degrau da ação (pessoa, turno, dia, data ou tirou; _agenda_degrau). Nulo em publicar ou criar sem antes. Só nasce no INSERT (P2).';

-- ── 3. As tabelas novas ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_marcacoes (
  acao_id          uuid not null references public.agenda_acoes(id) on delete restrict,
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  primary key (acao_id, service_order_id),
  quem             text not null check (quem in ('gestor', 'dono')),
  origem_acao      text not null,
  tipo_acao        text not null check (tipo_acao in ('publicar', 'criar', 'mover', 'promover_reserva', 'fixar', 'reparar', 'reestimar')),
  classe           text not null check (char_length(classe) between 3 and 40),
  duracao_fonte    text check (duracao_fonte in ('dono', 'aceita', 'orcamento', 'sugerida')),
  suposicoes       text[] not null default '{}',
  de               date not null,
  ate              date not null,
  meios            smallint not null check (meios > 0),
  pessoas          uuid[] not null,
  marcada_em       timestamptz not null,
  primeiro_inicio  timestamptz not null,
  aprovada_em      timestamptz,
  zona             text check (zona in ('travada', 'firme', 'livre')),
  degrau           text check (degrau in ('pessoa', 'turno', 'dia', 'data', 'tirou')),
  desfecho         text check (desfecho in ('aberta', 'aceita', 'ajustada', 'desfeita', 'remarcada', 'saiu')),
  ajustes          text[] not null default '{}' check (ajustes <@ '{duracao,pessoa,dia,tirou,material}'::text[]),
  desfecho_em      timestamptz,
  desfecho_acao_id uuid references public.agenda_acoes(id) on delete restrict,
  conferida        boolean not null default false,
  versao           smallint not null default 1,
  historico        jsonb not null default '[]'
                     check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  constraint marcacao_desfecho_so_gestor check ((quem = 'gestor') = (desfecho is not null)),
  constraint marcacao_decidida_tem_data  check ((desfecho in ('aceita', 'ajustada', 'desfeita', 'remarcada', 'saiu')) = (desfecho_em is not null)),
  constraint marcacao_ajustes_coerentes  check ((desfecho = 'ajustada') = (cardinality(ajustes) > 0)),
  constraint marcacao_periodo            check (de <= ate)
);

create index if not exists agenda_marcacoes_classe  on public.agenda_marcacoes(classe, desfecho_em desc) where quem = 'gestor';
create index if not exists agenda_marcacoes_abertas on public.agenda_marcacoes(service_order_id) where desfecho = 'aberta';

comment on table public.agenda_marcacoes is
  'Agenda de Produção (Fase 7g): uma linha por (ação executada, OS) que criou meio-dia que não é reserva, desde agenda_config.marcacoes_desde (R9.4-2). Quem marcou, a classe da OS, a fonte e as suposições da 1ª alocação, o período, e o desfecho da do gestor (aberta → aceita, ajustada, desfeita, remarcada ou saiu, uma vez). A do dono não tem desfecho. Não se apaga direto: sai em cascata com a OS. Escrita só pela rodada explicar (P5).';
comment on column public.agenda_marcacoes.quem is 'gestor ou dono (_agenda_quem_marcou). A origem cliente não entra (R9.4-2).';
comment on column public.agenda_marcacoes.origem_acao is 'agenda_acoes.origem (cópia).';
comment on column public.agenda_marcacoes.tipo_acao is 'O tipo da ação que marcou: publicar, criar, mover, promover_reserva, fixar, reparar ou reestimar (estes dois, do gestor da 7a, criam alocação: R9.4-2).';
comment on column public.agenda_marcacoes.classe is '_agenda_classe_de_campo(os) ->> ''chave'' na hora da marcação (rv:energia, barco:motor…).';
comment on column public.agenda_marcacoes.suposicoes is 'Só os códigos, da 1ª alocação criada (o detalhe fica na alocação).';
comment on column public.agenda_marcacoes.primeiro_inicio is 'lower(periodo) da 1ª alocação: até aqui, o que o dono muda é correção da marcação.';
comment on column public.agenda_marcacoes.aprovada_em is 'A aprovação da OS (coalesce(converted_to_os_at, signed_at, created_at), R9.5-7), para "da aprovação à data".';
comment on column public.agenda_marcacoes.desfecho is 'Só do gestor: aberta até decidir; aceita, ajustada, desfeita, remarcada ou saiu, uma vez (decidida não volta).';
comment on column public.agenda_marcacoes.ajustes is 'Na ajustada: o que o dono corrigiu (duracao, pessoa, dia, tirou, material).';
comment on column public.agenda_marcacoes.conferida is
  'Agenda de Produção (Fase 7g, R9.4-2): algum meio-dia da marcação com resultado cumprido ou parcial na hora do desfecho. "Ficaram como fiz" sem conferência é silêncio, não aceite: o texto diz "nenhuma conferida".';
comment on column public.agenda_marcacoes.historico is '[{em, antes, depois}] da mudança de desfecho (os 20 mais novos).';

create table if not exists public.agenda_tipos_os (
  classe           text primary key check (char_length(classe) between 3 and 40),
  nivel            text not null default 'sozinho' check (nivel in ('sozinho', 'espera_ok')),
  teria            text check (teria in ('sozinho', 'espera_ok')),
  n                smallint not null default 0,
  corrigidas       smallint not null default 0,
  aceitas_seguidas smallint not null default 0,
  amostra          jsonb not null default '[]'
                     check (case when jsonb_typeof(amostra) = 'array' then jsonb_array_length(amostra) <= 20 else false end),
  desde            timestamptz,
  acao_id          uuid references public.agenda_acoes(id) on delete set null,
  travado_ate      date,
  calculado_em     timestamptz not null,
  texto            text check (char_length(texto) <= 300),
  historico        jsonb not null default '[]'
                     check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  constraint tipo_espera_tem_desde check ((nivel = 'espera_ok') = (desde is not null))
);

comment on table public.agenda_tipos_os is
  'Agenda de Produção (Fase 7g, AG7-25): uma linha por classe de campo que o gestor marca: o nível (sozinho | espera_ok), o que seria em sombra (teria), a amostra e a trava. O P5 grava teria e texto; o nível é do P5b. Muda tudo menos a classe. Não se apaga.';
comment on column public.agenda_tipos_os.teria is 'Em sombra: o nível que a regra do AG7-25 daria.';
comment on column public.agenda_tipos_os.desde is 'Desde quando espera o ok (só com nivel espera_ok).';
comment on column public.agenda_tipos_os.acao_id is 'A ação nivel que mudou o nível (P5b).';
comment on column public.agenda_tipos_os.travado_ate is 'Depois do *desfaz espera*: até este dia, a classe não volta a esperar o ok.';

create table if not exists public.agenda_placar_semanas (
  semana        date primary key check (extract(isodow from semana) = 1),
  de            date not null,
  ate           date not null,
  modo          text not null check (modo in ('sombra', 'ligado')),
  numeros       jsonb not null check (jsonb_typeof(numeros) = 'object'),
  texto         text not null check (char_length(texto) between 3 and 1000),
  linha         text not null check (char_length(linha) between 3 and 300),
  calculado_em  timestamptz not null,
  enviado_em    timestamptz,
  versao        smallint not null default 1,
  historico     jsonb not null default '[]'
                  check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 10 else false end),
  constraint placar_periodo check (de <= ate)
);

comment on table public.agenda_placar_semanas is
  'Agenda de Produção (Fase 7g, AG7-26): o placar da semana medida, guardado (a segunda da semana é a chave). Muda inteiro (versão + 1 e histórico); enviado_em vai de nulo a um valor uma vez, quando a quinta leva o placar. Não se apaga. Escrita só pela rodada explicar (P6).';
comment on column public.agenda_placar_semanas.numeros is 'As chaves fixas do §5.6 (cobertura, aprovacao, marcacoes, correcoes, zonas, ppc, estimativa, compras, perguntas, mensagens, perdidos, tipos).';
comment on column public.agenda_placar_semanas.enviado_em is 'Quando a mensagem da quinta com este placar saiu (de nulo a um valor, uma vez).';

-- Os gatilhos. A marcação: só o desfecho muda, de aberta para decidido, uma vez (versão + 1 e uma entrada nova no histórico). Decidida, ou do dono, não muda mais
-- (depois do 1º dia, o que o dono muda é replano do serviço em andamento, não correção da marcação: §4.3).
create or replace function public._agenda_marcacoes_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  c_mudam constant text[] := array['desfecho', 'ajustes', 'desfecho_em', 'desfecho_acao_id', 'conferida', 'versao', 'historico'];
begin
  if (to_jsonb(new) - c_mudam) is distinct from (to_jsonb(old) - c_mudam) then
    raise exception 'A marcação é o que aconteceu: só o desfecho muda.';
  end if;
  if old.desfecho is distinct from 'aberta' or new.desfecho is not distinct from 'aberta' then
    raise exception 'O desfecho da marcação sai de aberta uma vez, e decidido não volta.';
  end if;
  if new.versao is distinct from old.versao + 1
     or jsonb_array_length(new.historico) = 0
     or new.historico = old.historico then
    raise exception 'A marcação só muda inteira: versão + 1 e o que mudou no histórico.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_marcacoes_so_muda() is
  'Agenda de Produção (Fase 7g, P1; §4.3): gatilho BEFORE UPDATE de agenda_marcacoes — mudam só desfecho, ajustes, desfecho_em, desfecho_acao_id e conferida, uma vez, de aberta para decidido (aceita, ajustada, desfeita, remarcada ou saiu), com versao + 1 e uma entrada nova no histórico. Decidida ou do dono (desfecho nulo) não muda. As FKs de ação são restrict (a ação não se apaga) e a da OS é cascade (apaga, não muda): nenhuma FK escreve por aqui.';

-- O tipo de OS: tudo muda menos a classe (o SET NULL de acao_id passa por aqui sem nada especial).
create or replace function public._agenda_tipos_os_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if new.classe is distinct from old.classe then
    raise exception 'O tipo de OS é a classe: a classe não muda.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_tipos_os_so_muda() is
  'Agenda de Produção (Fase 7g, P1; §4.3): gatilho BEFORE UPDATE de agenda_tipos_os — muda tudo menos a classe (inclusive o ON DELETE SET NULL de acao_id, R9.12-12).';

-- O placar: a semana não muda; os números, o texto, a linha, a hora e o modo mudam juntos com versão + 1 e histórico; enviado_em vai de nulo a um valor, uma vez,
-- sem versão nova. Mudar só a versão ou o histórico, sem conteúdo novo, é recusado.
create or replace function public._agenda_placar_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  c_mudam    constant text[] := array['numeros', 'texto', 'linha', 'calculado_em', 'modo', 'enviado_em', 'versao', 'historico'];
  c_resto    constant text[] := array['enviado_em', 'versao', 'historico'];
  v_mudou    boolean;
begin
  if (to_jsonb(new) - c_mudam) is distinct from (to_jsonb(old) - c_mudam) then
    raise exception 'O placar é da semana: a semana e o período não mudam.';
  end if;
  if old.enviado_em is not null and new.enviado_em is distinct from old.enviado_em then
    raise exception 'O placar enviado não volta: enviado_em vai de nulo a um valor, uma vez.';
  end if;
  v_mudou := (to_jsonb(new) - c_resto) is distinct from (to_jsonb(old) - c_resto);
  if v_mudou then
    if new.versao is distinct from old.versao + 1
       or jsonb_array_length(new.historico) = 0
       or new.historico = old.historico then
      raise exception 'O placar só muda inteiro: versão + 1 e o que mudou no histórico.';
    end if;
  elsif new.versao is distinct from old.versao or new.historico is distinct from old.historico then
    raise exception 'O placar só muda inteiro: versão + 1 e o que mudou no histórico.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_placar_so_muda() is
  'Agenda de Produção (Fase 7g, P1; §4.3): gatilho BEFORE UPDATE de agenda_placar_semanas — semana, de e ate não mudam; numeros, texto, linha, calculado_em e modo mudam com versao + 1 e uma entrada nova no histórico; enviado_em vai de nulo a um valor, uma vez, sem versão nova; versão ou histórico sem conteúdo novo é recusado.';

-- A marcação sai com a OS (cascade: o gatilho da FK roda com profundidade > 0); apagar direto, não. As outras duas não têm cascata: o gatilho vale sempre.
drop trigger if exists agenda_marcacoes_nao_apaga on public.agenda_marcacoes;
create trigger agenda_marcacoes_nao_apaga before delete on public.agenda_marcacoes
  for each row when (pg_trigger_depth() = 0) execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_marcacoes_so_muda on public.agenda_marcacoes;
create trigger agenda_marcacoes_so_muda before update on public.agenda_marcacoes
  for each row execute function public._agenda_marcacoes_so_muda();
drop trigger if exists agenda_tipos_os_nao_apaga on public.agenda_tipos_os;
create trigger agenda_tipos_os_nao_apaga before delete on public.agenda_tipos_os
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_tipos_os_so_muda on public.agenda_tipos_os;
create trigger agenda_tipos_os_so_muda before update on public.agenda_tipos_os
  for each row execute function public._agenda_tipos_os_so_muda();
drop trigger if exists agenda_placar_semanas_nao_apaga on public.agenda_placar_semanas;
create trigger agenda_placar_semanas_nao_apaga before delete on public.agenda_placar_semanas
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_placar_semanas_so_muda on public.agenda_placar_semanas;
create trigger agenda_placar_semanas_so_muda before update on public.agenda_placar_semanas
  for each row execute function public._agenda_placar_so_muda();

-- As portas: RLS nas 3, leitura TO authenticated pelo admin/financeiro; nenhuma policy de escrita; só o service_role escreve (as rodadas, definer, nos pacotes seguintes).
alter table public.agenda_marcacoes      enable row level security;
alter table public.agenda_tipos_os       enable row level security;
alter table public.agenda_placar_semanas enable row level security;
drop policy if exists agenda_marcacoes_leitura on public.agenda_marcacoes;
create policy agenda_marcacoes_leitura on public.agenda_marcacoes
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
drop policy if exists agenda_tipos_os_leitura on public.agenda_tipos_os;
create policy agenda_tipos_os_leitura on public.agenda_tipos_os
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
drop policy if exists agenda_placar_semanas_leitura on public.agenda_placar_semanas;
create policy agenda_placar_semanas_leitura on public.agenda_placar_semanas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
revoke all on table public.agenda_marcacoes, public.agenda_tipos_os, public.agenda_placar_semanas from public, anon, authenticated;
grant select on table public.agenda_marcacoes, public.agenda_tipos_os, public.agenda_placar_semanas to authenticated;
grant all on table public.agenda_marcacoes, public.agenda_tipos_os, public.agenda_placar_semanas to service_role;

-- ── 4. As listas fechadas (o ampliador da 7a; os valores de antes ficam, na mesma ordem) ──────────────
-- AG7-27: o *dia não* e o "como foi" passam a ter "faltou ferramenta ou carro". As palavras e o texto são do P6 (_agenda_motivo_dito, _agenda_motivo_texto, a
-- lista do TS); capacidade_motivos fica sem ele (não é falta do dono).
select public._agenda_ampliar_lista('public.agenda_alocacoes', 'agenda_alocacoes_motivo_check', 'motivo', array['ferramenta']);
-- A rodada explicar (P5) grava como as outras.
select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina', array['explicar']);

-- ── 5. As peças do porquê ────────────────────────────────────────────────────────────────────────────
-- Quem marcou (§3.1 item 6, R9.4-2): dono quando a alocação é do dono (ele pediu o dia) ou a ação veio de uma origem do dono; o resto é do gestor. 2 valores só:
-- quem não é dono é gestor (a origem cliente, que não é marcação do gestor, quem pula é a rodada do P5, não esta leitura). Os dois nulos = gestor.
create or replace function public._agenda_quem_marcou(p_origem_acao text, p_origem_alocacao text default null)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
begin
  if p_origem_alocacao = 'dono' then
    return 'dono';
  end if;
  if p_origem_acao = any ((public._agenda_cfg()).origens_do_dono) then
    return 'dono';
  end if;
  return 'gestor';
end;
$function$;

comment on function public._agenda_quem_marcou(text, text) is
  'Agenda de Produção (Fase 7g, P1; §5.1, §3.1 item 6): dono se a alocação é do dono (origem dono) ou a ação tem origem em agenda_config.origens_do_dono; senão gestor (os dois nulos também). STABLE, sem porta para authenticated (§5.1): execute só para service_role; a definer que a chamar roda como o dono.';

-- O degrau (§3.1 item 4): o que mudou entre o antes e o depois de uma substituição, no formato de agenda_acoes.antes/depois -> 'alocacoes' ([{payee_id, dia,
-- turno, presenca}]). Só os meios de presenca turno contam (abrir e fechar do dono não é degrau; sem a chave, é turno). Do mais barato ao mais caro: pessoa <
-- turno < dia < data < tirou; uma combinação vale o mais caro. Sem antes = nulo (marcação nova); antes e depois iguais = nulo (substituir sem mudar o lugar não
-- é reparo). O limite do "dia": o prometido ao cliente; sem ele, o domingo da semana ISO do fim de antes (antecipar fica no "dia"). Fim nulo = o último dia de
-- cada lado (R9.12-2: nulo explícito, nunca engolido por greatest).
create or replace function public._agenda_degrau(p_antes jsonb, p_depois jsonb, p_fim_antes date, p_fim_depois date, p_prometido_ate date)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_a      text[];
  v_d      text[];
  v_sa     text[];
  v_sd     text[];
  v_dias_a date[];
  v_dias_d date[];
  v_fim_a  date;
  v_fim_d  date;
  v_lim    date;
begin
  -- cada meio-dia de turno como 'dia|turno|pessoa', em ordem: duas listas iguais = os mesmos meios-dias com as mesmas pessoas
  v_a := array(select (e ->> 'dia') || '|' || (e ->> 'turno') || '|' || coalesce(e ->> 'payee_id', '')
                 from jsonb_array_elements(case when jsonb_typeof(p_antes) = 'array' then p_antes else '[]'::jsonb end) e
                where coalesce(e ->> 'presenca', 'turno') = 'turno'
                order by 1);
  v_d := array(select (e ->> 'dia') || '|' || (e ->> 'turno') || '|' || coalesce(e ->> 'payee_id', '')
                 from jsonb_array_elements(case when jsonb_typeof(p_depois) = 'array' then p_depois else '[]'::jsonb end) e
                where coalesce(e ->> 'presenca', 'turno') = 'turno'
                order by 1);
  if cardinality(v_a) = 0 then
    return null;
  end if;
  if cardinality(v_d) = 0 then
    return 'tirou';
  end if;
  if v_a = v_d then
    return null;
  end if;
  v_sa := array(select distinct split_part(x, '|', 1) || '|' || split_part(x, '|', 2) from unnest(v_a) x order by 1);
  v_sd := array(select distinct split_part(x, '|', 1) || '|' || split_part(x, '|', 2) from unnest(v_d) x order by 1);
  if v_sa = v_sd then
    return 'pessoa';
  end if;
  v_dias_a := array(select distinct split_part(x, '|', 1)::date from unnest(v_a) x order by 1);
  v_dias_d := array(select distinct split_part(x, '|', 1)::date from unnest(v_d) x order by 1);
  if v_dias_a = v_dias_d then
    return 'turno';
  end if;
  v_fim_a := case when p_fim_antes is null then v_dias_a[cardinality(v_dias_a)] else p_fim_antes end;
  v_fim_d := case when p_fim_depois is null then v_dias_d[cardinality(v_dias_d)] else p_fim_depois end;
  v_lim := case when p_prometido_ate is null then v_fim_a + (7 - extract(isodow from v_fim_a)::int) else p_prometido_ate end;
  if v_fim_d <= v_lim then
    return 'dia';
  end if;
  return 'data';
end;
$function$;

comment on function public._agenda_degrau(jsonb, jsonb, date, date, date) is
  'Agenda de Produção (Fase 7g, P1; §5.1, §3.1 item 4): o degrau entre p_antes e p_depois ([{payee_id, dia, turno, presenca}], só presenca turno; sem a chave = turno). Sem antes = nulo (nova); sem depois = tirou; iguais = nulo; mesmos meios-dias com outra pessoa = pessoa; mesmos dias com outro turno = turno; outros dias com o fim até o prometido (sem prometido, até o domingo da semana do fim de antes) = dia; depois disso = data. Fim nulo = o último dia de cada lado. IMMUTABLE.';

-- A zona mais severa (§5.1): travada > firme > livre. Lista nula, vazia ou só de nulos (ou de valores fora das 3) = nula (R9.12-2: nada a afirmar).
create or replace function public._agenda_zona_mais_severa(p_zonas text[])
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when 'travada' = any (p_zonas) then 'travada'
    when 'firme' = any (p_zonas) then 'firme'
    when 'livre' = any (p_zonas) then 'livre'
  end;
$function$;

comment on function public._agenda_zona_mais_severa(text[]) is
  'Agenda de Produção (Fase 7g, P1; §5.1): travada > firme > livre. Nula, vazia, só nulos ou nenhum dos 3 = nula. IMMUTABLE.';

-- A fonte da duração em palavras (§6.1). AG7-33 (R9.3-1): com a correção do viés aplicada, a frase é a de agenda_meios_da_os(…) ->> 'texto_vies' (os dois
-- números), que quem chama passa em p_texto_vies: esta função não refaz a conta nem escreve outra. Sem os dias, nada a dizer (nula). "uns" só com 2 dias ou mais
-- ("uns 1 dia" não é português): abaixo disso, o número sozinho.
create or replace function public._agenda_duracao_fonte_texto(p_fonte text, p_dias numeric, p_mo numeric, p_texto_vies text default null)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_d text;
begin
  if btrim(p_texto_vies) <> '' then
    return p_texto_vies;
  end if;
  if p_dias is null or p_dias <= 0 then
    return null;
  end if;
  v_d := public._agenda_dias(p_dias);
  return case p_fonte
    when 'dono' then 'você disse ' || v_d
    when 'aceita' then v_d || ' (a minha estimativa, que você aceitou)'
    when 'orcamento' then
      case when p_mo is not null and p_mo > 0
           then format('%s pelo orçamento (R$ %s de mão de obra; estimativa minha)', v_d, translate(to_char(round(p_mo), 'FM999,999,990'), ',', '.'))
           else v_d || ' pelo orçamento (estimativa minha)' end
    when 'sugerida' then
      case when p_dias >= 2 then 'uns ' || v_d else v_d end || ' (estimativa minha, só para reservar)'
  end;
end;
$function$;

comment on function public._agenda_duracao_fonte_texto(text, numeric, numeric, text) is
  'Agenda de Produção (Fase 7g, P1; §6.1, R9.3-1, AG7-33): de onde veio a duração, em palavras — dono "você disse 2 dias"; aceita "2 dias (a minha estimativa, que você aceitou)"; orcamento "3 dias pelo orçamento (estimativa minha)", com mo "3 dias pelo orçamento (R$ 2.300 de mão de obra; estimativa minha)"; sugerida "uns 3 dias (estimativa minha, só para reservar)" ("uns" só com 2 dias ou mais). Com p_texto_vies não vazio, a frase é ele (os dois números da 7e P3). Sem dias, ou fonte fora das 4, nula. IMMUTABLE.';

-- Uma suposição em palavras (§6.1, com o R9.3-7: o local pelo nome, com a preposição). O detalhe é o que valeu na hora da decisão (o P2 grava): o texto só
-- formata. Sem o número que a frase precisa, nula (não se afirma o que não foi contado). duracao_orcamento vai pela fonte da duração: nula aqui.
-- local_suposto: detalhe.local é o lugar já com a preposição (o texto_curto de _agenda_local_resolvido: "na MP Motorhomes", "em Balneário Camboriú").
create or replace function public._agenda_suposicao_texto(p_codigo text, p_detalhe jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  d       jsonb := case when jsonb_typeof(p_detalhe) = 'object' then p_detalhe else '{}'::jsonb end;
  v_itens text[];
  v_n     int;
  v_du    int;
  v_nomes text[];
  v_txt   text;
begin
  case p_codigo
    when 'prazo_padrao_peca' then
      v_du := (d ->> 'du')::int;
      if v_du is null then return null; end if;
      v_itens := array(select x from jsonb_array_elements_text(case when jsonb_typeof(d -> 'itens') = 'array' then d -> 'itens' else '[]'::jsonb end) x);
      v_n := cardinality(v_itens);
      v_txt := format('contei %s de entrega', public._agenda_plural(v_du, 'dia útil', 'dias úteis'));
      return case
        when v_n = 0 then v_txt || ' (não sei de quem comprar)'
        when v_n = 1 then v_itens[1] || ': ' || v_txt || ' (não sei de quem comprar)'
        else format('%s e mais %s: %s (sem fornecedor)', v_itens[1], public._agenda_plural(v_n - 1, 'peça', 'peças'), v_txt)
      end;
    when 'quanto_falta_padrao' then
      if (d ->> 'dias') is null then return null; end if;
      return format('contei que falta %s (você não disse quanto falta)', public._agenda_dias((d ->> 'dias')::numeric));
    when 'local_suposto' then
      if nullif(btrim(d ->> 'local'), '') is null then return null; end if;
      return btrim(d ->> 'local') || case d ->> 'fonte'
        when 'cidade' then ' (supus pela cidade do cliente)'
        when 'patio' then ' (supus pelo tipo do bem)'
        else format(' (supus pelo cadastro do %s)', coalesce(nullif(btrim(d ->> 'bem'), ''), 'bem')) end;
    when 'bem_disponivel' then
      return format('o %s livre nesses dias (ninguém disse que está em uso)', coalesce(nullif(btrim(d ->> 'bem'), ''), 'barco'));
    when 'disponibilidade_suposta' then
      v_nomes := array(select btrim(x) from jsonb_array_elements_text(case when jsonb_typeof(d -> 'pessoas') = 'array' then d -> 'pessoas' else '[]'::jsonb end) x
                        where btrim(x) <> '');
      v_n := cardinality(v_nomes);
      if v_n = 0 then return null; end if;
      return case when v_n = 1 then v_nomes[1]
                  else array_to_string(v_nomes[1:v_n - 1], ', ') || ' e ' || v_nomes[v_n] end
             || ': contei os dias da última resposta';
    when 'compra_interna_padrao' then
      v_du := (d ->> 'du')::int;
      if v_du is null then return null; end if;
      return format('você compra em até %s depois de aprovado', public._agenda_plural(v_du, 'dia útil', 'dias úteis'));
    when 'sinal_a_cobrar' then
      return 'o sinal ainda não foi pago: marquei e lembro você de cobrar';
    when 'uma_pessoa' then
      return '1 pessoa (dupla só quando o serviço pede)';
    when 'peca_nao_segura' then
      v_n := (d ->> 'n')::int;
      if v_n is null or v_n <= 0 or (d ->> 'limiar') is null then return null; end if;
      return format('%s para separar na véspera (abaixo de R$ %s)',
                    case when v_n = 1 then '1 item pequeno fica' else v_n || ' itens pequenos ficam' end,
                    translate(to_char(round((d ->> 'limiar')::numeric), 'FM999,999,990'), ',', '.'));
    when 'sem_peca' then
      return 'sem peça a comprar (o orçamento não tem material)';
    when 'dono_abre_fecha' then
      return 'você abre e fecha';
    else
      return null;
  end case;
end;
$function$;

comment on function public._agenda_suposicao_texto(text, jsonb) is
  'Agenda de Produção (Fase 7g, P1; §6.1, R9.3-7): a suposição em palavras, com os números do detalhe gravado na hora (o P2 grava): prazo_padrao_peca {itens, du}, quanto_falta_padrao {dias}, local_suposto {local (com a preposição), fonte, bem}, bem_disponivel {bem}, disponibilidade_suposta {pessoas}, compra_interna_padrao {du}, peca_nao_segura {n, limiar}; sinal_a_cobrar, uma_pessoa, sem_peca e dono_abre_fecha sem detalhe. duracao_orcamento vai pela fonte (nula aqui). Sem o número que a frase precisa, ou código fora da lista, nula. IMMUTABLE.';

-- O critério da pessoa em palavras (§6.1, R9.5-5): os 10 do CHECK do 7c (agenda_alocacoes_criterio_check). "quem você disse" é o dono_disse (a spec dizia dito,
-- que não existe). empate e presenca_do_dono não dizem nada: nula.
create or replace function public._agenda_criterio_texto(p_criterio text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_criterio
    when 'dono_disse'   then 'quem você disse'
    when 'lider'        then 'o responsável do serviço'
    when 'habilidade'   then 'quem sabe fazer'
    when 'continuidade' then 'quem já estava no serviço'
    when 'local'        then 'quem já estava no lugar'
    when 'carga'        then 'quem tinha a semana mais livre'
    when 'custo'        then 'o mais em conta para o serviço'
    when 'unico'        then 'só ele estava livre'
  end;
$function$;

comment on function public._agenda_criterio_texto(text) is
  'Agenda de Produção (Fase 7g, P1; §6.1, R9.5-5): o critério da escolha da pessoa (o do 7c) em palavras — dono_disse, lider, habilidade, continuidade, local, carga, custo e unico; empate, presenca_do_dono, nulo e outro código = nula. IMMUTABLE.';

-- O degrau em palavras (§6.1).
create or replace function public._agenda_degrau_texto(p_degrau text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_degrau
    when 'pessoa' then 'troquei só a pessoa'
    when 'turno'  then 'troquei só o turno'
    when 'dia'    then 'mudei o dia, dentro da semana combinada'
    when 'data'   then 'a data de fim andou'
    when 'tirou'  then 'tirei da agenda'
  end;
$function$;

comment on function public._agenda_degrau_texto(text) is
  'Agenda de Produção (Fase 7g, P1; §6.1): o degrau em palavras — pessoa, turno, dia, data e tirou; nulo ou outro = nula. IMMUTABLE.';

-- As portas (§5.1 e §3.1 item 13: as internas _agenda_* sem porta para authenticated): nenhuma para public, anon nem authenticated; o service_role tem execute.
-- O revoke de authenticated é explícito: o privilégio padrão do esquema dá execute a quem não for tirado. Hoje nenhuma função chama as 8 (B8b). Quem as chama
-- de dentro de uma definer passa pela porta do dono; o CHECK das suposições roda como quem escreve, e authenticated não grava agenda_alocacoes nem agenda_acoes
-- (só select, Fase 2). Pacote que fizer uma função sem definer, com porta para authenticated, chamar uma delas dá a porta a authenticated na mesma migration
-- e muda o B3e (o B3e3 aponta essa função). Os 3 gatilhos, sem porta para ninguém.
revoke all on function public._agenda_marcacoes_so_muda(), public._agenda_tipos_os_so_muda(), public._agenda_placar_so_muda()
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_suposicoes_validas(jsonb), public._agenda_quem_marcou(text, text), public._agenda_degrau(jsonb, jsonb, date, date, date),
                       public._agenda_zona_mais_severa(text[]), public._agenda_duracao_fonte_texto(text, numeric, numeric, text),
                       public._agenda_suposicao_texto(text, jsonb), public._agenda_criterio_texto(text), public._agenda_degrau_texto(text)
  from public, anon, authenticated;
grant execute on function public._agenda_suposicoes_validas(jsonb), public._agenda_quem_marcou(text, text), public._agenda_degrau(jsonb, jsonb, date, date, date),
                          public._agenda_zona_mais_severa(text[]), public._agenda_duracao_fonte_texto(text, numeric, numeric, text),
                          public._agenda_suposicao_texto(text, jsonb), public._agenda_criterio_texto(text), public._agenda_degrau_texto(text)
  to service_role;
