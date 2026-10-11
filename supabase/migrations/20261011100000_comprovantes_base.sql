-- Comprovantes F1 (11/10/2026): tabela, numeração CMP e a chave do interruptor.
--
-- Toda foto/PDF/XML que o DONO manda ao WhatsApp do sistema vira uma linha aqui (quando
-- app_settings.comprovante_fluxo não é 'off'). O arquivo vai para o bucket privado 'comprovantes'
-- (migration 20261011101000), é lido no PC pelo HBR Doc Worker (provider local-doc, via ai_jobs) e,
-- se for comprovante, ganha um número CMP-00123 que nunca é reaproveitado (cancelado = queimado).
--
-- Segurança (decisão 10 do dono, a confirmar com ele): só o ADMIN lê; ninguém escreve pela API.
-- Toda escrita é das RPCs security definer da migration 20261011102000 (só service_role).
-- Privacidade (decisão 11): 'leitura' guarda a saída do leitor SEM o texto do OCR e com CPF
-- mascarado; o texto bruto fica em 'leitura_texto' e o vigia o apaga aos 90 dias.
--
-- GRAVA DADO — OK NOMEADO: uma chave em app_settings ('comprovante_fluxo' = 'off', no fim do
-- arquivo). Nasce desligada: nada muda para ninguém até a chave virar 'sombra' ou 'dono'.
-- Recria o gatilho _app_settings_chaves_do_dono (20260928100000) com a chave nova: só o admin
-- liga ou desliga o fluxo; salário mínimo e pró-labore seguem protegidos como antes.
-- Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Tabela
-- ---------------------------------------------------------------------------------------------
create table if not exists public.comprovantes (
  id                           uuid primary key default gen_random_uuid(),
  numero                       integer unique,
  codigo                       text generated always as (
                                 case when numero is null then null
                                      when numero < 100000 then 'CMP-' || lpad(numero::text, 5, '0')
                                      else 'CMP-' || numero::text end) stored,
  compra_principal_id          uuid references public.comprovantes(id) on delete set null,
  situacao                     text not null default 'recebido',
  modo                         text not null,
  rota                         text not null,
  origem                       text not null default 'webhook',
  dono_id                      uuid not null,
  forcado                      boolean not null default false,
  legenda                      text,
  dica_da_legenda              text,
  whatsapp_message_id          uuid references public.whatsapp_messages(id) on delete set null,
  wa_message_id                text not null unique,
  -- a key da mensagem na Evolution ({id, remoteJid, fromMe, senderPn?, remoteJidAlt?}), copiada na
  -- chegada e conferida contra wa_message_id e o telefone: o download usa SEMPRE esta cópia, nunca
  -- o raw_payload de whatsapp_messages (que a equipe consegue alterar)
  wa_key                       jsonb,
  phone_normalized             text not null,
  tipo_whatsapp                text not null,
  nome_arquivo                 text,
  mime_declarado               text,
  recebido_em                  timestamptz not null,
  download_tentativas          smallint not null default 0,
  download_proxima_em          timestamptz,
  arquivo_path                 text,
  arquivo_mime                 text,
  arquivo_bytes                integer,
  arquivo_sha256               text,
  arquivo_apagar_apos          timestamptz,
  arquivo_apagado_em           timestamptz,
  job_id                       uuid references public.ai_jobs(id) on delete set null,
  leituras                     smallint not null default 0,
  reenfileirado                boolean not null default false,
  lido_em                      timestamptz,
  leitor_versao                text,
  leitura                      jsonb,
  leitura_texto                text,
  tipo                         text,
  confianca                    text,
  valor                        numeric(12,2),
  valor_confianca              text,
  data_confianca               text,
  hora_confianca               text,
  cnpj_confianca               text,
  data_compra                  date,
  hora_compra                  time,
  emitente_cnpj                text,
  chave_acesso                 text,
  forma_pagamento              text,
  favorecido_doc               text,
  linha_digitavel              text,
  alertas                      text[] not null default '{}',
  supplier_id                  uuid references public.suppliers(id) on delete set null,
  fornecedor_nome              text,
  duplicado_de                 uuid references public.comprovantes(id) on delete set null,
  dropbox_id                   text,
  dropbox_caminho              text,
  dropbox_rev                  text,
  dropbox_tentativas           smallint not null default 0,
  dropbox_proxima_em           timestamptz,
  dropbox_erro                 text,
  encaminhado_ao_assistente_em timestamptz,
  encaminhamento               text,
  avisado_em                   timestamptz,
  -- aviso que não saiu: a reserva é desfeita e o vigia tenta de novo em 5, 15, 60 e 180 min (sem
  -- whatsapp_send_queue, que qualquer logado lê e edita); na 5ª falha desiste
  aviso_tentativas             smallint not null default 0,
  aviso_proximo_em             timestamptz,
  erro                         text,
  motivo_cancelamento          text,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),
  constraint comprovantes_numero_chk check (numero > 0),
  constraint comprovantes_situacao_chk check (situacao in (
    'recebido', 'na_fila', 'lido', 'nao_comprovante', 'cancelado', 'falhou',
    -- reservados para a F2/F3: a F1 nunca escreve estes
    'perguntando', 'aguardando_vez', 'aguardando_sim', 'aguardando_banco', 'aguardando_xml',
    'gravado', 'conciliado', 'abandonado')),
  constraint comprovantes_modo_chk check (modo in ('sombra', 'dono')),
  constraint comprovantes_rota_chk check (rota in ('comprovante', 'ambos')),
  constraint comprovantes_origem_chk check (origem in ('webhook', 'repescagem')),
  constraint comprovantes_legenda_chk check (legenda is null or char_length(legenda) <= 1024),
  constraint comprovantes_dica_chk check (dica_da_legenda is null or char_length(dica_da_legenda) <= 1024),
  constraint comprovantes_wa_message_id_chk check (char_length(wa_message_id) between 1 and 128),
  constraint comprovantes_wa_key_chk check (
    wa_key is null or (jsonb_typeof(wa_key) = 'object' and wa_key->>'id' = wa_message_id
                       and octet_length(wa_key::text) <= 1024)),
  constraint comprovantes_phone_chk check (phone_normalized ~ '^[0-9]{10,15}$'),
  constraint comprovantes_tipo_whatsapp_chk check (tipo_whatsapp in ('image', 'document')),
  constraint comprovantes_nome_arquivo_chk check (nome_arquivo is null or char_length(nome_arquivo) <= 255),
  constraint comprovantes_mime_declarado_chk check (mime_declarado is null or char_length(mime_declarado) <= 100),
  constraint comprovantes_arquivo_path_chk check (
    arquivo_path is null or arquivo_path ~ '^[0-9]{4}/[0-9]{2}/[0-9a-f-]{36}\.(jpg|png|webp|heic|pdf|xml)$'),
  constraint comprovantes_arquivo_mime_chk check (arquivo_mime is null or arquivo_mime in (
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    'application/pdf', 'application/xml', 'text/xml')),
  constraint comprovantes_arquivo_bytes_chk check (arquivo_bytes is null or arquivo_bytes between 1 and 15728640),
  constraint comprovantes_arquivo_sha256_chk check (arquivo_sha256 is null or arquivo_sha256 ~ '^[0-9a-f]{64}$'),
  constraint comprovantes_leitor_versao_chk check (leitor_versao is null or char_length(leitor_versao) <= 64),
  constraint comprovantes_leitura_chk check (
    leitura is null or (jsonb_typeof(leitura) = 'object' and octet_length(leitura::text) <= 204800)),
  constraint comprovantes_leitura_texto_chk check (leitura_texto is null or char_length(leitura_texto) <= 30000),
  constraint comprovantes_tipo_chk check (tipo is null or tipo in (
    'nfce', 'nfe_danfe', 'nfe_xml', 'nfse', 'cupom_nao_fiscal', 'pix', 'boleto_pago', 'boleto', 'cartao',
    'fatura', 'guia', 'recibo', 'agendado', 'recebimento', 'tela_erro', 'pedido', 'outro', 'nao_documento')),
  constraint comprovantes_confianca_chk check (confianca is null or confianca in ('alta', 'media', 'baixa')),
  constraint comprovantes_valor_chk check (valor is null or valor > 0),
  constraint comprovantes_valor_confianca_chk check (valor_confianca is null or valor_confianca in ('alta', 'media', 'baixa')),
  constraint comprovantes_data_confianca_chk check (data_confianca is null or data_confianca in ('alta', 'media', 'baixa')),
  constraint comprovantes_hora_confianca_chk check (hora_confianca is null or hora_confianca in ('alta', 'media', 'baixa')),
  constraint comprovantes_cnpj_confianca_chk check (cnpj_confianca is null or cnpj_confianca in ('alta', 'media', 'baixa')),
  -- CNPJ alfanumérico (2026+) aceito: 12 posições [0-9A-Z] e 2 dígitos verificadores
  constraint comprovantes_emitente_cnpj_chk check (emitente_cnpj is null or emitente_cnpj ~ '^[0-9A-Z]{12}[0-9]{2}$'),
  constraint comprovantes_chave_acesso_chk check (chave_acesso is null or chave_acesso ~ '^[0-9]{6}[0-9A-Z]{12}[0-9]{26}$'),
  constraint comprovantes_forma_pagamento_chk check (forma_pagamento is null or forma_pagamento in (
    'dinheiro', 'cheque', 'credito', 'debito', 'credito_loja', 'boleto', 'deposito', 'pix', 'transferencia', 'outro')),
  -- CPF só entra mascarado (***.***.NNN-NN); CNPJ inteiro
  constraint comprovantes_favorecido_doc_chk check (
    favorecido_doc is null or favorecido_doc ~ '^[0-9A-Z]{12}[0-9]{2}$' or favorecido_doc ~ '^\*\*\*\.\*\*\*\.[0-9]{3}-[0-9]{2}$'),
  constraint comprovantes_linha_digitavel_chk check (linha_digitavel is null or linha_digitavel ~ '^[0-9]{44,48}$'),
  constraint comprovantes_fornecedor_nome_chk check (fornecedor_nome is null or char_length(fornecedor_nome) <= 200),
  constraint comprovantes_dropbox_id_chk check (dropbox_id is null or dropbox_id ~ '^id:[A-Za-z0-9_-]+$'),
  constraint comprovantes_dropbox_erro_chk check (dropbox_erro is null or char_length(dropbox_erro) <= 300),
  constraint comprovantes_encaminhamento_chk check (
    encaminhamento is null or encaminhamento in ('chegada', 'apos_leitura', 'dispensado_agrupado')),
  constraint comprovantes_erro_chk check (erro is null or char_length(erro) <= 300),
  constraint comprovantes_motivo_cancelamento_chk check (motivo_cancelamento is null or motivo_cancelamento in (
    'arquivo_repetido', 'chave_repetida', 'leitura_tela_erro', 'leitura_recebimento')),
  -- regras de estado
  constraint comprovantes_cmp_tem_arquivo check (numero is null or arquivo_sha256 is not null),
  constraint comprovantes_lido_e_cmp check (situacao <> 'lido' or numero is not null),
  constraint comprovantes_cancelado_tem_motivo check (situacao <> 'cancelado' or motivo_cancelamento is not null),
  constraint comprovantes_falhou_tem_erro check (situacao <> 'falhou' or erro is not null),
  -- decisão 13: do que não é comprovante fica só a classificação (sem número, campos nem texto).
  -- O texto do dono (legenda, dica, nome do arquivo) some junto com o original, aos 7 dias
  -- (comprovante_arquivo_apagado): até lá ele ajuda a medir o falso negativo da triagem.
  constraint comprovantes_nao_cmp_sem_dados check (
    situacao <> 'nao_comprovante'
    or (numero is null and leitura_texto is null and valor is null and emitente_cnpj is null
        and chave_acesso is null and favorecido_doc is null
        and (arquivo_apagado_em is null
             or (legenda is null and dica_da_legenda is null and nome_arquivo is null))))
);

comment on table public.comprovantes is
  'Comprovantes recebidos do dono pelo WhatsApp (F1: receber, guardar e ler). Um CMP é uma linha com numero; cancelado com numero = número queimado. Só o admin lê; escrita só pelas RPCs comprovante_* (service_role).';
comment on column public.comprovantes.codigo is 'CMP-00123 (5 dígitos até 99999; depois o número inteiro, sem cortar).';
comment on column public.comprovantes.compra_principal_id is 'F2: agrupa cupom, via de maquininha e Pix da mesma compra. A F1 nunca escreve.';
comment on column public.comprovantes.modo is 'Modo do fluxo NA CHEGADA (sombra|dono): é ele que decide aviso e encaminhamento, mesmo se a chave mudar depois.';
comment on column public.comprovantes.legenda is 'Só o caption da mídia (nunca o nome do arquivo).';
comment on column public.comprovantes.nome_arquivo is 'Informativo. Nunca vira legenda.';
comment on column public.comprovantes.leitura is 'Saída v1 do leitor sem o texto do OCR e com CPF mascarado.';
comment on column public.comprovantes.leitura_texto is 'Texto bruto do OCR (pode ter CPF). Só admin lê; o vigia apaga aos 90 dias.';
comment on column public.comprovantes.fornecedor_nome is 'Só do cadastro (suppliers), pelo CNPJ. Nunca do OCR.';
comment on column public.comprovantes.erro is 'Só código de erro, nunca conteúdo do documento.';

-- ---------------------------------------------------------------------------------------------
-- 2. Índices
-- ---------------------------------------------------------------------------------------------
create unique index if not exists comprovantes_um_cmp_por_arquivo
  on public.comprovantes (arquivo_sha256) where numero is not null and situacao <> 'cancelado';
create unique index if not exists comprovantes_um_cmp_por_chave
  on public.comprovantes (chave_acesso) where numero is not null and situacao <> 'cancelado' and chave_acesso is not null;
create index if not exists comprovantes_abertos
  on public.comprovantes (situacao, recebido_em) where situacao in ('recebido', 'na_fila', 'falhou');
create index if not exists comprovantes_dropbox_pendente
  on public.comprovantes (dropbox_proxima_em) where numero is not null and dropbox_id is null;
create index if not exists comprovantes_apagar
  on public.comprovantes (arquivo_apagar_apos) where arquivo_apagado_em is null and arquivo_path is not null;
create index if not exists comprovantes_aviso_pendente
  on public.comprovantes (phone_normalized, recebido_em) where avisado_em is null and modo = 'dono';
create index if not exists comprovantes_job on public.comprovantes (job_id);
create index if not exists comprovantes_mensagem on public.comprovantes (whatsapp_message_id);
create index if not exists comprovantes_texto_expira on public.comprovantes (lido_em) where leitura_texto is not null;
create index if not exists comprovantes_valor_data on public.comprovantes (valor, data_compra) where numero is not null;

drop trigger if exists update_comprovantes_updated_at on public.comprovantes;
create trigger update_comprovantes_updated_at before update on public.comprovantes
  for each row execute function public.update_updated_at_column();

-- ---------------------------------------------------------------------------------------------
-- 3. Numeração (padrão next_fiscal_number, sem sequence: o rollback devolve o número, sem buraco)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.comprovantes_numeracao (
  id     smallint primary key,
  ultimo integer not null,
  constraint comprovantes_numeracao_id_chk check (id = 1),
  constraint comprovantes_numeracao_ultimo_chk check (ultimo >= 0)
);
comment on table public.comprovantes_numeracao is 'Contador dos números CMP (linha única). Só o servidor mexe.';

create or replace function public._comprovante_proximo_numero()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v integer;
begin
  insert into public.comprovantes_numeracao as n (id, ultimo) values (1, 1)
  on conflict (id) do update set ultimo = n.ultimo + 1
  returning n.ultimo into v;
  return v;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Helpers puros
-- ---------------------------------------------------------------------------------------------

-- Apêndice C da spec: é compra (vira CMP)?
--   documentos de pagamento/compra: CMP se confiança alta/media; com legenda-chave, sempre;
--   pedido/outro/nao_documento: só com legenda-chave;
--   tela_erro/recebimento: nunca (com legenda-chave o registro é cancelado com motivo).
create or replace function public._comprovante_e_compra(p_tipo text, p_confianca text, p_forcado boolean)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when p_tipo is null then false
    when p_tipo in ('tela_erro', 'recebimento') then false
    when p_tipo in ('nfce', 'nfe_danfe', 'nfe_xml', 'nfse', 'cupom_nao_fiscal', 'pix', 'boleto_pago', 'boleto',
                    'cartao', 'fatura', 'guia', 'recibo', 'agendado')
      then coalesce(p_forcado, false) or coalesce(p_confianca, '') in ('alta', 'media')
    when p_tipo in ('pedido', 'outro', 'nao_documento') then coalesce(p_forcado, false)
    else false
  end;
$$;

-- Defesa em profundidade (o contrato já obriga o leitor a mandar CPF mascarado): troca todo CPF
-- FORMATADO por ***.***.NNN-NN.
create or replace function public._comprovante_mascarar_cpf(p text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select regexp_replace(p, '(?<![0-9])[0-9]{3}\.[0-9]{3}\.([0-9]{3})-([0-9]{2})(?![0-9])', '***.***.\1-\2', 'g');
$$;

-- ---------------------------------------------------------------------------------------------
-- 5. RLS e privilégios (revogar de anon/authenticated POR NOME: o grant padrão do Supabase não vem de PUBLIC)
-- ---------------------------------------------------------------------------------------------
alter table public.comprovantes enable row level security;
alter table public.comprovantes_numeracao enable row level security;

revoke all on table public.comprovantes from public, anon, authenticated;
grant select on table public.comprovantes to authenticated;
grant all on table public.comprovantes to service_role;

drop policy if exists comprovantes_admin_le on public.comprovantes;
create policy comprovantes_admin_le on public.comprovantes
  for select to authenticated using (public.is_admin((select auth.uid())));

revoke all on table public.comprovantes_numeracao from public, anon, authenticated;
grant all on table public.comprovantes_numeracao to service_role;

revoke all on function public._comprovante_proximo_numero() from public, anon, authenticated;
revoke all on function public._comprovante_e_compra(text, text, boolean) from public, anon, authenticated;
revoke all on function public._comprovante_mascarar_cpf(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 6. GRAVA DADO — OK NOMEADO: a chave do interruptor (decisão 9). Nasce 'off'.
--    A pasta do Dropbox NÃO vai para app_settings: é constante no código (PASTA_COMPROVANTES),
--    porque o financeiro escreve em app_settings e não pode desviar a pasta.
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('comprovante_fluxo', 'off',
   'Fluxo de comprovantes do WhatsApp do dono: off (desligado), sombra (guarda, lê e arquiva sem falar com o dono) ou dono (assume fotos e PDFs do dono, com avisos só informativos).')
on conflict (key) do nothing;

-- Só o administrador liga ou desliga o fluxo (a política geral de app_settings deixa o financeiro
-- escrever, e esta chave tira do assistente as fotos e PDFs do dono). É o gatilho que já protege
-- o salário mínimo e a regra do pró-labore (20260928100000), recriado com a chave nova; o resto do
-- comportamento é o mesmo (sem usuário logado = servidor/migration, passa).
create or replace function public._app_settings_chaves_do_dono()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null and not public.is_admin(v_uid) then
    if (tg_op <> 'INSERT' and old.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo'))
       or (tg_op <> 'DELETE' and new.key in ('salario_minimo', 'pro_labore_pelo_salario_minimo')) then
      raise exception 'Só o administrador muda o salário mínimo e a regra do pró-labore.' using errcode = '42501';
    end if;
    if (tg_op <> 'INSERT' and old.key = 'comprovante_fluxo')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_fluxo') then
      raise exception 'Só o administrador liga ou desliga o fluxo de comprovantes.' using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists app_settings_chaves_do_dono on public.app_settings;
create trigger app_settings_chaves_do_dono
  before insert or update or delete on public.app_settings
  for each row execute function public._app_settings_chaves_do_dono();

revoke all on function public._app_settings_chaves_do_dono() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_t text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.comprovantes'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.comprovantes_numeracao'::regclass) then
    raise exception 'RLS desligada em comprovantes/comprovantes_numeracao';
  end if;
  foreach v_t in array array['public.comprovantes', 'public.comprovantes_numeracao'] loop
    if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert')
       or has_table_privilege('anon', v_t, 'update') or has_table_privilege('anon', v_t, 'delete') then
      raise exception 'anon ainda alcança %', v_t;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.comprovantes', 'insert')
     or has_table_privilege('authenticated', 'public.comprovantes', 'update')
     or has_table_privilege('authenticated', 'public.comprovantes', 'delete') then
    raise exception 'authenticated escreve direto em comprovantes';
  end if;
  if has_table_privilege('authenticated', 'public.comprovantes_numeracao', 'select')
     or has_table_privilege('authenticated', 'public.comprovantes_numeracao', 'insert')
     or has_table_privilege('authenticated', 'public.comprovantes_numeracao', 'update')
     or has_table_privilege('authenticated', 'public.comprovantes_numeracao', 'delete') then
    raise exception 'authenticated alcança comprovantes_numeracao';
  end if;
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'comprovantes' and policyname = 'comprovantes_admin_le'
       and cmd = 'SELECT' and roles = array['authenticated']::name[]
  ) then
    raise exception 'policy comprovantes_admin_le ausente ou com papel errado';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename in ('comprovantes', 'comprovantes_numeracao')
       and (roles && array['anon', 'public']::name[] or policyname <> 'comprovantes_admin_le')
  ) then
    raise exception 'há policy a mais em comprovantes/comprovantes_numeracao (ou alcançando anon/public)';
  end if;
  if has_function_privilege('anon', 'public._comprovante_proximo_numero()', 'execute')
     or has_function_privilege('authenticated', 'public._comprovante_proximo_numero()', 'execute')
     or has_function_privilege('anon', 'public._comprovante_e_compra(text, text, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public._comprovante_e_compra(text, text, boolean)', 'execute')
     or has_function_privilege('anon', 'public._comprovante_mascarar_cpf(text)', 'execute')
     or has_function_privilege('authenticated', 'public._comprovante_mascarar_cpf(text)', 'execute') then
    raise exception 'helper interno dos comprovantes exposto';
  end if;
  if not exists (select 1 from public.app_settings where key = 'comprovante_fluxo') then
    raise exception 'chave comprovante_fluxo não foi criada';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'app_settings_chaves_do_dono'
                    and tgrelid = 'public.app_settings'::regclass and tgenabled <> 'D') then
    raise exception 'gatilho app_settings_chaves_do_dono ausente: o financeiro mudaria comprovante_fluxo';
  end if;
  if has_function_privilege('anon', 'public._app_settings_chaves_do_dono()', 'execute')
     or has_function_privilege('authenticated', 'public._app_settings_chaves_do_dono()', 'execute') then
    raise exception 'função do gatilho das chaves do dono exposta';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011100000', 'comprovantes_base')
on conflict do nothing;
