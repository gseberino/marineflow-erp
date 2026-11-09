-- Agenda de Produção, Fase 7, etapa 7e ("A margem que aprende"), pacote P1: a base — os 6 interruptores e os 32 parâmetros da etapa, as colunas do que
-- a medição congela (agenda_medidas_os e os_planejamento, com a saída do dono no AG7-33), a tabela das compras, a lista do aprendizado, o modo com o
-- freio e as contas pequenas (credibilidade, normal e temporada).
-- Spec: scratchpad agenda-pesquisa/spec-fase7e.md (§4, §4.5, §8.1, §8.3 agenda_fase7e_base.sql e o bloco R7, que vale sobre o corpo: R7.1, R7.2, R7.3, R7.6,
-- R7.11, R7.12, R7.13); nomes: fase7-registro.md §1 (7e P1); respostas do dono: fase7-padroes.md (AG7-20 temporada; AG7-29 ligar direto; AG7-30 urgência;
-- AG7-31 puxar; AG7-32 sem data de pronto ao cliente; AG7-33 pode corrigir os dias do dono; AG7-07 e AG7-06 os pontos de partida da compra).
-- Depende das Fases 1 a 6, da etapa 7a a 7d e da 7f inteira (última: 20261109101900). NÃO recria nenhuma função de antes: só acrescenta.
--
-- ═══ DDL — OK NOMEADO ═══ (38 colunas novas em agenda_config — 6 interruptores e 32 parâmetros — e o DEFAULT dos 6 interruptores; 12 colunas novas em
-- os_planejamento; 12 colunas novas em agenda_medidas_os; 1 tabela nova, agenda_medidas_compra, com RLS e 2 gatilhos; 1 lista fechada pelo ampliador;
-- 37 CHECKs novos por nome em agenda_config, 3 em os_planejamento e 2 em agenda_medidas_os; 1 índice em agenda_medidas_os, 2 na tabela nova; 6 funções novas, 1 delas de gatilho)
-- NÃO APLICADA. Existe para revisão e espera o OK. Nada aqui é copiado de outra migration: só colunas, CHECKs e funções novas.
--
-- POR QUE: a agenda erra as durações sem saber o quanto, guarda sempre a mesma folga e não mede quanto o dono leva para comprar. Esta etapa mede e ajusta
-- devagar; esta migration só cria o lugar: os interruptores (nascem desligados na linha), os parâmetros, as colunas que vão guardar o retrato do início e o
-- da marcação, e a tabela das compras. Quem usa são os pacotes seguintes (20261111100100 em diante), sempre atrás dos interruptores. Com os 6 desligados
-- (a linha nasce assim), nada muda para ninguém.
--
-- O QUE MUDA:
--   1. agenda_config: modo_vies, modo_folga_semana, modo_urgencia, modo_promessa, modo_tempo_compra e modo_folga_compra, desligado | sombra | ligado; a linha
--      fica 'desligado' e o DEFAULT vira 'sombra' (como de 7a a 7f); quem os põe em sombra é a migration de dado 20261111100900, com OK nomeado. Os parâmetros
--      da credibilidade, do viés, da folga da semana, da temporada, da urgência, do puxar, da promessa e das compras, mais folga_semana_min (R7.4) e
--      aprender_tempo_max (R7.8). CHECK por nome em cada um; nas listas de 12 do mês, o tamanho, a dimensão, o índice começando em 1, nenhum nulo e cada
--      valor entre 0 e 0,20.
--      vies_corrige_dono nasce TRUE (AG7-33, "Sim, pode corrigir"; a spec dizia false). O comentário de fator_promessa fica como está: ele segue sem leitor até o P5 (R7.5); o P5 troca o texto quando lhe der
--      leitor (e o AG7-32 vale: nada disso vai ao cliente).
--   2. os_planejamento: a estimativa congelada no início (estimativa_no_inicio_em, dp_bruto_no_inicio, pessoas_no_inicio, pm_plano_no_inicio,
--      inicio_plano_no_inicio, prazo_plano_no_inicio), o que valeu na marcação (marcado_em, vies_marcado, vies_marcado_chave, tempo_compra_marcado,
--      folga_compra_marcada) e vies_dono_fixo (AG7-33, R7.3-2: o dono repetiu os dias depois de ver a correção; vale o número dele naquela OS). 3 CHECKs por nome.
--   3. agenda_medidas_os: pm_reais, pm_estimados, estimativa_origem, razao_estimativa, pm_plano_dono, razao_dono, prazo_plano_du, prazo_real_du, razao_prazo,
--      vies_marcado, compra_pendente, motivo_razao. O CHECK motivo da Fase 6 não muda. pm_reais e compra_pendente nascem nuláveis, SEM DEFAULT (a §4.2 pedia not null default):
--      com NOT NULL/DEFAULT, o agenda_medir_os de hoje, que o P1 não recria, daria erro no "insert ... select (m).*" (NULL explícito) e, no update, to_jsonb(m) difere de
--      to_jsonb(m0) e a medida anda de versão a cada rodada (R7.5-1; provado no replay real: agenda_aprender 0 → 1 erro, 1 → 21 medidas). O P2 põe o DEFAULT e o NOT NULL na migration
--      que recria agenda_medir_os, depois de encher as linhas.
--   4. agenda_medidas_compra (nova): 1 linha por linha de material crítica que precisou de compra. Não se apaga direto; só muda inteira (versão + 1 e histórico). DESVIO DA §4.3, achado na conferência: a medida
--      nasce com a OS ainda aberta, e o gatilho sem exceção travava exclusões normais de fora da agenda (tirar peça, serviço ou item de OC, apagar OS: a cascata de os_material; apagar fornecedor: o ON DELETE
--      SET NULL dispara o BEFORE UPDATE). Agora a cascata passa (WHEN pg_trigger_depth() = 0 no gatilho de apagar: a linha de material deixou de existir, a medida vai junto) e o SET NULL do fornecedor também
--      (só ele: depth > 1, fornecedor_id de valor a nulo, o resto igual). Apagar direto e nulo direto seguem recusados.
--   5. agenda_aprendizado.item ganha vies, promessa, folga_semana, tempo_compra, folga_compra e prazo_sem_fornecedor, pelo ampliador da 7a.
--   6. Funções novas: _agenda_margem_modo (o modo EFETIVO, com o freio: ligado + freio = sombra; promessa = sombra sempre, AG7-32), _agenda_margem_modo_cru (o
--      modo cru, para o gravador e a saúde: R7.6), _agenda_credibilidade, _agenda_z, _agenda_temporada e o gatilho _agenda_medidas_compra_so_muda. Nada de antes
--      as chama ainda.
--
-- O QUE NÃO MUDA: nenhuma função de antes é recriada; com os 6 interruptores desligados, o motor, a vigia, os textos ao dono, à equipe e ao cliente e as
-- Fases 1 a 7f, byte a byte. As listas fechadas de antes continuam com os mesmos valores (a de aprendizado só soma). fornecedor_n_min não muda aqui (é o dado).
--
-- ORDEM DE LIGAR (spec R7.14): depois da 7f inteira publicada; antes de 20261111100100 (P2), que lê as colunas novas. À noite, depois das 21:00, logo depois de um
-- tique, com LOCK_TIMEOUT=5s: há ALTER TABLE em agenda_config, os_planejamento e agenda_medidas_os. Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7e_base.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261111100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; pelo publicar/exec/aplicar.sh, nunca db push: esta versão fica antes das 20261116* que já estão em produção):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261111100000_agenda_fase7e_tabelas.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261111100000', 'agenda_fase7e_tabelas');"
--
-- DESFAZER (só com os interruptores desligados e nada usando; a medição dos pacotes seguintes grava nestas colunas):
--   drop trigger if exists agenda_medidas_compra_nao_apaga on public.agenda_medidas_compra;
--   drop trigger if exists agenda_medidas_compra_so_muda on public.agenda_medidas_compra;
--   drop table if exists public.agenda_medidas_compra;
--   drop function if exists public._agenda_medidas_compra_so_muda(), public._agenda_margem_modo(text), public._agenda_margem_modo_cru(text),
--     public._agenda_credibilidade(numeric, integer, numeric, integer), public._agenda_z(numeric), public._agenda_temporada(date);
--   alter table public.agenda_medidas_os drop constraint if exists razao_so_valida, drop constraint if exists razao_dono_so_valida,
--     drop column if exists pm_reais, drop column if exists pm_estimados, drop column if exists estimativa_origem, drop column if exists razao_estimativa,
--     drop column if exists pm_plano_dono, drop column if exists razao_dono, drop column if exists prazo_plano_du, drop column if exists prazo_real_du,
--     drop column if exists razao_prazo, drop column if exists vies_marcado, drop column if exists compra_pendente, drop column if exists motivo_razao;
--   (os_planejamento: drop das 12 colunas e dos 3 CHECKs; agenda_config: drop dos 37 CHECKs e das 38 colunas; agenda_aprendizado_item_check: recriar com os 10 da
--    Fase 6, só com nenhuma linha dos itens novos.)
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (só cria o que falta), o ampliador (soma só o que falta), create table if not exists,
-- create index if not exists, drop trigger if exists + create, drop policy if exists + create, create or replace function, revoke/grant e comment.

-- ── 1. agenda_config: os interruptores e os parâmetros ──────────────────────────────────────────────
alter table public.agenda_config
  -- os interruptores: a linha fica 'desligado' até a migration de dado 20261111100900 (o molde de 7a a 7f); o DEFAULT passa a 'sombra' abaixo
  add column if not exists modo_vies                  text         not null default 'desligado',  -- AG7-29
  add column if not exists modo_folga_semana          text         not null default 'desligado',  -- AG7-29
  add column if not exists modo_urgencia              text         not null default 'desligado',  -- AG7-29, AG7-30, AG7-31
  add column if not exists modo_promessa              text         not null default 'desligado',  -- AG7-32: fica em sombra para sempre, o ligar-fase7e.sql recusa
  add column if not exists modo_tempo_compra          text         not null default 'desligado',  -- AG7-07, AG7-29
  add column if not exists modo_folga_compra          text         not null default 'desligado',  -- AG7-29; sem efeito nesta etapa (R7.5-16)
  -- a credibilidade (Z = n / (n + k))
  add column if not exists credibilidade_k            smallint     not null default 5,
  -- o viés da estimativa pelo valor
  add column if not exists vies_n_min                 smallint     not null default 1,
  add column if not exists vies_min                   numeric(3,2) not null default 0.50,
  add column if not exists vies_max                   numeric(3,2) not null default 2.50,
  add column if not exists vies_corrige_dono          boolean      not null default true,         -- AG7-33: "Sim, pode corrigir" (R7.3-2)
  -- a folga da equipe-semana
  add column if not exists folga_dispersao_padrao     numeric(3,2) not null default 0.15,
  add column if not exists folga_percentil            numeric(3,2) not null default 0.80,
  add column if not exists folga_semanas              smallint     not null default 12,
  add column if not exists folga_semanas_min          smallint     not null default 8,
  add column if not exists folga_residuos_min         smallint     not null default 6,
  add column if not exists folga_meios_min            smallint     not null default 4,
  add column if not exists folga_semana_max           numeric(3,2) not null default 0.30,
  add column if not exists folga_semana_min           numeric(3,2) not null default 0.05,         -- R7.4 (o piso: σ = 0 não pode zerar a folga)
  add column if not exists folga_semana_troca_max     numeric(3,2) not null default 0.05,
  add column if not exists carga_semana_min           numeric(3,2) not null default 0.60,
  add column if not exists carga_semana_max           numeric(3,2) not null default 0.95,
  -- a temporada: o tanto a mais da semana guardado para urgência, de janeiro a dezembro (AG7-20)
  add column if not exists folga_temporada_barco      numeric(3,2)[] not null default '{0.10,0.10,0.05,0,0,0,0,0,0,0,0.05,0.10}',  -- AG7-20
  add column if not exists folga_temporada_rv         numeric(3,2)[] not null default '{0,0,0,0,0.05,0.10,0,0,0,0,0.05,0.10}',     -- AG7-20
  -- a urgência e o puxar na véspera
  add column if not exists urgencia_du                smallint     not null default 5,            -- AG7-30
  add column if not exists puxar_hora                 time         not null default '17:30',
  add column if not exists puxar_quem                 text         not null default 'ja_vem',     -- AG7-31
  add column if not exists puxar_max_os               smallint     not null default 1,            -- AG7-31
  -- o prazo real que o dono vê (o ponto de partida é fator_promessa; AG7-32: nada disso vai ao cliente)
  add column if not exists promessa_n_min             smallint     not null default 1,
  add column if not exists promessa_min               numeric(3,2) not null default 1.00,
  -- as compras
  add column if not exists tempo_compra_n_min         smallint     not null default 3,            -- AG7-07
  add column if not exists tempo_compra_percentil     numeric(3,2) not null default 0.50,
  add column if not exists tempo_compra_max_du        smallint     not null default 15,
  add column if not exists folga_compra_n_min         smallint     not null default 3,
  add column if not exists folga_compra_percentil     numeric(3,2) not null default 0.80,
  add column if not exists folga_compra_max_du        smallint     not null default 5,
  add column if not exists prazo_sem_fornecedor_n_min smallint     not null default 3,            -- AG7-06
  -- a rodada do aprendizado (R7.8): o relógio entre os passos da margem
  add column if not exists aprender_tempo_max         interval     not null default '20 seconds';

-- Como de 7a a 7f: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima); quem a põe em sombra é a migration de
-- dado 20261111100900, com OK nomeado.
alter table public.agenda_config
  alter column modo_vies         set default 'sombra',
  alter column modo_folga_semana set default 'sombra',
  alter column modo_urgencia     set default 'sombra',
  alter column modo_promessa     set default 'sombra',
  alter column modo_tempo_compra set default 'sombra',
  alter column modo_folga_compra set default 'sombra';

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_vies_check',                 'check (modo_vies in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_folga_semana_check',         'check (modo_folga_semana in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_urgencia_check',             'check (modo_urgencia in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_promessa_check',             'check (modo_promessa in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_tempo_compra_check',         'check (modo_tempo_compra in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_modo_folga_compra_check',         'check (modo_folga_compra in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_credibilidade_k_check',           'check (credibilidade_k between 1 and 30)'),
      ('agenda_config_vies_n_min_check',                'check (vies_n_min between 1 and 20)'),
      ('agenda_config_vies_min_check',                  'check (vies_min between 0.30 and 1.00 and vies_min < vies_max)'),
      ('agenda_config_vies_max_check',                  'check (vies_max between 1.00 and 3.00)'),
      ('agenda_config_folga_dispersao_padrao_check',    'check (folga_dispersao_padrao between 0.05 and 0.30)'),
      ('agenda_config_folga_percentil_check',           'check (folga_percentil between 0.50 and 0.95)'),
      ('agenda_config_folga_semanas_check',             'check (folga_semanas between 8 and 26)'),
      ('agenda_config_folga_semanas_min_check',         'check (folga_semanas_min between 4 and folga_semanas)'),
      ('agenda_config_folga_residuos_min_check',        'check (folga_residuos_min between 3 and 20)'),
      ('agenda_config_folga_meios_min_check',           'check (folga_meios_min between 1 and 20)'),
      ('agenda_config_folga_semana_max_check',          'check (folga_semana_max between 0.05 and 0.40)'),
      -- R7.4: a menor folga (nunca acima da maior)
      ('agenda_config_folga_semana_min_check',          'check (folga_semana_min between 0.00 and 0.20 and folga_semana_min <= folga_semana_max)'),
      ('agenda_config_folga_semana_troca_max_check',    'check (folga_semana_troca_max between 0.01 and 0.20)'),
      ('agenda_config_carga_semana_min_check',          'check (carga_semana_min between 0.50 and 0.90 and carga_semana_min < carga_semana_max)'),
      ('agenda_config_carga_semana_max_check',          'check (carga_semana_max between 0.80 and 1.00)'),
      -- As duas listas do mês: "0 <= all (...)" com NULL dá NULL, e CHECK com NULL passa: o nulo é recusado à parte. Com índice que não começa em 1, folga[mes] voltaria nulo em dezembro.
      ('agenda_config_folga_temporada_barco_check',
       'check (cardinality(folga_temporada_barco) = 12 and array_ndims(folga_temporada_barco) = 1 and array_lower(folga_temporada_barco, 1) = 1 and array_position(folga_temporada_barco, null) is null and 0 <= all (folga_temporada_barco) and 0.20 >= all (folga_temporada_barco))'),
      ('agenda_config_folga_temporada_rv_check',
       'check (cardinality(folga_temporada_rv) = 12 and array_ndims(folga_temporada_rv) = 1 and array_lower(folga_temporada_rv, 1) = 1 and array_position(folga_temporada_rv, null) is null and 0 <= all (folga_temporada_rv) and 0.20 >= all (folga_temporada_rv))'),
      ('agenda_config_urgencia_du_check',               'check (urgencia_du between 1 and 20)'),
      ('agenda_config_puxar_hora_check',                'check (puxar_hora between ''12:00'' and ''19:00'')'),
      ('agenda_config_puxar_quem_check',                'check (puxar_quem in (''ja_vem'', ''disponivel''))'),
      ('agenda_config_puxar_max_os_check',              'check (puxar_max_os between 1 and 3)'),
      ('agenda_config_promessa_n_min_check',            'check (promessa_n_min between 1 and 20)'),
      ('agenda_config_promessa_min_check',              'check (promessa_min between 1.00 and 1.50)'),
      ('agenda_config_tempo_compra_n_min_check',        'check (tempo_compra_n_min between 2 and 20)'),
      ('agenda_config_tempo_compra_percentil_check',    'check (tempo_compra_percentil between 0.50 and 0.95)'),
      ('agenda_config_tempo_compra_max_du_check',       'check (tempo_compra_max_du between 5 and 40)'),
      ('agenda_config_folga_compra_n_min_check',        'check (folga_compra_n_min between 2 and 20)'),
      ('agenda_config_folga_compra_percentil_check',    'check (folga_compra_percentil between 0.50 and 0.95)'),
      ('agenda_config_folga_compra_max_du_check',       'check (folga_compra_max_du between 1 and 10)'),
      ('agenda_config_prazo_sem_fornecedor_n_min_check', 'check (prazo_sem_fornecedor_n_min between 2 and 20)'),
      -- R7.8: abaixo dos 30 s de statement_timeout do service_role, senão o relógio nunca dispara antes do corte
      ('agenda_config_aprender_tempo_max_check',
       'check (aprender_tempo_max between interval ''5 seconds'' and interval ''25 seconds'')')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.agenda_config.modo_vies is
  'Agenda de Produção (Fase 7e, AG7-29): o viés da estimativa pelo valor. Sombra só calcula e mostra em teste. Respeita o freio: ligado + gestor_so_propor = sombra. Leia por _agenda_margem_modo(''vies''); o gravador e a saúde leem _agenda_margem_modo_cru.';
comment on column public.agenda_config.modo_folga_semana is
  'Agenda de Produção (Fase 7e, AG7-29): a folga da equipe-semana. Respeita o freio. Leia por _agenda_margem_modo(''folga_semana'').';
comment on column public.agenda_config.modo_urgencia is
  'Agenda de Produção (Fase 7e, AG7-29, AG7-30, AG7-31): a OS urgente que usa a folga e o puxar na véspera. Respeita o freio. Leia por _agenda_margem_modo(''urgencia'').';
comment on column public.agenda_config.modo_promessa is
  'Agenda de Produção (Fase 7e, AG7-32, R7.3-1): fica em sombra para sempre. O cliente não ouve data de pronto; o prazo real é só para o dono. O publicar/exec/ligar-fase7e.sql recusa ligar. _agenda_margem_modo(''promessa'') devolve sombra sempre.';
comment on column public.agenda_config.modo_tempo_compra is
  'Agenda de Produção (Fase 7e, AG7-07, AG7-29): o tempo interno de compra medido no lugar de compra_interna_du. Respeita o freio. Leia por _agenda_margem_modo(''tempo_compra'').';
comment on column public.agenda_config.modo_folga_compra is
  'Agenda de Produção (Fase 7e, AG7-29): sem efeito nesta etapa (R7.5-16). Ficam a coluna, a medida, o item e a linha no foco; o leitor fica para quando houver 3 OS medidas.';
comment on column public.agenda_config.credibilidade_k is 'Agenda de Produção (Fase 7e): o k da credibilidade (Z = n / (n + k)): com n OS medidas, o valor medido pesa Z e o ponto de partida pesa 1 − Z. 1..30.';
comment on column public.agenda_config.vies_n_min is 'Agenda de Produção (Fase 7e): quantas OS com razao_estimativa fazem o item vies mexer. 1..20.';
comment on column public.agenda_config.vies_min is 'Agenda de Produção (Fase 7e): o menor viés que a agenda usa. 0,30..1,00 e abaixo de vies_max.';
comment on column public.agenda_config.vies_max is 'Agenda de Produção (Fase 7e): o maior viés que a agenda usa. 1,00..3,00.';
comment on column public.agenda_config.vies_corrige_dono is
  'Agenda de Produção (Fase 7e, AG7-33, R7.3-2): o viés corrige também os dias ditos pelo dono (os_planejamento.dias com fonte dono/aceita), mostrando os dois números. Nunca mexe na dupla dita. O dono repete os dias depois de ver a correção e vale o número dele (vies_dono_fixo).';
comment on column public.agenda_config.folga_dispersao_padrao is 'Agenda de Produção (Fase 7e): a folga da semana enquanto não há 8 semanas e 6 resíduos medidos. 0,05..0,30.';
comment on column public.agenda_config.folga_percentil is 'Agenda de Produção (Fase 7e): o percentil do erro por semana que a folga cobre. 0,50..0,95.';
comment on column public.agenda_config.folga_semanas is 'Agenda de Produção (Fase 7e): as semanas olhadas para medir a folga. 8..26.';
comment on column public.agenda_config.folga_semanas_min is 'Agenda de Produção (Fase 7e): o mínimo de semanas para a folga medida valer. 4..folga_semanas.';
comment on column public.agenda_config.folga_residuos_min is 'Agenda de Produção (Fase 7e): o mínimo de resíduos (OS do estimador) para a folga medida valer. 3..20.';
comment on column public.agenda_config.folga_meios_min is 'Agenda de Produção (Fase 7e): o mínimo de pessoa-meios firmes para a semana contar na folga. 1..20.';
comment on column public.agenda_config.folga_semana_max is 'Agenda de Produção (Fase 7e): a maior folga da semana. 0,05..0,40.';
comment on column public.agenda_config.folga_semana_min is
  'Agenda de Produção (Fase 7e, R7.4): a menor folga da semana, no lugar do piso 0: com o *dia feito* ecoando o plano, a dispersão zera e a reserva sumiria por falta de medida. 0..0,20 e no máximo folga_semana_max.';
comment on column public.agenda_config.folga_semana_troca_max is 'Agenda de Produção (Fase 7e): o maior passo da folga em uma rodada. 0,01..0,20.';
comment on column public.agenda_config.carga_semana_min is 'Agenda de Produção (Fase 7e): a menor carga da equipe-semana. 0,50..0,90 e abaixo de carga_semana_max.';
comment on column public.agenda_config.carga_semana_max is 'Agenda de Produção (Fase 7e): a maior carga da equipe-semana. 0,80..1,00.';
comment on column public.agenda_config.folga_temporada_barco is
  'Agenda de Produção (Fase 7e, AG7-20): o tanto a mais da semana guardado para urgência em temporada de barco, de janeiro a dezembro. Só vale nos meses de temporada_meses (a fonte única). 12 valores, cada um de 0 a 0,20.';
comment on column public.agenda_config.folga_temporada_rv is
  'Agenda de Produção (Fase 7e, AG7-20): o tanto a mais da semana guardado para urgência em temporada de motorhome, de janeiro a dezembro. 12 valores, cada um de 0 a 0,20.';
comment on column public.agenda_config.urgencia_du is 'Agenda de Produção (Fase 7e, AG7-30): serviço com prazo do cliente em até N dias úteis conta como urgente. 1..20.';
comment on column public.agenda_config.puxar_hora is 'Agenda de Produção (Fase 7e): a partir desta hora o gestor pode puxar para amanhã uma OS pronta (passo puxar do agenda-gestor). 12:00..19:00.';
comment on column public.agenda_config.puxar_quem is 'Agenda de Produção (Fase 7e, AG7-31): quem pode ser puxado: ja_vem (só quem já vem no dia) ou disponivel.';
comment on column public.agenda_config.puxar_max_os is 'Agenda de Produção (Fase 7e, AG7-31): quantas OS o gestor puxa por dia. 1..3.';
comment on column public.agenda_config.promessa_n_min is 'Agenda de Produção (Fase 7e): quantas OS com razao_prazo fazem o item promessa mexer. 1..20.';
comment on column public.agenda_config.promessa_min is 'Agenda de Produção (Fase 7e, AG7-32): o menor fator do prazo real que o dono vê. 1,00..1,50. Nunca vai ao cliente.';
comment on column public.agenda_config.tempo_compra_n_min is 'Agenda de Produção (Fase 7e, AG7-07): quantas OS com tempo de compra medido fazem o item mexer. 2..20.';
comment on column public.agenda_config.tempo_compra_percentil is 'Agenda de Produção (Fase 7e): o percentil do tempo de compra. 0,50..0,95.';
comment on column public.agenda_config.tempo_compra_max_du is 'Agenda de Produção (Fase 7e): o maior tempo de compra que a agenda usa, em dias úteis. 5..40.';
comment on column public.agenda_config.folga_compra_n_min is 'Agenda de Produção (Fase 7e): quantas OS medem a folga da compra. 2..20.';
comment on column public.agenda_config.folga_compra_percentil is 'Agenda de Produção (Fase 7e): o percentil do atraso da chegada. 0,50..0,95.';
comment on column public.agenda_config.folga_compra_max_du is 'Agenda de Produção (Fase 7e): a maior folga da compra, em dias úteis. 1..10.';
comment on column public.agenda_config.prazo_sem_fornecedor_n_min is 'Agenda de Produção (Fase 7e, AG7-06): quantas compras medem o prazo da peça sem fornecedor. 2..20.';
comment on column public.agenda_config.aprender_tempo_max is 'Agenda de Produção (Fase 7e, R7.8): o tempo da rodada do aprendizado; passou daí, ela pula os passos da margem e grava parou_no. 5..25 s, abaixo do corte de 30 s do service_role.';
-- ── 2. os_planejamento: o que a medição congela ─────────────────────────────────────────────────────
alter table public.os_planejamento
  -- a estimativa do dia do início (congelada pela rodada; a medida usa estas)
  add column if not exists estimativa_no_inicio_em date,
  add column if not exists dp_bruto_no_inicio      numeric(6,2) check (dp_bruto_no_inicio > 0),
  add column if not exists pessoas_no_inicio       smallint     check (pessoas_no_inicio between 1 and 6),
  add column if not exists pm_plano_no_inicio      numeric(6,1) check (pm_plano_no_inicio > 0),
  add column if not exists inicio_plano_no_inicio  date,
  add column if not exists prazo_plano_no_inicio   smallint     check (prazo_plano_no_inicio > 0),
  -- o que valeu na marcação (congelado pela rodada; "o publicado não muda pelo aprendizado")
  add column if not exists marcado_em              date,
  add column if not exists vies_marcado            numeric(4,2) check (vies_marcado > 0),
  add column if not exists vies_marcado_chave      text check (char_length(vies_marcado_chave) <= 60),
  add column if not exists tempo_compra_marcado    smallint check (tempo_compra_marcado >= 0),
  add column if not exists folga_compra_marcada    smallint check (folga_compra_marcada >= 0),
  -- AG7-33, R7.3-2: o dono repetiu os dias depois de ver a correção
  add column if not exists vies_dono_fixo          boolean not null default false;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('estimativa_no_inicio_coerente',
       'check (estimativa_no_inicio_em is not null or (dp_bruto_no_inicio is null and pessoas_no_inicio is null and pm_plano_no_inicio is null and prazo_plano_no_inicio is null))'),
      ('marcado_coerente',
       'check (marcado_em is not null or (vies_marcado is null and tempo_compra_marcado is null and folga_compra_marcada is null))'),
      ('prazo_plano_coerente',
       'check ((prazo_plano_no_inicio is null) = (inicio_plano_no_inicio is null))')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.os_planejamento'::regclass and conname = r.nome) then
      execute format('alter table public.os_planejamento add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.os_planejamento.estimativa_no_inicio_em is 'Agenda de Produção (Fase 7e, P2): o dia em que a rodada congelou a estimativa desta OS. Sem isso, as colunas do início ficam nulas: a OS sem base não tem dp, mas a data nunca fica para trás.';
comment on column public.os_planejamento.dp_bruto_no_inicio is 'Agenda de Produção (Fase 7e): diárias-pessoa da estimativa pelo valor no início, ao R$ padrão (nunca o aprendido).';
comment on column public.os_planejamento.pessoas_no_inicio is 'Agenda de Produção (Fase 7e): as pessoas da estimativa no início. 1..6.';
comment on column public.os_planejamento.pm_plano_no_inicio is 'Agenda de Produção (Fase 7e): os pessoa-meios do molde no início.';
comment on column public.os_planejamento.inicio_plano_no_inicio is 'Agenda de Produção (Fase 7e): o 1º dia do plano no início (prazo_plano_du conta dele).';
comment on column public.os_planejamento.prazo_plano_no_inicio is 'Agenda de Produção (Fase 7e): os dias úteis do 1º ao último dia planejado, no início.';
comment on column public.os_planejamento.marcado_em is 'Agenda de Produção (Fase 7e): o dia em que a OS ganhou compromisso; congela o que valeu na marcação.';
comment on column public.os_planejamento.vies_marcado is 'Agenda de Produção (Fase 7e, AG7-33): o viés que valeu na marcação. Com vies_dono_fixo, 1,00.';
comment on column public.os_planejamento.vies_marcado_chave is 'Agenda de Produção (Fase 7e): a chave de aprendizado do viés que valeu na marcação.';
comment on column public.os_planejamento.tempo_compra_marcado is 'Agenda de Produção (Fase 7e): o tempo interno de compra que valeu na marcação.';
comment on column public.os_planejamento.folga_compra_marcada is 'Agenda de Produção (Fase 7e): a folga própria da compra que valeu na marcação. Sem leitor nesta etapa (R7.5-16).';
comment on column public.os_planejamento.vies_dono_fixo is 'Agenda de Produção (Fase 7e, AG7-33, R7.3-2): o dono repetiu os dias depois de ver a correção; vale o número dele nesta OS, e soltar a OS da fila não apaga (P3, _agenda_aprender_congelar_marcacao).';

-- ── 3. agenda_medidas_os: o que a medição grava ─────────────────────────────────────────────────────
alter table public.agenda_medidas_os
  add column if not exists pm_reais          numeric(6,1),
  add column if not exists pm_estimados      numeric(6,1),
  add column if not exists estimativa_origem text check (estimativa_origem in ('congelada', 'recalculada')),
  add column if not exists razao_estimativa  numeric(4,2),
  add column if not exists pm_plano_dono     numeric(6,1),
  add column if not exists razao_dono        numeric(4,2),
  add column if not exists prazo_plano_du    smallint,
  add column if not exists prazo_real_du     smallint,
  add column if not exists razao_prazo       numeric(4,2),
  add column if not exists vies_marcado      numeric(4,2),
  add column if not exists compra_pendente   boolean,
  add column if not exists motivo_razao      text check (motivo_razao in ('reaberta', 'sem_inicio', 'sem_fim', 'sem_estimativa',
                                                                        'conferencia_incompleta', 'sem_diaria', 'sem_trabalho'));

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('razao_so_valida',      'check (razao_estimativa is null or motivo_razao is null)'),
      ('razao_dono_so_valida', 'check (razao_dono is null or motivo_razao is null)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_medidas_os'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_medidas_os add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

create index if not exists agenda_medidas_os_razao on public.agenda_medidas_os(concluida_em desc) where motivo_razao is null;

comment on column public.agenda_medidas_os.pm_reais is 'Agenda de Produção (Fase 7e): os pessoa-meios que aconteceram (o dono que vai junto não conta: R7.4). Nasce nulável (o P1 não recria agenda_medir_os); o P2 grava em todo caminho e põe NOT NULL.';
comment on column public.agenda_medidas_os.pm_estimados is 'Agenda de Produção (Fase 7e): 2 × dp_bruto_no_inicio (o estimador ao R$ padrão).';
comment on column public.agenda_medidas_os.estimativa_origem is 'Agenda de Produção (Fase 7e): congelada (a da rodada do início) ou recalculada (a OS medida antes da 7e).';
comment on column public.agenda_medidas_os.razao_estimativa is 'Agenda de Produção (Fase 7e): pm_reais ÷ pm_estimados, só com motivo_razao nulo.';
comment on column public.agenda_medidas_os.pm_plano_dono is 'Agenda de Produção (Fase 7e): os pessoa-meios planejados pelo dono (só fonte dono/aceita).';
comment on column public.agenda_medidas_os.razao_dono is 'Agenda de Produção (Fase 7e): pm_reais ÷ pm_plano_dono, só com motivo_razao nulo.';
comment on column public.agenda_medidas_os.prazo_plano_du is 'Agenda de Produção (Fase 7e): os dias úteis planejados do início ao fim (prazo real, só ao dono).';
comment on column public.agenda_medidas_os.prazo_real_du is 'Agenda de Produção (Fase 7e): os dias úteis reais do início ao fim.';
comment on column public.agenda_medidas_os.razao_prazo is 'Agenda de Produção (Fase 7e): prazo_real_du ÷ prazo_plano_du.';
comment on column public.agenda_medidas_os.vies_marcado is 'Agenda de Produção (Fase 7e): o viés que valeu na marcação, para quem compara o publicado.';
comment on column public.agenda_medidas_os.compra_pendente is 'Agenda de Produção (Fase 7e): a OS tinha compra por fazer quando começou (a folga da compra). Nasce nulável (ver pm_reais); o P2 grava em todo caminho e põe NOT NULL.';
comment on column public.agenda_medidas_os.motivo_razao is 'Agenda de Produção (Fase 7e, R7.4): por que a razão não vale nesta OS (motivo e valida da Fase 6 não mudam).';

-- ── 4. agenda_medidas_compra: uma linha por linha de material crítica que precisou de compra ───────
create table if not exists public.agenda_medidas_compra (
  os_material_id        uuid primary key references public.os_material(id) on delete cascade,
  service_order_id      uuid not null references public.service_orders(id) on delete cascade,
  fornecedor_id         uuid references public.suppliers(id) on delete set null,
  sem_fornecedor        boolean not null,
  entrega               text not null check (char_length(entrega) <= 60),
  aprovada_em           date not null,
  precisou_em           date not null,
  -- o retrato da marcação (só quando a OS ganhou o 1º compromisso com esta linha ainda por comprar)
  marcada_em            date,
  primeiro_dia          date,
  compre_ate            date,
  chegada_contada       date,
  prazo_contado_du      smallint,
  prazo_fonte           text check (char_length(prazo_fonte) <= 20),
  tempo_interno_du      smallint,
  folga_compra_du       smallint,
  -- os fatos
  comprado_em           date,
  comprado_fonte        text check (comprado_fonte in ('dono', 'oc', 'pix', 'fornecedor', 'nfe', 'registro', 'balcao')),
  chegou_em             date,
  previsao_original_em  date,
  -- o medido
  tempo_compra_du       smallint,
  prazo_real_du         smallint,
  atraso_chegada_du     smallint,
  comprou_ate_o_limite  boolean,
  primeiro_dia_cumprido boolean,
  valida_tempo          boolean not null,
  valida_prazo          boolean not null,
  valida_folga          boolean not null,
  motivo                text check (motivo in ('nao_critica', 'sem_compra', 'compra_antes', 'sem_chegada', 'balcao_inferido',
                                               'nao_marcada', 'comprada_antes_de_marcar', 'reaberta')),
  medida_em             timestamptz not null,
  versao                smallint not null default 1,
  historico             jsonb not null default '[]'
                          check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  constraint compra_marcada_coerente check ((marcada_em is null) = (primeiro_dia is null)),
  constraint compra_folga_so_marcada check (not valida_folga or marcada_em is not null)
);

create index if not exists agenda_medidas_compra_os   on public.agenda_medidas_compra(service_order_id);
create index if not exists agenda_medidas_compra_forn on public.agenda_medidas_compra(fornecedor_id) where valida_prazo;

comment on table public.agenda_medidas_compra is
  'Agenda de Produção (Fase 7e): uma linha por linha de material crítica que precisou de compra: quando a OS foi aprovada, quando a linha precisou, o que valeu na marcação, a compra, a chegada e o que deu para medir. Não se apaga direto: sai só com a linha de material, em cascata. Só muda inteira (versão + 1, com o histórico), fora o SET NULL do fornecedor apagado. Escrita só pelas funções da medição (P2).';
comment on column public.agenda_medidas_compra.sem_fornecedor is 'Agenda de Produção (Fase 7e, AG7-06): o prazo contado foi o padrão da empresa (prazo_sem_fornecedor_du).';
comment on column public.agenda_medidas_compra.entrega is 'nota:<id>, oc:<id> ou linha:<id> (o molde da Fase 6).';
comment on column public.agenda_medidas_compra.aprovada_em is 'A aprovação da OS (a mesma de os_prontidao: converted_to_os_at, signed_at, created_at).';
comment on column public.agenda_medidas_compra.precisou_em is 'greatest(aprovada_em, o dia em que a linha nasceu); nulo no greatest é da linha sem peça de origem, e vale a aprovação (R7.12-2).';
comment on column public.agenda_medidas_compra.marcada_em is 'O dia em que a OS ganhou o 1º compromisso com esta linha ainda por comprar.';
comment on column public.agenda_medidas_compra.primeiro_dia is 'O 1º dia marcado da OS naquele retrato.';
comment on column public.agenda_medidas_compra.compre_ate is 'O limite de compra da linha (os_material.compre_ate, 7a) naquele retrato.';
comment on column public.agenda_medidas_compra.chegada_contada is 'agenda_somar_du(primeiro_dia, −(folga_material_du + folga_compra_du)).';
comment on column public.agenda_medidas_compra.prazo_contado_du is 'Em dias úteis, o prazo de fornecedor que valeu na marcação (os_material.compre_ate_base, R7.5-6).';
comment on column public.agenda_medidas_compra.prazo_fonte is 'A fonte do prazo contado (a de os_material.compre_ate_base).';
comment on column public.agenda_medidas_compra.tempo_interno_du is 'O tempo interno de compra que valeu na marcação.';
comment on column public.agenda_medidas_compra.folga_compra_du is 'A folga da compra que valeu na marcação (0 enquanto o leitor não existir: R7.5-16).';
comment on column public.agenda_medidas_compra.comprado_em is 'O dia da compra (a 1ª fonte que tiver, na ordem de agenda_medir_compra).';
comment on column public.agenda_medidas_compra.comprado_fonte is 'De onde saiu comprado_em: dono, oc, pix, fornecedor, nfe, registro ou balcao.';
comment on column public.agenda_medidas_compra.chegou_em is 'os_material.chegou_em, só na mão.';
comment on column public.agenda_medidas_compra.previsao_original_em is 'os_material.previsao_original_em.';
comment on column public.agenda_medidas_compra.tempo_compra_du is 'Em dias úteis, de precisou_em a comprado_em (≥ 0): o tempo interno.';
comment on column public.agenda_medidas_compra.prazo_real_du is 'Em dias úteis, de comprado_em a chegou_em.';
comment on column public.agenda_medidas_compra.atraso_chegada_du is 'Em dias úteis, de chegada_contada a chegou_em (assinado).';
comment on column public.agenda_medidas_compra.comprou_ate_o_limite is 'comprado_em ≤ compre_ate.';
comment on column public.agenda_medidas_compra.primeiro_dia_cumprido is 'Houve meio-dia cumprido ou parcial da OS no primeiro_dia.';
comment on column public.agenda_medidas_compra.valida_tempo is 'A linha serve para medir o tempo interno.';
comment on column public.agenda_medidas_compra.valida_prazo is 'A linha serve para medir o prazo do fornecedor.';
comment on column public.agenda_medidas_compra.valida_folga is 'A linha serve para medir a folga da compra.';
comment on column public.agenda_medidas_compra.motivo is 'Por que a linha não vale: nao_critica, sem_compra, compra_antes, sem_chegada, balcao_inferido, nao_marcada, comprada_antes_de_marcar ou reaberta.';
comment on column public.agenda_medidas_compra.medida_em is 'Quando a rodada gravou esta versão.';
comment on column public.agenda_medidas_compra.versao is 'A versão; toda mudança leva versão + 1.';
comment on column public.agenda_medidas_compra.historico is '[{em, versao, antes, depois}]: o que mudou a cada nova versão (os 20 mais novos).';

-- O gatilho: a linha não muda de OS nem de material; toda mudança leva versão + 1 e uma entrada nova no histórico (o molde de _agenda_medidas_so_muda).
create or replace function public._agenda_medidas_compra_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if new.os_material_id is distinct from old.os_material_id or new.service_order_id is distinct from old.service_order_id then
    raise exception 'A medida da compra é da linha: a linha e a OS não mudam.';
  end if;
  -- O fornecedor apagado (ON DELETE SET NULL): a FK escreve de dentro do gatilho dela (depth > 1) e só tira fornecedor_id. Só esse caminho passa sem versão: o nulo escrito direto, ou junto com outra coluna, continua recusado.
  if pg_trigger_depth() > 1 and new.fornecedor_id is null and old.fornecedor_id is not null
     and (to_jsonb(new) - 'fornecedor_id') = (to_jsonb(old) - 'fornecedor_id') then
    return new;
  end if;
  if new.versao is distinct from old.versao + 1
     or jsonb_array_length(new.historico) = 0
     or new.historico = old.historico then
    raise exception 'A medida da compra só muda inteira: versão + 1 e o que mudou no histórico.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_medidas_compra_so_muda() is
  'Agenda de Produção (Fase 7e, P1): gatilho BEFORE UPDATE de agenda_medidas_compra — a linha e a OS não mudam; toda mudança leva versao + 1 e uma entrada nova no histórico (agenda_medir_compra). A única exceção é o ON DELETE SET NULL do fornecedor apagado: fornecedor_id de valor a nulo, de dentro do gatilho da FK, com o resto igual.';

drop trigger if exists agenda_medidas_compra_nao_apaga on public.agenda_medidas_compra;
create trigger agenda_medidas_compra_nao_apaga before delete on public.agenda_medidas_compra
  for each row when (pg_trigger_depth() = 0) execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_medidas_compra_so_muda on public.agenda_medidas_compra;
create trigger agenda_medidas_compra_so_muda before update on public.agenda_medidas_compra
  for each row execute function public._agenda_medidas_compra_so_muda();

alter table public.agenda_medidas_compra enable row level security;
drop policy if exists agenda_medidas_compra_leitura on public.agenda_medidas_compra;
create policy agenda_medidas_compra_leitura on public.agenda_medidas_compra
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_medidas_compra from public, anon, authenticated;
grant select on table public.agenda_medidas_compra to authenticated;
grant all on table public.agenda_medidas_compra to service_role;

-- ── 5. A lista fechada do aprendizado (o ampliador da 7a; os outros usos da Fase 6 continuam) ────────
select public._agenda_ampliar_lista('public.agenda_aprendizado', 'agenda_aprendizado_item_check', 'item',
       array['vies', 'promessa', 'folga_semana', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor']);

-- ── 6. O modo com o freio e as contas pequenas ───────────────────────────────────────────────────────
-- O modo cru (R7.6): do que está na linha, sem olhar o freio. O gravador e a saúde leem este: se o gravador visse o freio, a rodada viraria sombra, e
-- aprendizado_em_uso_coerente obriga em_uso nulo: soltar o freio recomeçaria do padrão. Nome que não é da margem = nulo. Mora aqui a única lista de itens: um
-- nome novo entra só neste CASE e os dois modos passam a conhecer.
create or replace function public._agenda_margem_modo_cru(p_item text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf public.agenda_config;
begin
  cf := public._agenda_cfg();
  return case p_item
           when 'vies'                 then cf.modo_vies
           when 'folga_semana'         then cf.modo_folga_semana
           when 'urgencia'             then cf.modo_urgencia
           when 'promessa'             then cf.modo_promessa
           when 'tempo_compra'         then cf.modo_tempo_compra
           when 'folga_compra'         then cf.modo_folga_compra
           when 'prazo_sem_fornecedor' then 'medida'
         end;
end;
$function$;

comment on function public._agenda_margem_modo_cru(text) is
  'Agenda de Produção (Fase 7e, P1; R7.6): o modo como está na linha (desligado | sombra | ligado) de vies, folga_semana, urgencia, promessa, tempo_compra e folga_compra; prazo_sem_fornecedor = medida; outro nome = nulo. Para o gravador e a saúde; quem decide usa _agenda_margem_modo. STABLE, invoker.';

-- O modo EFETIVO, molde de _agenda_local_modo (R7.6): com *gestor, só propor*, o que está ligado vale sombra (o desligado continua desligado). Promessa = sombra
-- sempre (AG7-32, R7.6), em qualquer modo e com ou sem freio: nenhum leitor pode achar que ela está ligada. Só a promessa é checada antes de ler o cru: é a única
-- que não olha a linha.
create or replace function public._agenda_margem_modo(p_item text)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_modo text;
begin
  if p_item = 'promessa' then
    return 'sombra';
  end if;
  v_modo := public._agenda_margem_modo_cru(p_item);
  if v_modo = 'ligado' and (public._agenda_cfg()).gestor_so_propor then
    return 'sombra';
  end if;
  return v_modo;
end;
$function$;

comment on function public._agenda_margem_modo(text) is
  'Agenda de Produção (Fase 7e, P1; R7.6): o modo EFETIVO. Com *gestor, só propor* (gestor_so_propor), o que está ligado vale sombra; o desligado continua desligado. promessa = sombra sempre (AG7-32). prazo_sem_fornecedor = medida. Outro nome = nulo. Todo leitor da margem usa esta função, nunca cf.modo_x; o gravador e a saúde usam _agenda_margem_modo_cru. STABLE, invoker: tem grant, porque os leitores invoker (os_prontidao, agenda_meios_da_os, os_duracao_sugerida) rodam como quem está logado.';

-- A credibilidade (§4.5): Z = n / (n + k). Sem amostra (estat ou n nulos, n <= 0) vale o ponto de partida (R7.12-2): sem o teste explícito de nulo, o else devolveria
-- nulo em vez de p_base. Sem arredondar: quem chama arredonda.
create or replace function public._agenda_credibilidade(p_estat numeric, p_n integer, p_base numeric, p_k integer)
 returns numeric
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_estat is null or p_n is null or p_n <= 0 then p_base
              else (p_n::numeric / (p_n + p_k)) * p_estat + (p_k::numeric / (p_n + p_k)) * p_base end;
$function$;

comment on function public._agenda_credibilidade(numeric, integer, numeric, integer) is
  'Agenda de Produção (Fase 7e, P1; §4.5): Z·estat + (1 − Z)·base com Z = n / (n + k). Estatística ou n nulos, ou n <= 0 = base. Não arredonda. IMMUTABLE.';

-- O quantil da normal (§4.5), de 0,50 a 0,95 em passos de 0,05, com interpolação linear entre os pontos. Não é parâmetro do dono: os valores são da tabela da
-- normal, escritos em inteiros (décimos de milésimo; q em centésimos) para a regra de literal da agenda não confundir com um parâmetro de agenda_config.
create or replace function public._agenda_z(p_q numeric)
 returns numeric
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  c_z constant numeric[] := array[0, 1257, 2533, 3853, 5244, 6745, 8416, 10364, 12816, 16449];
  v_q numeric;
  v_i int;
  v_fr numeric;
begin
  v_q := p_q * 100;
  if p_q is null or v_q < 50 or v_q > 95 then
    raise exception '_agenda_z: o quantil precisa estar entre 0,50 e 0,95 (recebido %).', p_q using errcode = '22023';
  end if;
  v_i := floor((v_q - 50) / 5)::int + 1;
  if v_i = 10 then
    return c_z[10] / 10000;
  end if;
  v_fr := (v_q - (50 + (v_i - 1) * 5)) / 5;
  return (c_z[v_i] + v_fr * (c_z[v_i + 1] - c_z[v_i])) / 10000;
end;
$function$;

comment on function public._agenda_z(numeric) is
  'Agenda de Produção (Fase 7e, P1; §4.5): o z de um quantil da normal entre 0,50 e 0,95, pela tabela de 0,05 em 0,05 com interpolação linear. Fora do intervalo, ou nulo, = 22023. IMMUTABLE.';

-- A temporada da semana (§4.5, R2, AG7-20): o mês da quinta-feira da semana ISO de p_seg (a semana que começa em 28/12 é de dezembro) e o quanto da semana fica guardado a
-- mais. temporada_meses é a fonte única de "é temporada de barco": fora dela, a folga de barco desse mês vale 0, seja o que for que a lista de 12 diga. Empate entre barco e
-- motorhome = barco (nov e dez, com os padrões). extra 0 = fora de temporada (por e texto nulos).
create or replace function public._agenda_temporada(p_seg date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config;
  v_mes int;
  v_b   numeric;
  v_r   numeric;
  v_ex  numeric;
  v_por text;
begin
  if p_seg is null then
    return null;
  end if;
  c := public._agenda_cfg();
  v_mes := extract(month from p_seg - (extract(isodow from p_seg)::int - 1) + 3)::int;
  v_b := case when v_mes::smallint = any (c.temporada_meses) then c.folga_temporada_barco[v_mes] else 0 end;
  v_r := c.folga_temporada_rv[v_mes];
  v_ex := greatest(v_b, v_r);
  v_por := case when v_ex <= 0 then null when v_b >= v_r then 'barco' else 'motorhome' end;
  return jsonb_build_object('mes', v_mes, 'barco', v_b, 'rv', v_r, 'extra', v_ex, 'por', v_por,
                            'texto', case v_por when 'barco' then 'temporada de barco' when 'motorhome' then 'temporada de motorhome' end);
end;
$function$;

comment on function public._agenda_temporada(date) is
  'Agenda de Produção (Fase 7e, P1; §4.5, AG7-20): {mes, barco, rv, extra, por, texto} da semana ISO de p_seg (o mês é o da quinta-feira). barco só nos meses de temporada_meses, a fonte única. extra = o maior dos dois; por = barco, motorhome ou nulo (extra 0); empate = barco. p_seg nulo = nulo. STABLE, invoker.';

-- As portas (R7.6 sobre a §4.5, que dizia "sem grant"): nenhuma para anon; authenticated e service_role têm execute, no molde de _agenda_local_modo: os leitores invoker
-- (os_prontidao, agenda_meios_da_os, os_duracao_sugerida, que têm grant a authenticated) rodam como quem está logado, e o modo cru é chamado de dentro do efetivo. O gatilho, sem porta.
revoke all on function public._agenda_medidas_compra_so_muda() from public, anon, authenticated, service_role;
revoke all on function public._agenda_margem_modo(text), public._agenda_margem_modo_cru(text),
                       public._agenda_credibilidade(numeric, integer, numeric, integer), public._agenda_z(numeric), public._agenda_temporada(date)
  from public, anon;
grant execute on function public._agenda_margem_modo(text), public._agenda_margem_modo_cru(text),
                          public._agenda_credibilidade(numeric, integer, numeric, integer), public._agenda_z(numeric), public._agenda_temporada(date)
  to authenticated, service_role;
