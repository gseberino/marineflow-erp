// "Para onde foi?" — o serviço de terceiro que a HBR pagou.
//
// Decisão do dono (26/09/2026): numa despesa de serviço de terceiro "tem que ter qual serviço
// e para que foi direcionado". O serviço contratado pode ter sido para o trabalho de um
// CLIENTE — no barco, no motorhome, num equipamento ou peça dele — e aí é custo daquele
// serviço, ligado à OS; ou para a PRÓPRIA HBR — pintura ou obra na sede, veículo, equipamento
// da empresa — e aí é despesa da empresa, com centro de custo, e não custo de serviço vendido
// (resposta do dono "pode seguir" à recomendação de 26/09/2026). Nos dois casos, o que foi
// feito vai escrito.
//
// A tela, o servidor (finance-review/aprovar e o "lançar sozinho") e o assistente usam estas
// mesmas funções: o que a tela deixa aprovar é exatamente o que o servidor aceita.

/** Serviço de terceiro feito para o serviço de um cliente: custo do serviço (custo_direto). */
export const SERVICO_DE_CLIENTE = "Serviços de terceiros";
/** Serviço de terceiro contratado para a própria HBR: despesa da empresa (despesa_operacional). */
export const SERVICO_DA_EMPRESA = "Serviços de terceiros para a empresa";

/** Categorias em que a pergunta "Para onde foi?" é obrigatória para aprovar. */
export const CATEGORIAS_COM_DESTINO: readonly string[] = [SERVICO_DE_CLIENTE, SERVICO_DA_EMPRESA];

export type Destino = "cliente" | "empresa";

/** O que foi respondido na linha (mesmos nomes da correção da tela e do servidor). */
export interface RespostaDoDestino {
  destino?: Destino | null;
  /** undefined = ninguém respondeu; null = "sem OS no sistema"; texto = a OS. */
  serviceOrderId?: string | null;
  costCenterId?: string | null;
  /** O que foi feito — vira a observação do lançamento. */
  notes?: string | null;
}

export type FaltaNoDestino = "destino" | "os" | "centro" | "o_que_foi_feito";

/** Menos que isto não diz o que foi feito ("ok", "."). */
export const MINIMO_DO_QUE_FOI_FEITO = 3;

/** A saída desta categoria precisa dizer para onde foi. */
export function precisaDeDestino(kind: string | null | undefined, categoria: string | null | undefined): boolean {
  return kind === "create_payable" && !!categoria && CATEGORIAS_COM_DESTINO.includes(categoria);
}

/**
 * O destino que vale: o que a pessoa disse; senão, o que a própria categoria já diz ("para a
 * empresa"); senão, uma OS já respondida (na tela ou na anotação) diz que foi para um cliente.
 */
export function destinoEfetivo(
  categoria: string | null | undefined,
  r: RespostaDoDestino | null | undefined,
  osJaDita?: string | null,
): Destino | null {
  if (r?.destino === "cliente" || r?.destino === "empresa") return r.destino;
  if (categoria === SERVICO_DA_EMPRESA) return "empresa";
  if (typeof r?.serviceOrderId === "string" || !!osJaDita) return "cliente";
  return null;
}

/** A categoria que vai para o lançamento depois da resposta. */
export function categoriaDoDestino(categoria: string, destino: Destino | null | undefined): string {
  if (destino === "empresa" && categoria === SERVICO_DE_CLIENTE) return SERVICO_DA_EMPRESA;
  if (destino === "cliente" && categoria === SERVICO_DA_EMPRESA) return SERVICO_DE_CLIENTE;
  return categoria;
}

/** O que ainda falta para aprovar. Vazio = pode aprovar (ou a categoria não pergunta). */
export function faltaNoDestino(
  kind: string | null | undefined,
  categoria: string | null | undefined,
  r: RespostaDoDestino | null | undefined,
  osJaDita?: string | null,
): FaltaNoDestino[] {
  if (!precisaDeDestino(kind, categoria)) return [];
  const destino = destinoEfetivo(categoria, r, osJaDita);
  const falta: FaltaNoDestino[] = [];
  if (!destino) falta.push("destino");
  // "Sem OS no sistema" (null) é resposta; só ninguém ter dito nada é falta.
  else if (destino === "cliente" && r?.serviceOrderId === undefined && !osJaDita) falta.push("os");
  else if (destino === "empresa" && !r?.costCenterId) falta.push("centro");
  if (String(r?.notes ?? "").trim().length < MINIMO_DO_QUE_FOI_FEITO) falta.push("o_que_foi_feito");
  return falta;
}

/**
 * O que a APROVAÇÃO faz com a resposta (finance-review/aprovar): a categoria que vai para o
 * lançamento, ou o motivo de recusar. `osRespondida` é a OS que vale — a da tela ou, sem
 * resposta na tela, a que o dono anotou pelo WhatsApp.
 */
export function aplicarDestino(
  kind: string,
  categoria: string,
  r: RespostaDoDestino | null | undefined,
  osRespondida: string | null | undefined,
): { categoria: string } | { erro: string } {
  const osJaDita = r?.serviceOrderId === undefined ? (osRespondida ?? null) : null;
  const falta = faltaNoDestino(kind, categoria, r, osJaDita);
  if (falta.length > 0) return { erro: fraseDaFalta(falta) };
  if (!precisaDeDestino(kind, categoria)) return { categoria };
  const destino = destinoEfetivo(categoria, r, osJaDita);
  if (destino === "empresa" && typeof osRespondida === "string") {
    return { erro: "Você disse que o serviço foi para a HBR e ligou a despesa à OS de um cliente — escolha um dos dois" };
  }
  return { categoria: categoriaDoDestino(categoria, destino) };
}

const ROTULO_DA_FALTA: Record<FaltaNoDestino, string> = {
  destino: "para onde foi (serviço de um cliente ou para a HBR)",
  os: "a OS do cliente (ou que não tem OS no sistema)",
  centro: "o centro de custo",
  o_que_foi_feito: "o que foi feito",
};

/** "Serviço de terceiro: diga para onde foi e o que foi feito". */
export function fraseDaFalta(falta: FaltaNoDestino[]): string {
  const partes = falta.map((f) => ROTULO_DA_FALTA[f]);
  const lista = partes.length <= 1 ? (partes[0] ?? "") : `${partes.slice(0, -1).join(", ")} e ${partes[partes.length - 1]}`;
  return `Serviço de terceiro: diga ${lista}`;
}
