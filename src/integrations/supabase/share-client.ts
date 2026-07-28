import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

/**
 * Cliente da tela pública (o link de orçamento/OS que o cliente abre).
 *
 * Manda o token do link como CABEÇALHO `x-share-token`, para que a RLS consiga
 * compará-lo. O `.eq('share_token', ...)` na query é conveniência de leitura, não
 * controle de acesso: quem chama a API direto simplesmente omite o filtro. É por
 * isso que o token precisa chegar até a política.
 *
 * Sem sessão: o visitante não é um usuário, então nada de localStorage nem de
 * refresh de token.
 */
export function createShareClient(shareToken: string) {
  return createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { 'x-share-token': shareToken } },
  });
}
