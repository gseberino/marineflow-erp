// Os tipos de item da manhã nova (os mesmos dos CHECKs de resumo_itens, migration 20261015200000).

export type Familia = "cobranca" | "cliente" | "contato" | "orcamento" | "os";

export type TipoDoItem =
  | "cobranca_grande" | "cobranca_marco" | "cobranca_fora_do_marco" | "cobranca_antiga"
  | "cliente_sem_resposta" | "cliente_recente"
  | "contato_pedindo_preco" | "contato_sem_cadastro" | "fornecedor"
  | "orcamento_parado" | "orcamento_vencendo" | "orcamento_nao_enviado" | "orcamento_na_lista"
  | "os_esperando_compra" | "os_sem_cobranca" | "os_parada";

/** As seções da *lista*, nesta ordem (as letras da lista seguem esta ordem). */
export type Secao = "dinheiro" | "clientes" | "obras" | "contatos";
export const SECOES: readonly Secao[] = ["dinheiro", "clientes", "obras", "contatos"];

export const TITULO_DA_SECAO: Record<Secao, string> = {
  dinheiro: "Dinheiro",
  clientes: "Clientes e orçamentos",
  obras: "Obras",
  contatos: "Contatos",
};

/**
 * Para quando vai o "X espera": quem espera resposta, amanhã; dinheiro, orçamento e cobrança da OS,
 * a próxima segunda (o "seguro até segunda" do desenho).
 */
export function esperaDoTipo(tipo: string): "amanha" | "segunda" {
  return tipo.startsWith("cliente") || tipo.startsWith("contato") || tipo === "os_esperando_compra" || tipo === "fornecedor"
    ? "amanha"
    : "segunda";
}

/** Cobrança grande fica toda manhã até entrar: o "feito" dela cala só o dia. */
export function ficaTodoDia(tipo: string): boolean {
  return tipo === "cobranca_grande";
}
