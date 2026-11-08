-- Retorno rápido ao cliente, F1 (sobe no pacote F0b-1 de ter 10/11/2026): as tabelas do retorno, todas
-- vazias, e as colunas novas de whatsapp_leads e clients.
--
-- 1. retorno_aberturas: o CASO — uma conversa de um número que pede resposta, do 1º recebido até ser
--    respondida de conteúdo, ficar em silêncio, não ser nada ou expirar. No máximo UM caso vivo
--    (aberta/vencida) por número (chave de 8 dígitos): a mesma conversa nunca abre dois recibos.
--    Guarda as duas horas de cada mensagem — a real (hora_real da F0b) e a de gravação (occurred_at) —
--    porque, ao voltar de queda, a Evolution regrava em lote e a hora de gravação engana.
--    nivel/motivo é a triagem (nada | recibo | passagem); prometido_ate e o relógio do caso são
--    calculados pelo banco (IA pensa, sistema preenche).
-- 2. retorno_mensagens: uma linha por recebida que o retorno leu — a idempotência de retorno_abrir
--    (a mesma mensagem nunca abre dois casos) e os sinais por mensagem. corpo_hash muda quando a
--    transcrição troca o "[audio]" pelo texto: é assim que o vigia sabe que deve reavaliar.
-- 3. retorno_saidas: cada "eu mandaria" e cada envio (molde agenda_cliente_mensagens). dedupe_key
--    única: a chave reservada fica para sempre, e a saída incerta nunca ganha 2ª tentativa. Também
--    conta (emissor 'fila', estado 'contada') o que a fila mandou ao número, para os tetos.
-- 4. retorno_silencios (F0b-8, só sombra): os buracos de entrada em horário comercial, com o estado da
--    conexão e se o vigia já tinha avisado a queda.
-- 5. retorno_alongamentos: cada vez que a promessa de uma faixa se alongou sozinha (B.4.1; só alonga).
-- 6. whatsapp_leads.lead_tipo ('pessoal', só o dono marca, nunca regex) e coleta (o que o número novo
--    disse, literal); clients.provisorio e origem (o cadastro provisório do retorno, que só nasce com
--    OK nomeado e se arquiva sozinho sem uso).
-- 7. O índice das ENVIADAS por chave em whatsapp_messages (a regra "número novo" e o
--    "respondida_pelo_dono"); o das recebidas já existe (agenda_wa_recebidas_por_chave). Fica entre as
--    marcas "bancada: pular": só serve à velocidade, e na bancada (P15) seguraria ShareLock em
--    whatsapp_messages até o rollback.
--
-- RLS nas cinco tabelas: leitura só de admin e financeiro (is_admin_or_financial), escrita só do
-- service_role (molde agenda_cliente_mensagens); anon nada. Sem gatilho de updated_at: as funções
-- gravam atualizada_em.
--
-- Sem dado: as tabelas nascem vazias; as colunas novas nascem nulas (provisorio = false); nenhuma linha
-- existente é reescrita.
-- Reverter (depois das migrations seguintes da F1): drop index public.retorno_wa_enviadas_por_chave;
-- drop table public.retorno_alongamentos, public.retorno_silencios, public.retorno_saidas,
-- public.retorno_mensagens, public.retorno_aberturas; alter table public.clients drop column provisorio,
-- drop column origem; alter table public.whatsapp_leads drop column lead_tipo, drop column coleta.

create table public.retorno_aberturas (
  id uuid primary key default gen_random_uuid(),
  chave text not null check (chave ~ '^[0-9]{8}$'),
  phone_normalized text not null,
  ddd text,
  papel text not null check (papel in ('cliente', 'cliente_ambiguo', 'cliente_parceiro',
                                       'numero_novo', 'contato_conhecido', 'fornecedor')),
  quem jsonb not null check (jsonb_typeof(quem) = 'object'),          -- quem_escreve() na abertura
  client_id uuid references public.clients(id) on delete set null,
  clientes uuid[] not null default '{}',
  lead_id uuid references public.whatsapp_leads(id) on delete set null,
  primeira_msg_id uuid not null unique references public.whatsapp_messages(id) on delete cascade,
  ultima_msg_id uuid references public.whatsapp_messages(id) on delete set null,
  msgs smallint not null default 1,
  aberta_em timestamptz not null,          -- hora real da 1ª (hora_real; sem ela, occurred_at)
  gravada_em timestamptz not null,         -- occurred_at da 1ª
  ultima_em timestamptz not null,
  ultima_gravada_em timestamptz not null,
  atraso_gravacao interval not null default '0',
  sinais jsonb not null default '{}' check (jsonb_typeof(sinais) = 'object'),
  intencao text not null default 'outro' check (intencao in ('pedido_servico', 'saudacao', 'pressa', 'risco',
                                         'reclamacao', 'quer_dono', 'lgpd', 'parar', 'outro')),
  nivel text not null check (nivel in ('nada', 'recibo', 'passagem')),
  motivo text check (motivo in ('cliente_final', 'opt_out', 'bloqueado', 'pessoal', 'fornecedor', 'contato_conhecido',
                                'parceiro_f4', 'robo', 'vendedor', 'agenda_consumiu', 'nao_pede_resposta',
                                'promessa_do_dono', 'numero_novo_sem_pedido', 'parar', 'parar_largo', 'atraso_longo')),
  tipo_recibo text check (tipo_recibo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo')),
  coleta jsonb check (coleta is null or jsonb_typeof(coleta) = 'object'),
  coleta_n smallint not null default 0 check (coleta_n between 0 and 2),
  insistencias smallint not null default 0,
  faixa text check (faixa in ('manha_cedo', 'meio', 'tarde', 'noite', 'folga', 'pressa', 'fora_ate', 'promessa_dono')),
  prometido_ate timestamptz,
  prometido_fonte text check (prometido_fonte in ('manha', 'meio_dia', 'fechamento', 'acorde', 'dono', 'fora_ate')),
  recibo_em timestamptz,
  adiamento_em timestamptz,
  segundo_prazo timestamptz,               -- X2
  fim_do_dia_em timestamptz,
  topo_dia date,                           -- a marca de topo: o caso abre a manhã deste dia
  urgente_em timestamptz,
  passagem_em timestamptz,
  respondida_em timestamptz,               -- 1ª saída humana ao número depois da abertura
  cumprida_em timestamptz,                 -- 1ª resposta humana de conteúdo
  cumprida_por text check (cumprida_por in ('celular', 'tela', 'assistente')),
  estado text not null default 'aberta' check (estado in ('aberta', 'vencida', 'fechada')),
  fechada_em timestamptz,
  fechada_motivo text check (fechada_motivo in ('conteudo', 'silencio', 'nada', 'expirou')),
  modo text not null check (modo in ('sombra', 'ligado')),
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  constraint retorno_aberturas_fechada check ((estado = 'fechada') = (fechada_em is not null)),
  constraint retorno_aberturas_cumprida check ((cumprida_em is null) = (cumprida_por is null)),
  constraint retorno_aberturas_motivo check ((nivel = 'nada') = (motivo is not null))
);
create unique index retorno_aberturas_uma_viva on public.retorno_aberturas (chave) where estado in ('aberta', 'vencida');
create index retorno_aberturas_relogio on public.retorno_aberturas (prometido_ate) where estado in ('aberta', 'vencida');
create index retorno_aberturas_por_dia on public.retorno_aberturas (aberta_em);

comment on table public.retorno_aberturas is
  'Retorno F1: o caso (conversa de um número que pede resposta). No máximo um vivo (aberta/vencida) por chave de 8 dígitos. Horas, prazos, estado e vínculo preenchidos pelo banco.';

create table public.retorno_mensagens (           -- idempotência de retorno_abrir e sinais por mensagem
  whatsapp_message_id uuid primary key references public.whatsapp_messages(id) on delete cascade,
  abertura_id uuid references public.retorno_aberturas(id) on delete cascade,
  chave text not null,
  recebida_em timestamptz not null,               -- hora real
  gravada_em timestamptz not null,                -- occurred_at
  corpo_hash text not null,                       -- md5(coalesce(body,'')): a transcrição muda o hash
  sinais jsonb not null default '{}',
  pede_resposta boolean not null,
  pede_motivo text,                               -- inclui 'robo' (detector da F0b ou resposta em < 5 s) e 'parar_largo'
  audio_pendente boolean not null default false,  -- corpo ainda '[audio]': o vigia reavalia quando a transcrição chegar
  consumida boolean not null default false,
  agenda_ao_dono boolean not null default false,  -- a agenda já levou ao dono (efeito 'ao_dono')
  processada_em timestamptz not null default now()
);
create index retorno_mensagens_por_abertura on public.retorno_mensagens (abertura_id, recebida_em);
create index retorno_mensagens_audio on public.retorno_mensagens (recebida_em) where audio_pendente;

comment on table public.retorno_mensagens is
  'Retorno F1: cada recebida que o retorno leu (uma linha por mensagem: retorno_abrir é idempotente), com os sinais e se pede resposta. corpo_hash muda com a transcrição do áudio.';

create table public.retorno_saidas (               -- molde agenda_cliente_mensagens
  id uuid primary key default gen_random_uuid(),
  emissor text not null default 'retorno' check (emissor in ('retorno', 'fila')),
  abertura_id uuid references public.retorno_aberturas(id) on delete cascade,
  fila_id uuid,                                    -- whatsapp_send_queue.id (sem FK: a fila é limpa por outras rotinas)
  fila_source text,
  tipo text not null check (tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo',
                                     'saudacao_numero_novo', 'adiamento', 'fim_do_dia', 'urgente', 'parar',
                                     'cadastro_provisorio', 'acorde', 'fila')),
  variante text check (char_length(variante) <= 40),
  origem text check (origem in ('retorno_recibo', 'retorno_coleta', 'retorno_adiamento')),
  classe text check (classe in ('resposta_imediata', 'resposta_atrasada')),
  chave text not null check (chave ~ '^[0-9]{8}$'),
  phone_normalized text not null,
  client_id uuid references public.clients(id) on delete set null,
  modo text not null check (modo in ('sombra', 'ligado')),
  estado text not null default 'agendada' check (estado in ('agendada', 'preparada', 'enviando', 'sombra', 'enviada',
                                                             'incerta', 'recusada', 'cancelada', 'contada')),
  motivo text check (motivo in (
    'respondida_pelo_dono', 'caso_fechado', 'caso_vencido', 'nivel_nada', 'rajada', 'lote_global', 'aguarda_transcricao',
    'fora_da_janela', 'espacamento', 'teto_numero', 'teto_dia', 'teto_coleta', 'teto_saudacao', 'teto_volta',
    'atraso_longo', 'bloqueado', 'opt_out', 'cliente_final', 'pessoal', 'equipe', 'so_reativo', 'segura_tudo',
    'segura_recibos', 'tipo_desligado', 'modo', 'urgente_desligado', 'validador', 'texto', 'canal', 'provedor',
    'reserva', 'erro', 'substituida', 'sem_config', 'classe_nao_suportada', 'sem_numero',
    'agenda_ja_acordou', 'duplicado_pergunta', 'sem_nome', 'recusaria_fila')),
  -- 'erro' = exceção ao compor (retorno_pegar marca e segue); os 3 últimos da 2ª linha vêm de canal_pode_enviar.
  -- O motivo de SOMBRA (modo, tipo_desligado, urgente_desligado, segura_*, passagem_sem_acorde, caso_sem_aviso,
  -- caso_em_sombra) fica em dados.sombra_motivo, não aqui.
  recusaria boolean,                               -- só emissor 'fila'
  enviar_em timestamptz not null,
  processando_ate timestamptz,
  tentativa smallint not null default 1 check (tentativa between 1 and 3),   -- só o 503 (reserva) reagenda; a incerta é final
  decidida_em timestamptz,
  enviada_em timestamptz,
  texto text check (texto is null or char_length(texto) between 3 and 600),
  dados jsonb not null default '{}' check (jsonb_typeof(dados) = 'object'),
  validador jsonb,
  provider_message_id text,
  dedupe_key text not null unique,
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  constraint retorno_saidas_enviada check ((estado = 'enviada') = (enviada_em is not null)),
  constraint retorno_saidas_motivo check (estado not in ('recusada', 'cancelada') or motivo is not null),
  constraint retorno_saidas_texto check (estado not in ('preparada', 'enviando', 'sombra', 'enviada', 'incerta')
                                         or texto is not null or tipo in ('acorde', 'cadastro_provisorio')),
  constraint retorno_saidas_fila check ((emissor = 'fila') = (fila_id is not null)),
  constraint retorno_saidas_contada check ((estado = 'contada') = (emissor = 'fila'))
);
create index retorno_saidas_devidas on public.retorno_saidas (enviar_em) where estado = 'agendada';
create index retorno_saidas_por_chave on public.retorno_saidas (chave, decidida_em);
create index retorno_saidas_por_abertura on public.retorno_saidas (abertura_id);

comment on table public.retorno_saidas is
  'Retorno F1: cada saída do retorno ("eu teria mandado" na sombra, ou o envio) e cada envio da fila ao número (emissor fila, estado contada). dedupe_key única e para sempre; a incerta é final.';

create table public.retorno_silencios (           -- F0b-8, em sombra
  id uuid primary key default gen_random_uuid(),
  dia date not null,
  desde timestamptz not null,          -- última recebida de fora da equipe (ou silencio_inicio do dia)
  detectado_em timestamptz not null,
  voltou_em timestamptz,               -- 1ª recebida de fora da equipe depois de desde
  saidas_humanas smallint not null,
  conexao_estado text,                 -- whatsapp_conexao_vigia.estado na detecção
  caiu_avisado boolean not null,       -- houve app_notifications 'whatsapp_caiu' desde (desde − 30 min)
  modo text not null default 'sombra' check (modo = 'sombra'),
  unique (dia, desde)
);

comment on table public.retorno_silencios is
  'Retorno F0b-8 (sombra): buraco de entrada em horário comercial (nenhuma recebida de fora da equipe por silencio_horas), com o estado da conexão e se a queda já tinha sido avisada.';

create table public.retorno_alongamentos (        -- B.4.1: a faixa alonga sozinha (P6.2, passo 13); a sexta conta
  id uuid primary key default gen_random_uuid(),
  faixa text not null,
  de jsonb not null,                    -- {"dias", "hora"} antes
  para jsonb not null,                  -- {"dias", "hora"} depois
  casos smallint not null,
  pct numeric(5,4) not null,
  em timestamptz not null default now()
);

comment on table public.retorno_alongamentos is
  'Retorno F1 (B.4.1): cada alongamento automático da promessa de uma faixa (só alonga; encurtar só com a palavra do dono).';

alter table public.whatsapp_leads
  add column if not exists lead_tipo text,
  add column if not exists coleta jsonb;
alter table public.whatsapp_leads drop constraint if exists whatsapp_leads_lead_tipo_check;
alter table public.whatsapp_leads add constraint whatsapp_leads_lead_tipo_check check (lead_tipo is null or lead_tipo = 'pessoal');
alter table public.whatsapp_leads drop constraint if exists whatsapp_leads_coleta_check;
alter table public.whatsapp_leads add constraint whatsapp_leads_coleta_check check (coleta is null or jsonb_typeof(coleta) = 'object');
comment on column public.whatsapp_leads.lead_tipo is
  'Retorno F1: ''pessoal'' = o dono disse que o número é pessoal; nunca recebe automático. Só o dono marca (nunca regex).';
comment on column public.whatsapp_leads.coleta is
  'Retorno F1: o que o número novo disse, literal, no formato de dados_site (nome, tipo, modelo, local, servico, detalhes) + fonte, ano, atualizado_em.';

alter table public.clients
  add column if not exists provisorio boolean not null default false,
  add column if not exists origem text;
alter table public.clients drop constraint if exists clients_origem_check;
alter table public.clients add constraint clients_origem_check check (origem is null or origem = 'retorno');
alter table public.clients drop constraint if exists clients_provisorio_origem;
alter table public.clients add constraint clients_provisorio_origem check (not provisorio or origem is not null);
comment on column public.clients.provisorio is
  'Retorno F1: cadastro provisório criado pelo retorno (número novo que disse o nome depois da coleta); só com OK nomeado; arquivado sem uso em cadastro_arquivar_apos.';
comment on column public.clients.origem is
  'Retorno F1: quem criou o cadastro fora da tela (''retorno''); nulo = cadastro de sempre.';

-- Leitura só no painel de admin e financeiro; escrita só o service_role; anon nada.
alter table public.retorno_aberturas enable row level security;
alter table public.retorno_mensagens enable row level security;
alter table public.retorno_saidas enable row level security;
alter table public.retorno_silencios enable row level security;
alter table public.retorno_alongamentos enable row level security;

drop policy if exists retorno_aberturas_leitura on public.retorno_aberturas;
create policy retorno_aberturas_leitura on public.retorno_aberturas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_mensagens_leitura on public.retorno_mensagens;
create policy retorno_mensagens_leitura on public.retorno_mensagens
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_saidas_leitura on public.retorno_saidas;
create policy retorno_saidas_leitura on public.retorno_saidas
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_silencios_leitura on public.retorno_silencios;
create policy retorno_silencios_leitura on public.retorno_silencios
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

drop policy if exists retorno_alongamentos_leitura on public.retorno_alongamentos;
create policy retorno_alongamentos_leitura on public.retorno_alongamentos
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.retorno_aberturas, public.retorno_mensagens, public.retorno_saidas,
                    public.retorno_silencios, public.retorno_alongamentos
  from public, anon, authenticated;
grant select on table public.retorno_aberturas, public.retorno_mensagens, public.retorno_saidas,
                      public.retorno_silencios, public.retorno_alongamentos
  to authenticated;
grant all on table public.retorno_aberturas, public.retorno_mensagens, public.retorno_saidas,
                   public.retorno_silencios, public.retorno_alongamentos
  to service_role;

-- As enviadas por chave (a regra "número novo" e o "respondida_pelo_dono"); a das recebidas já existe
-- (agenda_wa_recebidas_por_chave).
-- bancada: pular (início)  — só velocidade; na bancada pegaria ShareLock em whatsapp_messages até o rollback (P15)
create index if not exists retorno_wa_enviadas_por_chave
  on public.whatsapp_messages (public._agenda_chave_telefone(phone_normalized), occurred_at) where direction = 'outbound';
-- bancada: pular (fim)
