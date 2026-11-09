-- Retorno rápido ao cliente, F3 (P1): a base do orçamento sem espera.
--
-- 1. retorno_config ganha as chaves e as réguas da F3. Tudo nasce desligado: previa_modo = 'desligado', previa_ditado_ligado = false.
--    Proposta 'ligado' exige o ditado ligado (check): sem letras e sem ditado, o cartão não teria como ajustar nem aprovar.
-- 2. retorno_aberturas ganha visita_a_combinar_em (*precisa ver no local* saiu ao cliente: o caso fica na lista até o dono resolver,
--    rr-f1-10) e unidade_escolhida_id (a letra de unidade do dono; vale antes da busca por nome).
-- 3. Os checks fechados ganham os valores novos: tipo 'modelo_ver_no_local', motivo 'visita_a_combinar' e seis caiu_motivo.
-- 4. retorno_previa e retorno_previa_linhas: a proposta, que NÃO é OS. Nasce do orçamento parecido; o ORÇ só nasce no ato do dono.
--    Dois índices únicos: uma 'sombra' e uma 'proposta' do mesmo caso convivem (ditado na semana de sombra, P6.2).
-- 5. retorno_cartao_itens ganha previa_id e acao_sim (o que o *sim <PIN>* faz neste item; nulo = regra da F2).
-- 6. service_orders ganha origem, origem_chave8 e origem_parceiro_id (sem FK: parceiros é da F4). Sem default nem backfill:
--    nulo = tela e assistente livre. O grant de anon em service_orders é por coluna: as três nascem fechadas sem nada a fazer.
--
-- Sem dado novo. DDL em service_orders: na bancada só de madrugada (P12).
-- Reverter sem deploy: update public.retorno_config set previa_modo = 'desligado', previa_ditado_ligado = false. As tabelas ficam.

alter table public.retorno_config
  add column previa_modo text not null default 'desligado' check (previa_modo in ('desligado', 'sombra', 'ligado')),
  add column previa_ditado_ligado boolean not null default false,  -- letras L e de unidade, ditado e PDF do rascunho
  add column previa_max_linhas smallint not null default 12 check (previa_max_linhas between 1 and 40),
  add column previa_idade_max interval not null default '18 months',
  add column previa_preco_velho interval not null default '180 days',
  add column validade_orcamento_dias smallint not null default 7 check (validade_orcamento_dias between 1 and 60),  -- K6
  add constraint retorno_config_proposta_exige_ditado check (previa_modo <> 'ligado' or previa_ditado_ligado);

alter table public.retorno_aberturas
  add column visita_a_combinar_em timestamptz,   -- *precisa ver no local* saiu ao cliente: o caso fica na lista até o dono resolver (rr-f1-10)
  add column unidade_escolhida_id uuid references public.vessels(id) on delete set null;   -- a letra de unidade do dono neste caso (P6.1); vale antes da busca por nome

-- Os checks ganham os valores novos (lista fechada, como na F2).
alter table public.retorno_saidas drop constraint retorno_saidas_tipo_check;
alter table public.retorno_saidas add constraint retorno_saidas_tipo_check check (tipo in (
  'recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo', 'saudacao_numero_novo', 'adiamento',
  'fim_do_dia', 'urgente', 'parar', 'cadastro_provisorio', 'acorde', 'fila',
  'modelo_aguarda_peca', 'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico', 'modelo_liberado',
  'modelo_retirada_nao', 'modelo_ver_no_local'));
alter table public.retorno_saidas drop constraint retorno_saidas_motivo_check;
alter table public.retorno_saidas add constraint retorno_saidas_motivo_check check (motivo in (
  'respondida_pelo_dono', 'caso_fechado', 'caso_vencido', 'nivel_nada', 'rajada', 'lote_global', 'aguarda_transcricao',
  'fora_da_janela', 'espacamento', 'teto_numero', 'teto_dia', 'teto_coleta', 'teto_saudacao', 'teto_volta',
  'atraso_longo', 'bloqueado', 'opt_out', 'cliente_final', 'pessoal', 'equipe', 'so_reativo', 'segura_tudo',
  'segura_recibos', 'tipo_desligado', 'modo', 'urgente_desligado', 'validador', 'texto', 'canal', 'provedor',
  'reserva', 'erro', 'substituida', 'sem_config', 'classe_nao_suportada', 'sem_numero',
  'agenda_ja_acordou', 'duplicado_pergunta', 'sem_nome', 'recusaria_fila',
  'guardado_no_portao', 'acorde_repetido', 'fato_mudou', 'visita_a_combinar'));
alter table public.retorno_cartao_itens drop constraint retorno_cartao_itens_caiu_motivo_check;
alter table public.retorno_cartao_itens add constraint retorno_cartao_itens_caiu_motivo_check check (caiu_motivo in (
  'respondida_pelo_dono', 'caso_fechado', 'fato_mudou', 'telefone_mudou', 'canal_bloqueado',
  'item_provisorio', 'sem_cadastro', 'contato_diferente', 'orc_existe', 'cliente_final', 'rascunho_sem_valor'));

create table public.retorno_previa (
  id uuid primary key default gen_random_uuid(),
  abertura_id uuid not null references public.retorno_aberturas(id) on delete cascade,
  chave text not null check (chave ~ '^[0-9]{8}$'),
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  origem text not null check (origem in ('historico', 'ditado', 'rascunho')),   -- rascunho: PDF de ORÇ que já existia, linha gravada só ao sair (P6)
  fonte_os_id uuid references public.service_orders(id) on delete set null,
  fonte_numero text,
  fonte_em timestamptz,
  familias text[] not null default '{}',
  titulo text not null check (char_length(titulo) <= 120),
  estado text not null check (estado in ('sombra', 'proposta', 'virou_orc', 'ver_no_local', 'descartada', 'caiu')),
  modo text not null check (modo in ('sombra', 'ligado')),   -- origem 'historico': o previa_modo do nascimento; origem 'ditado' e 'rascunho': sempre 'ligado'
  total numeric(14,2) not null default 0,
  linhas_n smallint not null default 0,
  provisorios_n smallint not null default 0,
  preco_mais_antigo date,          -- a data que vai no cartão
  linhas_iniciais jsonb not null default '[]' check (jsonb_typeof(linhas_iniciais) = 'array'),   -- a foto da proposta como nasceu; retorno_previa_aplicar nunca toca (P11)
  hash text not null,
  condicao_pagamento text check (char_length(condicao_pagamento) <= 300),
  service_order_id uuid references public.service_orders(id) on delete set null,   -- o ORÇ nascido
  pdf_em timestamptz,
  pdf_chave text,                  -- a chave do telefone que recebeu de fato, devolvida pelo envio
  dados jsonb not null default '{}' check (jsonb_typeof(dados) = 'object'),   -- {alternativas: [{os_id, numero, em}], unidades: [{numero, vessel_id, nome}], motivo, forte, fonte_aprovada, travada, ajustada_por_ditado}
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  decidida_em timestamptz
);
create unique index retorno_previa_uma_sombra on public.retorno_previa (abertura_id) where estado = 'sombra';
create unique index retorno_previa_uma_proposta on public.retorno_previa (abertura_id) where estado = 'proposta';   -- dois índices: sombra e proposta do mesmo caso convivem (ditado na semana de sombra, P6.2)
create index retorno_previa_por_dia on public.retorno_previa (criada_em);
create index retorno_previa_por_orc on public.retorno_previa (service_order_id) where service_order_id is not null;

create table public.retorno_previa_linhas (
  id uuid primary key default gen_random_uuid(),
  previa_id uuid not null references public.retorno_previa(id) on delete cascade,
  ordem smallint not null,
  tipo text not null check (tipo in ('peca', 'servico')),
  product_id uuid references public.products(id) on delete set null,
  service_id uuid references public.services(id) on delete set null,
  nome text not null check (char_length(nome) <= 200),
  quantidade numeric(12,3) not null check (quantidade > 0),
  preco numeric(14,2) check (preco is null or preco > 0),   -- nulo = sem preço; zero nunca é preço
  preco_fonte text not null check (preco_fonte in ('praticado_cliente', 'praticado_outro', 'orcado_cliente', 'orcado_outro', 'catalogo', 'dito', 'sem_preco')),
  preco_em date,                   -- a data do preço; nula em catálogo e dito
  estado text not null check (estado in ('ok', 'assumido', 'provisorio')),
  motivo text,                     -- provisório: sem_preco, preco_invalido, nome_com_dado_de_outro ou inativo; assumido: 'pedido: <o que o dono disse>' ou sem_catalogo
  unique (previa_id, ordem)
);

alter table public.retorno_cartao_itens
  add column previa_id uuid references public.retorno_previa(id) on delete set null,
  add column acao_sim text check (acao_sim in ('orcar', 'pdf'));   -- o que o *sim <PIN>* faz neste item; nulo = regra da F2

alter table public.service_orders
  add column origem text check (origem in ('retorno_previa', 'retorno_ditado')),
  add column origem_chave8 text check (origem_chave8 ~ '^[0-9]{8}$'),
  add column origem_parceiro_id uuid;   -- sem FK: parceiros é da F4

comment on table public.retorno_previa is
  'Retorno F3: a proposta de orçamento do caso, nascida do parecido ou do ditado. Não é OS: o ORÇ só nasce no ato do dono (sim com PIN).';
comment on table public.retorno_previa_linhas is
  'Retorno F3: as linhas da proposta, com a origem e a data do preço. Zero nunca é preço.';
comment on column public.service_orders.origem is
  'Retorno F3: de onde o orçamento veio (retorno_previa ou retorno_ditado). Nulo = tela e assistente livre.';
comment on column public.service_orders.origem_chave8 is
  'Retorno F3: a chave de 8 dígitos do telefone do caso que originou o orçamento.';
comment on column public.service_orders.origem_parceiro_id is
  'Retorno F3: reservada para a F4 (parceiros). Sem FK: a tabela ainda não existe.';

-- Leitura só no painel de admin e financeiro; escrita só o service_role; anon nada.
alter table public.retorno_previa enable row level security;
alter table public.retorno_previa_linhas enable row level security;

drop policy if exists retorno_previa_leitura on public.retorno_previa;
create policy retorno_previa_leitura on public.retorno_previa
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_previa_linhas_leitura on public.retorno_previa_linhas;
create policy retorno_previa_linhas_leitura on public.retorno_previa_linhas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.retorno_previa, public.retorno_previa_linhas from public, anon, authenticated;
grant select on table public.retorno_previa, public.retorno_previa_linhas to authenticated;
grant all on table public.retorno_previa, public.retorno_previa_linhas to service_role;
