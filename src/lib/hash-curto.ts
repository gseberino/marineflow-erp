/**
 * Hash curto e determinístico (djb2 em base 36). Serve para montar chaves de idempotência
 * no cliente (ex.: envio de WhatsApp pelo painel); não é criptográfico.
 * Espelha `supabase/functions/_shared/whatsapp/idempotencia.ts`.
 */
export function hashCurto(texto: string): string {
  let h = 5381;
  for (let i = 0; i < texto.length; i++) {
    h = ((h << 5) + h + texto.charCodeAt(i)) | 0;
  }
  return (h >>> 0).toString(36);
}

/**
 * Chave de idempotência para um envio disparado por uma pessoa no painel: mesmo telefone,
 * mesmo conteúdo, mesma janela de 10 minutos = mesmo envio. Protege contra clique duplo e
 * contra a repetição automática quando a resposta se perdeu no caminho; não impede reenviar
 * de propósito mais tarde.
 */
export function chaveDeEnvioDoPainel(phone: string, conteudo: string, agora: number = Date.now()): string {
  const janela = Math.floor(agora / (10 * 60 * 1000));
  return `painel:${phone}:${hashCurto(conteudo)}:${janela}`;
}
