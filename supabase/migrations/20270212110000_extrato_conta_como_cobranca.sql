-- "Enviar extrato" com saldo conta como a cobrança do dia; a função que registra só aceita administrador e
-- financeiro. 20/11/2026. Depende de 20270212100000_fechar_juntas_cobranca_junto (aplicar as duas, nesta ordem).
--
-- Decisões do dono (Respostas do Diário, 20/11/2026):
--   "Extrato com saldo conta como a cobrança do dia?" → "Sim, conta como cobrança do dia".
--   "Técnico pode criar cobrança pela tela?" → "Só admin e financeiro".
--
-- A regra "1 por dia" mora em public.collections.last_auto_sent_at: o plano de inadimplência
-- (get_delinquency_plan, _shared/ai/tools/financial.ts) marca ja_cobrado_hoje pelo envio mais recente das
-- cobranças do CLIENTE, e o envio em lote (send_bulk_collection_reminders, flow-macros.ts) pula a cobrança
-- com last_auto_sent_at de hoje. O "Cobrar juntas" entra nela por cobrar_juntas_registrar_envio (cria a cobrança
-- da conta que não tem e registra o envio em todas). O extrato com saldo passa a entrar pelo MESMO caminho — nada
-- de tabela nova: depois do envio confirmado, a tela chama a função com p_os NULO, que quer dizer "o cliente
-- inteiro" (o extrato não escolhe OS). Muda, só nesse caso:
--   * as contas precisam ser do cliente (o titular), com ou sem OS — no Cobrar juntas, das OS escolhidas;
--   * a cobrança "da OS sem conta" (a Total da aprovação) que recebe o registro é a das OS das contas;
--   * conta sem OS (avulsa) também ganha cobrança (service_order_id nulo, como a avulsa da tela);
--   * a nota da cobrança criada diz "Enviar extrato".
-- O extrato SEM saldo (comprovante de quitação) não chama a função: não é cobrança.
--
-- Quem pode: só administrador e financeiro (is_admin_or_financial, o helper das policies de receivables). Antes:
-- logado menos o vendedor externo. A função é SECURITY DEFINER (passa por cima da RLS); sem esta conferência, um
-- técnico chamando a RPC criaria cobrança mesmo com a policy de collections fechada (migration 20270212120000).
-- Na prática nada muda para quem usa: só admin e financeiro leem receivables (a ficha mostra as contas só a eles)
-- e a tool cobrar_juntas já recusa os outros cargos.
--
-- A mesma assinatura: o assistente (tool cobrar_juntas) e a tela continuam chamando igual.

create or replace function public.cobrar_juntas_registrar_envio(
  p_cliente uuid,
  p_contas uuid[],          -- as contas a receber que entraram na mensagem (com saldo)
  p_os uuid[],              -- as OS escolhidas (Cobrar juntas); NULO = o cliente inteiro ("Enviar extrato")
  p_nota text default null, -- o texto do contato 'whatsapp_sent' no histórico da cobrança
  p_autor uuid default null -- quem pediu, quando a chamada vem do service role (assistente)
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_quem uuid;
  v_cli record;
  v_modelo record;
  v_distintas integer;
  v_lidas integer;
  v_fora text;
  v_extrato constant boolean := p_os is null;
  v_os uuid[];
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_nota text;
  v_id uuid;
  v_criadas uuid[] := '{}';
  v_cobrancas uuid[];
  v_abertas constant text[] := array['pending', 'sent', 'viewed', 'overdue', 'disputed'];
  r record;
begin
  -- 0. Quem pede: administrador ou financeiro, ativo (dono, 20/11/2026: "Só admin e financeiro")
  if v_autor is null then
    raise exception 'Faça login para registrar a cobrança.' using errcode = '42501';
  end if;
  select u.id into v_quem from public.app_users u where u.id = v_autor and coalesce(u.active, true);
  if v_quem is null or not public.is_admin_or_financial(v_autor) then
    raise exception 'Seu cargo não mexe em cobranças.' using errcode = '42501';
  end if;

  -- 1. Entrada
  if p_cliente is null then
    raise exception 'Diga de qual cliente é a cobrança.' using errcode = '22023';
  end if;
  if p_contas is null or cardinality(p_contas) = 0 or array_position(p_contas, null) is not null then
    raise exception 'Diga as contas que entraram na cobrança.' using errcode = '22023';
  end if;
  select count(distinct x) into v_distintas from unnest(p_contas) x;
  if v_distintas > 100 then
    raise exception 'Contas demais numa cobrança só (%).', v_distintas using errcode = '22023';
  end if;

  select c.id, c.name, c.phone, c.whatsapp, c.generico into v_cli from public.clients c where c.id = p_cliente;
  if v_cli.id is null then
    raise exception 'Cliente não encontrado.' using errcode = 'P0002';
  end if;
  if coalesce(v_cli.generico, false) then
    raise exception 'O cadastro % é genérico, sem CPF/CNPJ: não entra em cobrança%.', coalesce(v_cli.name, 'deste cliente'),
      case when v_extrato then '' else ' conjunta' end
      using errcode = '22023';
  end if;

  -- 2. Trava as contas sempre na mesma ordem e confere: existem, são do cliente (o titular) e — no Cobrar
  --    juntas — das OS escolhidas
  perform 1 from public.receivables x where x.id = any(p_contas) order by x.id for update;
  select count(*) into v_lidas from public.receivables x where x.id = any(p_contas);
  if v_lidas <> v_distintas then
    raise exception 'Alguma conta da cobrança não existe mais. Recarregue a tela.' using errcode = 'P0002';
  end if;
  select string_agg(coalesce(nullif(btrim(x.description), ''), 'conta') || coalesce(' (' || so.service_order_number || ')', ''), ', '
                    order by x.id)
    into v_fora
    from public.receivables x
    left join public.service_orders so on so.id = x.service_order_id
   where x.id = any(p_contas)
     and (x.client_id is distinct from p_cliente
          or (not v_extrato
              and (x.service_order_id is null or not (x.service_order_id = any(p_os)))));
  if v_fora is not null then
    if v_extrato then
      raise exception 'Estas contas não são deste cliente: %.', v_fora using errcode = '22023';
    end if;
    raise exception 'Estas contas não são deste cliente ou de uma das OS escolhidas: %.', v_fora using errcode = '22023';
  end if;

  -- As OS cujas cobranças "sem conta" recebem o registro: as escolhidas; no extrato, as das contas
  if v_extrato then
    select coalesce(array_agg(distinct x.service_order_id), '{}') into v_os
      from public.receivables x where x.id = any(p_contas) and x.service_order_id is not null;
  else
    v_os := p_os;
  end if;

  -- O modelo de mensagem padrão, como criar_cobranca e a tela escolhem (o padrão, senão o primeiro pelo nome)
  select t.body, t.send_method into v_modelo
    from public.collection_templates t
   order by t.is_default desc nulls last, t.name
   limit 1;
  v_nota := coalesce(nullif(btrim(p_nota), ''),
                     case when v_extrato then 'Extrato do cliente com saldo (Enviar extrato)'
                          else 'Cobrar juntas (várias OS numa mensagem)' end);

  -- 3. Cria a cobrança de cada conta com saldo que não tem nenhuma aberta (pela conta, ou da OS sem conta)
  for r in
    select x.id, x.client_id, x.service_order_id, x.due_date,
           round(greatest(coalesce(x.balance_amount, x.amount - coalesce(x.paid_amount, 0)), 0), 2) as saldo
      from public.receivables x
     where x.id = any(p_contas)
       and x.status not in ('paid', 'cancelled')
     order by x.service_order_id nulls last, x.due_date nulls last, x.id
  loop
    continue when r.saldo < 0.01;
    continue when exists (select 1 from public.collections k
                           where k.receivable_id = r.id and k.status = any(v_abertas));
    continue when r.service_order_id is not null
              and exists (select 1 from public.collections k
                           where k.receivable_id is null and k.service_order_id = r.service_order_id
                             and k.status = any(v_abertas));
    insert into public.collections (
      client_id, service_order_id, receivable_id, description, standalone_amount, amount, due_date,
      contact_name, phone, contact_whatsapp, send_method, message_template, auto_rule_enabled, status,
      created_by, notes
    ) values (
      r.client_id, r.service_order_id, r.id, null, null, r.saldo, coalesce(r.due_date, v_hoje),
      v_cli.name, v_cli.phone, coalesce(nullif(btrim(v_cli.whatsapp), ''), v_cli.phone),
      coalesce(v_modelo.send_method, 'text_link'), v_modelo.body, false, 'pending',
      v_quem,
      'Criada junto com o envio do ' || case when v_extrato then '"Enviar extrato"' else '"Cobrar juntas"' end
        || ' em ' || to_char(v_hoje, 'DD/MM/YYYY') || '.'
    )
    returning id into v_id;
    v_criadas := v_criadas || v_id;
  end loop;

  -- 4. Registra o envio em todas as abertas das contas (inclusive as recém-criadas) e nas da OS sem conta
  select array_agg(k.id order by k.id) into v_cobrancas
    from public.collections k
   where k.status = any(v_abertas)
     and (k.receivable_id = any(p_contas)
          or (k.receivable_id is null and k.service_order_id = any(v_os)));
  if v_cobrancas is not null then
    insert into public.collection_contacts (collection_id, contact_type, notes, created_by)
    select x, 'whatsapp_sent', v_nota, v_quem from unnest(v_cobrancas) x;
    update public.collections k
       set status = 'sent', last_auto_sent_at = now()
     where k.id = any(v_cobrancas);
  end if;

  return jsonb_build_object(
    'criadas', cardinality(v_criadas),
    'registradas', coalesce(cardinality(v_cobrancas), 0),
    'cobrancas_criadas', to_jsonb(v_criadas));
end $$;

comment on function public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid) is
  'Cobrar juntas (p_os = as OS escolhidas) ou Enviar extrato com saldo (p_os nulo = o cliente inteiro), depois do envio confirmado: cria a cobrança (collections) das contas que não têm nenhuma aberta e registra o envio (whatsapp_sent + sent + last_auto_sent_at) em todas. Tudo ou nada. Só administrador e financeiro.';

-- Privilégios: os mesmos da 20270212100000 (create or replace os mantém; conferidos de novo).
do $$
begin
  if has_function_privilege('anon', 'public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid)', 'execute')
  then
    raise exception 'Privilégios errados em cobrar_juntas_registrar_envio';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20270212110000', 'extrato_conta_como_cobranca')
on conflict do nothing;
