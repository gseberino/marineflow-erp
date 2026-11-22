-- O que vence, fatia 1 (21/11/2026): o boleto que chega por e-mail vira conta a pagar.
--
-- Pedido do dono (21/11): "não consigo ter controle nenhum sobre o financeiro da empresa, nem com cobranças, boletos a
-- pagar, controle de prioridade de pagamentos". Medido no mesmo dia: 1.829 das 1.837 contas pagas nasceram do extrato,
-- depois de o dinheiro sair; só 9 contas em aberto. O e-mail já lê os boletos (email_messages.dados_extraidos ->
-- 'boletos', conferidos por dígito verificador, sem IA): 21 boletos distintos, e só os que tinham nota fiscal
-- importada apareciam em Contas a pagar. Unifique, Celesc, DAS, Compass e Auto Tintas nunca apareceram.
-- Decisão do dono (21/11): o sistema cria a conta a pagar sozinho ao ler o boleto. Não paga nada.
--
-- O que esta migration faz (SEM dados: só colunas, a lista de origens, um índice e uma função):
--   1. payables.boleto_linha (a linha digitável, só dígitos) e payables.email_message_id (de onde veio);
--   2. origem nova 'boleto' na lista fechada de payables.origin;
--   3. um boleto = uma conta viva (índice único parcial; a função também olha as canceladas, para a recusa ficar);
--   4. contas_a_pagar_do_email(e-mail): para cada boleto com valor e vencimento certos —
--        a) a linha já está numa conta (mesmo cancelada)  → nada;
--        b) existe conta do mesmo valor no vencimento (parcela da nota, lançada à mão) ou já paga pelo Extrato por
--           boleto perto do vencimento                    → a linha é LIGADA a ela, nada é criado;
--        c) há saída por boleto do mesmo valor no banco, ainda sem lançamento → parece pago, nada é criado
--           (o Extrato cuida dela);
--        d) venceu há mais de 5 dias                      → nada (histórico: não dá para saber se foi pago com juros
--           ou por outra conta);
--        e) senão                                         → conta a pagar nova, origem 'boleto'.
--      Fornecedor só por documento: o cadastro que o e-mail já tem, ou o CNPJ do emitente da NF-e do mesmo e-mail.
--      Sem isso a conta nasce sem fornecedor, com o nome do remetente como texto (regra do dono, 26/09: nome
--      diferente nunca identifica). Categoria: a mais usada daquele fornecedor; sem fornecedor, sem categoria.
--
-- Chave de desligar sem publicar: app_settings 'boleto_email_modo' = 'desligado' (ausente = ligado).
-- Quem chama: a função email-imap (service_role), depois de gravar dados_extraidos. Ninguém mais.

alter table public.payables
  add column if not exists boleto_linha text,
  add column if not exists email_message_id uuid references public.email_messages(id) on delete set null;

comment on column public.payables.boleto_linha is
  'Linha digitável do boleto desta conta (só dígitos, 47 ou 48). Preenchida por contas_a_pagar_do_email.';
comment on column public.payables.email_message_id is
  'E-mail de onde o boleto desta conta foi lido (o primeiro que o trouxe).';

alter table public.payables drop constraint if exists chk_payables_origin;
alter table public.payables add constraint chk_payables_origin check (origin = any (array[
  'manual'::text, 'service_order_expense'::text, 'bank_reconciliation'::text, 'fiscal_note'::text,
  'commission'::text, 'purchase_order'::text, 'folha'::text, 'boleto'::text]));

create unique index if not exists payables_um_por_boleto
  on public.payables (boleto_linha)
  where boleto_linha is not null and status <> 'cancelled';

create or replace function public.contas_a_pagar_do_email(p_email_message_id uuid, p_hoje date default public._hoje_brt())
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_modo    text := coalesce((select s.value from public.app_settings s where s.key = 'boleto_email_modo'), 'ligado');
  v_m       public.email_messages%rowtype;
  b         jsonb;
  v_linha   text;
  v_valor   numeric;
  v_venc    date;
  v_rec     date;
  v_forn    uuid;
  v_nome    text;
  v_cat     text;
  v_ids     uuid[];
  v_alvo    uuid;
  v_criadas int := 0;
  v_ligadas int := 0;
  v_ja      int := 0;
  v_ign     int := 0;
  v_pagas   int := 0;
  v_antigas int := 0;
  v_barr    int := 0;
  v_erros   text[] := array[]::text[];
begin
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true);
  end if;
  select * into v_m from public.email_messages where id = p_email_message_id;
  if not found then
    raise exception 'contas_a_pagar_do_email: o e-mail % não existe', p_email_message_id using errcode = 'P0002';
  end if;
  if jsonb_typeof(v_m.dados_extraidos -> 'boletos') is distinct from 'array' then
    return jsonb_build_object('criadas', 0, 'ligadas', 0, 'ja_existiam', 0, 'ignoradas', 0,
                              'parecem_pagas', 0, 'antigas', 0, 'barradas', 0);
  end if;
  v_rec := (v_m.received_at at time zone 'America/Sao_Paulo')::date;

  -- Fornecedor só por documento: o cadastro que o e-mail já tem; senão o CNPJ do emitente da NF-e para a HBR que veio
  -- no mesmo e-mail, quando aponta para UM cadastro ativo.
  v_forn := v_m.supplier_id;
  if v_forn is null and jsonb_typeof(v_m.dados_extraidos -> 'nfes') = 'array' then
    v_ids := array(
      select distinct s.id
        from jsonb_array_elements(v_m.dados_extraidos -> 'nfes') n
        join public.suppliers s
          on regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') = regexp_replace(coalesce(n ->> 'emitente_cnpj', ''), '\D', '', 'g')
       where coalesce((n ->> 'para_empresa')::boolean, false)
         and coalesce(s.active, true)
         and regexp_replace(coalesce(n ->> 'emitente_cnpj', ''), '\D', '', 'g') ~ '^\d{14}$');
    if cardinality(v_ids) = 1 then
      v_forn := v_ids[1];
    end if;
  end if;
  if v_forn is not null then
    select s.name into v_nome from public.suppliers s where s.id = v_forn;
    -- A categoria mais usada daquele fornecedor, se ainda existe no plano de contas (o gatilho recusa a que não existe).
    select p.expense_category into v_cat
      from public.payables p
     where p.supplier_id = v_forn and p.status <> 'cancelled' and coalesce(p.expense_category, '') <> ''
       and exists (select 1 from public.financial_categories c
                    where c.name = p.expense_category and c.type = 'payable' and c.active)
     group by p.expense_category
     order by count(*) desc, max(p.created_at) desc
     limit 1;
  else
    v_nome := nullif(btrim(coalesce(nullif(btrim(v_m.from_name), ''), v_m.from_address, '')), '');
  end if;

  for b in select e from jsonb_array_elements(v_m.dados_extraidos -> 'boletos') e loop
    v_linha := regexp_replace(coalesce(b ->> 'linha', ''), '\D', '', 'g');
    v_valor := case when coalesce(b ->> 'valor', '') ~ '^\d+(\.\d+)?$' then round((b ->> 'valor')::numeric, 2) end;
    v_venc  := case when coalesce(b ->> 'vencimento', '') ~ '^\d{4}-\d{2}-\d{2}$' then (b ->> 'vencimento')::date end;
    if v_linha !~ '^\d{47,48}$' or v_valor is null or v_valor <= 0 or v_venc is null
       or coalesce(b ->> 'vencimento_incerto', '') = 'true' then
      v_ign := v_ign + 1;
      continue;
    end if;

    -- a) a linha já está numa conta, mesmo cancelada (a recusa do dono fica).
    if exists (select 1 from public.payables p where p.boleto_linha = v_linha) then
      v_ja := v_ja + 1;
      continue;
    end if;

    -- b) a conta deste boleto já existe: a parcela da nota ou a lançada à mão (pelo vencimento), ou a despesa que o
    --    Extrato já lançou a partir de um pagamento por boleto perto do vencimento. A mais próxima na data.
    select p.id into v_alvo
      from public.payables p
      left join public.bank_transactions t on t.id = p.bank_transaction_id
     where p.status <> 'cancelled'
       and p.boleto_linha is null
       and abs(p.amount - v_valor) < 0.01
       and (v_forn is null or p.supplier_id is null or p.supplier_id = v_forn)
       and (
            p.due_date between v_venc - 3 and v_venc + 3
         or (p.bank_transaction_id is not null and p.issue_date between v_venc - 10 and v_venc + 20
             and (upper(coalesce(t.payment_method, '')) = 'BOLETO' or t.description ilike '%boleto%'))
           )
     order by (p.supplier_id is not distinct from v_forn) desc, abs(p.due_date - v_venc), p.created_at
     limit 1
       for update of p;
    if v_alvo is not null then
      begin
        update public.payables
           set boleto_linha = v_linha,
               email_message_id = coalesce(email_message_id, p_email_message_id)
         where id = v_alvo;
        v_ligadas := v_ligadas + 1;
      exception when unique_violation then
        v_ja := v_ja + 1;
      end;
      continue;
    end if;

    -- c) saiu do banco por boleto, no mesmo valor, e ainda não virou lançamento: parece pago. O Extrato cuida.
    if exists (
      select 1 from public.bank_transactions t
       where t.transaction_type = 'debit'
         and abs(t.amount - v_valor) < 0.01
         and t.transaction_date between v_venc - 10 and v_venc + 20
         and (upper(coalesce(t.payment_method, '')) = 'BOLETO' or t.description ilike '%boleto%')
         and coalesce(t.dismissed_kind, '') <> 'duplicata'
         and not exists (select 1 from public.payables p where p.bank_transaction_id = t.id and p.status <> 'cancelled')
    ) then
      v_pagas := v_pagas + 1;
      continue;
    end if;

    -- d) histórico: vencido há mais de 5 dias não vira conta (pode ter sido pago com juros ou por outra conta).
    if v_venc < p_hoje - 5 then
      v_antigas := v_antigas + 1;
      continue;
    end if;

    -- e) conta a pagar nova. Mês fechado ou corrida com outro e-mail do mesmo boleto não derrubam a leitura.
    begin
      insert into public.payables (
        supplier_id, supplier_name, expense_category, description, issue_date, due_date, amount,
        status, paid_amount, balance_amount, origin, boleto_linha, email_message_id, notes)
      values (
        v_forn, v_nome, v_cat,
        left('Boleto — ' || coalesce(nullif(btrim(v_m.subject), ''), v_nome, 'recebido por e-mail'), 200),
        least(v_rec, v_venc), v_venc, v_valor,
        'pending', 0, v_valor, 'boleto', v_linha, p_email_message_id,
        'Criada sozinha a partir do boleto que chegou por e-mail em ' || to_char(v_rec, 'DD/MM/YYYY')
          || coalesce(' (de ' || nullif(btrim(coalesce(v_m.from_name, v_m.from_address, '')), '') || ')', '') || '.');
      v_criadas := v_criadas + 1;
    exception
      when unique_violation then
        v_ja := v_ja + 1;
      when others then
        -- nunca calado: o motivo volta para quem chamou (a email-imap grava em app_error_logs).
        v_barr := v_barr + 1;
        v_erros := v_erros || left(sqlstate || ': ' || sqlerrm, 200);
    end;
  end loop;

  return jsonb_build_object('criadas', v_criadas, 'ligadas', v_ligadas, 'ja_existiam', v_ja, 'ignoradas', v_ign,
                            'parecem_pagas', v_pagas, 'antigas', v_antigas, 'barradas', v_barr,
                            'erros', to_jsonb(v_erros));
end;
$function$;

comment on function public.contas_a_pagar_do_email(uuid, date) is
  'O boleto lido no e-mail vira conta a pagar (ou é ligado à conta que já existe). Só a função email-imap chama.';

-- Só o serviço: o grant padrão vem de PUBLIC, então revogar de PUBLIC, anon e authenticated e conceder nominal.
revoke all on function public.contas_a_pagar_do_email(uuid, date) from public;
revoke all on function public.contas_a_pagar_do_email(uuid, date) from anon;
revoke all on function public.contas_a_pagar_do_email(uuid, date) from authenticated;
grant execute on function public.contas_a_pagar_do_email(uuid, date) to service_role;
