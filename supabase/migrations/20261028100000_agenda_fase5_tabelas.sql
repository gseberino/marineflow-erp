-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P1: a base — o modo e os parâmetros da mensagem ao cliente,
-- o que foi DITO ao cliente (prometido_*) e como o serviço é dito a ele, as 2 tabelas do cliente (as mensagens e as
-- respostas) e as listas fechadas ampliadas.
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§3, §4). Decisões do dono 23/10 (Autonomia: "manda ao cliente as
-- mensagens-modelo com dados do banco"; janela seg–sex 8–19 e sáb 8–13, nunca domingo; no máximo 1 por dia e 3 por semana
-- por cliente; nos 3 primeiros dias de cada tipo a mensagem passa pelo dono). Depende das Fases 1 a 4 inteiras
-- (20261024160000 .. 20261027102000).
--
-- ═══ DDL — OK NOMEADO ═══ (2 tabelas novas, vazias; 25 colunas novas em agenda_config — a lista de tipos e 24 parâmetros
-- — e o DEFAULT de modo_cliente; 9 colunas novas em os_planejamento, todas nulas; 4 listas fechadas ampliadas; a coluna
-- gerada critica com 'cliente_aviso')
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: a agenda passa a falar com o cliente, SÓ por mensagem-modelo (o texto e as datas vêm do banco; o LLM não escreve
-- nada ao cliente). Esta migration só cria o lugar de cada coisa; quem escreve são as funções das próximas migrations da fase
-- (100100 a 100600). Tudo nasce desligado e a migration de dado 20261028101000 (P6, OK nomeado) põe o modo em sombra.
--
-- O QUE MUDA:
--   1. agenda_config: modo_cliente (já existe desde a Fase 1, 20261024160000, 'desligado' e com o CHECK
--      agenda_config_modo_cliente_check; aqui só o DEFAULT da coluna vira 'sombra', como nas Fases 2 a 4, e a linha fica
--      'desligado'), cliente_tipos_ligados (as ondas: tipo fora da lista fica em teste mesmo com o modo ligado) e 24 parâmetros da janela,
--      do teto, do intervalo, da aprovação dos primeiros dias, das horas, das validades e da conversa, cada um com CHECK por
--      nome. O DEFAULT é o único lugar do número. atraso_longo_dias (7) e remarcar_confirmado_du (2) da Fase 2 são reusados.
--   2. os_planejamento: prometido_tipo/de/ate (o que foi DITO ao cliente, ≠ o plano), prometido_original_ate (a 1ª
--      promessa: a pontualidade da Fase 6), prometido_em/fonte/mensagem_id, servico_cliente (como o serviço é dito ao
--      cliente) e acesso_ok_em (quando o acesso foi dito).
--   3. agenda_cliente_mensagens (toda mensagem ao cliente: mandada, esperando o dono, em teste ou recusada) e
--      agenda_cliente_respostas (toda mensagem do cliente que a agenda leu). Nenhuma se apaga; só as colunas de estado
--      mudam (gatilhos).
--   4. Listas fechadas: agenda_perguntas.tipo + cliente_aprovar, cliente_aviso (CRÍTICA: a coluna gerada critica ganha o
--      tipo), cliente_resposta; agenda_acoes.tipo + cliente; agenda_acoes.origem + cliente; agenda_vigia_rodadas.rotina +
--      cliente. agenda_rascunho.tipo NÃO muda (o prometido entra no tipo planejar, P5).
--   5. Portas: RLS ligada nas 2 tabelas; só leitura TO authenticated (admin/financeiro); revoke de public, anon e
--      authenticated; escrita só pelas funções security definer das próximas migrations (e por service_role).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase5_base.sql):
--   · cliente_tipos_ligados: a spec diz "os 10 tipos da §4.3", mas a §4.3 lista 11 (pronto e pronto_lembrete são os dois do
--     M8). O CHECK aceita os 11.
--   · cliente_hora_toque e cliente_hora_preparo "dentro da janela de seg–sex": [cliente_janela_inicio, cliente_janela_fim).
--   · O gatilho de agenda_cliente_mensagens deixa enviar_em mudar só enquanto a mensagem está registrada ou esperando o dono
--     (d19: a espera da conversa viva); depois de enfileirada, a hora fica.
--
-- O QUE NÃO MUDA: nenhum comportamento até as próximas migrations. Nenhum cron, nenhuma tela, nenhuma função de borda; nenhuma
-- mensagem sai. A coluna critica só muda para o tipo novo (as 6 críticas de antes continuam). O espelho scheduled_* da Fase 2
-- não muda (a Fase 5 lê o plano, não o espelho).
--
-- ORDEM DE LIGAR: depois das Fases 1 a 4 inteiras aplicadas (fila-do-dono/fase1-oks.md … fase4-oks.md); antes de
-- 20261028100100 (os textos, que leem as colunas novas). Aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase5_base.sql (begin/rollback; cada CHECK recusa uma linha errada, as
-- tabelas novas não se apagam e só mudam as colunas de estado, RLS, anon sem privilégio, critica com cliente_aviso). Na
-- bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261028100100
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261028100000_agenda_fase5_tabelas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100000', 'agenda_fase5_tabelas');"
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$ (os de lista fechada: drop if exists + add), create
-- table/index if not exists, create or replace function, drop trigger/policy if exists + create, SET EXPRESSION só quando a
-- expressão ainda não tem o tipo novo.

-- ── 1. O modo e os parâmetros da mensagem ao cliente ────────────────────────────────────────────────────
-- modo_cliente e o CHECK dele já existem desde a Fase 1 (20261024160000): o "if not exists" abaixo não os recria (fica para a
-- base que ainda não os tiver).
alter table public.agenda_config
  add column if not exists modo_cliente                     text     not null default 'desligado',
  add column if not exists cliente_tipos_ligados            text[]   not null default '{}',
  add column if not exists cliente_janela_inicio            time     not null default '08:00',
  add column if not exists cliente_janela_fim               time     not null default '19:00',
  add column if not exists cliente_sabado_fim               time     not null default '13:00',
  add column if not exists cliente_dia_max                  smallint not null default 1,
  add column if not exists cliente_semana_max               smallint not null default 3,
  add column if not exists cliente_total_dia_max            smallint not null default 8,
  add column if not exists cliente_intervalo_min_s          smallint not null default 30,
  add column if not exists cliente_intervalo_max_s          smallint not null default 60,
  add column if not exists cliente_aprovacao_dias           smallint not null default 3,
  add column if not exists cliente_hora_toque               time     not null default '09:00',
  add column if not exists cliente_hora_preparo             time     not null default '17:00',
  add column if not exists cliente_confirmar_du             smallint not null default 3,
  add column if not exists cliente_resposta_validade        interval not null default '72 hours',
  add column if not exists cliente_sem_resposta_horas       smallint not null default 48,
  add column if not exists cliente_atraso_na_hora_du        smallint not null default 2,
  add column if not exists cliente_acesso_validade_dias     smallint not null default 90,
  add column if not exists cliente_andamento_min_du         smallint not null default 5,
  add column if not exists cliente_andamento_intervalo_dias smallint not null default 6,
  add column if not exists cliente_pronto_lembrete_dias     smallint not null default 3,
  add column if not exists cliente_pos_dias                 smallint not null default 5,
  add column if not exists cliente_conversa_dias            smallint not null default 365,
  add column if not exists cliente_conversa_viva_min        smallint not null default 60,
  add column if not exists cliente_mesmo_tipo_horas         smallint not null default 24;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('agenda_config_modo_cliente_check',
       'check (modo_cliente in (''desligado'', ''sombra'', ''ligado''))'),
      ('agenda_config_cliente_tipos_ligados_check',
       'check (cliente_tipos_ligados <@ array[''confirmar'', ''vespera'', ''acesso'', ''material_chegou'', ''andamento'', ''pode_atrasar'', ''nova_data'', ''pronto'', ''pronto_lembrete'', ''pos_servico'', ''mudanca_no_dia'']::text[])'),
      ('agenda_config_cliente_janela_inicio_check',
       'check (cliente_janela_inicio between time ''07:00'' and time ''10:00'')'),
      ('agenda_config_cliente_janela_fim_check',
       'check (cliente_janela_fim between time ''17:00'' and time ''20:00'')'),
      ('agenda_config_cliente_sabado_fim_check',
       'check (cliente_sabado_fim between time ''11:00'' and time ''14:00'' and cliente_sabado_fim > cliente_janela_inicio)'),
      ('agenda_config_cliente_dia_max_check',          'check (cliente_dia_max between 1 and 2)'),
      ('agenda_config_cliente_semana_max_check',       'check (cliente_semana_max between 1 and 5)'),
      ('agenda_config_cliente_total_dia_max_check',    'check (cliente_total_dia_max between 1 and 30)'),
      ('agenda_config_cliente_intervalo_min_s_check',
       'check (cliente_intervalo_min_s between 10 and 120 and cliente_intervalo_min_s <= cliente_intervalo_max_s)'),
      ('agenda_config_cliente_intervalo_max_s_check',  'check (cliente_intervalo_max_s <= 300)'),
      ('agenda_config_cliente_aprovacao_dias_check',   'check (cliente_aprovacao_dias between 0 and 10)'),
      ('agenda_config_cliente_hora_toque_check',
       'check (cliente_hora_toque >= cliente_janela_inicio and cliente_hora_toque < cliente_janela_fim)'),
      ('agenda_config_cliente_hora_preparo_check',
       'check (cliente_hora_preparo >= cliente_janela_inicio and cliente_hora_preparo < cliente_janela_fim)'),
      ('agenda_config_cliente_confirmar_du_check',     'check (cliente_confirmar_du between 1 and 5)'),
      ('agenda_config_cliente_resposta_validade_check',
       'check (cliente_resposta_validade between interval ''24 hours'' and interval ''168 hours'')'),
      ('agenda_config_cliente_sem_resposta_horas_check', 'check (cliente_sem_resposta_horas between 12 and 96)'),
      ('agenda_config_cliente_atraso_na_hora_du_check',  'check (cliente_atraso_na_hora_du between 1 and 5)'),
      ('agenda_config_cliente_acesso_validade_dias_check', 'check (cliente_acesso_validade_dias between 7 and 365)'),
      ('agenda_config_cliente_andamento_min_du_check',   'check (cliente_andamento_min_du between 2 and 20)'),
      ('agenda_config_cliente_andamento_intervalo_dias_check', 'check (cliente_andamento_intervalo_dias between 3 and 14)'),
      ('agenda_config_cliente_pronto_lembrete_dias_check', 'check (cliente_pronto_lembrete_dias between 1 and 7)'),
      ('agenda_config_cliente_pos_dias_check',           'check (cliente_pos_dias between 3 and 7)'),
      ('agenda_config_cliente_conversa_dias_check',      'check (cliente_conversa_dias between 0 and 730)'),
      ('agenda_config_cliente_conversa_viva_min_check',  'check (cliente_conversa_viva_min between 0 and 240)'),
      ('agenda_config_cliente_mesmo_tipo_horas_check',   'check (cliente_mesmo_tipo_horas between 12 and 72)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.agenda_config'::regclass and conname = r.nome) then
      execute format('alter table public.agenda_config add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

-- Como as Fases 2 a 4: a estrutura não muda comportamento. A linha que já existe fica 'desligado' (do add column acima);
-- quem a põe em sombra é a migration de dado 20261028101000, com OK nomeado.
alter table public.agenda_config alter column modo_cliente set default 'sombra';

comment on column public.agenda_config.modo_cliente is
  'desligado = a agenda não fala com cliente; sombra = grava a mensagem que mandaria (aparece no foco clientes como ''Em teste''); ligado = manda os tipos de cliente_tipos_ligados (os outros seguem em teste), com a aprovação do dono nos cliente_aprovacao_dias primeiros dias de cada tipo.';
comment on column public.agenda_config.cliente_tipos_ligados is
  'As ondas (spec-fase5 §10): os tipos de mensagem ao cliente que saem com modo_cliente ligado. Tipo fora da lista é gravado em teste (sombra). Onda 1: material_chegou, nova_data, pode_atrasar; onda 2: + confirmar, vespera, acesso, mudanca_no_dia (a R15 sai junto); onda 3: + pronto, pronto_lembrete; onda 4: + andamento, pos_servico.';
comment on column public.agenda_config.cliente_janela_inicio is 'Mensagem ao cliente: a 1ª hora em que sai (seg a sáb; nunca domingo nem feriado).';
comment on column public.agenda_config.cliente_janela_fim is 'Mensagem ao cliente: nada sai desta hora em diante, de seg a sex.';
comment on column public.agenda_config.cliente_sabado_fim is 'Mensagem ao cliente no sábado: [cliente_janela_inicio, cliente_sabado_fim).';
comment on column public.agenda_config.cliente_dia_max is 'Mensagens ao MESMO cliente por dia (de Brasília).';
comment on column public.agenda_config.cliente_semana_max is 'Mensagens ao MESMO cliente por semana ISO.';
comment on column public.agenda_config.cliente_total_dia_max is 'Mensagens a clientes por dia, somando todos.';
comment on column public.agenda_config.cliente_intervalo_min_s is 'Segundos mínimos entre duas mensagens a clientes (o banco espaça entre o mínimo e o máximo).';
comment on column public.agenda_config.cliente_intervalo_max_s is 'Segundos máximos do espaçamento entre duas mensagens a clientes.';
comment on column public.agenda_config.cliente_aprovacao_dias is 'Um tipo de mensagem sai sozinho só depois de somar este número de dias DISTINTOS (Brasília) com mensagem daquele tipo aprovada pelo dono (d11). 0 = sem aprovação. "Segura" não conta.';
comment on column public.agenda_config.cliente_hora_toque is 'A hora do M1 (D-3 em dias úteis) e da véspera (D-1).';
comment on column public.agenda_config.cliente_hora_preparo is 'A partir desta hora a rodada registra a mensagem de amanhã (entra no fechamento das 17:30).';
comment on column public.agenda_config.cliente_confirmar_du is 'O "D-3": a confirmação da data sai estes dias úteis antes do 1º dia.';
comment on column public.agenda_config.cliente_resposta_validade is 'A resposta do cliente vale para a última mensagem da agenda enviada a ele até este tempo antes.';
comment on column public.agenda_config.cliente_sem_resposta_horas is 'Confirmação (M1/M3/M7/M10) enviada há mais destas horas sem resposta vira uma linha ao dono (sem reenviar).';
comment on column public.agenda_config.cliente_atraso_na_hora_du is 'O aviso de atraso (M6) sai na hora quando a data dita ao cliente vence em até estes dias úteis; senão vai pelo fechamento.';
comment on column public.agenda_config.cliente_acesso_validade_dias is 'O acesso dito pelo cliente (acesso_ok_em) vale estes dias; depois a véspera volta a perguntar.';
comment on column public.agenda_config.cliente_andamento_min_du is 'OS mais longa que estes dias úteis ganha o andamento semanal (M5).';
comment on column public.agenda_config.cliente_andamento_intervalo_dias is 'Dias corridos entre dois andamentos semanais (M5).';
comment on column public.agenda_config.cliente_pronto_lembrete_dias is 'Dias depois do "ficou pronto" (M8) sem resposta e sem entrega, o lembrete sai uma vez.';
comment on column public.agenda_config.cliente_pos_dias is 'Dias depois da entrega (ou da conclusão) em que sai o pós-serviço (M9).';
comment on column public.agenda_config.cliente_conversa_dias is 'Só manda a quem mandou alguma mensagem ao número da HBR nestes dias (d10). 0 = sem essa exigência.';
comment on column public.agenda_config.cliente_conversa_viva_min is 'Com mensagem do cliente (ou do dono a ele) nestes minutos, a mensagem da agenda espera o próximo tique (d19: uma voz só). 0 = não espera.';
comment on column public.agenda_config.cliente_mesmo_tipo_horas is 'A revalidação na saída recusa outra mensagem do mesmo tipo ao mesmo cliente enviada nestas horas.';

-- ── 2. O que foi DITO ao cliente (≠ o plano) e como o serviço é dito a ele ──────────────────────────────
alter table public.os_planejamento
  add column if not exists prometido_tipo         text check (prometido_tipo in ('condicional', 'faixa', 'firme')),
  add column if not exists prometido_de           date,
  add column if not exists prometido_ate          date,
  add column if not exists prometido_original_ate date,
  add column if not exists prometido_em           timestamptz,
  add column if not exists prometido_fonte        text check (prometido_fonte in ('mensagem', 'dono', 'confirmacao')),
  add column if not exists prometido_mensagem_id  uuid,
  add column if not exists servico_cliente        text check (char_length(servico_cliente) between 3 and 80),
  add column if not exists acesso_ok_em           timestamptz;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('prometido_coerente', 'check ((prometido_ate is null) = (prometido_tipo is null))'),
      ('prometido_faixa',    'check (prometido_de is null or prometido_de <= prometido_ate)'),
      ('prometido_original', 'check (prometido_original_ate is null or prometido_ate is not null)')
    ) as c(nome, regra)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.os_planejamento'::regclass and conname = r.nome) then
      execute format('alter table public.os_planejamento add constraint %I %s', r.nome, r.regra);
    end if;
  end loop;
end
$$;

comment on column public.os_planejamento.prometido_tipo is
  'Agenda de Produção (Fase 5): o que foi dito ao cliente (≠ o plano): gravado quando a mensagem com data sai (gatilho de whatsapp_send_queue) ou pelo *grava* do dono. A 1ª fica em prometido_original_ate. condicional = depende da peça; faixa = entre duas datas; firme = a data.';
comment on column public.os_planejamento.prometido_de is 'Agenda de Produção (Fase 5): o 1º dia dito ao cliente (firme: o início; faixa/condicional: o começo da faixa).';
comment on column public.os_planejamento.prometido_ate is 'Agenda de Produção (Fase 5): o último dia dito ao cliente (firme: o fim; faixa/condicional: o fim da faixa). O M6 nasce da diferença entre o planejado e isto.';
comment on column public.os_planejamento.prometido_original_ate is 'Agenda de Produção (Fase 5): o prometido_ate da 1ª promessa (nunca muda depois; a Fase 6 mede a pontualidade contra ele).';
comment on column public.os_planejamento.prometido_em is 'Agenda de Produção (Fase 5): quando o prometido foi gravado.';
comment on column public.os_planejamento.prometido_fonte is 'Agenda de Produção (Fase 5): mensagem (a agenda mandou), dono (o *grava* do "falei pro Flávio que é dia 3") ou confirmacao (o botão antigo de pedir confirmação).';
comment on column public.os_planejamento.prometido_mensagem_id is 'Agenda de Produção (Fase 5): agenda_cliente_mensagens.id da mensagem que disse a data (sem FK: a tabela é desta migration e a ordem das migrations não importa).';
comment on column public.os_planejamento.servico_cliente is
  'Agenda de Produção (Fase 5): como o serviço é dito ao cliente (''a instalação das baterias''). Sem ele: ''o serviço no seu motorhome''.';
comment on column public.os_planejamento.acesso_ok_em is 'Agenda de Produção (Fase 5): quando o acesso ao local foi dito (pelo cliente ou pelo dono). Vale cliente_acesso_validade_dias.';

-- ── 3. As tabelas do cliente ────────────────────────────────────────────────────────────────────────────

-- (1) Toda mensagem ao cliente (mandada, esperando o dono, em teste ou recusada). NUNCA apagada.
create table if not exists public.agenda_cliente_mensagens (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.clients(id),
  service_order_id uuid not null references public.service_orders(id),
  tipo             text not null check (tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                 'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                 'pos_servico', 'mudanca_no_dia')),
  modelo           text generated always as (case tipo
                     when 'confirmar' then 'M1' when 'vespera' then 'M2' when 'material_chegou' then 'M3'
                     when 'acesso' then 'M4' when 'andamento' then 'M5' when 'pode_atrasar' then 'M6'
                     when 'nova_data' then 'M7' when 'pronto' then 'M8' when 'pronto_lembrete' then 'M8'
                     when 'pos_servico' then 'M9' else 'M10' end) stored,
  variante         text check (char_length(variante) <= 30),
  origem           text not null check (origem in ('rodada', 'dono', 'botao')),
  dia_alvo         date,
  faixa_de         date,
  faixa_ate        date,
  prometido_tipo   text check (prometido_tipo in ('condicional', 'faixa', 'firme')),
  modo             text not null check (modo in ('sombra', 'ligado')),
  texto            text not null check (char_length(texto) between 3 and 600),
  base             jsonb not null default '{}' check (jsonb_typeof(base) = 'object'),
  enviar_em        timestamptz not null,
  valida_ate       timestamptz not null,
  aprovacao        text not null check (aprovacao in ('livre', 'pedida', 'aprovada', 'segurada', 'vencida', 'critica')),
  pergunta_id      uuid references public.agenda_perguntas(id) on delete restrict,
  aprovada_em      timestamptz,
  aprovada_por     uuid references public.app_users(id) on delete set null,
  estado           text not null default 'registrada' check (estado in ('registrada', 'aguardando_dono', 'enfileirada',
                     'enviada', 'respondida', 'sem_resposta', 'recusada')),
  recusa_motivo    text check (recusa_motivo in ('modo', 'tipo_em_teste', 'opt_out', 'sem_telefone', 'sem_conversa',
                     'domingo', 'feriado', 'janela', 'teto_dia', 'teto_semana', 'teto_total', 'intervalo', 'mesmo_tipo_24h',
                     'status', 'data_mudou', 'material', 'passou_da_data', 'desatualizada', 'segurada', 'vencida', 'texto')),
  fila_id          uuid,
  dedupe_key       text not null unique,
  enviada_em       timestamptz,
  resposta_id      uuid,
  acao_id          uuid references public.agenda_acoes(id) on delete set null,
  criada_em        timestamptz not null default now(),
  constraint cliente_recusa_coerente    check ((estado = 'recusada') = (recusa_motivo is not null)),
  constraint cliente_faixa_coerente     check (faixa_de is null or faixa_ate is null or faixa_de <= faixa_ate),
  constraint cliente_aprovacao_coerente check ((aprovacao in ('aprovada', 'segurada')) = (aprovada_em is not null)),
  -- a pergunta nasce antes da mensagem, na mesma transação: o registrar (P2) cria a pergunta com a chave da mensagem e
  -- insere a mensagem já com o pergunta_id (o CHECK vale no INSERT).
  constraint cliente_critica_pergunta   check (aprovacao not in ('pedida', 'critica') or modo = 'sombra' or pergunta_id is not null),
  constraint cliente_enviada_coerente   check ((estado in ('enviada', 'respondida', 'sem_resposta')) = (enviada_em is not null))
);

create index if not exists agenda_cliente_por_cliente on public.agenda_cliente_mensagens(client_id, enviar_em desc);
create index if not exists agenda_cliente_vivas on public.agenda_cliente_mensagens(estado, enviar_em)
  where estado in ('registrada', 'aguardando_dono', 'enfileirada');

comment on table public.agenda_cliente_mensagens is
  'Agenda de Produção (Fase 5): toda mensagem-modelo ao cliente (M1 confirmar, M2 véspera, M3 material chegou, M4 acesso, M5 andamento, M6 pode atrasar, M7 nova data, M8 pronto e o lembrete, M9 pós-serviço, M10 mudança no dia) — o texto é o do banco (_agenda_cliente_texto), nunca livre —, mandada (ligado), esperando o dono (aprovação dos primeiros dias ou pergunta crítica), só registrada (sombra) ou recusada com o motivo. Nunca leva valor, número de OS nem link. NUNCA apagada; só o estado, a recusa, a fila, a aprovação, a pergunta, o envio, a resposta e a ação mudam (e a hora, enquanto espera).';
comment on column public.agenda_cliente_mensagens.variante is 'primeira, seguinte, unico (M1); peca, execucao, remarcado (M6); primeiro_dia, semanal (M5); clima, equipe, geral (M10).';
comment on column public.agenda_cliente_mensagens.dia_alvo is 'O dia de que a mensagem fala (o início, o fim novo, o dia da véspera…).';
comment on column public.agenda_cliente_mensagens.prometido_tipo is 'O que a mensagem DIZ de data (null = sem data): ao sair, vira o os_planejamento.prometido_*.';
comment on column public.agenda_cliente_mensagens.base is '{status, dia_alvo, fim, nivel, prometido_ate, primeira, envio…}: o retrato de quando foi registrada, para a revalidação na saída.';
comment on column public.agenda_cliente_mensagens.valida_ate is 'Depois disto a mensagem não sai mais (vencida).';
comment on column public.agenda_cliente_mensagens.aprovacao is 'livre (sai sozinha), pedida (espera *manda cliente*), aprovada, segurada, vencida (o dono não respondeu a tempo) ou critica (pergunta crítica cliente_aviso).';
comment on column public.agenda_cliente_mensagens.fila_id is 'whatsapp_send_queue.id quando enfileirada (sem FK: a fila é podada).';
comment on column public.agenda_cliente_mensagens.dedupe_key is 'agenda-cliente:<tipo>:<os>:<dia_alvo ou n>[:sombra] — a chave da fila. Em sombra termina em ":sombra" (a de verdade não colide com a registrada).';
comment on column public.agenda_cliente_mensagens.resposta_id is 'agenda_cliente_respostas.id (a 1ª resposta).';

-- (2) Toda mensagem do cliente que a agenda leu (com ou sem mensagem dela esperando). NUNCA apagada.
create table if not exists public.agenda_cliente_respostas (
  id                  uuid primary key default gen_random_uuid(),
  client_id           uuid not null references public.clients(id),
  service_order_id    uuid references public.service_orders(id) on delete set null,
  mensagem_id         uuid references public.agenda_cliente_mensagens(id) on delete set null,
  whatsapp_message_id uuid unique,
  recebida_em         timestamptz not null,
  tipo_msg            text not null check (tipo_msg in ('text', 'audio', 'image', 'document', 'video', 'outro')),
  texto               text check (char_length(texto) <= 500),
  intencao            text not null check (intencao in ('confirma', 'remarcar', 'falta', 'data', 'acesso', 'opt_out', 'disputa',
                        'negociacao', 'pergunta', 'acordo', 'audio', 'outro')),
  expressao           text check (char_length(expressao) <= 60),
  data_dita           date,
  efeito              text not null check (efeito in ('confirmou', 'ciencia', 'replanejou', 'anotou_acesso', 'opt_out',
                        'ao_dono', 'ambigua', 'sombra', 'nada')),
  modo                text not null check (modo in ('sombra', 'ligado')),
  acao_id             uuid references public.agenda_acoes(id) on delete set null,
  pergunta_id         uuid references public.agenda_perguntas(id) on delete set null,
  criada_em           timestamptz not null default now()
);

create index if not exists agenda_cliente_respostas_por_cliente on public.agenda_cliente_respostas(client_id, recebida_em desc);

comment on table public.agenda_cliente_respostas is
  'Agenda de Produção (Fase 5): toda mensagem do cliente que a agenda leu — a intenção (sem IA: o leitor do webhook), a expressão de data e a data convertida pelo banco, e o efeito (confirmou, ciência, replanejou, anotou o acesso, opt-out, foi ao dono, ambígua, em teste, nada). O áudio nunca confirma. NUNCA apagada; só o efeito, a ação, a pergunta e a data dita mudam.';
comment on column public.agenda_cliente_respostas.whatsapp_message_id is 'whatsapp_messages.id (o webhook manda; sem FK: a mensagem é do WhatsApp). Uma resposta por mensagem.';
comment on column public.agenda_cliente_respostas.expressao is 'A expressão de data que o leitor (TS) extraiu ("pode ser sexta?" → "sexta"); a data sai do banco (agenda_data_dita).';

-- ── 4. Os registros não se apagam e só mudam no estado ──────────────────────────────────────────────────
create or replace function public._agenda_cliente_mensagens_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           array['estado', 'recusa_motivo', 'fila_id', 'aprovacao', 'pergunta_id', 'aprovada_em', 'aprovada_por',
                 'enviada_em', 'resposta_id', 'acao_id', 'enviar_em', 'modelo'],
           array['aprovada_por', 'acao_id']) then
    raise exception 'A mensagem ao cliente registrada não muda: só o estado, a aprovação, a fila, o envio e a resposta.';
  end if;
  -- A hora só muda enquanto a mensagem espera (d19: a conversa viva empurra para o próximo tique).
  if new.enviar_em is distinct from old.enviar_em and old.estado not in ('registrada', 'aguardando_dono') then
    raise exception 'A hora da mensagem ao cliente só muda enquanto ela espera (registrada ou esperando o dono).';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_cliente_mensagens_so_muda() is
  'Agenda de Produção (Fase 5): gatilho BEFORE UPDATE de agenda_cliente_mensagens — só estado, recusa_motivo, fila_id, aprovacao, pergunta_id, aprovada_*, enviada_em, resposta_id, acao_id e enviar_em mudam (este só enquanto a mensagem está registrada ou esperando o dono); o texto, o tipo, o cliente, a OS, o modo, a chave e a base ficam como foram.';

create or replace function public._agenda_cliente_respostas_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new), array['efeito', 'acao_id', 'pergunta_id', 'data_dita'],
                                 array['service_order_id', 'mensagem_id', 'acao_id', 'pergunta_id']) then
    raise exception 'A resposta do cliente registrada não muda: só o efeito, a ação, a pergunta e a data dita.';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_cliente_respostas_so_muda() is
  'Agenda de Produção (Fase 5): gatilho BEFORE UPDATE de agenda_cliente_respostas — só efeito, acao_id, pergunta_id e data_dita mudam (e as referências que o ON DELETE SET NULL anular); o texto, a intenção e quem mandou ficam como foram.';

drop trigger if exists agenda_cliente_mensagens_nao_apaga on public.agenda_cliente_mensagens;
create trigger agenda_cliente_mensagens_nao_apaga before delete on public.agenda_cliente_mensagens
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_cliente_mensagens_so_muda on public.agenda_cliente_mensagens;
create trigger agenda_cliente_mensagens_so_muda before update on public.agenda_cliente_mensagens
  for each row execute function public._agenda_cliente_mensagens_so_muda();

drop trigger if exists agenda_cliente_respostas_nao_apaga on public.agenda_cliente_respostas;
create trigger agenda_cliente_respostas_nao_apaga before delete on public.agenda_cliente_respostas
  for each row execute function public._agenda_registro_nao_apaga();
drop trigger if exists agenda_cliente_respostas_so_muda on public.agenda_cliente_respostas;
create trigger agenda_cliente_respostas_so_muda before update on public.agenda_cliente_respostas
  for each row execute function public._agenda_cliente_respostas_so_muda();

-- ── 5. As listas fechadas ampliadas ─────────────────────────────────────────────────────────────────────
-- Perguntas: os 22 tipos da Fase 4 + os 3 do cliente. cliente_aviso é CRÍTICA (o 2º atraso, o atraso longo, a data dita que
-- passou e o aviso que não cabe no teto: recomenda ligar); cliente_aprovar é a aprovação dos primeiros dias e
-- cliente_resposta é fato que só o dono resolve (nenhuma das duas é crítica).
alter table public.agenda_perguntas drop constraint if exists agenda_perguntas_tipo_check;
alter table public.agenda_perguntas add constraint agenda_perguntas_tipo_check
  check (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono',
                  'conferencia','chegou','parada','estouro','duracao','material_conferir','padrao_do_dono',
                  'diaria','diaria_ligar','equipe_resposta','concluir','entrega',
                  'nfe_vincular','pix_material','previsao_fornecedor','fornecedor_cadastro','fornecedores_prazo',
                  'cliente_aprovar','cliente_aviso','cliente_resposta'));

-- A coluna gerada: cliente_aviso passa a ser crítica. SET EXPRESSION (Postgres 17+, o molde da Fase 3 em
-- 20261026100000) mantém a coluna no lugar e reconstrói e revalida critica_tem_opcoes e critica_decidida com o mesmo nome.
-- Só se a expressão ainda não tem 'cliente_aviso' (rodar de novo não reescreve a tabela).
do $$
begin
  if exists (select 1
               from pg_attribute a
               join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
              where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica' and a.attgenerated = 's'
                and pg_get_expr(d.adbin, d.adrelid) not like '%''cliente_aviso''%') then
    if current_setting('server_version_num')::int < 170000 then
      raise exception 'agenda_perguntas.critica: esta migration precisa do Postgres 17 ou mais novo (ALTER COLUMN … SET EXPRESSION); este é o %.',
        current_setting('server_version');
    end if;
    alter table public.agenda_perguntas alter column critica set expression as
      (tipo in ('nao_cabe','segundo_atraso','atraso_longo','remarcar_confirmado','fixada_pelo_dono','diaria','cliente_aviso'));
  end if;
end
$$;

comment on column public.agenda_perguntas.chave is
  'chegou:<os_material>:<previsao_ate>, conferencia:<dia>, nao_cabe:<os>:<versao>… — a mesma pergunta não abre duas vezes. Fase 4: fornecedor_cadastro:<fornecedor> e fornecedores_prazo (uma só), que o *grava* do prazo do fornecedor resolve. Fase 5: cliente_aprovar:<mensagem>, cliente_aviso:<os>:<dia_alvo>, cliente_resposta:<resposta>.';

alter table public.agenda_acoes drop constraint if exists agenda_acoes_tipo_check;
alter table public.agenda_acoes add constraint agenda_acoes_tipo_check
  check (tipo in ('publicar','criar','mover','cancelar','fixar','promover_reserva','soltar_reserva','status','resultado',
                  'desfazer','diaria','concluir','entregar','equipe','material','fornecedor','cliente'));
alter table public.agenda_acoes drop constraint if exists agenda_acoes_origem_check;
alter table public.agenda_acoes add constraint agenda_acoes_origem_check
  check (origem in ('motor','vigia','conferencia','dono','assistente','tela','aprovacao','sistema','equipe',
                    'fornecedor','nota','cliente'));

-- A rodada do cliente (P3: agenda_cliente_vigiar) grava as rodadas na mesma tabela. A agenda_saude já filtra por rotina.
alter table public.agenda_vigia_rodadas drop constraint if exists agenda_vigia_rodadas_rotina_check;
alter table public.agenda_vigia_rodadas add constraint agenda_vigia_rodadas_rotina_check
  check (rotina in ('vigia', 'rotina', 'material', 'cliente'));

comment on column public.agenda_vigia_rodadas.rotina is
  'Agenda de Produção (Fase 3): vigia (o tique da Fase 2) ou rotina (a rotina da equipe e da diária); Fase 4: material (a nota, o Pix, o detector e a mensagem ao fornecedor); Fase 5: cliente (as mensagens-modelo ao cliente). As rodadas de antes são da vigia.';

-- ── 6. Portas: RLS, só leitura, escrita só pelas funções ────────────────────────────────────────────────
alter table public.agenda_cliente_mensagens enable row level security;
alter table public.agenda_cliente_respostas enable row level security;

drop policy if exists agenda_cliente_mensagens_leitura on public.agenda_cliente_mensagens;
create policy agenda_cliente_mensagens_leitura on public.agenda_cliente_mensagens
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_cliente_respostas_leitura on public.agenda_cliente_respostas;
create policy agenda_cliente_respostas_leitura on public.agenda_cliente_respostas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.agenda_cliente_mensagens, public.agenda_cliente_respostas from public, anon, authenticated;
grant select on table public.agenda_cliente_mensagens, public.agenda_cliente_respostas to authenticated;
grant all on table public.agenda_cliente_mensagens, public.agenda_cliente_respostas to service_role;

-- Funções de gatilho: sem grant a ninguém.
revoke all on function public._agenda_cliente_mensagens_so_muda(), public._agenda_cliente_respostas_so_muda()
  from public, anon, authenticated;
