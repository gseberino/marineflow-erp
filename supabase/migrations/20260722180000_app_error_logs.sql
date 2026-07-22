-- ─────────────────────────────────────────────────────────────────────────────
-- Registro de erros da aplicação.
--
-- MOTIVO: hoje os erros só existem no navegador do usuário (232 toast.error) ou
-- nos logs do Supabase (44 console.error), que nem sempre estão acessíveis. Pior:
-- as três piores falhas recentes foram SILENCIOSAS — edge nunca deployada, RPC
-- referenciando colunas inexistentes, e auditoria gravando em tabela errada sem
-- checar o retorno. Nenhuma delas apareceu para ninguém no primeiro uso.
--
-- Com esta tabela, basta dizer "deu erro ao importar" que o diagnóstico sai de
-- uma consulta SQL, com contexto e pilha.
--
-- Agrupa por FINGERPRINT (fonte+contexto+mensagem normalizada) com contador, para
-- 500 repetições do mesmo erro não viram 500 linhas de ruído.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.app_error_logs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fingerprint   text        NOT NULL,
  source        text        NOT NULL CHECK (source IN ('frontend', 'edge', 'db')),
  level         text        NOT NULL DEFAULT 'error' CHECK (level IN ('error', 'warn')),
  context       text,                    -- rota do app ou nome da edge function
  action        text,                    -- o que o usuário estava fazendo
  message       text        NOT NULL,
  details       jsonb,                   -- pilha, status HTTP, payload já mascarado
  user_id       uuid,
  user_email    text,
  user_agent    text,
  occurrences   int         NOT NULL DEFAULT 1,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  resolved_at   timestamptz
);

-- Um erro "aberto" por fingerprint; ao resolver, um novo episódio pode abrir
-- outra linha (permitindo comparar antes/depois de uma correção).
CREATE UNIQUE INDEX IF NOT EXISTS uq_app_error_logs_open
  ON public.app_error_logs (fingerprint) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_app_error_logs_recent
  ON public.app_error_logs (last_seen_at DESC);

ALTER TABLE public.app_error_logs ENABLE ROW LEVEL SECURITY;

-- Leitura só para admin: mensagens de erro podem conter fragmentos de dados de
-- negócio. A escrita NÃO passa por policy — é feita pela RPC SECURITY DEFINER.
DROP POLICY IF EXISTS app_error_logs_admin_select ON public.app_error_logs;
CREATE POLICY app_error_logs_admin_select ON public.app_error_logs
  FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS app_error_logs_admin_update ON public.app_error_logs;
CREATE POLICY app_error_logs_admin_update ON public.app_error_logs
  FOR UPDATE TO authenticated USING (public.is_admin(auth.uid()));

-- ── Registro (usado pelo front e pelas edge functions) ───────────────────────
-- SECURITY DEFINER para gravar sem abrir a tabela: o chamador só consegue
-- inserir no formato desta função.
CREATE OR REPLACE FUNCTION public.log_app_error(
  p_source  text,
  p_message text,
  p_context text  DEFAULT NULL,
  p_action  text  DEFAULT NULL,
  p_level   text  DEFAULT 'error',
  p_details jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_fp    text;
  v_id    uuid;
  v_msg   text;
  v_email text;
BEGIN
  IF coalesce(btrim(p_message), '') = '' THEN
    RETURN NULL;  -- nada a registrar; nunca falhar o fluxo do usuário por causa do log
  END IF;

  -- Mensagem limitada: pilhas gigantes vão em details, não no agrupamento.
  v_msg := left(btrim(p_message), 2000);

  -- Impressão digital sem os números variáveis (ids, horários), senão cada
  -- ocorrência do MESMO erro viraria um grupo novo.
  v_fp := md5(
    coalesce(p_source, '') || '|' || coalesce(p_context, '') || '|' ||
    regexp_replace(lower(left(v_msg, 500)), '[0-9a-f]{8}-[0-9a-f-]{27}|\d+', '#', 'g')
  );

  SELECT email INTO v_email FROM app_users WHERE id = auth.uid();

  INSERT INTO app_error_logs (
    fingerprint, source, level, context, action, message, details, user_id, user_email
  ) VALUES (
    v_fp, p_source,
    CASE WHEN p_level IN ('error', 'warn') THEN p_level ELSE 'error' END,
    left(p_context, 200), left(p_action, 200), v_msg, p_details, auth.uid(), v_email
  )
  ON CONFLICT (fingerprint) WHERE resolved_at IS NULL DO UPDATE
    SET occurrences  = app_error_logs.occurrences + 1,
        last_seen_at = now(),
        message      = EXCLUDED.message,
        details      = coalesce(EXCLUDED.details, app_error_logs.details),
        action       = coalesce(EXCLUDED.action, app_error_logs.action),
        user_id      = coalesce(EXCLUDED.user_id, app_error_logs.user_id),
        user_email   = coalesce(EXCLUDED.user_email, app_error_logs.user_email)
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION WHEN others THEN
  -- Um log que quebra a operação seria pior que não ter log.
  RETURN NULL;
END;
$$;

-- ── Expurgo (retenção) ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prune_app_error_logs(p_days int DEFAULT 90)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n int;
BEGIN
  DELETE FROM app_error_logs WHERE last_seen_at < now() - (p_days || ' days')::interval;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.log_app_error(text, text, text, text, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.prune_app_error_logs(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_app_error(text, text, text, text, text, jsonb) TO authenticated;

COMMENT ON TABLE public.app_error_logs IS
  'Erros da aplicação (front e edge), agrupados por fingerprint. Leitura só admin; escrita via log_app_error().';
