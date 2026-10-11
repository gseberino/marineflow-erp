-- Comprovantes F2 (11/10/2026): colunas da conversa, registro único de pergunta ativa e a chave
-- comprovante_conversa.
--
-- A F2 conversa com o dono sobre cada CMP lido (para quê, como pagou, peça ou despesa da OS?),
-- mostra o resumo do que VAI fazer e só grava depois do sim. Esta migration só prepara o terreno:
--   * colunas novas em comprovantes (respostas, plano, efeitos gravados, cancelamento, Dropbox,
--     índice do mês e os ganchos da F3, que a F2 nunca preenche);
--   * whatsapp_perguntas: o registro ÚNICO de pergunta ativa por telefone (índice único parcial),
--     compartilhado com as pendências do assistente, lembretes de revisão, campanha e
--     acompanhar-conversas;
--   * comprovantes_fila_do_telefone (pausa e espaçamento), comprovantes_indice_mensal (o CSV de
--     cada mês no Dropbox) e cnpj_consultas (cache da BrasilAPI);
--   * _comprovante_conversa_ligada(): verdadeiro só com comprovante_fluxo = 'dono' E
--     comprovante_conversa = 'on'.
--
-- FKs só no sentido comprovantes → outras tabelas (nenhuma coluna nova em anotacoes_do_extrato,
-- payables ou service_order_expenses aponta para comprovantes): o PostgREST não vê dois caminhos
-- entre as mesmas tabelas (PGRST201).
--
-- GRAVA DADO — OK NOMEADO: uma chave em app_settings ('comprovante_conversa' = 'off', no fim do
-- arquivo). Nasce desligada: com ela em 'off' tudo segue como na F1 (avisos só informativos).
-- Recria o gatilho _app_settings_chaves_do_dono (igual ao da F1) com a chave nova: só o admin
-- liga ou desliga a conversa. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Colunas novas em comprovantes
-- ---------------------------------------------------------------------------------------------
alter table public.comprovantes
  add column if not exists destino                  text,
  add column if not exists destino_os_id            uuid references public.service_orders(id) on delete set null,
  -- ajustes do dono (11/10/2026): o comprovante nunca é cobrado do cliente; na OS, a pergunta é
  -- "peça/material ou despesa da OS" (só quando não há lançamento igual já na OS)
  add column if not exists tipo_na_os               text,
  add column if not exists quem_pagou               text,
  add column if not exists pagador_payee_id         uuid references public.payees(id) on delete set null,
  add column if not exists categoria                text,
  add column if not exists valor_confirmado         numeric(12,2),
  add column if not exists data_confirmada          date,
  add column if not exists forma_confirmada         text,
  add column if not exists fornecedor_receita       text,
  add column if not exists passo                    text,
  add column if not exists resumo_versao            integer not null default 0,
  add column if not exists fila_desde               timestamptz,
  add column if not exists fila_ordem               timestamptz,
  add column if not exists perguntas_automaticas    smallint not null default 0,
  add column if not exists ultima_pergunta_em       timestamptz,
  add column if not exists gravado_em               timestamptz,
  add column if not exists gravado_por              uuid,
  add column if not exists plano                    jsonb,
  add column if not exists efeitos                  jsonb not null default '[]'::jsonb,
  add column if not exists so_expense_id            uuid references public.service_order_expenses(id) on delete set null,
  -- a peça que já estava na OS e que o comprovante só comprova (ajustes do dono, 11/10/2026)
  add column if not exists so_part_id               uuid references public.service_order_parts(id) on delete set null,
  add column if not exists anotacao_id              uuid references public.anotacoes_do_extrato(id) on delete set null,
  add column if not exists payable_id               uuid references public.payables(id) on delete set null,
  add column if not exists fiscal_note_id           uuid references public.fiscal_notes(id) on delete set null,
  -- ganchos da F3 (conciliação fina com o extrato): a F2 só marca aguardando_banco_desde
  add column if not exists bank_transaction_id      uuid references public.bank_transactions(id) on delete set null,
  add column if not exists aguardando_banco_desde   timestamptz,
  add column if not exists conciliacao              text,
  add column if not exists conciliado_em            timestamptz,
  add column if not exists pendencias               text[] not null default '{}',
  add column if not exists cancelado_em             timestamptz,
  add column if not exists cancelado_por            uuid,
  add column if not exists cancelamento_texto       text,
  add column if not exists dropbox_pendente         text,
  add column if not exists dropbox_mover_tentativas smallint not null default 0,
  add column if not exists dropbox_mover_proxima_em timestamptz,
  add column if not exists dropbox_mover_erro       text,
  add column if not exists indice_mes               date,
  -- revisão de 11/10/2026: dois CMPs da mesma compra (o cupom e o print do Pix) não lançam duas
  -- vezes — o dono diz se é a mesma compra (só arquivo) ou outra (grava normal). Sem FK (o outro
  -- CMP é desta mesma tabela; o plano confere de novo na gravação).
  add column if not exists mesma_compra_de          uuid,
  add column if not exists outra_compra             boolean,
  -- "pular"/"deixar para depois": o vigia não pergunta este CMP antes disto
  add column if not exists adiado_ate               timestamptz,
  -- as mensagens de texto do dono que viraram dica deste CMP (não contam como conversa em andamento)
  add column if not exists mensagens_de_dica        uuid[] not null default '{}';

comment on column public.comprovantes.destino is 'F2: para quê (os, estoque, insumo, empresa, pessoal), respondido pelo dono ou lido da legenda.';
comment on column public.comprovantes.tipo_na_os is 'F2 (ajustes do dono, 11/10/2026): na OS, peca (só comprova: a peça entra pela OS) ou despesa (custo interno da OS, que nunca aparece para o cliente). Nulo = não perguntado (há lançamento igual já na OS, ou não é de OS). O comprovante nunca é cobrado do cliente.';
comment on column public.comprovantes.so_part_id is 'F2 (ajustes do dono, 11/10/2026): a peça que já estava na OS e que este CMP comprova (não lança custo).';
comment on column public.comprovantes.valor_confirmado is 'F2: o valor que o dono confirmou (nasce do lido só com selo alta/media).';
comment on column public.comprovantes.fornecedor_receita is 'F2: nome do fornecedor pela Receita (BrasilAPI, cache em cnpj_consultas). Nunca do OCR.';
comment on column public.comprovantes.passo is 'F2: o passo da conversa em aberto (ou forçado por corrigir). Nulo = o próximo é calculado.';
comment on column public.comprovantes.resumo_versao is 'F2: +1 a cada mudança de dado da conversa; o sim só vale para a versão que o dono viu.';
comment on column public.comprovantes.plano is 'F2: o plano de gravação aplicado no sim (_comprovante_plano).';
comment on column public.comprovantes.efeitos is 'F2: o que foi gravado, com os ids e o "antes" para o cancelamento desfazer.';
comment on column public.comprovantes.bank_transaction_id is 'Gancho da F3 (conciliação com o extrato). A F2 nunca escreve.';
comment on column public.comprovantes.aguardando_banco_desde is 'Gancho da F3: a F2 só marca quando a gravação espera a linha do banco (anotação ou crédito).';
comment on column public.comprovantes.conciliacao is 'Gancho da F3 (verde/azul/cinza). A F2 nunca escreve.';
comment on column public.comprovantes.indice_mes is 'F2: o mês (dia 1) do _INDICE AAAA-MM.csv a que o CMP pertence desde a gravação.';
comment on column public.comprovantes.mesma_compra_de is 'F2: o dono disse que é a mesma compra deste outro CMP (já gravado): este só guarda o arquivo, nada no financeiro.';
comment on column public.comprovantes.outra_compra is 'F2: o dono disse que NÃO é a mesma compra do CMP parecido: grava normal.';
comment on column public.comprovantes.adiado_ate is 'F2: "pular"/"deixar para depois" — o vigia não pergunta este CMP antes desta hora.';

-- ---------------------------------------------------------------------------------------------
-- 2. CHECKs (por nome, só se ainda não existem; o de motivo é recriado com 'dono_cancelou')
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_c record;
begin
  -- o motivo do cancelamento ganha 'dono_cancelou' (o CMP gravado que o dono cancela)
  if exists (select 1 from pg_constraint
              where conrelid = 'public.comprovantes'::regclass and conname = 'comprovantes_motivo_cancelamento_chk'
                and pg_get_constraintdef(oid) not like '%dono_cancelou%') then
    alter table public.comprovantes drop constraint comprovantes_motivo_cancelamento_chk;
  end if;

  for v_c in
    select * from (values
      ('comprovantes_motivo_cancelamento_chk',
       $c$motivo_cancelamento is null or motivo_cancelamento in ('arquivo_repetido', 'chave_repetida', 'leitura_tela_erro', 'leitura_recebimento', 'dono_cancelou')$c$),
      ('comprovantes_destino_chk', $c$destino is null or destino in ('os', 'estoque', 'insumo', 'empresa', 'pessoal')$c$),
      ('comprovantes_quem_pagou_chk', $c$quem_pagou is null or quem_pagou in ('empresa', 'socio', 'tecnico', 'cliente')$c$),
      ('comprovantes_categoria_chk', $c$categoria is null or char_length(categoria) <= 100$c$),
      ('comprovantes_valor_confirmado_chk', $c$valor_confirmado is null or valor_confirmado > 0$c$),
      ('comprovantes_forma_confirmada_chk', $c$forma_confirmada is null or forma_confirmada in (
         'dinheiro', 'cheque', 'credito', 'debito', 'credito_loja', 'boleto', 'deposito', 'pix', 'transferencia', 'outro')$c$),
      ('comprovantes_fornecedor_receita_chk', $c$fornecedor_receita is null or char_length(fornecedor_receita) <= 200$c$),
      ('comprovantes_passo_chk', $c$passo is null or passo in (
         'valor', 'para_que', 'qual_os', 'mesma_compra', 'como_pagou', 'quem_pagou', 'qual_tecnico', 'tipo_na_os', 'categoria',
         'data', 'confirmar', 'corrigir')$c$),
      ('comprovantes_tipo_na_os_chk', $c$tipo_na_os is null or tipo_na_os in ('peca', 'despesa')$c$),
      ('comprovantes_mensagens_de_dica_chk', $c$cardinality(mensagens_de_dica) <= 20$c$),
      ('comprovantes_mesma_compra_chk', $c$mesma_compra_de is null or mesma_compra_de <> id$c$),
      ('comprovantes_resumo_versao_chk', $c$resumo_versao >= 0$c$),
      ('comprovantes_perguntas_automaticas_chk', $c$perguntas_automaticas >= 0$c$),
      ('comprovantes_plano_chk', $c$plano is null or (jsonb_typeof(plano) = 'object' and octet_length(plano::text) <= 20480)$c$),
      ('comprovantes_efeitos_chk', $c$jsonb_typeof(efeitos) = 'array' and octet_length(efeitos::text) <= 20480$c$),
      ('comprovantes_conciliacao_chk', $c$conciliacao is null or conciliacao in ('verde', 'azul', 'cinza')$c$),
      ('comprovantes_cancelamento_texto_chk', $c$cancelamento_texto is null or char_length(cancelamento_texto) <= 300$c$),
      ('comprovantes_dropbox_pendente_chk', $c$dropbox_pendente is null or dropbox_pendente in ('mover', 'cancelar')$c$),
      ('comprovantes_dropbox_mover_erro_chk', $c$dropbox_mover_erro is null or char_length(dropbox_mover_erro) <= 300$c$),
      ('comprovantes_indice_mes_chk', $c$indice_mes is null or extract(day from indice_mes) = 1$c$),
      ('comprovantes_dono_cancelou_tem_data', $c$motivo_cancelamento is distinct from 'dono_cancelou' or cancelado_em is not null$c$),
      ('comprovantes_gravado_tem_destino', $c$gravado_em is null or destino is not null$c$),
      -- (revisão de 11/10/2026) SEM o CHECK "gravado de OS tem a OS": destino_os_id é "on delete set
      -- null", e apagar de verdade uma OS com CMP gravado esbarraria nele com um erro obscuro na tela.
      -- Quem garante a OS na gravação é o plano (falta "qual_os"); o número dela fica no plano gravado.
      ('comprovantes_situacao_gravada', $c$situacao not in ('gravado', 'aguardando_xml') or gravado_em is not null$c$),
      ('comprovantes_pendencias_chk', $c$pendencias <@ array['dar_entrada', 'incluir_na_os', 'acerto_tecnico',
         'classificar_no_extrato', 'dar_baixa']::text[]$c$)
    ) as t(nome, def)
  loop
    if not exists (select 1 from pg_constraint where conrelid = 'public.comprovantes'::regclass and conname = v_c.nome) then
      execute format('alter table public.comprovantes add constraint %I check (%s)', v_c.nome, v_c.def);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Índices novos
-- ---------------------------------------------------------------------------------------------
create index if not exists comprovantes_fila
  on public.comprovantes (phone_normalized, fila_ordem) where situacao = 'aguardando_vez';
create index if not exists comprovantes_na_conversa
  on public.comprovantes (phone_normalized) where situacao in ('perguntando', 'aguardando_sim');
create unique index if not exists comprovantes_uma_despesa
  on public.comprovantes (so_expense_id) where so_expense_id is not null;
create unique index if not exists comprovantes_uma_peca
  on public.comprovantes (so_part_id) where so_part_id is not null;
create index if not exists comprovantes_anotacao on public.comprovantes (anotacao_id) where anotacao_id is not null;
create index if not exists comprovantes_lancamento on public.comprovantes (payable_id) where payable_id is not null;
create index if not exists comprovantes_nota on public.comprovantes (fiscal_note_id) where fiscal_note_id is not null;
create index if not exists comprovantes_dropbox_mover
  on public.comprovantes (dropbox_mover_proxima_em) where dropbox_pendente is not null;
create index if not exists comprovantes_pendencias
  on public.comprovantes (phone_normalized) where cardinality(pendencias) > 0;
create index if not exists comprovantes_aguardando_nota
  on public.comprovantes (chave_acesso) where situacao = 'aguardando_xml';
create index if not exists comprovantes_destino_os on public.comprovantes (destino_os_id) where destino_os_id is not null;
create index if not exists comprovantes_mesma_compra on public.comprovantes (mesma_compra_de) where mesma_compra_de is not null;

-- ---------------------------------------------------------------------------------------------
-- 4. whatsapp_perguntas: o registro ÚNICO de pergunta ativa (uma aberta por telefone)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.whatsapp_perguntas (
  id                   uuid primary key default gen_random_uuid(),
  phone_normalized     text not null,
  origem               text not null,
  tipo                 text not null,
  referencia_id        uuid not null,               -- CMP, pendência ou sessão (polimórfica: sem FK)
  referencia_codigo    text,
  passo                text,
  opcoes               jsonb not null default '[]'::jsonb,
  dados                jsonb not null default '{}'::jsonb,
  status               text not null default 'aberta',
  motivo               text,
  wa_message_id        text,
  -- todos os envios desta pergunta (o primeiro, o reenvio depois de uma resposta que não serviu, o
  -- "responda sim a este resumo"): o dono cita a última mensagem que vê
  wa_message_ids       text[] not null default '{}',
  -- quando o whatsapp-send confirmou o envio (mesmo sem o id do WhatsApp): resposta mais velha que
  -- isto não é resposta a esta pergunta
  enviada_em           timestamptz,
  dedupe_key           text unique,
  aberta_em            timestamptz not null default now(),
  expira_em            timestamptz not null,
  fechada_em           timestamptz,
  resposta_message_id  uuid references public.whatsapp_messages(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint whatsapp_perguntas_phone_chk check (phone_normalized ~ '^[0-9]{10,15}$'),
  constraint whatsapp_perguntas_origem_chk check (origem in (
    'comprovante', 'assistente', 'lembrete_revisao', 'campanha_temporada', 'acompanhar_conversa')),
  constraint whatsapp_perguntas_tipo_chk check (tipo in ('pergunta', 'confirmacao', 'opcoes')),
  -- 'pergunta' é só do comprovante; as outras origens só registram confirmação/opções
  constraint whatsapp_perguntas_tipo_da_origem check ((origem = 'comprovante') = (tipo = 'pergunta')),
  constraint whatsapp_perguntas_codigo_chk check (referencia_codigo is null or char_length(referencia_codigo) <= 80),
  constraint whatsapp_perguntas_passo_chk check (passo is null or char_length(passo) <= 40),
  constraint whatsapp_perguntas_opcoes_chk check (jsonb_typeof(opcoes) = 'array' and octet_length(opcoes::text) <= 8192),
  constraint whatsapp_perguntas_dados_chk check (jsonb_typeof(dados) = 'object' and octet_length(dados::text) <= 8192),
  constraint whatsapp_perguntas_status_chk check (status in ('aberta', 'respondida', 'substituida', 'expirada', 'cancelada')),
  constraint whatsapp_perguntas_motivo_chk check (motivo is null or char_length(motivo) <= 60),
  constraint whatsapp_perguntas_wa_chk check (wa_message_id is null or char_length(wa_message_id) between 1 and 128),
  constraint whatsapp_perguntas_wa_ids_chk check (cardinality(wa_message_ids) <= 20),
  constraint whatsapp_perguntas_fechada_chk check ((status = 'aberta') = (fechada_em is null))
);

comment on table public.whatsapp_perguntas is
  'Registro único da pergunta que espera resposta do dono no WhatsApp (uma aberta por telefone): comprovantes (F2), pendências do assistente, lembretes de revisão, campanha e acompanhar-conversas. Só o admin lê; escrita só pelas RPCs pergunta_* e comprovante_* (service_role).';
comment on column public.whatsapp_perguntas.wa_message_id is 'Id do WhatsApp da mensagem da pergunta (o quotedId da resposta citada aponta para cá).';

create unique index if not exists whatsapp_perguntas_uma_aberta_por_telefone
  on public.whatsapp_perguntas (phone_normalized) where status = 'aberta';
create index if not exists whatsapp_perguntas_mensagem
  on public.whatsapp_perguntas (phone_normalized, wa_message_id) where wa_message_id is not null;
create index if not exists whatsapp_perguntas_mensagens on public.whatsapp_perguntas using gin (wa_message_ids);
create index if not exists whatsapp_perguntas_referencia on public.whatsapp_perguntas (referencia_id);
create index if not exists whatsapp_perguntas_expira on public.whatsapp_perguntas (expira_em) where status = 'aberta';

drop trigger if exists update_whatsapp_perguntas_updated_at on public.whatsapp_perguntas;
create trigger update_whatsapp_perguntas_updated_at before update on public.whatsapp_perguntas
  for each row execute function public.update_updated_at_column();

-- ---------------------------------------------------------------------------------------------
-- 5. Fila da conversa por telefone (pausa do "sair" e espaçamento do vigia)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.comprovantes_fila_do_telefone (
  phone_normalized            text primary key,
  pausada_ate                 timestamptz,
  ultima_pergunta_fechada_em  timestamptz,
  atualizado_em               timestamptz not null default now(),
  constraint comprovantes_fila_phone_chk check (phone_normalized ~ '^[0-9]{10,15}$')
);
comment on table public.comprovantes_fila_do_telefone is 'F2: pausa ("sair") e espaçamento das perguntas automáticas por telefone. Só o servidor mexe.';

-- ---------------------------------------------------------------------------------------------
-- 6. Índice do mês no Dropbox (_INDICE AAAA-MM.csv)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.comprovantes_indice_mensal (
  mes            date primary key,
  dropbox_id     text,
  caminho        text,
  rev            text,
  linhas         integer,
  pendente       boolean not null default true,
  tentativas     smallint not null default 0,
  proxima_em     timestamptz default now(),
  erro           text,
  atualizado_em  timestamptz not null default now(),
  constraint comprovantes_indice_mes_dia_1 check (extract(day from mes) = 1),
  constraint comprovantes_indice_dropbox_id_chk check (dropbox_id is null or dropbox_id ~ '^id:[A-Za-z0-9_-]+$'),
  constraint comprovantes_indice_caminho_chk check (caminho is null or char_length(caminho) <= 1000),
  constraint comprovantes_indice_rev_chk check (rev is null or char_length(rev) <= 100),
  constraint comprovantes_indice_linhas_chk check (linhas is null or linhas >= 0),
  constraint comprovantes_indice_tentativas_chk check (tentativas >= 0),
  constraint comprovantes_indice_erro_chk check (erro is null or char_length(erro) <= 300)
);
comment on table public.comprovantes_indice_mensal is 'F2: o _INDICE AAAA-MM.csv de cada mês no Dropbox (id, caminho e rev para regravar). Só o admin lê; escrita só pelo servidor.';

-- ---------------------------------------------------------------------------------------------
-- 7. Cache da BrasilAPI (nome do fornecedor pela Receita; nunca do OCR)
--    Validade: 90 dias (encontrado) e 7 dias (não encontrado), conferida por quem lê.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.cnpj_consultas (
  cnpj                text primary key,
  encontrado          boolean not null,
  razao_social        text,
  nome_fantasia       text,
  situacao_cadastral  text,
  consultado_em       timestamptz not null,
  constraint cnpj_consultas_cnpj_chk check (cnpj ~ '^[0-9]{14}$'),
  constraint cnpj_consultas_razao_chk check (razao_social is null or char_length(razao_social) <= 200),
  constraint cnpj_consultas_fantasia_chk check (nome_fantasia is null or char_length(nome_fantasia) <= 200),
  constraint cnpj_consultas_situacao_chk check (situacao_cadastral is null or char_length(situacao_cadastral) <= 60)
);
comment on table public.cnpj_consultas is 'F2: cache da consulta de CNPJ (BrasilAPI) dos fornecedores dos comprovantes. Dado público. Só o admin lê; escrita só pelo servidor.';

-- ---------------------------------------------------------------------------------------------
-- 8. RLS e privilégios (revogar de anon/authenticated POR NOME)
-- ---------------------------------------------------------------------------------------------
alter table public.whatsapp_perguntas enable row level security;
alter table public.comprovantes_fila_do_telefone enable row level security;
alter table public.comprovantes_indice_mensal enable row level security;
alter table public.cnpj_consultas enable row level security;

revoke all on table public.whatsapp_perguntas from public, anon, authenticated;
grant select on table public.whatsapp_perguntas to authenticated;
grant all on table public.whatsapp_perguntas to service_role;
drop policy if exists whatsapp_perguntas_admin_le on public.whatsapp_perguntas;
create policy whatsapp_perguntas_admin_le on public.whatsapp_perguntas
  for select to authenticated using (public.is_admin((select auth.uid())));

revoke all on table public.comprovantes_fila_do_telefone from public, anon, authenticated;
grant all on table public.comprovantes_fila_do_telefone to service_role;

revoke all on table public.comprovantes_indice_mensal from public, anon, authenticated;
grant select on table public.comprovantes_indice_mensal to authenticated;
grant all on table public.comprovantes_indice_mensal to service_role;
drop policy if exists comprovantes_indice_admin_le on public.comprovantes_indice_mensal;
create policy comprovantes_indice_admin_le on public.comprovantes_indice_mensal
  for select to authenticated using (public.is_admin((select auth.uid())));

revoke all on table public.cnpj_consultas from public, anon, authenticated;
grant select on table public.cnpj_consultas to authenticated;
grant all on table public.cnpj_consultas to service_role;
drop policy if exists cnpj_consultas_admin_le on public.cnpj_consultas;
create policy cnpj_consultas_admin_le on public.cnpj_consultas
  for select to authenticated using (public.is_admin((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 9. GRAVA DADO — OK NOMEADO: a chave da conversa. Nasce 'off'.
--    Três fontes do mesmo padrão: esta linha, o literal 'off' de _comprovante_conversa_ligada
--    (chave ausente = desligada) e o padrão do código das edges.
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('comprovante_conversa', 'off',
   'Conversa dos comprovantes (F2): on = no modo dono, o sistema pergunta sobre cada comprovante e só grava depois do sim do dono; off = avisos só informativos da F1.')
on conflict (key) do nothing;

-- Igual ao da F1 (20261011100000), com a chave nova ao lado de comprovante_fluxo.
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
    if (tg_op <> 'INSERT' and old.key = 'comprovante_conversa')
       or (tg_op <> 'DELETE' and new.key = 'comprovante_conversa') then
      raise exception 'Só o administrador liga ou desliga a conversa dos comprovantes.' using errcode = '42501';
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
-- 10. A conversa está ligada? Só com comprovante_fluxo = 'dono' E comprovante_conversa = 'on'
--     (normalizados como o modo.ts: trim, aspas em volta, minúsculas). Ausente ou erro = falso.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_conversa_ligada()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fluxo text;
  v_conversa text;
begin
  select s.value::text into v_fluxo from public.app_settings s where s.key = 'comprovante_fluxo';
  select s.value::text into v_conversa from public.app_settings s where s.key = 'comprovante_conversa';
  v_fluxo := lower(btrim(regexp_replace(btrim(coalesce(v_fluxo, '')), '^"(.*)"$', '\1')));
  v_conversa := lower(btrim(regexp_replace(btrim(coalesce(v_conversa, 'off')), '^"(.*)"$', '\1')));
  return v_fluxo = 'dono' and v_conversa = 'on';
exception when others then
  return false;
end $$;

revoke all on function public._comprovante_conversa_ligada() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_t text;
  v_tabelas text[] := array['public.whatsapp_perguntas', 'public.comprovantes_fila_do_telefone',
                            'public.comprovantes_indice_mensal', 'public.cnpj_consultas'];
begin
  foreach v_t in array v_tabelas loop
    if not (select relrowsecurity from pg_class where oid = v_t::regclass) then
      raise exception 'RLS desligada em %', v_t;
    end if;
    if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert')
       or has_table_privilege('anon', v_t, 'update') or has_table_privilege('anon', v_t, 'delete') then
      raise exception 'anon ainda alcança %', v_t;
    end if;
    if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
       or has_table_privilege('authenticated', v_t, 'delete') then
      raise exception 'authenticated escreve direto em %', v_t;
    end if;
    if not has_table_privilege('service_role', v_t, 'select') or not has_table_privilege('service_role', v_t, 'insert') then
      raise exception 'service_role não alcança %', v_t;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.comprovantes_fila_do_telefone', 'select') then
    raise exception 'authenticated lê comprovantes_fila_do_telefone (só o servidor)';
  end if;
  -- policies: só as três previstas, só TO authenticated, só SELECT
  if (select count(*) from pg_policies
       where schemaname = 'public'
         and tablename in ('whatsapp_perguntas', 'comprovantes_fila_do_telefone', 'comprovantes_indice_mensal', 'cnpj_consultas')) <> 3
     or exists (select 1 from pg_policies
                 where schemaname = 'public'
                   and tablename in ('whatsapp_perguntas', 'comprovantes_fila_do_telefone', 'comprovantes_indice_mensal', 'cnpj_consultas')
                   and (roles <> array['authenticated']::name[] or cmd <> 'SELECT'
                        or policyname not in ('whatsapp_perguntas_admin_le', 'comprovantes_indice_admin_le', 'cnpj_consultas_admin_le'))) then
    raise exception 'policies das tabelas da F2 diferentes das previstas (ou alcançando anon/public)';
  end if;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'whatsapp_perguntas'
                    and indexname = 'whatsapp_perguntas_uma_aberta_por_telefone'
                    and indexdef ilike '%unique%' and indexdef ilike '%where%aberta%') then
    raise exception 'índice único parcial do registro de perguntas ausente';
  end if;
  if not exists (select 1 from public.app_settings where key = 'comprovante_conversa') then
    raise exception 'chave comprovante_conversa não foi criada';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'app_settings_chaves_do_dono'
                    and tgrelid = 'public.app_settings'::regclass and tgenabled <> 'D') then
    raise exception 'gatilho app_settings_chaves_do_dono ausente: o financeiro mudaria comprovante_conversa';
  end if;
  if position('comprovante_conversa' in pg_get_functiondef('public._app_settings_chaves_do_dono()'::regprocedure)) = 0
     or position('comprovante_fluxo' in pg_get_functiondef('public._app_settings_chaves_do_dono()'::regprocedure)) = 0 then
    raise exception 'o gatilho das chaves do dono não protege comprovante_fluxo e comprovante_conversa';
  end if;
  if has_function_privilege('anon', 'public._app_settings_chaves_do_dono()', 'execute')
     or has_function_privilege('authenticated', 'public._app_settings_chaves_do_dono()', 'execute')
     or has_function_privilege('anon', 'public._comprovante_conversa_ligada()', 'execute')
     or has_function_privilege('authenticated', 'public._comprovante_conversa_ligada()', 'execute') then
    raise exception 'helper da conversa dos comprovantes exposto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011200000', 'comprovantes_conversa_base')
on conflict do nothing;
