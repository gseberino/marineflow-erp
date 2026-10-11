-- Comprovantes F3 (11/10/2026): colunas da conciliação com o extrato.
--
-- A F3 procura, para cada CMP gravado que espera o banco (Pix/transferência, boleto, débito, crédito
-- da empresa), a linha do extrato que é dele; liga o CMP a UMA linha (comprovantes.bank_transaction_id,
-- índice único) e "explica" a linha (classifica a proposta da fila do Extrato com os dados do CMP,
-- anexa ao lançamento que já existe ou dá baixa na conta a pagar que o CMP anexou). As RPCs moram em
-- 20261011302000; esta migration só prepara o terreno:
--   * colunas novas em comprovantes: a regra de busca, a última avaliação (candidatas, hash, quando),
--     a pergunta da F3 (perguntar, tentativas, última), as linhas que o dono recusou, quando a linha
--     foi explicada e quando a NF-e esperada chegou por e-mail;
--   * o CHECK comprovantes_situacao_gravada passa a cobrir aguardando_banco, conciliado e abandonado;
--   * o CHECK comprovantes_pendencias_chk ganha "conferir_estorno" (a linha ligada foi estornada no
--     banco: o dono decide o que fazer com a despesa da OS);
--   * bank_transactions.nome_pelo_comprovante: a loja do CMP para a linha sem nome (o débito do C6
--     chega como "DEBITO DE CARTAO", sem loja nem documento) — o Extrato mostra. Fora da lista
--     PREENCHIVEIS do banking-sync: o Pluggy nunca a sobrescreve;
--   * índices: uma linha, um CMP não cancelado (comprovantes_uma_linha), e os da varredura.
--
-- FK só no sentido comprovantes → bank_transactions (a da F2, on delete set null). Nenhuma coluna nova
-- em bank_transactions aponta para comprovantes: o PostgREST não vê dois caminhos (PGRST201).
--
-- DDL. Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Colunas novas em comprovantes
-- ---------------------------------------------------------------------------------------------
alter table public.comprovantes
  add column if not exists banco_regra               text,
  add column if not exists banco_so_registro         boolean not null default false,
  add column if not exists banco_candidatos          jsonb not null default '[]'::jsonb,
  add column if not exists banco_avaliado_em         timestamptz,
  add column if not exists banco_hash                text,
  add column if not exists banco_perguntar           boolean not null default false,
  add column if not exists banco_perguntas           smallint not null default 0,
  add column if not exists banco_ultima_pergunta_em  timestamptz,
  add column if not exists banco_recusados           uuid[] not null default '{}',
  add column if not exists linha_explicada_em        timestamptz,
  add column if not exists nota_no_email_em          timestamptz;

comment on column public.comprovantes.banco_regra is 'F3: como o CMP procura a linha do extrato (pix, boleto, debito, credito). Nulo = não procura (dinheiro, NF-e, sócio, técnico, cliente...).';
comment on column public.comprovantes.banco_so_registro is 'F3: PESSOAL pago por forma bancária/crédito: os candidatos só ficam registrados (nunca pergunta, nunca liga, nunca reserva a linha) até o dono decidir (pendência 11.1).';
comment on column public.comprovantes.banco_candidatos is 'F3: as candidatas da última avaliação (até 3, forma Candidata da spec 3.7).';
comment on column public.comprovantes.banco_avaliado_em is 'F3: quando as candidatas foram calculadas pela última vez.';
comment on column public.comprovantes.banco_hash is 'F3: md5 da lista mostrada (ids, ações e "há mais"): mudou = a pergunta aberta é refeita.';
comment on column public.comprovantes.banco_perguntar is 'F3: há pergunta "apareceu no extrato, ligo?" a fazer (verde ou azul, com a conversa ligada).';
comment on column public.comprovantes.banco_perguntas is 'F3: perguntas automáticas (vigia) já feitas sobre a linha do extrato; no máximo 3.';
comment on column public.comprovantes.banco_ultima_pergunta_em is 'F3: quando a pergunta da linha do extrato foi aberta pela última vez (espaçamento de 4 h do vigia).';
comment on column public.comprovantes.banco_recusados is 'F3: as linhas do extrato que o dono disse que NÃO são deste CMP (nunca voltam como candidatas).';
comment on column public.comprovantes.linha_explicada_em is 'F3: quando a linha ligada foi explicada (proposta classificada, lançamento anexado ou conta baixada). Nulo com a linha ligada = a varredura tenta de novo.';
comment on column public.comprovantes.nota_no_email_em is 'F3: a NF-e que o CMP espera (aguardando_xml) chegou anexada a um e-mail mas ainda não foi importada.';
comment on column public.comprovantes.bank_transaction_id is 'F3: a linha do extrato ligada a este CMP (uma linha, um CMP não cancelado: comprovantes_uma_linha).';
comment on column public.comprovantes.conciliacao is 'F3: o nível da última avaliação (verde, azul, cinza) ou o da ligação.';
comment on column public.comprovantes.conciliado_em is 'F3: quando o CMP foi ligado à linha do extrato.';

-- ---------------------------------------------------------------------------------------------
-- 2. CHECKs (por nome, só se ainda não existem; o da situação gravada é recriado com os estados
--    da F3)
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_c record;
begin
  if exists (select 1 from pg_constraint
              where conrelid = 'public.comprovantes'::regclass and conname = 'comprovantes_situacao_gravada'
                and pg_get_constraintdef(oid) not like '%conciliado%') then
    alter table public.comprovantes drop constraint comprovantes_situacao_gravada;
  end if;
  -- a lista fechada de pendências ganha "conferir_estorno" (a linha ligada foi estornada no banco: o
  -- dono decide o que fazer com a despesa da OS). Lista fechada: pendência nova sem o CHECK novo
  -- derrubaria a varredura inteira do CMP.
  if exists (select 1 from pg_constraint
              where conrelid = 'public.comprovantes'::regclass and conname = 'comprovantes_pendencias_chk'
                and pg_get_constraintdef(oid) not like '%conferir_estorno%') then
    alter table public.comprovantes drop constraint comprovantes_pendencias_chk;
  end if;

  for v_c in
    select * from (values
      ('comprovantes_situacao_gravada',
       $c$situacao not in ('gravado', 'aguardando_xml', 'aguardando_banco', 'conciliado', 'abandonado') or gravado_em is not null$c$),
      ('comprovantes_pendencias_chk', $c$pendencias <@ array['dar_entrada', 'incluir_na_os', 'cobrar_a_parte', 'acerto_tecnico',
         'classificar_no_extrato', 'ajustar_recebiveis', 'dar_baixa', 'conferir_estorno']::text[]$c$),
      ('comprovantes_banco_regra_chk', $c$banco_regra is null or banco_regra in ('pix', 'boleto', 'debito', 'credito')$c$),
      ('comprovantes_banco_candidatos_chk',
       $c$jsonb_typeof(banco_candidatos) = 'array' and octet_length(banco_candidatos::text) <= 8192$c$),
      ('comprovantes_banco_hash_chk', $c$banco_hash is null or char_length(banco_hash) <= 64$c$),
      ('comprovantes_banco_perguntas_chk', $c$banco_perguntas >= 0$c$),
      ('comprovantes_banco_recusados_chk', $c$cardinality(banco_recusados) <= 50$c$)
    ) as t(nome, def)
  loop
    if not exists (select 1 from pg_constraint where conrelid = 'public.comprovantes'::regclass and conname = v_c.nome) then
      execute format('alter table public.comprovantes add constraint %I check (%s)', v_c.nome, v_c.def);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. bank_transactions.nome_pelo_comprovante (a loja do CMP para a linha sem nome)
-- ---------------------------------------------------------------------------------------------
alter table public.bank_transactions add column if not exists nome_pelo_comprovante text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.bank_transactions'::regclass and conname = 'bank_transactions_nome_pelo_comprovante_chk') then
    alter table public.bank_transactions add constraint bank_transactions_nome_pelo_comprovante_chk
      check (nome_pelo_comprovante is null or char_length(nome_pelo_comprovante) <= 160);
  end if;
end $$;

comment on column public.bank_transactions.nome_pelo_comprovante is
  'F3: a loja do comprovante ligado, para a linha sem nome (débito do C6). Só as RPCs dos comprovantes escrevem; o Pluggy nunca preenche.';

-- ---------------------------------------------------------------------------------------------
-- 4. Índices (a tabela bank_transactions tem ~2.500 linhas: create index não concorrente)
-- ---------------------------------------------------------------------------------------------
create unique index if not exists comprovantes_uma_linha
  on public.comprovantes (bank_transaction_id) where bank_transaction_id is not null and situacao <> 'cancelado';
create index if not exists comprovantes_aguardando_banco
  on public.comprovantes (aguardando_banco_desde) where situacao = 'aguardando_banco';
create index if not exists comprovantes_banco_perguntar
  on public.comprovantes (phone_normalized) where banco_perguntar;
create index if not exists comprovantes_linha_por_explicar
  on public.comprovantes (bank_transaction_id) where situacao = 'conciliado' and linha_explicada_em is null;
create index if not exists bank_transactions_debito_por_valor
  on public.bank_transactions (amount, transaction_date) where transaction_type = 'debit';

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_col text;
begin
  -- as colunas novas de comprovantes seguem a tabela: anon nada, authenticated só lê (policy do admin)
  foreach v_col in array array['banco_regra', 'banco_so_registro', 'banco_candidatos', 'banco_avaliado_em', 'banco_hash',
                               'banco_perguntar', 'banco_perguntas', 'banco_ultima_pergunta_em', 'banco_recusados',
                               'linha_explicada_em', 'nota_no_email_em'] loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'comprovantes' and column_name = v_col) then
      raise exception 'coluna comprovantes.% não foi criada', v_col;
    end if;
    if has_column_privilege('anon', 'public.comprovantes', v_col, 'select')
       or has_column_privilege('anon', 'public.comprovantes', v_col, 'update') then
      raise exception 'anon alcança comprovantes.%', v_col;
    end if;
    if has_column_privilege('authenticated', 'public.comprovantes', v_col, 'insert')
       or has_column_privilege('authenticated', 'public.comprovantes', v_col, 'update') then
      raise exception 'authenticated escreve comprovantes.%', v_col;
    end if;
  end loop;
  if not (select relrowsecurity from pg_class where oid = 'public.comprovantes'::regclass) then
    raise exception 'RLS desligada em comprovantes';
  end if;
  -- bank_transactions: o anon pode ter grant de tabela (padrão do Supabase), mas nenhuma policy o
  -- alcança — o conjunto de policies continua o de hoje (4, todas TO authenticated)
  if not has_column_privilege('service_role', 'public.bank_transactions', 'nome_pelo_comprovante', 'update') then
    raise exception 'service_role não alcança bank_transactions.nome_pelo_comprovante';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.bank_transactions'::regclass) then
    raise exception 'RLS desligada em bank_transactions';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'bank_transactions'
                and (roles && array['anon', 'public']::name[] or roles <> array['authenticated']::name[])) then
    raise exception 'há policy de bank_transactions alcançando anon/public';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'bank_transactions') <> 4 then
    raise exception 'o conjunto de policies de bank_transactions mudou (eram 4, todas TO authenticated)';
  end if;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'comprovantes' and indexname = 'comprovantes_uma_linha'
                    and indexdef ilike '%unique%' and indexdef ilike '%cancelado%') then
    raise exception 'índice único comprovantes_uma_linha ausente';
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.comprovantes'::regclass and conname = 'comprovantes_situacao_gravada'
                    and pg_get_constraintdef(oid) like '%conciliado%' and pg_get_constraintdef(oid) like '%abandonado%') then
    raise exception 'CHECK comprovantes_situacao_gravada sem os estados da F3';
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.comprovantes'::regclass and conname = 'comprovantes_pendencias_chk'
                    and pg_get_constraintdef(oid) like '%conferir_estorno%' and pg_get_constraintdef(oid) like '%acerto_tecnico%') then
    raise exception 'CHECK comprovantes_pendencias_chk sem a pendência conferir_estorno da F3';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011300000', 'comprovantes_conciliacao_base')
on conflict do nothing;
