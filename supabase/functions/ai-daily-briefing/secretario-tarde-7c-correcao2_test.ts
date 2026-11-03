// (Agenda de Produção, Fase 7c, correção 2 da revisão — migration 20261102100590, achados 1 e 13) O que o Secretário faz com os
// números novos que o banco manda: com uma linha da 7c ligada que espera demais (a (n) de quem faz o quê nunca vista há 2 dias úteis, ou a
// (o) "Etapas" da véspera do último dia), TODAS as linhas ligadas de 75 sobem a 77 juntas, e a pergunta do gestor de 76 que não perde hoje
// é quem sai no corte de 1.000 — nunca a mensagem ao cliente que espera *manda cliente*. Antes (a 100580), só a (n) subia: com 4 linhas
// de 75 ou mais, saía o cliente. O TS do Secretário não muda; este teste fixa o que ele faz com cada ordem (os textos de tamanho real são
// os do secretario-tarde-texto_test.ts).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type AgendaDoFechamento, type DadosDaTarde, LIMITE_DA_TARDE, textoDaTarde } from "./secretario-tarde-texto.ts";
import type { LinhaComLetra } from "./secretario-tarde-regras.ts";

type Linha = NonNullable<AgendaDoFechamento["linhas"]>[number];
const l = (tipo: Linha["tipo"], texto: string, perda: number, extra: Partial<Linha> = {}): Linha => ({
  tipo, texto, perda, pergunta_id: null, acao_ids: [], modo: "ligado", ...extra,
});
function ficou(letra: string, texto: string): LinhaComLetra {
  return { letra, parte: "ficou", referencia: `ref:${letra}`, tipo: "cobranca_grande", texto, faco: "te mostro o lembrete pronto",
           alternativa: "até segunda", comandoAlternativo: "espera", valor: 100, desde: "2026-10-13" } as LinhaComLetra;
}
const COMPRAS = "Compras: Sem fornecedor (contei 7 dias úteis): 3 itens de Vanderlei — compre até hoje.";
const GESTOR = "Agenda: Sem resposta até qua 04/11 18:00: Flávio (OS-00104) 3,5 dias; Nelson (OS-00112) 4 dias; Vanderlei (OS-00069) 7,5 dias; " +
  "MP (ORÇ-00095) 1 dia. Espero você (não marco sozinho): Giancarlo (OS-00130).";
const GESTOR_C = "Agenda: Sem resposta até qua 04/11 18:00, conto: Flávio (OS-00104) 3,5 dias; Nelson (OS-00112) 4 dias; Vanderlei (OS-00069) " +
  "7,5 dias; MP (ORÇ-00095) 1 dia. Espero você (não marco sozinho): Giancarlo (OS-00130).";
const HAB = "Agenda: Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: Alex instala sozinho, também com " +
  "220 V ou banco de bateria, e sobe no teto (você disse que ele vem todo dia útil). Comissionar Victron fica com você. Se você não " +
  "responder até as 18:00 do próximo dia útil depois de ver esta pergunta, fica assim. Para corrigir, me diga numa frase (ex.: \"o Alex " +
  "não sobe no teto\" ou \"o Alex é ajudante\").";
const HAB_C = "Agenda, equipe: quem faz o quê — marquei: Alex instala sozinho; sem resposta até qui 05/11 às 18:00, fica assim. *agenda pendências* mostra.";
const CLI = "Mensagem para Vera (véspera, com a pergunta do acesso), sai ter 10/11 às 09:00: \"Bom dia, Vera! Aqui é o Gustavo, da HBR " +
  "Marine. Amanhã chegamos o dia todo para o serviço no seu motorhome. Para não perdermos a viagem: onde o seu motorhome vai estar, e a " +
  "chave fica com quem? Pode responder por aqui mesmo, até por áudio.\". *manda cliente Vera* ou *segura cliente Vera*.";
const CLI_C = "Mensagem para Vera (véspera, com a pergunta do acesso) espera *manda cliente Vera* (sai ter 10/11 às 09:00); *agenda clientes* mostra.";
const ETA = "Etapas (Alex não tem telefone: quem passa e confere é você). Seg 09/11, Alex no Lenine: Terminar: Passagem e crimpagem de " +
  "cabos de bateria; Testar e conferir antes de entregar (Elétrico DC). É o último dia: tem que ficar tudo pronto.";
const ETA_C = "Etapas: seg 09/11 é o último dia do Lenine (Alex, 2 etapas). Pergunte o que o Alex faz na seg 09/11.";
const FICARAM = [
  ficou("A", "OS-00112 Nelson (Santo Inácio 7.8): 4 itens a comprar até seg 26/10"),
  ficou("B", "Marcelo Marco Bertoldi (OS-00038): R$ 16.890,00, venceu 13/10 (16 dias); ainda não entrou"),
  ficou("C", "APOLO INDUSTRIA E COMERCIO DE…: R$ 5.237,99, venceu 16/10 (13 dias); ainda não entrou"),
];
function dados(linhas: Linha[], ficaram: number, hoje = "2026-11-10", pergunta = false): DadosDaTarde {
  return {
    hoje, turno: "fechamento", ficaram: FICARAM.slice(0, ficaram), fornecedores: [], parados: [], panorama: null, antigas: null,
    mesQueFechou: null, faturamento: null, pergunta,
    escritorio: { propostas: { saidas: 107, entradas: 10, transferencias: 1, outras: 0 }, alertas: 33, regras: 0, debitosSemLoja: 8, entradas: null },
    amanha: { dia: "2026-11-11", itens: [], carteira: { semData: 6 }, agenda: { modo: "ligado", cauda: null, semana: [], linhas, vagas_garantidas: 3 } },
  } as unknown as DadosDaTarde;
}
const gestor = (p: number) => ({ ...l("pergunta", GESTOR, p, { pergunta_id: "q-g", pergunta_ids: ["q-g"] }), texto_curto: GESTOR_C });
const hab = (p: number) => ({ ...l("pergunta", HAB, p, { pergunta_id: "q-hab", pergunta_ids: ["q-hab"] }), texto_curto: HAB_C });
const cli = (p: number) => ({ ...l("cliente", CLI, p, { pergunta_id: "q-cli" }), texto_curto: CLI_C });
const eta = (p: number) => ({ ...l("dia", ETA, p), texto_curto: ETA_C });
const saiu = (linhas: Linha[], f: number, hoje?: string, pergunta?: boolean) => {
  const t = textoDaTarde(dados(linhas, f, hoje, pergunta));
  assert((t.texto?.length ?? 0) <= LIMITE_DA_TARDE, `passou de ${LIMITE_DA_TARDE}: ${t.texto?.length}`);
  return { texto: t.texto ?? "", linhas: (t.agenda?.linhas ?? []).map((x) => `${x.tipo} ${x.perda}`) };
};

for (const f of [0, 2]) {
  Deno.test(`7c correção 2, achado 1 (ficaram ${f}): a (n) que espera, a do gestor (76) e o cliente — as de 75 sobem juntas e o cliente fica`, () => {
    // a 100580 (só a (n) a 77): o cliente, a de menor perda, saía do fechamento
    const antes = saiu([l("compras", COMPRAS, 80), hab(77), gestor(76), cli(75)], f);
    assert(!antes.texto.includes("Vera"), `antes, o cliente saía: ${antes.linhas.join(", ")}`);
    // a 100590 (as de 75 a 77 juntas): sai a do gestor, que não perde hoje; o cliente e a (n) ficam
    const agora = saiu([l("compras", COMPRAS, 80), cli(77), hab(77), gestor(76)], f);
    assert(agora.texto.includes("Vera"), `o cliente tem de ficar: ${agora.linhas.join(", ")}`);
    assert(agora.texto.includes("quem faz o quê"), `a (n) tem de ficar: ${agora.linhas.join(", ")}`);
    assert(!agora.linhas.includes("pergunta 76"), `a do gestor (76) é quem sai: ${agora.linhas.join(", ")}`);
  });
}

Deno.test("7c correção 2, achado 13 (a sexta cheia, com a pergunta da semana): a véspera do último dia sobe com as de 75 e a do gestor espera", () => {
  // sex 06/11, o Lenine termina na seg 09/11: antes, a (o) de 75 saía atrás da do gestor (76)
  const antes = saiu([l("compras", COMPRAS, 80), gestor(76), eta(75)], 3, "2026-11-06", true);
  assert(!antes.texto.includes("último dia"), `antes, a véspera não chegava: ${antes.linhas.join(", ")}`);
  const agora = saiu([l("compras", COMPRAS, 80), eta(77), gestor(76)], 3, "2026-11-06", true);
  assert(agora.texto.includes("seg 09/11 é o último dia do Lenine"), `a véspera tem de chegar: ${agora.linhas.join(", ")}`);
  assertEquals(agora.linhas.includes("pergunta 76"), false);
});
