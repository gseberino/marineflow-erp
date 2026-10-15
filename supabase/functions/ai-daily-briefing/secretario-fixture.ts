// Dados de teste da manhã nova: o dia 15/10/2026 às 07:30 como estava no banco (reconstruído por SELECT no
// ensaio de 15/10 — D:/IA-HBR/comprovantes-bancada/spec/ensaio-manha.md), com ids de mentira e só uma parte dos
// contatos. Só os testes importam (o index.ts não: não vai na publicação).
//
// O que o ensaio corrigiu em relação ao primeiro fixture: a tarefa de compra da OS-00104 é recriada e fechada a
// cada hora (às 07:30 não há tarefa aberta: a OS é "parada"); o ORÇ-00116 foi encaminhado ao cliente em 09/10
// (é "enviado", não "montado e não enviado"); a conversa da MP já estava respondida; o Jorge escreveu em 14/10
// "quer que eu leve o motorhome amanhã" (hoje); o "Cesar" (sem cadastro até 15/10 12:15) pediu o orçamento.

import type { ColetaDoSecretario } from "./secretario-candidatos.ts";
import type { DadosDeHoje } from "./secretario-texto.ts";

export const AGORA_1510 = new Date("2026-10-15T10:30:00Z"); // 07:30 de Brasília
export const HOJE_1510 = "2026-10-15";

export const CLIENTES = {
  marcelo: "c-marcelo", joao: "c-joao", mp: "c-mp", lirio: "c-lirio", flavio: "c-flavio", jorge: "c-jorge", giancarlo: "c-giancarlo",
  nelson: "c-nelson", final: "c-final", everton: "c-everton", santo: "c-santo", vanderlei: "c-vanderlei", cesar: "c-cesar",
};

export function coleta1510(): ColetaDoSecretario {
  return {
    cobrancas: [
      { id: "r-mp45", client_id: CLIENTES.mp, cliente: "MP MOTOR HOMES", descricao: "OS-00045 - Estoque Revenda", vencimento: "2026-07-22", saldo: 1650, os_numero: "OS-00045", barco: "Estoque Revenda" },
      { id: "r-lirio", client_id: CLIENTES.lirio, cliente: "Lírio", descricao: "OS-00047 - S.I. 8.5 2016", vencimento: "2026-07-22", saldo: 756, os_numero: "OS-00047", barco: "S.I. 8.5 2016" },
      { id: "r-mp46", client_id: CLIENTES.mp, cliente: "MP MOTOR HOMES", descricao: "OS-00046 - Estoque Revenda", vencimento: "2026-07-22", saldo: 20, os_numero: "OS-00046", barco: "Estoque Revenda" },
      { id: "r-joao", client_id: CLIENTES.joao, cliente: "João Luiz Hang", descricao: "Saldo — OS-00051", vencimento: "2026-10-13", saldo: 1710, os_numero: "OS-00051", barco: "Overland Vegini" },
      { id: "r-marcelo", client_id: CLIENTES.marcelo, cliente: "Marcelo Marco Bertoldi", descricao: "À vista — OS-00038", vencimento: "2026-10-13", saldo: 16890, os_numero: "OS-00038", barco: "Aria" },
    ],
    conversas: [
      {
        phone: "5547900000001", contato: "Jorge Girardon", categoria: "cliente", client_id: CLIENTES.jorge, last_inbound_at: "2026-10-14T17:53:05Z",
        last_body: "🎤 Oi Gustavo, como é que tá o senhor? Tudo bom? Tu quer que eu leve o motorhome amanhã lá pra gente dar uma olhada naquele ar-condicionado",
        recebidas: [
          { body: "🎤 Oi Gustavo, como é que tá o senhor? Tudo bom? Tu quer que eu leve o motorhome amanhã lá pra gente dar uma olhada naquele ar-condicionado", em: "2026-10-14T17:53:05Z" },
          { body: "🎤 Boa tarde Gustavo, beleza? Tu quer que eu deixe o motorhome amanhã para você fazer o estofado lá da Dinete?", em: "2026-10-14T17:48:01Z" },
        ],
        diasComMensagemSua: 0,
      },
      {
        // sem cadastro às 07:30 (virou cliente "César – Palazzo" às 12:15, com o ORÇ-00119)
        phone: "5511900000002", contato: "Cesar", categoria: "contato", client_id: null, last_inbound_at: "2026-10-14T15:23:16Z", last_body: "[conteúdo vazio]",
        recebidas: [
          { body: "[conteúdo vazio]", em: "2026-10-14T15:23:16Z" },
          { body: "Pode me passar o orçamento por favor", em: "2026-10-14T15:23:13Z" },
          { body: "Td tranquilo", em: "2026-10-14T15:22:57Z" },
          { body: "Programação para feriado dia 02-11", em: "2026-10-09T20:44:19Z" },
        ],
        diasComMensagemSua: 1,
      },
      {
        phone: "5547900000003", contato: "Giancarlo Ribeiro dos Santos", categoria: "cliente", client_id: CLIENTES.giancarlo, last_inbound_at: "2026-10-13T13:31:48Z",
        last_body: "A entrega vc consegue p qdo?",
        recebidas: [
          { body: "A entrega vc consegue p qdo?", em: "2026-10-13T13:31:48Z" },
          { body: "Me passa a forma de pagamento do que ficou. Vi teu pix no orçamento,  quanto vc precisa no pix?", em: "2026-10-13T13:23:03Z" },
        ],
        diasComMensagemSua: 2,
      },
      {
        phone: "5547900000004", contato: "Flávio da Igreja", categoria: "cliente", client_id: CLIENTES.flavio, last_inbound_at: "2026-10-08T19:26:44Z", last_body: "Já",
        recebidas: [{ body: "Já", em: "2026-10-08T19:26:44Z" }, { body: "Veja aí vou viajar fim do mês", em: "2026-10-08T14:36:37Z" }],
        diasComMensagemSua: 1,
      },
      {
        phone: "5547900000005", contato: "Climatec Refrigeração — seu conforto em boas mãos!\n\nClimatec", categoria: "contato", client_id: null,
        last_inbound_at: "2026-10-14T21:08:12Z", last_body: "🎤 Pois é, porque tá meio feinho, né? Tem que limpar",
        recebidas: [{ body: "🎤 Pois é, porque tá meio feinho, né? Tem que limpar", em: "2026-10-14T21:08:12Z" }], diasComMensagemSua: 2,
      },
      {
        phone: "5547900000006", contato: "Jaison Consultor de Vendas", categoria: "contato", client_id: null, last_inbound_at: "2026-10-14T14:37:13Z",
        last_body: "Passando pra ver contigo se ficou alguma duvida aos itens que você solicitou?",
        // vendedor falando de preço não é "pedir preço"
        recebidas: [
          { body: "Passando pra ver contigo se ficou alguma duvida aos itens que você solicitou?", em: "2026-10-14T14:37:13Z" },
          { body: "Pode mas ai será o preço de tabela, com as quantidades ai já consigo buscar uma proposta diferenciada", em: "2026-10-13T17:02:02Z" },
        ],
        diasComMensagemSua: 2,
      },
      {
        phone: "5547900000007", contato: "SR Contabilidade", categoria: "fornecedor", client_id: null, last_inbound_at: "2026-10-13T17:02:03Z",
        last_body: "Assim que possível enviar extrato bancário do ano 2026", recebidas: [{ body: "Assim que possível enviar extrato bancário do ano 2026", em: "2026-10-13T17:02:03Z" }],
        diasComMensagemSua: 0,
      },
    ],
    orcamentos: [
      { id: "q-95", numero: "ORÇ-00095", quote_status: "awaiting_deposit", valor: 14461, client_id: CLIENTES.mp, cliente: "MP MOTOR HOMES", barco: "Industrailer Scania", criado_em: "2026-09-09T15:34:28Z", mexido_em: "2026-10-06T14:06:25Z", fim_validade: null },
      { id: "q-111", numero: "ORÇ-00111", quote_status: "awaiting_approval", valor: 4254.69, client_id: CLIENTES.final, cliente: "Cliente Final", barco: "Motorhome", criado_em: "2026-09-30T19:06:29Z", mexido_em: "2026-10-13T13:17:40Z", fim_validade: "2026-10-03" },
      // rascunho encaminhado ao cliente em 09/10 (a coleta o trata como enviado)
      { id: "q-116", numero: "ORÇ-00116", quote_status: "sent", valor: 70050, client_id: CLIENTES.santo, cliente: "Santo Inacio", barco: "S.I. 7.8 AUTO", criado_em: "2026-10-09T20:31:29Z", mexido_em: "2026-10-09T20:48:19.000Z", fim_validade: "2026-10-12", enviado_em: "2026-10-09T20:48:19.000Z" },
      { id: "q-117", numero: "ORÇ-00117", quote_status: "draft", valor: 120020, client_id: CLIENTES.everton, cliente: "EVERTON CARLOS PINHEIRO", barco: "Sprinter Furgão Longo Teto Alto", criado_em: "2026-10-13T15:20:19Z", mexido_em: "2026-10-14T21:44:26Z", fim_validade: null },
      { id: "q-118", numero: "ORÇ-00118", quote_status: "draft", valor: 21333.7, client_id: CLIENTES.final, cliente: "Cliente Final", barco: "Trailer Darlan", criado_em: "2026-10-13T20:20:15Z", mexido_em: "2026-10-13T20:54:29Z", fim_validade: null },
      { id: "q-78", numero: "ORÇ-00078", quote_status: "draft", valor: 3693.29, client_id: "c-rodrigo", cliente: "Rodrigo", barco: "MH Overlander - VW Delivery", criado_em: "2026-08-13T23:25:05Z", mexido_em: "2026-09-26T01:06:26Z", fim_validade: null },
      { id: "q-114", numero: "ORÇ-00114", quote_status: "draft", valor: 2022.61, client_id: CLIENTES.cesar, cliente: "César", barco: "Santo Inácio 8.5 – 2015", criado_em: "2026-10-08T21:41:19Z", mexido_em: "2026-10-09T15:40:46Z", fim_validade: null },
      { id: "q-115", numero: "ORÇ-00115", quote_status: "draft", valor: 453.4, client_id: CLIENTES.cesar, cliente: "César", barco: "Santo Inácio 8.5 – 2015", criado_em: "2026-10-08T21:54:10Z", mexido_em: "2026-10-08T22:00:22Z", fim_validade: null },
    ],
    oss: [
      // a tarefa de compra da OS-00104 nunca está aberta às 07:30 (recriada e fechada a cada hora)
      { id: "o-104", numero: "OS-00104", status: "awaiting_parts", valor: 2760, client_id: CLIENTES.flavio, cliente: "Flávio da Igreja", barco: "Itapoã", mexido_em: "2026-10-03T23:25:20Z", agendada_em: "2026-10-06T09:00:00Z", sinal_pago: 2070, tarefa_compra: null, cobrancas_vivas: 1 },
      // a "tarefa fantasma" da crítica (a compra já foi feita): dedução, o texto diz "parece"
      { id: "o-112", numero: "OS-00112", status: "awaiting_parts", valor: 10500, client_id: CLIENTES.nelson, cliente: "Nelson", barco: "Santo Inácio 7.8", mexido_em: "2026-10-13T13:10:15Z", agendada_em: null, sinal_pago: 7600, tarefa_compra: { titulo: "Comprar 4 itens — OS-00112 (Nelson)", criada_em: "2026-10-13T13:15:04Z" }, cobrancas_vivas: 2 },
      { id: "o-69", numero: "OS-00069", status: "open", valor: 9008.99, client_id: CLIENTES.vanderlei, cliente: "Vanderlei Andrade", barco: "Santo Inácio 6.9", mexido_em: "2026-10-03T23:25:20Z", agendada_em: null, sinal_pago: 4500, tarefa_compra: null, cobrancas_vivas: 1 },
      { id: "o-38", numero: "OS-00038", status: "completed", valor: 16890, client_id: CLIENTES.marcelo, cliente: "Marcelo Marco Bertoldi", barco: "Aria", mexido_em: "2026-10-13T13:11:52Z", agendada_em: null, sinal_pago: 0, tarefa_compra: null, cobrancas_vivas: 1 },
      { id: "o-100", numero: "OS-00100", status: "open", valor: 5739, client_id: CLIENTES.giancarlo, cliente: "Giancarlo Ribeiro dos Santos", barco: "Vitória Star", mexido_em: "2026-10-13T13:57:07Z", agendada_em: null, sinal_pago: 2869.5, tarefa_compra: null, cobrancas_vivas: 2 },
    ],
  };
}

export function deHoje1510(): DadosDeHoje {
  return {
    agenda: [],
    // o texto da promessa é o que o banco guardou (a frase do dono)
    promessas: [{ contato: "Eng.⁰ Rafael Borges DOMETIC", promessa: "Claro, te passo agora!" }],
    vencimentos: [{ lado: "receber", quando: "amanha", valor: 5237.99, nome: "APOLO INDUSTRIA E COMERCIO DE VEICULOS DE RECREACAO LTDA" }],
    falhasDeEnvio: 0,
    errosDaNoite: 0,
  };
}
