-- Comprovantes F3 (11/10/2026): vigia da F3 e índice próprio da pasta PESSOAL.
--
-- Padrão do dono: o índice mensal da contadora (_INDICE AAAA-MM.csv) NÃO lista os PESSOAIS; a pasta
-- COMPROVANTES/PESSOAL/AAAA-MM ganha o próprio _INDICE PESSOAL AAAA-MM.csv (mesmo formato), com
-- tabela, RPCs e vigia próprios:
--   R7 comprovantes_indice_pessoal_do_mes(mes)            as linhas do índice PESSOAL do mês
--   R8 comprovante_indice_pessoal_gravado(mes, ...)       o CSV foi regravado (id, caminho, rev)
--   R9 comprovante_indice_pessoal_falhou(mes, erro)       5, 15, 60, 180 min; desiste na 5ª
-- A marcação "índice pessoal pendente" é por GATILHO em comprovantes (não redefine as funções que
-- marcam o índice do mês).
--
-- Redefine (create or replace, corpo da F2 de 20261011204000 IGUAL + só o diff), sem mexer no pg_cron
-- (o comando do job 'comprovantes-vigia' continua o mesmo):
--   * comprovantes_indice_do_mes: sem os PESSOAIS;
--   * comprovantes_vigia_conversa: + "indices_pessoais" (a mesma reserva de "indices");
--   * _comprovantes_vigia_tem_trabalho: + índice pessoal vencido + a pergunta da F3 que o vigia pode
--     fazer agora (com o dono ocupado, fora do horário ou a fila da F2 na frente, não conta);
--   * _comprovantes_manutencao: + (c) a varredura da F3 (limite de 20 CMPs na busca por passo) e (d) a
--     divisão do pagamento do técnico entre diárias e reembolso (resposta 4 do dono, 11/10/2026): a do Pix
--     anotado se aplica até 2 min depois da aprovação da linha.
-- O "quem pagou?" da regra E (ajustes do dono) é pergunta do extrato: a guarda já a conta (banco_perguntar).
--
-- DDL + funções. Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Índice próprio da pasta PESSOAL
-- ---------------------------------------------------------------------------------------------
create table if not exists public.comprovantes_indice_pessoal (
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
  constraint comprovantes_indice_pessoal_mes_dia_1 check (extract(day from mes) = 1),
  constraint comprovantes_indice_pessoal_dropbox_id_chk check (dropbox_id is null or dropbox_id ~ '^id:[A-Za-z0-9_-]+$'),
  constraint comprovantes_indice_pessoal_caminho_chk check (caminho is null or char_length(caminho) <= 1000),
  constraint comprovantes_indice_pessoal_rev_chk check (rev is null or char_length(rev) <= 100),
  constraint comprovantes_indice_pessoal_linhas_chk check (linhas is null or linhas >= 0),
  constraint comprovantes_indice_pessoal_tentativas_chk check (tentativas >= 0),
  constraint comprovantes_indice_pessoal_erro_chk check (erro is null or char_length(erro) <= 300)
);
comment on table public.comprovantes_indice_pessoal is
  'F3: o _INDICE PESSOAL AAAA-MM.csv de cada mês na pasta COMPROVANTES/PESSOAL (o índice da contadora não lista os PESSOAIS). Só o admin lê; escrita só pelo servidor.';

alter table public.comprovantes_indice_pessoal enable row level security;
revoke all on table public.comprovantes_indice_pessoal from public, anon, authenticated;
grant select on table public.comprovantes_indice_pessoal to authenticated;
grant all on table public.comprovantes_indice_pessoal to service_role;
drop policy if exists comprovantes_indice_pessoal_admin_le on public.comprovantes_indice_pessoal;
create policy comprovantes_indice_pessoal_admin_le on public.comprovantes_indice_pessoal
  for select to authenticated using (public.is_admin((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 2. Gatilho: CMP PESSOAL (agora ou antes da mudança) marca o índice pessoal do mês como pendente
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovantes_indice_pessoal_marcar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mes date;
begin
  if new.numero is not null and new.destino = 'pessoal' then
    v_mes := coalesce(new.indice_mes,
                      date_trunc('month', coalesce(new.data_confirmada, new.data_compra,
                                                   (new.recebido_em at time zone 'America/Sao_Paulo')::date))::date);
    insert into public.comprovantes_indice_pessoal as i (mes, pendente, proxima_em, atualizado_em)
    values (v_mes, true, now(), now())
    on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();
  end if;
  if tg_op = 'UPDATE' and old.numero is not null and old.destino = 'pessoal' then
    v_mes := coalesce(old.indice_mes,
                      date_trunc('month', coalesce(old.data_confirmada, old.data_compra,
                                                   (old.recebido_em at time zone 'America/Sao_Paulo')::date))::date);
    insert into public.comprovantes_indice_pessoal as i (mes, pendente, proxima_em, atualizado_em)
    values (v_mes, true, now(), now())
    on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();
  end if;
  return null;
end $$;

drop trigger if exists comprovantes_indice_pessoal_marcar on public.comprovantes;
create trigger comprovantes_indice_pessoal_marcar
  after insert or update of destino, situacao, indice_mes, dropbox_caminho, valor_confirmado, data_confirmada
  on public.comprovantes
  for each row execute function public._comprovantes_indice_pessoal_marcar();

-- ---------------------------------------------------------------------------------------------
-- 3. comprovantes_indice_do_mes (RPC 19 da F2): corpo da F2 IGUAL + sem os PESSOAIS
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_indice_do_mes(p_mes date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_linhas jsonb;
  i record;
begin
  if p_mes is null then
    raise exception 'comprovantes_indice_do_mes: mês obrigatório' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', x.codigo,
           'data', coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date),
           'hora', x.hora_compra::text,
           'tipo', x.tipo,
           'valor', coalesce(x.valor_confirmado, x.valor)::text,
           'fornecedor', public._comprovante_fornecedor(x)->>'nome',
           'cnpj', case when x.emitente_cnpj is not null and (v_raiz is null or left(x.emitente_cnpj, 8) <> v_raiz)
                        then x.emitente_cnpj end,
           'destino', x.destino,
           'os', so.service_order_number,
           'barco', nullif(btrim(v.name), ''),
           'na_os', case when x.destino is distinct from 'os' then null
                         when x.efeitos @> '[{"tipo": "despesa_os"}]'::jsonb then 'despesa'
                         when x.efeitos @> '[{"tipo": "anexar_despesa"}]'::jsonb or x.efeitos @> '[{"tipo": "anexar_peca"}]'::jsonb
                              or x.efeitos @> '[{"tipo": "comprovar_na_os", "motivo": "ambiguo"}]'::jsonb then 'ja_lancado'
                         else x.tipo_na_os end,
           'quem_pagou', x.quem_pagou,
           'forma', coalesce(x.forma_confirmada, x.forma_pagamento),
           'situacao', x.situacao,
           'pendencias', to_jsonb(x.pendencias),
           'arquivo', x.dropbox_caminho) order by x.numero), '[]'::jsonb)
    into v_linhas
    from public.comprovantes x
    left join public.service_orders so on so.id = x.destino_os_id
    left join public.vessels v on v.id = so.vessel_id
   where x.numero is not null
     and x.destino is distinct from 'pessoal'
     and coalesce(x.indice_mes,
                  date_trunc('month', coalesce(x.data_confirmada, x.data_compra,
                                               (x.recebido_em at time zone 'America/Sao_Paulo')::date))::date) = v_mes;
  select m.dropbox_id, m.caminho, m.rev into i from public.comprovantes_indice_mensal m where m.mes = v_mes;
  return jsonb_build_object('mes', to_char(v_mes, 'YYYY-MM'), 'dropbox_id', i.dropbox_id, 'caminho', i.caminho,
                            'rev', i.rev, 'linhas', v_linhas);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R7. comprovantes_indice_pessoal_do_mes: espelho da RPC 19, só destino = 'pessoal'
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_indice_pessoal_do_mes(p_mes date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_linhas jsonb;
  i record;
begin
  if p_mes is null then
    raise exception 'comprovantes_indice_pessoal_do_mes: mês obrigatório' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', x.codigo,
           'data', coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date),
           'hora', x.hora_compra::text,
           'tipo', x.tipo,
           'valor', coalesce(x.valor_confirmado, x.valor)::text,
           'fornecedor', public._comprovante_fornecedor(x)->>'nome',
           'cnpj', case when x.emitente_cnpj is not null and (v_raiz is null or left(x.emitente_cnpj, 8) <> v_raiz)
                        then x.emitente_cnpj end,
           'destino', x.destino,
           'os', so.service_order_number,
           'barco', nullif(btrim(v.name), ''),
           'na_os', case when x.destino is distinct from 'os' then null
                         when x.efeitos @> '[{"tipo": "despesa_os"}]'::jsonb then 'despesa'
                         when x.efeitos @> '[{"tipo": "anexar_despesa"}]'::jsonb or x.efeitos @> '[{"tipo": "anexar_peca"}]'::jsonb
                              or x.efeitos @> '[{"tipo": "comprovar_na_os", "motivo": "ambiguo"}]'::jsonb then 'ja_lancado'
                         else x.tipo_na_os end,
           'quem_pagou', x.quem_pagou,
           'forma', coalesce(x.forma_confirmada, x.forma_pagamento),
           'situacao', x.situacao,
           'pendencias', to_jsonb(x.pendencias),
           'arquivo', x.dropbox_caminho) order by x.numero), '[]'::jsonb)
    into v_linhas
    from public.comprovantes x
    left join public.service_orders so on so.id = x.destino_os_id
    left join public.vessels v on v.id = so.vessel_id
   where x.numero is not null
     and x.destino = 'pessoal'
     and coalesce(x.indice_mes,
                  date_trunc('month', coalesce(x.data_confirmada, x.data_compra,
                                               (x.recebido_em at time zone 'America/Sao_Paulo')::date))::date) = v_mes;
  select m.dropbox_id, m.caminho, m.rev into i from public.comprovantes_indice_pessoal m where m.mes = v_mes;
  return jsonb_build_object('mes', to_char(v_mes, 'YYYY-MM'), 'dropbox_id', i.dropbox_id, 'caminho', i.caminho,
                            'rev', i.rev, 'linhas', v_linhas);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R8. comprovante_indice_pessoal_gravado: espelho da RPC 20
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_indice_pessoal_gravado(p_mes date, p_dropbox_id text, p_caminho text, p_rev text, p_linhas integer)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
begin
  if p_mes is null then
    raise exception 'comprovante_indice_pessoal_gravado: mês obrigatório' using errcode = '22023';
  end if;
  if p_dropbox_id is null or p_dropbox_id !~ '^id:[A-Za-z0-9_-]+$' then
    raise exception 'comprovante_indice_pessoal_gravado: id do Dropbox inválido' using errcode = '22023';
  end if;
  insert into public.comprovantes_indice_pessoal as i
    (mes, dropbox_id, caminho, rev, linhas, pendente, tentativas, proxima_em, erro, atualizado_em)
  values (v_mes, p_dropbox_id, left(p_caminho, 1000), left(p_rev, 100), greatest(coalesce(p_linhas, 0), 0),
          false, 0, null, null, now())
  on conflict (mes) do update
    set dropbox_id = excluded.dropbox_id, caminho = excluded.caminho, rev = excluded.rev, linhas = excluded.linhas,
        pendente = false, tentativas = 0, proxima_em = null, erro = null, atualizado_em = now();
end $$;

-- ---------------------------------------------------------------------------------------------
-- R9. comprovante_indice_pessoal_falhou: espelho da RPC 21 (5, 15, 60, 180 min; desiste na 5ª)
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_indice_pessoal_falhou(p_mes date, p_erro text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_n smallint;
  v_prox timestamptz;
begin
  if p_mes is null then
    raise exception 'comprovante_indice_pessoal_falhou: mês obrigatório' using errcode = '22023';
  end if;
  insert into public.comprovantes_indice_pessoal (mes) values (v_mes) on conflict (mes) do nothing;
  select m.tentativas + 1 into v_n from public.comprovantes_indice_pessoal m where m.mes = v_mes for update;
  v_prox := case v_n
              when 1 then now() + interval '5 minutes'
              when 2 then now() + interval '15 minutes'
              when 3 then now() + interval '60 minutes'
              when 4 then now() + interval '180 minutes'
              else null end;
  update public.comprovantes_indice_pessoal m
     set tentativas = least(v_n, 32767), proxima_em = v_prox, pendente = true,
         erro = left(coalesce(nullif(p_erro, ''), 'erro'), 300), atualizado_em = now()
   where m.mes = v_mes;
  return jsonb_build_object('tentativas', v_n, 'proxima_em', v_prox, 'desistiu', v_prox is null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. comprovantes_vigia_conversa (RPC 22 da F2): corpo da F2 IGUAL + "indices_pessoais"
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_vigia_conversa(p_limite integer default 10)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lim integer := least(greatest(coalesce(p_limite, 10), 1), 50);
  v_subir jsonb;
  v_mover jsonb;
  v_indices jsonb;
  v_indices_pessoais jsonb;
  v_perguntar jsonb;
begin
  -- subir: CMP já na conversa cuja cópia da F1 ainda não chegou ao Dropbox (a F1 só sobe lido/falhou)
  with alvo as (
    select x.id from public.comprovantes x
     where x.numero is not null and x.dropbox_id is null
       and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
       and x.dropbox_pendente is null
       and x.dropbox_tentativas < 5 and x.dropbox_proxima_em <= now()
     order by x.dropbox_proxima_em
     limit v_lim
     for update skip locked
  ), reservados as (
    update public.comprovantes x set dropbox_proxima_em = now() + interval '10 minutes'
      from alvo where x.id = alvo.id
    returning x as linha
  )
  select coalesce(jsonb_agg(public._comprovante_dados_do_arquivo(r.linha) order by (r.linha).numero), '[]'::jsonb)
    into v_subir
    from reservados r;

  -- mover: gravado ou cancelado com o arquivo ainda fora do destino
  with alvo as (
    select x.id, x.dropbox_mover_proxima_em from public.comprovantes x
     where x.dropbox_pendente is not null and x.dropbox_mover_proxima_em <= now()
     order by x.dropbox_mover_proxima_em
     limit v_lim
     for update skip locked
  ), reservados as (
    update public.comprovantes x set dropbox_mover_proxima_em = now() + interval '10 minutes'
      from alvo where x.id = alvo.id
    returning x.id, alvo.dropbox_mover_proxima_em as quando
  )
  select coalesce(jsonb_agg(r.id order by r.quando), '[]'::jsonb) into v_mover from reservados r;

  -- índices dos meses que mudaram
  with alvo as (
    select m.mes from public.comprovantes_indice_mensal m
     where m.pendente and m.proxima_em <= now()
     order by m.mes
     limit v_lim
     for update skip locked
  ), reservados as (
    update public.comprovantes_indice_mensal m set proxima_em = now() + interval '10 minutes'
      from alvo where m.mes = alvo.mes
    returning m.mes
  )
  select coalesce(jsonb_agg(to_char(r.mes, 'YYYY-MM-DD') order by r.mes), '[]'::jsonb) into v_indices from reservados r;

  -- F3: os índices próprios da pasta PESSOAL que mudaram (a mesma reserva)
  with alvo as (
    select m.mes from public.comprovantes_indice_pessoal m
     where m.pendente and m.proxima_em <= now()
     order by m.mes
     limit v_lim
     for update skip locked
  ), reservados as (
    update public.comprovantes_indice_pessoal m set proxima_em = now() + interval '10 minutes'
      from alvo where m.mes = alvo.mes
    returning m.mes
  )
  select coalesce(jsonb_agg(to_char(r.mes, 'YYYY-MM-DD') order by r.mes), '[]'::jsonb) into v_indices_pessoais from reservados r;

  -- perguntar: telefones com fila em que o vigia pode perguntar agora (mesmas regras da RPC 7)
  select coalesce(jsonb_agg(t.phone order by t.phone), '[]'::jsonb) into v_perguntar
    from (select distinct x.phone_normalized as phone
            from public.comprovantes x where x.situacao = 'aguardando_vez') t
   where public._comprovante_vigia_pode(t.phone) is null;

  return jsonb_build_object(
    'subir', v_subir,
    'mover', v_mover,
    'indices', v_indices,
    'indices_pessoais', v_indices_pessoais,
    'perguntar', v_perguntar,
    'cnpj', public.comprovantes_cnpj_a_consultar(null, 3));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Guarda do vigia: corpo da F2 IGUAL + índice pessoal vencido + a pergunta da F3
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovantes_vigia_tem_trabalho()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    -- ═══ F1 ═══
    -- expurgo do texto do OCR
    exists (select 1 from public.comprovantes x
             where x.leitura_texto is not null and x.lido_em < now() - interval '90 days')
    -- baixar, e a rede de segurança (recebido há 1 h sem desfecho)
    or exists (select 1 from public.comprovantes x
                where x.situacao = 'recebido'
                  and (x.created_at < now() - interval '1 hour'
                       or (x.arquivo_path is null
                           and (x.download_proxima_em <= now()
                                or (x.download_proxima_em is null and x.created_at < now() - interval '5 minutes')))))
    -- entregar (o gatilho perdeu) e reenfileirar
    or exists (select 1 from public.comprovantes x
                 join public.ai_jobs j on j.id = x.job_id
                where x.situacao = 'na_fila'
                  and j.status in ('completed', 'failed', 'cancelled')
                  and ((coalesce(j.completed_at, j.updated_at) < now() - interval '2 minutes' and not (j.metadata ? 'entregue_em'))
                       or (j.status = 'failed' and j.error_code in ('deadline_exceeded', 'input_unavailable')
                           and j.metadata ? 'entregue_em' and not x.reenfileirado and x.arquivo_apagado_em is null)))
    -- Dropbox
    or exists (select 1 from public.comprovantes x
                where x.numero is not null and x.dropbox_id is null and x.situacao in ('lido', 'falhou')
                  and x.dropbox_tentativas < 5 and x.dropbox_proxima_em <= now())
    -- apagar original vencido (nunca de CMP vivo)
    or exists (select 1 from public.comprovantes x
                where x.arquivo_apagar_apos <= now() and x.arquivo_apagado_em is null and x.arquivo_path is not null
                  and not (x.numero is not null and x.situacao <> 'cancelado'))
    -- aviso que esperou 10 min ou mais
    or exists (select 1 from public.comprovantes x
                where x.modo = 'dono' and x.avisado_em is null and x.recebido_em <= now() - interval '10 minutes'
                  and (x.aviso_proximo_em is null or x.aviso_proximo_em <= now())
                  and ((x.situacao in ('lido', 'falhou') and x.numero is not null)
                       or (x.situacao = 'cancelado' and x.motivo_cancelamento in ('arquivo_repetido', 'chave_repetida'))
                       or (x.situacao = 'falhou' and x.forcado and x.numero is null)))
    -- ═══ F2 (as listas de comprovantes_vigia_conversa) ═══
    -- subir: CMP na conversa sem a cópia no Dropbox
    or exists (select 1 from public.comprovantes x
                where x.numero is not null and x.dropbox_id is null
                  and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
                  and x.dropbox_pendente is null
                  and x.dropbox_tentativas < 5 and x.dropbox_proxima_em <= now())
    -- mover para o destino final / _CANCELADOS
    or exists (select 1 from public.comprovantes x
                where x.dropbox_pendente is not null and x.dropbox_mover_proxima_em <= now())
    -- índice do mês
    or exists (select 1 from public.comprovantes_indice_mensal m where m.pendente and m.proxima_em <= now())
    -- perguntar (com o dono ocupado, fora do horário ou pausado, não conta)
    or exists (select 1 from (select distinct x.phone_normalized as phone
                                from public.comprovantes x where x.situacao = 'aguardando_vez') t
                where public._comprovante_vigia_pode(t.phone) is null)
    -- CNPJ do fornecedor sem cache (só de CMP na conversa, das últimas 24 h, e com ela ligada)
    or (public._comprovante_conversa_ligada() and exists (select 1 from public.comprovantes x
                where x.numero is not null and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
                  and x.recebido_em > now() - interval '24 hours'
                  and x.emitente_cnpj ~ '^[0-9]{14}$' and x.cnpj_confianca in ('alta', 'media') and x.supplier_id is null
                  and left(x.emitente_cnpj, 8) is distinct from public.raiz_do_cnpj_da_empresa()
                  and not exists (select 1 from public.cnpj_consultas k
                                   where k.cnpj = x.emitente_cnpj
                                     and k.consultado_em > now() - case when k.encontrado then interval '90 days' else interval '7 days' end)))
    -- ═══ F3 ═══
    -- índice próprio da pasta PESSOAL
    or exists (select 1 from public.comprovantes_indice_pessoal m where m.pendente and m.proxima_em <= now())
    -- a pergunta do extrato que o vigia pode fazer agora (horário, espaçamento, limite; a F2 primeiro)
    or exists (select 1 from (select distinct x.phone_normalized as phone
                                from public.comprovantes x
                               where x.banco_perguntar and x.situacao = 'aguardando_banco'
                                 and x.banco_perguntas < 3
                                 and (x.banco_ultima_pergunta_em is null or x.banco_ultima_pergunta_em <= now() - interval '4 hours')) t
                where public._comprovante_banco_pode(t.phone) is null);
$$;

-- ---------------------------------------------------------------------------------------------
-- 6. Manutenção só de banco (chamada pelo próprio pg_cron): corpo da F2 IGUAL + (c) a varredura da F3 e
--    (d) as divisões pendentes do pagamento do técnico (resposta 4 do dono)
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovantes_manutencao()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_a integer := 0;
  v_b integer := 0;
  v_c integer := 0;
  v_d integer := 0;
  v_e integer := 0;
  v_f integer := 0;
  v_varredura jsonb;
  r record;
begin
  begin
    update public.comprovantes x set leitura_texto = null
     where x.leitura_texto is not null and x.lido_em < now() - interval '90 days';
    get diagnostics v_a = row_count;

    update public.ai_jobs j
       set response = case when jsonb_typeof(j.response->'data') = 'object' and (j.response->'data') ? 'texto'
                           then jsonb_set(j.response, '{data}', (j.response->'data') #- '{texto}')
                           else j.response end,
           input = case when jsonb_typeof(j.input->'arquivo') = 'object' and (j.input->'arquivo') ? 'url'
                        then j.input #- '{arquivo,url}'
                        else j.input end
     where j.metadata->>'tipo' = 'comprovante_leitura'
       and j.status in ('completed', 'failed', 'cancelled')
       and coalesce(j.completed_at, j.updated_at) < now() - interval '1 hour'
       and ((jsonb_typeof(j.response->'data') = 'object' and (j.response->'data') ? 'texto')
            or (jsonb_typeof(j.input->'arquivo') = 'object' and (j.input->'arquivo') ? 'url'));
    get diagnostics v_b = row_count;
  exception when others then
    raise warning 'comprovantes: manutenção do vigia falhou: %', sqlstate;
  end;

  -- (a) perguntas vencidas / de comprovante com a conversa desligada (o CMP volta para a fila)
  begin
    for r in
      select distinct w.phone_normalized
        from public.whatsapp_perguntas w
       where w.status = 'aberta'
         and (w.expira_em <= now() or (w.origem = 'comprovante' and not public._comprovante_conversa_ligada()))
    loop
      perform public._pergunta_limpar(r.phone_normalized);
      v_c := v_c + 1;
    end loop;
    -- conversa desligada: os CMPs que esperavam a vez voltam a ser os da F1 (lido/falhou, fora da
    -- fila; as respostas ficam) — senão ficavam em aguardando_vez para sempre, fora do aviso da F1
    -- e do "lote antigo"
    if not public._comprovante_conversa_ligada() then
      for r in
        select x.id from public.comprovantes x
         where x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim') and x.gravado_em is null
           and not exists (select 1 from public.whatsapp_perguntas w where w.referencia_id = x.id and w.status = 'aberta')
      loop
        perform public._comprovante_sair_da_conversa(r.id);
        v_c := v_c + 1;
      end loop;
    end if;
  exception when others then
    raise warning 'comprovantes: limpeza das perguntas falhou: %', sqlstate;
  end;

  -- (b) notas que chegaram para CMPs aguardando_xml
  begin
    v_d := public._comprovante_aplicar_notas_chegadas();
  exception when others then
    raise warning 'comprovantes: ligar notas que chegaram falhou: %', sqlstate;
  end;
  -- (c) F3: re-valida as ligações, liga pela anotação, explica, busca quem tem linha nova, abandona,
  --     notas e e-mail (limite de 20 CMPs na busca por passo)
  begin
    v_varredura := public._comprovantes_banco_varrer(20, 'manutencao');
    v_e := coalesce((v_varredura->>'ligados')::integer, 0) + coalesce((v_varredura->>'explicadas')::integer, 0)
           + coalesce((v_varredura->>'desligados')::integer, 0) + coalesce((v_varredura->>'abandonados')::integer, 0)
           + coalesce((v_varredura->>'notas')::integer, 0);
  exception when others then
    raise warning 'comprovantes: varredura do extrato falhou: %', sqlstate;
  end;
  -- (d) resposta 4 do dono: o Pix ao técnico anotado com a divisão (diárias e reembolso) se divide quando a
  --     linha dele é aprovada — venha a aprovação da tela, do assistente ou da regra por CPF
  begin
    v_f := public._diarias_aplicar_divisoes_pendentes(20);
  exception when others then
    raise warning 'diárias: divisões pendentes do pagamento falharam: %', sqlstate;
  end;
  return v_a + v_b + v_c + v_d + v_e + v_f;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovantes_indice_pessoal_marcar() from public, anon, authenticated, service_role;
revoke all on function public._comprovantes_vigia_tem_trabalho() from public, anon, authenticated;
revoke all on function public._comprovantes_manutencao() from public, anon, authenticated;
revoke all on function public.comprovantes_indice_do_mes(date) from public, anon, authenticated;
revoke all on function public.comprovantes_vigia_conversa(integer) from public, anon, authenticated;
revoke all on function public.comprovantes_indice_pessoal_do_mes(date) from public, anon, authenticated;
revoke all on function public.comprovante_indice_pessoal_gravado(date, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.comprovante_indice_pessoal_falhou(date, text) from public, anon, authenticated;
grant execute on function public.comprovantes_indice_do_mes(date) to service_role;
grant execute on function public.comprovantes_vigia_conversa(integer) to service_role;
grant execute on function public.comprovantes_indice_pessoal_do_mes(date) to service_role;
grant execute on function public.comprovante_indice_pessoal_gravado(date, text, text, text, integer) to service_role;
grant execute on function public.comprovante_indice_pessoal_falhou(date, text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_rpcs text[] := array[
    'public.comprovantes_indice_pessoal_do_mes(date)',
    'public.comprovante_indice_pessoal_gravado(date, text, text, text, integer)',
    'public.comprovante_indice_pessoal_falhou(date, text)',
    'public.comprovantes_indice_do_mes(date)',
    'public.comprovantes_vigia_conversa(integer)'];
  v_redefinidas text[] := array[
    'public._comprovantes_vigia_tem_trabalho()',
    'public._comprovantes_manutencao()',
    'public._comprovantes_indice_pessoal_marcar()'];
begin
  foreach v_f in array v_rpcs || v_redefinidas loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função do vigia/índice pessoal exposta para anon/authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  if has_function_privilege('service_role', 'public._comprovantes_indice_pessoal_marcar()', 'execute') then
    raise exception 'a função do gatilho do índice pessoal está alcançável';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.comprovantes_indice_pessoal'::regclass) then
    raise exception 'RLS desligada em comprovantes_indice_pessoal';
  end if;
  if has_table_privilege('anon', 'public.comprovantes_indice_pessoal', 'select')
     or has_table_privilege('anon', 'public.comprovantes_indice_pessoal', 'insert')
     or has_table_privilege('authenticated', 'public.comprovantes_indice_pessoal', 'insert')
     or has_table_privilege('authenticated', 'public.comprovantes_indice_pessoal', 'update')
     or has_table_privilege('authenticated', 'public.comprovantes_indice_pessoal', 'delete')
     or not has_table_privilege('service_role', 'public.comprovantes_indice_pessoal', 'insert') then
    raise exception 'privilégios de comprovantes_indice_pessoal diferentes dos previstos';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'comprovantes_indice_pessoal') <> 1
     or not exists (select 1 from pg_policies
                     where schemaname = 'public' and tablename = 'comprovantes_indice_pessoal'
                       and policyname = 'comprovantes_indice_pessoal_admin_le' and cmd = 'SELECT'
                       and roles = array['authenticated']::name[]) then
    raise exception 'policy de comprovantes_indice_pessoal diferente da prevista';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'comprovantes_indice_pessoal_marcar'
                    and tgrelid = 'public.comprovantes'::regclass and tgenabled <> 'D') then
    raise exception 'gatilho do índice pessoal ausente';
  end if;
  if position('_comprovantes_banco_varrer' in pg_get_functiondef('public._comprovantes_manutencao()'::regprocedure)) = 0
     or position('_diarias_aplicar_divisoes_pendentes' in pg_get_functiondef('public._comprovantes_manutencao()'::regprocedure)) = 0 then
    raise exception 'a manutenção não chama a varredura da F3 ou a divisão pendente do pagamento do técnico';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and not exists (select 1 from cron.job where jobname = 'comprovantes-vigia'
                        and command like '%_comprovantes_manutencao()%'
                        and command like '%_comprovantes_vigia_tem_trabalho()%') then
    raise exception 'cron comprovantes-vigia sem a manutenção ou sem a guarda';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011304000', 'comprovantes_vigia_e_indice_pessoal')
on conflict do nothing;
