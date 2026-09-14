-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-04T02:26:12.294Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260804022617 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- A política de escrita estava anulando a de leitura.
--
-- Políticas de RLS permissivas se combinam com OU: basta UMA permitir para a linha
-- aparecer. A `payables_write` era FOR ALL — e FOR ALL inclui SELECT —, então ela
-- liberava a leitura de tudo e a restrição de pró-labore não valia nada. A tela mostrava
-- o dado protegido e ninguém saberia, porque o teste "olhei e apareceu" passa igual.
--
-- Escrita agora é declarada por comando, sem tocar em SELECT.

DROP POLICY IF EXISTS payables_write ON public.payables;

CREATE POLICY payables_insert ON public.payables
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY payables_update ON public.payables
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY payables_delete ON public.payables
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL);
