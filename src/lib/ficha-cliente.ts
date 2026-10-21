import type { Client } from '@/hooks/use-clients';
import { normalizePhoneE164 } from '@/lib/masks';

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

export interface ResumoEmAberto {
  /** Soma do saldo dos títulos não pagos e não cancelados. */
  emAberto: number;
  vencidos: number;
  valorVencido: number;
}

type TituloAberto = {
  amount: number | null;
  paid_amount: number | null;
  balance_amount: number | null;
  due_date: string | null;
  status: string | null;
};

function hojeLocal(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/**
 * O que o cliente deve. Saldo = balance_amount (o banco mantém), com amount − paid_amount de
 * reserva. Vencido = a data passou: os "vence na conclusão" de OS ainda abertas têm data futura,
 * e o gatilho do banco troca pela data real ao concluir — então a data basta.
 */
export function resumirEmAberto(titulos: TituloAberto[], hoje: string = hojeLocal()): ResumoEmAberto {
  const r: ResumoEmAberto = { emAberto: 0, vencidos: 0, valorVencido: 0 };
  for (const t of titulos) {
    if (t.status === 'paid' || t.status === 'cancelled') continue;
    const saldo = t.balance_amount ?? (Number(t.amount ?? 0) - Number(t.paid_amount ?? 0));
    if (!(Number(saldo) > 0.009)) continue;
    r.emAberto += Number(saldo);
    if (t.due_date && t.due_date.slice(0, 10) < hoje) {
      r.vencidos += 1;
      r.valorVencido += Number(saldo);
    }
  }
  return r;
}

/** tel: com DDI só quando o número está completo; número curto (sem DDD) vai como está. */
export function hrefTelefone(fone: string): string {
  const e164 = normalizePhoneE164(fone);
  return e164.length >= 12 ? `tel:+${e164}` : `tel:${e164}`;
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
