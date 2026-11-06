-- Retorno rápido (P16.1): o PIN da equipe para de ficar em claro em whatsapp_messages. Sem dado: vale do gatilho em
-- diante; as linhas antigas são outra migration, com OK próprio.
--
-- Por quê: get_whatsapp_conversation lê body cru, com busca em todas as conversas, então o modelo consegue ler um
-- "sim <PIN>" de semanas atrás. raw_payload guarda a mesma coisa.
--
-- O turno não é afetado: a confirmação usa o texto em memória, que o webhook já tem e que a transcrição devolve na
-- resposta. Ninguém relê body para decidir (conferido em 06/11: webhook, ai-agent, comprovantes e as 6 funções SQL que
-- leem body).
--
-- Desvio da spec, com o motivo: ela apagava data.message de toda mensagem de texto mascarada. O fluxo de comprovantes
-- guarda documento com legenda como message_type = 'text', e a referência do arquivo está em
-- data.message.documentWithCaptionMessage: nesse envelope só a legenda sai.
--
-- Hash: "<salt>:<sha256hex de 'salt:pin'>", o mesmo de _shared/ai/whatsapp-pin.ts. A paridade é testada dos dois lados.
--
-- Reverter: drop trigger trg_whatsapp_mascarar_pin on public.whatsapp_messages. O texto já mascarado não volta.

create or replace function public._whatsapp_payload_sem_texto(p_payload jsonb, p_tipo text)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when p_tipo = 'text'
         and not coalesce((p_payload #> '{data,message}') ? 'documentWithCaptionMessage', false)
      then p_payload #- '{data,message}'
    else p_payload
      #- '{data,message,imageMessage,caption}'
      #- '{data,message,videoMessage,caption}'
      #- '{data,message,documentMessage,caption}'
      #- '{data,message,documentWithCaptionMessage,message,documentMessage,caption}'
  end || '{"pin_mascarado": true}'::jsonb;
$$;

comment on function public._whatsapp_payload_sem_texto(jsonb, text) is
  'Retorno P16: tira o texto da carga do webhook e preserva data.key e data.messageTimestamp, que o dedupe e a hora_real usam. Mídia e documento com legenda perdem só a legenda.';

create or replace function public._whatsapp_mascarar_pin()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_guardado text;
  v_salt text;
  v_hash text;
  v_corpo text := new.body;
  v_achado text;
begin
  -- Mensagem de cliente passa aqui, em 1 índice, e sai sem custo nem máscara.
  select u.ai_whatsapp_pin_hash into v_guardado
    from public.app_users u
   where u.phone_normalized = new.phone_normalized
     and u.ai_whatsapp_enabled
     and u.active;
  if v_guardado is null then
    return new;
  end if;

  v_salt := split_part(v_guardado, ':', 1);
  v_hash := split_part(v_guardado, ':', 2);

  -- 1. O PIN inteiro, em qualquer ponto da frase.
  for v_achado in
    select distinct t.m[1]
      from regexp_matches(v_corpo, '(?<![0-9])[0-9]{3,8}(?![0-9])', 'g') as t(m)
     limit 30
  loop
    if encode(sha256(convert_to(v_salt || ':' || v_achado, 'UTF8')), 'hex') = v_hash then
      v_corpo := regexp_replace(v_corpo, '(?<![0-9])' || v_achado || '(?![0-9])', '••••', 'g');
    end if;
  end loop;

  -- 2. O PIN com os dígitos separados: o áudio transcrito traz "7 3 9 1" e "7, 3, 9, 1".
  for v_achado in
    select distinct t.m[1]
      from regexp_matches(v_corpo, '(?<![0-9])[0-9](?:[[:space:].,-]{1,2}[0-9]){2,7}(?![0-9])', 'g') as t(m)
     limit 30
  loop
    if encode(sha256(convert_to(v_salt || ':' || regexp_replace(v_achado, '[^0-9]', '', 'g'), 'UTF8')), 'hex') = v_hash then
      v_corpo := replace(v_corpo, v_achado, '••••');
    end if;
  end loop;

  -- 3. A forma inteira de um comando com PIN, mesmo que o número não bata: PIN errado por um dígito é quase o PIN.
  if v_corpo ~* '^\s*(🎤\s*)?"?\s*(sim|s|ok|confirmar|confirmo|1)[\s,.;:!-]+[0-9]{3,8}[\s.!"]*$' then
    v_corpo := regexp_replace(v_corpo, '[0-9]{3,8}', '••••');
  end if;

  if v_corpo = new.body then
    return new;
  end if;
  new.body := v_corpo;

  -- No update (a transcrição do áudio regrava body) a carga não tem o texto dito: ela fica como está.
  if tg_op = 'INSERT' and new.raw_payload is not null then
    begin
      new.raw_payload := public._whatsapp_payload_sem_texto(new.raw_payload, new.message_type);
    exception when others then
      -- Carga fora do formato: nenhum leitor a entende, e entre perdê-la e guardar o PIN nela, perde-se a carga.
      new.raw_payload := '{"pin_mascarado": true}'::jsonb;
      perform public.log_app_error('db', 'máscara do PIN: carga fora do formato (' || sqlstate || ')',
        '_whatsapp_mascarar_pin', 'mascarar_carga', 'warn', null);
    end;
  end if;

  return new;
exception when others then
  -- Perder a mensagem é pior. O corpo nunca vai ao log; log_app_error não lança erro.
  perform public.log_app_error('db', 'máscara do PIN falhou (' || sqlstate || ')',
    '_whatsapp_mascarar_pin', 'mascarar', 'error', null);
  return new;
end;
$$;

comment on function public._whatsapp_mascarar_pin() is
  'Retorno P16: mascara o PIN em whatsapp_messages na chegada e na transcrição. Só para número da equipe com PIN; nunca bloqueia a mensagem.';

revoke all on function public._whatsapp_payload_sem_texto(jsonb, text) from public, anon, authenticated;
revoke all on function public._whatsapp_mascarar_pin() from public, anon, authenticated;

-- O nome ordena antes de trg_whatsapp_mensagem_hora_e_quem (gatilhos rodam em ordem alfabética): ela já lê a carga limpa,
-- e data.messageTimestamp segue lá.
drop trigger if exists trg_whatsapp_mascarar_pin on public.whatsapp_messages;
create trigger trg_whatsapp_mascarar_pin
  before insert or update of body on public.whatsapp_messages
  for each row
  when (new.direction = 'inbound' and new.body ~ '[0-9][[:space:].,-]{0,2}[0-9][[:space:].,-]{0,2}[0-9]')
  execute function public._whatsapp_mascarar_pin();
