-- Retorno rápido ao cliente, F0a-1 (05/11/2026): parar o que fala errado, sem mandar nada novo.
--
-- 1. canal_bloqueado(fone): por que um número NÃO pode receber mensagem AUTOMÁTICA, ou null.
--    Lida pelo whatsapp-send nas origens automáticas (origem "sistema") e pelo gatilho da fila.
--    O envio que o dono pede (tela ou assistente) não passa por aqui.
--    Medido em 31/10: 0 opt-out em clients, 0 em suppliers, 0 números bloqueados; o opt-out não
--    era conferido por whatsapp-send, receivable-reminders, process-scheduled nem pela fila fora
--    da agenda. E o "Cliente Final" (clients.generico) guarda o telefone de um terceiro que
--    ninguém identificou: um PDF com preço e Pix iria para ele.
--
--    Chave pelos 8 últimos dígitos (_agenda_chave_telefone), a mesma da agenda: com e sem o 55,
--    com e sem o 9, o número é o mesmo. Dois números de DDD diferente com os mesmos 8 dígitos
--    contam como um só aqui — o erro, quando houver, é mandar MENOS.
--    Número da equipe (app_users ativo) nunca é bloqueado: o aviso ao dono não pode sumir porque
--    alguém pôs o telefone dele num cadastro.
--
-- 2. Gatilho na fila: linha nova (ou telefone trocado) para o número do "Cliente Final" nasce
--    cancelada, com o motivo. Vale para toda origem da fila, que é toda automática ou agendada.
--
-- Sem dado: nenhuma linha muda. Reverter: drop trigger + drop das duas funções.

create or replace function public.canal_bloqueado(p_fone text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  with k as (select public._agenda_chave_telefone(p_fone) as chave)
  select case
    when k.chave is null then null
    when exists (select 1 from public.app_users u
                  where u.active and public._agenda_chave_telefone(u.phone_normalized) = k.chave)
      then null
    when exists (select 1 from public.clients c
                  where c.generico
                    and k.chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone)))
      then 'cliente_final'
    when exists (select 1 from public.whatsapp_blocked_numbers b
                  where public._agenda_chave_telefone(b.phone_normalized) = k.chave)
      then 'bloqueado'
    when exists (select 1 from public.clients c
                  where c.opt_out_whatsapp
                    and k.chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone)))
      then 'opt_out'
    when exists (select 1 from public.suppliers s
                  where s.opt_out_whatsapp and public._agenda_chave_telefone(s.phone) = k.chave)
      then 'opt_out'
  end
  from k;
$$;

comment on function public.canal_bloqueado(text) is
  'Retorno F0a: motivo para NÃO mandar mensagem automática ao número (cliente_final, bloqueado, opt_out) ou null. Chave de 8 dígitos; equipe nunca bloqueada.';

revoke all on function public.canal_bloqueado(text) from public, anon, authenticated;
grant execute on function public.canal_bloqueado(text) to service_role;

create or replace function public._fila_recusa_cliente_final()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'pending' and public.canal_bloqueado(new.phone_normalized) = 'cliente_final' then
    new.status := 'cancelled';
    new.failed_reason := 'Recusado: é o telefone do cadastro genérico "Cliente Final", de um terceiro não identificado.';
  end if;
  return new;
end;
$$;

revoke all on function public._fila_recusa_cliente_final() from public, anon, authenticated;

-- O nome ordena este gatilho depois dos da agenda (trg_agenda_*) e antes do de idempotência:
-- o que a agenda devolve como pendente ainda passa por aqui.
drop trigger if exists trg_whatsapp_send_queue_cliente_final on public.whatsapp_send_queue;
create trigger trg_whatsapp_send_queue_cliente_final
  before insert or update of phone_normalized on public.whatsapp_send_queue
  for each row execute function public._fila_recusa_cliente_final();
