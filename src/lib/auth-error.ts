import {
  isAuthApiError, isAuthRetryableFetchError, isAuthSessionMissingError, isAuthWeakPasswordError,
} from '@supabase/supabase-js';

/**
 * Mensagem legível para um erro de login ou de troca de senha.
 *
 * No incidente de 17/08/2026 o banco ficou sobrecarregado, o servidor de login respondeu 503
 * e a tela mostrou só "{}". A causa está na biblioteca de login do Supabase (auth-js): nos
 * status 502, 503, 504, 520–524 e 530 ela monta a mensagem com `JSON.stringify` do próprio
 * objeto Response — que vira "{}" —, e a tela repassava `err.message` como veio.
 *
 * Por isso a pergunta aqui é pelo TIPO do erro (e pelo código que o servidor manda), não pelo
 * texto, e o que é texto de máquina ("{}") nunca chega à tela.
 */
export function mensagemDeErroDeAutenticacao(err: unknown, padrao: string): string {
  // Sem resposta do servidor de login (rede, 5xx, Cloudflare): nada a ver com a senha digitada.
  if (isAuthRetryableFetchError(err)) {
    const status = err.status ? ` (erro ${err.status})` : '';
    return `O servidor de login não respondeu agora${status}. Tente de novo em alguns instantes.`;
  }
  if (isAuthSessionMissingError(err)) {
    return 'O link de redefinição expirou ou já foi usado. Peça um novo em "Esqueci minha senha".';
  }
  if (isAuthWeakPasswordError(err)) {
    // 'pwned' só aparece com a proteção contra senha vazada ligada no painel do Supabase.
    return err.reasons.includes('pwned')
      ? 'Essa senha aparece em vazamentos conhecidos. Escolha outra.'
      : 'Senha fraca. Use uma senha mais longa, misturando letras e números.';
  }

  const e = (err ?? {}) as { message?: unknown; code?: unknown; status?: unknown };
  const mensagem = typeof e.message === 'string' ? e.message : '';
  const codigo = isAuthApiError(err) ? err.code : typeof e.code === 'string' ? e.code : undefined;

  if (codigo === 'invalid_credentials' || mensagem.includes('Invalid login credentials')) {
    return 'Email ou senha incorretos';
  }
  if (codigo === 'email_not_confirmed' || mensagem.includes('Email not confirmed')) {
    return 'Confirme seu email antes de entrar';
  }
  if (codigo === 'over_request_rate_limit' || e.status === 429 || /too many requests|rate limit/i.test(mensagem)) {
    return 'Muitas tentativas. Aguarde alguns minutos.';
  }
  if (codigo === 'same_password') {
    return 'A nova senha precisa ser diferente da atual.';
  }

  // O que sobrar só aparece se for frase: "{}", "[object Object]" e vazio viram o padrão.
  return /^\s*$|^\s*[{[]|\[object /.test(mensagem) ? padrao : mensagem;
}
