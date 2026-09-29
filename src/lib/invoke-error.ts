/**
 * Extrai a mensagem REAL de erro de uma chamada a `supabase.functions.invoke`.
 *
 * Sem isto, o cliente do Supabase devolve apenas "Edge Function returned a
 * non-2xx status code" e a mensagem que a função escreveu (ex.: "Arquivo não é
 * uma NF-e válida") se perde — inclusive no registro de erros, deixando o
 * problema indiagnosticável tanto para quem usa quanto para quem dá suporte.
 * A mensagem verdadeira vem no corpo da resposta, acessível em `error.context`.
 *
 * Estava duplicado dentro da tela de emissão fiscal; virou lib para as demais
 * telas não repetirem o mesmo erro de engolir o motivo.
 */
export async function extractInvokeErrorMessage(error: unknown): Promise<string> {
  const parsed = await extractInvokeErrorBody(error);
  if (parsed?.error) return String(parsed.error);
  return error instanceof Error ? error.message : String(error);
}

/**
 * O corpo JSON que a função devolveu junto com o erro, para quem precisa de mais que a
 * mensagem (ex.: o `em_andamento` do whatsapp-send). `null` se não houver corpo JSON.
 */
export async function extractInvokeErrorBody(error: unknown): Promise<Record<string, unknown> | null> {
  if (error && typeof error === 'object' && 'context' in error) {
    const ctx = (error as { context?: unknown }).context;
    if (ctx && typeof (ctx as Response).json === 'function') {
      try {
        const parsed = await (ctx as Response).clone().json();
        return parsed && typeof parsed === 'object' ? parsed as Record<string, unknown> : null;
      } catch {
        // corpo não era JSON
      }
    }
  }
  return null;
}
