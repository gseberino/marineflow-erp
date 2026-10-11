-- Comprovantes F2 (11/10/2026): o arquivo no destino final, o índice do mês e o vigia da conversa.
--
--   16 comprovante_destino_do_arquivo(id)            o que o edge precisa para a pasta e o nome final
--   17 comprovante_dropbox_movido(id, did, cam, rev, pendente)  o arquivo foi para o destino (move_v2 mantém o id)
--   18 comprovante_dropbox_mover_falhou(id, erro, pendente)     5, 15, 60, 180 min; desiste na 5ª
--   19 comprovantes_indice_do_mes(mes)               as linhas do _INDICE AAAA-MM.csv (todos os CMPs do mês)
--   20 comprovante_indice_gravado(mes, ...)          o CSV foi regravado (id, caminho, rev)
--   21 comprovante_indice_falhou(mes, erro)          mesmo backoff do 18
--   22 comprovantes_vigia_conversa(limite)           reserva o que a edge faz no vigia (subir, mover,
--                                                    índices, perguntar, CNPJ)
--
-- Redefine (create or replace, corpo da F1 + o da F2), sem mexer no pg_cron (o comando do job
-- 'comprovantes-vigia' continua o mesmo):
--   * _comprovantes_vigia_tem_trabalho(): as condições da F1 IGUAIS + uma para cada lista da RPC 22
--     (com o dono ocupado ou fora do horário, "perguntar" não conta: o cron não chama a edge);
--   * _comprovantes_manutencao(): o corpo da F1 IGUAL + fecha perguntas vencidas (e as de conversa
--     desligada), devolve à F1 os CMPs da fila quando a conversa foi desligada (lido/falhou, fora
--     da fila: voltam pelo "lote antigo") e liga as notas que chegaram aos CMPs aguardando_xml.
-- As pastas do Dropbox são constantes no código (a pasta dos comprovantes nunca vem do banco).
-- Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 16. comprovante_destino_do_arquivo
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_destino_do_arquivo(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_os jsonb;
  v_ef jsonb;
  v_conta text;
  v_label text;
  v_pid uuid;
begin
  select * into c from public.comprovantes x where x.id = p_id;
  if not found then
    raise exception 'comprovante_destino_do_arquivo: comprovante % não existe', p_id using errcode = '22023';
  end if;
  v_os := public._comprovante_os_info(c.destino_os_id);
  v_ef := public._comprovante_efetivo(c);

  if c.destino = 'pessoal' then
    v_conta := null;
  elsif v_ef->>'quem' = 'cliente' then
    v_conta := 'CLIENTE';
  elsif v_ef->>'quem' = 'tecnico' then
    v_conta := btrim('TECNICO ' || upper(split_part(public._comprovante_normalizar(v_ef->>'pagador_nome'), ' ', 1)));
  elsif v_ef->>'quem' = 'socio' then
    v_conta := btrim('BOLSO ' || upper(split_part(public._comprovante_normalizar(v_ef->>'pagador_nome'), ' ', 1)));
  elsif c.forma_confirmada = 'dinheiro' then
    v_conta := 'CAIXA';
  else
    -- A3: a conta do banco da linha que o CMP anexou
    select (e->>'payable_id')::uuid into v_pid
      from jsonb_array_elements(c.efeitos) e
     where e->>'tipo' = 'anexar_lancamento' and e->>'origem' = 'anotar'
     limit 1;
    if v_pid is not null then
      select bc.label into v_label
        from public.payables p
        join public.bank_transactions t on t.id = p.bank_transaction_id
        join public.bank_connections bc on bc.id = t.bank_connection_id
       where p.id = v_pid;
    end if;
    v_conta := coalesce(nullif(upper(public._comprovante_normalizar(v_label)), ''), 'EMPRESA');
  end if;

  return jsonb_build_object(
    'id', c.id,
    'codigo', c.codigo,
    'situacao', c.situacao,
    'cancelado', c.situacao = 'cancelado',
    'tipo', c.tipo,
    'valor', coalesce(c.valor_confirmado, c.valor)::text,
    'valor_confirmado', c.valor_confirmado is not null,
    'data', coalesce(c.data_confirmada, c.data_compra, (c.recebido_em at time zone 'America/Sao_Paulo')::date),
    'hora', c.hora_compra::text,
    'fornecedor', public._comprovante_fornecedor(c)->>'nome',
    'destino', c.destino,
    'os', case when v_os is null then null
               else jsonb_build_object('numero', v_os->'numero', 'vessel_id', v_os->'vessel_id', 'client_id', v_os->'client_id',
                                       'barco', v_os->'barco', 'cliente', v_os->'cliente',
                                       'pasta_registrada', v_os->'pasta_registrada') end,
    'forma', coalesce(c.forma_confirmada, c.forma_pagamento),
    'conta', v_conta,
    'mes', to_char(coalesce(c.indice_mes, c.data_confirmada, c.data_compra, (c.recebido_em at time zone 'America/Sao_Paulo')::date), 'YYYY-MM'),
    'dropbox_id', c.dropbox_id,
    'dropbox_caminho', c.dropbox_caminho,
    'dropbox_pendente', c.dropbox_pendente,
    'arquivo_path', c.arquivo_path,
    'arquivo_mime', c.arquivo_mime);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 17. comprovante_dropbox_movido: o arquivo foi para o destino. p_pendente = o movimento que o edge
--     FEZ (o dropbox_pendente que ele leu em comprovante_destino_do_arquivo). Se outro foi pedido no
--     meio (o "mover" ainda andava e o dono cancelou: "cancelar"), só grava onde o arquivo está e o
--     pendente novo fica, para já (senão o arquivo cancelado ficava no destino com o nome normal).
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_dropbox_movido(p_id uuid, p_dropbox_id text, p_caminho text, p_rev text, p_pendente text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_mes date;
  v_atual text;
begin
  if p_dropbox_id is null or p_dropbox_id !~ '^id:[A-Za-z0-9_-]+$' then
    raise exception 'comprovante_dropbox_movido: id do Dropbox inválido' using errcode = '22023';
  end if;
  select x.dropbox_pendente into v_atual from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception 'comprovante_dropbox_movido: comprovante % não existe', p_id using errcode = '22023';
  end if;
  update public.comprovantes x
     set dropbox_id = p_dropbox_id,
         dropbox_caminho = left(p_caminho, 1000),
         dropbox_rev = left(p_rev, 100),
         dropbox_erro = null,
         dropbox_proxima_em = null,
         dropbox_pendente = case when v_atual is not distinct from p_pendente then null else x.dropbox_pendente end,
         dropbox_mover_tentativas = 0,
         dropbox_mover_erro = null,
         dropbox_mover_proxima_em = case when v_atual is not distinct from p_pendente then null else now() end
   where x.id = p_id
  returning coalesce(x.indice_mes,
                     date_trunc('month', coalesce(x.data_confirmada, x.data_compra,
                                                  (x.recebido_em at time zone 'America/Sao_Paulo')::date))::date) into v_mes;
  insert into public.comprovantes_indice_mensal as i (mes, pendente, proxima_em, atualizado_em)
  values (v_mes, true, now(), now())
  on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();
end $$;

-- ---------------------------------------------------------------------------------------------
-- 18. comprovante_dropbox_mover_falhou: 5, 15, 60, 180 min; na 5ª desiste (fica o pendente).
--     p_pendente = o movimento que falhou; se outro foi pedido no meio, a falha não conta e o novo
--     sai já.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_dropbox_mover_falhou(p_id uuid, p_erro text, p_pendente text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_n smallint;
  v_prox timestamptz;
begin
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception 'comprovante_dropbox_mover_falhou: comprovante % não existe', p_id using errcode = '22023';
  end if;
  if c.dropbox_pendente is null then
    return jsonb_build_object('tentativas', c.dropbox_mover_tentativas, 'proxima_em', null, 'desistiu', false, 'ignorado', true);
  end if;
  if c.dropbox_pendente is distinct from p_pendente then
    update public.comprovantes x set dropbox_mover_tentativas = 0, dropbox_mover_proxima_em = now() where x.id = p_id;
    return jsonb_build_object('tentativas', 0, 'proxima_em', now(), 'desistiu', false, 'ignorado', true);
  end if;
  v_n := c.dropbox_mover_tentativas + 1;
  v_prox := case v_n
              when 1 then now() + interval '5 minutes'
              when 2 then now() + interval '15 minutes'
              when 3 then now() + interval '60 minutes'
              when 4 then now() + interval '180 minutes'
              else null end;
  update public.comprovantes x
     set dropbox_mover_tentativas = least(v_n, 32767),
         dropbox_mover_proxima_em = v_prox,
         dropbox_mover_erro = left(coalesce(nullif(p_erro, ''), 'erro'), 300)
   where x.id = p_id;
  return jsonb_build_object('tentativas', v_n, 'proxima_em', v_prox, 'desistiu', v_prox is null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 19. comprovantes_indice_do_mes: uma linha por CMP do mês (gravados pelo indice_mes; os outros
--     pelo mês da data), inclusive cancelados e os que estão nas pastas dos barcos e em PESSOAL.
--     Valores crus (o edge formata o CSV: ';', BOM, CRLF). CPF nunca. "na_os" (ajustes do dono,
--     11/10/2026): despesa (custo interno da OS), peca (comprova a peça a lançar) ou ja_lancado.
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
     and coalesce(x.indice_mes,
                  date_trunc('month', coalesce(x.data_confirmada, x.data_compra,
                                               (x.recebido_em at time zone 'America/Sao_Paulo')::date))::date) = v_mes;
  select m.dropbox_id, m.caminho, m.rev into i from public.comprovantes_indice_mensal m where m.mes = v_mes;
  return jsonb_build_object('mes', to_char(v_mes, 'YYYY-MM'), 'dropbox_id', i.dropbox_id, 'caminho', i.caminho,
                            'rev', i.rev, 'linhas', v_linhas);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 20. comprovante_indice_gravado
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_indice_gravado(p_mes date, p_dropbox_id text, p_caminho text, p_rev text, p_linhas integer)
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
    raise exception 'comprovante_indice_gravado: mês obrigatório' using errcode = '22023';
  end if;
  if p_dropbox_id is null or p_dropbox_id !~ '^id:[A-Za-z0-9_-]+$' then
    raise exception 'comprovante_indice_gravado: id do Dropbox inválido' using errcode = '22023';
  end if;
  insert into public.comprovantes_indice_mensal as i
    (mes, dropbox_id, caminho, rev, linhas, pendente, tentativas, proxima_em, erro, atualizado_em)
  values (v_mes, p_dropbox_id, left(p_caminho, 1000), left(p_rev, 100), greatest(coalesce(p_linhas, 0), 0),
          false, 0, null, null, now())
  on conflict (mes) do update
    set dropbox_id = excluded.dropbox_id, caminho = excluded.caminho, rev = excluded.rev, linhas = excluded.linhas,
        pendente = false, tentativas = 0, proxima_em = null, erro = null, atualizado_em = now();
end $$;

-- ---------------------------------------------------------------------------------------------
-- 21. comprovante_indice_falhou: 5, 15, 60, 180 min; na 5ª desiste (fica pendente, sem próxima)
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_indice_falhou(p_mes date, p_erro text)
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
    raise exception 'comprovante_indice_falhou: mês obrigatório' using errcode = '22023';
  end if;
  insert into public.comprovantes_indice_mensal (mes) values (v_mes) on conflict (mes) do nothing;
  select m.tentativas + 1 into v_n from public.comprovantes_indice_mensal m where m.mes = v_mes for update;
  v_prox := case v_n
              when 1 then now() + interval '5 minutes'
              when 2 then now() + interval '15 minutes'
              when 3 then now() + interval '60 minutes'
              when 4 then now() + interval '180 minutes'
              else null end;
  update public.comprovantes_indice_mensal m
     set tentativas = least(v_n, 32767), proxima_em = v_prox, pendente = true,
         erro = left(coalesce(nullif(p_erro, ''), 'erro'), 300), atualizado_em = now()
   where m.mes = v_mes;
  return jsonb_build_object('tentativas', v_n, 'proxima_em', v_prox, 'desistiu', v_prox is null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 22. comprovantes_vigia_conversa: reserva com prazo (como comprovantes_vigia_lote), para dois vigias
--     seguidos não pegarem o mesmo item.
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

  -- perguntar: telefones com fila em que o vigia pode perguntar agora (mesmas regras da RPC 7)
  select coalesce(jsonb_agg(t.phone order by t.phone), '[]'::jsonb) into v_perguntar
    from (select distinct x.phone_normalized as phone
            from public.comprovantes x where x.situacao = 'aguardando_vez') t
   where public._comprovante_vigia_pode(t.phone) is null;

  return jsonb_build_object(
    'subir', v_subir,
    'mover', v_mover,
    'indices', v_indices,
    'perguntar', v_perguntar,
    'cnpj', public.comprovantes_cnpj_a_consultar(null, 3));
end $$;

-- ---------------------------------------------------------------------------------------------
-- Guarda do vigia: as condições da F1 IGUAIS + as listas da RPC 22. CNPJ só de CMP na conversa
-- recebido nas últimas 24 h (com a BrasilAPI fora do ar, o cron não chama a edge para sempre).
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
                                     and k.consultado_em > now() - case when k.encontrado then interval '90 days' else interval '7 days' end)));
$$;

-- ---------------------------------------------------------------------------------------------
-- Manutenção só de banco (chamada pelo próprio pg_cron): o corpo da F1 IGUAL + (a) fecha as
-- perguntas vencidas e as de comprovante com a conversa desligada; (b) liga as notas que chegaram.
-- Cada parte no seu bloco: falha numa vira aviso e não desfaz a outra, nunca derruba o cron.
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
  return v_a + v_b + v_c + v_d;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovantes_vigia_tem_trabalho() from public, anon, authenticated;
revoke all on function public._comprovantes_manutencao() from public, anon, authenticated;

revoke all on function public.comprovante_destino_do_arquivo(uuid) from public, anon, authenticated;
revoke all on function public.comprovante_dropbox_movido(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.comprovante_dropbox_mover_falhou(uuid, text, text) from public, anon, authenticated;
revoke all on function public.comprovantes_indice_do_mes(date) from public, anon, authenticated;
revoke all on function public.comprovante_indice_gravado(date, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.comprovante_indice_falhou(date, text) from public, anon, authenticated;
revoke all on function public.comprovantes_vigia_conversa(integer) from public, anon, authenticated;

grant execute on function public.comprovante_destino_do_arquivo(uuid) to service_role;
grant execute on function public.comprovante_dropbox_movido(uuid, text, text, text, text) to service_role;
grant execute on function public.comprovante_dropbox_mover_falhou(uuid, text, text) to service_role;
grant execute on function public.comprovantes_indice_do_mes(date) to service_role;
grant execute on function public.comprovante_indice_gravado(date, text, text, text, integer) to service_role;
grant execute on function public.comprovante_indice_falhou(date, text) to service_role;
grant execute on function public.comprovantes_vigia_conversa(integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_rpcs text[] := array[
    'public.comprovante_destino_do_arquivo(uuid)',
    'public.comprovante_dropbox_movido(uuid, text, text, text, text)',
    'public.comprovante_dropbox_mover_falhou(uuid, text, text)',
    'public.comprovantes_indice_do_mes(date)',
    'public.comprovante_indice_gravado(date, text, text, text, integer)',
    'public.comprovante_indice_falhou(date, text)',
    'public.comprovantes_vigia_conversa(integer)'];
  v_redefinidas text[] := array[
    'public._comprovantes_vigia_tem_trabalho()',
    'public._comprovantes_manutencao()'];
begin
  foreach v_f in array v_rpcs || v_redefinidas loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função do Dropbox/vigia dos comprovantes exposta para anon/authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and not exists (select 1 from cron.job where jobname = 'comprovantes-vigia'
                        and command like '%_comprovantes_manutencao()%'
                        and command like '%_comprovantes_vigia_tem_trabalho()%') then
    raise exception 'cron comprovantes-vigia sem a manutenção ou sem a guarda';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011204000', 'comprovantes_dropbox_e_vigia_f2')
on conflict do nothing;
