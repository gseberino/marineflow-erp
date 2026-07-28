-- Fixa o search_path das três funções SECURITY DEFINER que ainda não o declaravam.
--
-- Função com privilégio elevado e search_path livre resolve nomes não qualificados usando
-- o caminho de quem chama. Quem consegue criar um objeto num schema que venha antes na
-- busca passa a ter o próprio código executado com os privilégios do dono da função —
-- é o "search_path hijacking", e o Supabase sinaliza isso como risco de segurança.
--
-- Seguro de aplicar: ALTER FUNCTION ... SET search_path não altera o corpo, só fixa o
-- ambiente de resolução de nomes. As três referenciam apenas tabelas de `public` e não
-- usam funções de extensão (verificado antes da alteração), então o comportamento
-- observável não muda. Mesmo padrão já adotado pelas demais funções do projeto.

ALTER FUNCTION public.cancel_service_order_cascade SET search_path TO 'public';
ALTER FUNCTION public.handle_quote_deposit_payment SET search_path TO 'public';
ALTER FUNCTION public.receive_po SET search_path TO 'public';
