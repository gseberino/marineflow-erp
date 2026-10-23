// A mesma regra do servidor, na tela: qual vínculo vale para uma linha do Extrato e quando
// a linha não pode ser aprovada sem alguém escolher.
//
// A política mora em supabase/functions/_shared/banking/vinculo.ts (vinculoAutomatico,
// exigeDecisao) e destino.ts ("para onde foi" do serviço de terceiro) e é importada daqui — a
// tela e o servidor não podem discordar sobre o que acontece quando se clica em aprovar.
import {
  exigeDecisao, osAnotada, podeJaEstarLancado, vinculoAutomatico, type OpcaoDeVinculo, type VinculoSugerido,
} from '../../supabase/functions/_shared/banking/vinculo';
import { faltaNoDestino, type FaltaNoDestino } from '../../supabase/functions/_shared/banking/destino';
import {
  situacaoDoClienteSugerido, type AnotacaoDoDono, type ClienteDaEvidencia, type SituacaoDoClienteSugerido,
} from '../../supabase/functions/_shared/banking/contraparte';

export type EscolhaDeVinculo = { id: string } | 'nenhum' | undefined;

/** O que uma linha da fila precisa para dizer de quem é a entrada. */
interface LinhaComCliente {
  suggested_client_id?: string | null;
  evidencia?: { cliente?: ClienteDaEvidencia | null; anotacao?: AnotacaoDoDono | null } | null;
}

/**
 * Como fica o cliente SUGERIDO desta linha na aprovação — a MESMA conta do servidor (situacaoDoClienteSugerido, a fonte
 * única de clienteQueAprovacaoUsa e pedidoDeConfirmacaoDoCliente; revisão de 23/10/2026, 4ª rodada):
 *   - "vale": a aprovação usa o sugerido sem perguntar (prova do motor deste cliente que não pede o SIM, ou anotação do
 *     dono que o disse — "o Pix de 1.500 é da TSD" vence a prova antiga de outro cliente);
 *   - "pede_sim": a prova do motor é deste cliente e pede o SIM (pagador conhecido, histórico de terceiro, vínculo) —
 *     "Sim, é do X";
 *   - "escolher": o sugerido NÃO é o da prova (prova de outro cliente, ou nenhuma) e nenhuma anotação em vigor o disse
 *     (desfeita: a marca sai da evidência e o sugerido fica) — ninguém resolveu de quem é: "De qual cliente veio?" em
 *     branco, sem "Sim, é do <prova>" e fora do lote;
 *   - "sem_sugestao".
 * A tela não lê a anotação: vale a marca que a evidência guarda (evidencia.anotacao = {id, os_id}) — o mesmo que o
 * servidor usa quando não a lê. O cliente anotado IGUAL ao da prova, sem OS, continua pedindo o "sim" aqui, enquanto o
 * servidor (que lê a anotação) o dispensa: a tela erra para o lado da pergunta.
 */
export function situacaoDoSugerido(p: LinhaComCliente): SituacaoDoClienteSugerido {
  return situacaoDoClienteSugerido(p.suggested_client_id, p.evidencia?.cliente, p.evidencia?.anotacao ?? null);
}

/** O sugerido desta linha pede o SIM ("Sim, é do X" sobre o cliente da prova)? Só na situação "pede_sim". */
export function sugeridoPedeSim(p: LinhaComCliente): boolean {
  return situacaoDoSugerido(p) === 'pede_sim';
}

/**
 * O cliente que a linha mostra como escolhido — e o MESMO que a aprovação vai usar (finance-review/aprovar,
 * clienteQueAprovacaoUsa): a escolha da pessoa; sem escolha, o sugerido só na situação "vale". Quando ele pede o SIM
 * (leva 8, 22/10/2026) ou falta escolher (4ª rodada), fica em branco até alguém responder "Sim, é do X" ou escolher
 * um cliente: a tela não pode mostrar um cliente que o servidor não vai usar.
 */
export function clienteEscolhido(p: LinhaComCliente, correcao?: { clientId?: string | null } | null): string | null {
  return correcao?.clientId ?? (situacaoDoSugerido(p) === 'vale' ? p.suggested_client_id ?? null : null);
}

/** Há um cliente sugerido que pede o SIM e ninguém respondeu nem escolheu outro. */
export function clientePedeSim(p: LinhaComCliente, correcao?: { clientId?: string | null } | null): boolean {
  return !correcao?.clientId && sugeridoPedeSim(p);
}

/**
 * Há um cliente sugerido que ninguém disse ser o da linha (situação "escolher") e a pessoa ainda não escolheu: o
 * servidor recusaria com "Escolha o cliente…" (PEDIDO_DE_ESCOLHA_DO_CLIENTE). Nenhum cliente é oferecido — nem o
 * sugerido, nem o da prova antiga.
 */
export function clienteFaltaEscolher(p: LinhaComCliente, correcao?: { clientId?: string | null } | null): boolean {
  return !correcao?.clientId && situacaoDoSugerido(p) === 'escolher';
}

/**
 * O cliente com que o "Parece pagar" é calculado: a escolha da pessoa ou o sugerido que vale ou pede o SIM (o
 * "Este Pix paga…" com o cliente à vista é o SIM) — nunca o sugerido da situação "escolher", que ninguém disse ser o
 * da linha (revisão de 23/10/2026). Mesma regra do assistente (listar_propostas_de_lancamento).
 */
export function clienteDoParecePagar(p: LinhaComCliente, correcao?: { clientId?: string | null } | null): string | null {
  return correcao?.clientId ?? (situacaoDoSugerido(p) === 'escolher' ? null : p.suggested_client_id ?? null);
}

/** Todas as opções de uma sugestão, a principal primeiro. */
export function opcoesDoVinculo(v: VinculoSugerido | null | undefined): OpcaoDeVinculo[] {
  return v ? [v.principal, ...(v.alternativas ?? [])] : [];
}

/**
 * O que a aprovação vai usar: a escolha da pessoa; sem escolha, o vínculo automático.
 * `null` = lança novo.
 */
export function vinculoEfetivo(v: VinculoSugerido | null | undefined, escolha: EscolhaDeVinculo): OpcaoDeVinculo | null {
  if (escolha === 'nenhum') return null;
  if (escolha && typeof escolha === 'object') return opcoesDoVinculo(v).find((o) => o.id === escolha.id) ?? null;
  return vinculoAutomatico(v);
}

/**
 * Há vínculo sugerido e ninguém respondeu: não aprova no escuro (decisão do dono, 26/09/2026 —
 * toda sugestão de vínculo é pergunta).
 */
export function precisaDecidir(v: VinculoSugerido | null | undefined, escolha: EscolhaDeVinculo): boolean {
  if (escolha) return false;
  return exigeDecisao(v);
}

export { podeJaEstarLancado };

export {
  osVemDoVinculo, osAnotada, temPerguntaDaOS, temPerguntaDaOC, perguntaDaOSAberta, type LinhaComPerguntas,
} from '../../supabase/functions/_shared/banking/vinculo';

export {
  SERVICO_DE_CLIENTE, SERVICO_DA_EMPRESA, CATEGORIAS_COM_DESTINO, precisaDeDestino, destinoEfetivo,
  categoriaDoDestino, fraseDaFalta, type FaltaNoDestino, type Destino,
} from '../../supabase/functions/_shared/banking/destino';
export { faltaNoDestino };

/** O que uma linha da fila precisa para a pergunta "Para onde foi?". */
interface LinhaParaODestino {
  kind: string;
  suggested_category: string | null;
  suggested_service_order_id?: string | null;
  evidencia?: { anotacao?: { id?: string; os_id?: string | null } | null } | null;
}

/** O que a tela respondeu na linha (os campos da correção que importam aqui). */
interface RespostaDaLinha {
  category?: string;
  serviceOrderId?: string | null;
  costCenterId?: string | null;
  notes?: string | null;
  destino?: 'cliente' | 'empresa' | null;
  vinculo?: { id: string } | 'nenhum';
}

/**
 * O que falta para aprovar uma linha de serviço de terceiro — a MESMA conta que o servidor faz
 * em finance-review/aprovar: a categoria escolhida na tela, a OS anotada pelo WhatsApp quando
 * ninguém respondeu outra, e nada quando a linha vai CASAR com um lançamento que já existe
 * (ele já tem a categoria dele).
 */
export function faltaNoDestinoDaLinha(p: LinhaParaODestino, r: RespostaDaLinha | undefined): FaltaNoDestino[] {
  if (r?.vinculo && typeof r.vinculo === 'object') return [];
  const categoria = r?.category ?? p.suggested_category ?? '';
  const osJaDita = r?.serviceOrderId === undefined ? osAnotada(p) : null;
  return faltaNoDestino(p.kind, categoria, r, osJaDita);
}
