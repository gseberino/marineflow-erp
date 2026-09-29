// A mensagem de erro do login aparecia vazia ("{}") quando o servidor de login caía
// (incidente de 17/08/2026). Estes testes passam o erro pela biblioteca de verdade — um
// servidor que responde 503 — em vez de fabricar o objeto: o defeito mora justamente no
// jeito como a biblioteca monta a mensagem, e um erro fabricado à mão esconderia isso.
import { describe, it, expect } from 'vitest';
import {
  createClient, AuthApiError, AuthWeakPasswordError, AuthSessionMissingError,
} from '@supabase/supabase-js';
import { mensagemDeErroDeAutenticacao } from './auth-error';

function clienteQueResponde(status: number, corpo = '') {
  return createClient('https://projeto-teste.supabase.co', 'chave-publica-de-teste', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: `teste-${Math.random()}` },
    global: { fetch: async () => new Response(corpo, { status }) },
  });
}

async function erroDoLogin(status: number, corpo = '') {
  const { error } = await clienteQueResponde(status, corpo).auth.signInWithPassword({
    email: 'dono@hbr.com.br', password: 'qualquer',
  });
  return error;
}

describe('mensagem de erro do login', () => {
  it.each([502, 503, 504, 522])('servidor de login fora do ar (%i) não vira "{}"', async (status) => {
    const erro = await erroDoLogin(status);
    // O defeito, como a biblioteca entrega: a mensagem crua é literalmente "{}".
    expect(erro?.message).toBe('{}');
    const texto = mensagemDeErroDeAutenticacao(erro, 'Erro ao fazer login');
    expect(texto).toBe(`O servidor de login não respondeu agora (erro ${status}). Tente de novo em alguns instantes.`);
  });

  it('sem rede nenhuma também explica, sem inventar status', async () => {
    const cliente = createClient('https://projeto-teste.supabase.co', 'chave-publica-de-teste', {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: `teste-${Math.random()}` },
      global: { fetch: async () => { throw new TypeError('Failed to fetch'); } },
    });
    const { error } = await cliente.auth.signInWithPassword({ email: 'dono@hbr.com.br', password: 'x' });
    expect(mensagemDeErroDeAutenticacao(error, 'Erro ao fazer login'))
      .toBe('O servidor de login não respondeu agora. Tente de novo em alguns instantes.');
  });

  it('senha errada continua dizendo que é a senha', async () => {
    const erro = await erroDoLogin(400, JSON.stringify({
      code: 'invalid_credentials', message: 'Invalid login credentials',
    }));
    expect(mensagemDeErroDeAutenticacao(erro, 'x')).toBe('Email ou senha incorretos');
  });

  it('muitas tentativas', async () => {
    const erro = await erroDoLogin(429, JSON.stringify({ code: 'over_request_rate_limit', message: 'Request rate limit reached' }));
    expect(mensagemDeErroDeAutenticacao(erro, 'x')).toBe('Muitas tentativas. Aguarde alguns minutos.');
  });

  it('corpo de erro sem frase nenhuma cai no texto padrão, não em "{}"', async () => {
    const erro = await erroDoLogin(500, '{}');
    expect(mensagemDeErroDeAutenticacao(erro, 'Erro ao fazer login')).toBe('Erro ao fazer login');
    expect(mensagemDeErroDeAutenticacao({}, 'Erro ao fazer login')).toBe('Erro ao fazer login');
    expect(mensagemDeErroDeAutenticacao(null, 'Erro ao fazer login')).toBe('Erro ao fazer login');
  });

  it('mensagem que já é frase passa como veio', () => {
    expect(mensagemDeErroDeAutenticacao(new AuthApiError('Signups not allowed for this instance', 422, 'signup_disabled'), 'x'))
      .toBe('Signups not allowed for this instance');
  });
});

describe('mensagem de erro da troca de senha', () => {
  it('senha vazada (proteção do painel ligada) diz o motivo', () => {
    const erro = new AuthWeakPasswordError('Password is known to be weak', 422, ['pwned']);
    expect(mensagemDeErroDeAutenticacao(erro, 'x')).toBe('Essa senha aparece em vazamentos conhecidos. Escolha outra.');
  });

  it('senha curta ou simples demais', () => {
    const erro = new AuthWeakPasswordError('Password should be at least 6 characters', 422, ['length']);
    expect(mensagemDeErroDeAutenticacao(erro, 'x')).toBe('Senha fraca. Use uma senha mais longa, misturando letras e números.');
  });

  it('link de redefinição vencido', () => {
    expect(mensagemDeErroDeAutenticacao(new AuthSessionMissingError(), 'x'))
      .toBe('O link de redefinição expirou ou já foi usado. Peça um novo em "Esqueci minha senha".');
  });

  it('senha nova igual à antiga', () => {
    const erro = new AuthApiError('New password should be different from the old password.', 422, 'same_password');
    expect(mensagemDeErroDeAutenticacao(erro, 'x')).toBe('A nova senha precisa ser diferente da atual.');
  });
});
