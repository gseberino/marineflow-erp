-- Sinal pago: o orçamento deixa de "aguardar sinal".
--
-- POR QUE: 10 OS com o sinal PAGO continuavam com quote_status = 'awaiting_deposit' (OS-00060,
-- 61, 69, 73, 74, 75, 77, 84, 94, 104). Na ficha da OS o botão "Registrar sinal" aparece enquanto o
-- orçamento aguarda sinal — com o sinal já pago, era a porta para registrá-lo duas vezes — e o
-- assistente e o resumo do dia listavam essas OS como "aguardando sinal".
--
-- A causa: register_deposit_and_convert grava o sinal JÁ PAGO (insert) e converte a OS ela mesma;
-- a regra on_quote_deposit_paid só olha UPDATE do recebível e só age em orçamento ainda não
-- convertido. Nenhum caminho levava o orçamento convertido a 'approved' — que é o estado das
-- outras 30 OS convertidas.
--
-- 1) Na conversão (converted_to_os_at preenchido), com sinal pago, quote_status vira 'approved'.
-- 2) Sinal pago depois, numa OS já convertida (pelo Extrato, pelo "Este Pix paga…"): idem.
-- 3) As 10 de hoje, com trilha em audit_log.
-- O status da OS (open, completed…) não muda; os gatilhos de estoque, comissão e casos de serviço
-- só reagem à troca de status.

create or replace function public.orcamento_aprovado_ao_converter()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.quote_status = 'awaiting_deposit'
     and new.converted_to_os_at is not null
     and old.converted_to_os_at is null
     and exists (
       select 1 from public.receivables r
        where r.service_order_id = new.id and r.is_deposit and r.status in ('paid', 'partially_paid')
     )
  then
    new.quote_status := 'approved';
  end if;
  return new;
end;
$$;

revoke all on function public.orcamento_aprovado_ao_converter() from public, anon, authenticated;

drop trigger if exists trg_orcamento_aprovado_ao_converter on public.service_orders;
create trigger trg_orcamento_aprovado_ao_converter
  before update of converted_to_os_at on public.service_orders
  for each row execute function public.orcamento_aprovado_ao_converter();

create or replace function public.handle_quote_deposit_payment()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- Only fire when status moves TO paid/partially_paid
  if new.service_order_id is not null
     and new.status in ('paid', 'partially_paid')
     and (old.status is distinct from new.status) then

    update public.service_orders
    set
      converted_to_os_at = now(),
      status             = 'approved',
      quote_status       = 'approved'
    where id                  = new.service_order_id
      and converted_to_os_at  is null
      and quote_status         = 'awaiting_deposit';

    -- Sinal pago numa OS já convertida (Extrato, "Este Pix paga…"): só o estado do orçamento.
    if new.is_deposit then
      update public.service_orders
         set quote_status = 'approved'
       where id = new.service_order_id
         and converted_to_os_at is not null
         and quote_status = 'awaiting_deposit';
    end if;

  end if;
  return new;
end;
$function$;

with corrigidas as (
  update public.service_orders so
     set quote_status = 'approved'
   where so.quote_status = 'awaiting_deposit'
     and so.converted_to_os_at is not null
     and exists (
       select 1 from public.receivables r
        where r.service_order_id = so.id and r.is_deposit and r.status in ('paid', 'partially_paid')
     )
  returning so.id, so.service_order_number
)
insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
select 'service_orders', c.id, 'update', 'migration 20261003210000',
       jsonb_build_object('quote_status', 'awaiting_deposit'),
       jsonb_build_object('quote_status', 'approved'),
       c.service_order_number || ': sinal já pago; orçamento ficou "aguardando sinal" porque register_deposit_and_convert não mudava o estado (autorizado pelo dono em 03/10/2026)'
  from corrigidas c;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261003210000', 'sinal_pago_aprova_orcamento')
on conflict do nothing;
