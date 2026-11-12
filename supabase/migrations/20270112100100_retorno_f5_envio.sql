-- Retorno rápido ao cliente, F5 (P2): o envio do orçamento e a validade contada do envio (K6). Nada liga aqui.
--
-- 1. trg_orcamento_quote_status (BEFORE UPDATE OF quote_status, só quando muda): a 1ª passagem de rascunho ou "aguardando
--    aprovação" a "enviado" carimba service_orders.orcamento_enviado_em (a hora que veio no mesmo update, senão now()) e a via
--    (a que veio, senão 'marcado'). Depois disso, a hora, a via e a chave do 1º envio nunca mudam. "Perdido" carimba
--    motivo_perda_em; sair de "perdido" apaga os 4 campos do motivo. Nunca lê outra tabela e nunca lança.
-- 2. trg_orcamento_envio_depois (AFTER UPDATE OF quote_status, orcamento_enviado_em): grava em orcamento_envios só a
--    marcação à mão (via 'marcado', sem chave, ao_cliente falso). As outras vias têm o seu escritor: orcamento_registrar_envio
--    (whatsapp-send), orcamento_detectar_envio (aparelho) e a migration de dado (histórico). O mesmo envio nunca entra duas vezes.
--    O AFTER olha as duas colunas porque UPDATE OF ignora o que o BEFORE muda: na marcação à mão só quote_status está no SET.
-- 3. orcamento_validade_do_envio (C-VAL-ENVIO; a única função da F5 aberta a authenticated): confere o cargo antes de tudo
--    (service_role, ou app_users ativo admin, financial ou seller); para quem não é a service_role, p_agora é ignorado (now()).
--    Com validade_envio_ligada, fixa "hoje + validade_orcamento_dias" em quote_validity_date no envio (p_gravar), ou só mostra
--    (prévia), ou recusa quando o dia virou entre a prévia e o envio (p_esperada). Depois do envio não renova (D13); com a data
--    já vencida, não devolve a linha de validade. A legenda (O21) e a linha (O22) vêm de _orcamento_legenda (P4).
-- 4. _orcamento_ultimo_dia: o porte de ultimoDiaDaValidade (_shared/pdf/documento.ts) e de primeiraValidade.
-- 5. orcamento_registrar_envio (C-REG-ENVIO; só service_role): o whatsapp-send registra todo envio de orçamento, a qualquer
--    número, reenvio inclusive. Nunca lança. Não grava destino de parceiro confirmado nem orçamento de cliente parceiro.
-- 6. orcamento_detectar_envio (C-DETECTA): o PDF mandado do aparelho do dono (eco), pelo número do documento no nome do
--    arquivo (ORC- ou ORÇ-, nunca OS-: OS não é orçamento), com a hora do eco. Marca d'água retorno_config.orcamento_envio_ate.
--    'registrar' só grava o envio; 'marcar' também passa o funil a "enviado" (ao número do cliente). Nunca lê o corpo e nunca
--    grava o nome do arquivo.
--
-- Sem dado: só funções e gatilhos. Tudo nasce desligado (validade_envio_ligada falso, envio_mao_modo 'desligado'), mas os
-- gatilhos 1 e 2 valem desde a publicação: só colunas da própria ordem e linhas em orcamento_envios, nenhuma mensagem.
-- Reverter: drop trigger trg_orcamento_envio_depois e trg_orcamento_quote_status on public.service_orders; drop das funções
-- desta migration. As colunas e as linhas de orcamento_envios ficam.

-- ── 1. O gatilho do funil (BEFORE) ──────────────────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_quote_status_antes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 1. A 1ª passagem a "enviado": quem sabe a hora do envio a passa no mesmo update (a detecção passa a hora do eco); o
  --    gatilho nunca sobrescreve o que veio. A marcação à mão não tem via nem chave: fica 'marcado', sem chave.
  if new.quote_status = 'sent' and old.quote_status in ('draft', 'awaiting_approval') and old.orcamento_enviado_em is null then
    new.orcamento_enviado_em := coalesce(new.orcamento_enviado_em, now());
    new.orcamento_enviado_via := coalesce(new.orcamento_enviado_via, 'marcado');
  end if;
  -- O 1º envio nunca muda depois: a hora, a via e a chave descrevem o mesmo evento.
  if old.orcamento_enviado_em is not null then
    new.orcamento_enviado_em := old.orcamento_enviado_em;
    new.orcamento_enviado_via := old.orcamento_enviado_via;
    new.orcamento_enviado_chave := old.orcamento_enviado_chave;
  end if;
  -- 2. "Perdido": carimba a hora do motivo (sem motivo, quem barra é o CHECK da migration de dado).
  -- 3. Saindo de "perdido" (reabrir): o motivo some; o audit_log guarda o anterior.
  if new.quote_status = 'rejected' then
    new.motivo_perda_em := coalesce(new.motivo_perda_em, now());
  elsif old.quote_status = 'rejected' then
    new.motivo_perda := null;
    new.motivo_perda_em := null;
    new.motivo_perda_por := null;
    new.motivo_perda_nota := null;
  end if;
  return new;
end;
$$;

comment on function public._orcamento_quote_status_antes() is
  'Retorno F5 (P2.1): BEFORE UPDATE OF quote_status. Passagem de draft/awaiting_approval a sent sem envio anterior: orcamento_enviado_em = o que veio ou now(), via = a que veio ou marcado. Com envio anterior, hora, via e chave ficam as de antes. rejected carimba motivo_perda_em; sair de rejected apaga os 4 campos do motivo. Não lê tabela e não lança.';

revoke all on function public._orcamento_quote_status_antes() from public, anon, authenticated;

drop trigger if exists trg_orcamento_quote_status on public.service_orders;
create trigger trg_orcamento_quote_status
  before update of quote_status on public.service_orders
  for each row
  when (old.quote_status is distinct from new.quote_status)
  execute function public._orcamento_quote_status_antes();

-- ── 2. A marcação à mão em orcamento_envios (AFTER) ─────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_envio_depois()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ao_cliente boolean;
begin
  -- Só a via 'marcado': as outras têm o seu escritor (whatsapp-send, aparelho, histórico).
  if new.orcamento_enviado_via is distinct from 'marcado' then
    return null;
  end if;
  begin
    select new.orcamento_enviado_chave is not null
           and new.orcamento_enviado_chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
      into v_ao_cliente
      from public.clients c
     where c.id = new.client_id;
    insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
    values (new.id, new.client_id, 'marcado', new.orcamento_enviado_chave, coalesce(v_ao_cliente, false), new.orcamento_enviado_em, true)
    on conflict do nothing;
  exception when others then
    -- Está no caminho de toda mudança de funil: nunca derruba a marcação.
    perform public._retorno_log('orcamento_envio_depois', '_orcamento_envio_depois: ' || sqlerrm, 'error',
                                jsonb_build_object('service_order_id', new.id, 'sqlstate', sqlstate));
  end;
  return null;
end;
$$;

comment on function public._orcamento_envio_depois() is
  'Retorno F5 (P2.1): AFTER UPDATE OF quote_status, orcamento_enviado_em, quando orcamento_enviado_em nasce. Grava em orcamento_envios só a via marcado (marcação à mão: chave nula, ao_cliente falso, marcou verdadeiro). As outras vias têm o seu escritor. Erro vira log, nunca derruba a marcação.';

revoke all on function public._orcamento_envio_depois() from public, anon, authenticated;

drop trigger if exists trg_orcamento_envio_depois on public.service_orders;
create trigger trg_orcamento_envio_depois
  after update of quote_status, orcamento_enviado_em on public.service_orders
  for each row
  when (old.orcamento_enviado_em is null and new.orcamento_enviado_em is not null)
  execute function public._orcamento_envio_depois();

-- ── 3. O último dia da validade (porte de ultimoDiaDaValidade e primeiraValidade) ───────────────────────────────────────

-- Um nível de dias serve quando é número finito cujo inteiro (para baixo) fica entre 1 e 3650 (diasDeValidade); a data fixa
-- é o próprio último dia; sem ela, o dia de Brasília da emissão (created_at) mais o 1º nível que serve entre os dias do
-- orçamento e app_settings.quote_validity_days, com reserva de 15 (VALIDADE_PADRAO_DE_RESERVA).
create or replace function public._orcamento_ultimo_dia(p_os uuid)
returns date
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_so record;
  v_txt text;
  v_dias integer;
  v_cfg numeric;
begin
  select so.quote_validity_date, so.quote_validity_days, so.created_at into v_so from public.service_orders so where so.id = p_os;
  if not found then
    return null;
  end if;
  if v_so.quote_validity_date is not null then
    return v_so.quote_validity_date;
  end if;
  if v_so.created_at is null then
    return null;
  end if;
  if v_so.quote_validity_days between 1 and 3650 then
    v_dias := v_so.quote_validity_days;
  else
    select s.value into v_txt from public.app_settings s where s.key = 'quote_validity_days';
    v_txt := btrim(coalesce(v_txt, ''));
    if v_txt ~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$' then
      begin
        v_cfg := floor(v_txt::numeric);
      exception when others then
        v_cfg := null;
      end;
    end if;
    v_dias := (case when v_cfg between 1 and 3650 then v_cfg::integer else 15 end);
  end if;
  return (v_so.created_at at time zone 'America/Sao_Paulo')::date + v_dias;
end;
$$;

comment on function public._orcamento_ultimo_dia(uuid) is
  'Retorno F5 (P2.1): o último dia (Brasília) em que o orçamento vale, a mesma conta de ultimoDiaDaValidade: a data fixa; senão created_at + o 1º nível de dias que serve (1 a 3650) entre quote_validity_days e app_settings.quote_validity_days, com reserva de 15. Ordem que não existe: nulo.';

revoke all on function public._orcamento_ultimo_dia(uuid) from public, anon, authenticated;

-- ── 4. A validade contada do envio (C-VAL-ENVIO) ────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_validade_do_envio(p_os uuid, p_agora timestamptz default now(), p_gravar boolean default true,
                                                              p_esperada date default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_uid uuid := auth.uid();
  v_papel text;
  v_agora timestamptz;
  v_hoje date;
  v_cfg public.retorno_config;
  v_so record;
  v_n integer;
  v_data date;
  v_leg jsonb;
begin
  -- Quem chama, antes de tudo. Com login: app_users ativo com cargo do PDF ao cliente (CARGOS_DO_PDF_AO_CLIENTE), e o
  -- relógio é o do banco (ninguém escolhe a data por p_agora). Sem login: só a service_role ou o próprio banco.
  if v_uid is not null then
    if not exists (select 1 from public.app_users u
                    where u.id = v_uid and u.active and u.role in ('admin', 'financial', 'seller')) then
      return jsonb_build_object('ok', false, 'motivo', 'cargo');
    end if;
    v_agora := now();
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      return jsonb_build_object('ok', false, 'motivo', 'cargo');
    end if;
    v_agora := coalesce(p_agora, now());
  end if;
  v_hoje := (v_agora at time zone c_fuso)::date;

  begin
    v_cfg := public._retorno_cfg();
    if v_cfg.id is null or v_cfg.validade_envio_ligada is not true then
      return jsonb_build_object('ok', true, 'fixou', false, 'motivo', 'desligada');
    end if;

    if coalesce(p_gravar, true) then
      select so.id, so.status, so.quote_status, so.converted_to_os_at, so.orcamento_enviado_em, so.quote_validity_date
        into v_so from public.service_orders so where so.id = p_os for update;
    else
      select so.id, so.status, so.quote_status, so.converted_to_os_at, so.orcamento_enviado_em, so.quote_validity_date
        into v_so from public.service_orders so where so.id = p_os;
    end if;
    if not found then
      return jsonb_build_object('ok', false, 'motivo', 'erro');
    end if;

    -- Não é orçamento, ou já foi enviado: a data não renova (D13). Vencida: nenhuma data passada é afirmada ao cliente.
    if v_so.status is distinct from 'draft' or v_so.converted_to_os_at is not null or v_so.orcamento_enviado_em is not null then
      v_data := coalesce(v_so.quote_validity_date, public._orcamento_ultimo_dia(p_os));
      if v_data is null then
        return jsonb_build_object('ok', true, 'fixou', false, 'motivo', 'ja_enviado');
      end if;
      if v_data < v_hoje then
        return jsonb_build_object('ok', true, 'fixou', false, 'data', v_data, 'motivo', 'vencida');
      end if;
      -- A legenda que não se monta não derruba a resposta: sai sem legenda nem linha (quem chama usa a de hoje).
      begin
        v_leg := public._orcamento_legenda(p_os, v_data, v_agora);
      exception when others then
        v_leg := null;
        perform public._retorno_log('orcamento_validade_do_envio', '_orcamento_legenda: ' || sqlerrm, 'error',
                                    jsonb_build_object('service_order_id', p_os, 'sqlstate', sqlstate));
      end;
      return jsonb_build_object('ok', true, 'fixou', false, 'data', v_data, 'motivo', 'ja_enviado') || coalesce(v_leg, '{}'::jsonb);
    end if;

    if (v_so.quote_status in ('draft', 'awaiting_approval')) is not true then
      return jsonb_build_object('ok', true, 'fixou', false, 'motivo', 'funil');
    end if;

    v_n := v_cfg.validade_orcamento_dias;
    v_data := v_hoje + v_n;
    -- O dia virou entre o que o dono leu e o envio: não envia, pede de novo.
    if p_esperada is not null and p_esperada is distinct from v_data then
      return jsonb_build_object('ok', true, 'fixou', false, 'data', v_data, 'antes', p_esperada, 'motivo', 'mudou');
    end if;

    begin
      v_leg := public._orcamento_legenda(p_os, v_data, v_agora);
    exception when others then
      v_leg := null;
      perform public._retorno_log('orcamento_validade_do_envio', '_orcamento_legenda: ' || sqlerrm, 'error',
                                  jsonb_build_object('service_order_id', p_os, 'sqlstate', sqlstate));
    end;
    if not coalesce(p_gravar, true) then
      return jsonb_build_object('ok', true, 'fixou', false, 'data', v_data, 'dias', v_n, 'motivo', 'previa') || coalesce(v_leg, '{}'::jsonb);
    end if;

    update public.service_orders so
       set quote_validity_days = v_n, quote_validity_date = v_data
     where so.id = p_os and so.status = 'draft' and so.converted_to_os_at is null and so.orcamento_enviado_em is null;
    if not found then
      return jsonb_build_object('ok', false, 'motivo', 'erro');
    end if;
    return jsonb_build_object('ok', true, 'fixou', true, 'data', v_data, 'dias', v_n) || coalesce(v_leg, '{}'::jsonb);
  exception when others then
    perform public._retorno_log('orcamento_validade_do_envio', 'orcamento_validade_do_envio: ' || sqlerrm, 'error',
                                jsonb_build_object('service_order_id', p_os, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'motivo', 'erro');
  end;
end;
$$;

comment on function public.orcamento_validade_do_envio(uuid, timestamptz, boolean, date) is
  'Retorno F5 (P2.1, C-VAL-ENVIO, K6): {ok, fixou, data?, dias?, legenda?, linha?, contexto?, antes?, motivo?}. Confere o cargo antes de tudo (service_role, ou app_users ativo admin, financial ou seller; senão motivo cargo); para quem não é a service_role, p_agora é ignorado. Com validade_envio_ligada: orçamento não enviado em draft/awaiting_approval ganha quote_validity_date = hoje (Brasília) + validade_orcamento_dias (p_gravar), ou só a conta (previa), ou mudou (p_esperada diferente). Já enviado ou não orçamento: ja_enviado com a data de antes; data anterior a hoje: vencida, sem legenda nem linha. legenda = O21, linha = O22 (_orcamento_legenda). Erro: {ok: false, motivo: erro}.';

revoke all on function public.orcamento_validade_do_envio(uuid, timestamptz, boolean, date) from public, anon, authenticated;
grant execute on function public.orcamento_validade_do_envio(uuid, timestamptz, boolean, date) to authenticated, service_role;

-- ── 5. Todo envio de orçamento pelo sistema (C-REG-ENVIO) ───────────────────────────────────────────────────────────────

create or replace function public.orcamento_registrar_envio(p_os uuid, p_via text, p_chave text, p_marcou boolean,
                                                            p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_chave text := public._agenda_chave_telefone(p_chave);   -- aceita a chave ou o telefone inteiro; menos de 8 dígitos = nula
  v_so record;
  v_ao_cliente boolean;
  v_id uuid;
begin
  if p_via is null or p_via not in ('assistente', 'tela', 'cartao') then
    return jsonb_build_object('ok', false, 'motivo', 'via');
  end if;
  begin
    select so.id, so.status, so.converted_to_os_at, so.client_id, c.whatsapp, c.phone into v_so
      from public.service_orders so
      left join public.clients c on c.id = so.client_id
     where so.id = p_os;
    if not found then
      return jsonb_build_object('ok', false, 'motivo', 'sem_ordem');
    end if;
    if v_so.status is distinct from 'draft' or v_so.converted_to_os_at is not null then
      return jsonb_build_object('ok', true, 'ignorado', 'nao_e_orcamento');
    end if;
    -- O orçamento de cliente que é o próprio parceiro e o envio a número confirmado de parceiro ficam de fora (dúvida 4).
    if v_so.client_id = any ((public._retorno_cfg()).clientes_parceiros) then
      return jsonb_build_object('ok', true, 'ignorado', 'cliente_parceiro');
    end if;
    if v_chave is not null
       and exists (select 1 from public.parceiro_numeros nn
                     join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
                     join public.parceiros pa on pa.id = pe.parceiro_id and pa.ativo
                    where nn.chave = v_chave and nn.situacao = 'confirmado') then
      return jsonb_build_object('ok', true, 'ignorado', 'parceiro');
    end if;
    v_ao_cliente := v_chave is not null
                    and v_chave in (public._agenda_chave_telefone(v_so.whatsapp), public._agenda_chave_telefone(v_so.phone));
    insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
    values (v_so.id, v_so.client_id, p_via, v_chave, coalesce(v_ao_cliente, false), v_agora, coalesce(p_marcou, false))
    on conflict do nothing
    returning id into v_id;
    return jsonb_strip_nulls(jsonb_build_object('ok', true, 'ao_cliente', coalesce(v_ao_cliente, false), 'id', v_id,
                                                'ignorado', (case when v_id is null then 'repetido' end)));
  exception when others then
    perform public._retorno_log('orcamento_registrar_envio', 'orcamento_registrar_envio: ' || sqlerrm, 'error',
                                jsonb_build_object('service_order_id', p_os, 'via', p_via, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false);
  end;
end;
$$;

comment on function public.orcamento_registrar_envio(uuid, text, text, boolean, timestamptz) is
  'Retorno F5 (P2.1, C-REG-ENVIO): o whatsapp-send registra todo envio de orçamento (context quote, todo kind, fora do modo de teste), a qualquer número e em qualquer estado do funil. p_via em assistente, tela, cartao. Grava em orcamento_envios (ao_cliente = a chave casa com whatsapp ou phone do cliente; em = p_agora; marcou = p_marcou). Ordem que não é orçamento: ignorado nao_e_orcamento. Cliente parceiro ou número confirmado de parceiro: ignorado, nada gravado. Nunca lança: erro = {ok: false}.';

revoke all on function public.orcamento_registrar_envio(uuid, text, text, boolean, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_registrar_envio(uuid, text, text, boolean, timestamptz) to service_role;

-- ── 6. O PDF mandado do aparelho (C-DETECTA) ────────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_detectar_envio(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config;
  v_ate timestamptz;
  m record;
  v_casou text[];
  v_so record;
  v_chave text;
  v_ao_cliente boolean;
  v_em timestamptz;
  v_id uuid;
  v_marcou integer;
  v_lidos integer := 0;
  v_registrados integer := 0;
  v_marcados integer := 0;
  v_fora integer := 0;
begin
  select * into v_cfg from public.retorno_config c where c.id for update;
  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_config');
  end if;
  v_ate := v_cfg.orcamento_envio_ate;

  -- Desligada, ou a 1ª vez: só avança a marca. Ao ligar, nada do passado vira envio. A marca nunca volta.
  if v_cfg.envio_mao_modo = 'desligado' or v_ate is null then
    update public.retorno_config c
       set orcamento_envio_ate = greatest(coalesce(c.orcamento_envio_ate, v_agora), v_agora)
     where c.id;
    return jsonb_build_object('ok', true, 'modo', v_cfg.envio_mao_modo, 'lidos', 0, 'registrados', 0, 'marcados', 0,
                              'sem_numero', 0, 'ate', greatest(coalesce(v_ate, v_agora), v_agora));
  end if;

  for m in
    select w.id, w.occurred_at, w.hora_real, w.phone_normalized,
           w.raw_payload #>> '{data,message,documentMessage,fileName}' as arquivo
      from public.whatsapp_messages w
     where w.direction = 'outbound'
       and w.message_type = 'document'
       and w.raw_payload ? 'data'
       and not (w.raw_payload ? 'via')
       and w.occurred_at > v_ate
       and w.occurred_at <= v_agora
     order by w.occurred_at, w.id
  loop
    v_lidos := v_lidos + 1;
    begin
      -- Só o número do documento: ORC- ou ORÇ- (o "Baixar" da tela e o PDF do assistente saem com ORÇ-). OS- é OS, não
      -- orçamento. Sem número, fica de fora. O nome do arquivo não é gravado em lugar nenhum.
      v_casou := regexp_match(lower(coalesce(m.arquivo, '')), '(?:^|[^a-z0-9])or[cç]-([0-9]{3,8})(?:[^0-9]|$)');
      if v_casou is null then
        v_fora := v_fora + 1;
        continue;
      end if;
      -- ORC- do arquivo é ORÇ- no banco (slugifyForFilename tira a cedilha); sem lpad, como a F4. Só orçamento: OS
      -- convertida (outro número) e ordem que não é rascunho ficam de fora.
      select so.id, so.client_id, so.status, so.quote_status, so.converted_to_os_at, c.whatsapp, c.phone into v_so
        from public.service_orders so
        left join public.clients c on c.id = so.client_id
       where so.service_order_number = 'ORÇ-' || v_casou[1]
         and so.merged_into_id is null
       order by so.created_at desc, so.id
       limit 1;
      if not found or v_so.status is distinct from 'draft' or v_so.converted_to_os_at is not null then
        continue;
      end if;
      v_chave := public._agenda_chave_telefone(m.phone_normalized);
      -- O PDF a número confirmado de parceiro e o orçamento de cliente parceiro ficam de fora (dúvida 4).
      if v_so.client_id = any (v_cfg.clientes_parceiros)
         or exists (select 1 from public.parceiro_numeros nn
                      join public.parceiro_pessoas pe on pe.id = nn.pessoa_id and pe.ativo
                      join public.parceiros pa on pa.id = pe.parceiro_id and pa.ativo
                     where nn.chave = v_chave
                       and nn.situacao = 'confirmado'
                       and (nn.ddd is null or public._ddd_do_telefone(m.phone_normalized) is null
                            or nn.ddd = public._ddd_do_telefone(m.phone_normalized))) then
        continue;
      end if;
      v_ao_cliente := v_chave is not null
                      and v_chave in (public._agenda_chave_telefone(v_so.whatsapp), public._agenda_chave_telefone(v_so.phone));
      -- A hora é a do eco (a mensagem real), não a da detecção.
      v_em := coalesce(m.hora_real, m.occurred_at);
      v_id := null;
      insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, whatsapp_message_id, marcou)
      values (v_so.id, v_so.client_id, 'aparelho', v_chave, coalesce(v_ao_cliente, false), v_em, m.id, false)
      on conflict do nothing
      returning id into v_id;
      if v_id is null then
        continue;
      end if;
      v_registrados := v_registrados + 1;

      -- 'marcar': o PDF ao número do cliente passa o funil a "enviado", com a hora do eco (o gatilho guarda a que veio).
      if v_cfg.envio_mao_modo = 'marcar' and v_ao_cliente and v_so.quote_status in ('draft', 'awaiting_approval') then
        update public.service_orders so
           set quote_status = 'sent', orcamento_enviado_em = v_em, orcamento_enviado_via = 'aparelho', orcamento_enviado_chave = v_chave
         where so.id = v_so.id and so.status = 'draft' and so.converted_to_os_at is null
           and so.quote_status in ('draft', 'awaiting_approval');
        get diagnostics v_marcou = row_count;
        if v_marcou > 0 then
          insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
          values ('service_orders', v_so.id, 'update', 'retorno-f5', jsonb_build_object('quote_status', v_so.quote_status),
                  jsonb_build_object('quote_status', 'sent', 'orcamento_enviado_via', 'aparelho'),
                  'PDF ORC-' || v_casou[1] || ' mandado do aparelho ao número do cliente');
          update public.orcamento_envios e set marcou = true where e.id = v_id;
          v_marcados := v_marcados + 1;
        end if;
      end if;
    exception when others then
      -- Erro nunca trava a fila: o próximo segue.
      perform public._retorno_log('orcamento_detectar_envio', 'orcamento_detectar_envio: ' || sqlerrm, 'error',
                                  jsonb_build_object('mensagem', m.id, 'sqlstate', sqlstate));
    end;
  end loop;

  update public.retorno_config c
     set orcamento_envio_ate = greatest(coalesce(c.orcamento_envio_ate, v_agora), v_agora)
   where c.id;
  return jsonb_build_object('ok', true, 'modo', v_cfg.envio_mao_modo, 'lidos', v_lidos, 'registrados', v_registrados,
                            'marcados', v_marcados, 'sem_numero', v_fora, 'ate', greatest(v_ate, v_agora));
end;
$$;

comment on function public.orcamento_detectar_envio(timestamptz) is
  'Retorno F5 (P2.1, C-DETECTA): o PDF de orçamento mandado do aparelho do dono (eco: raw_payload ? data, sem via), pela marca retorno_config.orcamento_envio_ate. Só o número do documento (ORC- ou ORÇ- com 3 a 8 dígitos; OS- fica de fora), nunca o nome do arquivo nem o corpo. Grava orcamento_envios (via aparelho, em = a hora do eco); com envio_mao_modo marcar e destino do cliente, passa o funil a sent com audit_log. Número confirmado de parceiro e cliente parceiro: nada. Desligada ou 1ª vez: só avança a marca.';

revoke all on function public.orcamento_detectar_envio(timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_detectar_envio(timestamptz) to service_role;
