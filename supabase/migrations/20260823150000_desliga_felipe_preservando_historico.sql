-- Felipe não trabalha mais na HBR (informado pelo dono em 23/08/2026).
--
-- DESATIVA, não apaga. Ele tem 8 ordens de serviço atribuídas em
-- `service_order_technicians` — apagar o cadastro levaria junto o registro de quem executou
-- aqueles serviços, e histórico de execução não se reescreve porque alguém saiu.
--
-- `active = false` já o tira das listas de técnico e da atribuição de novas OS; o vínculo antigo
-- continua legível. `resignation_date` existe em `app_users` e é onde essa informação mora.
--
-- Também zera o acesso ao assistente por WhatsApp — quem saiu não conversa com o agente da casa.
-- (No caso dele o acesso já estava desligado e sem telefone cadastrado, mas deixar explícito
-- evita que um cadastro futuro reaproveite a linha com o acesso ligado.)

update public.app_users
set active               = false,
    ai_whatsapp_enabled  = false,
    resignation_date     = coalesce(resignation_date, date '2026-08-23'),
    updated_at           = now()
where id = '8d8d554b-af2c-4024-a32b-ba4b9f5f9aec'
  and full_name = 'Felipe';
