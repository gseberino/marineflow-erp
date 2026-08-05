-- ─────────────────────────────────────────────────────────────────────────────
-- Entrada de mercadoria estava BLOQUEADA por uma letra maiúscula.
--
-- Erro relatado pelo dono em 04/08/2026, ao confirmar a importação de uma NF-e:
--   'Categoria "Compras de Mercadorias" não existe no plano de contas.'
--
-- Ela existe — como "Compras de mercadorias", com m minúsculo. O plano de contas
-- foi refeito em 29/07 (commit 826eaaa, 33 categorias novas) e a capitalização
-- mudou; `confirm_nfe_import`, escrita antes, continuou gravando o literal
-- 'Compras de Mercadorias'. A validação compara com `=`, que diferencia caixa, e
-- por isso a importação inteira parava — estoque, conta a pagar, tudo.
--
-- A correção não é mexer em `confirm_nfe_import` (7.387 caracteres, mexe em estoque
-- e financeiro) nem afrouxar a validação, que é boa e existe por um motivo real:
-- despesa em categoria inexistente some do resultado. O trigger é BEFORE, então
-- pode CORRIGIR o valor em vez de só recusá-lo — se a categoria existe ignorando a
-- caixa, ele normaliza para o nome canônico e deixa passar.
--
-- Normalizar (em vez de aceitar como veio) importa: relatórios agrupam despesa por
-- texto, e "Compras de Mercadorias" convivendo com "Compras de mercadorias"
-- apareceria como duas linhas diferentes no DRE.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.valida_categoria_de_despesa()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_canonico text;
begin
  if new.expense_category is null or new.expense_category = '' then
    return new;
  end if;

  -- Nome exato: caminho normal, sai cedo.
  if exists (
    select 1 from public.financial_categories
    where name = new.expense_category and type = 'payable' and active
  ) then
    return new;
  end if;

  -- Só a caixa difere? Normaliza para o nome cadastrado e segue.
  select name into v_canonico
  from public.financial_categories
  where lower(name) = lower(new.expense_category) and type = 'payable' and active
  limit 1;

  if v_canonico is not null then
    new.expense_category := v_canonico;
    return new;
  end if;

  raise exception
    'Categoria "%" não existe no plano de contas. Crie-a antes de usar, senão o valor some do resultado.',
    new.expense_category
    using errcode = 'check_violation';
end;
$$;

comment on function public.valida_categoria_de_despesa() is
  'Exige que expense_category exista no plano de contas, mas normaliza diferenca de MAIUSCULA/minuscula para o nome canonico — uma letra de diferenca chegou a bloquear a entrada de mercadoria inteira em 04/08/2026.';
