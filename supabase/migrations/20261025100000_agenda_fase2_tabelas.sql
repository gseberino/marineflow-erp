-- Agenda de Produção, Fase 2 ("O gestor de agenda"), pacote P1: o modelo de dados e as invariantes no banco.
-- Spec: scratchpad agenda-pesquisa/spec-fase2.md (§3.1, §4). Plano: plano-final.md §3.3; revisão §12; decisões 23/10.
-- Depende da Fase 1 inteira (20261024160000..161000): agenda_config, os_planejamento, os_material e _agenda_cfg().
--
-- ═══ DDL — OK NOMEADO ═══ (5 tabelas novas, vazias; 11 colunas novas com DEFAULT; gatilhos só nas tabelas novas)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: com a Fase 2 a agenda deixa de ser só leitura. O sistema monta, publica e ajusta o plano sozinho e conta
-- tudo no fechamento com *desfaz*. Para isso ser seguro POR CONSTRUÇÃO (e não por cuidado de quem escreve o código),
-- as regras que nunca podem quebrar ficam no banco, valendo para qualquer caminho de escrita:
--   · ninguém em dois lugares no plano vigente (EXCLUDE 1) e nenhuma proposta inviável por dentro (EXCLUDE 2);
--   · o que já foi publicado não muda: cancela-se e cria-se outro, e fica o rastro; o fixado só sai com a chave;
--   · nada que já esteve em vigor é apagado; propostas, perguntas e ações nunca são apagadas;
--   · a versão do plano sobe a cada linha que entra ou sai do vigente, sob trava (pg_advisory_xact_lock);
--   · ação crítica só entra com a decisão do dono registrada (pergunta respondida, com a opção escolhida).
--
-- O QUE MUDA:
--   1. agenda_config: 10 parâmetros novos (hora do plano, presença curta, validade do desfazer, interrupções,
--      inícios tentados, atraso longo, remarcar o confirmado, sem registro, fila mínima de serviço pronto, quantas
--      vezes a mesma pergunta aparece), cada um com CHECK por nome. O DEFAULT é o único lugar do número.
--      modo_proposta e modo_vigia passam a NASCER 'sombra' (só o DEFAULT da coluna; a linha que já existe NÃO muda
--      aqui: é a migration de dado 20261025101000, com OK nomeado).
--   2. os_planejamento.adiantavel_patio_dias: quanto do serviço dá para adiantar no pátio sem o bem.
--   3. Cinco tabelas: agenda_propostas (o que o motor ou o dono calculou), agenda_perguntas (as decisões críticas e as
--      perguntas de fato), agenda_acoes (TODA escrita no plano, com desfazer), agenda_alocacoes (quem, em que OS, em
--      que meio-dia ou na presença curta de abrir/fechar) e agenda_vigia_rodadas (uma linha por tique da vigia).
--   4. agenda_periodo(dia, turno, presença) e _agenda_hoje() (o p_hoje das RPCs, visto pelos gatilhos).
--   5. Os gatilhos das invariantes (lista acima) e o que recusa ação crítica sem decisão.
--   6. Portas: RLS ligada; só leitura TO authenticated (admin/financeiro; a alocação também para o técnico ligado ao
--      próprio payee); revoke de public, anon e authenticated; escrita só pelas RPCs security definer das próximas
--      migrations da fase (e por service_role).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase2_base.sql):
--   · A policy do técnico na spec lia payees direto ("exists (select 1 from payees p where p.id = payee_id and
--     p.app_user_id = auth.uid())"). Em produção payees tem RLS só para admin/financeiro (08-politicas-rls.sql): para
--     o técnico esse exists NUNCA casaria e ele não veria nada. A policy lê por _agenda_payees_do_login() (security
--     definer, só os payees do próprio login ativo). A bancada passa a ligar a RLS de produção de payees para provar.
--   · As FKs ON DELETE SET NULL de agenda_propostas, agenda_perguntas e agenda_acoes (autor, OS, linha de material,
--     proposta) fazem um UPDATE que os gatilhos de "só estas colunas mudam" recusariam — e então apagar uma peça da
--     OS falharia. Os gatilhos aceitam a referência que vira nula (é o que o ON DELETE SET NULL faz); o registro fica.
--     Pela mesma razão agenda_perguntas.service_order_id e os_material_id são ON DELETE SET NULL (a spec dizia
--     CASCADE, que esbarraria no "o registro da agenda não se apaga" e travaria tirar a peça da OS).
--   · Os gatilhos de alocação não recusam turno, presença ou pessoa que não existe: deixam o CHECK ou a FK dizer o
--     nome do que está errado (com turno inválido o período fica vazio só para o CHECK responder). A pessoa inativa
--     só é recusada ao nascer e ao entrar em vigor: cancelar o meio-dia de quem saiu da equipe tem de continuar
--     possível.
--   · fixado_tem_motivo: a spec pedia (estado = 'fixada') = (fixado_por is not null), o que obrigaria a apagar o
--     "fixado por quem" ao cancelar um fixado (com a chave) e perderia o rastro. Fixada exige o motivo; proposta e
--     publicada não têm; a cancelada guarda o que tinha.
--   · agenda_propostas: além do estado/decidida_*/motivo_fim, itens pode mudar no MESMO update que aplica a proposta
--     (a aplicação parcial marca itens[].aplicado, spec d24). Proposta fechada não muda mais nada.
--   · agenda_perguntas: o estado só sai de 'aberta' (nunca volta) e a pergunta fechada não muda mais (a decisão
--     registrada é fato); a recomendação e a opção escolhida têm de ser uma das opções da pergunta.
--   · agenda_acoes: o desfazer é uma vez só (desfeita_* não muda depois de preenchido).
--   · hora_do_plano ganhou CHECK (08:00 a 17:00): publicar depois das 17:00 cairia depois do fechamento das 17:30
--     só por acaso. agenda_vigia_rodadas ganhou CHECK nos modos, erros e duração.
--
-- O QUE NÃO MUDA: nenhuma tabela existente além das 11 colunas com DEFAULT; nenhum gatilho em tabela existente;
-- nenhuma função da Fase 0/1; nenhum cron. Nenhuma tela nem função de borda lê estas tabelas ainda.
--
-- ORDEM DE LIGAR: depois da Fase 1 inteira aplicada (fila-do-dono/fase1-oks.md); antes de 20261025100100 (a porta de
-- status e o gatilho das datas, que escrevem em agenda_acoes e leem agenda_alocacoes). Aplicar sozinha não muda nada
-- para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase2_base.sql (begin/rollback; cada CHECK recusa uma linha
-- errada, as 2 EXCLUDE, os gatilhos, RLS, anon sem privilégio). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261025100000
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261025100000_agenda_fase2_tabelas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261025100000', 'agenda_fase2_tabelas');"
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$, create table/index if not exists,
-- create or replace function, drop trigger/policy if exists + create.

-- A EXCLUDE com uuid e intervalo precisa da classe de operador do btree_gist (produção: 1.7, em extensions).
create extension if not exists btree_gist with schema extensions;

-- ── 1. Parâmetros novos ─────────────────────────────────────────────────────────────────────────────────
alter table public.agenda_config
  add column if not exists hora_do_plano          time          not null default '16:30',
  add column if not exists presenca_curta         interval      not null default '1 hour',
  add column if not exists desfazer_validade      interval      not null default '24 hours',
  add column if not exists interrupcoes_max       smallint      not null default 1,
  add column if not exists inicios_tentados_du    smallint      not null default 10,
  add column if not exists atraso_longo_dias      smallint      not null default 7,
  add column if not exists remarcar_confirmado_du smallint      not null default 2,
  add column if not exists sem_registro_du        smallint      not null default 2,
  add column if not exists backlog_minimo_semanas numeric(3,1)  not null default 1.0,
  add column if not exists perguntas_vezes_max    smallint      not null default 2;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_hora_do_plano_check',          'check (hora_do_plano between time ''08:00'' and time ''17:00'')'),
      ('agenda_config_presenca_curta_check',         'check (presenca_curta between interval ''30 minutes'' and interval ''2 hours'')'),
      ('agenda_config_desfazer_validade_check',      'check (desfazer_validade between interval ''1 hour'' and interval ''72 hours'')'),
      ('agenda_config_interrupcoes_max_check',       'check (interrupcoes_max between 0 and 2)'),
      ('agenda_config_inicios_tentados_du_check',    'check (inicios_tentados_du between 3 and 20)'),
      ('agenda_config_atraso_longo_dias_check',      'check (atraso_longo_dias between 3 and 30)'),
      ('agenda_config_remarcar_confirmado_du_check', 'check (remarcar_confirmado_du between 1 and 5)'),
      ('agenda_config_sem_registro_du_check',        'check (sem_registro_du between 1 and 5)'),
      ('agenda_config_backlog_minimo_semanas_check', 'check (backlog_minimo_semanas between 0.5 and 4)'),
      ('agenda_config_perguntas_vezes_max_check',    'check (perguntas_vezes_max between 1 and 5)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

alter table public.agenda_config
  alter column modo_proposta set default 'sombra',
  alter column modo_vigia    set default 'sombra';

comment on column public.agenda_config.modo_proposta is
  'desligado = o motor não roda; sombra (nasce) = calcula e grava a proposta e o que faria, sem publicar nem mudar nada; ligado = publica na quinta, replaneja por evento, escreve o espelho scheduled_* e liga o gatilho das datas; R1 e R16 deixam de criar tarefa.';
comment on column public.agenda_config.modo_vigia is
  'desligado = sem perguntas nem acorde da agenda; sombra (nasce) = as perguntas são gravadas e não aparecem; ligado = aparecem no fechamento e no acorde, a R2 deixa de criar tarefa e o secretário lê o plano em os_parada/os_esperando_compra.';
comment on column public.agenda_config.versao_plano is
  'Contador do plano publicado: sobe 1 a cada alocação que entra ou sai do vigente (publicada/fixada), sob pg_advisory_xact_lock(hashtext(''agenda_plano'')). A proposta guarda a versão em que foi calculada (versao_base).';
comment on column public.agenda_config.hora_do_plano is 'No dia_do_plano, a vigia publica a semana seguinte no 1º tique depois desta hora (o fechamento das 17:30 conta o que foi publicado).';
comment on column public.agenda_config.presenca_curta is 'Abrir e fechar do dono: a 1ª (abertura) ou a última (fechamento) parte do turno com esta duração. Não ocupa o turno inteiro dele.';
comment on column public.agenda_config.desfazer_validade is 'Por quanto tempo uma mudança feita sozinha pode ser desfeita (*desfaz*), se o meio-dia ainda não começou.';
comment on column public.agenda_config.interrupcoes_max is 'Quantos dias úteis inteiros sem a OS cabem depois de ela começar (multi-dia com no máximo 1 interrupção).';
comment on column public.agenda_config.inicios_tentados_du is 'Quantos dias de início o encaixe tenta para cada OS.';
comment on column public.agenda_config.atraso_longo_dias is 'Dias corridos de atraso do fim publicado a partir dos quais o replano é crítico (pergunta antes e recomenda ligar para o cliente).';
comment on column public.agenda_config.remarcar_confirmado_du is 'Remarcar o que o cliente já confirmou para mais do que estes dias úteis depois é crítico.';
comment on column public.agenda_config.sem_registro_du is 'Dias úteis depois do meio-dia sem resultado para ele virar sem_registro.';
comment on column public.agenda_config.backlog_minimo_semanas is 'Serviço pronto na fila abaixo disto (em semanas de capacidade) vira uma linha na quinta.';
comment on column public.agenda_config.perguntas_vezes_max is 'Em quantos fechamentos a mesma pergunta aparece antes de sair da vista (continua em agenda_ver).';

-- ── 2. Adiantável no pátio ──────────────────────────────────────────────────────────────────────────────
alter table public.os_planejamento add column if not exists adiantavel_patio_dias numeric(3,1);

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.os_planejamento'::regclass and conname = 'adiantavel_coerente') then
    alter table public.os_planejamento add constraint adiantavel_coerente
      check (adiantavel_patio_dias is null
             or (adiantavel_patio_dias > 0 and adiantavel_patio_dias * 2 = trunc(adiantavel_patio_dias * 2)
                 and (dias is null or adiantavel_patio_dias <= dias)));
  end if;
end
$$;

comment on column public.os_planejamento.adiantavel_patio_dias is
  'Quanto do serviço dá para adiantar no pátio sem o bem (bancada: barramento, chicote), em meio dia. Vira reserva nomeada quando o bem está fora.';

-- ── 3. As cinco tabelas ─────────────────────────────────────────────────────────────────────────────────

-- (1) Propostas: o que o motor (ou o dono pela conversa) calculou. NUNCA apagadas.
create table if not exists public.agenda_propostas (
  id           uuid primary key default gen_random_uuid(),
  escopo       text not null check (escopo in ('semana','os','replano')),
  periodo      daterange not null check (not isempty(periodo)),
  os_alvo      uuid[] not null default '{}',
  versao_base  bigint not null,
  modo         text not null check (modo in ('sombra','ligado')),
  estado       text not null default 'aberta' check (estado in ('aberta','aplicada','expirada','obsoleta','descartada')),
  itens        jsonb not null default '[]' check (jsonb_typeof(itens) = 'array'),
  fora         jsonb not null default '[]' check (jsonb_typeof(fora) = 'array'),
  carga        jsonb not null default '{}' check (jsonb_typeof(carga) = 'object'),
  textos       jsonb not null default '{}' check (jsonb_typeof(textos) = 'object'),
  parametros   jsonb not null check (jsonb_typeof(parametros) = 'object' and parametros ? 'p_hoje'),
  pontuacao    jsonb,
  criada_por   text not null check (criada_por in ('motor','vigia','dono','assistente','tela','aprovacao')),
  autor        uuid references public.app_users(id) on delete set null,
  criada_em    timestamptz not null default now(),
  expira_em    timestamptz not null,
  decidida_em  timestamptz,
  decidida_via text check (decidida_via in ('motor','whatsapp','painel','tela','aprovacao')),
  decidida_por uuid references public.app_users(id) on delete set null,
  motivo_fim   text check (char_length(motivo_fim) <= 200),
  constraint expira_depois     check (expira_em > criada_em),
  constraint decidida_coerente check ((estado in ('aplicada','descartada')) = (decidida_em is not null))
);

create unique index if not exists agenda_propostas_semana_aberta on public.agenda_propostas(modo)
  where estado = 'aberta' and escopo = 'semana';
create index if not exists agenda_propostas_abertas on public.agenda_propostas(estado, expira_em) where estado = 'aberta';

comment on table public.agenda_propostas is
  'Agenda de Produção (Fase 2): o que o motor (ou o dono pela conversa) calculou, com a entrada reprodutível (parametros, com p_hoje), a versão do plano em que foi calculada, o diff (itens), as OS de fora com quem trava, a carga por pessoa e as frases prontas. Uma proposta da semana aberta por modo. NUNCA apagada; fechada não muda mais.';
comment on column public.agenda_propostas.versao_base is 'agenda_config.versao_plano lida sob a trava do plano quando a proposta foi calculada. Aplicar com a versão mudada = obsoleta.';
comment on column public.agenda_propostas.expira_em is 'least(criada_em + proposta_validade, início do 1º item).';
comment on column public.agenda_propostas.itens is 'O diff: [{os, criar:[…], cancelar:[…], aplicado?}]. A aplicação parcial marca itens[].aplicado no mesmo update que fecha a proposta.';

-- (2) Perguntas ao dono: as críticas (decisões) e as de fato (conferência, chegou?, parada?, o que falta?).
-- NUNCA apagadas; fechada não muda mais.
create table if not exists public.agenda_perguntas (
  id                 uuid primary key default gen_random_uuid(),
  tipo               text not null check (tipo in (
                       'nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono',
                       'conferencia','chegou','parada','estouro','duracao','material_conferir','padrao_do_dono')),
  critica            boolean generated always as
                       (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono')) stored,
  chave              text not null check (char_length(chave) between 3 and 200),
  service_order_id   uuid references public.service_orders(id) on delete set null,
  os_ids             uuid[] not null default '{}',
  os_material_id     uuid references public.os_material(id) on delete set null,
  dia                date,
  perda_em           date,
  texto              text not null check (char_length(texto) between 3 and 600),
  opcoes             jsonb not null default '[]' check (jsonb_typeof(opcoes) = 'array'),
  recomendacao       smallint,
  recomendacao_texto text check (char_length(recomendacao_texto) <= 300),
  proposta_id        uuid references public.agenda_propostas(id) on delete set null,
  versao_base        bigint,
  modo               text not null check (modo in ('sombra','ligado')),
  estado             text not null default 'aberta' check (estado in ('aberta','respondida','resolvida','vencida','descartada')),
  mostrada_vezes     smallint not null default 0 check (mostrada_vezes between 0 and 50),
  mostrada_em        timestamptz,
  mostrada_via       text check (mostrada_via in ('fechamento','acorde','conversa')),
  respondida_em      timestamptz,
  respondida_por     uuid references public.app_users(id) on delete set null,
  respondida_via     text check (respondida_via in ('whatsapp','painel','tela')),
  opcao_escolhida    smallint,
  resposta           text check (char_length(resposta) <= 500),
  resolvida_motivo   text check (char_length(resolvida_motivo) <= 200),
  criada_em          timestamptz not null default now(),
  expira_em          timestamptz,
  constraint critica_tem_opcoes  check (not critica or (jsonb_array_length(opcoes) >= 2 and recomendacao is not null)),
  constraint respondida_coerente check ((estado = 'respondida') = (respondida_em is not null)),
  constraint critica_decidida    check (not (critica and estado = 'respondida') or opcao_escolhida is not null),
  constraint conferencia_tem_dia check (tipo <> 'conferencia' or dia is not null)
);

create unique index if not exists agenda_perguntas_viva on public.agenda_perguntas(chave, modo) where estado = 'aberta';
create index if not exists agenda_perguntas_abertas on public.agenda_perguntas(modo, estado, perda_em) where estado = 'aberta';

comment on table public.agenda_perguntas is
  'Agenda de Produção (Fase 2): a fila do que só o dono responde. As críticas (nao_cabe, segundo_atraso, atraso_longo, remarcar_confirmado, fixada_pelo_dono) têm 2+ opções e uma recomendação, e nada do que elas seguram é executado sem a resposta (opcao_escolhida). As de fato: conferencia (o dia), chegou, parada, estouro, duracao, material_conferir, padrao_do_dono. Uma aberta por chave e modo. NUNCA apagada; fechada não muda mais.';
comment on column public.agenda_perguntas.chave is 'chegou:<os_material>:<previsao_ate>, conferencia:<dia>, nao_cabe:<os>:<versao>… — a mesma pergunta não abre duas vezes.';
comment on column public.agenda_perguntas.perda_em is 'O dia em que algo se perde sem resposta: ordena o fechamento e o acorde.';
comment on column public.agenda_perguntas.opcoes is '[{n, texto, os, efeito:{restricoes}}]. A recomendação e a opção escolhida são um dos n.';
comment on column public.agenda_perguntas.resposta is 'As palavras do dono.';
comment on column public.agenda_perguntas.resolvida_motivo is 'O fato que respondeu sozinho (a peça chegou, a OS saiu da carteira).';

-- (3) Ações: TODA escrita no plano (do motor, da vigia, do dono, da tela), com desfazer. NUNCA apagadas.
create table if not exists public.agenda_acoes (
  id                   uuid primary key default gen_random_uuid(),
  criada_em            timestamptz not null default now(),
  dia                  date not null,
  executada            boolean not null,
  origem               text not null check (origem in ('motor','vigia','conferencia','dono','assistente','tela','aprovacao','sistema')),
  tipo                 text not null check (tipo in ('publicar','criar','mover','cancelar','fixar','promover_reserva',
                                                       'soltar_reserva','status','resultado','desfazer')),
  service_order_id     uuid references public.service_orders(id) on delete set null,
  os_ids               uuid[] not null default '{}',
  proposta_id          uuid references public.agenda_propostas(id) on delete set null,
  pergunta_id          uuid references public.agenda_perguntas(id) on delete restrict,
  critica              boolean not null default false,
  versao_antes         bigint,
  versao_depois        bigint,
  alocacoes_criadas    uuid[] not null default '{}',
  alocacoes_canceladas uuid[] not null default '{}',
  status_antes         text,
  status_depois        text,
  atraso_du            smallint,
  antes                jsonb not null default '{}' check (jsonb_typeof(antes) = 'object'),
  depois               jsonb not null default '{}' check (jsonb_typeof(depois) = 'object'),
  texto                text not null check (char_length(texto) between 3 and 400),
  motivo               text check (char_length(motivo) <= 200),
  autor                uuid references public.app_users(id) on delete set null,
  desfazivel_ate       timestamptz,
  desfeita_em          timestamptz,
  desfeita_por         uuid references public.app_users(id) on delete set null,
  desfeita_pela        uuid references public.agenda_acoes(id) on delete restrict,
  desfaz_a             uuid references public.agenda_acoes(id) on delete restrict,
  contada_em           timestamptz,
  contada_via          text check (contada_via in ('fechamento','acorde','conversa')),
  constraint critica_tem_pergunta check (not critica or pergunta_id is not null),
  constraint desfazer_aponta      check ((tipo = 'desfazer') = (desfaz_a is not null)),
  constraint desfeita_coerente    check ((desfeita_em is null) = (desfeita_pela is null)),
  constraint sombra_nao_desfaz    check (executada or (desfazivel_ate is null and desfeita_em is null))
);

create index if not exists agenda_acoes_os  on public.agenda_acoes(service_order_id, criada_em desc);
create index if not exists agenda_acoes_dia on public.agenda_acoes(dia, executada);

comment on table public.agenda_acoes is
  'Agenda de Produção (Fase 2): toda escrita no plano e todo status mudado pela porta, de quem quer que seja (motor, vigia, conferência, dono, assistente, tela, aprovação), com antes/depois, a frase ao dono e o desfazer. executada false = sombra (o que o motor faria). critica true só com a pergunta respondida (gatilho). NUNCA apagada; só desfeita_* (uma vez) e contada_* mudam.';
comment on column public.agenda_acoes.dia is 'O p_hoje de quem agiu.';
comment on column public.agenda_acoes.pergunta_id is 'A decisão do dono que autorizou a ação crítica.';
comment on column public.agenda_acoes.atraso_du is 'Quanto o fim da OS andou, em dias úteis (mover, replano).';
comment on column public.agenda_acoes.texto is 'A frase ao dono (fechamento, acorde, conversa).';

-- (4) Alocação: quem, em que OS, em que meio-dia (ou na presença curta de abrir/fechar).
create table if not exists public.agenda_alocacoes (
  id               uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  payee_id         uuid not null references public.payees(id),
  dia              date not null,
  turno            text not null check (turno in ('manha','tarde')),
  presenca         text not null default 'turno' check (presenca in ('turno','abertura','fechamento')),
  periodo          tstzrange not null,
  tipo             text not null default 'execucao' check (tipo in ('execucao','diagnostico','comissionamento','entrega','reserva')),
  estado           text not null check (estado in ('proposta','publicada','fixada','cancelada')),
  origem           text not null default 'motor' check (origem in ('motor','dono','cliente')),
  proposta_id      uuid references public.agenda_propostas(id) on delete set null,
  acao_id          uuid references public.agenda_acoes(id) on delete set null,
  substitui_id     uuid references public.agenda_alocacoes(id) on delete set null,
  fixado_por       text check (fixado_por in ('cliente_confirmou','em_execucao','dono','congelamento')),
  reserva_de       text check (reserva_de in ('teto','condicionada','patio')),
  condicao         text check (char_length(condicao) <= 160),
  condicao_tipo    text check (condicao_tipo in ('compra','material','conferir_material','duracao')),
  condicao_ate     date,
  resultado        text check (resultado in ('cumprido','parcial','nao_cumprido','sem_registro')),
  motivo           text check (motivo in ('material','cliente_ou_bem','equipe_faltou','trabalho_anterior','informacao','clima',
                                          'estimativa','imprevisto_tecnico','urgencia_outra_os','esqueci','concluida_antes')),
  resultado_em     timestamptz,
  resultado_via    text check (resultado_via in ('dia_feito','conversa','tela','sistema')),
  resultado_por    uuid references public.app_users(id) on delete set null,
  resultado_trecho text check (char_length(resultado_trecho) <= 300),
  publicada_em     timestamptz,
  cancelada_em     timestamptz,
  cancelada_motivo text check (cancelada_motivo in ('replanejado','desfeito','os_saiu','pessoa','material','cliente','clima',
                                                    'condicao_vencida','promovida','dono')),
  motivos          jsonb not null default '[]' check (jsonb_typeof(motivos) = 'array'),
  historico        jsonb not null default '[]'
                     check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint proposta_tem_origem  check (estado <> 'proposta' or proposta_id is not null),
  -- Fixada diz por quê; proposta e publicada não têm motivo de fixado; a cancelada guarda o que tinha (o rastro).
  constraint fixado_tem_motivo    check (case estado when 'fixada' then fixado_por is not null
                                                     when 'cancelada' then true
                                                     else fixado_por is null end),
  constraint resultado_so_vigente check (resultado is null or estado in ('publicada','fixada')),
  constraint falha_tem_motivo     check (resultado is null or resultado not in ('parcial','nao_cumprido') or motivo is not null),
  constraint condicao_completa    check ((condicao is null) = (condicao_tipo is null) and (condicao_tipo is null) = (condicao_ate is null)),
  constraint condicao_so_reserva  check (condicao is null or tipo = 'reserva'),
  constraint reserva_tem_razao    check ((tipo = 'reserva') = (reserva_de is not null)),
  constraint curta_nao_e_reserva  check (presenca = 'turno' or tipo <> 'reserva'),
  constraint cancelada_coerente   check ((estado = 'cancelada') = (cancelada_em is not null)),
  constraint vigente_tem_data     check (estado not in ('publicada','fixada') or publicada_em is not null),
  -- INVARIANTE 1: ninguém em dois lugares no plano vigente.
  constraint sem_choque_vigente     exclude using gist (payee_id with =, periodo with &&) where (estado in ('publicada','fixada')),
  -- INVARIANTE 2: cada proposta é viável por dentro.
  constraint sem_choque_na_proposta exclude using gist (proposta_id with =, payee_id with =, periodo with &&) where (estado = 'proposta')
);

create index if not exists agenda_alocacoes_os   on public.agenda_alocacoes(service_order_id, dia) where estado in ('publicada','fixada');
create index if not exists agenda_alocacoes_dia  on public.agenda_alocacoes(dia) where estado in ('publicada','fixada');
create index if not exists agenda_alocacoes_prop on public.agenda_alocacoes(proposta_id) where estado = 'proposta';

comment on table public.agenda_alocacoes is
  'Agenda de Produção (Fase 2): quem (payee), em que OS, em que meio-dia (turno) ou na presença curta do dono (abertura/fechamento). periodo vem de agenda_periodo pelo gatilho. Vigente = publicada ou fixada: ninguém em dois lugares (EXCLUDE), não muda (cancela-se e cria-se outra), não se apaga. Reserva = lugar guardado (teto, condicionada a material/compra/duração, pátio), nunca o compromisso. resultado (cumprido, parcial, nao_cumprido, sem_registro) com o motivo da falha (LCI).';
comment on column public.agenda_alocacoes.periodo is 'Calculado pelo gatilho: agenda_periodo(dia, turno, presenca). Não se escreve à mão.';
comment on column public.agenda_alocacoes.publicada_em is 'A 1ª vez que entrou em vigor; nunca volta a nulo. Alocação que já vigorou não se apaga.';
comment on column public.agenda_alocacoes.condicao is 'A condição da reserva em palavras ("se o material da Premel estiver na mão"), com o tipo e a data-limite (condicao_ate).';
comment on column public.agenda_alocacoes.historico is 'As correções do resultado ({em, de, para, via}), até 20.';

-- (5) Rodadas da vigia: uma linha por tique (agenda_saude lê; a vigia apaga as de mais de 60 dias).
create table if not exists public.agenda_vigia_rodadas (
  id            uuid primary key default gen_random_uuid(),
  rodou_em      timestamptz not null default now(),
  p_hoje        date not null,
  p_agora       timestamptz not null,
  modo_proposta text not null check (modo_proposta in ('desligado','sombra','ligado')),
  modo_vigia    text not null check (modo_vigia in ('desligado','sombra','ligado')),
  contagens     jsonb not null default '{}' check (jsonb_typeof(contagens) = 'object'),
  erros         smallint not null default 0 check (erros >= 0),
  duracao_ms    integer check (duracao_ms >= 0)
);

create index if not exists agenda_vigia_rodadas_quando on public.agenda_vigia_rodadas(rodou_em desc);

comment on table public.agenda_vigia_rodadas is
  'Agenda de Produção (Fase 2): uma linha por tique da vigia (os modos naquele instante, as contagens, os erros). agenda_saude lê; a própria vigia apaga as de mais de 60 dias.';

-- ── 4. Funções da base ──────────────────────────────────────────────────────────────────────────────────

-- O intervalo de tempo de um meio-dia (ou da presença curta), no fuso de Brasília.
create or replace function public.agenda_periodo(p_dia date, p_turno text, p_presenca text default 'turno')
 returns tstzrange
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c     public.agenda_config := public._agenda_cfg();
  v_de  timestamptz;
  v_ate timestamptz;
begin
  if p_dia is null then
    raise exception 'Falta o dia do meio-dia.' using errcode = '22023';
  end if;
  if p_turno = 'manha' then
    v_de  := (p_dia + c.manha_inicio) at time zone 'America/Sao_Paulo';
    v_ate := (p_dia + c.manha_fim)    at time zone 'America/Sao_Paulo';
  elsif p_turno = 'tarde' then
    v_de  := (p_dia + c.tarde_inicio) at time zone 'America/Sao_Paulo';
    v_ate := (p_dia + c.tarde_fim)    at time zone 'America/Sao_Paulo';
  else
    raise exception 'Turno desconhecido: "%" (manha ou tarde).', coalesce(p_turno, '') using errcode = '22023';
  end if;
  if coalesce(p_presenca, 'turno') = 'turno' then
    return tstzrange(v_de, v_ate, '[)');
  elsif p_presenca = 'abertura' then
    return tstzrange(v_de, least(v_de + c.presenca_curta, v_ate), '[)');
  elsif p_presenca = 'fechamento' then
    return tstzrange(greatest(v_ate - c.presenca_curta, v_de), v_ate, '[)');
  end if;
  raise exception 'Presença desconhecida: "%" (turno, abertura ou fechamento).', p_presenca using errcode = '22023';
end;
$function$;

comment on function public.agenda_periodo(date, text, text) is
  'Agenda de Produção (Fase 2): o intervalo [início, fim) do meio-dia em Brasília — turno manha/tarde pelos horários de agenda_config; abertura = a 1ª presenca_curta do turno; fechamento = a última. Turno ou presença fora da lista lança 22023.';

-- O dia de quem está agindo: o p_hoje que a RPC do motor passou (set_config('agenda.hoje', …, true)), senão o de
-- Brasília. Os gatilhos conferem "o dia já chegou?" com o mesmo dia dos testes.
create or replace function public._agenda_hoje()
 returns date
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(nullif(current_setting('agenda.hoje', true), '')::date, public._hoje_brt());
$function$;

comment on function public._agenda_hoje() is
  'Agenda de Produção (Fase 2): o p_hoje da RPC que está agindo (agenda.hoje, local à transação), senão o dia de Brasília.';

-- Os payees do login (o técnico ligado ao próprio cadastro). security definer porque payees é fechada para o
-- técnico (só admin/financeiro leem): a policy de agenda_alocacoes precisa desta resposta, e só dela.
create or replace function public._agenda_payees_do_login()
 returns uuid[]
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select coalesce(array_agg(p.id order by p.id), '{}'::uuid[])
    from public.payees p
    join public.app_users u on u.id = p.app_user_id
   where p.app_user_id = auth.uid() and u.active and p.active;
$function$;

comment on function public._agenda_payees_do_login() is
  'Agenda de Produção (Fase 2): os payees ativos ligados ao login ativo (auth.uid()). Só para a policy de leitura de agenda_alocacoes: payees tem RLS só para admin/financeiro, e um exists direto nunca casaria para o técnico.';

-- ── 5. Gatilhos das invariantes ─────────────────────────────────────────────────────────────────────────

-- 5a. Alocação, antes de gravar: o período, as datas de vigor e de cancelamento, a pessoa, a presença curta e o
-- "esse dia já chegou?".
create or replace function public._agenda_alocacoes_antes()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_kind   text;
  v_ativo  boolean;
  v_entra  boolean := new.estado in ('publicada', 'fixada')
                      and (tg_op = 'INSERT' or old.estado not in ('publicada', 'fixada'));
begin
  -- Período: só do dia, turno e presença (nunca à mão). Na mudança de outra coisa, fica o que estava: a
  -- alocação publicada não muda de hora porque alguém mexeu nos horários de agenda_config depois.
  if tg_op = 'INSERT' or new.dia is distinct from old.dia or new.turno is distinct from old.turno
     or new.presenca is distinct from old.presenca then
    if new.dia is not null and new.turno in ('manha', 'tarde') and new.presenca in ('turno', 'abertura', 'fechamento') then
      new.periodo := public.agenda_periodo(new.dia, new.turno, new.presenca);
    else
      new.periodo := 'empty';   -- turno ou presença fora da lista: o CHECK da coluna diz qual
    end if;
  else
    new.periodo := old.periodo;
  end if;

  if tg_op = 'UPDATE' then
    new.criado_em    := old.criado_em;
    -- Entrou em vigor ou foi cancelada uma vez: a data fica.
    new.publicada_em := coalesce(old.publicada_em, new.publicada_em);
    new.cancelada_em := coalesce(old.cancelada_em, new.cancelada_em);
  end if;
  new.atualizado_em := now();

  -- A pessoa: ativa ao nascer e ao entrar em vigor (cancelar o meio-dia de quem saiu continua possível). Pessoa que
  -- não existe passa daqui e a FK recusa.
  if tg_op = 'INSERT' or v_entra or new.payee_id is distinct from old.payee_id
     or new.presenca is distinct from old.presenca then
    select p.kind, p.active into v_kind, v_ativo from public.payees p where p.id = new.payee_id;
    if found and not v_ativo and (tg_op = 'INSERT' or v_entra or new.payee_id is distinct from old.payee_id) then
      raise exception 'Essa pessoa não está ativa: não entra na agenda.';
    end if;
    if found and new.presenca in ('abertura', 'fechamento') and v_kind <> 'socio' then
      raise exception 'Abrir e fechar (presença curta) é só do sócio; a equipe ocupa o turno inteiro.';
    end if;
  end if;

  if new.estado in ('publicada', 'fixada') then
    new.publicada_em := coalesce(new.publicada_em, now());
  end if;
  if new.estado = 'cancelada' then
    new.cancelada_em := coalesce(new.cancelada_em, now());
  end if;

  -- O resultado é do dia que já chegou (o dia de quem está agindo).
  if new.resultado is not null and (tg_op = 'INSERT' or new.resultado is distinct from old.resultado) then
    if new.dia > public._agenda_hoje() then
      raise exception 'Esse dia ainda não chegou: não dá para dizer como foi.';
    end if;
  end if;
  -- A hora do resultado, quando quem escreve não disse (o case vai entre parênteses: no IF do PL/pgSQL, o 1º "then"
  -- fora de parênteses encerra a condição).
  if (new.resultado is distinct from (case when tg_op = 'UPDATE' then old.resultado end))
     and ((tg_op = 'INSERT' and new.resultado_em is null)
          or (tg_op = 'UPDATE' and new.resultado_em is not distinct from old.resultado_em)) then
    new.resultado_em := case when new.resultado is null then null else now() end;
  end if;

  return new;
end;
$function$;

-- 5b. Alocação publicada ou fixada não muda: cancela-se e cria-se outra (fica o rastro). As transições de estado e
-- a correção do resultado (que entra no histórico).
create or replace function public._agenda_alocacoes_imutavel()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_h jsonb;
  v_mudou_o_que boolean :=
    (new.service_order_id, new.payee_id, new.dia, new.turno, new.presenca, new.tipo, new.origem,
     new.condicao, new.condicao_tipo, new.condicao_ate)
    is distinct from
    (old.service_order_id, old.payee_id, old.dia, old.turno, old.presenca, old.tipo, old.origem,
     old.condicao, old.condicao_tipo, old.condicao_ate);
begin
  if old.estado = 'cancelada' and (v_mudou_o_que or new.estado is distinct from old.estado) then
    raise exception 'Alocação cancelada não volta nem muda: crie outra.';
  end if;
  if old.estado in ('publicada', 'fixada') and v_mudou_o_que then
    raise exception 'Alocação publicada não muda: cancele e crie outra (fica o rastro).';
  end if;

  if new.estado is distinct from old.estado then
    if old.estado = 'fixada' and new.estado = 'cancelada'
       and coalesce(current_setting('agenda.mexe_fixado', true), '') <> 'on' then
      raise exception 'Esse meio-dia está fixado: só sai com a decisão de mexer no fixado.';
    end if;
    if not ((old.estado = 'proposta' and new.estado in ('publicada', 'fixada', 'cancelada'))
            or (old.estado = 'publicada' and new.estado in ('fixada', 'cancelada'))
            or (old.estado = 'fixada' and new.estado = 'cancelada')) then
      raise exception 'Essa troca de estado não existe: % → %.', old.estado, new.estado;
    end if;
    if new.estado = 'cancelada' and coalesce(old.resultado, new.resultado) is not null then
      raise exception 'Esse meio-dia já aconteceu: corrija o resultado, não cancele.';
    end if;
  end if;

  -- Corrigir o resultado é permitido e fica no histórico (os 20 mais novos).
  if old.resultado is not null and new.resultado is distinct from old.resultado then
    v_h := old.historico || jsonb_build_array(jsonb_build_object(
             'em', now(), 'de', old.resultado, 'para', new.resultado, 'via', new.resultado_via));
    if jsonb_array_length(v_h) > 20 then
      select jsonb_agg(e order by o) into v_h
        from jsonb_array_elements(v_h) with ordinality t(e, o)
       where o > jsonb_array_length(v_h) - 20;
    end if;
    new.historico := v_h;
  end if;

  return new;
end;
$function$;

-- 5c. O que já esteve no plano não se apaga. Só a alocação de proposta que nunca vigorou.
create or replace function public._agenda_alocacoes_nao_apaga()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if old.publicada_em is not null or old.resultado is not null or old.estado in ('publicada', 'fixada') then
    raise exception 'Esse meio-dia já esteve no plano: não se apaga (cancele, e fica o rastro).';
  end if;
  return old;
end;
$function$;

-- 5d. A versão do plano: sobe 1 a cada linha que entra ou sai do vigente, sob a trava do plano (nunca sequência).
create or replace function public._agenda_alocacoes_versao()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_antes  boolean := tg_op <> 'INSERT' and old.estado in ('publicada', 'fixada');
  v_depois boolean := tg_op <> 'DELETE' and new.estado in ('publicada', 'fixada');
begin
  if coalesce(v_antes, false) <> coalesce(v_depois, false) then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
    update public.agenda_config set versao_plano = versao_plano + 1 where id;
  end if;
  return null;
end;
$function$;

-- 5e. Propostas, perguntas e ações nunca se apagam.
create or replace function public._agenda_registro_nao_apaga()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  raise exception 'O registro da agenda não se apaga.';
end;
$function$;

-- Igualdade de duas linhas fora das colunas que podem mudar; a referência que virou nula (o ON DELETE SET NULL de
-- uma FK) conta como igual.
create or replace function public._agenda_so_mudou(p_velho jsonb, p_novo jsonb, p_mudam text[], p_anulaveis text[])
 returns boolean
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_velho jsonb := p_velho - p_mudam;
  v_novo  jsonb := p_novo - p_mudam;
  k       text;
begin
  foreach k in array coalesce(p_anulaveis, '{}') loop
    if v_novo -> k = 'null'::jsonb then
      v_velho := v_velho - k;
      v_novo  := v_novo - k;
    end if;
  end loop;
  return v_velho = v_novo;
end;
$function$;

-- 5f. Proposta: só fecha (de aberta para os outros 4 estados), com decidida_* e motivo_fim; itens só no mesmo update
-- que a aplica (aplicação parcial). Fechada não muda mais.
create or replace function public._agenda_propostas_so_fecha()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_mudam text[] := '{}';
begin
  if old.estado = 'aberta' then
    v_mudam := array['estado', 'decidida_em', 'decidida_via', 'decidida_por', 'motivo_fim'];
    if new.estado = 'aplicada' then
      v_mudam := array_append(v_mudam, 'itens');
    end if;
  end if;
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new), v_mudam, array['autor', 'decidida_por']) then
    raise exception 'A proposta não muda depois de calculada: só fecha (aplicada, expirada, obsoleta ou descartada).';
  end if;
  return new;
end;
$function$;

-- 5g. Pergunta: a recomendação e a opção escolhida são uma das opções; só sai de aberta (nunca volta) com o que a
-- responde, mostra ou resolve; fechada não muda mais.
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
  end if;
  if tg_op = 'UPDATE'
     and not public._agenda_so_mudou(to_jsonb(old) - 'critica', to_jsonb(new) - 'critica',
           case when old.estado = 'aberta'
                then array['estado', 'mostrada_vezes', 'mostrada_em', 'mostrada_via', 'respondida_em', 'respondida_por',
                           'respondida_via', 'opcao_escolhida', 'resposta', 'resolvida_motivo', 'expira_em']
                else '{}'::text[] end,
           array['service_order_id', 'os_material_id', 'proposta_id', 'respondida_por']) then
    if old.estado = 'aberta' then
      raise exception 'A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.';
    end if;
    raise exception 'A pergunta fechada não muda: a decisão registrada fica como foi.';
  end if;
  return new;
end;
$function$;

-- 5h. Ação: só o desfazer (uma vez) e o "contada ao dono" mudam.
create or replace function public._agenda_acoes_so_desfaz()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           case when old.desfeita_em is null
                then array['desfeita_em', 'desfeita_por', 'desfeita_pela', 'contada_em', 'contada_via']
                else array['contada_em', 'contada_via'] end,
           array['service_order_id', 'proposta_id', 'autor', 'desfeita_por']) then
    raise exception 'A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.';
  end if;
  return new;
end;
$function$;

-- 5i. Ação crítica só com a decisão do dono: a pergunta crítica respondida, com a opção escolhida; executada só se a
-- pergunta foi feita de verdade (modo ligado). Sem pergunta nenhuma, quem recusa é o CHECK critica_tem_pergunta.
create or replace function public._agenda_acoes_critica_decidida()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  q record;
begin
  if not new.critica or new.pergunta_id is null then
    return new;
  end if;
  select p.critica, p.estado, p.opcao_escolhida, p.modo into q from public.agenda_perguntas p where p.id = new.pergunta_id;
  if not found or not q.critica or q.estado <> 'respondida' or q.opcao_escolhida is null
     or (new.executada and q.modo <> 'ligado') then
    raise exception 'Ação crítica sem decisão do dono: nada foi feito.';
  end if;
  return new;
end;
$function$;

drop trigger if exists agenda_alocacoes_antes on public.agenda_alocacoes;
create trigger agenda_alocacoes_antes before insert or update on public.agenda_alocacoes
  for each row execute function public._agenda_alocacoes_antes();
drop trigger if exists agenda_alocacoes_imutavel on public.agenda_alocacoes;
create trigger agenda_alocacoes_imutavel before update on public.agenda_alocacoes
  for each row execute function public._agenda_alocacoes_imutavel();
drop trigger if exists agenda_alocacoes_nao_apaga on public.agenda_alocacoes;
create trigger agenda_alocacoes_nao_apaga before delete on public.agenda_alocacoes
  for each row execute function public._agenda_alocacoes_nao_apaga();
drop trigger if exists agenda_alocacoes_versao on public.agenda_alocacoes;
create trigger agenda_alocacoes_versao after insert or update or delete on public.agenda_alocacoes
  for each row execute function public._agenda_alocacoes_versao();

drop trigger if exists agenda_propostas_nao_apaga on public.agenda_propostas;
create trigger agenda_propostas_nao_apaga before delete on public.agenda_propostas
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_propostas_so_fecha on public.agenda_propostas;
create trigger agenda_propostas_so_fecha before update on public.agenda_propostas
  for each row execute function public._agenda_propostas_so_fecha();

drop trigger if exists agenda_perguntas_nao_apaga on public.agenda_perguntas;
create trigger agenda_perguntas_nao_apaga before delete on public.agenda_perguntas
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_perguntas_antes on public.agenda_perguntas;
create trigger agenda_perguntas_antes before insert or update on public.agenda_perguntas
  for each row execute function public._agenda_perguntas_antes();

drop trigger if exists agenda_acoes_nao_apaga on public.agenda_acoes;
create trigger agenda_acoes_nao_apaga before delete on public.agenda_acoes
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_acoes_so_desfaz on public.agenda_acoes;
create trigger agenda_acoes_so_desfaz before update on public.agenda_acoes
  for each row execute function public._agenda_acoes_so_desfaz();
drop trigger if exists agenda_acoes_critica_decidida on public.agenda_acoes;
create trigger agenda_acoes_critica_decidida before insert on public.agenda_acoes
  for each row execute function public._agenda_acoes_critica_decidida();

comment on function public._agenda_alocacoes_antes() is 'Agenda de Produção (Fase 2): gatilho BEFORE INSERT/UPDATE de agenda_alocacoes — período por agenda_periodo, publicada_em/cancelada_em uma vez, pessoa ativa ao nascer e ao entrar em vigor, presença curta só do sócio, resultado só de dia que já chegou (_agenda_hoje).';
comment on function public._agenda_alocacoes_imutavel() is 'Agenda de Produção (Fase 2): gatilho BEFORE UPDATE — publicada/fixada não muda (cancela-se e cria-se outra); proposta → publicada|fixada|cancelada, publicada → fixada|cancelada, fixada → cancelada só com agenda.mexe_fixado = on; cancelada não volta; com resultado não se cancela; correção do resultado vai para o histórico.';
comment on function public._agenda_alocacoes_nao_apaga() is 'Agenda de Produção (Fase 2): gatilho BEFORE DELETE — recusa o que já vigorou (publicada_em), tem resultado ou está vigente.';
comment on function public._agenda_alocacoes_versao() is 'Agenda de Produção (Fase 2): gatilho AFTER, por linha — entrou ou saiu do vigente: pg_advisory_xact_lock(hashtext(''agenda_plano'')) e versao_plano + 1.';
comment on function public._agenda_registro_nao_apaga() is 'Agenda de Produção (Fase 2): gatilho BEFORE DELETE de propostas, perguntas e ações — o registro não se apaga.';
comment on function public._agenda_so_mudou(jsonb, jsonb, text[], text[]) is 'Agenda de Produção (Fase 2): as duas linhas são iguais fora das colunas que podem mudar (a referência que virou nula pelo ON DELETE SET NULL conta como igual).';
comment on function public._agenda_propostas_so_fecha() is 'Agenda de Produção (Fase 2): gatilho BEFORE UPDATE — a proposta só fecha (estado, decidida_*, motivo_fim; itens só ao aplicar); fechada não muda.';
comment on function public._agenda_perguntas_antes() is 'Agenda de Produção (Fase 2): gatilho BEFORE INSERT/UPDATE — recomendação e opção escolhida são uma das opções; a pergunta só sai de aberta, com o que a mostra/responde/resolve; fechada não muda.';
comment on function public._agenda_acoes_so_desfaz() is 'Agenda de Produção (Fase 2): gatilho BEFORE UPDATE — só desfeita_* (uma vez) e contada_* mudam.';
comment on function public._agenda_acoes_critica_decidida() is 'Agenda de Produção (Fase 2): gatilho BEFORE INSERT — ação crítica só com a pergunta crítica respondida (opcao_escolhida) e, executada, só com a pergunta feita em ligado. Senão "Ação crítica sem decisão do dono: nada foi feito."';

-- ── 6. Portas: RLS, só leitura, escrita só pelas RPCs ───────────────────────────────────────────────────
alter table public.agenda_propostas     enable row level security;
alter table public.agenda_perguntas     enable row level security;
alter table public.agenda_acoes         enable row level security;
alter table public.agenda_alocacoes     enable row level security;
alter table public.agenda_vigia_rodadas enable row level security;

drop policy if exists agenda_propostas_leitura on public.agenda_propostas;
create policy agenda_propostas_leitura on public.agenda_propostas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_perguntas_leitura on public.agenda_perguntas;
create policy agenda_perguntas_leitura on public.agenda_perguntas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_acoes_leitura on public.agenda_acoes;
create policy agenda_acoes_leitura on public.agenda_acoes
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

-- O técnico vê os meio-dias do próprio cadastro (payee ligado ao login), e só eles. O (select …)::uuid[] é um valor
-- só por consulta (initplan), não uma chamada por linha.
drop policy if exists agenda_alocacoes_leitura on public.agenda_alocacoes;
create policy agenda_alocacoes_leitura on public.agenda_alocacoes
  for select to authenticated
  using (public.is_admin_or_financial((select auth.uid()))
         or payee_id = any ((select public._agenda_payees_do_login())::uuid[]));

drop policy if exists agenda_vigia_rodadas_leitura on public.agenda_vigia_rodadas;
create policy agenda_vigia_rodadas_leitura on public.agenda_vigia_rodadas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_propostas, public.agenda_perguntas, public.agenda_acoes, public.agenda_alocacoes,
  public.agenda_vigia_rodadas from public, anon, authenticated;
grant select on table public.agenda_propostas, public.agenda_perguntas, public.agenda_acoes, public.agenda_alocacoes,
  public.agenda_vigia_rodadas to authenticated;
grant all on table public.agenda_propostas, public.agenda_perguntas, public.agenda_acoes, public.agenda_alocacoes,
  public.agenda_vigia_rodadas to service_role;

-- Funções: as de leitura para authenticated e service_role, nunca anon; as de gatilho sem grant a ninguém.
revoke all on function public.agenda_periodo(date, text, text), public._agenda_hoje(), public._agenda_payees_do_login()
  from public, anon;
grant execute on function public.agenda_periodo(date, text, text), public._agenda_hoje(), public._agenda_payees_do_login()
  to authenticated, service_role;
revoke all on function public._agenda_alocacoes_antes(), public._agenda_alocacoes_imutavel(),
  public._agenda_alocacoes_nao_apaga(), public._agenda_alocacoes_versao(), public._agenda_registro_nao_apaga(),
  public._agenda_so_mudou(jsonb, jsonb, text[], text[]), public._agenda_propostas_so_fecha(),
  public._agenda_perguntas_antes(), public._agenda_acoes_so_desfaz(), public._agenda_acoes_critica_decidida()
  from public, anon, authenticated;
