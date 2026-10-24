-- Agenda de Produção, Fase 1 ("O que eu tenho que fazer"), pacote P1: as 6 tabelas da base.
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§3, §4, §5.7). Plano: plano-final.md §3; revisão §4–§7.
--
-- ═══ DDL — OK NOMEADO ═══ (6 tabelas novas, vazias, e UMA linha de configuração em agenda_config)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- O QUE MUDA:
--   1. agenda_config: os parâmetros da agenda numa linha tipada, com CHECK em cada um. O DEFAULT da coluna é o
--      ÚNICO lugar do número (nenhum literal no TS nem no corpo das funções agenda_*/os_*). Sem folga remota
--      (revisão §7: o prazo "outro estado" já cobre o transporte) e sem limiar de turno nem compromissos do
--      dono (revisão §6). Nasce com modo_leitura = 'sombra' (a ferramenta e os comandos respondem; o
--      fechamento só registra) e os outros quatro modos 'desligado'. versao_plano 0 (o motor é da Fase 2).
--      A linha entra aqui mesmo (insert … on conflict do nothing): é configuração, não dado de cliente.
--   2. agenda_disponibilidade: quem vem quando. PADRÃO por dia da semana (dias_semana) OU EXCEÇÃO por data
--      (periodo), nunca os dois. Turno nulo = o dia inteiro. payee_id nulo = todos (recesso). A semente das
--      diárias (origem 'historico', 20261024160200) guarda a frequência medida; o dono, o diarista e o
--      agente gravam sem frequência. Linha trocada não é apagada: ganha substituida_em (fica o rastro).
--      frequencia é numeric(5,4) e não (3,2): com 2 casas a soma das linhas arredondadas do João dá 2,34
--      em vez de 2,33 (0,50 + 0,67 + 0,67 + 0,50), e a capacidade 5,42 em vez de 5,41.
--   3. os_planejamento: o que o dono DISSE da OS — dias de calendário, quem vai (3b), se ele abre e fecha,
--      quando o cliente precisa, quando o bem está fora, "não antes de", escopo em aberto e decidido,
--      espera, prioridade e "não tem peça a comprar" (material_conferido_em). O que é derivado (meios-dias,
--      estado, prontidão) é calculado na leitura (Fase 1, P3). estimativa_fonte só aceita 'dono' ou 'aceita':
--      a sugestão do banco nunca vira linha gravada ("nenhum número não dito").
--   3b. os_planejamento_equipe: quem vai, por turno (dia, manhã, tarde), com FK para payees — pessoa que não
--      existe não entra. O dono também pode estar aqui ("um dia, eu e o Roberto").
--   4. os_material: o fato de cada linha de material da OS (peça, texto livre, item de OC de texto livre ou
--      linha que o dono citou): quanto precisa, quanto está na mão, se é crítico ("pode começar sem" =
--      critico false, não uma situação), situação, de onde veio a informação, previsão com a fonte, chegada,
--      as palavras do dono (trecho) e o histórico. O nível A–E é derivado na leitura. Os CHECKs impedem o
--      estado incoerente ("na mão" sem a quantidade completa, "falta" com previsão, previsão sem fonte). Um
--      índice único por vínculo impede a mesma peça duas vezes; a linha do dono pode citar a mesma linha de
--      serviço quantas vezes precisar (peça embutida: "baterias", "barramento").
--   5. agenda_rascunho: o que o dono disse na conversa e ainda não mandou gravar (uma linha aberta por chave;
--      a correção substitui). Só o *grava* do dono (RPC da Fase 1, P5) transforma rascunho em fato.
--
-- PORTAS (§5.7): RLS ligada nas 6; só policy de LEITURA, TO authenticated, para admin ou financeiro (o
-- rascunho: só o próprio autor, e admin). Nenhuma policy de escrita: escreve-se só pelas RPCs security definer
-- (P2, P5). revoke de public, anon e authenticated; grant select a authenticated, all a service_role.
-- A spec citava uma policy de UPDATE da agenda_config por admin; ela não entra: sem o privilégio de update
-- (revogado de authenticated, como a spec manda) a policy seria letra morta. O parâmetro muda por SQL, com OK;
-- uma tela futura ganha RPC própria.
--
-- O QUE NÃO MUDA: nenhuma tabela existente, nenhuma função, nenhum gatilho, nenhum cron.
--
-- ORDEM DE LIGAR: depois da Fase 0 inteira aplicada (20261024150000, 150100, 150200 e a faxina 153000);
-- antes de 20261024160100 (calendário, que lê agenda_config e agenda_disponibilidade) e 160200 (semente).
-- Nenhuma tela nem função de borda lê estas tabelas ainda: aplicar sozinha não muda nada para ninguém.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase1_base.sql (begin/rollback; cada CHECK recusa uma
-- linha errada, RLS, policies {authenticated}, anon sem privilégio). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261024160200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261024160000_agenda_fase1_tabelas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024160000', 'agenda_fase1_tabelas');"
--
-- IDEMPOTENTE: create table/index if not exists, drop policy if exists + create policy, insert on conflict.

-- ── 1. Parâmetros ───────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_config (
  id                    boolean primary key default true check (id),
  manha_inicio          time not null default '08:00',
  manha_fim             time not null default '12:00',
  tarde_inicio          time not null default '13:00',
  tarde_fim             time not null default '17:00',
  jornada_horas         numeric(4,2) not null default 8     check (jornada_horas between 4 and 12),
  carga_max             numeric(3,2) not null default 0.80  check (carga_max between 0.50 and 1.00),
  fator_promessa        numeric(3,2) not null default 1.50  check (fator_promessa between 1.00 and 2.50),
  wip_max               smallint     not null default 2     check (wip_max between 1 and 3),
  congelamento_du       smallint     not null default 1     check (congelamento_du between 0 and 3),
  horizonte_semanas     smallint     not null default 6     check (horizonte_semanas between 2 and 12),
  folga_material_du     smallint     not null default 1     check (folga_material_du between 0 and 5),
  prazo_classe_du       jsonb        not null
    default '{"balcao":0,"entrega_local":1,"distribuidor_sc_pr":2,"outro_estado":4,"marketplace":3}'
    check (jsonb_typeof(prazo_classe_du) = 'object'),
  importacao_dias       smallint     not null default 20,
  municipios_locais     text[]       not null
    default '{"Itajaí","Balneário Camboriú","Navegantes","Camboriú","Tijucas","Blumenau","Penha"}',
  mo_por_diaria_preco   numeric(8,2) not null default 1600  check (mo_por_diaria_preco > 0),
  mo_por_diaria_real    numeric(8,2) not null default 764   check (mo_por_diaria_real > 0),
  equipe_sugerida       smallint     not null default 2     check (equipe_sugerida between 1 and 3),
  prazo_padrao_du       smallint     not null default 20    check (prazo_padrao_du between 5 and 60),
  parada_du             smallint     not null default 3,
  estouro_fator         numeric(3,2) not null default 1.50,
  aviso_atraso_du       smallint     not null default 2,
  proposta_validade     interval     not null default '72 hours',
  acordes_dia_max       smallint     not null default 1,
  exige_sinal_publicar  boolean      not null default true,
  sabado_util           boolean      not null default false,
  dia_do_plano          smallint     not null default 4     check (dia_do_plano between 1 and 5),
  medicao_semanas       smallint     not null default 8     check (medicao_semanas between 2 and 26),
  equipe_recente_dias   smallint     not null default 14    check (equipe_recente_dias between 7 and 60),
  frequencia_minima     numeric(3,2) not null default 0.25  check (frequencia_minima between 0 and 1),
  peca_embutida_acima   numeric(10,2) not null default 1000 check (peca_embutida_acima >= 0),
  texto_max             smallint     not null default 1000  check (texto_max between 400 and 3000),
  rascunho_validade     interval     not null default '24 hours',
  modo_leitura          text not null default 'sombra'    check (modo_leitura  in ('desligado','sombra','ligado')),
  modo_proposta         text not null default 'desligado' check (modo_proposta in ('desligado','sombra','ligado')),
  modo_vigia            text not null default 'desligado' check (modo_vigia    in ('desligado','sombra','ligado')),
  modo_equipe           text not null default 'desligado' check (modo_equipe   in ('desligado','sombra','ligado')),
  modo_cliente          text not null default 'desligado' check (modo_cliente  in ('desligado','sombra','ligado')),
  versao_plano          bigint not null default 0,
  atualizado_em         timestamptz not null default now(),
  atualizado_por        uuid
);

comment on table public.agenda_config is
  'Agenda de Produção: os parâmetros, numa linha só (id = true). O DEFAULT de cada coluna é o único lugar do número: nenhum literal no TS nem nas funções agenda_*/os_*. Muda por SQL com OK do dono.';
comment on column public.agenda_config.dia_do_plano is 'Dia da semana ISO (1 = segunda … 5 = sexta) em que o fechamento traz a semana seguinte. 4 = quinta.';
comment on column public.agenda_config.medicao_semanas is 'Semanas de diárias que a semente de agenda_disponibilidade mede (até a última diária lançada).';
comment on column public.agenda_config.equipe_recente_dias is 'Só entra na semente quem teve diária nesses dias corridos até a última diária lançada (tira quem saiu da equipe pela regra, não pelo nome).';
comment on column public.agenda_config.frequencia_minima is 'Frequência mínima (fração dos dias úteis trabalhados naquele dia da semana) para a semente criar o padrão.';
comment on column public.agenda_config.modo_leitura is 'desligado = sem comandos, fechamento nem sincronização; sombra (nasce) = ferramenta e comandos respondem, o fechamento só registra em resumo_tarde.detalhe; ligado = o fechamento fala.';
comment on column public.agenda_config.versao_plano is 'Contador do plano publicado (Fase 2). Na Fase 1 fica em 0.';

insert into public.agenda_config default values on conflict (id) do nothing;

-- ── 2. Disponibilidade ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_disponibilidade (
  id             uuid primary key default gen_random_uuid(),
  payee_id       uuid references public.payees(id) on delete cascade,
  dias_semana    smallint[],
  periodo        daterange,
  turno          text check (turno in ('manha','tarde')),
  situacao       text not null check (situacao in ('disponivel','indisponivel','confirmada')),
  origem         text not null check (origem in ('historico','dono','diarista','agente')),
  frequencia     numeric(5,4) check (frequencia between 0 and 1),
  nota           text check (char_length(nota) <= 200),
  trecho         text check (char_length(trecho) <= 300),
  substituida_em timestamptz,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  constraint padrao_ou_excecao       check (num_nonnulls(dias_semana, periodo) = 1),
  constraint dias_validos            check (dias_semana is null or (dias_semana <@ '{1,2,3,4,5,6}' and cardinality(dias_semana) > 0)),
  constraint periodo_nao_vazio       check (periodo is null or not isempty(periodo)),
  constraint padrao_tem_pessoa       check (dias_semana is null or payee_id is not null),
  constraint frequencia_so_historico check ((frequencia is not null) = (origem = 'historico'))
);

create index if not exists agenda_disp_pessoa on public.agenda_disponibilidade(payee_id) where substituida_em is null;

comment on table public.agenda_disponibilidade is
  'Agenda de Produção: quem vem quando. Padrão por dia da semana (dias_semana, ISO 1..6) OU exceção por data (periodo). turno nulo = o dia inteiro; payee_id nulo = todos (recesso). Leitura: exceção indisponível > exceção confirmada > exceção disponível > padrão (o mais novo vence no empate). Linha trocada ganha substituida_em, não é apagada.';
comment on column public.agenda_disponibilidade.frequencia is 'Só na origem historico (a semente das diárias): fração dos dias úteis em que a pessoa trabalhou naquele dia da semana.';
comment on column public.agenda_disponibilidade.trecho is 'As palavras do dono (ou do diarista) que deram origem à linha.';

-- ── 3. Plano de serviço por OS: o que o dono disse ───────────────────────────────────────────────────────
create table if not exists public.os_planejamento (
  service_order_id      uuid primary key references public.service_orders(id) on delete cascade,
  dias                  numeric(4,1) check (dias > 0 and dias <= 60 and dias * 2 = trunc(dias * 2)),
  estimativa_fonte      text check (estimativa_fonte in ('dono','aceita')),
  estimativa_em         timestamptz,
  dono_presenca         text check (dono_presenca in ('abre_e_fecha','sempre','nunca')),
  precisa_ate           date,
  bem_indisponivel      datemultirange not null default '{}',
  nao_antes_de          date,
  nao_antes_motivo      text check (char_length(nao_antes_motivo) <= 120),
  escopo_em_aberto      text check (char_length(escopo_em_aberto) <= 160),
  escopo_decidido       text check (char_length(escopo_decidido) <= 160),
  congelada_ate         date,
  revisar_em            date,
  prioridade_manual     smallint check (prioridade_manual between 1 and 3),
  material_conferido_em timestamptz,
  trecho                text check (char_length(trecho) <= 500),
  historico             jsonb not null default '[]'
    check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  atualizado_em         timestamptz not null default now(),
  atualizado_por        uuid,
  constraint fonte_coerente     check ((dias is null) = (estimativa_fonte is null)),
  constraint motivo_coerente    check ((nao_antes_de is null) = (nao_antes_motivo is null)),
  constraint espera_tem_revisao check (congelada_ate is null or revisar_em is not null)
);

comment on table public.os_planejamento is
  'Agenda de Produção: o que o dono DISSE da OS (dias de calendário, presença dele, prazo do cliente, bem fora, escopo, espera, "não tem peça a comprar"). O derivado (meios-dias, estado, prontidão) é calculado na leitura. Escreve-se só pelo *grava* do dono (agenda_rascunho_gravar).';
comment on column public.os_planejamento.dias is 'Dias de calendário que o dono disse (meio dia em meio dia). A sugestão do banco nunca é gravada aqui sem o dono aceitar (estimativa_fonte aceita).';
comment on column public.os_planejamento.dono_presenca is 'null = a regra (abre e fecha; sempre em diagnóstico, comissionamento ou marina nova).';
comment on column public.os_planejamento.material_conferido_em is 'Quando o dono disse que não tem (mais) peça a comprar.';

-- ── 3b. Quem vai, por turno ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.os_planejamento_equipe (
  service_order_id uuid not null references public.os_planejamento(service_order_id) on delete cascade,
  payee_id         uuid not null references public.payees(id),
  turnos           text not null check (turnos in ('dia','manha','tarde')),
  criado_em        timestamptz not null default now(),
  primary key (service_order_id, payee_id)
);

comment on table public.os_planejamento_equipe is
  'Agenda de Produção: quem vai na OS e em que turno (dia, manhã, tarde), como o dono disse. O dono também pode estar aqui.';

-- ── 4. Material por linha da OS: fatos ──────────────────────────────────────────────────────────────────
create table if not exists public.os_material (
  id                       uuid primary key default gen_random_uuid(),
  service_order_id         uuid not null references public.service_orders(id) on delete cascade,
  service_order_part_id    uuid references public.service_order_parts(id) on delete cascade,
  service_order_service_id uuid references public.service_order_services(id) on delete cascade,
  -- CASCADE, não SET NULL (P2): a linha de origem 'oc' exige o item (CHECK origem_coerente), e com SET NULL
  -- o "remover item" da OC seria recusado pelo CHECK. Item apagado = linha apagada, como peça e serviço.
  purchase_order_item_id   uuid references public.purchase_order_items(id) on delete cascade,
  origem                   text not null check (origem in ('peca','texto_livre','oc','dono')),
  descricao                text not null check (char_length(descricao) <= 200),
  quantidade_necessaria    numeric(10,3) not null check (quantidade_necessaria > 0),
  quantidade_na_mao        numeric(10,3) not null default 0 check (quantidade_na_mao >= 0),
  critico                  boolean not null default true,
  situacao                 text not null default 'falta'
    check (situacao in ('falta','comprado','a_caminho','na_mao','dispensado')),
  fonte                    text check (fonte in ('dono','fornecedor','nfe','oc','pix','estoque')),
  fornecedor_id            uuid references public.suppliers(id),
  fornecedor_nome          text check (char_length(fornecedor_nome) <= 80),
  compra_prevista_em       date,
  comprado_em              date,
  previsao_de              date,
  previsao_ate             date,
  previsao_original        date,
  previsao_fonte           text check (previsao_fonte in ('dono','fornecedor','nfe','oc','pix')),
  chegou_em                date,
  trecho                   text check (char_length(trecho) <= 300),
  evidencia                jsonb not null default '{}' check (jsonb_typeof(evidencia) = 'object'),
  historico                jsonb not null default '[]'
    check (case when jsonb_typeof(historico) = 'array' then jsonb_array_length(historico) <= 20 else false end),
  conferido_em             timestamptz,
  atualizado_em            timestamptz not null default now(),
  atualizado_por           uuid,
  constraint um_vinculo               check (num_nonnulls(service_order_part_id, service_order_service_id, purchase_order_item_id) <= 1),
  constraint origem_coerente          check ((origem = 'peca') = (service_order_part_id is not null)
                                         and (origem <> 'texto_livre' or service_order_service_id is not null)
                                         and (origem <> 'oc' or purchase_order_item_id is not null)
                                         and (origem <> 'dono' or (service_order_part_id is null and purchase_order_item_id is null))),
  constraint na_mao_completo          check (situacao <> 'na_mao' or (quantidade_na_mao = quantidade_necessaria and chegou_em is not null)),
  constraint quantidade_coerente      check (quantidade_na_mao <= quantidade_necessaria),
  constraint completo_e_na_mao        check (situacao in ('na_mao','dispensado') or quantidade_na_mao < quantidade_necessaria),
  constraint falta_sem_previsao       check (situacao <> 'falta' or previsao_ate is null),
  constraint compra_prevista_so_falta check (compra_prevista_em is null or situacao = 'falta'),
  constraint previsao_tem_fonte       check ((previsao_ate is null) = (previsao_fonte is null)),
  constraint faixa_coerente           check (previsao_de is null or (previsao_ate is not null and previsao_de <= previsao_ate))
);

create unique index if not exists os_material_peca  on public.os_material(service_order_part_id)    where service_order_part_id is not null;
create unique index if not exists os_material_oc    on public.os_material(purchase_order_item_id)   where purchase_order_item_id is not null;
create unique index if not exists os_material_livre on public.os_material(service_order_service_id) where origem = 'texto_livre';
create index if not exists os_material_os on public.os_material(service_order_id);

comment on table public.os_material is
  'Agenda de Produção: o fato de cada linha de material da OS (peça, texto livre, item de OC de texto livre da própria OS, ou linha que o dono citou). O nível A–E é derivado na leitura. Zero linhas = material não conferido, nunca completo. critico false = pode começar sem. Escreve-se só pelo sincronizador e pelo *grava* do dono.';
comment on column public.os_material.fonte is 'De onde veio o fato: dono, fornecedor, nfe, oc, pix ou estoque. null = linha só sincronizada, nunca confirmada.';
comment on column public.os_material.compra_prevista_em is '"Compro terça na Premel": a compra combinada (não é previsão de chegada; só com a situação falta).';
comment on column public.os_material.trecho is 'As palavras do dono que deram origem ao fato.';

-- ── 5. Rascunho da conversa ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.agenda_rascunho (
  id               uuid primary key default gen_random_uuid(),
  autor            uuid not null references public.app_users(id) on delete cascade,
  canal            text not null check (canal in ('whatsapp','painel')),
  tipo             text not null check (tipo in ('planejar','material','disponibilidade')),
  chave            text not null check (char_length(chave) <= 200),
  service_order_id uuid references public.service_orders(id) on delete cascade,
  dados            jsonb not null,
  texto            text not null check (char_length(texto) <= 300),
  trecho           text check (char_length(trecho) <= 500),
  estado           text not null default 'aberto'
    check (estado in ('aberto','gravado','substituido','descartado','expirado')),
  criado_em        timestamptz not null default now(),
  expira_em        timestamptz not null,
  gravado_em       timestamptz,
  constraint expira_depois check (expira_em > criado_em)
);

create unique index if not exists agenda_rascunho_um_por_chave on public.agenda_rascunho(autor, chave) where estado = 'aberto';
create index if not exists agenda_rascunho_aberto on public.agenda_rascunho(autor, criado_em) where estado = 'aberto';

comment on table public.agenda_rascunho is
  'Agenda de Produção: o que o dono disse na conversa e ainda não mandou gravar. Uma linha aberta por chave (planejar:<os>, material:<linha>, disp:<pessoa>:<quando>:<turno>); a correção substitui. Só o *grava* do dono (agenda_rascunho_gravar) transforma em fato.';

-- ── Portas: RLS, só leitura para admin/financeiro, escrita só pelas RPCs ───────────────────────────────
alter table public.agenda_config          enable row level security;
alter table public.agenda_disponibilidade enable row level security;
alter table public.os_planejamento        enable row level security;
alter table public.os_planejamento_equipe enable row level security;
alter table public.os_material            enable row level security;
alter table public.agenda_rascunho        enable row level security;

drop policy if exists agenda_config_leitura on public.agenda_config;
create policy agenda_config_leitura on public.agenda_config
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_disponibilidade_leitura on public.agenda_disponibilidade;
create policy agenda_disponibilidade_leitura on public.agenda_disponibilidade
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists os_planejamento_leitura on public.os_planejamento;
create policy os_planejamento_leitura on public.os_planejamento
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists os_planejamento_equipe_leitura on public.os_planejamento_equipe;
create policy os_planejamento_equipe_leitura on public.os_planejamento_equipe
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists os_material_leitura on public.os_material;
create policy os_material_leitura on public.os_material
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists agenda_rascunho_leitura on public.agenda_rascunho;
create policy agenda_rascunho_leitura on public.agenda_rascunho
  for select to authenticated using (autor = (select auth.uid()) and public.is_admin((select auth.uid())));

revoke all on table public.agenda_config, public.agenda_disponibilidade, public.os_planejamento,
  public.os_planejamento_equipe, public.os_material, public.agenda_rascunho from public, anon, authenticated;
grant select on table public.agenda_config, public.agenda_disponibilidade, public.os_planejamento,
  public.os_planejamento_equipe, public.os_material, public.agenda_rascunho to authenticated;
grant all on table public.agenda_config, public.agenda_disponibilidade, public.os_planejamento,
  public.os_planejamento_equipe, public.os_material, public.agenda_rascunho to service_role;
