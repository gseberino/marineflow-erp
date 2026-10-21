import type { Client } from '@/hooks/use-clients';

type ClienteBuscavel = Pick<Client, 'name' | 'cpf_cnpj' | 'email' | 'phone' | 'whatsapp' | 'active'>;

/** Sem acento e em minúsculas: "joao" acha "João". */
function normalizar(s: string | null | undefined): string {
  return (s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

const soDigitos = (s: string | null | undefined) => (s ?? '').replace(/\D/g, '');

/**
 * O filtro dos seletores de cliente. Até 3 caracteres devolve a lista (cap 200), como sempre
 * foi; depois procura em nome, CPF/CNPJ, e-mail, telefone e WhatsApp, sem ligar para acento.
 *
 * Termo só de números (3+ dígitos) também procura pelos DÍGITOS do documento e dos telefones:
 * "47999991234" acha "(47) 99999-1234" e o CPF acha com ou sem pontuação. Com letra no meio
 * ("Marina 300") não — senão o "300" puxaria todo telefone que tem 300.
 */
export function filtrarClientes<C extends ClienteBuscavel>(
  clientes: C[] | undefined,
  termo: string,
  limite = 200,
): C[] {
  if (!clientes) return [];
  const ativos = clientes.filter((c) => c.active);
  const t = normalizar(termo.trim());
  if (t.length < 3) return ativos.slice(0, limite);

  const digitos = soDigitos(t);
  const porDigitos = digitos.length >= 3 && !/\p{L}/u.test(t);

  return ativos.filter((c) => {
    const texto = normalizar([c.name, c.cpf_cnpj, c.email, c.phone, c.whatsapp].filter(Boolean).join(' '));
    if (texto.includes(t)) return true;
    if (!porDigitos) return false;
    return [c.cpf_cnpj, c.phone, c.whatsapp].some((v) => soDigitos(v).includes(digitos));
  }).slice(0, limite);
}
