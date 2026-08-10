-- MF-AUD-023 — a proteção de categoria sensível era contornável por UPDATE.
--
-- A migration 20260803020000 escondeu do não-admin os lançamentos de categoria sensível
-- (pró-labore, folha) no SELECT, e teve o cuidado de declarar a escrita POR COMANDO para
-- que nenhuma política FOR ALL anulasse a leitura. Ficou correta no que se propôs.
--
-- O que passou: UPDATE e DELETE herdaram `USING (auth.uid() IS NOT NULL)`. Como o USING
-- do UPDATE define quais LINHAS o usuário alcança, um não-admin alcançava a linha
-- sensível — que ele não pode ler — e podia trocar `expense_category` para uma categoria
-- comum. Feito isso, o SELECT passava a devolvê-la. A proteção dependia de o usuário não
-- pensar nisso.
--
-- Correção: o mesmo predicado do SELECT no USING de UPDATE e DELETE. Quem não é admin
-- não alcança a linha sensível para nenhum comando — nem para ler, nem para alterar, nem
-- para apagar.
--
-- O WITH CHECK do UPDATE recebe o mesmo predicado para fechar o outro sentido: um
-- não-admin não pode transformar um lançamento comum em sensível e assim tirá-lo da
-- própria vista (e da vista dos colegas de mesmo cargo) sem que ninguém perceba.
--
-- O INSERT fica como está, de propósito. Criar um lançamento de categoria sensível não
-- expõe dado de terceiro — no máximo o autor deixa de enxergar o que acabou de criar.
-- Restringir ali quebraria o lançamento de folha por quem não é admin, que é fluxo
-- legítimo e não foi objeto de decisão do dono.
--
-- Reversível: voltar as duas políticas para `USING (auth.uid() IS NOT NULL)`.

ALTER POLICY payables_update ON public.payables
  USING (
    auth.uid() IS NOT NULL
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  )
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  );

ALTER POLICY payables_delete ON public.payables
  USING (
    auth.uid() IS NOT NULL
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  );
