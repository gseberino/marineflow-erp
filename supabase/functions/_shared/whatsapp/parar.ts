// Retorno rápido ao cliente, F1 (P13; sobe no pacote F0b-1 de 10/11/2026): o PARAR estreito, o mesmo do banco.
//
// Até aqui o whatsapp-webhook gravava opt_out_whatsapp no cliente ou no fornecedor pela regra LARGA de
// classificarResposta (_shared/ai/comms/reply-router.ts:31, congelado): "nunca mais", "me tira", "pare de me
// mandar" também contavam. Com a identificação nova (F0b-1), que reconhece 22 números de cliente em vez de 4,
// essa regra passaria a calar em silêncio quem só reclamou (R1-17, defeito 37). Por isso, com a identificação nova
// ligada (retorno_config.identificacao_nova), o webhook só grava o opt-out do cliente que ela achou quando a mensagem
// INTEIRA é o pedido de parar: a mesma regra de _e_pedido_de_parar (F0b, 20261106100100:19-28), que o gatilho
// trg_whatsapp_mensagem_parar já aplica a qualquer número. Com ela desligada, e sempre no fornecedor, continua a
// regra larga de hoje: sem o retorno ligado, nada muda.
//
// O PARAR por extenso ("pare de me mandar mensagem") do cliente achado pela identificação nova deixa de gravar
// opt-out. Ele só chega ao dono pelo sinal parar_largo (P2), que tira o recibo, e pela linha "Para conferir" da
// manhã (P9/P14), e os dois só sobem em 16/11: entre ligar a identificação nova e 16/11, esse pedido não grava
// opt-out e não chega a ninguém. O classificarResposta continua marcando o ai_comms_log como antes.
//
// Porte exato, passo a passo: lower + translate dos acentos de _texto_simples (sem o ñ), [^a-z0-9 ] vira espaço,
// espaços juntados, trim e o mesmo padrão. parar_test.ts roda os casos de supabase/tests/retorno_f0b_parar.sql e
// confere o padrão contra a migration: se um lado mudar, o teste cai até o outro mudar junto.
//
// Reverter: apagar este arquivo e parar_test.ts, e voltar a condição de manejarRespostaAutomatica
// (whatsapp-webhook/index.ts) para `r.intencao === "opt_out"`, sem o parâmetro identificacaoNova. Sem deploy:
// retorno_config.identificacao_nova = false já volta à regra larga de hoje.

/** Os acentos que _texto_simples troca (translate), na mesma ordem; o ñ fica de fora, como no banco. */
const COM_ACENTO = "áàâãäéèêëíìîïóòôõöúùûüç";
const SEM_ACENTO = "aaaaaeeeeiiiiooooouuuuc";

/** O padrão de _e_pedido_de_parar, letra por letra (a mensagem inteira, já simplificada). */
export const PEDIDO_DE_PARAR =
  /^(parar|pare|stop|sair|descadastrar|nao quero mais (receber )?(mensagem|mensagens)( automaticas?)?)( por favor| pf)?$/;

/** Porte de _texto_simples: minúsculas e sem os acentos do translate. Nulo vira texto vazio, como o coalesce. */
export function textoSimples(texto: string | null | undefined): string {
  let saida = "";
  for (const letra of (typeof texto === "string" ? texto : "").toLowerCase()) {
    const i = COM_ACENTO.indexOf(letra);
    saida += i >= 0 ? SEM_ACENTO[i] : letra;
  }
  return saida;
}

/**
 * A mensagem inteira é o pedido de parar (parar, pare, stop, sair, descadastrar, "não quero mais mensagem")?
 * Igual a _e_pedido_de_parar: "vou parar o carro aí", "nunca mais faço com vocês" e "me tira uma dúvida" não contam.
 */
export function ehPedidoDeParar(texto: string | null | undefined): boolean {
  const simples = textoSimples(texto).replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
  return PEDIDO_DE_PARAR.test(simples);
}
