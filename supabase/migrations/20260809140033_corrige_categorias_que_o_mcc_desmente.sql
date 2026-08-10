-- Resgatada de supabase_migrations.schema_migrations em 09/08/2026 — aplicada em
-- produção sem arquivo (NOVO-003). Conteúdo copiado literalmente da coluna
-- `statements` (1 statement), sem qualquer edição do SQL original.
--
-- IDEMPOTÊNCIA / REPLAY EM BANCO LIMPO: segura, com uma ressalva.
--   · A tabela é TEMP com ON COMMIT DROP — não deixa resíduo e não colide em replay
--     (exige rodar dentro de transação, que é como o CLI aplica migrations).
--   · O UPDATE é no-op em banco limpo (não há `payables`) e no-op ao reaplicar sobre
--     dados já corrigidos: a cláusula `expense_category IS DISTINCT FROM m.categoria`
--     somada às três origens permitidas ('Alimentação de campo' → farmácia,
--     'Aluguel e condomínio' → alimentação, 'Outras despesas') deixa de casar depois
--     que a categoria foi trocada.
--   · RESSALVA: não é uma migration de schema, é CORREÇÃO DE DADOS. Reaplicá-la mais
--     tarde num banco vivo voltaria a reclassificar lançamentos novos que estiverem em
--     'Outras despesas' — o efeito é o pretendido pelo autor, mas não é inerte.
--     Depende de `financial_categories` já semeada com os nomes usados aqui.

-- O MCC (código da bandeira) desmente a categoria lançada em três grupos.
--
-- Corrige SÓ o que é erro, não o que é julgamento. Peça × ferramenta são categorias
-- vizinhas e o MCC não sabe mais que o gestor sobre elas — 110 lançamentos ficam como
-- estão de propósito. O que entra aqui é inequívoco:
--
--  · 10 farmácias lançadas como "Alimentação de campo" — efeito da regra FARMA que
--    apontava para alimentação, corrigida ontem; estas foram lançadas antes.
--  · 10 lançadas como "Aluguel e condomínio" com MCC de alimentação (R$ 12,90 de média).
--  ·  38 em "Outras despesas", que é ausência de classificação, e a bandeira sabe qual é.

CREATE TEMP TABLE _mcc(codigo text PRIMARY KEY, categoria text) ON COMMIT DROP;
INSERT INTO _mcc VALUES
 ('5541','Combustível e deslocamento'),('5542','Combustível e deslocamento'),
 ('5983','Combustível e deslocamento'),('4121','Combustível e deslocamento'),
 ('7523','Pedágio e estacionamento'),('4784','Pedágio e estacionamento'),
 ('5251','Ferramentas e equipamentos'),('5200','Ferramentas e equipamentos'),
 ('5211','Ferramentas e equipamentos'),
 ('5722','Peças e materiais'),('5732','Peças e materiais'),('5065','Peças e materiais'),
 ('5013','Peças e materiais'),('5533','Peças e materiais'),('5551','Peças e materiais'),
 ('5571','Peças e materiais'),('5099','Peças e materiais'),('5085','Peças e materiais'),
 ('5812','Alimentação de campo'),('5814','Alimentação de campo'),('5462','Alimentação de campo'),
 ('5411','Alimentação de campo'),('5499','Alimentação de campo'),('5813','Alimentação de campo'),
 ('5817','Software e assinaturas'),('5818','Software e assinaturas'),('7372','Software e assinaturas'),
 ('4816','Software e assinaturas'),('5734','Software e assinaturas'),
 ('4814','Telefonia e internet'),('4899','Telefonia e internet'),
 ('7538','Manutenção de veículo'),('7534','Manutenção de veículo'),('7549','Manutenção de veículo'),
 ('5532','Manutenção de veículo'),
 ('7011','Hospedagem e Hotelaria'),('3000','Hospedagem e Hotelaria'),('4511','Hospedagem e Hotelaria'),
 ('4722','Hospedagem e Hotelaria'),('5912','Assistência médica/farmacêutica'),
 ('8931','Contabilidade e assessoria'),('8111','Contabilidade e assessoria'),
 ('6300','Seguro'),('4215','Frete e importação'),('4214','Frete e importação');

UPDATE public.payables p
   SET expense_category = m.categoria
  FROM public.bank_transactions b, _mcc m, public.financial_categories c
 WHERE b.id = p.bank_transaction_id
   AND m.codigo = b.payee_mcc
   AND c.name = m.categoria AND c.type = 'payable' AND c.active
   AND p.expense_category IS DISTINCT FROM m.categoria
   AND (
     -- Farmácia lançada como alimentação
     (p.expense_category = 'Alimentação de campo' AND m.categoria = 'Assistência médica/farmacêutica')
     -- Alimentação lançada como aluguel
     OR (p.expense_category = 'Aluguel e condomínio' AND m.categoria = 'Alimentação de campo')
     -- Sem classificação nenhuma: a bandeira sabe qual é
     OR p.expense_category = 'Outras despesas'
   );
