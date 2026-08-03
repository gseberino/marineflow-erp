-- Faltava "Comissões" no plano de contas.
--
-- Percebido pelo usuário ao conciliar à mão: ele acabou de cadastrar comissionados e não
-- tinha em que categoria lançar o que paga a eles. A lacuna passou despercebida porque a
-- lista nasceu do extrato do último ano, e comissão ainda não tinha sido paga por lá.
--
-- despesa_operacional: comissão é custo de vender, entra no resultado.
INSERT INTO public.financial_categories (name, type, dre_group, sort_order, color, active, description)
VALUES ('Comissões', 'payable', 'despesa_operacional', 215, '#8b5cf6', true,
        'Percentual pago a vendedores e representantes sobre vendas realizadas')
ON CONFLICT (name, type) DO UPDATE
  SET active = true, dre_group = EXCLUDED.dre_group, description = EXCLUDED.description;
