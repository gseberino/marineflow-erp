-- Agenda de Produção, Fase 7, etapa 7f ("Falar só o que importa"), pacote P1: a base — os 6 interruptores e os 15 parâmetros da etapa, as
-- colunas do padrão e do prazo nas perguntas, as colunas do que a mensagem à equipe diz, as listas fechadas ampliadas, o modelo M12, o
-- padrão de cada pergunta (o gatilho de INSERT e o backfill das abertas), a zona do dia, a classe de cada saída e o modo com o freio.
-- Spec: scratchpad agenda-pesquisa/spec-fase7f.md (§4, §5.1, §8.3 agenda_fase7f_base.sql e o bloco R8, que vale sobre o corpo: R8.5-1 a 6,
-- R8.6, R8.8, R8.12, R8.13); nomes: fase7-registro.md §1 (7f P1); respostas do dono: fase7-padroes.md (AG7-15 o prazo; AG7-16 a semana ao
-- cliente; AG7-22 a mensagem da quinta; AG7-23 o convite; AG7-24 o teto de 5; AG7-02 os dias do dono primeiro).
-- Depende das Fases 1 a 6, do lote de 30/10 e das etapas 7a, 7b, 7c e 7d (20261031100000 .. 20261107100870; a recriada vem de
-- 20261031100000). NÃO depende da 7e, que nesta ordem vem depois (fio principal, 06/11).
--
-- ═══ DDL — OK NOMEADO ═══ (21 colunas novas em agenda_config — 6 interruptores e 15 parâmetros — e o DEFAULT dos 6 interruptores; 7 colunas
-- novas em agenda_perguntas; 2 colunas novas em agenda_equipe_mensagens; 5 listas fechadas pelo ampliador e 1 à mão; 1 coluna gerada por SET
-- EXPRESSION; 1 índice único recriado; 20 CHECKs novos por nome em agenda_config e 3 em agenda_perguntas; 1 CHECK a menos em
-- agenda_perguntas (veto_nao_critica); 5 funções novas, 1 de gatilho; 1 gatilho novo; 1 função recriada; 1 UPDATE de dado: o padrão das
-- perguntas abertas)
-- NÃO APLICADA. Existe para revisão e espera o OK. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7f/p1/montar-migration.mjs: a
-- recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o montador para se outra migration a definir depois da origem),
-- _agenda_perguntas_antes de 20261031100000_agenda_fase7a_base.sql, e a mudança está só nos blocos "-- FASE 7f: … -- FASE 7f: fim". Tirados
-- os blocos, o corpo é o da origem, byte a byte (o montador e o B4 de supabase/tests/agenda_fase7f_base.sql conferem).
--
-- POR QUE: em 06/11 havia 22 perguntas ligadas na história, 0 respondidas e 13 nunca mostradas, e o fechamento mostrou 1 de 8 linhas da
-- agenda. Para a agenda caber e o silêncio do dono ter efeito previsível, cada pergunta precisa nascer sabendo o que acontece sem resposta,
-- e se aquilo pode vencer sozinho. Esta migration só cria o lugar e as regras; quem muda alguma coisa são as próximas (20261109100100 em
-- diante), sempre atrás dos interruptores. Com os 6 desligados (a linha nasce assim), nada muda para ninguém.
--
-- O QUE MUDA:
--   1. agenda_config: os interruptores modo_bloco_agenda, modo_veto, modo_lote_dono, modo_equipe_previsto, modo_equipe_convite e
--      modo_cliente_camadas — desligado | sombra | ligado; a linha fica 'desligado', o DEFAULT da coluna vira 'sombra' (como de 7a a 7d);
--      quem os põe em sombra é a migration de dado 20261109100900, com OK nomeado. Os parâmetros do bloco (bloco_*), do prazo (veto_tipos,
--      perguntas_abertas_max, perguntas_primeiro), da quinta (dono_semana_*), do convite, das camadas ao cliente e o tempo da rodada
--      (comunicar_tempo_max, R8.5-7). CHECK por nome em cada um.
--      veto_tipos é trava no banco: o CHECK recusa os tipos que nunca vencem (R8.5-3). perguntas_primeiro não tem CHECK de lista: CHECK não
--      lê catálogo, e o teste B1 cobra.
--   2. agenda_perguntas: padrao_chave, padrao_efeito (a suposição, lista fechada; o texto de cada chave mora em _agenda_pergunta_linha, P2),
--      veto_espera (por que não vence), veto_teria_em (em sombra, quando teria vencido), destrava, assumida_por, assumida_em.
--      Os CHECKs pergunta_padrao_coerente, pergunta_assumida_coerente e pergunta_assumida_fechada.
--      SAI o CHECK veto_nao_critica do 7a: a crítica pode vencer quando o tipo está em veto_tipos e veto_espera é nulo (AG7-15). Fica
--      veto_padrao_tem_prazo. NÃO entra o CHECK pergunta_veto_so_com_padrao da §4.2 (R8.5-1): a equipe_cadastro aberta em produção tem
--      veto_ate e veto_espera = 'tipo', e toda escrita de veto_ate da 7a, da 7b e da 7c lançaria dentro da vigia ou do gestor. Quem
--      filtra é a rodada do prazo (P2, _agenda_gestor_vetos).
--   3. agenda_equipe_mensagens: dias (os dias que a mensagem diz) e alocacao_ids (as alocações do convite). Nada escreve aqui ainda.
--      agenda_equipe_uma_por_dia deixa de cobrir mudanca (pode haver a urgente e a das 19:30; a mudança se protege pela dedupe_key).
--   4. As listas fechadas, pelo ampliador da 7a: agenda_acoes.tipo + assumir; agenda_perguntas.respondida_via + prazo;
--      agenda_vigia_rodadas.rotina + comunicar; agenda_equipe_mensagens.tipo + previsto, mudanca, convite; agenda_cliente_mensagens.tipo +
--      semana. agenda_config_cliente_tipos_ligados_check + semana, À MÃO: o CHECK é "<@", e o ampliador só aceita "= ANY" (R8.5-4). O valor
--      da linha continua como está: o tipo novo fica FORA da lista, ou seja, em teste.
--   5. agenda_cliente_mensagens.modelo, por SET EXPRESSION (Postgres 17+): a expressão de 20261107100000 + 'semana' = M12.
--   6. _agenda_fala_modo (nova, molde de _agenda_local_modo): o modo EFETIVO das 6 peças. veto, previsto, convite e camadas respeitam
--      *gestor, só propor* (ligado + freio = sombra); bloco e lote, não: são forma de contar (R8.6). Todo leitor desses modos usa ela;
--      a saúde e o gravador usam o modo cru.
--   7. _agenda_padrao_da_pergunta (nova): {chave, efeito, espera} de cada tipo; _agenda_perguntas_padrao + o gatilho agenda_perguntas_padrao
--      (BEFORE INSERT): toda pergunta nasce com o padrão pronto e destrava 0. Quem calcula destrava é o passo diário do P2, nunca a vigia
--      (R8.5-6). 1 leitura de os_planejamento só nos tipos que dependem do prometido.
--   8. _agenda_perguntas_antes (de 20261031100000): destrava, veto_teria_em e assumida_* mudam na aberta; veto_espera vai de nulo a dono ou
--      a sem_padrao; veto_ate vai de um valor a outro só na pergunta que nunca foi mostrada antes do prazo, na mesma escrita que a mostra
--      (R2); na fechada, só assumida_*, de nulo a valor (o prazo do P2 decide e depois carimba); padrao_* e veto_espera, além disso, só
--      com agenda.backfill_padrao = 'on', que só esta migration liga.
--   9. O backfill: as perguntas abertas ganham o padrão pela mesma função do gatilho, ANTES dos CHECKs. Fechada fica nula.
--  10. _agenda_zona (nova): travada | firme | livre, sobre _agenda_dia_avisado, sem repetir a regra do 7a. _agenda_classe_da_saida (nova):
--      decisao | mudanca | informacao, o que a saída mexe e se é exceção. Nada as chama ainda.
--
-- O QUE NÃO MUDA: com os 6 interruptores desligados, ou em sombra, o motor, a vigia, os textos ao dono, à equipe e ao cliente e as Fases 1 a
-- 7d, byte a byte (nada de antes lê as colunas nem chama as funções novas, fora o gatilho, que só preenche as colunas dele). Os valores de
-- antes continuam nas listas; o modelo dos 12 tipos de antes é o mesmo; _agenda_modo_da_pergunta não é recriada (R8.6: ela segue crua).
--
-- ORDEM DE LIGAR (spec R8.14): depois da 7d inteira; antes de 20261109100100 (P2), que lê as colunas novas. À noite, depois das 21:00, logo
-- depois de um tique, com LOCK_TIMEOUT=5s: há ALTER TABLE em agenda_config, agenda_perguntas e agenda_equipe_mensagens, e o SET EXPRESSION
-- reescreve agenda_cliente_mensagens. Aplicar sozinha não muda nada para ninguém (os interruptores ficam 'desligado' na linha).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7f_base.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261109100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261109100000_agenda_fase7f_base.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261109100000', 'agenda_fase7f_base');"
--
-- DESFAZER (só a estrutura; nada usa as colunas antes das próximas migrations): recriar _agenda_perguntas_antes com o corpo de 20261031100000
-- e tirar o gatilho; o resto pode ficar (colunas nulas ou com DEFAULT, listas só somadas). Se alguma crítica já tiver prazo, o CHECK
-- veto_nao_critica não volta. Para tirar mesmo (só sem valor novo nas listas):
--   drop trigger if exists agenda_perguntas_padrao on public.agenda_perguntas;
--   drop function if exists public._agenda_perguntas_padrao(), public._agenda_padrao_da_pergunta(text, boolean, uuid, jsonb, smallint, uuid[]),
--     public._agenda_classe_da_saida(text, uuid, date, timestamptz), public._agenda_zona(uuid, uuid, date, date), public._agenda_fala_modo(text);
--   alter table public.agenda_perguntas drop column if exists padrao_chave, drop column if exists padrao_efeito,
--     drop column if exists veto_espera, drop column if exists veto_teria_em, drop column if exists destrava,
--     drop column if exists assumida_por, drop column if exists assumida_em;
--   alter table public.agenda_perguntas add constraint veto_nao_critica check (veto_ate is null or not critica);
--   alter table public.agenda_equipe_mensagens drop column if exists dias, drop column if exists alocacao_ids;
--   (agenda_equipe_uma_por_dia: recriar com where tipo <> 'resposta'; agenda_config: drop dos 20 CHECKs e das 21 colunas; modelo: SET EXPRESSION
--    com a expressão de 20261107100000; as listas: recriar o CHECK de cada uma com os valores da 7d)
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (só cria o que falta), as listas pelo ampliador (soma só o que falta), a lista
-- à mão e o SET EXPRESSION só quando ainda não têm o valor novo, create or replace function, drop trigger if exists + create, o índice
-- recriado só se ainda cobre mudanca, o backfill só nas abertas sem padrão, revoke/grant e comment.

-- ── 1. agenda_config: os interruptores e os parâmetros ──────────────────────────────────────────────
alter table public.agenda_config
  -- a linha fica 'desligado' até a migration de dado 20261109100900 (o molde de 7a a 7d); o DEFAULT passa a 'sombra' abaixo
  add column if not exists modo_bloco_agenda             text     not null default 'desligado',
  add column if not exists modo_veto                     text     not null default 'desligado',  -- AG7-15
  add column if not exists modo_lote_dono                text     not null default 'desligado',  -- AG7-22
  add column if not exists modo_equipe_previsto          text     not null default 'desligado',
  add column if not exists modo_equipe_convite           text     not null default 'desligado',  -- AG7-23
  add column if not exists modo_cliente_camadas          text     not null default 'desligado',  -- AG7-16
  -- o bloco do fechamento
  add column if not exists bloco_max_chars               smallint not null default 520,
  add column if not exists bloco_decisoes_max            smallint not null default 3,
  add column if not exists bloco_mudancas_max            smallint not null default 3,
  add column if not exists bloco_compras_max             smallint not null default 3,
  add column if not exists bloco_compras_du              smallint not null default 2,
  -- as perguntas: o prazo é o veto_du e o veto_hora do 7a (AG7-15); aqui, quais tipos vencem, o teto e a ordem
  add column if not exists veto_tipos                    text[]   not null default
    '{duracao,material_conferir,padrao_do_dono,chegou,parada,estouro,previsao_fornecedor,fornecedor_cadastro,fornecedores_prazo,equipe_resposta,nao_cabe,atraso_longo,segundo_atraso,fixada_pelo_dono}',  -- AG7-15
  add column if not exists perguntas_abertas_max         smallint not null default 5,            -- AG7-24
  add column if not exists perguntas_primeiro            text[]   not null default '{padrao_do_dono,dias_semana}',  -- AG7-02
  -- o lote do dono
  add column if not exists dono_semana_aviso             text     not null default 'propria',    -- AG7-22
  add column if not exists dono_semana_hora              time     not null default '16:50',      -- AG7-22: sai no 1º tique depois, o das 17:00
  -- a equipe
  add column if not exists equipe_convite_antecedencia_h smallint not null default 72,           -- AG7-23
  -- o cliente
  add column if not exists cliente_dia_exato_du          smallint not null default 1,            -- AG7-16
  add column if not exists cliente_semana_du             smallint not null default 10,           -- AG7-16
  add column if not exists cliente_camadas_para          text     not null default 'estimativa', -- AG7-16
  -- a rodada (R8.5-7): o molde de agenda_gestor_rodar, com o relógio entre os passos
  add column if not exists comunicar_tempo_max           interval not null default '15 seconds';

-- veto_tipos: a lista do que NUNCA vence (R8.5-3): dinheiro, cliente, aprendizado, dia confirmado, o que já tem relógio ou dono próprio. Um
-- CHECK não lê catálogo: a lista mora aqui, e o tipo novo que nunca vence soma aqui (o B1 cobra que todo nome dela existe em agenda_perguntas).
do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_bloco_agenda_check',    'check (modo_bloco_agenda in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_veto_check',            'check (modo_veto in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_lote_dono_check',       'check (modo_lote_dono in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_equipe_previsto_check', 'check (modo_equipe_previsto in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_equipe_convite_check',  'check (modo_equipe_convite in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_cliente_camadas_check', 'check (modo_cliente_camadas in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_bloco_max_chars_check',      'check (bloco_max_chars between 300 and 800)'),
      ('agenda_config_bloco_decisoes_max_check',   'check (bloco_decisoes_max between 1 and 5)'),
      ('agenda_config_bloco_mudancas_max_check',   'check (bloco_mudancas_max between 1 and 6)'),
      ('agenda_config_bloco_compras_max_check',    'check (bloco_compras_max between 1 and 6)'),
      ('agenda_config_bloco_compras_du_check',     'check (bloco_compras_du between 1 and 5)'),
      ('agenda_config_veto_tipos_check',
       'check (not (veto_tipos && array[''diaria'', ''diaria_ligar'', ''nfe_vincular'', ''pix_material'', ''concluir'', ''entrega'', '
       || '''cliente_aprovar'', ''cliente_aviso'', ''cliente_resposta'', ''aprendizado'', ''conferencia'', ''remarcar_confirmado'', '
       || '''compre_ate'', ''sinal'', ''tarefa'', ''local'', ''combinar'', ''acesso'', ''dia_prometido'', ''dia_avisado'']::text[]))'),
      ('agenda_config_perguntas_abertas_max_check', 'check (perguntas_abertas_max between 3 and 10)'),
      ('agenda_config_dono_semana_aviso_check',     'check (dono_semana_aviso in (''propria'', ''fechamento''))'),
      ('agenda_config_dono_semana_hora_check',      'check (dono_semana_hora between hora_do_plano and cliente_janela_fim)'),
      ('agenda_config_equipe_convite_antecedencia_h_check', 'check (equipe_convite_antecedencia_h between 24 and 120)'),
      ('agenda_config_cliente_dia_exato_du_check',
       'check (cliente_dia_exato_du between 1 and 3 and cliente_dia_exato_du <= cliente_confirmar_du)'),
      ('agenda_config_cliente_semana_du_check',     'check (cliente_semana_du between 5 and 20)'),
      ('agenda_config_cliente_camadas_para_check',  'check (cliente_camadas_para in (''estimativa'', ''todas''))'),
      ('agenda_config_comunicar_tempo_max_check',
       'check (comunicar_tempo_max between interval ''5 seconds'' and interval ''60 seconds'')')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como de 7a a 7d: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem a põe em sombra é a
-- migration de dado 20261109100900, com OK nomeado.
alter table public.agenda_config
  alter column modo_bloco_agenda    set default 'sombra',
  alter column modo_veto            set default 'sombra',
  alter column modo_lote_dono       set default 'sombra',
  alter column modo_equipe_previsto set default 'sombra',
  alter column modo_equipe_convite  set default 'sombra',
  alter column modo_cliente_camadas set default 'sombra';

comment on column public.agenda_config.modo_bloco_agenda is
  'Agenda de Produção (Fase 7f): o bloco Agenda do fechamento, nos 3 turnos. desligado = as linhas de sempre; sombra = o bloco vai só ao detalhe de resumo_tarde, e o texto é o de sempre, byte a byte; ligado = o bloco toma o lugar das linhas. Não respeita o freio (R8.6): é forma de contar. Leia por _agenda_fala_modo(''bloco'').';
comment on column public.agenda_config.modo_veto is
  'Agenda de Produção (Fase 7f, AG7-15): a pergunta com padrão vence no prazo, depois de mostrada com o prazo escrito, e no teto. sombra = só grava veto_teria_em. Respeita o freio: ligado + gestor_so_propor = sombra. Leia por _agenda_fala_modo(''veto'').';
comment on column public.agenda_config.modo_lote_dono is
  'Agenda de Produção (Fase 7f, AG7-22): fora do fechamento, só a exceção sai na hora; o resto vai no bloco e na mensagem da quinta. Não respeita o freio (R8.6): é forma de contar. Leia por _agenda_fala_modo(''lote'').';
comment on column public.agenda_config.modo_equipe_previsto is
  'Agenda de Produção (Fase 7f): o previsto da semana e a mensagem de mudança à equipe. Respeita o freio. Leia por _agenda_fala_modo(''previsto'').';
comment on column public.agenda_config.modo_equipe_convite is
  'Agenda de Produção (Fase 7f, AG7-23): o dia acrescentado com menos de equipe_convite_antecedencia_h horas pede o SIM da pessoa. Respeita o freio. Leia por _agenda_fala_modo(''convite'').';
comment on column public.agenda_config.modo_cliente_camadas is
  'Agenda de Produção (Fase 7f, AG7-16): OS marcada por estimativa recebe a semana prevista (M12) e o dia exato só na véspera, com a compra feita. Respeita o freio. Leia por _agenda_fala_modo(''camadas'').';
comment on column public.agenda_config.bloco_max_chars is
  'Agenda de Produção (Fase 7f): o tamanho máximo do bloco Agenda do fechamento (520). 300..800.';
comment on column public.agenda_config.bloco_decisoes_max is
  'Agenda de Produção (Fase 7f): até quantas decisões o bloco mostra (3). 1..5.';
comment on column public.agenda_config.bloco_mudancas_max is
  'Agenda de Produção (Fase 7f): até quantas mudanças o bloco mostra (3). 1..6.';
comment on column public.agenda_config.bloco_compras_max is
  'Agenda de Produção (Fase 7f): até quantos grupos de compra o bloco mostra (3). 1..6.';
comment on column public.agenda_config.bloco_compras_du is
  'Agenda de Produção (Fase 7f): o bloco mostra as compras que vencem em até N dias úteis (2). 1..5.';
comment on column public.agenda_config.veto_tipos is
  'Agenda de Produção (Fase 7f, AG7-15): os tipos de pergunta que podem vencer pelo prazo. Tipo fora daqui nasce com veto_espera = tipo. O CHECK recusa o que nunca vence: dinheiro, cliente, aprendizado, dia confirmado e o que tem relógio ou dono próprio.';
comment on column public.agenda_config.perguntas_abertas_max is
  'Agenda de Produção (Fase 7f, AG7-24): o teto de perguntas abertas ligadas (5), sem contar conferencia; acima, a mais velha que pode vencer fica com o padrão. 3..10.';
comment on column public.agenda_config.perguntas_primeiro is
  'Agenda de Produção (Fase 7f, AG7-02): os tipos que vêm antes na ordem das perguntas: os dias do dono em campo (padrao_do_dono, dias_semana). Lista de agenda_perguntas.tipo: o teste B1 cobra.';
comment on column public.agenda_config.dono_semana_aviso is
  'Agenda de Produção (Fase 7f, AG7-22): a semana vai em mensagem própria na quinta (propria) ou no fechamento (fechamento).';
comment on column public.agenda_config.dono_semana_hora is
  'Agenda de Produção (Fase 7f, AG7-22): a partir de que hora da quinta sai a mensagem da semana (16:50: sai no 1º tique depois, o das 17:00). Entre hora_do_plano e cliente_janela_fim.';
comment on column public.agenda_config.equipe_convite_antecedencia_h is
  'Agenda de Produção (Fase 7f, AG7-23): dia acrescentado a menos de N horas pede o SIM da pessoa (72). 24..120.';
comment on column public.agenda_config.cliente_dia_exato_du is
  'Agenda de Produção (Fase 7f, AG7-16): o dia exato vai ao cliente a N dias úteis do 1º dia (1 = a véspera). 1..3 e não maior que cliente_confirmar_du.';
comment on column public.agenda_config.cliente_semana_du is
  'Agenda de Produção (Fase 7f, AG7-16): a semana prevista vai ao cliente a até N dias úteis do 1º dia (10); é também o limite da zona firme em _agenda_zona. 5..20.';
comment on column public.agenda_config.cliente_camadas_para is
  'Agenda de Produção (Fase 7f, AG7-16): quem recebe em camadas: só a OS marcada por estimativa (estimativa) ou toda OS (todas).';
comment on column public.agenda_config.comunicar_tempo_max is
  'Agenda de Produção (Fase 7f): o tempo da rodada agenda_comunicar_rodar (15 s): passou entre 2 passos, ela para e grava parou_no. É teto, não meta. 5..60 segundos.';

-- ── 2. agenda_perguntas: o padrão e o prazo ─────────────────────────────────────────────────────────
alter table public.agenda_perguntas
  add column if not exists padrao_chave  text check (padrao_chave in ('estimativa', 'sem_peca', 'abre_e_fecha', 'prazo_padrao',
                                                                      'como_esta', 'nao_chegou', 'recomendacao')),
  add column if not exists padrao_efeito text check (padrao_efeito in ('nada', 'opcao')),
  add column if not exists veto_espera   text check (veto_espera in ('cliente', 'dinheiro', 'tipo', 'sem_padrao', 'dono')),
  add column if not exists veto_teria_em timestamptz,
  add column if not exists destrava      smallint not null default 0 check (destrava between 0 and 9999),
  add column if not exists assumida_por  text check (assumida_por in ('prazo', 'teto')),
  add column if not exists assumida_em   timestamptz;

-- Sai a regra do 7a de que a crítica nunca tem prazo (AG7-15): ela pode vencer quando o tipo está em veto_tipos e veto_espera é nulo. O CHECK
-- veto_padrao_tem_prazo fica.
alter table public.agenda_perguntas drop constraint if exists veto_nao_critica;

comment on column public.agenda_perguntas.padrao_chave is
  'Agenda de Produção (Fase 7f, AG7-15): o que o gestor assume sem resposta, lista fechada; o texto de cada chave mora em _agenda_pergunta_linha. Nasce pelo gatilho agenda_perguntas_padrao e não muda.';
comment on column public.agenda_perguntas.padrao_efeito is
  'Agenda de Produção (Fase 7f, AG7-15): nada (o padrão já está em vigor, o prazo só fecha a pergunta) ou opcao (aplica coalesce(opcao_padrao, recomendacao) por agenda_decidir). Nasce com padrao_chave.';
comment on column public.agenda_perguntas.veto_espera is
  'Agenda de Produção (Fase 7f, AG7-15): por que a pergunta não vence pelo prazo desta etapa: cliente (mexe no que o cliente ouviu), dinheiro, tipo (fora de veto_tipos, ou com relógio próprio), sem_padrao, dono (*agenda espera <nome>*). Nula = pode vencer. É a foto do nascimento: quem vence confere o prometido de novo. Muda só de nula para dono ou sem_padrao.';
comment on column public.agenda_perguntas.veto_teria_em is
  'Agenda de Produção (Fase 7f, AG7-15): em sombra, quando a pergunta teria vencido. Nada mais muda.';
comment on column public.agenda_perguntas.destrava is
  'Agenda de Produção (Fase 7f): os meios-dias de OS que a resposta põe na agenda. Nasce 0; quem calcula é o passo diário da rodada comunicar, nunca a vigia (R8.5-6).';
comment on column public.agenda_perguntas.assumida_por is
  'Agenda de Produção (Fase 7f, AG7-15, AG7-24): prazo ou teto: por qual caminho a pergunta ficou com o padrão sem resposta.';
comment on column public.agenda_perguntas.assumida_em is
  'Agenda de Produção (Fase 7f, AG7-15): quando a pergunta ficou com o padrão sem resposta.';
comment on column public.agenda_perguntas.veto_ate is
  'Agenda de Produção (Fase 7a, AG7-15): o prazo da pergunta — sem resposta até aqui, e só se ela foi mostrada ao dono antes (mostrada_vezes > 0 e mostrada_em < veto_ate), vale opcao_padrao (_agenda_gestor_vetos). Vai de nulo a um valor uma vez, na pergunta aberta (quem mostra com o prazo escrito grava: 7b e 7c); de um valor a outro, só o 7f. Fase 7f (AG7-15, R2): de um valor a outro só na pergunta nunca mostrada antes do prazo, na mesma escrita que a mostra; quem mostra com o prazo escrito é o bloco e a mensagem da quinta. Pergunta crítica pode ter prazo: quem filtra é a rodada (veto_tipos, veto_espera), não o CHECK.';

-- ── 3. agenda_equipe_mensagens: o que a mensagem diz ────────────────────────────────────────────────
alter table public.agenda_equipe_mensagens
  add column if not exists dias         date[],
  add column if not exists alocacao_ids uuid[];

comment on column public.agenda_equipe_mensagens.dias is
  'Agenda de Produção (Fase 7f): os dias que a mensagem DIZ (previsto, mudança, convite, a ficha da quinta com o previsto). Os dias declarados pela pessoa são de outra tabela (7b).';
comment on column public.agenda_equipe_mensagens.alocacao_ids is
  'Agenda de Produção (Fase 7f, AG7-23): convite: as alocações que o SIM confirma.';

-- mudanca pode ter mais de uma por dia (a urgente e a das 19:30): sai do índice e se protege pela dedupe_key. Só recria se ainda cobre mudanca.
do $$
begin
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and indexname = 'agenda_equipe_uma_por_dia' and indexdef like '%mudanca%') then
    drop index if exists public.agenda_equipe_uma_por_dia;
    create unique index agenda_equipe_uma_por_dia on public.agenda_equipe_mensagens(payee_id, dia, tipo, modo)
      where tipo not in ('resposta', 'mudanca');
  end if;
end
$$;

-- ── 4. As listas fechadas ───────────────────────────────────────────────────────────────────────────
select public._agenda_ampliar_lista('public.agenda_acoes', 'agenda_acoes_tipo_check', 'tipo', array['assumir']);
select public._agenda_ampliar_lista('public.agenda_perguntas', 'agenda_perguntas_respondida_via_check', 'respondida_via', array['prazo']);
select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina', array['comunicar']);
select public._agenda_ampliar_lista('public.agenda_equipe_mensagens', 'agenda_equipe_mensagens_tipo_check', 'tipo',
                                    array['previsto', 'mudanca', 'convite']);
select public._agenda_ampliar_lista('public.agenda_cliente_mensagens', 'agenda_cliente_mensagens_tipo_check', 'tipo', array['semana']);

comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor); Fase 5: cliente (as mensagens-modelo ao cliente); Fase 6: aprender (a medição e o aprendizado, uma vez por dia); Fase 7a: gestor (a rodada do gestor da agenda, o job agenda-gestor); Fase 7b: equipe_semana (a pergunta da semana, o passo 0b1 do task-automations); Fase 7c: habilidade (a rodada de quem faz o quê, o passo 0b2a). As rodadas de antes são da vigia. Fase 7c (P8): tarefas (a rodada das etapas do dia). Fase 7d: local (a rodada diária do local: combinar e conflitos). Fase 7f: comunicar (a rodada do que se fala ao dono, à equipe e ao cliente, o passo 0e do task-automations).';
comment on column public.agenda_equipe_mensagens.tipo is
  'Agenda de Produção (Fase 3): ficha (a da véspera), confirmar (a da manhã), como_foi (o "como foi hoje?"), resposta (o que a agenda respondeu). Fase 7b: dias — a pergunta da semana ("quais dias você pode na semana de dd/mm?"); o dia é a segunda da semana perguntada. Fase 7f: previsto (a semana prevista), mudanca (o que mudou nos dias já ditos; pode haver mais de uma por dia, pela dedupe_key), convite (o dia novo com pedido de SIM).';

-- À MÃO (R8.5-4): este CHECK é "cliente_tipos_ligados <@ array[...]", e o ampliador só aceita "coluna = ANY (array[...])": daria 22023 e a
-- migration cairia. Molde de 20261107100000. Só se ainda não tem o valor (rodar de novo não recria). O valor da linha continua como está:
-- semana fica fora da lista, em teste.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.agenda_config'::regclass and conname = 'agenda_config_cliente_tipos_ligados_check'
                    and pg_get_constraintdef(oid) like '%''semana''%') then
    alter table public.agenda_config drop constraint if exists agenda_config_cliente_tipos_ligados_check;
    alter table public.agenda_config add constraint agenda_config_cliente_tipos_ligados_check
      check (cliente_tipos_ligados <@ array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                            'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia', 'onde_fica', 'semana']::text[]);
  end if;
end
$$;

-- ── 5. A coluna gerada ──────────────────────────────────────────────────────────────────────────────
-- semana = M12 (o M11 é o onde_fica da 7d); sem isto cairia no else M10. Copia a expressão de 20261107100000. Nenhum índice nem view depende
-- de modelo. Só se a expressão ainda não tem 'semana'.
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_cliente_mensagens'::regclass and a.attname = 'modelo' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''semana''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_cliente_mensagens.modelo: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_cliente_mensagens alter column modelo set expression as
      (case tipo
         when 'confirmar' then 'M1' when 'vespera' then 'M2' when 'material_chegou' then 'M3'
         when 'acesso' then 'M4' when 'andamento' then 'M5' when 'pode_atrasar' then 'M6'
         when 'nova_data' then 'M7' when 'pronto' then 'M8' when 'pronto_lembrete' then 'M8'
         when 'pos_servico' then 'M9' when 'onde_fica' then 'M11' when 'semana' then 'M12' else 'M10' end);
  end if;
end
$$;

comment on column public.agenda_cliente_mensagens.modelo is
  'Agenda de Produção (Fase 5; Fase 7d; Fase 7f): o modelo da mensagem, gerado do tipo — M1 confirmar, M2 vespera, M3 material_chegou, M4 acesso, M5 andamento, M6 pode_atrasar, M7 nova_data, M8 pronto e pronto_lembrete, M9 pos_servico, M11 onde_fica, M12 semana; o resto (mudanca_no_dia), M10.';

-- ── 6. O modo com o freio ───────────────────────────────────────────────────────────────────────────
-- R8.6, molde de _agenda_local_modo: com *gestor, só propor*, o que está ligado em veto, previsto, convite e camadas vale sombra (o desligado
-- continua desligado). Decidir por silêncio, tirar alguém do dia ou dizer dia ao cliente com o gestor freado é o que o dono mandou parar. O
-- bloco e o lote não respeitam: são forma de contar, e o aviso segue saindo com o freio. Todo leitor desses modos usa esta função, nunca cf.modo_x; a
-- saúde e o gravador usam o modo cru.
create or replace function public._agenda_fala_modo(p_item text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_modo text;
begin
  if p_item is null or p_item <> all (array['bloco', 'lote', 'veto', 'previsto', 'convite', 'camadas']) then
    raise exception '_agenda_fala_modo: o item "%" não existe.', p_item using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  v_modo := case p_item
              when 'bloco'    then cf.modo_bloco_agenda
              when 'lote'     then cf.modo_lote_dono
              when 'veto'     then cf.modo_veto
              when 'previsto' then cf.modo_equipe_previsto
              when 'convite'  then cf.modo_equipe_convite
              when 'camadas'  then cf.modo_cliente_camadas
            end;
  if p_item not in ('bloco', 'lote') and cf.gestor_so_propor and v_modo = 'ligado' then
    return 'sombra';
  end if;
  return v_modo;
end;
$function$;

comment on function public._agenda_fala_modo(text) is
  'Agenda de Produção (Fase 7f, P1; R8.6): o modo EFETIVO (desligado | sombra | ligado) de bloco (modo_bloco_agenda), lote (modo_lote_dono), veto (modo_veto), previsto (modo_equipe_previsto), convite (modo_equipe_convite) e camadas (modo_cliente_camadas). Com *gestor, só propor* (gestor_so_propor), o que está ligado em veto, previsto, convite e camadas vale sombra; bloco e lote não respeitam o freio; o desligado continua desligado. Todo leitor desses modos usa esta função; a saúde e o gravador usam o modo cru. Outro nome = 22023. STABLE, invoker.';

-- ── 7. O padrão de cada pergunta ────────────────────────────────────────────────────────────────────
-- A tabela da §5.1 com o R8.5-2. Quem tem relógio próprio fica fora de veto_tipos e nasce com espera = tipo: 2 relógios na mesma pergunta,
-- não. Tipo que esta função não conhece = sem_padrao (o B3 reprova tipo da lista fechada fora do CASE). Efeito opcao sem uma opção de
-- verdade = sem_padrao: a rodada do prazo nunca chama agenda_decidir com nulo (R8.12-2). O prometido sai por fora, com coalesce: só 4 de 131
-- OS têm linha em os_planejamento (R8.12-3), e só os tipos que dependem dele leem a tabela. p_recomendacao = coalesce(opcao_padrao,
-- recomendacao): a opção que seria aplicada. p_os_ids (só isto além da assinatura da spec) = as outras OS da pergunta: prometido em
-- qualquer uma segura. p_critica é da assinatura e não decide nada: a tabela vai pelo tipo, e em BEFORE INSERT a coluna gerada ainda é nula.
create or replace function public._agenda_padrao_da_pergunta(p_tipo text, p_critica boolean, p_os uuid, p_opcoes jsonb,
                                                             p_recomendacao smallint, p_os_ids uuid[] default '{}')
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_chave  text;
  v_efeito text;
  v_espera text;
begin
  case
    when p_tipo = 'duracao' then
      v_chave := 'estimativa'; v_efeito := 'nada';
    when p_tipo = 'material_conferir' then
      v_chave := 'sem_peca'; v_efeito := 'nada';
    when p_tipo = 'padrao_do_dono' then
      v_chave := 'abre_e_fecha'; v_efeito := 'nada';
    when p_tipo = 'dias_semana' then
      v_chave := 'abre_e_fecha'; v_efeito := 'nada'; v_espera := 'tipo';
    when p_tipo in ('previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo') then
      v_chave := 'prazo_padrao'; v_efeito := 'nada';
    when p_tipo in ('parada', 'estouro', 'equipe_resposta') then
      v_chave := 'como_esta'; v_efeito := 'nada';
    when p_tipo = 'chegou' then
      v_chave := 'nao_chegou'; v_efeito := 'nada';
    when p_tipo in ('nao_cabe', 'atraso_longo', 'segundo_atraso', 'fixada_pelo_dono') then
      v_chave := 'recomendacao'; v_efeito := 'opcao';
      if exists (select 1 from public.os_planejamento pl
                  where pl.service_order_id = any (coalesce(p_os_ids, '{}') || p_os) and pl.prometido_tipo is not null) then
        v_espera := 'cliente';
      end if;
    when p_tipo in ('remarcar_confirmado', 'dia_prometido', 'acesso') then
      v_chave := 'recomendacao'; v_efeito := 'opcao'; v_espera := 'cliente';
    when p_tipo in ('diaria', 'diaria_ligar', 'nfe_vincular', 'pix_material', 'concluir', 'entrega', 'compre_ate', 'sinal') then
      v_espera := 'dinheiro';
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta', 'aprendizado', 'conferencia', 'tarefa') then
      v_espera := 'tipo';
    when p_tipo in ('situacao', 'estimativa', 'reestimar', 'ficha_estimativa') then
      v_chave := 'estimativa'; v_efeito := 'opcao';
    when p_tipo in ('bem_livre', 'equipe_cadastro') then
      v_chave := 'como_esta'; v_efeito := 'nada'; v_espera := 'tipo';
    when p_tipo in ('onda', 'dia_avisado', 'sabado') then
      v_chave := 'recomendacao'; v_efeito := 'opcao'; v_espera := 'tipo';
    when p_tipo = 'habilidade' then
      v_chave := 'recomendacao'; v_efeito := 'nada'; v_espera := 'tipo';
    when p_tipo = 'local' then
      v_espera := 'cliente';
    else
      -- reavaliar, equipe_sem_dias, combinar e o tipo que esta função não conhece
      v_espera := 'sem_padrao';
  end case;

  if v_efeito = 'opcao'
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_opcoes) = 'array' then p_opcoes else '[]'::jsonb end) e
                      where e ->> 'n' = p_recomendacao::text) then
    return jsonb_build_object('chave', null, 'efeito', null, 'espera', 'sem_padrao');
  end if;

  if v_espera is null and not p_tipo = any ((public._agenda_cfg()).veto_tipos) then
    v_espera := 'tipo';
  end if;
  return jsonb_build_object('chave', v_chave, 'efeito', v_efeito, 'espera', v_espera);
end;
$function$;

comment on function public._agenda_padrao_da_pergunta(text, boolean, uuid, jsonb, smallint, uuid[]) is
  'Agenda de Produção (Fase 7f, P1; §5.1, R8.5-2; AG7-15): {chave, efeito, espera} do tipo de pergunta. p_recomendacao é a opção que seria aplicada, coalesce(opcao_padrao, recomendacao); efeito opcao sem essa opção entre as opções = sem_padrao. Prometido em p_os ou em p_os_ids = espera cliente. Tipo fora de veto_tipos = espera tipo, mantendo a chave. Tipo desconhecido = sem_padrao. É a foto do nascimento: quem vence confere o prometido de novo. STABLE, sem grant: quem chama é o gatilho, que é definer, e o backfill.';

-- O gatilho: roda depois de agenda_perguntas_antes (ordem alfabética). Definer: quem insere pode ser o service_role, e a função do padrão não
-- tem grant nem precisa cair na RLS de os_planejamento. Falha = exceção: a pergunta não nasce pela metade. Toda pergunta nova, de qualquer etapa e
-- em qualquer modo, passa aqui; o que veio no INSERT nessas colunas é ignorado. destrava nasce 0: a conta é por OS e não roda dentro da vigia (R8.5-6).
create or replace function public._agenda_perguntas_padrao()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v jsonb;
begin
  v := public._agenda_padrao_da_pergunta(new.tipo, new.critica, new.service_order_id, new.opcoes,
                                         coalesce(new.opcao_padrao, new.recomendacao), new.os_ids);
  new.padrao_chave  := v ->> 'chave';
  new.padrao_efeito := v ->> 'efeito';
  new.veto_espera   := v ->> 'espera';
  new.destrava      := 0;
  return new;
end;
$function$;

comment on function public._agenda_perguntas_padrao() is
  'Agenda de Produção (Fase 7f, P1; §5.1, R8.5-6; AG7-15): gatilho BEFORE INSERT de agenda_perguntas: grava padrao_chave, padrao_efeito e veto_espera por _agenda_padrao_da_pergunta e destrava = 0. Nunca muda o texto nem o tipo. Falha = exceção. Security definer, sem grant.';

drop trigger if exists agenda_perguntas_padrao on public.agenda_perguntas;
create trigger agenda_perguntas_padrao before insert on public.agenda_perguntas
  for each row execute function public._agenda_perguntas_padrao();

-- ── 8. O gatilho de antes da pergunta (corpo de 20261031100000:821, a mais nova), recriado ──────────
-- _agenda_perguntas_antes (de 20261031100000_agenda_fase7a_base.sql)
create or replace function public._agenda_perguntas_antes()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- (opções que não são lista: quem recusa é o CHECK da coluna)
  if jsonb_typeof(new.opcoes) = 'array' and jsonb_array_length(new.opcoes) > 0 then
    if new.recomendacao is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.recomendacao::text) then
      raise exception 'A recomendação tem de ser uma das opções da pergunta.';
    end if;
    if new.opcao_escolhida is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.opcao_escolhida::text) then
      raise exception 'Essa opção não existe nesta pergunta.';
    end if;
    -- FASE 7: a opção que vale sem resposta (AG7-15) também é uma das opções.
    if new.opcao_padrao is not null
       and not exists (select 1 from jsonb_array_elements(new.opcoes) e where e ->> 'n' = new.opcao_padrao::text) then
      raise exception 'A opção que vale sem resposta tem de ser uma das opções da pergunta.';
    end if;
    -- FASE 7: fim
  end if;
  if tg_op = 'UPDATE'
     and not public._agenda_so_mudou(to_jsonb(old) - 'critica', to_jsonb(new) - 'critica',
           case when old.estado = 'aberta'
                -- FASE 3: carona_em (a pergunta que foi junto de uma resposta) muda como o "mostrada".
                then array['estado', 'mostrada_vezes', 'mostrada_em', 'mostrada_via', 'respondida_em', 'respondida_por',
                           'respondida_via', 'opcao_escolhida', 'resposta', 'resolvida_motivo', 'expira_em', 'carona_em']
                     -- FASE 7: o prazo vai de nulo a um valor UMA vez, na pergunta aberta (quem mostra com o prazo escrito
                     -- grava: 7b e 7c); de um valor a outro, não (só o 7f, que recria esta função).
                     || case when old.veto_ate is null then array['veto_ate'] else '{}'::text[] end
                     -- FASE 7: fim
                     -- FASE 7f: (7f P1, §4.2, R2, R8.5-9) na aberta, o que o prazo e a ordem gravam. O prazo vai de um valor a outro só na pergunta que
                     -- nunca foi mostrada antes dele, na mesma escrita que a mostra depois dele: o dono está lendo o prazo novo, e o que ele já viu
                     -- com prazo nunca muda. veto_espera vai de nulo a dono (*agenda espera <nome>*) ou a sem_padrao (a recusa do prazo: a pergunta
                     -- fica aberta, sem prazo). padrao_*, e o veto_espera de um valor a outro, só com agenda.backfill_padrao, que só a migration liga.
                     || array['destrava', 'veto_teria_em', 'assumida_por', 'assumida_em']
                     || case when old.veto_ate is not null and new.veto_ate > old.veto_ate and new.mostrada_em > old.veto_ate
                                  and not coalesce(old.mostrada_vezes > 0 and old.mostrada_em < old.veto_ate, false)
                             then array['veto_ate'] else '{}'::text[] end
                     || case when old.veto_espera is null and new.veto_espera in ('dono', 'sem_padrao')
                             then array['veto_espera'] else '{}'::text[] end
                     || case when coalesce(current_setting('agenda.backfill_padrao', true), '') = 'on'
                             then array['padrao_chave', 'padrao_efeito', 'veto_espera'] else '{}'::text[] end
                     -- FASE 7f: fim
                -- FASE 7f: (7f P1, §5.2) na fechada, só o carimbo de que ela ficou com o padrão, de nulo a valor: o prazo decide por agenda_decidir,
                -- que fecha a pergunta, e carimba depois. O CHECK pergunta_assumida_fechada recusa a carimbada ainda aberta.
                when old.estado in ('respondida', 'resolvida') and old.assumida_por is null then array['assumida_por', 'assumida_em']
                -- FASE 7f: fim
                else '{}'::text[] end,
           -- FASE 3: payee_id é ON DELETE SET NULL (apagar o favorecido deixa a pergunta com a pessoa nula).
           array['service_order_id', 'os_material_id', 'proposta_id', 'respondida_por', 'payee_id']) then
    if old.estado = 'aberta' then
      raise exception 'A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.';
    end if;
    raise exception 'A pergunta fechada não muda: a decisão registrada fica como foi.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_perguntas_antes() is 'Agenda de Produção (Fase 2; Fase 3: carona_em e payee_id; Fase 7a: veto_ate e opcao_padrao; Fase 7f: o padrão e o prazo): gatilho BEFORE INSERT/UPDATE — recomendação, opção escolhida e opção padrão são uma das opções; a pergunta só sai de aberta, com o que a mostra/responde/resolve (e a carona); na aberta, destrava, veto_teria_em e assumida_* mudam; veto_ate vai de nulo a um valor uma vez, e de um valor a outro só na pergunta que nunca foi mostrada antes do prazo, na mesma escrita que a mostra; veto_espera vai de nulo a dono ou sem_padrao; padrao_* só com agenda.backfill_padrao = on, que só a migration liga; fechada não muda, fora assumida_* de nulo a valor.';

-- ── 9. O backfill das abertas, ANTES dos CHECKs ─────────────────────────────────────────────────────
-- A mesma função do gatilho, com a mesma opção. Sem pergunta_veto_so_com_padrao (R8.5-1): a equipe_cadastro aberta em produção tem veto_ate e
-- espera = tipo, e passa. No mesmo bloco: set_config(…, true) vale até o fim da transação, e cada bloco é uma transação se o arquivo não for.
do $$
begin
  perform set_config('agenda.backfill_padrao', 'on', true);
  update public.agenda_perguntas q
     set padrao_chave = p.v ->> 'chave', padrao_efeito = p.v ->> 'efeito', veto_espera = p.v ->> 'espera'
    from (select x.id,
                 public._agenda_padrao_da_pergunta(x.tipo, x.critica, x.service_order_id, x.opcoes,
                                                   coalesce(x.opcao_padrao, x.recomendacao), x.os_ids) as v
            from public.agenda_perguntas x
           where x.estado = 'aberta' and x.padrao_chave is null and x.veto_espera is null) p
   where q.id = p.id;
  perform set_config('agenda.backfill_padrao', '', true);
end
$$;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('pergunta_padrao_coerente',   'check ((padrao_chave is null) = (padrao_efeito is null))'),
      ('pergunta_assumida_coerente', 'check ((assumida_por is null) = (assumida_em is null))'),
      ('pergunta_assumida_fechada',  'check (assumida_por is null or estado in (''resolvida'', ''respondida''))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_perguntas'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_perguntas add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- O comentário da 7a dizia que o CHECK recusa o prazo em crítica: não recusa mais.
comment on function public._agenda_gestor_perguntar(text, text, uuid, text, jsonb, smallint, timestamptz, smallint, text, timestamptz) is
  'Agenda de Produção (Fase 7a, P4): grava a pergunta do gestor em agenda_perguntas e devolve o id — uma aberta por chave e modo (devolve a aberta); a fechada não volta na mesma chave (null), salvo a vencida que o dono não viu antes do prazo; perda_em = o dia do prazo (sem prazo, o do expira_em), expira_em = p_veto_ate + desfazer_validade (sem prazo, 7 dias), veto_ate e opcao_padrao como vieram (a Fase 7f tirou o CHECK veto_nao_critica: nenhuma pergunta do gestor com prazo é crítica, e quem decide se vence é a rodada, por veto_tipos e veto_espera). p_modo fora de sombra/ligado = null, nada gravado. Security definer, sem grant a ninguém (nem service_role). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; achado 20 de novo): a pergunta sem prazo que venceu sem resposta também volta na mesma chave (o gestor pergunta de novo a cada expira_em, 7 dias): acima do teto de diárias, a OS não fica sem data e sem pergunta para sempre.';

-- ── 10. A zona e a classe ───────────────────────────────────────────────────────────────────────────
-- §3.1, item 3: travada = até o fim do congelamento (hoje e o próximo dia útil) ou dia já dito à pessoa ou ao cliente, pela _agenda_dia_avisado do
-- 7a, sem repetir a regra; firme = até cliente_semana_du dias úteis; livre = depois. Sem o dia, null: nada a afirmar.
create or replace function public._agenda_zona(p_os uuid, p_payee uuid, p_dia date, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf public.agenda_config;
begin
  if p_dia is null or p_hoje is null then
    return null;
  end if;
  cf := public._agenda_cfg();
  if p_dia <= public.agenda_somar_du(p_hoje, cf.congelamento_du)
     or public._agenda_dia_avisado(p_payee, p_os, p_dia) is not null then
    return 'travada';
  end if;
  if p_dia <= public.agenda_somar_du(p_hoje, cf.cliente_semana_du) then
    return 'firme';
  end if;
  return 'livre';
end;
$function$;

comment on function public._agenda_zona(uuid, uuid, date, date) is
  'Agenda de Produção (Fase 7f, P1; §3.1 item 3): travada (até o fim do congelamento, ou dia já dito: _agenda_dia_avisado do 7a), firme (até cliente_semana_du dias úteis) ou livre. Sem o dia = null. STABLE, sem grant.';

-- §5.1: classe é leitura, não coluna. p_tipo: pergunta, acao ou linha. Pergunta aberta em ligado = decisão. Ação executada e não desfeita = mudança
-- (toda ação executada, pela D7 do dono): o que ela mexe sai das alocações dela, e o dia é o mais cedo. Ação em sombra, pergunta em sombra ou fechada e a
-- linha de leitura = informação. Referência que não existe lança: quem chama diz "não consegui ler", nunca "é só informação".
create or replace function public._agenda_classe_da_saida(p_tipo text, p_ref uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_nao    constant jsonb := jsonb_build_object('equipe', false, 'cliente', false, 'dono', false);
  a        public.agenda_acoes;
  q        public.agenda_perguntas;
  r        record;
  v_amanha date;
  v_dia    date;
  v_zona   text;
  v_z      text;
  v_equipe boolean := false;
  v_cli    boolean := false;
  v_dono   boolean := false;
  v_exc    boolean;
  v_oss    uuid[];
  v_fim    date;
begin
  if p_tipo is null or p_tipo <> all (array['acao', 'pergunta', 'linha']) then
    raise exception '_agenda_classe_da_saida: o tipo "%" não existe.', p_tipo using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_classe_da_saida: sem o dia ou a hora.' using errcode = '22004';
  end if;
  if p_tipo = 'linha' then
    return jsonb_build_object('classe', 'informacao', 'afeta', c_nao, 'zona', null, 'dia', null, 'excecao', false);
  end if;
  v_amanha := public.agenda_somar_du(p_hoje, 1);

  if p_tipo = 'pergunta' then
    select * into q from public.agenda_perguntas x where x.id = p_ref;
    if not found then
      raise exception '_agenda_classe_da_saida: a pergunta % não existe.', p_ref using errcode = 'P0002';
    end if;
    if q.estado = 'aberta' and q.modo = 'ligado' then
      return jsonb_build_object('classe', 'decisao', 'afeta', c_nao,
                                'zona', public._agenda_zona(q.service_order_id, null, coalesce(q.perda_em, q.dia), p_hoje),
                                'dia', coalesce(q.perda_em, q.dia),
                                'excecao', coalesce(q.critica and q.perda_em <= v_amanha, false));
    end if;
    return jsonb_build_object('classe', 'informacao', 'afeta', c_nao, 'zona', null, 'dia', coalesce(q.perda_em, q.dia), 'excecao', false);
  end if;

  select * into a from public.agenda_acoes x where x.id = p_ref;
  if not found then
    raise exception '_agenda_classe_da_saida: a ação % não existe.', p_ref using errcode = 'P0002';
  end if;
  if not a.executada or a.desfeita_em is not null then
    return jsonb_build_object('classe', 'informacao', 'afeta', c_nao, 'zona', null, 'dia', a.dia, 'excecao', false);
  end if;

  -- as OS da ação e o dia mais cedo que ela mexe; sem alocação, o dia que a ação diz, senão o dela
  v_oss := array(select distinct o from unnest(a.os_ids || a.service_order_id) o where o is not null);
  for r in
    select al.service_order_id as os, al.payee_id, al.dia
      from public.agenda_alocacoes al
     where al.id = any (a.alocacoes_criadas || a.alocacoes_canceladas)
     order by al.dia, al.id
  loop
    v_dia := coalesce(v_dia, r.dia);
    v_z := public._agenda_zona(r.os, r.payee_id, r.dia, p_hoje);
    v_zona := case when 'travada' in (v_zona, v_z) then 'travada' when 'firme' in (v_zona, v_z) then 'firme' else coalesce(v_z, v_zona) end;
    if not r.os = any (v_oss) then
      v_oss := v_oss || r.os;
    end if;
    v_equipe := v_equipe or exists (
      select 1 from public.agenda_equipe_mensagens m
       where m.payee_id = r.payee_id and m.modo = 'ligado'
         and m.tipo in ('ficha', 'confirmar', 'convite', 'previsto', 'mudanca')
         and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
         and (m.dia = r.dia or r.dia = any (m.dias)));
    v_cli := v_cli or public._agenda_cliente_ouviu(r.os, r.dia, p_agora);
  end loop;
  if v_dia is null then
    v_dia := coalesce(case when a.depois ->> 'dia' ~ '^\d{4}-\d{2}-\d{2}$' then (a.depois ->> 'dia')::date end, a.dia);
    v_zona := public._agenda_zona(v_oss[1], a.payee_id, v_dia, p_hoje);
    v_cli := exists (select 1 from unnest(v_oss) o where public._agenda_cliente_ouviu(o, v_dia, p_agora));
  end if;

  -- o prometido: o dia ou o fim do plano fora do intervalo dito. Nada de linha em os_planejamento = nada dito (a maioria das OS).
  for r in
    select pl.service_order_id as os, coalesce(pl.prometido_de, pl.prometido_ate) as de, pl.prometido_ate as ate
      from public.os_planejamento pl
     where pl.service_order_id = any (v_oss) and pl.prometido_tipo is not null
  loop
    v_fim := (public._agenda_plano_da_os(r.os, p_hoje) ->> 'ultimo_dia')::date;
    v_cli := v_cli or v_dia not between r.de and r.ate
             or (case when v_fim is null then false else v_fim not between r.de and r.ate end);
  end loop;

  v_dono := exists (select 1 from public.agenda_acoes b
                     where b.id <> a.id and b.executada and b.desfeita_em is null and b.contada_em is not null
                       and (b.service_order_id = any (v_oss) or b.os_ids && v_oss));

  v_exc := v_dia <= v_amanha and (v_equipe or v_cli);
  if a.tipo = 'equipe' and a.depois ->> 'motivo' in ('nao_vou', 'sem_sim') and v_dia <= v_amanha then
    v_exc := true;
  end if;
  return jsonb_build_object('classe', 'mudanca', 'afeta', jsonb_build_object('equipe', v_equipe, 'cliente', v_cli, 'dono', v_dono),
                            'zona', v_zona, 'dia', v_dia, 'excecao', v_exc);
end;
$function$;

comment on function public._agenda_classe_da_saida(text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7f, P1; §3.1 itens 2 e 4, §5.1): {classe: decisao | mudanca | informacao, afeta: {equipe, cliente, dono}, zona, dia, excecao} de uma pergunta, ação ou linha. Calculada na hora: nada é gravado na ação, nada pesa na vigia. Exceção = o dia mais cedo até o próximo dia útil e a mudança mexe no que a equipe ou o cliente já sabem, a falta de alguém para hoje ou o próximo dia útil, ou a crítica que perde até lá. Referência que não existe = P0002. STABLE, sem grant.';

-- ── 11. Portas ──────────────────────────────────────────────────────────────────────────────────────
-- _agenda_perguntas_antes: create or replace mantém a porta de antes (sem grant).
revoke all on function public._agenda_fala_modo(text) from public, anon;
grant execute on function public._agenda_fala_modo(text) to authenticated, service_role;
revoke all on function public._agenda_perguntas_padrao() from public, anon, authenticated, service_role;
revoke all on function public._agenda_padrao_da_pergunta(text, boolean, uuid, jsonb, smallint, uuid[]),
                       public._agenda_zona(uuid, uuid, date, date),
                       public._agenda_classe_da_saida(text, uuid, date, timestamptz)
  from public, anon, authenticated, service_role;
