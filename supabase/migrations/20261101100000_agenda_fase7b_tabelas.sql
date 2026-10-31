-- Agenda de Produção, Fase 7, etapa 7b ("os dias de verdade de quem trabalha e a dupla pela tarefa"), pacote P1: as tabelas, os
-- parâmetros e as listas — os 5 interruptores da etapa (modo_dias, modo_dupla, modo_sabado, modo_cadastro e modo_chamar), os
-- parâmetros com o código da pergunta ao dono, a semana presa da disponibilidade (semana_dita) e de onde ela veio, a situação
-- so_pontas, a coluna chamar do diário do gestor, as listas fechadas ampliadas e o modo de quem faz a pergunta dias_semana.
-- Spec: scratchpad agenda-pesquisa/spec-fase7b.md (§R4.7 P1, §R4.4 "Parâmetros novos", §R4.6, §4, §8.3 agenda_fase7b_base.sql);
-- nomes: fase7-registro.md §1 (7b P1); respostas do dono: fase7-padroes.md (AG7-01 ligar direto; AG7-02 o dono em campo, meia
-- capacidade; AG7-03 a equipe: Alex, o dono e quem vem sob demanda — Mateus e Vinicius; AG7-04 uma pessoa, dupla só quando
-- precisa; AG7-08 sábado quando precisar; AG7-10 quem faz o quê; AG7-13 telefones; AG7-15 sem resposta fica como proposto).
-- Depende das Fases 1 a 6, do lote de 30/10 (20261030100000 .. 100600, em produção) e da 7a inteira (20261031100000 .. 100985 e o
-- dado 20261031100990: o ampliador de listas, o diário do gestor, o tipo equipe_cadastro, dupla_gatilhos/dupla_notas, sabado_manha e
-- _agenda_modo_da_pergunta de 20261031100850).
--
-- ═══ DDL — OK NOMEADO ═══ (26 colunas novas em agenda_config — 5 interruptores e 21 parâmetros — e o DEFAULT dos 5 interruptores;
-- 3 colunas novas em agenda_disponibilidade e 1 em agenda_gestor_dia, nulas ou com DEFAULT; 1 índice novo; 4 listas fechadas
-- ampliadas; 22 CHECKs novos em agenda_config, 3 em agenda_disponibilidade e 1 em agenda_gestor_dia; 1 função recriada; nenhuma
-- tabela nova, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/p1/montar-migration.mjs: a recriada (_agenda_modo_da_pergunta) é o corpo da definição MAIS NOVA,
-- 20261031100850_agenda_fase7a_protecoes.sql (conferida a cada montagem: o montador para se outra migration a definir depois), e
-- a mudança está só no bloco "-- FASE 7b: … -- FASE 7b: fim".
--
-- POR QUE: a capacidade passa a ser o que cada um diz que pode (a pergunta da semana à equipe com telefone e, só quando faz
-- diferença, ao dono), a dupla vale pela tarefa e por meio-dia, quem vem sob demanda (Mateus, Vinicius) entra só nas datas que o
-- dono diz e nunca fica sozinho, o dono conta meia capacidade (AG7-02), o sábado só para prazo firme e o gestor sugere quem chamar.
-- Esta migration só cria o lugar de cada coisa; quem muda comportamento são as próximas (20261101100100 a 100500), sempre atrás
-- dos interruptores. Com os 5 desligados (a linha nasce assim), nada muda para ninguém.
--
-- O QUE MUDA:
--   1. agenda_config: os interruptores modo_dias (a pergunta da semana e as respostas), modo_dupla (a dupla por meio-dia, AG7-04),
--      modo_sabado (AG7-08), modo_cadastro (a chamada da equipe e a lista da rotina, AG7-03/AG7-13) e modo_chamar (a sugestão de
--      quem chamar, R4.4) — desligado | sombra | ligado; a linha fica 'desligado', o DEFAULT da coluna vira 'sombra' (como na 7a);
--      quem os põe em sombra é a migration de dado 20261101100900, com OK nomeado — e 21 parâmetros com o código AG7 no comentário:
--      a hora e a semana da pergunta (equipe_hora_dias 16:45, equipe_dias_semanas_a_frente 2, equipe_dias_tentar_dias 5,
--      equipe_dias_fechar_antes 30 min), o dono (dono_dias_semanal, dono_como_tecnico não, dono_carga_max 0,50, dias_semana_motivos
--      {dono_sem_padrao,semente,chamar}), a dupla (dupla_tec_viagem_min 2, dupla_espera_max_du 5), o novato e quem vem sob demanda
--      (novato_dias 30, novato_diarias 10, novato_sozinho não, sob_demanda_sozinho não), a falta (falta_semanas 8, falta_dias_min
--      10), a chamada da equipe (equipe_chamada_dias 56, equipe_chamada_prazo_du 3, equipe_cadastro_abertas_max 3) e quem chamar
--      (chamar_min_meios 2, chamar_max_os 3). CHECK por nome em cada um (fora os 4 de sim/não). equipe_inativo_dias NÃO existe.
--   2. agenda_disponibilidade: semana_dita (a segunda da semana que a resposta prende; só em exceção), mensagem_id (a pergunta que o
--      diarista respondeu) e pergunta_id (a pergunta do dono que foi respondida), com disp_semana_e_segunda, disp_semana_so_excecao e
--      disp_so_pontas_excecao, e o índice agenda_disp_semana; situacao + so_pontas (o dono só abre e fecha naquele dia).
--   3. agenda_gestor_dia.chamar (a sugestão de quem chamar do dia, que o P6 grava; '{}' até lá).
--   4. As listas fechadas (pelo ampliador da 7a): agenda_equipe_mensagens.tipo + dias; agenda_perguntas.tipo + dias_semana (não
--      crítica: a expressão de critica não muda); agenda_vigia_rodadas.rotina + equipe_semana.
--   5. Recriada _agenda_modo_da_pergunta (de 20261031100850): dias_semana = modo_dias; equipe_cadastro = modo_cadastro fora de
--      desligado (o 7b P3 faz o passo equipe do gestor ceder a chamada ao modo_cadastro: uma pergunta só), senão o do gestor que
--      marca, como antes.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7b_base.sql; registradas em notas-fase77b.md, P1):
--   · modo_chamar e os parâmetros do R4.4 e do R4.2 estão aqui (a §4.1 do corpo só tinha os 4 modos); equipe_inativo_dias saiu
--     (R4.1-6). O DEFAULT de modo_chamar também vira 'sombra' (o molde dos outros 4).
--   · dias_semana_motivos aceita a lista vazia (= nunca pergunta ao dono por motivo, como dono_dias_semanal false) e recusa valor
--     fora de {dono_sem_padrao, semente, chamar, sempre}.
--   · agenda_gestor_dia.chamar com o CHECK por nome em do $$ (agenda_gestor_dia_chamar_check: objeto), como os outros.
--   · Nenhuma função nova: o B4 da spec ("as _agenda_* novas sem grant; agenda_equipe_semana só service_role") vale para o P3; aqui
--     o teste prova as portas da recriada (só o service_role, como antes).
--
-- O QUE NÃO MUDA: nenhum comportamento. Nenhum cron, tela, função de borda ou mensagem. Os valores de antes continuam nas listas (o
-- ampliador lê a lista viva e só soma); as críticas continuam as mesmas; o modo de todo tipo de pergunta de antes é o mesmo (com
-- modo_cadastro desligado, equipe_cadastro continua do gestor que marca).
--
-- ORDEM DE LIGAR (spec §10): depois da 7a inteira (as 15 de estrutura e o dado 20261031100990); antes de 20261101100100 (P2), que
-- lê as colunas novas. Aplicar sozinha não muda nada para ninguém (os interruptores ficam 'desligado' na linha).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7b_base.sql (begin/rollback; cada CHECK recusa uma linha errada e aceita a
-- certa, as listas de antes iguais com as novas no fim, so_pontas e semana_dita só onde podem, RLS e portas, as regex dos gatilhos de
-- dupla e o modo de cada tipo). Na bancada: node scripts/bancada-agenda/rodar.mjs --ate 20261101100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261101100000_agenda_fase7b_tabelas.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261101100000', 'agenda_fase7b_tabelas');"
--
-- DESFAZER (só a estrutura; nada usa as colunas antes das próximas migrations): recriar _agenda_modo_da_pergunta com o corpo de
-- 20261031100850; o resto pode ficar (colunas nulas ou com DEFAULT, listas só somadas). Para tirar mesmo:
--   drop index if exists public.agenda_disp_semana;
--   alter table public.agenda_disponibilidade drop column if exists semana_dita, drop column if exists mensagem_id,
--     drop column if exists pergunta_id;
--   alter table public.agenda_gestor_dia drop column if exists chamar;
--   (as listas: recriar o CHECK de cada uma com os valores da 7a; só sem linha com valor novo)
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$, as listas pelo ampliador (soma só o que falta; rodar de novo não
-- recria nada), create index if not exists, create or replace function, revoke/grant e comment.

-- ── 1. agenda_config: os interruptores e os parâmetros ──────────────────────────────────────────────────────────
alter table public.agenda_config
  -- a linha fica 'desligado' até a migration de dado 20261101100900 (o molde da 7a); o DEFAULT passa a 'sombra' abaixo
  add column if not exists modo_dias                    text         not null default 'desligado',   -- AG7-02 / AG7-03
  add column if not exists modo_dupla                   text         not null default 'desligado',   -- AG7-04
  add column if not exists modo_sabado                  text         not null default 'desligado',   -- AG7-08
  add column if not exists modo_cadastro                text         not null default 'desligado',   -- AG7-03 / AG7-13
  add column if not exists modo_chamar                  text         not null default 'desligado',   -- AG7-03 / AG7-04
  -- a pergunta da semana
  add column if not exists equipe_hora_dias             time         not null default '16:45',       -- AG7-03
  add column if not exists equipe_dias_semanas_a_frente smallint     not null default 2,             -- AG7-03
  add column if not exists equipe_dias_tentar_dias      smallint     not null default 5,             -- AG7-03
  add column if not exists equipe_dias_fechar_antes     interval     not null default '30 minutes',  -- AG7-03 / AG7-15
  -- o dono
  add column if not exists dono_dias_semanal            boolean      not null default true,          -- AG7-02
  add column if not exists dono_como_tecnico            boolean      not null default false,         -- AG7-02
  add column if not exists dono_carga_max               numeric(3,2) not null default 0.50,          -- AG7-02
  add column if not exists dias_semana_motivos          text[]       not null default '{dono_sem_padrao,semente,chamar}',  -- AG7-02 / AG7-03
  -- a dupla
  add column if not exists dupla_tec_viagem_min         smallint     not null default 2,             -- AG7-04
  add column if not exists dupla_espera_max_du          smallint     not null default 5,             -- AG7-04
  -- o novato e quem vem sob demanda
  add column if not exists novato_dias                  smallint     not null default 30,            -- AG7-04 / AG7-10
  add column if not exists novato_diarias               smallint     not null default 10,            -- AG7-04 / AG7-10
  add column if not exists novato_sozinho               boolean      not null default false,         -- AG7-04 / AG7-10
  add column if not exists sob_demanda_sozinho          boolean      not null default false,         -- AG7-03 / AG7-10
  -- a falta (só medida)
  add column if not exists falta_semanas                smallint     not null default 8,             -- AG7-03
  add column if not exists falta_dias_min               smallint     not null default 10,            -- AG7-03
  -- a chamada da equipe e o cadastro
  add column if not exists equipe_chamada_dias          smallint     not null default 56,            -- AG7-03
  add column if not exists equipe_chamada_prazo_du      smallint     not null default 3,             -- AG7-15
  add column if not exists equipe_cadastro_abertas_max  smallint     not null default 3,             -- AG7-03 / AG7-13
  -- quem chamar
  add column if not exists chamar_min_meios             smallint     not null default 2,             -- AG7-03 / AG7-04
  add column if not exists chamar_max_os                smallint     not null default 3;             -- AG7-03 / AG7-04

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_dias_check',      'check (modo_dias in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_dupla_check',     'check (modo_dupla in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_sabado_check',    'check (modo_sabado in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_cadastro_check',  'check (modo_cadastro in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_chamar_check',    'check (modo_chamar in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_equipe_hora_dias_check',
       'check (equipe_hora_dias >= equipe_janela_inicio and equipe_hora_dias <= equipe_janela_fim - interval ''30 minutes'')'),
      ('agenda_config_equipe_dias_semanas_a_frente_check', 'check (equipe_dias_semanas_a_frente between 2 and 3)'),
      ('agenda_config_equipe_dias_tentar_dias_check',      'check (equipe_dias_tentar_dias between 1 and 6)'),
      ('agenda_config_equipe_dias_fechar_antes_check',
       'check (equipe_dias_fechar_antes between interval ''15 minutes'' and interval ''4 hours'')'),
      ('agenda_config_dono_carga_max_check',               'check (dono_carga_max between 0.20 and 1.00)'),
      ('agenda_config_dias_semana_motivos_check',
       'check (dias_semana_motivos <@ array[''dono_sem_padrao'', ''semente'', ''chamar'', ''sempre'']::text[])'),
      ('agenda_config_dupla_tec_viagem_min_check',         'check (dupla_tec_viagem_min between 2 and 6)'),
      ('agenda_config_dupla_espera_max_du_check',          'check (dupla_espera_max_du between 0 and 20)'),
      ('agenda_config_novato_dias_check',                  'check (novato_dias between 0 and 180)'),
      ('agenda_config_novato_diarias_check',               'check (novato_diarias between 0 and 60)'),
      ('agenda_config_falta_semanas_check',                'check (falta_semanas between 4 and 26)'),
      ('agenda_config_falta_dias_min_check',               'check (falta_dias_min between 4 and 60)'),
      ('agenda_config_equipe_chamada_dias_check',          'check (equipe_chamada_dias between 14 and 180)'),
      ('agenda_config_equipe_chamada_prazo_du_check',      'check (equipe_chamada_prazo_du between 1 and 10)'),
      ('agenda_config_equipe_cadastro_abertas_max_check',  'check (equipe_cadastro_abertas_max between 1 and 6)'),
      ('agenda_config_chamar_min_meios_check',             'check (chamar_min_meios between 1 and 20)'),
      ('agenda_config_chamar_max_os_check',                'check (chamar_max_os between 1 and 10)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como a 7a: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem a põe em sombra é
-- a migration de dado 20261101100900, com OK nomeado (AG7-01: ligar no mesmo dia do pós-deploy verde).
alter table public.agenda_config
  alter column modo_dias     set default 'sombra',
  alter column modo_dupla    set default 'sombra',
  alter column modo_sabado   set default 'sombra',
  alter column modo_cadastro set default 'sombra',
  alter column modo_chamar   set default 'sombra';

comment on column public.agenda_config.modo_dias is
  'Agenda de Produção (Fase 7b, AG7-02/AG7-03): a pergunta da semana — toda quinta, a quem está na rotina com dias fixos e telefone ("quais dias você pode na semana de dd/mm?") e, só quando faz diferença (dias_semana_motivos), ao dono; as respostas gravam a semana presa (agenda_disponibilidade.semana_dita) e o padrão. desligado = não pergunta e o rascunho dos dias é o de antes; sombra = registra sem mandar e o dono conta meia capacidade (dono_carga_max); ligado = manda. A migration de dado 20261101100900 põe sombra; o ligar espera o OK dos textos à equipe.';
comment on column public.agenda_config.modo_dupla is
  'Agenda de Produção (Fase 7b, AG7-04): a dupla por meio-dia e pela tarefa (dupla_gatilhos, technician_count_for_travel, os_planejamento.dupla_dita). desligado = a dupla de antes (só a dita o tempo todo pela palavra da 7a); sombra = a dupla só acrescenta a 2ª pessoa onde a tarefa pede (a segurança não espera) e a dita no início ou no fim já espera a 2ª pessoa; ligado = 1 pessoa no resto, a duração conserva as diárias-pessoa e, sem a 2ª pessoa, a inferida vai com 1 e diz quando chamar um ajudante.';
comment on column public.agenda_config.modo_sabado is
  'Agenda de Produção (Fase 7b, AG7-08): o sábado de manhã de quem ofereceu, só para cumprir prazo firme (sabado_manha, da 7a), sempre escrito na marcação. desligado = a pergunta sabado da 7a; sombra = só a linha "Em teste" do resumo; ligado = o motor usa e avisa no texto (a pergunta da 7a sai).';
comment on column public.agenda_config.modo_cadastro is
  'Agenda de Produção (Fase 7b, AG7-03/AG7-13): a chamada da equipe ao dono (quem conto, quem não tem telefone, quem saiu, com prazo depois de vista), a pergunta do contato de quem vem sob demanda e a regra d14 da lista da rotina reaplicada toda quinta. Fora de desligado, a pergunta equipe_cadastro é desta etapa (o passo equipe do gestor da 7a cede). A agenda nunca pede valor de diária (work_profiles é do pagamento).';
comment on column public.agenda_config.modo_chamar is
  'Agenda de Produção (Fase 7b, AG7-03/AG7-04; R4.4): a sugestão de quem chamar — o ajudante para a dupla, a pessoa a mais que faria caber o que está sem lugar e o ajudante que faria cumprir um prazo —, calculada pelo passo diário do gestor (agenda_gestor_dia.chamar) e mostrada no foco *agenda gestor*, na pergunta da quinta e no *livre*. Só sugere: quem chama é o dono; nada é gravado com a pessoa a mais. desligado = não calcula; sombra = só o foco, com "Em teste:"; ligado = os três lugares.';
comment on column public.agenda_config.equipe_hora_dias is
  'Agenda de Produção (Fase 7b, AG7-03): a hora da pergunta da semana na quinta (16:45: depois da publicação das 16:30 e antes do "como foi" das 17:00). Entre equipe_janela_inicio e equipe_janela_fim − 30 min.';
comment on column public.agenda_config.equipe_dias_semanas_a_frente is
  'Agenda de Produção (Fase 7b, AG7-03): a semana perguntada — 2 = a seguinte à próxima (a da quinta que vem planeja; a de agora já sai publicada às 16:30). 2 ou 3.';
comment on column public.agenda_config.equipe_dias_tentar_dias is
  'Agenda de Produção (Fase 7b, AG7-03): por quantos dias (corridos, sem domingo) a pergunta da semana ainda pode sair quando o teto de mensagens do dia já está cheio.';
comment on column public.agenda_config.equipe_dias_fechar_antes is
  'Agenda de Produção (Fase 7b, AG7-03/AG7-15): o prazo da resposta da semana — a quinta que planeja a semana perguntada, hora_do_plano menos isto (30 min). Sem resposta, vale o padrão.';
comment on column public.agenda_config.dono_dias_semanal is
  'Agenda de Produção (Fase 7b, AG7-02): a pergunta dos dias de campo ao dono pode nascer (só com um motivo de dias_semana_motivos). false = nunca pergunta ao dono.';
comment on column public.agenda_config.dono_como_tecnico is
  'Agenda de Produção (Fase 7b, AG7-02): o dono pode ir numa vaga de técnico (por último, nos dias de campo que ele disse, dentro de dono_carga_max). Padrão não: o dono respondeu que acompanha o serviço em andamento e faz o diagnóstico e o comissionamento.';
comment on column public.agenda_config.dono_carga_max is
  'Agenda de Produção (Fase 7b, AG7-02): o teto próprio do dono em campo — a fração dos meios-dias de turno dele na semana (0,50: o dono respondeu "meia capacidade", confirmado no fio em 29/10). O aprendido só abaixa. Vale com modo_dias fora de desligado.';
comment on column public.agenda_config.dias_semana_motivos is
  'Agenda de Produção (Fase 7b, AG7-02/AG7-03; R4.2(b)): quando a pergunta dos dias (dias_semana) nasce para o dono — dono_sem_padrao (ele não disse os dias e uma OS precisa dele o turno inteiro, sem a pergunta padrao_do_dono aberta), semente (alguém na grade sem telefone conta só pela semente do histórico), chamar (a sugestão de quem chamar do dia, com modo_chamar ligado); sempre = toda quinta. Lista vazia = nunca por motivo. Uma por semana.';
comment on column public.agenda_config.dupla_tec_viagem_min is
  'Agenda de Produção (Fase 7b, AG7-04): a OS cujo orçamento previu pelo menos este número de técnicos (service_orders.technician_count_for_travel) vai em dupla o tempo todo (suposição; o dono corrige).';
comment on column public.agenda_config.dupla_espera_max_du is
  'Agenda de Produção (Fase 7b, AG7-04; R4.3(a)): quanto a dupla inferida pela tarefa pode atrasar o fim do serviço, em dias úteis, antes de o serviço ir com 1 pessoa e a agenda sugerir o ajudante (5). A dupla dita pelo dono não cai para 1 pessoa: espera.';
comment on column public.agenda_config.novato_dias is
  'Agenda de Produção (Fase 7b, AG7-04/AG7-10): novato = perfil de diária há menos destes dias (30) E menos de novato_diarias diárias. O 7c troca pela etiqueta.';
comment on column public.agenda_config.novato_diarias is
  'Agenda de Produção (Fase 7b, AG7-04/AG7-10): novato = menos destas diárias (10) E perfil há menos de novato_dias dias.';
comment on column public.agenda_config.novato_sozinho is
  'Agenda de Produção (Fase 7b, AG7-04/AG7-10): o novato pode ficar sozinho num meio-dia? Padrão não (vira dupla com quem não é novato, ou é lacuna).';
comment on column public.agenda_config.sob_demanda_sozinho is
  'Agenda de Produção (Fase 7b, AG7-03/AG7-10; R4.3(d)): quem vem sob demanda (na grade só pelas datas que o dono diz, sem dias fixos: Mateus, Vinicius) pode ficar sozinho num meio-dia? Padrão não — o dono: "ajudante nunca sozinho em tarefa de risco"; vira dupla com um técnico ou é lacuna. Se o dono disser que o auxiliar pode ir sozinho num serviço sem risco, é UPDATE (e, no 7c, a etiqueta).';
comment on column public.agenda_config.falta_semanas is
  'Agenda de Produção (Fase 7b, AG7-03): a janela (semanas) da medida da chance de falta — dias ditos × dias em que a pessoa faltou. Só medida: não desconta capacidade (o 7e decide).';
comment on column public.agenda_config.falta_dias_min is
  'Agenda de Produção (Fase 7b, AG7-03): abaixo destes dias ditos na janela, a chance de falta é "ainda pouco para medir".';
comment on column public.agenda_config.equipe_chamada_dias is
  'Agenda de Produção (Fase 7b, AG7-03): de quantos em quantos dias a chamada da equipe volta ao dono (56); também a janela do "saiu da agenda em dd/mm".';
comment on column public.agenda_config.equipe_chamada_prazo_du is
  'Agenda de Produção (Fase 7b, AG7-15): o prazo da chamada da equipe — este tanto de dias úteis depois de MOSTRADA (veto_ate gravado na 1ª vez que aparece ao dono); sem resposta, segue com a equipe que tem.';
comment on column public.agenda_config.equipe_cadastro_abertas_max is
  'Agenda de Produção (Fase 7b, AG7-03/AG7-13): no máximo tantas perguntas equipe_cadastro abertas ao mesmo tempo (a chamada, o telefone, o contato).';
comment on column public.agenda_config.chamar_min_meios is
  'Agenda de Produção (Fase 7b, AG7-03/AG7-04; R4.4): a sugestão de mais uma pessoa só entra quando o trabalho que passaria a caber soma pelo menos estes meios-dias (2).';
comment on column public.agenda_config.chamar_max_os is
  'Agenda de Produção (Fase 7b, AG7-03/AG7-04; R4.4): quantas OS cada parte da sugestão de quem chamar cita pelo nome nos textos (3); depois, "e mais N".';

-- ── 2. agenda_disponibilidade: a semana presa, de onde veio e o so_pontas ──────────────────────────────────────
alter table public.agenda_disponibilidade
  add column if not exists semana_dita date,
  add column if not exists mensagem_id uuid references public.agenda_equipe_mensagens(id) on delete set null,
  add column if not exists pergunta_id uuid references public.agenda_perguntas(id) on delete set null;

select public._agenda_ampliar_lista('public.agenda_disponibilidade', 'agenda_disponibilidade_situacao_check', 'situacao',
                                    array['so_pontas']);

do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- a semana presa começa na segunda
      ('disp_semana_e_segunda',  'check (semana_dita is null or extract(isodow from semana_dita) = 1)'),
      -- a semana presa é uma linha por dia (exceção), nunca um padrão
      ('disp_semana_so_excecao', 'check (semana_dita is null or periodo is not null)'),
      -- "só abre e fecha" é de uma pessoa e de um dia (ou período), nunca um padrão nem um recesso de todos
      ('disp_so_pontas_excecao', 'check (situacao <> ''so_pontas'' or (periodo is not null and payee_id is not null))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_disponibilidade'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_disponibilidade add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

create index if not exists agenda_disp_semana on public.agenda_disponibilidade(payee_id, semana_dita)
  where substituida_em is null and semana_dita is not null;

comment on column public.agenda_disponibilidade.situacao is
  'disponivel, indisponivel ou confirmada (Fase 1). Fase 7b: so_pontas — o dono disse que naquele dia só abre e fecha (capacidade 0 de campo, as pontas de abrir e fechar livres); só em exceção (periodo) de uma pessoa.';
comment on column public.agenda_disponibilidade.semana_dita is
  'Agenda de Produção (Fase 7b): a segunda da semana que a resposta da semana prende (uma linha por dia útil, em exceção), para a resposta da semana seguinte, que troca o padrão, não mudar a semana já dita. Nula nas outras linhas. Só _agenda_equipe_dias_gravar (P2) escreve.';
comment on column public.agenda_disponibilidade.mensagem_id is
  'Agenda de Produção (Fase 7b): a pergunta da semana (agenda_equipe_mensagens, tipo dias) que a pessoa respondeu e gerou a linha.';
comment on column public.agenda_disponibilidade.pergunta_id is
  'Agenda de Produção (Fase 7b): a pergunta do dono (agenda_perguntas, tipo dias_semana) cuja resposta gerou a linha.';

-- ── 3. agenda_gestor_dia: a sugestão de quem chamar ─────────────────────────────────────────────────────────────
alter table public.agenda_gestor_dia
  add column if not exists chamar jsonb not null default '{}';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.agenda_gestor_dia'::regclass and conname = 'agenda_gestor_dia_chamar_check') then
    alter table public.agenda_gestor_dia add constraint agenda_gestor_dia_chamar_check check (jsonb_typeof(chamar) = 'object');
  end if;
end
$$;

comment on column public.agenda_gestor_dia.chamar is
  'Agenda de Produção (Fase 7b, R4.4): a sugestão de quem chamar do dia ({calculado_em, modo, dupla, capacidade, prazo, texto, texto_pergunta, texto_livre, ms}), que o passo diário chamar do gestor grava (P6, pelo _agenda_gestor_dia_gravar). {} até lá. A pergunta dias_semana da quinta lê daqui (nunca recalcula).';

-- ── 4. As listas fechadas: a mensagem da semana, a pergunta do dono e a rodada ──────────────────────────────────
select public._agenda_ampliar_lista('public.agenda_equipe_mensagens', 'agenda_equipe_mensagens_tipo_check', 'tipo', array['dias']);
-- dias_semana NÃO é crítica: a expressão gerada de agenda_perguntas.critica não muda.
select public._agenda_ampliar_lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check', 'tipo', array['dias_semana']);
select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina',
                                    array['equipe_semana']);

comment on column public.agenda_equipe_mensagens.tipo is
  'Agenda de Produção (Fase 3): ficha (a da véspera), confirmar (a da manhã), como_foi (o "como foi hoje?"), resposta (o que a agenda respondeu). Fase 7b: dias — a pergunta da semana ("quais dias você pode na semana de dd/mm?"); o dia é a segunda da semana perguntada.';
comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor); Fase 5: cliente (as mensagens-modelo ao cliente); Fase 6: aprender (a medição e o aprendizado, uma vez por dia); Fase 7a: gestor (a rodada do gestor da agenda, o job agenda-gestor); Fase 7b: equipe_semana (a pergunta da semana, o passo 0b1 do task-automations). As rodadas de antes são da vigia.';

-- ── 5. O modo de quem faz cada tipo de pergunta (corpo de 20261031100850, a mais nova), recriado ─────────────────
-- Todo tipo da lista fechada tem o modo de quem o faz (o S4 do lote de 30/10 e o B4j da 7a cobram): dias_semana é do modo_dias; a
-- chamada da equipe (equipe_cadastro) passa a ser do modo_cadastro fora de desligado. Quem recriar depois copia DESTA migration
-- (fase7-registro.md §2: 7c P1/P8, 7d P1, 7g P1).
-- _agenda_modo_da_pergunta (de 20261031100850_agenda_fase7a_protecoes.sql)
create or replace function public._agenda_modo_da_pergunta(p_tipo text, p_chave text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_tipo in ('nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono') then c.modo_proposta
    when p_tipo = 'chegou' and coalesce(p_chave, '') like 'chegou:fornecedor:%' then c.modo_material
    -- CORREÇÃO 29/10 (revisão): a equipe sem dias é da vigia.
    when p_tipo = 'equipe_sem_dias' then c.modo_vigia
    -- CORREÇÃO 29/10 (revisão): fim
    when p_tipo in ('conferencia', 'chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'entrega')
      then c.modo_vigia
    when p_tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
      then c.modo_material
    when p_tipo in ('diaria', 'diaria_ligar') then c.modo_diaria
    when p_tipo in ('equipe_resposta', 'concluir') then c.modo_equipe
    when p_tipo in ('cliente_aprovar', 'cliente_aviso', 'cliente_resposta') then c.modo_cliente
    when p_tipo = 'aprendizado' then c.modo_aprendizado
    -- FASE 7: (7a P11) a pergunta da ficha da equipe de um dia pela estimativa (ficha_estimativa) é das mensagens à equipe
    -- (modo_equipe), não do gestor que marca: a proteção vale enquanto houver dia marcado pela estimativa na janela, também com
    -- *gestor, só propor* (sem isso a pergunta nasceria em teste e a ficha ficaria segurada sem o dono poder soltá-la). Vem antes
    -- da linha do 7a P1, que ainda a cita.
    when p_tipo = 'ficha_estimativa' then c.modo_equipe
    -- FASE 7: fim
    -- FASE 7b: (7b P1) a pergunta dos dias da semana ao dono (dias_semana) é do modo_dias; a chamada da equipe (equipe_cadastro)
    -- passa a ser do modo_cadastro quando ele sai de desligado (o 7b P3 faz o passo equipe do gestor ceder: uma pergunta só);
    -- desligado, continua a do gestor que marca (a linha do 7a P1, abaixo, que ainda a cita). Vem antes dela.
    when p_tipo = 'dias_semana' then c.modo_dias
    when p_tipo = 'equipe_cadastro' and c.modo_cadastro <> 'desligado' then c.modo_cadastro
    -- FASE 7b: fim
    -- FASE 7: os tipos do gestor da agenda (7a P1). O dia avisado e o prometido são críticas do plano, como o remarcar
    -- confirmado; a revisão diária faz reavaliar e reestimar; a cobrança do "compre até", a dela; o resto é do gestor que marca.
    when p_tipo in ('dia_avisado', 'dia_prometido') then c.modo_proposta
    when p_tipo in ('reavaliar', 'reestimar') then public._agenda_gestor_modo('revisao')
    when p_tipo = 'compre_ate' then public._agenda_gestor_modo('compre_ate')
    when p_tipo in ('situacao', 'estimativa', 'equipe_cadastro', 'ficha_estimativa', 'bem_livre', 'sinal', 'onda', 'sabado')
      then public._agenda_gestor_modo('marcar')
    -- FASE 7: fim
  end
    from public.agenda_config c
   where c.id;
$function$;

comment on function public._agenda_modo_da_pergunta(text, text) is
  'Agenda de Produção (correção de 29/10, P3): o modo de agenda_config de quem grava cada tipo de pergunta — críticas do plano: modo_proposta; conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono, entrega: modo_vigia; chegou:fornecedor:…, nfe_vincular, pix_material, previsao_fornecedor, fornecedor_cadastro, fornecedores_prazo: modo_material; diaria, diaria_ligar: modo_diaria; equipe_resposta, concluir: modo_equipe; cliente_*: modo_cliente; aprendizado: modo_aprendizado; outro tipo: null. A limpeza da vigia fecha a pergunta aberta em sombra quando este modo está ligado. STABLE, invoker, só o service_role. CORREÇÃO 29/10 (revisão): o tipo novo equipe_sem_dias é da vigia (modo_vigia). Fase 7a (P1): dia_avisado e dia_prometido = modo_proposta (críticas do plano); reavaliar e reestimar = o modo da revisão do gestor; compre_ate = o da cobrança; situacao, estimativa, equipe_cadastro, ficha_estimativa, bem_livre, sinal, onda e sabado = o do gestor que marca (_agenda_gestor_modo). Fase 7a (P11): ficha_estimativa = modo_equipe (a pergunta é das mensagens à equipe: a proteção da ficha vale com *gestor, só propor*); o bloco vem antes da linha do P1, que ainda a cita. Fase 7b (P1): dias_semana = modo_dias (a pergunta dos dias da semana ao dono); equipe_cadastro = modo_cadastro fora de desligado (a chamada da equipe passa a ser da 7b), senão o do gestor que marca, como antes.';

revoke all on function public._agenda_modo_da_pergunta(text, text) from public, anon, authenticated;
grant execute on function public._agenda_modo_da_pergunta(text, text) to service_role;
