-- Retorno rápido (P16.2): o PIN sai das mensagens antigas. Migration COM DADO, aplicada com o OK nomeado do dono
-- ("OK limpar PIN", 08/11/2026). Desde a 20261106100400 o PIN novo já entra mascarado; esta cuida do que veio antes.
--
-- Por forma, não por hash: o PIN pode já ter mudado, e o hash de hoje não acharia as linhas antigas. A forma é a
-- confirmação do dono: sim|s|ok|confirmar|confirmo|1 + um número de 3 a 8 dígitos no começo da mensagem. Só em
-- recebidas de número da equipe (whatsapp_messages) e em falas do usuário no chat do assistente (ai_operator_messages).
-- Uma frase como "sim 235 reais" tem a mesma forma e também perde o número: não dá para separar sem ler a linha.
--
-- Nunca imprime conteúdo. Idempotente: rodar de novo não acha nada. Se sobrar alguma linha, aborta e não grava.
-- Fora de alcance: D:/IA-HBR/Backups e o PITR do Supabase guardam as linhas antigas. Por isso o dono troca o PIN.
--
-- Reverter: não há. O texto mascarado não volta (só por backup).

update public.whatsapp_messages m
   set body = regexp_replace(m.body, '[0-9]{3,8}(?![0-9])', '••••'),
       raw_payload = case when jsonb_typeof(m.raw_payload) = 'object'
                          then public._whatsapp_payload_sem_texto(m.raw_payload, m.message_type)
                          else m.raw_payload end
 where m.direction = 'inbound'
   and m.phone_normalized in (select phone_normalized from public.app_users where phone_normalized is not null)
   and m.body ~* '^\s*(🎤\s*)?"?\s*(sim|s|ok|confirmar|confirmo|1)[\s,.;:!-]+[0-9]{3,8}(?![0-9])';

update public.ai_operator_messages a
   set content = regexp_replace(a.content, '[0-9]{3,8}(?![0-9])', '••••')
 where a.role = 'user'
   and a.content ~* '^\s*(🎤\s*)?"?\s*(sim|s|ok|confirmar|confirmo|1)[\s,.;:!-]+[0-9]{3,8}(?![0-9])';

do $$
begin
  if exists (select 1 from public.whatsapp_messages m
              where m.direction = 'inbound'
                and m.phone_normalized in (select phone_normalized from public.app_users where phone_normalized is not null)
                and m.body ~* '^\s*(🎤\s*)?"?\s*(sim|s|ok|confirmar|confirmo|1)[\s,.;:!-]+[0-9]{3,8}(?![0-9])')
     or exists (select 1 from public.ai_operator_messages a
                 where a.role = 'user'
                   and a.content ~* '^\s*(🎤\s*)?"?\s*(sim|s|ok|confirmar|confirmo|1)[\s,.;:!-]+[0-9]{3,8}(?![0-9])') then
    raise exception 'pin_limpar_antigas: sobrou linha com a forma do PIN';
  end if;
end $$;
