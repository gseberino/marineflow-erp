// Retorno rápido, F4 (P15): a travessia do parceiro, a metade que roda no CI (sem banco). A outra metade, com banco, é
// supabase/tests/retorno_f4_travessia.sql (bancada, grupo 7, onda 10).
//
// O que prova:
//  1. os textos reais (os modelos do catálogo _parceiro_texto, conferidos LITERAIS contra a migration) passam no validador
//     do parceiro, e cada negativo da F4 reprova (valor, data de pronto, dado pessoal, nome de outro cliente, OS de outro);
//  2. a guarda de envio (compliance-guard): valor nunca vai a quem só indicou, nem com o documento;
//  3. os leitores contra a matriz 7.2 e 7.3: as palavras do parceiro e do cliente (pátio, pausar, NÃO MP) nunca são palavra
//     do dono; *segura pátio* é; o opt-out largo não lê "nao mp";
//  4. as âncoras de código: parceiro_saida_autorizada chamada por retorno_saida_autorizada (na última definição);
//     a rodada nunca valida texto à parceira com o validador do cliente; send_service_order_link nunca lê telefone de
//     args; a via reduzida do PDF sem CPF, fone, e-mail e endereço.
//
// Mora em _shared/whatsapp/ porque importa compliance-guard e leitores de _shared/ai/: o isolamento_test.ts varre
// _shared/retorno/ e _shared/parceiro/, testes inclusive (o mesmo arranjo de retorno-comandos_test.ts).
// Frases, nomes e números inventados (4321 e 7391 como finais). Nenhuma mensagem real.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  type ContextoAoParceiro,
  type ContextoDoValidador,
  type RegraDoValidador,
  validarSaida,
  validarSaidaAoParceiro,
} from "../retorno/validador.ts";
import { ehComandoDeCartao, lerComandoDoRetorno } from "../retorno/comandos.ts";
import { lerComandoDoParceiro } from "../parceiro/comandos.ts";
import { lerComandoDaAgenda } from "../agenda/comandos.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { lerPedidoDePdf } from "../ai/atalho-pdf.ts";
import { parseConfirmationReply } from "../ai/whatsapp-channel.ts";
import { classificarResposta } from "../ai/comms/reply-router.ts";
import { guardaDeEnvio } from "../ai/comms/send-guard.ts";
import { ehPedidoDeParar } from "./parar.ts";
import { buildOrderHTML, buildPDFFilename, DEFAULT_PDF_OPTIONS } from "../pdf/documento.ts";
import { ORCAMENTO } from "../pdf/amostras.ts";

const FUNCOES = new URL("../../", import.meta.url);
const MIGRATIONS = new URL("../migrations/", FUNCOES);
// CRLF vira LF: no Windows o checkout pode trazer \r\n, e as âncoras procuram por linha
const ler = (url: URL) => Deno.readTextFileSync(url).replace(/\r\n/g, "\n");

// ─── 1. Os textos reais e os negativos ─────────────────────────────────────────────────────────────────────────

/** Os modelos que validador_parceiro_test.ts copia do catálogo, lidos da fonte (P e Q). */
function modelosDoTesteDoValidador(): Record<string, string> {
  const fonte = ler(new URL("../retorno/validador_parceiro_test.ts", import.meta.url));
  const modelos: Record<string, string> = {};
  for (const bloco of ["const P: Record<string, string> = {", "const Q: Record<string, string> = {"]) {
    const ini = fonte.indexOf(bloco);
    const fim = fonte.indexOf("};", ini);
    assert(ini > 0 && fim > ini, `o bloco ${bloco} sumiu de validador_parceiro_test.ts`);
    for (const m of fonte.slice(ini, fim).matchAll(/^\s*([PQ]\w+): "((?:[^"\\]|\\.)*)",/gm)) {
      modelos[m[1]] = m[2].replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    }
  }
  return modelos;
}

Deno.test("travessia 1a: cada modelo do teste do validador está LITERAL no catálogo da migration (o texto real)", () => {
  const sql = ler(new URL("20270105100300_retorno_f4_textos.sql", MIGRATIONS)).replace(/''/g, "'");
  const modelos = modelosDoTesteDoValidador();
  assert(Object.keys(modelos).length >= 20, `poucos modelos lidos (${Object.keys(modelos).length})`);
  const fora: string[] = [];
  for (const [id, texto] of Object.entries(modelos)) {
    // {comigo} e {pessoa} são o prefixo {abertura} no catálogo (spec P4.1): o resto do modelo tem de estar lá
    const miolo = texto.replace(/^\{(comigo|abertura|pessoa)\}/, "");
    if (!sql.includes(miolo)) fora.push(id);
  }
  assertEquals(fora, [], "modelo do teste que não está no catálogo do banco");
});

const SEM_MARCAS: ContextoDoValidador["marcas"] = { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false };

/** O contexto como _parceiro_contexto_do_validador monta: os trechos são o texto cortado nos valores. */
function ctx(texto: string, valores: string[], extra: Partial<ContextoAoParceiro> = {}): ContextoAoParceiro {
  let corte = texto;
  for (const v of [...valores].filter((x) => x.trim() !== "").sort((a, b) => b.length - a.length)) corte = corte.split(v).join("\u001f");
  return {
    audiencia: "parceiro", datas_permitidas: [], horas_permitidas: [], nome_permitido: null, nomes_de_outros: [], nomes_da_lista: [],
    papel_do_parceiro: "indicou", os_permitidas: [], textos_do_cliente: [], marcas: SEM_MARCAS,
    trechos_do_modelo: corte.split("\u001f").filter((p) => p.trim() !== ""),
    ...extra,
  };
}

const PAINEL_OK = "Pátio HBR · qua (13/01)\n1. Motorhome de João S.: em serviço.\n2. Motorhome de Ana P.: aguardando uma peça; sem novidade desde 08/01.\nPara ver de novo, mande *pátio*.";
const VALORES_DO_PAINEL = ["qua (13/01)", "Motorhome", "João S.", "Ana P.", "08/01"];

Deno.test("travessia 1b: o painel real passa; cada negativo da F4 reprova com a regra certa", () => {
  const base = { datas_permitidas: ["qua (13/01)", "08/01"], nomes_da_lista: ["João S.", "Ana P."] };
  assertEquals(validarSaidaAoParceiro(PAINEL_OK, ctx(PAINEL_OK, VALORES_DO_PAINEL, base)), { ok: true });
  const reprova = (texto: string, valores: string[], regra: RegraDoValidador, extra: Partial<ContextoAoParceiro> = {}) => {
    const r = validarSaidaAoParceiro(texto, ctx(texto, valores, { ...base, ...extra }));
    assert(!r.ok && r.regras.includes(regra), `${regra} não reprovou: ${texto} → ${JSON.stringify(r)}`);
  };
  // valor, até à contratante: valor só sai no PDF
  reprova("Pátio HBR · qua (13/01)\n1. Motorhome de João S.: R$ 1.200,00.", ["qua (13/01)", "Motorhome", "João S."], "valor_a_parceiro");
  reprova("Pátio HBR · qua (13/01)\n1. Motorhome de João S.: R$ 1.200,00.", ["qua (13/01)", "Motorhome", "João S."], "valor_a_parceiro",
    { papel_do_parceiro: "contratante" });
  // data de pronto: nunca
  reprova("Pátio HBR: o motorhome de João S. fica pronto amanhã.", ["motorhome", "João S."], "data_de_pronto");
  // dado pessoal: o telefone do cliente
  reprova("Pátio HBR: o cliente João S. (47 98888-7391) já foi avisado.", ["João S."], "dado_pessoal");
  // nome de outro cliente (homônimo fora da lista)
  reprova("Pátio HBR · qua (13/01)\n1. Motorhome de Pedro K.: em serviço.", ["qua (13/01)", "Motorhome", "Pedro K."], "nome_de_outro",
    { nomes_de_outros: ["Pedro K."] });
  // sem contexto, ou com o contexto do cliente: reprova (o validador do cliente nunca é usado para a parceira)
  assert(!validarSaidaAoParceiro(PAINEL_OK, null).ok);
  const comoCliente = { ...ctx(PAINEL_OK, VALORES_DO_PAINEL, base), audiencia: "cliente" } as unknown as ContextoAoParceiro;
  assertEquals(validarSaidaAoParceiro(PAINEL_OK, comoCliente).ok, false);
  // e o inverso: o contexto do parceiro nunca passa no validador do cliente
  assertEquals(validarSaida(PAINEL_OK, ctx(PAINEL_OK, VALORES_DO_PAINEL, base) as unknown as ContextoDoValidador).ok, false);
});

// ─── 2. A guarda de envio: valor nunca a quem só indicou ───────────────────────────────────────────────────────

Deno.test("travessia 2: valor_a_parceiro em indicou (texto ou documento); contratante e pagador só com o documento", () => {
  const t = new FakeTime(new Date("2027-01-13T14:00:00.000Z")); // 11:00 em Brasília, dentro da janela
  try {
    // a regra de valor lê o texto do contexto (ctx.texto); o 1º argumento é o do estilo
    const guarda = (texto: string, papel: "indicou" | "contratante" | "pagador" | null, documentoComValor = false) =>
      guardaDeEnvio(texto, {
        tipo: "os_link", audiencia: "parceiro", canal: "whatsapp", destinatarioIdentificado: true, papelDoParceiro: papel, documentoComValor, texto,
      });
    assertEquals(guarda("Segue o orçamento do motorhome de João, válido até 15/01.", "indicou", true).codigoBloqueio, "valor_a_parceiro");
    assertEquals(guarda("Segue o orçamento do motorhome de João, válido até 15/01.", null, true).codigoBloqueio, "valor_a_parceiro");
    assertEquals(guarda("O total ficou em R$ 3.500.", "indicou").codigoBloqueio, "valor_a_parceiro");
    assertEquals(guarda("Segue o orçamento do motorhome de João, válido até 15/01.", "contratante", true).bloqueado, false);
    assertEquals(guarda("Segue o orçamento do motorhome de João, válido até 15/01.", "pagador", true).bloqueado, false);
    assertEquals(guarda("O motorhome de João S. está em serviço.", "indicou").bloqueado, false);
  } finally {
    t.restore();
  }
});

// ─── 3. Os leitores contra a matriz 7.2 e 7.3 ──────────────────────────────────────────────────────────────────

const DO_CLIENTE = ["NÃO MP", "nao mp", "Não, MP", "não mp.", "nao quero mp", "não quero a mp", "nao mp por favor", "NÃO FÖRTRO", "nao fortro", "mp"];
const DO_PARCEIRO = ["pátio", "patio", "PÁTIO", "o patio", "ver patio", "pausar", "pausa", "pausar painel", "retomar", "retoma", "voltar", "volta", "pode executar", "pode fazer"];

Deno.test("travessia 3a: as palavras do cliente e do parceiro nunca são palavra do dono", () => {
  for (const t of [...DO_CLIENTE, ...DO_PARCEIRO]) {
    assertEquals(lerComandoDoParceiro(t), null, `parceiro: ${t}`);
    assertEquals(lerComandoDoRetorno(t), null, `retorno: ${t}`);
    assertEquals(lerComandoDaAgenda(t), null, `agenda: ${t}`);
    assertEquals(lerComando(t), null, `comprovantes: ${t}`);
    assertEquals(lerPedidoDePdf(t), null, `pdf: ${t}`);
  }
  // "volta mp" colide com o Secretário: por isso não existe como palavra do parceiro
  assertEquals(lerComandoDoParceiro("volta mp"), null);
});

Deno.test("travessia 3b: o NÃO MP não dispara o opt-out largo nem o pedido de parar; o *parar* continua sendo parar", () => {
  for (const t of ["nao mp", "NÃO MP", "não quero a mp"]) {
    assertEquals(classificarResposta(t).intencao, "outro", t);
    assertEquals(ehPedidoDeParar(t), false, t);
  }
  for (const t of ["parar", "pare", "stop", "sair"]) assertEquals(ehPedidoDeParar(t), true, t);
  // NÃO MP com a pendência no ponteiro rejeita o pedido (A-10): é palavra de cliente, fora do caminho do dono
  assertEquals(parseConfirmationReply("nao mp")?.decision, "reject");
});

Deno.test("travessia 3c: *segura pátio* é do dono e não é de cartão; *pátio* sozinho do dono é conversa", () => {
  for (const t of ["segura pátio", "solta pátio", "segura patio", "solta patio"]) {
    const c = lerComandoDoRetorno(t);
    assertEquals(c?.comando === "segura" || c?.comando === "solta", true, t);
    assertEquals(ehComandoDeCartao(c!), false, t);
    assertEquals(lerComandoDoSecretario(t), null, t);
  }
  assertEquals(lerComandoDoRetorno("pátio"), null);
});

// ─── 4. As âncoras de código ───────────────────────────────────────────────────────────────────────────────────

/** O corpo da ÚLTIMA definição de uma função no conjunto de migrations (a que vale depois de aplicar todas). */
function ultimaDefinicao(nome: string): { arquivo: string; corpo: string } {
  const arquivos = [...Deno.readDirSync(MIGRATIONS)].filter((e) => e.isFile && e.name.endsWith(".sql")).map((e) => e.name).sort();
  let achado: { arquivo: string; corpo: string } | null = null;
  const re = new RegExp(`create or replace function public\\.${nome}\\(`, "g");
  for (const a of arquivos) {
    const sql = ler(new URL(a, MIGRATIONS));
    for (const m of sql.matchAll(re)) {
      const ini = m.index!;
      const abre = sql.indexOf("$$", ini);
      const fecha = sql.indexOf("$$", abre + 2);
      achado = { arquivo: a, corpo: sql.slice(abre, fecha) };
    }
  }
  assert(achado, `${nome} não existe nas migrations`);
  return achado!;
}

Deno.test("travessia 4a: retorno_saida_autorizada (a última definição) entrega a saída do parceiro a parceiro_saida_autorizada, antes de tudo", () => {
  const { arquivo, corpo } = ultimaDefinicao("retorno_saida_autorizada");
  assertEquals(arquivo >= "20270105100400_retorno_f4_canal.sql", true, `a última definição é de ${arquivo}`);
  const desvio = corpo.indexOf("if v_s.emissor = 'parceiro' then");
  const chama = corpo.indexOf("return public.parceiro_saida_autorizada(p_saida, p_fone, v_agora);");
  const doRetorno = corpo.indexOf("if v_s.emissor is distinct from 'retorno' then");
  assert(desvio > 0 && chama > desvio && doRetorno > chama, "a saída do parceiro não passa pela trava dela antes da do retorno");
  // e a trava do parceiro confere o veto e a regra de ouro no instante do envio
  const { corpo: trava } = ultimaDefinicao("parceiro_saida_autorizada");
  assert(trava.includes("parceiro_os_visivel") || trava.includes("_parceiro_os_visivel"), "parceiro_saida_autorizada sem a regra de ouro");
});

Deno.test("travessia 4b: a rodada nunca valida o texto à parceira com o validador do cliente", () => {
  const fonte = ler(new URL("../../retorno-recibos/rodada.ts", import.meta.url));
  assert(/const aoParceiro = deParceiro && item\.origem !== "retorno_aviso";/.test(fonte), "a decisão do validador mudou");
  assert(/aoParceiro\s*\?\s*validarSaidaAoParceiro\(t, ctx as ContextoAoParceiro\)\s*:\s*validarSaida\(/.test(fonte), "validar não separa o parceiro");
  // toda chamada de validar na rodada leva o aoParceiro
  const chamadas = [...fonte.matchAll(/\bvalidar\(([^)]*)\)/g)].map((m) => m[1]).filter((a) => !a.startsWith("texto: unknown"));
  assert(chamadas.length >= 2, "a rodada não chama validar");
  for (const a of chamadas) assert(/aoParceiro\s*$/.test(a.trim()), `chamada de validar sem aoParceiro: validar(${a})`);
});

Deno.test("travessia 4c: send_service_order_link nunca lê telefone de args, nem no caminho do parceiro", () => {
  const fonte = ler(new URL("../ai/tools/whatsapp.ts", import.meta.url));
  const ini = fonte.indexOf('name: "send_service_order_link"');
  const fim = fonte.indexOf('name: "', ini + 40);
  const tool = fonte.slice(ini, fim);
  const iniP = fonte.indexOf("async function enviarPdfAoParceiro(");
  const parceiro = fonte.slice(iniP, fonte.indexOf("\n}\n", iniP));
  assert(ini > 0 && iniP > 0 && tool.length > 1000 && parceiro.length > 500, "as âncoras do envio sumiram");
  for (const trecho of [tool, parceiro]) {
    assertEquals(/args(\??\.|\[")\s*(phone|to_phone|telefone|fone|whatsapp|numero)\b/.test(trecho), false, "o envio lê telefone de args");
  }
  // o destino do parceiro sai do banco; o parceiro_id só do retrato
  assert(parceiro.includes("destinoDoParceiro(admin, so.id, ctx.userId ?? null, typeof retrato?.parceiro_id"), "o destino não vem só do banco");
  // e a ferramenta não tem campo de telefone
  assert(!/(phone|telefone|to_phone)\s*:\s*\{\s*type/.test(tool), "send_service_order_link ganhou campo de telefone");
});

Deno.test("travessia 4d: a via reduzida do PDF não leva CPF, fone, e-mail nem endereço; o arquivo, só tipo e número", () => {
  const t = new FakeTime(new Date("2026-09-26T14:00:00.000Z"));
  try {
    const dados = {
      ...ORCAMENTO,
      client: { name: "Maria Clara Inventada", cpf_cnpj: "987.654.321-00", phone: "(47) 97777-4321", email: "maria.inventada@exemplo.com", address: "Travessa Sintética, 9" },
    };
    const html = buildOrderHTML(dados, { ...DEFAULT_PDF_OPTIONS, ocultarDadosDoCliente: true });
    for (const dado of ["987.654.321-00", "97777-4321", "maria.inventada@exemplo.com", "Travessa Sintética", "Maria Clara Inventada", "Clara"]) {
      assertEquals(html.includes(dado), false, dado);
    }
    assert(html.includes("Maria I."));
    assertEquals(buildPDFFilename({ ...dados, documentType: "quote" }, { ...DEFAULT_PDF_OPTIONS, ocultarDadosDoCliente: true }), "Orcamento_ORC-00086.pdf");
  } finally {
    t.restore();
  }
});
