-- Migration: adiciona suporte a target_kind = 'manual' na tabela whatsapp_scheduled_sends
-- Permite agendar mensagens avulsas sem vincular a OS ou recebível

-- 1. Remove a constraint antiga que exige service_order_id ou receivable_id
ALTER TABLE whatsapp_scheduled_sends
  DROP CONSTRAINT IF EXISTS chk_target;

-- 2. Remove o CHECK inline do target_kind original (recriado na nova constraint)
-- (a constraint inline já foi dropada com o DROP CONSTRAINT acima em alguns Postgres,
--  mas fazemos o ALTER COLUMN para garantir)
ALTER TABLE whatsapp_scheduled_sends
  ALTER COLUMN target_kind TYPE text;

-- 3. Recria a constraint permitindo 'manual', 'service_order' e 'receivable'
ALTER TABLE whatsapp_scheduled_sends
  ADD CONSTRAINT chk_target CHECK (
    (target_kind = 'service_order' AND service_order_id IS NOT NULL) OR
    (target_kind = 'receivable'    AND receivable_id    IS NOT NULL) OR
    (target_kind = 'manual')
  );
