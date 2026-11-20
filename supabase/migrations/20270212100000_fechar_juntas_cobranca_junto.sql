-- "Cobrar juntas": a cobrança é criada junto com o envio quando a conta não tem uma. 20/11/2026.
--
-- Decisão do dono (Respostas do Diário, 20/11/2026), cartão "Cobrar juntas: criar a cobrança quando a conta não
-- tem uma?" → "Criar a cobrança junto". Caso real: a MP MOTOR HOMES (OS-00045 R$ 1.650 + OS-00046 R$ 20, vencidas
-- desde 22/07) tem as contas a receber e NENHUMA cobrança (collections). Até aqui o "Cobrar juntas" mandava a
-- mensagem e só avisava que o envio não ficava registrado: sem cobrança não há onde gravar last_auto_sent_at, que é
-- o que o plano de inadimplência (get_delinquency_plan) lê para não sugerir cobrar o mesmo cliente de novo no dia.
--
-- "Cobrança registrada" = linha em public.collections (a tela Cobranças, criar_cobranca do assistente,
-- CreateCollectionDialog). Nada de tabela nova: esta função cria a MESMA linha que criar_cobranca cria para uma
-- conta da OS (ligada à conta pelo receivable_id, valor = saldo, vencimento = o da conta, contato do cadastro,
-- modelo de mensagem padrão, régua automática desligada, situação 'pending') e registra o envio do MESMO jeito
-- que registrarEnvioDaCobranca (_shared/ai/tools/cobrancas.ts) e a tela já registravam: contato 'whatsapp_sent' +
-- situação 'sent' + last_auto_sent_at.
--
-- Sem duplicar: não cria quando a conta já tem cobrança aberta (pela conta) nem quando a OS da conta tem cobrança
-- aberta SEM conta (a "Total" gerada na aprovação por generate-collections.ts, ou a avulsa da OS) — nesses casos o
-- envio é registrado na que existe. As contas ficam travadas (FOR UPDATE) na mesma ordem: dois envios ao mesmo
-- tempo não criam duas cobranças para a mesma conta (o segundo espera e encontra a do primeiro).
--
-- Atômico, nesta ordem (documentado aqui e no hook/tool): a mensagem sai PRIMEIRO pelo whatsapp-send; só com o
-- envio confirmado (não desviado pelo modo de teste, não "já enviado hoje") a tela/tool chama esta função. Mensagem
-- que não sai = função não chamada = nenhuma cobrança criada. Esta função é tudo-ou-nada: ou cria as que faltam E
-- registra o envio em todas, ou não grava nada — e aí a tela/tool avisa "a mensagem foi enviada, mas não consegui
-- registrar". O inverso (criar antes e apagar se o envio falhar) deixaria cobrança órfã quando o apagar falhasse.
--
-- Quem pode: o mesmo de quem já gravava direto (RLS de collections: logado, menos o vendedor externo). A tool
-- cobrar_juntas restringe a administrador e financeiro antes de chegar aqui.

create or replace function public.cobrar_juntas_registrar_envio(
  p_cliente uuid,
  p_contas uuid[],          -- as contas a receber que entraram na mensagem (com saldo)
  p_os uuid[],              -- as OS escolhidas (as cobranças da OS sem conta também recebem o registro)
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
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_nota text;
  v_id uuid;
  v_criadas uuid[] := '{}';
  v_cobrancas uuid[];
  v_abertas constant text[] := array['pending', 'sent', 'viewed', 'overdue', 'disputed'];
  r record;
begin
  -- 0. Quem pede
  if v_autor is null then
    raise exception 'Faça login para registrar a cobrança.' using errcode = '42501';
  end if;
  select u.id into v_quem from public.app_users u where u.id = v_autor and coalesce(u.active, true);
  if v_quem is null or public.is_external_seller(v_autor) then
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
    raise exception 'O cadastro % é genérico, sem CPF/CNPJ: não entra em cobrança conjunta.', coalesce(v_cli.name, 'deste cliente')
      using errcode = '22023';
  end if;

  -- 2. Trava as contas sempre na mesma ordem e confere: existem, são do cliente (o titular) e das OS escolhidas
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
          or x.service_order_id is null
          or not (x.service_order_id = any(coalesce(p_os, '{}'::uuid[]))));
  if v_fora is not null then
    raise exception 'Estas contas não são deste cliente ou de uma das OS escolhidas: %.', v_fora using errcode = '22023';
  end if;

  -- O modelo de mensagem padrão, como criar_cobranca e a tela escolhem (o padrão, senão o primeiro pelo nome)
  select t.body, t.send_method into v_modelo
    from public.collection_templates t
   order by t.is_default desc nulls last, t.name
   limit 1;
  v_nota := coalesce(nullif(btrim(p_nota), ''), 'Cobrar juntas (várias OS numa mensagem)');

  -- 3. Cria a cobrança de cada conta com saldo que não tem nenhuma aberta (pela conta, ou da OS sem conta)
  for r in
    select x.id, x.client_id, x.service_order_id, x.due_date,
           round(greatest(coalesce(x.balance_amount, x.amount - coalesce(x.paid_amount, 0)), 0), 2) as saldo
      from public.receivables x
     where x.id = any(p_contas)
       and x.status not in ('paid', 'cancelled')
     order by x.service_order_id, x.due_date nulls last, x.id
  loop
    continue when r.saldo < 0.01;
    continue when exists (select 1 from public.collections k
                           where k.receivable_id = r.id and k.status = any(v_abertas));
    continue when exists (select 1 from public.collections k
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
      v_quem, 'Criada junto com o envio do "Cobrar juntas" em ' || to_char(v_hoje, 'DD/MM/YYYY') || '.'
    )
    returning id into v_id;
    v_criadas := v_criadas || v_id;
  end loop;

  -- 4. Registra o envio em todas as abertas das contas (inclusive as recém-criadas) e nas da OS sem conta
  select array_agg(k.id order by k.id) into v_cobrancas
    from public.collections k
   where k.status = any(v_abertas)
     and (k.receivable_id = any(p_contas)
          or (k.receivable_id is null and k.service_order_id = any(coalesce(p_os, '{}'::uuid[]))));
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
  'Cobrar juntas, depois do envio confirmado: cria a cobrança (collections) das contas que não têm nenhuma aberta e registra o envio (whatsapp_sent + sent + last_auto_sent_at) em todas. Tudo ou nada.';

-- Privilégios: logado (a tela) e service role (o assistente). Anon fora, por nome (o padrão do Supabase concede).
revoke all on function public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid) from public, anon;
grant execute on function public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid) to authenticated, service_role;

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
values ('20270212100000', 'fechar_juntas_cobranca_junto')
on conflict do nothing;
