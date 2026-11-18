-- Revisão do documento (orçamento / OS / fatura): o número que sai impresso ("Rev. 3"), no nome do arquivo e no
-- Dropbox, e que a tela e o assistente consultam.
--
-- Pedido e decisões do dono (17/11/2026), plano em D:/IA-HBR/Trabalho/revisao-documentos/PLANO.md:
--   1A  a revisão só sobe quando muda o que o CLIENTE LÊ (itens, valores, condições, validade, observações...);
--       situação, técnico, nota interna, pagamento recebido não sobem;
--   2A  sobe ao GERAR/ENVIAR o documento, se o conteúdo mudou desde o último PDF (cinco edições seguidas = uma
--       revisão);
--   3A  a primeira emissão é a Rev. 1;
--   4   extras: a revisão que o cliente recebeu, a que ele aprovou/assinou, "substitui a Rev. N de dd/mm".
--
-- Por que não é o `versao` do histórico (20270121100000): aquele retrato guarda o documento INTEIRO — status,
-- técnicos, parcela paga — e sobe a cada marco interno; o cliente veria "Rev. 7" num orçamento que mudou uma vez.
-- A revisão continua ligada a ele: cada revisão emitida aponta para o retrato do histórico daquele momento
-- (versao_historico), e é por ele que o "o que mudou da Rev. 2 para a 3" sai pronto (documento_historico/comparar).
--
-- Por que uma tabela e não mais uma ação no audit_log: a revisão é contador + estado (enviada, aprovada) que muda
-- depois de gravada; o audit_log é só-inserção, com lista fechada de ações espelhada no front e três leitores
-- (linha do tempo, consulta, restauração) que teriam de aprender a ação nova.
--
-- Contador por documento E tipo: "ORÇ-00136 Rev. 3" e, depois de convertido, a OS do mesmo número começa na Rev. 1.

-- ─── 1. Tabela ─────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.documento_revisoes (
  id               uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  tipo             text not null check (tipo in ('quote', 'service_order', 'invoice')),
  revisao          integer not null check (revisao > 0),
  hash             text not null,
  codigo           text not null check (codigo ~ '^[0-9A-F]{4}-[0-9A-F]{4}$'),
  emitida_em       timestamptz not null default clock_timestamp(),
  ator_id          uuid,
  origem           text,
  versao_historico integer,
  enviada_em       timestamptz,
  enviada_via      text,
  aprovada_em      timestamptz,
  assinada_em      timestamptz,
  unique (service_order_id, tipo, revisao)
);
create index if not exists documento_revisoes_codigo on public.documento_revisoes (codigo);

comment on table public.documento_revisoes is
  'Revisões emitidas de cada documento (Rev. N impressa no PDF). Sobe só quando muda o conteúdo que o cliente lê '
  '(private.documento_conteudo_impresso). Escrita só pelas funções documento_revisao_*; ninguém lê direto.';
comment on column public.documento_revisoes.codigo is 'Código de conferência impresso no rodapé (XXXX-XXXX).';
comment on column public.documento_revisoes.versao_historico is 'Retrato do histórico (audit_log.versao) no momento da emissão.';

alter table public.documento_revisoes enable row level security;
revoke all on public.documento_revisoes from public, anon, authenticated;
grant all on public.documento_revisoes to service_role;

-- ─── 2. O que o cliente lê ─────────────────────────────────────────────────────────────────────────
-- Lista FECHADA, espelho do que _shared/pdf/dados.ts monta e documento.ts imprime. Coluna nova no documento
-- impresso tem de entrar aqui, senão mudá-la não sobe a revisão (src/lib/revisao-conteudo.test.ts confere).
-- Texto vazio e nulo contam como iguais (o formulário troca um pelo outro sem o usuário mexer).
create or replace function private.revisao_campos(p_linha jsonb, p_campos text[])
returns jsonb language sql immutable set search_path = public, pg_temp as $$
  select coalesce(jsonb_object_agg(c, nullif(p_linha ->> c, '')), '{}'::jsonb)
    from unnest(p_campos) c;
$$;

create or replace function private.documento_conteudo_impresso(p_os uuid, p_tipo text)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'cabecalho', private.revisao_campos(to_jsonb(so), array[
      'service_order_number', 'client_id', 'vessel_id', 'marina_id', 'created_at', 'problem_description',
      'extra_notes', 'grand_total', 'labor_cost_total', 'parts_cost_total', 'travel_cost_total',
      'is_travel_billable', 'travel_hours', 'ferry_cost', 'travel_type', 'discount_amount',
      'discount_services_pct', 'discount_parts_pct', 'tax_amount', 'operational_cost_total',
      'subcontract_cost_total', 'card_fee_amount', 'card_installments', 'payment_conditions',
      'payment_condition_preset_id', 'custom_payment_installments', 'payment_method_preferred',
      'quote_validity_days', 'quote_validity_date']
      -- Só a OS e a fatura imprimem a data agendada e as notas do técnico: reagendar não muda o orçamento.
      || case when p_tipo <> 'quote' then array['scheduled_start_at', 'technician_notes'] else array[]::text[] end
      -- E só a fatura imprime as observações financeiras.
      || case when p_tipo = 'invoice' then array['financial_notes'] else array[]::text[] end),
    'cliente', (select private.revisao_campos(to_jsonb(c), array['name', 'cpf_cnpj', 'phone', 'email',
                                                                  'address_line_1', 'city', 'state'])
                  from public.clients c where c.id = so.client_id),
    'unidade', (select private.revisao_campos(to_jsonb(v), array['name', 'asset_type', 'manufacturer', 'model',
                                                                  'year', 'hull_id_or_registration'])
                  from public.vessels v where v.id = so.vessel_id),
    'local', (select private.revisao_campos(to_jsonb(m), array['name', 'city'])
                from public.marinas m where m.id = so.marina_id),
    'servicos', coalesce((
      select jsonb_agg(private.revisao_campos(to_jsonb(s), array['service_id', 'name_snapshot', 'description_snapshot',
                         'billing_unit_snapshot', 'quantity', 'unit_price_snapshot', 'line_total', 'discount_amount'])
                       order by s.created_at, s.id)
        from public.service_order_services s where s.service_order_id = so.id), '[]'::jsonb),
    'pecas', coalesce((
      select jsonb_agg(private.revisao_campos(to_jsonb(p), array['product_id', 'quantity', 'unit_sale_snapshot',
                         'line_total_sale', 'discount_amount'])
                       || private.revisao_campos(to_jsonb(pr), array['name', 'sku'])
                       order by p.created_at, p.id)
        from public.service_order_parts p
        left join public.products pr on pr.id = p.product_id
       where p.service_order_id = so.id), '[]'::jsonb),
    -- As despesas que o documento mostra: pagas pela empresa e não nascidas de comprovante (despesasDoCliente).
    'despesas', coalesce((
      select jsonb_agg(private.revisao_campos(to_jsonb(e), array['category', 'description', 'amount'])
                       order by e.created_at, e.id)
        from public.service_order_expenses e
       where e.service_order_id = so.id and e.paid_by = 'company' and nullif(to_jsonb(e) ->> 'origem_codigo', '') is null),
      '[]'::jsonb),
    'condicao', (select private.revisao_campos(to_jsonb(pc), array['label', 'installments'])
                   from public.payment_condition_presets pc where pc.id = so.payment_condition_preset_id),
    -- O levantamento que vai ao documento: o fechado mais recente (buildSurveyForPdf).
    'levantamento', (
      select jsonb_build_object(
               'em', sv.answered_at, 'porque', sv.confidence_rationale,
               'respostas', (select jsonb_agg(jsonb_build_object('q', a.question_snapshot, 'r', nullif(a.answer_value, ''),
                                                                 'pulou', nullif(a.skipped_reason, ''),
                                                                 'foto', a.photo_path is not null) order by a.seq, a.id)
                               from public.service_survey_answers a where a.survey_id = sv.id))
        from public.service_surveys sv
       where sv.service_order_id = so.id and sv.status = 'closed'
       order by sv.answered_at desc nulls last
       limit 1),
    'fotos', coalesce((select jsonb_agg(ph.storage_path order by ph.created_at, ph.id)
                         from public.service_order_photos ph where ph.service_order_id = so.id), '[]'::jsonb),
    'empresa', (select coalesce(jsonb_object_agg(a.key, nullif(a.value, '')), '{}'::jsonb)
                  from public.app_settings a
                 where a.key in ('terms_general', 'terms_warranty', 'terms_cancellation', 'terms_delivery',
                                 'terms_responsibilities', 'bank_name', 'bank_agency', 'bank_account', 'pix_key'))
  )
  from public.service_orders so
  where so.id = p_os;
$$;

-- ─── 3. Quem pode emitir / consultar ───────────────────────────────────────────────────────────────
-- Mesmo alcance da leitura da OS (pg_policies em 17/11/2026): usuário logado lê toda OS; o cliente do link só a
-- OS do token no cabeçalho; o servidor (service_role) tudo.
create or replace function private.revisao_pode(p_os uuid, p_so_logado boolean)
returns boolean language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_papel text;
begin
  begin v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  exception when others then v_papel := ''; end;
  if v_papel = 'service_role' or auth.uid() is not null then
    return true;
  end if;
  if p_so_logado or v_papel <> 'anon' then
    return false;
  end if;
  begin
    return exists (select 1 from public.service_orders so
                    where so.id = p_os and so.share_token is not null
                      and so.share_token::text = public.share_token_da_requisicao());
  exception when others then
    return false;   -- cabeçalhos ilegíveis: sem token não há acesso
  end;
end $$;

-- ─── 4. Emitir ─────────────────────────────────────────────────────────────────────────────────────
-- Devolve a revisão do conteúdo de AGORA: a última, se nada do que o cliente lê mudou; senão grava a próxima.
create or replace function private.documento_revisao_emitir(p_os uuid, p_tipo text)
returns public.documento_revisoes language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_conteudo jsonb;
  v_hash     text;
  v_ult      public.documento_revisoes;
  v_nova     public.documento_revisoes;
  v_ctx      record;
  v_n        integer;
begin
  if p_tipo not in ('quote', 'service_order', 'invoice') then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('documento_revisao:' || p_os::text || ':' || p_tipo, 0));

  v_conteudo := private.documento_conteudo_impresso(p_os, p_tipo);
  if v_conteudo is null then
    return null;   -- OS inexistente
  end if;
  v_hash := md5(v_conteudo::text);

  select * into v_ult from public.documento_revisoes r
   where r.service_order_id = p_os and r.tipo = p_tipo
   order by r.revisao desc limit 1;
  if v_ult.id is not null and v_ult.hash = v_hash then
    return v_ult;
  end if;

  v_n := coalesce(v_ult.revisao, 0) + 1;
  select * into v_ctx from private.historico_contexto();
  insert into public.documento_revisoes
    (service_order_id, tipo, revisao, hash, codigo, ator_id, origem, versao_historico)
  values
    (p_os, p_tipo, v_n, v_hash,
     upper(substr(md5(p_os::text || ':' || p_tipo || ':' || v_n || ':' || v_hash), 1, 4) || '-' ||
           substr(md5(p_os::text || ':' || p_tipo || ':' || v_n || ':' || v_hash), 5, 4)),
     v_ctx.ator_id, v_ctx.origem,
     -- O retrato do histórico deste momento (grava um novo só se o documento mudou desde o último).
     private.documento_versionar(p_os, format('revisão %s', v_n)))
  returning * into v_nova;
  return v_nova;
end $$;

-- O tipo que a ordem gera hoje (documentTypeFor): rascunho é orçamento, o resto é OS.
create or replace function private.revisao_tipo_da_ordem(p_status text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select case when p_status = 'draft' then 'quote' else 'service_order' end;
$$;

create or replace function private.revisao_json(p_r public.documento_revisoes)
returns jsonb language sql stable set search_path = public, pg_temp as $$
  select case when p_r.id is null then null else jsonb_build_object(
    'revisao', p_r.revisao, 'codigo', p_r.codigo, 'emitida_em', p_r.emitida_em,
    'enviada_em', p_r.enviada_em, 'enviada_via', p_r.enviada_via,
    'aprovada_em', p_r.aprovada_em, 'assinada_em', p_r.assinada_em) end;
$$;

-- A porta da geração do PDF: tela, portal do cliente (token) e servidor. Devolve a revisão e a anterior
-- (para o "substitui a Rev. N de dd/mm"). Tipo fora da lista (recibo) devolve null: o recibo não tem revisão.
create or replace function public.documento_revisao_emitir(p_os uuid, p_tipo text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_r   public.documento_revisoes;
  v_ant public.documento_revisoes;
begin
  if not private.revisao_pode(p_os, false) then
    raise exception 'Sem acesso a este documento.' using errcode = '42501';
  end if;
  v_r := private.documento_revisao_emitir(p_os, p_tipo);
  if v_r.id is null then
    return null;
  end if;
  select * into v_ant from public.documento_revisoes r
   where r.service_order_id = p_os and r.tipo = p_tipo and r.revisao = v_r.revisao - 1;
  return private.revisao_json(v_r) || jsonb_build_object('tipo', v_r.tipo, 'anterior', private.revisao_json(v_ant));
end $$;

-- ─── 5. Situação (tela e assistente): emitida, enviada, aprovada, e se mudou desde a última ───────
create or replace function public.documento_revisao_situacao(p_os uuid, p_tipo text default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_tipo    text;
  v_ult     public.documento_revisoes;
  v_env     public.documento_revisoes;
  v_apr     public.documento_revisoes;
  v_status  text;
begin
  if not private.revisao_pode(p_os, true) then
    raise exception 'Sem acesso a este documento.' using errcode = '42501';
  end if;
  select so.status into v_status from public.service_orders so where so.id = p_os;
  if not found then
    return null;
  end if;
  v_tipo := coalesce(p_tipo, private.revisao_tipo_da_ordem(v_status));

  select * into v_ult from public.documento_revisoes r
   where r.service_order_id = p_os and r.tipo = v_tipo order by r.revisao desc limit 1;
  select * into v_env from public.documento_revisoes r
   where r.service_order_id = p_os and r.tipo = v_tipo and r.enviada_em is not null order by r.revisao desc limit 1;
  select * into v_apr from public.documento_revisoes r
   where r.service_order_id = p_os and r.tipo = v_tipo and (r.aprovada_em is not null or r.assinada_em is not null)
   order by r.revisao desc limit 1;

  return jsonb_build_object(
    'tipo', v_tipo,
    'atual', private.revisao_json(v_ult),
    'enviada', private.revisao_json(v_env),
    'aprovada', private.revisao_json(v_apr),
    -- O que está na tela já não é o da última revisão emitida (o próximo PDF sai com a revisão seguinte).
    'mudou_desde_a_ultima', v_ult.id is not null
                            and v_ult.hash <> md5(private.documento_conteudo_impresso(p_os, v_tipo)::text));
end $$;

-- ─── 6. Conferir um código impresso ────────────────────────────────────────────────────────────────
create or replace function public.documento_revisao_conferir(p_codigo text)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_cod text := upper(regexp_replace(coalesce(p_codigo, ''), '[^0-9A-Fa-f]', '', 'g'));
begin
  if not private.revisao_pode(null, true) then
    raise exception 'Sem acesso.' using errcode = '42501';
  end if;
  if length(v_cod) <> 8 then
    return jsonb_build_object('achou', false, 'motivo', 'O código tem 8 letras/números, como 7F3A-21C9.');
  end if;
  v_cod := substr(v_cod, 1, 4) || '-' || substr(v_cod, 5, 4);
  return jsonb_build_object('achou', exists (select 1 from public.documento_revisoes where codigo = v_cod),
    'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'service_order_id', r.service_order_id, 'numero', so.service_order_number,
               'tipo', r.tipo, 'revisao', r.revisao, 'emitida_em', r.emitida_em,
               'enviada_em', r.enviada_em, 'aprovada_em', r.aprovada_em, 'assinada_em', r.assinada_em,
               'ultima_revisao', (select max(x.revisao) from public.documento_revisoes x
                                   where x.service_order_id = r.service_order_id and x.tipo = r.tipo),
               'e_a_atual', r.revisao = (select max(x.revisao) from public.documento_revisoes x
                                          where x.service_order_id = r.service_order_id and x.tipo = r.tipo)
                            and r.hash = md5(private.documento_conteudo_impresso(r.service_order_id, r.tipo)::text))
             order by r.emitida_em desc)
        from public.documento_revisoes r
        join public.service_orders so on so.id = r.service_order_id
       where r.codigo = v_cod), '[]'::jsonb));
end $$;

-- ─── 6b. Todas as revisões de um documento, pelo número (assistente: consultar_historico_documento, modo revisoes) ──
-- Mesmo resolvedor e mesma porta do histórico (20270121100100): administrador e financeiro, ou o servidor.
-- versao_do_historico liga cada revisão ao retrato: "o que mudou da Rev. 2 para a 3" = comparar esses dois retratos.
create or replace function public.documento_revisoes(p_ref text)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_doc    record;
  v_status text;
  v_tipo   text;
  v_ult    public.documento_revisoes;
  v_hora   constant text := 'DD/MM/YYYY HH24:MI';
begin
  if not private.historico_pode_ler() then
    raise exception 'As revisões do documento são só para administrador e financeiro.' using errcode = '42501';
  end if;
  select * into v_doc from private.historico_resolver('os', p_ref);
  select so.status into v_status from public.service_orders so where so.id = v_doc.doc_id;
  v_tipo := private.revisao_tipo_da_ordem(v_status);
  select * into v_ult from public.documento_revisoes r
   where r.service_order_id = v_doc.doc_id and r.tipo = v_tipo order by r.revisao desc limit 1;
  return jsonb_build_object(
    'documento', v_doc.rotulo,
    'tipo_atual', case v_tipo when 'quote' then 'orçamento' else 'OS' end,
    'revisoes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tipo', case r.tipo when 'quote' then 'orçamento' when 'invoice' then 'fatura' else 'OS' end,
               'revisao', r.revisao, 'codigo', r.codigo,
               'emitida_em', to_char(r.emitida_em at time zone 'America/Sao_Paulo', v_hora),
               'enviada_ao_cliente_em', to_char(r.enviada_em at time zone 'America/Sao_Paulo', v_hora),
               'enviada_por', r.enviada_via,
               'aprovada_em', to_char(r.aprovada_em at time zone 'America/Sao_Paulo', v_hora),
               'assinada_em', to_char(r.assinada_em at time zone 'America/Sao_Paulo', v_hora),
               'versao_do_historico', r.versao_historico)
             order by r.tipo, r.revisao)
        from public.documento_revisoes r where r.service_order_id = v_doc.doc_id), '[]'::jsonb),
    'mudou_desde_a_ultima', v_ult.id is not null
                            and v_ult.hash <> md5(private.documento_conteudo_impresso(v_doc.doc_id, v_tipo)::text));
end $$;

-- ─── 7. A revisão que o cliente RECEBEU (registro de envio da F5, só o que foi ao cliente) ─────────
create or replace function private.revisao_marcar_envio()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_status text;
  v_r      public.documento_revisoes;
begin
  if not new.ao_cliente or new.via = 'historico' then
    return null;   -- carga de envio antigo: o conteúdo de hoje não é o que foi enviado
  end if;
  select so.status into v_status from public.service_orders so where so.id = new.service_order_id;
  v_r := private.documento_revisao_emitir(new.service_order_id, private.revisao_tipo_da_ordem(v_status));
  if v_r.id is not null then
    update public.documento_revisoes
       set enviada_em = coalesce(new.em, clock_timestamp()), enviada_via = new.via
     where id = v_r.id
       and (enviada_em is null or enviada_em < coalesce(new.em, clock_timestamp()));
  end if;
  return null;
end $$;

drop trigger if exists trg_revisao_envio on public.orcamento_envios;
create trigger trg_revisao_envio
  after insert on public.orcamento_envios
  for each row execute function private.revisao_marcar_envio();

-- ─── 8. A revisão que o cliente APROVOU / ASSINOU ──────────────────────────────────────────────────
-- O tipo é o de ANTES da mudança: aprovar o orçamento pode convertê-lo em OS na mesma gravação.
create or replace function private.revisao_marcar_aprovacao()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_r public.documento_revisoes;
begin
  if new.quote_status = 'approved' and old.quote_status is distinct from 'approved' then
    v_r := private.documento_revisao_emitir(new.id, private.revisao_tipo_da_ordem(old.status));
    update public.documento_revisoes set aprovada_em = clock_timestamp() where id = v_r.id and aprovada_em is null;
  end if;
  if new.signed_at is not null and old.signed_at is null then
    v_r := private.documento_revisao_emitir(new.id, private.revisao_tipo_da_ordem(old.status));
    update public.documento_revisoes set assinada_em = new.signed_at where id = v_r.id and assinada_em is null;
  end if;
  return null;
end $$;

drop trigger if exists trg_revisao_aprovacao on public.service_orders;
create trigger trg_revisao_aprovacao
  after update of quote_status, signed_at on public.service_orders
  for each row execute function private.revisao_marcar_aprovacao();

-- ─── 9. Segurança ──────────────────────────────────────────────────────────────────────────────────
revoke all on function private.revisao_campos(jsonb, text[])                 from public, anon, authenticated;
revoke all on function private.documento_conteudo_impresso(uuid, text)       from public, anon, authenticated;
revoke all on function private.revisao_pode(uuid, boolean)                   from public, anon, authenticated;
revoke all on function private.documento_revisao_emitir(uuid, text)          from public, anon, authenticated;
revoke all on function private.revisao_tipo_da_ordem(text)                   from public, anon, authenticated;
revoke all on function private.revisao_json(public.documento_revisoes)       from public, anon, authenticated;
revoke all on function private.revisao_marcar_envio()                        from public, anon, authenticated;
revoke all on function private.revisao_marcar_aprovacao()                    from public, anon, authenticated;

-- Emitir: o portal do cliente também gera PDF (anon com o token; a função confere o token).
revoke all on function public.documento_revisao_emitir(uuid, text) from public;
grant execute on function public.documento_revisao_emitir(uuid, text) to anon, authenticated, service_role;
-- Situação e conferência: só quem está logado (e o servidor). Grant nominal de anon vem do default do Supabase.
revoke all on function public.documento_revisao_situacao(uuid, text) from public, anon;
grant execute on function public.documento_revisao_situacao(uuid, text) to authenticated, service_role;
revoke all on function public.documento_revisao_conferir(text) from public, anon;
grant execute on function public.documento_revisao_conferir(text) to authenticated, service_role;
revoke all on function public.documento_revisoes(text) from public, anon;
grant execute on function public.documento_revisoes(text) to authenticated, service_role;
