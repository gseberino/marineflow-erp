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
--    com e sem o 9, o número é o mesmo. Para BLOQUEAR, 8 dígitos bastam (dois números de DDD
--    diferente contam como um só — o erro, quando houver, é mandar MENOS). Para ISENTAR, não: o
--    número da equipe (app_users ativo) só passa com o mesmo DDD (_mesmo_telefone), senão um
--    estranho com os mesmos 8 dígitos do dono escaparia do opt-out e do "Cliente Final".
--
-- 2. Gatilho na fila (whatsapp_send_queue), linha nova ou telefone trocado:
--    - "Cliente Final": nas origens de UMA linha que respondem a quem pediu — a agenda ao cliente,
--      o "a caminho" e a cotação da tela — a gravação é RECUSADA com 23514 (detail sem_telefone):
--      a agenda já faz disso "recusada, sem telefone" (_agenda_cliente_enfileirar) e a tela mostra
--      o erro, em vez de um "Cliente avisado" falso. Nas outras (as automáticas gravam em lote, e
--      um erro derrubaria o lote inteiro) a linha nasce cancelada, com o motivo. As outras linhas
--      da agenda (equipe, dono, fornecedor) não passam por aqui: a agenda é dona delas.
--    - opt-out e lista de bloqueio: cancelados só nas origens AUTOMÁTICAS (nem agenda, que confere
--      o próprio opt-out, nem o que alguém pediu: manual, ai_agent, on-my-way, quote_request).
--
-- Sem dado: nenhuma linha muda. Reverter: drop trigger + drop das funções.

-- DDD de um telefone brasileiro: com 55 (12–13 dígitos) ou sem (10–11). Só 8–9 dígitos: nulo.
create or replace function public._ddd_do_telefone(p_fone text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when d ~ '^55[0-9]{10,11}$' then substr(d, 3, 2)
    when d ~ '^[0-9]{10,11}$' then substr(d, 1, 2)
  end
  from (select regexp_replace(coalesce(p_fone, ''), '\D', '', 'g') as d) x;
$$;

-- O mesmo telefone: os 8 últimos dígitos e, quando os dois lados têm DDD, o mesmo DDD.
create or replace function public._mesmo_telefone(p_a text, p_b text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public._agenda_chave_telefone(p_a) is not null
     and public._agenda_chave_telefone(p_a) = public._agenda_chave_telefone(p_b)
     and (public._ddd_do_telefone(p_a) is null or public._ddd_do_telefone(p_b) is null
          or public._ddd_do_telefone(p_a) = public._ddd_do_telefone(p_b));
$$;

revoke all on function public._ddd_do_telefone(text) from public, anon;
revoke all on function public._mesmo_telefone(text, text) from public, anon;

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
                  where u.active
                    and (public._mesmo_telefone(p_fone, u.phone_normalized) or public._mesmo_telefone(p_fone, u.phone)))
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
  'Retorno F0a: motivo para NÃO mandar mensagem automática ao número (cliente_final, bloqueado, opt_out) ou null. Bloqueia pela chave de 8 dígitos; a equipe (mesmo DDD) nunca é bloqueada.';

revoke all on function public.canal_bloqueado(text) from public, anon, authenticated;
grant execute on function public.canal_bloqueado(text) to service_role;

create or replace function public._fila_recusa_cliente_final()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_motivo text;
  v_fonte text := coalesce(new.source, 'manual');
begin
  if new.status is distinct from 'pending'
     or (v_fonte like 'agenda-%' and v_fonte <> 'agenda-cliente') then
    return new;
  end if;
  v_motivo := public.canal_bloqueado(new.phone_normalized);
  if v_motivo is null then
    return new;
  end if;

  if v_motivo = 'cliente_final' then
    if v_fonte in ('agenda-cliente', 'on-my-way', 'quote_request') then
      raise exception using
        errcode = '23514',
        message = 'Recusado: é o telefone do cadastro genérico "Cliente Final", de um terceiro não identificado.',
        detail = 'sem_telefone';
    end if;
    new.status := 'cancelled';
    new.failed_reason := 'Recusado: é o telefone do cadastro genérico "Cliente Final", de um terceiro não identificado.';
  elsif v_fonte not like 'agenda-%' and v_fonte not in ('manual', 'ai_agent', 'on-my-way', 'quote_request') then
    new.status := 'cancelled';
    new.failed_reason := case v_motivo
      when 'opt_out' then 'Recusado: o contato pediu para não receber mensagens automáticas.'
      else 'Recusado: o número está na lista de bloqueio.' end;
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
