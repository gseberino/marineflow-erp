-- Retorno rápido ao cliente, F4 (P1): a base do parceiro (a MP). Nada liga aqui.
--
-- 1. retorno_config ganha as chaves e as réguas da F4. Tudo nasce desligado ou no padrão seguro (seção 10 da spec):
--    parceiro_modo = 'desligado', nenhum tipo em parceiro_tipos_ligados, pdf_parceiro_ligado e pdf_sem_espera_ligado falsos,
--    pdf_mao_modo = 'desligado', parceiro_cadastro_ligado falso, parceiro_historico_na_ia falso.
-- 2. Os checks fechados ganham os valores do parceiro: emissor 'parceiro'; os 11 tipos parceiro_*; as origens retorno_parceiro e
--    retorno_aviso; as classes aviso e resumo_parceiro; 11 motivos (numero_compartilhado inclusive); o papel 'parceiro' e o tipo de
--    recibo 'recibo_parceiro' do caso. O limite de tamanho do texto vai a 1.500 só para emissor 'parceiro' (painel e pátio); as
--    outras saídas continuam em 600.
-- 3. As 9 tabelas: parceiros, parceiro_pessoas, parceiro_numeros e os_interessados (o vínculo OS × parceiro, molde
--    pagadores_do_cliente), e as de apoio parceiro_vetos (NÃO MP, sem OS: vale para as seguintes), parceiro_cliente_sabe,
--    parceiro_paineis, parceiro_fila (o que espera o dono mandar *parceiro*) e parceiro_pedidos (C13, um por caso).
--    parceiro_pedidos e parceiro_fila nascem aqui para _parceiro_triar e os produtores da fila rodarem desde a onda deles.
-- 4. service_orders.origem_parceiro_id ganha a FK reservada pela F3, e o check de origem aceita 'retorno_parceiro'. As duas
--    constraints nascem not valid e são validadas em seguida, para não segurar service_orders (tabela quente).
-- 5. _parceiro_fila_por: a porta única da fila. Prioridade pelo tipo; chave repetida só atualiza dados e validade, e o estado
--    só volta a 'espera' de 'caiu'. A exceção é p_reabrir, aceito só em 'pedido', que leva 'feito' a 'espera'.
--
-- RLS nas 9 tabelas: leitura só de admin e financeiro, escrita só do service_role; anon nada. O grant de anon em service_orders
-- é por coluna: origem_parceiro_id já nasce fechada.
--
-- Sem dado, salvo a troca dos checks. DDL em service_orders: na bancada só de madrugada (seção 7.4, F4_DDL_QUENTE).
-- Reverter sem deploy: update public.retorno_config set parceiro_modo = 'desligado', pdf_mao_modo = 'desligado',
-- parceiro_cadastro_ligado = false. As tabelas ficam.

alter table public.retorno_config
  add column parceiro_modo text not null default 'desligado' check (parceiro_modo in ('desligado', 'sombra', 'ligado')),
  add column parceiro_tipos_ligados text[] not null default '{}' check (parceiro_tipos_ligados <@ array[
    'parceiro_ativacao', 'parceiro_recibo', 'parceiro_coleta', 'parceiro_aviso_cliente', 'parceiro_nao_mp_ok',
    'parceiro_painel', 'parceiro_patio', 'parceiro_eco', 'parceiro_pausa', 'parceiro_repassar', 'parceiro_recado']::text[]),
  add column painel_nivel text not null default 'fechamento' check (painel_nivel in ('fechamento', 'sozinho')),
  add column patio_nivel text not null default 'cartao' check (patio_nivel in ('cartao', 'direto')),
  add column eco_modo text not null default 'sombra' check (eco_modo in ('sombra', 'ligado')),
  add column segura_patio boolean not null default false,
  add column parceiro_carencia interval not null default '30 minutes',
  add column parceiro_aviso_espera interval not null default '24 hours',
  add column painel_fechamento_hora time not null default '17:30',
  add column painel_hora time not null default '17:45',
  add column painel_janela_fim time not null default '18:30',
  add column painel_dia_max smallint not null default 2 check (painel_dia_max between 1 and 5),
  add column eco_dia_max smallint not null default 2 check (eco_dia_max between 0 and 5),
  add column patio_dia_max smallint not null default 3 check (patio_dia_max between 1 and 10),
  add column patio_recibo_intervalo interval not null default '12 hours',
  add column iniciadas_dia_max smallint not null default 12 check (iniciadas_dia_max between 0 and 50),
  add column parceiro_rodape_intervalo interval not null default '7 days',
  add column parceiro_retencao interval not null default '180 days',
  add column painel_promover_apos smallint not null default 10 check (painel_promover_apos between 3 and 30),
  add column pdf_parceiro_ligado boolean not null default false,   -- o destino de parceiro no send_service_order_link nasce desligado
  add column pdf_sem_espera_ligado boolean not null default false, -- PDF à contratante ou pagadora antes do aviso e das 24 h; só com o OK do dono (dúvida 9)
  add column parceiro_historico_na_ia boolean not null default false, -- false: o assistente não lê a conversa dos números confirmados de parceiro (P12.4)
  add column parceiro_pdf_ate timestamptz,                          -- marca d'água da detecção do PDF à mão (P9)
  add column pdf_mao_modo text not null default 'desligado' check (pdf_mao_modo in ('desligado', 'registrar', 'perguntar')), -- detecção do PDF à mão (P9, dúvida 6)
  add column parceiro_cadastro_ligado boolean not null default false, -- cria clients e vessels reais no C13; nasce desligado (P10, dúvida 5)
  add column parceiro_coleta_espera interval not null default '24 hours', -- silêncio da MP que derruba a coleta (P10)
  add column parceiro_pedido_validade interval not null default '14 days'; -- quanto o item `pedido` espera o dono (P8, P10)

-- ── 2. Os checks fechados, com os valores do parceiro (lista fechada, sem not valid) ─────────────────────────────────────────

alter table public.retorno_saidas drop constraint retorno_saidas_emissor_check;
alter table public.retorno_saidas add constraint retorno_saidas_emissor_check check (emissor in ('retorno', 'fila', 'parceiro'));

alter table public.retorno_saidas drop constraint retorno_saidas_tipo_check;
alter table public.retorno_saidas add constraint retorno_saidas_tipo_check check (tipo in (
  'recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo', 'saudacao_numero_novo', 'adiamento',
  'fim_do_dia', 'urgente', 'parar', 'cadastro_provisorio', 'acorde', 'fila',
  'modelo_aguarda_peca', 'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico', 'modelo_liberado',
  'modelo_retirada_nao', 'modelo_ver_no_local',
  'parceiro_ativacao', 'parceiro_recibo', 'parceiro_coleta', 'parceiro_aviso_cliente', 'parceiro_nao_mp_ok',
  'parceiro_painel', 'parceiro_patio', 'parceiro_eco', 'parceiro_pausa', 'parceiro_repassar', 'parceiro_recado'));

alter table public.retorno_saidas drop constraint retorno_saidas_origem_check;
alter table public.retorno_saidas add constraint retorno_saidas_origem_check
  check (origem in ('retorno_recibo', 'retorno_coleta', 'retorno_adiamento', 'retorno_modelo', 'retorno_parceiro', 'retorno_aviso'));

alter table public.retorno_saidas drop constraint retorno_saidas_classe_check;
alter table public.retorno_saidas add constraint retorno_saidas_classe_check
  check (classe in ('resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro'));

alter table public.retorno_saidas drop constraint retorno_saidas_motivo_check;
alter table public.retorno_saidas add constraint retorno_saidas_motivo_check check (motivo in (
  'respondida_pelo_dono', 'caso_fechado', 'caso_vencido', 'nivel_nada', 'rajada', 'lote_global', 'aguarda_transcricao',
  'fora_da_janela', 'espacamento', 'teto_numero', 'teto_dia', 'teto_coleta', 'teto_saudacao', 'teto_volta',
  'atraso_longo', 'bloqueado', 'opt_out', 'cliente_final', 'pessoal', 'equipe', 'so_reativo', 'segura_tudo',
  'segura_recibos', 'tipo_desligado', 'modo', 'urgente_desligado', 'validador', 'texto', 'canal', 'provedor',
  'reserva', 'erro', 'substituida', 'sem_config', 'classe_nao_suportada', 'sem_numero',
  'agenda_ja_acordou', 'duplicado_pergunta', 'sem_nome', 'recusaria_fila',
  'guardado_no_portao', 'acorde_repetido', 'fato_mudou', 'visita_a_combinar',
  'parceiro_regra', 'veto', 'pausado', 'segura_patio', 'teto_iniciadas', 'teto_painel', 'teto_eco', 'teto_patio',
  'parceiro_desligado', 'cliente_nao_ouviu', 'numero_compartilhado'));

-- O limite de tamanho (não é a constraint retorno_saidas_texto, que exige texto nos estados que saem): 1.500 só para o parceiro.
alter table public.retorno_saidas drop constraint retorno_saidas_texto_check;
alter table public.retorno_saidas add constraint retorno_saidas_texto_check
  check (texto is null or char_length(texto) between 3 and (case when emissor = 'parceiro' then 1500 else 600 end));

alter table public.retorno_aberturas drop constraint retorno_aberturas_papel_check;
alter table public.retorno_aberturas add constraint retorno_aberturas_papel_check check (papel in (
  'cliente', 'cliente_ambiguo', 'cliente_parceiro', 'numero_novo', 'contato_conhecido', 'fornecedor', 'parceiro'));

alter table public.retorno_aberturas drop constraint retorno_aberturas_tipo_recibo_check;
alter table public.retorno_aberturas add constraint retorno_aberturas_tipo_recibo_check check (tipo_recibo in (
  'recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo', 'recibo_parceiro'));

-- ── 3. As tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────────────

create table public.parceiros (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (btrim(nome) <> ''),
  sigla text not null check (sigla ~ '^[A-Za-zÀ-ÿ]{2,12}$'),
  tipo text not null check (tipo in ('revenda', 'revenda_e_patio', 'patio', 'seguradora')),
  client_id uuid references public.clients(id) on delete set null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);
create unique index parceiros_sigla_unica on public.parceiros (public._texto_simples(sigla));

create table public.parceiro_pessoas (
  id uuid primary key default gen_random_uuid(),
  parceiro_id uuid not null references public.parceiros(id) on delete cascade,
  nome text check (nome is null or btrim(nome) <> ''),   -- nulo: o número é compartilhado, e o recibo sai sem nome de pessoa
  papel text not null check (papel in ('comercial', 'financeiro', 'dono', 'recepcao')),
  ativo boolean not null default true,
  pausado_em timestamptz,
  criado_em timestamptz not null default now()
);

create table public.parceiro_numeros (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references public.parceiro_pessoas(id) on delete cascade,
  phone_normalized text not null,
  chave text not null check (chave ~ '^[0-9]{8}$'),
  ddd text,
  rotulo text check (char_length(rotulo) <= 60),
  uso text not null default 'comercial' check (uso in ('comercial', 'pessoal', 'financeiro')),
  recebe_painel boolean not null default false,
  recebe_documento boolean not null default false,   -- o único número da pessoa que recebe PDF com preço (P12.2)
  situacao text not null default 'proposto' check (situacao in ('proposto', 'confirmado', 'recusado', 'pausado')),
  confirmado_por uuid references public.app_users(id) on delete set null,
  confirmado_em timestamptz,
  apresentada_em timestamptz,          -- 1ª mensagem com "Claudia, assistente virtual" enviada a este número
  criado_em timestamptz not null default now(),
  constraint parceiro_numeros_confirmado check (situacao <> 'confirmado' or confirmado_em is not null)
);
create unique index parceiro_numeros_um_vivo on public.parceiro_numeros (chave) where situacao in ('proposto', 'confirmado', 'pausado');
create unique index parceiro_numeros_um_documento on public.parceiro_numeros (pessoa_id) where recebe_documento and situacao in ('proposto', 'confirmado', 'pausado');

create table public.os_interessados (
  id uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  parceiro_id uuid not null references public.parceiros(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  pessoa_id uuid references public.parceiro_pessoas(id) on delete set null,   -- quem pediu ou recebeu; é a pessoa do vínculo no destino do PDF
  papel text check (papel in ('indicou', 'contratante', 'pagador', 'anfitria')),   -- nulo só em proposto de origem carteira ou dono (*parceiro 74*): o dono escolhe pela letra
  pacote text not null default 'status' check (pacote in ('status', 'status_fotos', 'completo')),
  situacao text not null default 'proposto' check (situacao in ('proposto', 'confirmado', 'recusado', 'pausado')),
  origem text not null check (origem in ('numero_do_pedido', 'unidade_anterior', 'propria', 'carteira', 'dono')),
  base text not null default 'legitimo_interesse' check (base in ('legitimo_interesse', 'contrato', 'consentimento', 'decisao_do_dono')),
  aviso_ao_cliente text not null default 'nao_avisado' check (aviso_ao_cliente in ('mensagem', 'pessoalmente', 'pela_revenda', 'proprio_parceiro', 'nao_avisado')),
  aviso_em timestamptz,
  aviso_saida_id uuid references public.retorno_saidas(id) on delete set null,
  veto_do_cliente_em timestamptz,
  retido_em timestamptz,                -- o cliente respondeu ao aviso com algo que pode ser "não"; segura até o dono decidir
  proposto_em timestamptz not null default now(),
  confirmado_por uuid references public.app_users(id) on delete set null,
  confirmado_em timestamptz,
  decidido_motivo text check (char_length(decidido_motivo) <= 500),
  constraint os_interessados_confirmado check (situacao <> 'confirmado' or (confirmado_em is not null and papel is not null)),
  constraint os_interessados_aviso check ((aviso_ao_cliente = 'nao_avisado') = (aviso_em is null)),
  constraint os_interessados_completo check (pacote <> 'completo' or papel in ('contratante', 'pagador')),
  constraint os_interessados_anfitria check (papel <> 'anfitria' or pacote = 'status')
);
create unique index os_interessados_um_comercial on public.os_interessados (service_order_id, parceiro_id) where papel is distinct from 'anfitria';
create unique index os_interessados_uma_anfitria on public.os_interessados (service_order_id, parceiro_id) where papel = 'anfitria';
create index os_interessados_por_parceiro on public.os_interessados (parceiro_id, situacao);

create table public.parceiro_vetos (                 -- NÃO MP: vale para as OS seguintes, sem depender da OS
  client_id uuid not null references public.clients(id) on delete cascade,
  parceiro_id uuid not null references public.parceiros(id) on delete cascade,
  em timestamptz not null,
  origem text not null check (origem in ('nao_mp', 'dono')),
  whatsapp_message_id uuid references public.whatsapp_messages(id) on delete set null,
  primary key (client_id, parceiro_id)
);

create table public.parceiro_cliente_sabe (          -- o dono disse no item do painel que o cliente já sabe daquele marco
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  marco text not null check (marco in ('pronto', 'peca_chegou', 'aguarda_peca')),
  autor uuid not null references public.app_users(id),
  em timestamptz not null,
  primary key (service_order_id, marco)
);

create table public.parceiro_paineis (
  id uuid primary key default gen_random_uuid(),
  parceiro_id uuid not null references public.parceiros(id) on delete cascade,
  dia date not null,
  estado text not null check (estado in ('sombra', 'aguardando', 'aprovado', 'enviado', 'sem_mudanca', 'vencido', 'cancelado')),
  mudou boolean not null,
  linhas jsonb not null check (jsonb_typeof(linhas) = 'array'),   -- [{n, interessado_id, service_order_id, estado, desde, rotulo, retida_por, fora_por}], sem texto de cliente (P7.2)
  impressao text not null,                                         -- md5 das linhas que saem; campos em P7.2, para o "mudou"
  editado boolean not null default false,
  aprovado_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (parceiro_id, dia)
);

create table public.parceiro_fila (                  -- o que espera o dono mandar *parceiro*; tabela por tipo em P8.1
  id uuid primary key default gen_random_uuid(),
  chave text not null unique,
  tipo text not null check (tipo in ('painel', 'patio', 'pergunta', 'pedido', 'retido', 'pdf_mao', 'aviso', 'repassar', 'vinculo')),
  parceiro_id uuid not null references public.parceiros(id) on delete cascade,
  referencia uuid not null,                          -- id na tabela de origem, conforme o tipo (P8.1)
  dados jsonb not null default '{}' check (jsonb_typeof(dados) = 'object'),   -- só ids e horas; nunca texto de cliente
  prioridade smallint not null check (prioridade between 1 and 8),
  estado text not null default 'espera' check (estado in ('espera', 'no_cartao', 'feito', 'caiu')),
  criado_em timestamptz not null default now(),
  valido_ate timestamptz,                            -- nulo: até decidir
  adiado_ate timestamptz,                            -- *não N*: não volta antes disto
  vezes smallint not null default 0,                 -- quantas vezes já foi ao cartão; o desempate da fila
  ultimo_em timestamptz,
  decidido_em timestamptz
);
create index parceiro_fila_espera on public.parceiro_fila (prioridade, vezes, ultimo_em, criado_em) where estado = 'espera';

create table public.parceiro_pedidos (               -- C13; máquina de estados em P10.1
  id uuid primary key default gen_random_uuid(),
  abertura_id uuid not null references public.retorno_aberturas(id) on delete cascade,
  parceiro_id uuid not null references public.parceiros(id) on delete cascade,
  pessoa_id uuid references public.parceiro_pessoas(id) on delete set null,
  primeiro_nome text check (char_length(primeiro_nome) <= 40),
  veiculo text check (char_length(veiculo) <= 40),
  autoriza_whatsapp boolean,
  whatsapp_informado text,                    -- só no campo; nunca volta ao parceiro
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  estado text not null default 'coleta' check (estado in ('coleta', 'cadastrado', 'cartao', 'decidido', 'caiu')),
  caiu_motivo text check (caiu_motivo in ('sem_resposta', 'caso_fechado', 'desfeito', 'validade', 'duplicado')),
  mais_pedidos smallint not null default 0,   -- pedido novo escrito no mesmo caso: não mistura, só conta; recalculado a cada triagem (P2.1)
  completo_em timestamptz,                    -- hora real da mensagem que completou veículo e nome, ou a saída de `coleta`; régua de mais_pedidos e do P15 (P2.1)
  cadastro_simulado jsonb,                    -- o "criaria" enquanto o cadastro está desligado
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index parceiro_pedidos_um_por_caso on public.parceiro_pedidos (abertura_id);

comment on table public.parceiros is
  'Retorno F4: o parceiro (revenda, pátio, seguradora). client_id é o cadastro dele como cliente, quando existe.';
comment on table public.parceiro_pessoas is
  'Retorno F4: as pessoas do parceiro. nome nulo = número compartilhado (o texto sai sem nome de pessoa).';
comment on table public.parceiro_numeros is
  'Retorno F4: os números das pessoas do parceiro. Só o confirmado pelo dono identifica (quem_escreve). Um vivo por chave de 8 dígitos; um recebe_documento vivo por pessoa.';
comment on table public.os_interessados is
  'Retorno F4: o vínculo OS × parceiro (molde pagadores_do_cliente). Nasce proposto e só vale com o sim do dono; recusado é veto do par e não volta.';
comment on table public.parceiro_vetos is
  'Retorno F4: o NÃO MP do cliente (ou o veto do dono), por cliente × parceiro, sem OS: vale para as OS seguintes.';
comment on table public.parceiro_cliente_sabe is
  'Retorno F4: o dono disse, no item do painel, que o cliente já sabe daquele marco (*N sabe L*).';
comment on table public.parceiro_paineis is
  'Retorno F4: o painel do dia por parceiro. linhas só com ids, estados e datas, nunca texto de cliente.';
comment on table public.parceiro_fila is
  'Retorno F4: o que espera o dono mandar *parceiro*. Escrita só por _parceiro_fila_por; dados só com ids e horas.';
comment on table public.parceiro_pedidos is
  'Retorno F4 (C13): o pedido de orçamento feito pelo parceiro para um cliente dele, um por caso. whatsapp_informado nunca volta ao parceiro.';

-- ── 4. service_orders: a FK reservada pela F3 e a origem do parceiro (not valid + validate: não segura a tabela) ──────────

alter table public.service_orders
  add constraint service_orders_origem_parceiro_fk foreign key (origem_parceiro_id) references public.parceiros(id) on delete set null not valid;
alter table public.service_orders validate constraint service_orders_origem_parceiro_fk;
alter table public.service_orders drop constraint service_orders_origem_check;
alter table public.service_orders add constraint service_orders_origem_check
  check (origem in ('retorno_previa', 'retorno_ditado', 'retorno_parceiro')) not valid;
alter table public.service_orders validate constraint service_orders_origem_check;

comment on column public.service_orders.origem_parceiro_id is
  'Retorno F3 e F4: o parceiro que pediu este orçamento (C13). FK a parceiros desde a F4.';

-- ── 5. A porta única da fila ───────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public._parceiro_fila_por(p_tipo text, p_parceiro uuid, p_referencia uuid, p_chave text,
                                                     p_valido_ate timestamptz, p_dados jsonb default '{}',
                                                     p_reabrir boolean default false)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_prioridade smallint;
  v_dados jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_reabrir boolean := coalesce(p_reabrir, false);
  v_id uuid;
begin
  -- A prioridade é do tipo (P8.1): painel 1, pátio 2, pergunta e pedido 3, retido 4, PDF à mão 5, aviso 6, repassar 7, vínculo 8.
  v_prioridade := case p_tipo
    when 'painel' then 1
    when 'patio' then 2
    when 'pergunta' then 3
    when 'pedido' then 3
    when 'retido' then 4
    when 'pdf_mao' then 5
    when 'aviso' then 6
    when 'repassar' then 7
    when 'vinculo' then 8
  end;
  if v_prioridade is null then
    raise exception using errcode = '22023', message = format('parceiro_fila_por: tipo desconhecido %s', coalesce(p_tipo, '(nenhum)'));
  end if;
  -- Só o pedido volta de 'feito' a 'espera', e só por parceiro_previa_soltar (P10.1).
  if v_reabrir and p_tipo <> 'pedido' then
    raise exception using errcode = '22023', message = 'parceiro_fila_por: p_reabrir só vale para pedido';
  end if;
  if p_parceiro is null or p_referencia is null or coalesce(btrim(p_chave), '') = '' then
    raise exception using errcode = '22023', message = 'parceiro_fila_por: falta parceiro, referência ou chave';
  end if;

  insert into public.parceiro_fila as f (chave, tipo, parceiro_id, referencia, dados, prioridade, valido_ate)
  values (p_chave, p_tipo, p_parceiro, p_referencia, v_dados, v_prioridade, p_valido_ate)
  on conflict (chave) do update
     set dados = f.dados || excluded.dados,
         valido_ate = excluded.valido_ate,
         -- 'no_cartao' e 'feito' não mudam; 'caiu' volta à fila; 'feito' só volta com p_reabrir (pedido).
         estado = case when f.estado = 'caiu' then 'espera'
                       when v_reabrir and f.estado = 'feito' then 'espera'
                       else f.estado end,
         decidido_em = case when f.estado = 'caiu' or (v_reabrir and f.estado = 'feito') then null else f.decidido_em end
  returning f.id into v_id;
  return v_id;
end;
$$;

comment on function public._parceiro_fila_por(text, uuid, uuid, text, timestamptz, jsonb, boolean) is
  'Retorno F4 (P1): a porta única de parceiro_fila. Prioridade pelo tipo; a mesma chave só atualiza dados (merge) e valido_ate, e o estado só volta a espera de caiu. p_reabrir (só pedido, por parceiro_previa_soltar) leva feito a espera; em outro tipo dá 22023.';

revoke all on function public._parceiro_fila_por(text, uuid, uuid, text, timestamptz, jsonb, boolean) from public, anon, authenticated;

-- ── 6. Leitura só no painel de admin e financeiro; escrita só o service_role; anon nada ────────────────────────────────────

alter table public.parceiros enable row level security;
alter table public.parceiro_pessoas enable row level security;
alter table public.parceiro_numeros enable row level security;
alter table public.os_interessados enable row level security;
alter table public.parceiro_vetos enable row level security;
alter table public.parceiro_cliente_sabe enable row level security;
alter table public.parceiro_paineis enable row level security;
alter table public.parceiro_fila enable row level security;
alter table public.parceiro_pedidos enable row level security;

drop policy if exists parceiros_leitura on public.parceiros;
create policy parceiros_leitura on public.parceiros
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists parceiro_pessoas_leitura on public.parceiro_pessoas;
create policy parceiro_pessoas_leitura on public.parceiro_pessoas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists parceiro_numeros_leitura on public.parceiro_numeros;
create policy parceiro_numeros_leitura on public.parceiro_numeros
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists os_interessados_leitura on public.os_interessados;
create policy os_interessados_leitura on public.os_interessados
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists parceiro_vetos_leitura on public.parceiro_vetos;
create policy parceiro_vetos_leitura on public.parceiro_vetos
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists parceiro_cliente_sabe_leitura on public.parceiro_cliente_sabe;
create policy parceiro_cliente_sabe_leitura on public.parceiro_cliente_sabe
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists parceiro_paineis_leitura on public.parceiro_paineis;
create policy parceiro_paineis_leitura on public.parceiro_paineis
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists parceiro_fila_leitura on public.parceiro_fila;
create policy parceiro_fila_leitura on public.parceiro_fila
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists parceiro_pedidos_leitura on public.parceiro_pedidos;
create policy parceiro_pedidos_leitura on public.parceiro_pedidos
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.parceiros, public.parceiro_pessoas, public.parceiro_numeros, public.os_interessados,
                    public.parceiro_vetos, public.parceiro_cliente_sabe, public.parceiro_paineis, public.parceiro_fila,
                    public.parceiro_pedidos
  from public, anon, authenticated;
grant select on table public.parceiros, public.parceiro_pessoas, public.parceiro_numeros, public.os_interessados,
                      public.parceiro_vetos, public.parceiro_cliente_sabe, public.parceiro_paineis, public.parceiro_fila,
                      public.parceiro_pedidos
  to authenticated;
grant all on table public.parceiros, public.parceiro_pessoas, public.parceiro_numeros, public.os_interessados,
                   public.parceiro_vetos, public.parceiro_cliente_sabe, public.parceiro_paineis, public.parceiro_fila,
                   public.parceiro_pedidos
  to service_role;
