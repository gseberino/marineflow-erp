/**
 * Trocar o cliente ou a embarcação da OS sem perder nada sem querer (pedido do dono, 21/10/2026:
 * "proteções contra erros do usuário").
 *
 * Regras puras, para provar sem montar o formulário:
 *  · o texto da confirmação diz de quem, para quem e o que SAI da OS — confirmação genérica
 *    ("Tem certeza?") é clicada sem ler;
 *  · escolher de novo a mesma embarcação não é troca (antes apagava o solicitante em silêncio);
 *  · o que veio de sugestão e ninguém mexeu acompanha a troca; o que foi escolhido ou escrito à
 *    mão fica.
 */

export interface Perdas {
  /** Nome da embarcação que sai da OS ("" quando ela não tem nome). */
  embarcacao?: string | null;
  /** Nome do solicitante que sai da OS. */
  solicitante?: string | null;
  /** Nome da marina que sai junto (era a do barco antigo). */
  marina?: string | null;
  /** O local e acesso sai junto (era a sugestão do barco antigo). */
  local?: boolean;
}

export function temPerda(p: Perdas | undefined): boolean {
  return !!p && (p.embarcacao != null || p.solicitante != null || p.marina != null || !!p.local);
}

export function tituloDaTroca(documento: 'OS' | 'orçamento'): string {
  return documento === 'orçamento' ? 'Trocar o cliente deste orçamento?' : 'Trocar o cliente desta OS?';
}

/** "De João para Maria. Saem: a embarcação Netuno II e o solicitante Pedro." Sem nome de
    origem (cliente fora da lista): "Do cliente atual para…". */
export function descricaoDaTroca(de: string | null, para: string | null, p: Perdas): string {
  const itens: string[] = [];
  if (p.embarcacao != null) itens.push(p.embarcacao ? `a embarcação ${p.embarcacao}` : 'a embarcação escolhida');
  if (p.solicitante != null) itens.push(p.solicitante ? `o solicitante ${p.solicitante}` : 'o solicitante escolhido');
  // O nome da marina quase sempre já começa por "Marina": entre parênteses, não "a marina Marina X".
  if (p.marina != null) itens.push(p.marina ? `a marina sugerida (${p.marina})` : 'a marina sugerida');
  if (p.local) itens.push('o local e acesso da embarcação');
  const inicio = `${de ? `De ${de}` : 'Do cliente atual'} para ${para ?? 'um cliente novo'}.`;
  if (!itens.length) return inicio;
  const lista = itens.length === 1 ? itens[0] : `${itens.slice(0, -1).join(', ')} e ${itens[itens.length - 1]}`;
  return `${inicio} ${itens.length === 1 ? 'Sai' : 'Saem'}: ${lista}.`;
}

type Form = Record<string, any>;
type Barco = { marina_id?: string | null; access_notes?: string | null } | null | undefined;

/** O texto do local e acesso ainda é a sugestão do barco (ninguém mexeu)? */
function eSugestaoDe(siteAccess: unknown, barco: Barco): boolean {
  return !!barco?.access_notes && siteAccess === barco.access_notes;
}

/** A marina da OS é a do barco (veio de sugestão)? */
function eMarinaDo(marinaId: unknown, barco: Barco): boolean {
  return !!barco?.marina_id && marinaId === barco.marina_id;
}

/** Cliente novo: embarcação e solicitante saem (são do cliente antigo). A marina e o local que
    vieram de sugestão do barco antigo saem junto — senão, escolhido o barco do cliente novo, a
    marina antiga ficaria (ela já não seria "sugestão" de ninguém). Escolhidos à mão, ficam. */
export function trocarClienteNoForm(f: Form, clienteId: string, barcoAntigo: Barco): Form {
  return {
    ...f,
    client_id: clienteId,
    vessel_id: '',
    requested_by_contact_id: '',
    requested_by_name: '',
    marina_id: eMarinaDo(f.marina_id, barcoAntigo) ? '' : f.marina_id,
    site_access: eSugestaoDe(f.site_access, barcoAntigo) ? '' : f.site_access,
  };
}

/** O que trocarClienteNoForm tira da OS — pelos MESMOS critérios, para a confirmação não
    esconder nada. `nomes` só dá os nomes para o texto. */
export function perdasDaTrocaDeCliente(
  f: Form,
  barcoAntigo: Barco,
  nomes: { embarcacao?: string | null; solicitante?: string | null; marina?: string | null },
): Perdas {
  const temSolicitante = !!(f.requested_by_contact_id || f.requested_by_name);
  return {
    embarcacao: f.vessel_id ? (nomes.embarcacao ?? '') : null,
    solicitante: temSolicitante ? (nomes.solicitante || f.requested_by_name || '') : null,
    marina: eMarinaDo(f.marina_id, barcoAntigo) ? (nomes.marina ?? '') : null,
    local: eSugestaoDe(f.site_access, barcoAntigo),
  };
}

/** Embarcação nova. Devolve o MESMO objeto quando é a mesma embarcação (nada muda). */
export function trocarEmbarcacaoNoForm(f: Form, embarcacaoId: string, antigo: Barco, novo: Barco): Form {
  if (embarcacaoId === f.vessel_id) return f;
  const marinaSugerida = !f.marina_id || eMarinaDo(f.marina_id, antigo);
  const localSugerido = !f.site_access || eSugestaoDe(f.site_access, antigo);
  return {
    ...f,
    vessel_id: embarcacaoId,
    // O contato é da embarcação antiga. O nome só sai se veio dele; digitado à mão, fica.
    requested_by_contact_id: '',
    requested_by_name: f.requested_by_contact_id ? '' : f.requested_by_name,
    // A marina acompanha o barco só se estava vazia ou era a do barco anterior (barco novo sem
    // marina deixa vazio); escolhida à mão, fica.
    marina_id: marinaSugerida ? (novo?.marina_id ?? '') : f.marina_id,
    site_access: localSugerido ? (novo?.access_notes ?? '') : f.site_access,
  };
}
