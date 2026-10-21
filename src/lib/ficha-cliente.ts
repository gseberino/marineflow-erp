import type { Client } from '@/hooks/use-clients';

type ClienteFiscal = Pick<
  Client,
  'cpf_cnpj' | 'address_line_1' | 'neighborhood' | 'city' | 'state' | 'postal_code' | 'ie_indicator' | 'state_registration'
>;

const soDigitos = (s: string | null | undefined) => (s ?? '').replace(/\D/g, '');

/**
 * O que falta no cadastro para a nota sair. Espelha os validadores do SERVIDOR — tomador da
 * NFS-e (_shared/fiscal/nfse-payload-builder.ts) e destinatário da NF-e (payload-builder.ts),
 * que leem as colunas do cliente direto (fiscal-emit). Mostrar isso na OS, antes de faturar,
 * evita descobrir o buraco no 422 da emissão, longe da causa.
 */
export function faltasParaNota(c: ClienteFiscal): string[] {
  const doc = soDigitos(c.cpf_cnpj);
  const faltas: string[] = [];
  if (!doc) faltas.push('CPF/CNPJ');
  else if (doc.length !== 11 && doc.length !== 14) faltas.push('CPF/CNPJ incompleto');
  // Só a NF-e (peças) exige; a NFS-e não tem IE.
  if (c.ie_indicator === 1 && !soDigitos(c.state_registration)) faltas.push('inscrição estadual');
  if (!c.address_line_1?.trim()) faltas.push('rua');
  if (!c.neighborhood?.trim()) faltas.push('bairro');
  if (!c.city?.trim()) faltas.push('cidade');
  if (!c.state?.trim()) faltas.push('UF');
  const cep = soDigitos(c.postal_code);
  if (!cep) faltas.push('CEP');
  else if (cep.length !== 8) faltas.push('CEP incompleto');
  return faltas;
}

/** "Rua X, 123 — Centro, Itajaí/SC". Null quando não há nada de endereço. */
export function enderecoEmUmaLinha(
  c: Pick<Client, 'address_line_1' | 'neighborhood' | 'city' | 'state'>,
): string | null {
  const cidade = [c.city, c.state].filter(Boolean).join('/');
  const local = [c.neighborhood, cidade].filter(Boolean).join(', ');
  const linha = [c.address_line_1, local].filter(Boolean).join(' — ');
  return linha || null;
}
