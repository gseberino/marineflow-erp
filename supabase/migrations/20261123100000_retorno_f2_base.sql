-- Retorno rápido ao cliente, F2 (Pacote 1): a base do cartão único, das palavras do dono e dos modelos com fato.
--
-- 1. retorno_config ganha as chaves e as réguas da F2. Tudo nasce desligado: cartao_ligado = false faz *retorno*
--    mostrar lista sem pendência; carona_ligada = false, variantes_ligadas = false.
-- 2. Os checks da F1 ganham os valores novos, e dois checks de grupo entram:
--    - urgente e acorde são um grupo só: um sem o outro prometeria o que ninguém cumpre;
--    - meio-dia prometido sem urgente tira do ar os recibos da manhã (o recibo das 07:00 às 10:59 passa a prometer
--      14h, com X2 = 19h; adiamento com X2 oferece URGENTE; sem urgente, _retorno_modo_efetivo devolve caso_sem_aviso).
--      O check olha modo = 'ligado' porque os testes da F1 ligam o meio-dia em sombra.
-- 3. retorno_modelo_tipos: os 5 tipos de modelo com fato. As 5 linhas, todas em nível 'desligado', são o único dado da
--    migration. modelo_retirada_nao fica fora de propósito: não é promovível, só sai pela opção B do cartão.
-- 4. retorno_cartoes e retorno_cartao_itens: o cartão único. O texto TEM palavras do cliente e nunca vai a
--    ai_operator_messages. No máximo 1 cartão vivo (índice único) e 1 meio-dia por dia que não tenha falhado.
-- 5. retorno_toques: cada resposta do dono a um cartão é um toque novo; a meta é 3 ou menos por dia útil.
-- 6. service_orders.liberado_retirada_em e _por: a marca de *libera <cliente>*. Nunca é status, vence em
--    liberado_validade, e nasce fechada ao anônimo porque o grant de service_orders é por coluna.
--
-- Reverter sem deploy: update public.retorno_config set cartao_ligado = false, carona_ligada = false,
-- variantes_ligadas = false; update public.retorno_modelo_tipos set nivel = 'desligado'. As tabelas ficam.

alter table public.retorno_config
  add column cartao_ligado boolean not null default false,          -- false: *retorno* mostra lista, sem pendência
  add column cartao_max_itens smallint not null default 3 check (cartao_max_itens between 1 and 3),
  add column cartao_validade interval not null default '24 hours',
  add column carona_ligada boolean not null default false,          -- K5
  add column carona_intervalo interval not null default '30 minutes',
  add column carona_em timestamptz,                                 -- a última carona do retorno
  add column modelo_dias_aprovacao smallint not null default 3 check (modelo_dias_aprovacao between 1 and 10),  -- K7
  add column modelo_usos_liberado smallint not null default 3 check (modelo_usos_liberado between 1 and 10),
  add column modelo_repete_fato interval not null default '24 hours',
  add column fato_pronto_idade interval not null default '48 hours',
  add column fato_servico_idade interval not null default '24 hours',
  add column fato_peca_idade interval not null default '7 days',
  add column auditoria_cada smallint not null default 10 check (auditoria_cada between 2 and 50),
  add column fadiga_s smallint not null default 3,
  add column fadiga_vezes smallint not null default 3,
  add column fadiga_suspende interval not null default '7 days',
  add column rebaixa_edicao_pct numeric(3,2) not null default 0.20,
  add column cartao_tentativas smallint not null default 3,
  add column variantes_ligadas boolean not null default false,      -- T29–T35 mudam texto ao cliente: nascem desligadas
  add column liberado_validade interval not null default '14 days', -- *libera* vence: delivered_at nunca é preenchido
  add column pessoal_ultimo jsonb;                                  -- a volta do *pessoal*: {phone, lead_tipo_antes, em}

-- Os checks da F1 ganham os valores novos (lista fechada, sem not valid: as tabelas nascem vazias ou quase).
alter table public.retorno_config drop constraint retorno_config_tipos_ligados_check;
alter table public.retorno_config add constraint retorno_config_tipos_ligados_check check (tipos_ligados <@ array[
  'recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo', 'saudacao_numero_novo', 'adiamento',
  'fim_do_dia', 'parar', 'cadastro_provisorio', 'urgente', 'acorde']::text[]);
alter table public.retorno_config add constraint retorno_config_grupo_acorde
  check (('urgente' = any (tipos_ligados)) = ('acorde' = any (tipos_ligados)));
alter table public.retorno_config add constraint retorno_config_meio_dia_urgente
  check (not meio_dia_ligado or modo <> 'ligado' or 'urgente' = any (tipos_ligados));

alter table public.retorno_aberturas drop constraint retorno_aberturas_cumprida_por_check;
alter table public.retorno_aberturas add constraint retorno_aberturas_cumprida_por_check
  check (cumprida_por in ('celular', 'tela', 'assistente', 'cartao', 'modelo'));

alter table public.retorno_saidas drop constraint retorno_saidas_tipo_check;
alter table public.retorno_saidas add constraint retorno_saidas_tipo_check check (tipo in (
  'recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo', 'saudacao_numero_novo', 'adiamento',
  'fim_do_dia', 'urgente', 'parar', 'cadastro_provisorio', 'acorde', 'fila',
  'modelo_aguarda_peca', 'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico', 'modelo_liberado',
  'modelo_retirada_nao'));
alter table public.retorno_saidas drop constraint retorno_saidas_origem_check;
alter table public.retorno_saidas add constraint retorno_saidas_origem_check
  check (origem in ('retorno_recibo', 'retorno_coleta', 'retorno_adiamento', 'retorno_modelo'));
alter table public.retorno_saidas drop constraint retorno_saidas_motivo_check;
alter table public.retorno_saidas add constraint retorno_saidas_motivo_check check (motivo in (
  'respondida_pelo_dono', 'caso_fechado', 'caso_vencido', 'nivel_nada', 'rajada', 'lote_global', 'aguarda_transcricao',
  'fora_da_janela', 'espacamento', 'teto_numero', 'teto_dia', 'teto_coleta', 'teto_saudacao', 'teto_volta',
  'atraso_longo', 'bloqueado', 'opt_out', 'cliente_final', 'pessoal', 'equipe', 'so_reativo', 'segura_tudo',
  'segura_recibos', 'tipo_desligado', 'modo', 'urgente_desligado', 'validador', 'texto', 'canal', 'provedor',
  'reserva', 'erro', 'substituida', 'sem_config', 'classe_nao_suportada', 'sem_numero',
  'agenda_ja_acordou', 'duplicado_pergunta', 'sem_nome', 'recusaria_fila',
  'guardado_no_portao', 'acorde_repetido', 'fato_mudou'));

alter table public.retorno_saidas
  add column letra text check (letra in ('Z', 'Y', 'X', 'W', 'V')),   -- do "Mandei sozinho", gravada no envio
  add column letra_dia date;
create unique index retorno_saidas_letra_do_dia on public.retorno_saidas (letra_dia, letra) where letra is not null;

create table public.retorno_modelo_tipos (
  tipo text primary key check (tipo in ('modelo_aguarda_peca', 'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico',
                                        'modelo_liberado')),
  nivel text not null default 'desligado' check (nivel in ('desligado', 'cartao', 'sozinho')),
  regua text not null default 'dias' check (regua in ('dias', 'usos')),   -- modelo_liberado conta usos
  aprovados_dias date[] not null default '{}',
  aprovados_usos smallint not null default 0,
  promovido_em timestamptz,
  promocao_suspensa_ate timestamptz,                                       -- fadiga de aprovação
  rebaixado_em timestamptz,
  rebaixado_motivo text check (rebaixado_motivo in ('errado', 'queixa', 'opt_out', 'edicao', 'validador', 'dono')),
  envios_sozinho integer not null default 0,                               -- a conta da auditoria de 1 em 10
  atualizado_em timestamptz not null default now()
);
insert into public.retorno_modelo_tipos (tipo, regua) values
  ('modelo_aguarda_peca', 'dias'), ('modelo_peca_chegou', 'dias'), ('modelo_pronto', 'dias'), ('modelo_em_servico', 'dias'),
  ('modelo_liberado', 'usos')
on conflict (tipo) do nothing;

create table public.retorno_cartoes (
  id uuid primary key default gen_random_uuid(),
  gatilho text not null check (gatilho in ('puxar', 'meio_dia', 'acorde')),
  dia date not null,                 -- dia local do cartão
  estado text not null check (estado in ('lista', 'vivo', 'decidido', 'caiu', 'expirou', 'falhou')),
  sessao_id uuid references public.ai_operator_sessions(id) on delete set null,
  pendencia_id uuid unique,          -- ai_operator_pending_actions.id (sem FK: a limpeza de pendências é de outra rotina)
  pergunta_id uuid,                  -- whatsapp_perguntas.id
  aviso_id uuid,                     -- avisos_do_dono.id (meio-dia e acorde)
  hash text not null,
  texto text not null check (char_length(texto) <= 3500),   -- TEM texto do cliente. Nunca vai a ai_operator_messages
  mais smallint not null default 0,  -- os que ficaram de fora ("e mais N")
  tentativas smallint not null default 0,
  criado_em timestamptz not null default now(),
  enviado_em timestamptz,
  expira_em timestamptz not null,
  decidido_em timestamptz,
  decidido_por text check (decidido_por in ('sim_pin', 'nao', 'painel')),
  caiu_motivo text,
  dados jsonb not null default '{}' check (jsonb_typeof(dados) = 'object')
);
create unique index retorno_cartoes_um_vivo on public.retorno_cartoes ((true)) where estado = 'vivo';
create index retorno_cartoes_por_dia on public.retorno_cartoes (criado_em);
create unique index retorno_cartoes_meio_dia_um on public.retorno_cartoes (gatilho, dia)   -- duas rodadas não mandam as 12:30 duas vezes
  where gatilho = 'meio_dia' and estado <> 'falhou';

create table public.retorno_cartao_itens (
  id uuid primary key default gen_random_uuid(),
  cartao_id uuid not null references public.retorno_cartoes(id) on delete cascade,
  n smallint not null check (n between 1 and 3),
  abertura_id uuid not null references public.retorno_aberturas(id) on delete cascade,
  tipo_item text not null check (tipo_item in ('modelo', 'peca_sem_registro', 'pronto_sem_palavra', 'retirada', 'ambiguo',
                                               'numero_novo', 'orcamento', 'adicional', 'livre')),
  modelo_tipo text,                  -- o tipo de saída que o sim <PIN> cria (modelo_*); null = o sim não manda nada neste item
  service_order_id uuid references public.service_orders(id) on delete set null,
  texto_mostrado text,               -- o texto exato que iria ao cliente (a trava por hash)
  opcoes jsonb not null default '[]' check (jsonb_typeof(opcoes) = 'array'),   -- [{"letra", "rotulo", "acao", ...}]
  fatos jsonb not null default '{}' check (jsonb_typeof(fatos) = 'object'),     -- o retrato do fato (só colunas da lista positiva)
  hash text not null,
  estado text not null default 'vivo' check (estado in ('vivo', 'fora', 'feito', 'caiu')),
  selecionado boolean not null default true,   -- *só*, *sem* e *não N* mexem aqui; *retorno* restaura; só o *sim <PIN>* consome
  escolha text,                      -- a letra escolhida
  texto_ditado text check (char_length(texto_ditado) <= 1000),
  ditado_via text check (ditado_via in ('dita', 'assistente')),
  decidido_em timestamptz,
  caiu_motivo text check (caiu_motivo in ('respondida_pelo_dono', 'caso_fechado', 'fato_mudou', 'telefone_mudou',
                                          'canal_bloqueado')),
  saida_id uuid references public.retorno_saidas(id) on delete set null,
  unique (cartao_id, n)
);
create index retorno_cartao_itens_por_caso on public.retorno_cartao_itens (abertura_id);

create table public.retorno_toques (                -- cada resposta do dono a um cartão é um toque novo
  id uuid primary key default gen_random_uuid(),
  em timestamptz not null default now(),
  cartao_id uuid references public.retorno_cartoes(id) on delete set null,
  abertura_id uuid references public.retorno_aberturas(id) on delete set null,
  palavra text not null check (palavra in ('sim_pin', 'nao', 'letra', 'dita', 'so', 'sem', 'tirar', 'ver', 'pessoal',
                                           'errado', 'libera')),
  latencia_s integer,                               -- do envio do cartão até esta resposta
  rapido boolean not null default false             -- menos de fadiga_s
);
create index retorno_toques_por_dia on public.retorno_toques (em);

alter table public.service_orders
  add column liberado_retirada_em timestamptz,
  add column liberado_retirada_por uuid references public.app_users(id) on delete set null;
comment on column public.service_orders.liberado_retirada_em is
  'Retorno F2: *libera <cliente>*. Com isto preenchido, "posso retirar?" pode ser respondido pelo modelo. Só o dono marca. Nunca é status.';

-- Leitura só no painel de admin e financeiro; escrita só o service_role; anon nada.
alter table public.retorno_modelo_tipos enable row level security;
alter table public.retorno_cartoes enable row level security;
alter table public.retorno_cartao_itens enable row level security;
alter table public.retorno_toques enable row level security;

drop policy if exists retorno_modelo_tipos_leitura on public.retorno_modelo_tipos;
create policy retorno_modelo_tipos_leitura on public.retorno_modelo_tipos
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_cartoes_leitura on public.retorno_cartoes;
create policy retorno_cartoes_leitura on public.retorno_cartoes
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_cartao_itens_leitura on public.retorno_cartao_itens;
create policy retorno_cartao_itens_leitura on public.retorno_cartao_itens
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_toques_leitura on public.retorno_toques;
create policy retorno_toques_leitura on public.retorno_toques
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.retorno_modelo_tipos, public.retorno_cartoes, public.retorno_cartao_itens,
                    public.retorno_toques
  from public, anon, authenticated;
grant select on table public.retorno_modelo_tipos, public.retorno_cartoes, public.retorno_cartao_itens,
                      public.retorno_toques
  to authenticated;
grant all on table public.retorno_modelo_tipos, public.retorno_cartoes, public.retorno_cartao_itens,
                   public.retorno_toques
  to service_role;
