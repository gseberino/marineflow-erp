-- Comissionado entra como tipo de favorecido.
--
-- POR QUE: `commissions.user_id` aponta para usuários do sistema, então só quem tem login
-- pode receber comissão. A tabela tem ZERO linhas. Enquanto isso, 60 ordens de serviço
-- guardam o comissionado em texto livre (`commissioned_person`) — e o conteúdo mostra o
-- estrago: "Gustavo", "felipe@hbrmarine.com.br" e strings vazias convivem no mesmo campo.
-- Três grafias da mesma pessoa são três pessoas para qualquer soma.
--
-- Mesmo raciocínio do diarista: quem vende não precisa de login no ERP para receber.

ALTER TABLE public.payees DROP CONSTRAINT IF EXISTS payees_kind_check;

ALTER TABLE public.payees ADD CONSTRAINT payees_kind_check CHECK (kind IN (
  'socio',         -- pró-labore e retirada: NÃO é despesa operacional
  'funcionario',   -- folha e encargos
  'diarista',      -- apoio pontual, sem vínculo
  'prestador',     -- pessoa jurídica de serviço
  'comissionado'   -- vende e recebe percentual; raramente tem login
));

-- Percentual usual deste comissionado, para a comissão não ser digitada a cada venda.
ALTER TABLE public.payees
  ADD COLUMN IF NOT EXISTS commission_percentage numeric(5,2);

COMMENT ON COLUMN public.payees.commission_percentage IS
  'Percentual habitual de comissão. Padrão para novas vendas; sempre editável na venda.';

COMMENT ON COLUMN public.payees.kind IS
  'socio = pró-labore (fora do resultado operacional); funcionario = folha; diarista = apoio pontual; prestador = PJ de serviço; comissionado = recebe percentual sobre venda.';

-- Liga a comissão a um favorecido, para quem vende sem ter login também poder receber.
-- `user_id` continua existindo: quem é usuário do sistema segue funcionando como antes.
ALTER TABLE public.commissions
  ADD COLUMN IF NOT EXISTS payee_id uuid REFERENCES public.payees(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.commissions.payee_id IS
  'Comissionado que não é usuário do sistema. Alternativo a user_id — um dos dois, nunca ambos.';
