-- Histórico de documentos (F1): o BANCO passa a registrar toda alteração de orçamento/OS e dos
-- documentos ligados, venha de onde vier (tela, assistente, WhatsApp, automação, exclusão em cascata),
-- e guarda um RETRATO inteiro do documento a cada marco (enviado, aprovado, assinado, convertido...).
--
-- Plano e decisões do dono (16/11/2026): D:/IA-HBR/Trabalho/versoes-documentos/plano.md
--   1. Escopo amplo: OS/orçamento + itens + parcelas + compras/cotações + orçamento externo + cadastros
--      (cliente, embarcação, produto, serviço) + configurações que formam o documento. Financeiro fora.
--   3. Técnico NÃO vê o histórico (só admin e financeiro).
--   4. Mudança nos ITENS de documento assinado pede nova assinatura (antes só total/texto pediam).
--
-- Por que estender o audit_log e não criar tabela: ele já tem o formato antes/depois (previous_value /
-- new_value), a tela da OS (ServiceOrderTimeline), a do cliente/embarcação (RecordHistory) e a página de
-- auditoria já leem dele, e as 781 fotos antigas do cabeçalho continuam valendo como histórico legado.
--
-- O que muda no audit_log:
--   * colunas doc_tabela/doc_id (o documento raiz — a OS, também para as linhas), ator_id (quem, uuid),
--     origem (por onde: tela, assistente_*, cliente_link, servidor, automacao, banco, restauracao, migracao),
--     xact_id (agrupa o que mudou na mesma transação) e versao (número do retrato);
--   * o banco CARIMBA quem gravou: linha escrita por usuário logado leva o auth.uid() dele, não o
--     "sistema" que o navegador mandava (1.278 de 1.348 edições de OS estavam assim) — e ninguém forja autor;
--   * as ações insert/delete/versao/restore são do banco: a API não grava essas;
--   * leitura só para admin e financeiro (o técnico lia preço e custo pelo previous_value).
--
-- Quem alterou, por canal:
--   * tela / assistente no painel: auth.uid() (o JWT do usuário);
--   * edge com service_role (assistente no WhatsApp/Max, envio, assinatura): cabeçalho x-mf-ator /
--     x-mf-origem — só aceito quando o papel é service_role, a mesma regra de _autor_da_agenda (um
--     navegador forja qualquer cabeçalho, então para o papel authenticated vale só o auth.uid());
--   * sem requisição (cron, função do banco, migration): GUC marineflow.historico_ator/origem, ou
--     "automacao"/"banco".
--
-- Desligar a captura numa carga em massa (restaurar backup): set local marineflow.historico_desligado = 'on'.

-- ─── 1. Colunas novas ───────────────────────────────────────────────────────────────────────────────
alter table public.audit_log
  add column if not exists doc_tabela text,
  add column if not exists doc_id uuid,
  add column if not exists ator_id uuid,
  add column if not exists origem text,
  add column if not exists xact_id xid8,
  add column if not exists versao integer,
  add column if not exists pelo_banco boolean not null default false;

-- Default separado do ADD: com o default no ADD, as 2,4 mil linhas antigas ganhariam o xid DESTA migration.
alter table public.audit_log alter column xact_id set default pg_current_xact_id();
-- Hora de verdade de cada linha: now() é a hora do INÍCIO da transação, e um salvamento grava cabeçalho,
-- linhas e retrato na mesma transação — com now() todos empatavam e a ordem entre eles se perdia.
alter table public.audit_log alter column changed_at set default clock_timestamp();

comment on column public.audit_log.doc_tabela is 'Tabela do documento raiz (service_orders, purchase_orders, clients...). Linha de item aponta para o documento dela.';
comment on column public.audit_log.doc_id is 'Id do documento raiz. Para a OS: o id da OS, também nas linhas de peças/serviços/parcelas.';
comment on column public.audit_log.ator_id is 'Quem alterou (app_users.id). Carimbado pelo banco; nulo = automação/servidor sem usuário.';
comment on column public.audit_log.origem is 'Por onde: tela, assistente_painel, assistente_whatsapp, assistente_max, cliente_link, servidor, automacao, banco, restauracao, migracao.';
comment on column public.audit_log.xact_id is 'Transação que gravou (pg_current_xact_id): junta cabeçalho e linhas de um mesmo salvamento.';
comment on column public.audit_log.pelo_banco is 'true = gravada pelo gatilho/funções do histórico (com o valor de antes confiável). A API não consegue gravar true. Só estas linhas se desfazem.';
comment on column public.audit_log.versao is 'Número do retrato do documento (action = versao), sequencial por documento.';

create index if not exists audit_log_doc_idx
  on public.audit_log (doc_tabela, doc_id, changed_at desc) where doc_id is not null;
create index if not exists audit_log_registro_idx
  on public.audit_log (table_name, record_id, changed_at desc);
create unique index if not exists audit_log_versao_unica
  on public.audit_log (doc_tabela, doc_id, versao) where action = 'versao';

-- ─── 2. Lista fechada de ações (+ insert, delete, versao, restore) ─────────────────────────────────
-- Anda junto com AuditAction (src/hooks/use-audit-log.ts) e src/test/audit-log-acoes.test.ts.
alter table public.audit_log drop constraint if exists audit_log_action_check;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_action_check CHECK (action = ANY (ARRAY[
  'update', 'cancel', 'reopen', 'reversal', 'cascade_update', 'client_signature',
  'whatsapp_send', 'whatsapp_send_api', 'whatsapp_received', 'whatsapp_preview',
  'whatsapp_send_open', 'whatsapp_unread_reminder_enqueued',
  'lead_created', 'lead_matched', 'lead_converted',
  'import_xml', 'confirm_import', 'revert_import',
  'insert', 'delete', 'versao', 'restore'
]::text[]));

-- ─── 3. Quem e por onde ────────────────────────────────────────────────────────────────────────────
create or replace function private.historico_contexto(out ator_id uuid, out origem text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_claims  jsonb;
  v_headers jsonb;
  v_papel   text;
  v_orig_h  text;
  v_ator_t  text;
  v_guc     text;
begin
  begin v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  exception when others then v_claims := null; end;
  begin v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then v_headers := null; end;

  v_papel  := coalesce(v_claims ->> 'role', '');
  v_orig_h := lower(nullif(v_headers ->> 'x-mf-origem', ''));
  ator_id  := auth.uid();

  if ator_id is not null then
    -- Usuário logado: o autor é o login. O cabeçalho só distingue o assistente do painel da tela.
    origem := case when v_orig_h = 'assistente_painel' then v_orig_h else 'tela' end;
  elsif v_papel = 'service_role' then
    -- cabeçalho do client do turno; sem ele, o que uma função do banco declarou (restaurar com p_autor)
    v_ator_t := coalesce(nullif(v_headers ->> 'x-mf-ator', ''), nullif(current_setting('marineflow.historico_ator', true), ''));
    if v_ator_t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      ator_id := v_ator_t::uuid;
    end if;
    origem := coalesce(case when v_orig_h ~ '^[a-z_]{3,40}$' then v_orig_h end, 'servidor');
  elsif v_papel = 'anon' then
    origem := 'cliente_link';
  else
    -- Sem requisição HTTP: pg_cron, função chamada pelo banco, migration.
    v_ator_t := nullif(current_setting('marineflow.historico_ator', true), '');
    if v_ator_t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      ator_id := v_ator_t::uuid;
    end if;
    origem := case when current_setting('application_name', true) ilike 'pg_cron%' then 'automacao' else 'banco' end;
  end if;

  -- Função do banco que sabe o que está fazendo (restaurar, agrupar, migration) diz a origem.
  -- O navegador não alcança set_config: o PostgREST só expõe funções do schema public.
  v_guc := nullif(current_setting('marineflow.historico_origem', true), '');
  if v_guc ~ '^[a-z_]{3,40}$' then
    origem := v_guc;
  end if;
end $$;

create or replace function private.historico_nome(p_ator uuid)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select nullif(btrim(u.full_name), '') from public.app_users u where u.id = p_ator;
$$;

-- Configurações que mudam o documento (termos, PDF, link público, pagamento, empresa, preços de deslocamento).
-- Lista fechada de propósito: app_settings também guarda segredo (cron_worker_secret) e cursores de automação
-- que mudam a cada minuto.
create or replace function private.historico_config_relevante(p_key text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_key like 'terms\_%' or p_key like 'pdf\_options\_%' or p_key like 'public\_view\_%'
      or p_key like 'company\_%' or p_key like 'bank\_%' or p_key like 'travel\_%'
      or p_key = any (array[
        'quote_validity_days', 'quote_deposit_percentage', 'quote_expiry_days', 'card_fee_percent',
        'default_card_fee_percent', 'pix_key', 'payment_link_url', 'cnpj', 'iss_rate_pct',
        'default_hourly_rate', 'default_payment_method', 'signature_status_after',
        'default_commission_rate', 'default_profit_margin', 'simples_aliquota'
      ]);
$$;

-- ─── 4. O gatilho genérico: grava só o que mudou ─────────────────────────────────────────────────────
-- Argumentos: (1) coluna que aponta para o documento raiz ('id' na própria raiz; '' = sem documento),
--             (2) tabela do documento raiz, (3) colunas a ignorar, separadas por vírgula.
create or replace function private.historico_registrar()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_doc_col text   := nullif(tg_argv[0], '');
  v_doc_tab text   := nullif(tg_argv[1], '');
  v_ignorar text[] := array['updated_at'] || coalesce(string_to_array(nullif(tg_argv[2], ''), ','), '{}'::text[]);
  v_old     jsonb;
  v_new     jsonb;
  v_antes   jsonb := '{}'::jsonb;
  v_depois  jsonb := '{}'::jsonb;
  v_k       text;
  v_a       jsonb;
  v_d       jsonb;
  v_reg     uuid;
  v_doc     uuid;
  v_acao    text;
  v_chave   text;
  v_ctx     record;
begin
  if coalesce(current_setting('marineflow.historico_desligado', true), '') = 'on' then
    return null;
  end if;

  if tg_op <> 'INSERT' then v_old := to_jsonb(old) - v_ignorar; end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new) - v_ignorar; end if;

  if tg_table_name = 'app_settings' then
    v_chave := coalesce(v_new ->> 'key', v_old ->> 'key');
    if not private.historico_config_relevante(v_chave) then
      return null;
    end if;
    v_reg := md5('app_settings:' || v_chave)::uuid;   -- a chave é texto; o record_id é uuid estável por chave
  else
    v_reg := (coalesce(v_new ->> 'id', v_old ->> 'id'))::uuid;
  end if;

  if tg_op = 'UPDATE' then
    for v_k, v_d in select e.key, e.value from jsonb_each(v_new) e loop
      v_a := v_old -> v_k;
      -- null e "" contam como iguais: o formulário troca um pelo outro sem o usuário mexer.
      if v_a is distinct from v_d
         and not (coalesce(v_a, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb)
                  and coalesce(v_d, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb)) then
        v_antes  := v_antes  || jsonb_build_object(v_k, v_a);
        v_depois := v_depois || jsonb_build_object(v_k, v_d);
      end if;
    end loop;
    if v_depois = '{}'::jsonb then
      return null;   -- salvar sem mudar nada não vira histórico (eram 70% das linhas antigas)
    end if;
    v_acao := 'update';
  elsif tg_op = 'INSERT' then
    v_antes := null; v_depois := v_new; v_acao := 'insert';
  else
    v_antes := v_old; v_depois := null; v_acao := 'delete';
  end if;

  if v_chave is not null and v_depois is not null then
    v_depois := v_depois || jsonb_build_object('key', v_chave);
  end if;

  if v_doc_col is not null then
    v_doc := nullif(coalesce(v_new ->> v_doc_col, v_old ->> v_doc_col), '')::uuid;
  end if;

  select * into v_ctx from private.historico_contexto();
  perform set_config('marineflow.historico_interno', 'on', true);
  insert into public.audit_log
    (table_name, record_id, action, changed_by, previous_value, new_value, reason,
     doc_tabela, doc_id, ator_id, origem, pelo_banco)
  values
    (tg_table_name, v_reg, v_acao, coalesce(private.historico_nome(v_ctx.ator_id), v_ctx.origem),
     v_antes, v_depois, nullif(current_setting('marineflow.historico_motivo', true), ''),
     case when v_doc is not null then v_doc_tab end, v_doc, v_ctx.ator_id, v_ctx.origem, true);
  -- desliga logo: a licença vale só para ESTE insert, não para o resto da transação
  perform set_config('marineflow.historico_interno', '', true);
  return null;
end $$;

-- ─── 5. Carimbo em toda linha que entra no audit_log ───────────────────────────────────────────────
create or replace function private.audit_log_carimbar()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ctx record;
begin
  if coalesce(current_setting('marineflow.historico_interno', true), '') <> 'on' then
    -- Linha que NÃO veio do gatilho/das funções do histórico (navegador, edge, RPC antiga): não é prova de nada
    -- que o banco gravou. Ações do histórico, recusadas; o resto entra, mas sem poder se passar por linha do banco
    -- nem se pendurar em outro documento (a restauração só confia em pelo_banco = true).
    if new.action in ('insert', 'delete', 'versao', 'restore') then
      raise exception 'A ação % do histórico é gravada só pelo banco.', new.action using errcode = '42501';
    end if;
    new.pelo_banco := false;
    new.versao     := null;
    new.changed_at := clock_timestamp();
    new.xact_id    := pg_current_xact_id();
    if new.table_name = 'service_orders' then
      new.doc_tabela := 'service_orders';
      new.doc_id     := new.record_id;
    else
      new.doc_tabela := null;
      new.doc_id     := null;
    end if;
  end if;

  select * into v_ctx from private.historico_contexto();
  if auth.uid() is not null then
    -- Usuário logado: autor e canal são os da sessão, não o que veio no corpo do insert.
    new.ator_id    := auth.uid();
    new.origem     := v_ctx.origem;
    new.changed_by := coalesce(private.historico_nome(new.ator_id), new.changed_by);
  elsif new.ator_id is null and new.origem is null then
    new.ator_id := v_ctx.ator_id;
    new.origem  := v_ctx.origem;
  end if;

  return new;
end $$;

drop trigger if exists trg_audit_log_carimbar on public.audit_log;
create trigger trg_audit_log_carimbar
  before insert on public.audit_log
  for each row execute function private.audit_log_carimbar();

-- ─── 6. Retrato do documento e versão ──────────────────────────────────────────────────────────────
-- Cabeçalho + linhas + parcelas + termos daquele momento. Sem share_token (é a chave do link público).
create or replace function private.documento_retrato(p_os uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'numero',     so.service_order_number,
    'cabecalho',  to_jsonb(so) - array['share_token', 'updated_at', 'reminder_sent_at'],
    'cliente',    (select jsonb_build_object('id', c.id, 'nome', c.name) from public.clients c where c.id = so.client_id),
    'embarcacao', (select jsonb_build_object('id', v.id, 'nome', v.name) from public.vessels v where v.id = so.vessel_id),
    'pecas', coalesce((
      select jsonb_agg((to_jsonb(p) - array['updated_at']) || jsonb_build_object('produto', pr.name, 'sku', pr.sku)
                       order by p.created_at, p.id)
        from public.service_order_parts p
        left join public.products pr on pr.id = p.product_id
       where p.service_order_id = so.id), '[]'::jsonb),
    'servicos', coalesce((
      select jsonb_agg(to_jsonb(s) - array['updated_at', 'elapsed_minutes'] order by s.created_at, s.id)
        from public.service_order_services s
       where s.service_order_id = so.id), '[]'::jsonb),
    'despesas', coalesce((
      select jsonb_agg(to_jsonb(e) - array['updated_at'] order by e.created_at, e.id)
        from public.service_order_expenses e
       where e.service_order_id = so.id), '[]'::jsonb),
    'tecnicos', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', t.user_id, 'nome', u.full_name, 'papel', t.role_in_order)
                       order by u.full_name, t.user_id)
        from public.service_order_technicians t
        left join public.app_users u on u.id = t.user_id
       where t.service_order_id = so.id), '[]'::jsonb),
    'parcelas', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'descricao', r.description, 'vencimento', r.due_date,
                                          'valor', r.amount, 'situacao', r.status, 'sinal', r.is_deposit)
                       order by r.due_date, r.id)
        from public.receivables r
       where r.service_order_id = so.id), '[]'::jsonb),
    'termos', (
      select jsonb_object_agg(a.key, a.value)
        from public.app_settings a
       where a.key like 'terms\_%'
          or a.key in ('quote_validity_days', 'quote_deposit_percentage', 'card_fee_percent', 'payment_link_url'))
  )
  from public.service_orders so
  where so.id = p_os;
$$;

-- Grava um retrato novo só se o documento mudou desde o último (mesma ideia da impressão digital do Dropbox).
-- Devolve o número da versão vigente.
create or replace function private.documento_versionar(p_os uuid, p_marco text)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ret  jsonb;
  v_hash text;
  v_ult  record;
  v_n    integer;
  v_ctx  record;
begin
  if p_os is null or coalesce(current_setting('marineflow.historico_desligado', true), '') = 'on' then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('documento_versao:' || p_os::text, 0));

  v_ret := private.documento_retrato(p_os);
  if v_ret is null then
    return null;
  end if;
  v_hash := md5(v_ret::text);

  select l.versao, l.new_value ->> 'hash' as hash
    into v_ult
    from public.audit_log l
   where l.doc_tabela = 'service_orders' and l.doc_id = p_os and l.action = 'versao'
   order by l.versao desc
   limit 1;
  if v_ult.hash is not distinct from v_hash and v_ult.versao is not null then
    return v_ult.versao;
  end if;

  v_n := coalesce(v_ult.versao, 0) + 1;
  select * into v_ctx from private.historico_contexto();
  perform set_config('marineflow.historico_interno', 'on', true);
  insert into public.audit_log
    (table_name, record_id, action, changed_by, new_value, reason, doc_tabela, doc_id, ator_id, origem, versao, pelo_banco)
  values
    ('service_orders', p_os, 'versao', coalesce(private.historico_nome(v_ctx.ator_id), v_ctx.origem),
     jsonb_build_object('versao', v_n, 'marco', p_marco, 'hash', v_hash, 'retrato', v_ret),
     p_marco, 'service_orders', p_os, v_ctx.ator_id, v_ctx.origem, v_n, true);
  perform set_config('marineflow.historico_interno', '', true);
  return v_n;
end $$;

-- Marcos da própria OS.
create or replace function private.documento_marco_os()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_marco text;
begin
  v_marco := case
    when new.merged_into_id is not null and old.merged_into_id is null                         then 'agrupado'
    when new.status = 'cancelled' and old.status is distinct from 'cancelled'                  then 'cancelado'
    when new.signed_at is not null and old.signed_at is null                                    then 'assinado'
    when (new.status = 'invoiced' and old.status is distinct from 'invoiced')
      or (new.invoicing_status = 'invoiced' and old.invoicing_status is distinct from 'invoiced') then 'faturado'
    when new.status = 'completed' and old.status is distinct from 'completed'                  then 'concluido'
    when new.converted_to_os_at is not null and old.converted_to_os_at is null                  then 'convertido'
    when new.quote_status = 'approved' and old.quote_status is distinct from 'approved'        then 'aprovado'
    when new.quote_status = 'sent' and old.quote_status is distinct from 'sent'                then 'enviado'
    when new.quote_status = 'rejected' and old.quote_status is distinct from 'rejected'        then 'perdido'
    when old.status in ('cancelled', 'completed', 'invoiced')
     and new.status not in ('cancelled', 'completed', 'invoiced')                               then 'reaberto'
    when old.quote_status = 'rejected' and new.quote_status is distinct from 'rejected'        then 'reaberto'
  end;
  if v_marco is not null then
    perform private.documento_versionar(new.id, v_marco);
  end if;
  return null;
end $$;

drop trigger if exists trg_documento_marco on public.service_orders;
create trigger trg_documento_marco
  after update of status, quote_status, signed_at, converted_to_os_at, invoicing_status, merged_into_id
  on public.service_orders
  for each row execute function private.documento_marco_os();

-- Todo ENVIO ao cliente (não só o primeiro): documento ou link pelo WhatsApp, e o registro de envio da F5.
create or replace function private.documento_marco_envio()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_table_name = 'audit_log' then
    -- Só o envio que o provedor ACEITOU (o whatsapp-send grava também a recusa e a falha: 17 de 141 em 16/11/2026).
    -- O formato antigo (Z-API) só tinha http_status.
    if new.table_name = 'service_orders' and new.record_id is not null
       and coalesce(new.new_value ->> 'kind', '') in ('document', 'link')
       and not (new.new_value ? 'recusado')
       and (new.new_value -> 'provider_result' ->> 'ok' = 'true'
            or (new.new_value -> 'provider_result' is null
                and coalesce(new.new_value ->> 'http_status', '') ~ '^2\d\d$')) then
      perform private.documento_versionar(new.record_id, 'enviado');
    end if;
  elsif new.via is distinct from 'historico' then
    -- registro de envio da F5; 'historico' é carga de envio antigo (o retrato de hoje não é o que foi enviado)
    perform private.documento_versionar(new.service_order_id, 'enviado');
  end if;
  return null;
end $$;

drop trigger if exists trg_documento_marco_envio on public.audit_log;
create trigger trg_documento_marco_envio
  after insert on public.audit_log
  for each row when (new.action in ('whatsapp_send_api', 'whatsapp_send'))
  execute function private.documento_marco_envio();

drop trigger if exists trg_documento_marco_envio on public.orcamento_envios;
create trigger trg_documento_marco_envio
  after insert on public.orcamento_envios
  for each row execute function private.documento_marco_envio();

-- ─── 7. Itens mexidos em documento assinado pedem nova assinatura (decisão 4) ──────────────────────
-- detect_so_change_after_signature só olha o cabeçalho: trocar uma peça por outra de mesmo valor, ou mudar
-- a descrição de um serviço, passava sem aviso. Aqui o mesmo efeito, para as linhas.
create or replace function private.linha_pede_nova_assinatura()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_os     uuid := coalesce(new.service_order_id, old.service_order_id);
  v_campos text[];
  v_mudou  boolean := true;
begin
  if coalesce(current_setting('marineflow.historico_desligado', true), '') = 'on' then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    v_campos := case tg_table_name
      when 'service_order_parts' then
        array['product_id', 'quantity', 'unit_sale_snapshot', 'line_total_sale', 'discount_pct', 'discount_amount', 'notes', 'serial_number']
      else
        array['service_id', 'name_snapshot', 'description_snapshot', 'billing_unit_snapshot', 'quantity',
              'unit_price_snapshot', 'line_total', 'discount_pct', 'discount_amount', 'notes']
    end;
    select exists (
      select 1 from unnest(v_campos) c
       where (to_jsonb(new) -> c) is distinct from (to_jsonb(old) -> c)
    ) into v_mudou;
  end if;
  if not v_mudou then
    return null;
  end if;

  update public.service_orders so
     set requires_resignature = true,
         resignature_requested_at = now()
   where so.id = v_os
     and so.signed_at is not null
     and so.requires_resignature = false;
  if found then
    update public.service_order_signatures sg
       set superseded_at = now(),
           superseded_reason = 'Itens alterados após assinatura'
     where sg.service_order_id = v_os
       and sg.superseded_at is null;
  end if;
  return null;
end $$;

drop trigger if exists trg_linha_pede_nova_assinatura on public.service_order_parts;
create trigger trg_linha_pede_nova_assinatura
  after insert or update or delete on public.service_order_parts
  for each row execute function private.linha_pede_nova_assinatura();

drop trigger if exists trg_linha_pede_nova_assinatura on public.service_order_services;
create trigger trg_linha_pede_nova_assinatura
  after insert or update or delete on public.service_order_services
  for each row execute function private.linha_pede_nova_assinatura();

-- ─── 8. Onde a captura é ligada ────────────────────────────────────────────────────────────────────
do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- tabela                        coluna do documento    documento raiz         colunas ignoradas
      ('service_orders',               'id',                  'service_orders',      'reminder_sent_at,share_token'),
      ('service_order_parts',          'service_order_id',    'service_orders',      ''),
      ('service_order_services',       'service_order_id',    'service_orders',      'elapsed_minutes'),
      ('service_order_expenses',       'service_order_id',    'service_orders',      ''),
      ('service_order_technicians',    'service_order_id',    'service_orders',      ''),
      ('service_order_steps',          'service_order_id',    'service_orders',      'actual_minutes'),
      ('service_order_signatures',     'service_order_id',    'service_orders',      'share_token'),
      ('service_order_photos',         'service_order_id',    'service_orders',      ''),
      ('receivables',                  'service_order_id',    'service_orders',      'reminder_sent_at'),
      ('purchase_orders',              'id',                  'purchase_orders',     ''),
      ('purchase_order_items',         'purchase_order_id',   'purchase_orders',     ''),
      ('quote_requests',               'id',                  'quote_requests',      ''),
      ('quote_request_items',          'quote_request_id',    'quote_requests',      ''),
      ('external_quotes',              'id',                  'external_quotes',     ''),
      ('external_quote_parts',         'external_quote_id',   'external_quotes',     ''),
      ('external_quote_services',      'external_quote_id',   'external_quotes',     ''),
      ('clients',                      'id',                  'clients',             ''),
      ('vessels',                      'id',                  'vessels',             ''),
      ('products',                     'id',                  'products',            'stock_quantity,reserved_quantity,last_stock_entry_at'),
      ('services',                     'id',                  'services',            ''),
      ('app_settings',                 '',                    '',                    '')
    ) as t(tabela, doc_col, doc_tab, ignorar)
  loop
    execute format('drop trigger if exists trg_historico on public.%I', r.tabela);
    execute format(
      'create trigger trg_historico after insert or update or delete on public.%I '
      'for each row execute function private.historico_registrar(%L, %L, %L)',
      r.tabela, r.doc_col, r.doc_tab, r.ignorar);
  end loop;
end $$;

-- ─── 9. Segurança ──────────────────────────────────────────────────────────────────────────────────
-- Funções: ninguém de fora executa (gatilho não precisa de EXECUTE para disparar).
revoke all on function private.historico_contexto()                  from public, anon, authenticated;
revoke all on function private.historico_nome(uuid)                  from public, anon, authenticated;
revoke all on function private.historico_config_relevante(text)      from public, anon, authenticated;
revoke all on function private.historico_registrar()                 from public, anon, authenticated;
revoke all on function private.audit_log_carimbar()                  from public, anon, authenticated;
revoke all on function private.documento_retrato(uuid)               from public, anon, authenticated;
revoke all on function private.documento_versionar(uuid, text)       from public, anon, authenticated;
revoke all on function private.documento_marco_os()                  from public, anon, authenticated;
revoke all on function private.documento_marco_envio()               from public, anon, authenticated;
revoke all on function private.linha_pede_nova_assinatura()          from public, anon, authenticated;

-- Tabela: o anon não tem nada a fazer aqui; o usuário logado só insere (o banco carimba) e lê se for
-- admin/financeiro. UPDATE/DELETE já eram barrados pela RLS; agora também pelo GRANT.
revoke all on public.audit_log from anon;
revoke update, delete, truncate, references, trigger on public.audit_log from authenticated;

drop policy if exists audit_log_select_auth on public.audit_log;
create policy audit_log_select_auth on public.audit_log
  for select to authenticated
  using (public.is_admin_or_financial((select auth.uid())));

-- O selo "enviado pelo WhatsApp" das listas de orçamento/OS (use-whatsapp-send-log) continua visível a todo cargo
-- logado, como antes: a decisão 3 do dono é sobre o histórico de alterações, não sobre o status de envio.
drop policy if exists audit_log_select_envios on public.audit_log;
create policy audit_log_select_envios on public.audit_log
  for select to authenticated
  using ((select auth.uid()) is not null
         and table_name = 'service_orders'
         and action in ('whatsapp_send_api', 'whatsapp_send'));
