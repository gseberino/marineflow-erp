-- Retorno rápido ao cliente, F0b (06/11/2026): o PARAR de QUALQUER número vira opt-out.
--
-- Hoje o opt-out só é gravado quando o webhook reconhece o contato como cliente ou fornecedor
-- (4 de 22 números de cliente em 90 dias) ou pela agenda, no PARAR de quem recebeu mensagem dela.
-- Quem pediu para parar e não tem cadastro reconhecido continuava recebendo o automático.
--
-- Agora toda RECEBIDA que é só o pedido de parar grava o número em whatsapp_blocked_numbers com
-- tipo 'opt_out' (separado do spam). canal_bloqueado (F0a) já barra esse número no envio
-- automático, e a agenda já o lê (_agenda_cliente_sem_mensagem). Honrar na hora, sem sombra:
-- falha para o lado seguro (manda menos), e a LGPD e a Meta pedem respeito imediato ao "parar".
--
-- A regra é ESTREITA, a mensagem inteira: a mesma palavra do lembrete de manutenção
-- (parar, pare, stop, sair, descadastrar) e "não quero mais (receber) mensagem(ns)". "Nunca mais
-- faço com vocês" ou "me tira essa dúvida" não contam. A equipe nunca entra.
-- Erro aqui nunca derruba a gravação da mensagem: vai ao app_error_logs.
--
-- Sem dado: nenhuma linha muda. Reverter: drop trigger + drop das funções.

create or replace function public._e_pedido_de_parar(p_texto text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select btrim(regexp_replace(regexp_replace(public._texto_simples(p_texto), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'))
         ~ '^(parar|pare|stop|sair|descadastrar|nao quero mais (receber )?(mensagem|mensagens)( automaticas?)?)( por favor| pf)?$';
$$;

comment on function public._e_pedido_de_parar(text) is
  'Retorno F0b: a mensagem inteira é o pedido de parar (parar, pare, stop, sair, descadastrar, "não quero mais mensagem").';

revoke all on function public._e_pedido_de_parar(text) from public, anon;

create or replace function public._whatsapp_mensagem_parar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.direction <> 'inbound' or coalesce(new.phone_normalized, '') ~ '@' or not public._e_pedido_de_parar(new.body) then
    return new;
  end if;
  begin
    if exists (select 1 from public.app_users u
                where u.active and (public._mesmo_telefone(new.phone_normalized, u.phone_normalized)
                                    or public._mesmo_telefone(new.phone_normalized, u.phone)))
       or exists (select 1 from public.payees p where p.active and public._mesmo_telefone(new.phone_normalized, p.phone)) then
      return new;
    end if;
    if not exists (select 1 from public.whatsapp_blocked_numbers b
                    where public._agenda_chave_telefone(b.phone_normalized) = public._agenda_chave_telefone(new.phone_normalized)
                      and b.tipo = 'opt_out') then
      insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo)
      values (new.phone_normalized,
              'Pediu para parar pelo WhatsApp em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
              'opt_out');
    end if;
  exception when others then
    perform public.log_app_error('db', format('opt-out do PARAR: %s', sqlerrm), 'retorno', 'parar', 'error',
                                 jsonb_build_object('mensagem', new.id, 'sqlstate', sqlstate));
  end;
  return new;
end;
$$;

revoke all on function public._whatsapp_mensagem_parar() from public, anon, authenticated;

drop trigger if exists trg_whatsapp_mensagem_parar on public.whatsapp_messages;
create trigger trg_whatsapp_mensagem_parar
  after insert on public.whatsapp_messages
  for each row execute function public._whatsapp_mensagem_parar();
