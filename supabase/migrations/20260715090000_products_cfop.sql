-- Adiciona CFOP (Código Fiscal de Operações e Prestações) por produto — usado ao
-- montar o item da NF-e. '5102' = venda de mercadoria adquirida/recebida de
-- terceiros (operação interna mais comum para revenda). Editável por produto e
-- também no momento da emissão.
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS cfop text DEFAULT '5102';
