-- Retorno rápido ao cliente, F0b, parte 1 (06/11/2026): ver direito quem escreve e quando.
--
-- 1. whatsapp_messages.hora_real: a hora em que a mensagem foi MANDADA (messageTimestamp da
--    Evolution), não a de gravação. Medido em 31/10: 387 de 3.691 recebidas foram gravadas com
--    mais de 12 h de atraso (máximo de 135 h) — ao voltar de queda, a Evolution regrava em lote, e
--    o occurred_at (padrão now()) fica com a hora da volta. O occurred_at NÃO muda de sentido (o
--    detector de promessas e outros 18 leitores dependem dele); nada de reescrever o histórico.
--    Vinda do webhook sem messageTimestamp numérico: fica nula. Saída pelos nossos envios
--    (whatsapp-send, caixa do app; sem o "data" do webhook no raw_payload): a hora da gravação,
--    que é a do envio.
--
-- 2. quem_escreve(fone): quem é o número, pela chave de 8 dígitos, devolvendo LISTA e papel —
--    nunca pelo nome (regra 2 do dono). Substitui, depois da sombra, o ILIKE + maybeSingle do
--    webhook, que acha 4 dos 22 números de cliente que escreveram em 90 dias (o cadastro guarda
--    sem o 55). Não usa resolve_contact_identity (LIMIT 1: com número compartilhado falaria da OS
--    do outro cliente).
--    - equipe (app_users e payees ativos) vem primeiro, como na agenda (_agenda_clientes_do_telefone):
--      o número da equipe nunca vira cliente;
--    - cliente: ativo e fora do "Cliente Final". 1 cliente com o mesmo DDD identifica. 2 ou mais,
--      DDD diferente, ou cadastro sem DDD = ambíguo (propõe, nunca identifica);
--    - fornecedor só ATIVO (há 310 linhas de fornecedor inativo com telefone de cliente ativo);
--    - a pessoa de parceiro (MP, Förtro) entra na F4, entre cliente e fornecedor.
--
-- 3. whatsapp_messages.quem_sombra: o resultado de quem_escreve em toda RECEBIDA, gravado por
--    gatilho, em SOMBRA — ninguém lê para decidir. Por 3 dias úteis compara-se com o client_id que
--    o webhook grava hoje; só depois o webhook passa a usar a função (com o OK do dono).
--    Erro na função nunca derruba a gravação da mensagem: vira {"erro": ...}.
--
-- 4. whatsapp_blocked_numbers.tipo: 'spam' (o que existe hoje) ou 'opt_out' (a pessoa pediu
--    PARAR). Hoje são 0 linhas. canal_bloqueado (F0a) já barra os dois no envio automático.
--
-- 5. _saida_e_humana(direção, raw_payload, sent_by): a regra ÚNICA que separa o que o dono mandou
--    do que o sistema mandou, pela ORIGEM gravada (plano B.7):
--    - humano: o eco do celular do dono (webhook: raw_payload com "data" e sem "via"); o
--      whatsapp-send com origem "assistente" ou "tela"; a caixa do app (whatsapp-send-text: sem
--      raw_payload);
--    - automático: o whatsapp-send com origem "sistema" sem sent_by; a fila ("fila:<fonte>"); e
--      qualquer origem desconhecida (na dúvida, não conta como resposta do dono).
--    A regra antiga ("humano = sem via e sem sent_by") desfaria o registro de 15/10: o que o dono
--    aprova pelo assistente sai com via e sent_by. Gravada em whatsapp_messages.saida_humana pelo
--    mesmo gatilho, para quem lê pela API (o detector de promessas) e para as medidas.
--
-- Sem dado: colunas novas nulas, nenhuma linha reescrita. Reverter: drop trigger, drop das
-- funções e das colunas.

alter table public.whatsapp_messages
  add column if not exists hora_real timestamptz,
  add column if not exists quem_sombra jsonb,
  add column if not exists saida_humana boolean;

comment on column public.whatsapp_messages.saida_humana is
  'Retorno F0b: _saida_e_humana() na gravação, só nas enviadas (true = o dono; false = sistema). Nula nas recebidas e nas gravadas antes de 06/11/2026.';

comment on column public.whatsapp_messages.hora_real is
  'Retorno F0b: hora em que a mensagem foi mandada (messageTimestamp); nula quando o webhook não trouxe número. occurred_at segue sendo a hora de gravação.';
comment on column public.whatsapp_messages.quem_sombra is
  'Retorno F0b: quem_escreve() na hora da gravação, em sombra (ninguém decide por ela até a identificação nova ligar).';

alter table public.whatsapp_blocked_numbers
  add column if not exists tipo text not null default 'spam';
alter table public.whatsapp_blocked_numbers
  drop constraint if exists whatsapp_blocked_numbers_tipo_check;
alter table public.whatsapp_blocked_numbers
  add constraint whatsapp_blocked_numbers_tipo_check check (tipo in ('spam', 'opt_out'));

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

create or replace function public.quem_escreve(p_fone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_chave text := public._agenda_chave_telefone(p_fone);
  v_ddd text := public._ddd_do_telefone(p_fone);
  v_equipe boolean;
  v_identificam uuid[];
  v_ambiguos uuid[];
  v_motivo text;
  v_fornecedores uuid[];
begin
  if v_chave is null then
    return jsonb_build_object('papel', 'sem_numero', 'versao', 1);
  end if;

  select exists (select 1 from public.app_users u
                  where u.active and v_chave in (public._agenda_chave_telefone(u.phone_normalized), public._agenda_chave_telefone(u.phone)))
      or exists (select 1 from public.payees p
                  where p.active and public._agenda_chave_telefone(p.phone) = v_chave)
    into v_equipe;
  if v_equipe then
    return jsonb_build_object('papel', 'equipe', 'chave', v_chave, 'ddd', v_ddd, 'versao', 1);
  end if;

  -- Cada cliente pelo telefone que casa (o whatsapp antes do phone): com o mesmo DDD (ou sem DDD
  -- do lado de quem escreve) identifica; DDD diferente ou cadastro sem DDD fica ambíguo.
  with casam as (
    select c.id,
           public._ddd_do_telefone(case when public._agenda_chave_telefone(c.whatsapp) = v_chave then c.whatsapp else c.phone end) as ddd
      from public.clients c
     where c.active and not c.generico
       and v_chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
  )
  select coalesce(array_agg(id order by id) filter (where ddd is not null and (v_ddd is null or ddd = v_ddd)), '{}'),
         coalesce(array_agg(id order by id) filter (where ddd is null or (v_ddd is not null and ddd <> v_ddd)), '{}'),
         case
           when count(*) filter (where ddd is not null and v_ddd is not null and ddd <> v_ddd) > 0 then 'ddd_diferente'
           when count(*) filter (where ddd is null) > 0 then 'cadastro_sem_ddd'
           when count(*) > 1 then 'varios_clientes'
         end
    into v_identificam, v_ambiguos, v_motivo
    from casam;

  if cardinality(v_identificam) = 1 and cardinality(v_ambiguos) = 0 then
    return jsonb_build_object('papel', 'cliente', 'chave', v_chave, 'ddd', v_ddd,
                              'cliente_id', v_identificam[1], 'clientes', to_jsonb(v_identificam), 'versao', 1);
  end if;
  if cardinality(v_identificam) + cardinality(v_ambiguos) > 0 then
    return jsonb_build_object('papel', 'cliente_ambiguo', 'chave', v_chave, 'ddd', v_ddd,
                              'clientes', to_jsonb(v_identificam || v_ambiguos), 'motivo', v_motivo, 'versao', 1);
  end if;

  -- F4: a pessoa de parceiro confirmada pelo dono entra aqui, antes do fornecedor.

  select coalesce(array_agg(s.id order by s.id), '{}') into v_fornecedores
    from public.suppliers s
   where s.active and public._agenda_chave_telefone(s.phone) = v_chave;
  if cardinality(v_fornecedores) > 0 then
    return jsonb_build_object('papel', 'fornecedor', 'chave', v_chave, 'ddd', v_ddd,
                              'fornecedores', to_jsonb(v_fornecedores), 'versao', 1);
  end if;

  return jsonb_build_object('papel', 'novo', 'chave', v_chave, 'ddd', v_ddd, 'versao', 1);
end;
$$;

comment on function public.quem_escreve(text) is
  'Retorno F0b: papel do número pela chave de 8 dígitos (equipe, cliente, cliente_ambiguo, fornecedor, novo), com a lista; nunca pelo nome.';

revoke all on function public.quem_escreve(text) from public, anon, authenticated;
grant execute on function public.quem_escreve(text) to service_role;
revoke all on function public._ddd_do_telefone(text) from public, anon;

create or replace function public._saida_e_humana(p_direcao text, p_raw jsonb, p_sent_by uuid)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when p_direcao is distinct from 'outbound' then null
    when p_raw is null or jsonb_typeof(p_raw) <> 'object' then true
    when p_raw ? 'data' and not (p_raw ? 'via') then true
    when p_raw ->> 'via' = 'whatsapp-send' then
      p_raw ->> 'origem' in ('assistente', 'tela') or (p_raw ->> 'origem' = 'sistema' and p_sent_by is not null)
    else false
  end;
$$;

comment on function public._saida_e_humana(text, jsonb, uuid) is
  'Retorno F0b (plano B.7): a enviada é do dono (true) ou do sistema (false), pela origem gravada; nula na recebida.';

revoke all on function public._saida_e_humana(text, jsonb, uuid) from public, anon;

create or replace function public._whatsapp_mensagem_hora_e_quem()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ts numeric;
begin
  if new.hora_real is null then
    if jsonb_typeof(new.raw_payload -> 'data' -> 'messageTimestamp') = 'number' then
      v_ts := (new.raw_payload -> 'data' ->> 'messageTimestamp')::numeric;
      -- Em segundos (2017 a 2100); fora disso é dado estranho: fica nula, nunca derruba a gravação.
      if v_ts between 1500000000 and 4102444800 then
        new.hora_real := to_timestamp(v_ts);
      end if;
    elsif new.raw_payload is null or jsonb_typeof(new.raw_payload) <> 'object' or not (new.raw_payload ? 'data') then
      new.hora_real := now();
    end if;
  end if;

  if new.direction = 'outbound' then
    new.saida_humana := public._saida_e_humana(new.direction, new.raw_payload, new.sent_by);
  end if;

  if new.direction = 'inbound' and new.quem_sombra is null then
    begin
      new.quem_sombra := public.quem_escreve(new.phone_normalized);
    exception when others then
      new.quem_sombra := jsonb_build_object('erro', left(sqlerrm, 200));
    end;
  end if;
  return new;
end;
$$;

revoke all on function public._whatsapp_mensagem_hora_e_quem() from public, anon, authenticated;

drop trigger if exists trg_whatsapp_mensagem_hora_e_quem on public.whatsapp_messages;
create trigger trg_whatsapp_mensagem_hora_e_quem
  before insert on public.whatsapp_messages
  for each row execute function public._whatsapp_mensagem_hora_e_quem();
