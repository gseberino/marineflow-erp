// Pacote 1 do assistente, S6 (24/11/2026): o turno que leu texto de fora (conversa, e-mail, mensagem de fornecedor) e
// depois grava cadastro, contato, preço ou memória. Aqui ficam a regra pura e as três listas conferidas contra o
// catálogo; o executor (cartão, risk_reason, autonomia, o laço) está em agent-texto-de-fora_test.ts.
//
// O que se fixa:
//   · quando o turno conta como "leu": a lista de ferramentas do job, a ferramenta_extra, o pedido do vigia (🤖);
//   · o que não dá para conferir vale como "leu" (lista torta, job que não foi lido, lista perto do teto da RPC);
//   · a regra só sobe o risco, e sem leitura não muda nada;
//   · todo nome das três listas existe no catálogo, e as listas não se cruzam;
//   · o cartão das ferramentas que passam a poder pedir o sim sai em português (título e rótulo de cada campo);
//   · varredura das leituras: ferramenta que lê as tabelas ou os campos de mensagem está na lista ou numa exceção com motivo;
//   · varredura do telefone: ferramenta que grava e tem campo de telefone está em SOBEM_PARA_SIM ou numa exceção com motivo;
//   · o que a especificação proíbe subir continua fora.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/texto-de-fora_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type Acompanhamento, textoDoAviso } from "./acompanhar.ts";
import { campoTemRotulo, formatFieldValue, humanizeToolName, linhaDoPin, rotuloDoCampo, tituloDaAcao } from "./agent.ts";
import { NOME_DA_FERRAMENTA_EXTRA } from "./ferramenta-extra.ts";
import { podeGravar } from "./pedido-do-turno.ts";
import { allTools } from "./tools/index.ts";
import type { RiskLevel } from "./tools/registry.ts";
import {
  LEITURAS_DE_TEXTO_DE_FORA, leuTextoDeFora, leuTextoDeForaNoJob, LIMITE_DO_METADATA_NA_RPC, LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA,
  MARCA_DO_VIGIA, MOTIVO_DO_TEXTO_DE_FORA, nomeDaFerramentaUsada, riscoDepoisDeTextoDeFora, SOBEM_PARA_PIN, SOBEM_PARA_SIM,
  tamanhoComoOBancoMede, TETO_PARA_CONFIAR_NA_LISTA,
} from "./texto-de-fora.ts";

const porNome = new Map(allTools.map((t) => [t.name, t]));
const NIVEIS: RiskLevel[] = ["low", "medium", "high"];

// ─── O turno leu? ───────────────────────────────────────────────────────────────────────────────

Deno.test("S6 leu: a lista de ferramentas do job, na ordem em que rodaram", () => {
  assertEquals(leuTextoDeFora(["search_clients", "get_whatsapp_conversation", "update_client"]), true);
  assertEquals(leuTextoDeFora(["search_clients", "get_service_order", "update_client"]), false, "sem leitura de fora");
  assertEquals(leuTextoDeFora([]), false);
  // sem lista = nenhuma ferramenta usada ainda no turno
  assertEquals(leuTextoDeFora(undefined), false);
  assertEquals(leuTextoDeFora(null), false);
  // cada leitura da lista marca sozinha
  for (const nome of LEITURAS_DE_TEXTO_DE_FORA) assertEquals(leuTextoDeFora([nome]), true, nome);
  // a escrita não marca: quem marca é a leitura
  for (const nome of [...SOBEM_PARA_SIM, ...SOBEM_PARA_PIN]) assertEquals(leuTextoDeFora([nome]), false, nome);
});

Deno.test("S6 leu: pela ferramenta_extra conta a ferramenta chamada; só pedir a descrição não conta", () => {
  assertEquals(NOME_DA_FERRAMENTA_EXTRA, "ferramenta_extra", "é o prefixo que o erp-mcp grava (nomeReal)");
  assertEquals(nomeDaFerramentaUsada("ler_email"), "ler_email");
  assertEquals(nomeDaFerramentaUsada("ferramenta_extra:ler_email"), "ler_email");
  assertEquals(nomeDaFerramentaUsada("ferramenta_extra:descrever:ler_email"), null);
  assertEquals(leuTextoDeFora(["ferramenta_extra:ler_email"]), true);
  assertEquals(leuTextoDeFora(["ferramenta_extra:descrever:ler_email"]), false, "descrever não roda nada");
  assertEquals(leuTextoDeFora(["ferramenta_extra:descrever:ler_email", "ferramenta_extra:update_supplier"]), false);
  assertEquals(leuTextoDeFora(["ferramenta_extra:descrever:ler_email", "ferramenta_extra:ler_email"]), true);
  // a ferramenta_extra sem nome (o executor recusa) e um nome que não existe não leem nada
  assertEquals(leuTextoDeFora(["ferramenta_extra", "ferramenta_extra:nao_existe"]), false);
});

Deno.test("S6 leu: o pedido do vigia começa com 🤖 e já traz mensagem de terceiro citada", () => {
  assertEquals(MARCA_DO_VIGIA, "🤖");
  assertEquals(leuTextoDeFora(undefined, "🤖 Acompanhamento (pedido seu): João está esperando resposta."), true);
  assertEquals(leuTextoDeFora([], "  \n🤖 Lembrete que você pediu: responder João."), true, "espaço antes não esconde a marca");
  assertEquals(leuTextoDeFora([], "cadastra o fornecedor João 🤖"), false, "só no começo");
  assertEquals(leuTextoDeFora([], "cadastra o fornecedor João"), false);
  assertEquals(leuTextoDeFora([], undefined), false);
  assertEquals(leuTextoDeFora([], 42), false, "texto que não é texto não marca");
  // Os três pedidos de verdade do vigia (acompanhar.ts): se a marca de lá mudar, este teste acusa.
  const base: Acompanhamento = {
    id: "a1", phone_normalized: "5547999990000", contato: "João", modo: "acompanhar", intervalo_min: 120, ate: "2030-01-02T12:00:00Z",
    lembrar_em: "2030-01-01T12:00:00Z", promessa: "te mando o orçamento amanhã", ultimo_aviso_em: null, avisos_dia: null, avisos_no_dia: 0,
    created_at: "2030-01-01T09:00:00Z",
  };
  const conversa = { ultimaRecebida: { em: "2030-01-01T10:00:00Z", texto: "e o orçamento?" }, ultimaEnviadaEm: null };
  for (const modo of ["acompanhar", "lembrar_em", "promessa"] as const) {
    const pedido = textoDoAviso({ ...base, modo }, conversa, new Date("2030-01-01T12:00:00Z"), "(47) 99999-0000");
    assert(pedido.startsWith(MARCA_DO_VIGIA), modo);
    assertEquals(leuTextoDeFora(undefined, pedido), true, modo);
  }
});

Deno.test("S6 leu: o que não dá para conferir vale como leu (lado seguro)", () => {
  assertEquals(leuTextoDeFora("get_whatsapp_conversation"), true, "lista que não é lista");
  assertEquals(leuTextoDeFora({ 0: "search_clients" }), true);
  assertEquals(leuTextoDeFora(0), true);
  assertEquals(leuTextoDeFora(["search_clients", 7]), true, "entrada que não é texto");
  assertEquals(leuTextoDeFora(["search_clients", null]), true);
});

Deno.test("S6 leu (Claude Max): a marca sai da linha do job relida; job que não foi lido vale como leu", () => {
  const job = (ferramentas?: unknown) => ({ metadata: { tipo: "agente_whatsapp", session_id: "s1", ...(ferramentas === undefined ? {} : { ferramentas_usadas: ferramentas }) } });
  assertEquals(leuTextoDeForaNoJob(job(), false, "cadastra o fornecedor João"), false, "primeira chamada do turno: nada lido");
  assertEquals(leuTextoDeForaNoJob(job(["search_suppliers"]), false, "cadastra o fornecedor João"), false);
  assertEquals(leuTextoDeForaNoJob(job(["listar_emails", "ler_email"]), false, "cadastra o fornecedor do e-mail"), true);
  assertEquals(leuTextoDeForaNoJob(job(["ferramenta_extra:get_open_loops"]), false, "x"), true);
  assertEquals(leuTextoDeForaNoJob(job([]), false, "🤖 Acompanhamento (pedido seu): João está esperando resposta."), true, "o turno do vigia");
  // não deu para conferir
  assertEquals(leuTextoDeForaNoJob(job([]), true, "x"), true, "a leitura do job falhou");
  assertEquals(leuTextoDeForaNoJob(null, false, "x"), true, "a linha do job não veio");
  assertEquals(leuTextoDeForaNoJob(undefined, false, "x"), true);
  assertEquals(leuTextoDeForaNoJob({ metadata: null }, false, "x"), true, "sem metadata");
  assertEquals(leuTextoDeForaNoJob({ metadata: "texto" }, false, "x"), true);
  assertEquals(leuTextoDeForaNoJob({ metadata: [] }, false, "x"), true);
  assertEquals(leuTextoDeForaNoJob(job("torta"), false, "x"), true, "lista torta");
  // nunca lança: metadata que explode ao ser lido vale como leu
  const hostil = new Proxy({}, { ownKeys() { throw new Error("explode"); }, get() { throw new Error("explode"); } });
  assertEquals(leuTextoDeForaNoJob({ metadata: hostil }, false, "x"), true);
});

Deno.test("S6 leu (Claude Max): o tamanho do metadata é medido como o banco mede", () => {
  // Medido no Postgres em 25/11/2026 com este mesmo valor (octet_length(valor::text) = 209; "ação" tem 2 letras de 2 bytes).
  const valor = {
    b: [1, 2, "x:y, z"], c: { d: null, e: "ação" }, f: [], g: {}, h: true, tipo: "agente_whatsapp", versao: 1,
    ferramentas_usadas: ["ler_email", "ferramenta_extra:update_client", "my_agenda"],
  };
  const comoOBancoEscreve = '{"b": [1, 2, "x:y, z"], "c": {"d": null, "e": "ação"}, "f": [], "g": {}, "h": true, "tipo": "agente_whatsapp", "versao": 1, ' +
    '"ferramentas_usadas": ["ler_email", "ferramenta_extra:update_client", "my_agenda"]}';
  assertEquals(new TextEncoder().encode(comoOBancoEscreve).length, 209);
  assertEquals(tamanhoComoOBancoMede(valor), 209);
  assertEquals(tamanhoComoOBancoMede({}), 2);
  assertEquals(tamanhoComoOBancoMede([]), 2);
  assertEquals(tamanhoComoOBancoMede({ a: undefined }), 2, "chave sem valor não existe no JSON");
  assertEquals(tamanhoComoOBancoMede(null), 4);
});

Deno.test("S6 leu (Claude Max): perto do teto em que a RPC para de acrescentar nomes, a lista não é prova de nada", () => {
  assertEquals(LIMITE_DO_METADATA_NA_RPC, 18_000, "o limite de ai_job_registrar_ferramenta (20261003235000)");
  // A folga cobre com sobra o maior nome que a RPC acrescenta: 80 bytes do nome, as aspas, a vírgula e o espaço.
  assert(LIMITE_DO_METADATA_NA_RPC - TETO_PARA_CONFIAR_NA_LISTA >= 10 * 84);
  // A mesma regra da RPC, simulada: acrescenta o nome só se o metadata, com ele, couber no limite.
  const metadata: { tipo: string; mcp_token_sha256: string; ferramentas_usadas: string[] } = {
    tipo: "agente_whatsapp", mcp_token_sha256: "0".repeat(64), ferramentas_usadas: [],
  };
  const acrescenta = (nome: string): boolean => {
    const novo = { ...metadata, ferramentas_usadas: [...metadata.ferramentas_usadas, nome.slice(0, 80)] };
    if (tamanhoComoOBancoMede(novo) > LIMITE_DO_METADATA_NA_RPC) return false;
    metadata.ferramentas_usadas = novo.ferramentas_usadas;
    return true;
  };
  // Um turno enorme só de consultas que não leem texto de fora, com a ferramenta de nome mais curto do catálogo.
  const neutra = [...porNome.keys()].filter((n) => !LEITURAS_DE_TEXTO_DE_FORA.has(n)).sort((a, b) => a.length - b.length)[0];
  // Até uns 16.000 bytes de uma vez (cada nome ocupa o nome, as aspas, a vírgula e o espaço): a lista ainda vale pelo que diz.
  metadata.ferramentas_usadas = Array.from({ length: Math.floor(16_000 / (neutra.length + 4)) }, () => neutra);
  assert(tamanhoComoOBancoMede(metadata) < TETO_PARA_CONFIAR_NA_LISTA);
  assertEquals(leuTextoDeForaNoJob({ metadata }, false, "x"), false, "abaixo do teto, mil consultas neutras não marcam o turno");
  // Daí em diante, chamada a chamada, até a RPC deixar de acrescentar.
  let marcouAntesDeCortar = false;
  while (acrescenta(neutra)) marcouAntesDeCortar = leuTextoDeForaNoJob({ metadata }, false, "x");
  const chamadas = metadata.ferramentas_usadas.length;
  assert(chamadas > 500, `o teto só é alcançado num turno com centenas de chamadas (${chamadas})`);
  assertEquals(marcouAntesDeCortar, true, "quando o primeiro nome deixa de caber, o turno já vale como leu");
  // A leitura que não coube na lista não desmarca o turno.
  assertEquals(acrescenta("get_whatsapp_conversation"), false);
  assertEquals(leuTextoDeForaNoJob({ metadata }, false, "x"), true);
  // E longe do teto a lista vale pelo que diz (o maior metadata em 90 dias teve 2.396 bytes).
  const pequeno = { ...metadata, ferramentas_usadas: Array.from({ length: 60 }, () => neutra) };
  assert(tamanhoComoOBancoMede(pequeno) < 2_500);
  assertEquals(leuTextoDeForaNoJob({ metadata: pequeno }, false, "x"), false);
});

// ─── A regra ────────────────────────────────────────────────────────────────────────────────────

Deno.test("S6 regra: sem leitura de fora, nenhum risco muda e não há motivo", () => {
  for (const nome of [...SOBEM_PARA_SIM, ...SOBEM_PARA_PIN, ...LEITURAS_DE_TEXTO_DE_FORA, "add_service_order_item", "nao_existe"]) {
    for (const risco of NIVEIS) assertEquals(riscoDepoisDeTextoDeFora(nome, risco, false), { risco, motivo: null }, `${nome} ${risco}`);
  }
  // a marca tem de ser exatamente true: valor torto não liga a regra sozinho, e quem chama já compara com true
  assertEquals(riscoDepoisDeTextoDeFora("create_supplier", "low", undefined as unknown as boolean), { risco: "low", motivo: null });
});

Deno.test("S6 regra: cadastro, contato e preço sobem para o sim; a memória sobe para o PIN; nunca rebaixa", () => {
  for (const nome of SOBEM_PARA_SIM) {
    assertEquals(riscoDepoisDeTextoDeFora(nome, "low", true), { risco: "medium", motivo: MOTIVO_DO_TEXTO_DE_FORA }, nome);
    // já pedia o sim ou o PIN: fica no nível dela e leva o motivo (é ele que trava a autonomia)
    assertEquals(riscoDepoisDeTextoDeFora(nome, "medium", true), { risco: "medium", motivo: MOTIVO_DO_TEXTO_DE_FORA }, nome);
    assertEquals(riscoDepoisDeTextoDeFora(nome, "high", true), { risco: "high", motivo: MOTIVO_DO_TEXTO_DE_FORA }, nome);
  }
  for (const nome of SOBEM_PARA_PIN) {
    for (const risco of NIVEIS) assertEquals(riscoDepoisDeTextoDeFora(nome, risco, true), { risco: "high", motivo: MOTIVO_DO_TEXTO_DE_FORA }, `${nome} ${risco}`);
  }
  // fora das duas listas, a leitura não muda nada
  for (const nome of ["add_service_order_item", "create_quote_from_items", "send_whatsapp_message", "get_whatsapp_conversation", "nao_existe"]) {
    for (const risco of NIVEIS) assertEquals(riscoDepoisDeTextoDeFora(nome, risco, true), { risco, motivo: null }, `${nome} ${risco}`);
  }
  // nível que não existe não dá para comparar: o mais alto
  assertEquals(riscoDepoisDeTextoDeFora("create_supplier", "altíssimo" as unknown as RiskLevel, true).risco, "high");
});

Deno.test("S6 regra: as duas linhas que o dono lê", () => {
  assertEquals(LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA, "Este turno leu texto de fora (conversa, e-mail ou mensagem de fornecedor): por isso pede *sim*.");
  // a do PIN segue o formato que vale no WhatsApp e no chat do app (linhaDoPin, do S1)
  assertEquals(linhaDoPin([MOTIVO_DO_TEXTO_DE_FORA]), "🔒 No WhatsApp, pede PIN: este turno leu texto de fora (conversa, e-mail ou mensagem de fornecedor).");
});

// ─── As listas contra o catálogo ────────────────────────────────────────────────────────────────

Deno.test("S6 listas: todo nome existe no catálogo, e as listas não se cruzam", () => {
  const faltam: string[] = [];
  for (const [lista, nomes] of [["leituras", LEITURAS_DE_TEXTO_DE_FORA], ["sim", SOBEM_PARA_SIM], ["PIN", SOBEM_PARA_PIN]] as const) {
    for (const n of nomes) if (!porNome.has(n)) faltam.push(`${lista}: ${n}`);
  }
  assertEquals(faltam, [], "nome que não existe em allTools");
  assertEquals([...SOBEM_PARA_SIM].filter((n) => SOBEM_PARA_PIN.has(n)), [], "a mesma ferramenta nas duas escritas");
  assertEquals([...LEITURAS_DE_TEXTO_DE_FORA].filter((n) => SOBEM_PARA_SIM.has(n) || SOBEM_PARA_PIN.has(n)), [], "leitura que também sobe");
});

Deno.test("S6 listas: toda leitura da lista roda direto (risco baixo, sem cálculo por argumento nem pelo servidor)", () => {
  // Se uma delas passasse a pedir o sim, não leria nada no turno, e a marca do laço (que é ligada depois de rodar) nunca viria.
  const problemas = [...LEITURAS_DE_TEXTO_DE_FORA].filter((n) => {
    const t = porNome.get(n)!;
    return t.risk !== "low" || !!t.computeRisk || !!t.riscoNoServidor;
  });
  assertEquals(problemas, []);
});

Deno.test("S6 listas: o que a especificação manda NÃO subir continua fora das duas escritas", () => {
  // Montar orçamento a partir da conversa ("lê e monta") não pode virar uma fila de cartões; a mensagem a fornecedor
  // segue a regra do S1 (envio-livre.ts), não esta.
  const fora = [
    "add_service_order_item", "create_quote_from_items", "record_quote_response", "create_service_order",
    "send_whatsapp_message", "schedule_whatsapp_message", "send_supplier_quote_request",
  ];
  for (const n of fora) {
    assert(porNome.has(n), `${n} saiu do catálogo: reveja esta lista`);
    assertEquals(SOBEM_PARA_SIM.has(n) || SOBEM_PARA_PIN.has(n), false, n);
  }
});

Deno.test("S6 cartão: toda ferramenta das duas listas tem título e todos os campos com rótulo em português", () => {
  // Várias rodavam direto, à vista do admin, e nunca tinham virado cartão: fornecedor, embarcação ou veículo, produto e a
  // observação sobre um cadastro. Sem rótulo, o cartão sairia "- Cost Price: 80", "- Hull Id Or Registration: …", "- Body: …".
  const problemas: string[] = [];
  for (const nome of [...SOBEM_PARA_SIM, ...SOBEM_PARA_PIN]) {
    if (tituloDaAcao(nome) === humanizeToolName(nome)) problemas.push(`${nome}: sem título`);
    const campos = Object.keys((porNome.get(nome)!.input_schema as { properties?: Record<string, unknown> }).properties ?? {});
    for (const campo of campos) if (!campoTemRotulo(campo)) problemas.push(`${nome}.${campo}: sem rótulo (ponha em ROTULOS_DOS_CAMPOS, rotulos.ts)`);
  }
  assertEquals(problemas, []);
  // O que o dono lê nos campos que ganharam rótulo com o S6 (o Intl separa "R$" do número com espaço fixo).
  const linha = (campo: string, valor: unknown) => `- ${rotuloDoCampo(campo)}: ${formatFieldValue(campo, valor)}`.replace(/ /g, " ");
  assertEquals(linha("cost_price", 80), "- Preço de custo: R$ 80,00");
  assertEquals(linha("hull_id_or_registration", "ABC1D23"), "- Registro, chassi ou placa: ABC1D23");
  assertEquals(linha("scope", "client"), "- Sobre: cliente");
  assertEquals(linha("scope", "vessel"), "- Sobre: embarcação ou veículo");
  assertEquals(linha("body", "Prefere atendimento à tarde."), "- Observação: Prefere atendimento à tarde.");
  assertEquals(linha("from_user", true), "- Dito por você: sim");
});

// ─── Varredura das leituras ─────────────────────────────────────────────────────────────────────
// Toda ferramenta cujo execute cita uma FONTE de texto de terceiro (as tabelas de mensagem e de e-mail, e as RPCs e a
// view que as devolvem) ou um CAMPO que guarda a frase original tem de estar em LEITURAS_DE_TEXTO_DE_FORA, ou aqui, com
// o motivo. O que a varredura não vê: a ferramenta que lê por função auxiliar (o execute só chama a função). Essas
// entram na lista à mão: retorno_ler_caso, read_supplier_media, list_agenda_suggestions, dismiss_agenda_suggestions.

const FONTES = /whatsapp_messages|email_messages|whatsapp_pending_inbox|unidentified_contacts|get_entity_open_loops|retorno_ver_caso_para_modelo/;
const CAMPOS_DA_FRASE = /body_text|last_body|ultima_frase|\bevidence\b|source_excerpt/;
/** Coluna de texto de mensagem ou de e-mail: uma exceção que cita a fonte não pode passar a ler nenhuma delas. */
const TEXTO_DA_MENSAGEM = /\bbody\b|body_text|last_body|ultima_frase|\bsubject\b/;

const NAO_DEVOLVEM_TEXTO_DE_FORA: Record<string, string> = {
  attach_photo_to_service_order: "lê só o tipo e o arquivo da mensagem, para copiar a foto para a OS; não devolve texto",
  get_situation_overview: "da caixa de entrada devolve só o contato e há quanto tempo espera; a prévia da mensagem não sai",
  identify_contact: "lê só a quem as mensagens do número estão ligadas (client_id, supplier_id); devolve nomes do cadastro",
  link_contact_identity: "só grava o vínculo nas mensagens do número; não lê o texto (está em SOBEM_PARA_SIM)",
  link_contact_to_entity: "lê o número da mensagem e grava o vínculo; não lê o texto (está em SOBEM_PARA_SIM)",
  link_whatsapp_lead_to_client: "só grava o cliente nas mensagens do número; não lê o texto (está em SOBEM_PARA_SIM)",
  list_routines: "evidence aqui é a anotação que o próprio assistente gravou com a rotina, não frase de mensagem",
  record_routine: "grava a anotação da rotina que o modelo passou; não devolve texto lido (está em SOBEM_PARA_PIN)",
  record_quote_response: "grava o trecho que o modelo passou; não devolve texto lido (e não sobe: é o \"lê e registra\" da cotação)",
};

Deno.test("S6 varredura das leituras: quem lê fonte ou campo de mensagem está na lista ou numa exceção com motivo", () => {
  const semDono: string[] = [];
  const apontadas = new Set<string>();
  for (const t of allTools) {
    const fonte = t.execute.toString();
    if (!FONTES.test(fonte) && !CAMPOS_DA_FRASE.test(fonte)) continue;
    apontadas.add(t.name);
    if (!LEITURAS_DE_TEXTO_DE_FORA.has(t.name) && !(t.name in NAO_DEVOLVEM_TEXTO_DE_FORA)) semDono.push(t.name);
  }
  assertEquals(semDono, [], "ferramenta nova que lê mensagem ou e-mail: ponha em LEITURAS_DE_TEXTO_DE_FORA (texto-de-fora.ts) ou, se não devolve o texto, na exceção com o motivo");
  // A varredura está viva: acha as leituras diretas que a especificação conferiu.
  for (const n of ["get_whatsapp_conversation", "ler_email", "listar_emails", "read_supplier_messages", "get_client_360", "get_supplier_360"]) {
    assert(apontadas.has(n), `a varredura deixou de enxergar ${n}`);
  }
});

Deno.test("S6 varredura das leituras: a lista de exceções não sobra, não cruza com a de leituras e não lê texto de mensagem", () => {
  const problemas: string[] = [];
  for (const [nome, motivo] of Object.entries(NAO_DEVOLVEM_TEXTO_DE_FORA)) {
    const t = porNome.get(nome);
    if (!t) { problemas.push(`${nome}: não existe`); continue; }
    if (!motivo.trim()) problemas.push(`${nome}: sem motivo`);
    if (LEITURAS_DE_TEXTO_DE_FORA.has(nome)) problemas.push(`${nome}: está na lista de leituras e na de exceções`);
    const fonte = t.execute.toString();
    if (!FONTES.test(fonte) && !CAMPOS_DA_FRASE.test(fonte)) problemas.push(`${nome}: a varredura não aponta mais (tire da exceção)`);
    if (FONTES.test(fonte) && TEXTO_DA_MENSAGEM.test(fonte)) problemas.push(`${nome}: passou a ler coluna de texto de mensagem`);
  }
  assertEquals(problemas, []);
});

// ─── Varredura do telefone ──────────────────────────────────────────────────────────────────────
// A raiz do achado NOVO-p1-s1-04: gravar um número num cadastro muda o que a mensagem livre pede depois (fornecedor e
// equipe, só o "sim"). Toda ferramenta que GRAVA e aceita um telefone nos argumentos tem de estar em SOBEM_PARA_SIM, ou
// aqui, com o motivo.

const CAMPO_DE_TELEFONE = /^(phone|telefone|whatsapp|to_phone|celular|fone)$/i;

const TELEFONE_QUE_NAO_E_CADASTRO: Record<string, string> = {
  send_whatsapp_message: "mensagem para fora: quem decide o sim e o PIN é o S1 (envio-livre.ts), pelo número que recebe e pelo texto",
  schedule_whatsapp_message: "idem, no agendamento; nunca roda sozinha",
  acompanhar_conversa: "liga o acompanhamento de uma conversa: o aviso vai só ao dono, e nenhum cadastro recebe o número",
  parar_acompanhamento: "encerra o acompanhamento; não grava número",
};

Deno.test("S6 varredura do telefone: quem grava e aceita telefone nos argumentos pede o sim depois de texto de fora", () => {
  const semDono: string[] = [];
  const apontadas = new Set<string>();
  for (const t of allTools) {
    const campos = Object.keys((t.input_schema as { properties?: Record<string, unknown> }).properties ?? {});
    if (!campos.some((c) => CAMPO_DE_TELEFONE.test(c)) || !podeGravar(t.name)) continue;
    apontadas.add(t.name);
    if (!SOBEM_PARA_SIM.has(t.name) && !(t.name in TELEFONE_QUE_NAO_E_CADASTRO)) semDono.push(t.name);
  }
  assertEquals(semDono, [], "ferramenta nova que grava telefone: ponha em SOBEM_PARA_SIM (texto-de-fora.ts) ou na exceção com o motivo");
  for (const [nome, motivo] of Object.entries(TELEFONE_QUE_NAO_E_CADASTRO)) {
    assert(apontadas.has(nome), `${nome}: a varredura não aponta mais (tire da exceção)`);
    assert(motivo.trim() !== "" && !SOBEM_PARA_SIM.has(nome), nome);
  }
});

Deno.test("S6 telefone em cadastro (NOVO-p1-s1-04): as escritas que gravam número em cliente, fornecedor, equipe e contato estão na lista", () => {
  const gravamNumero = [
    // as três da raiz do achado: rodavam direto e trocavam o PIN da mensagem livre pelo sim
    "create_supplier", "update_supplier", "link_contact_to_entity",
    // as outras que gravam número num cadastro ou num contato
    "link_contact_identity", "link_whatsapp_lead_to_client", "create_client", "update_client", "add_vessel_contact", "update_vessel_contact",
    "create_marina", "update_marina", "alterar_favorecido", "cadastrar_freelancer", "mute_contact", "criar_cobranca", "alterar_cobranca",
    "criar_missao_acompanhamento",
  ];
  assertEquals(gravamNumero.filter((n) => !SOBEM_PARA_SIM.has(n)), []);
  // As três da raiz declaram risco baixo: sem o S6 rodam direto (é o que continua aberto fora do turno que leu texto de fora).
  for (const n of ["create_supplier", "update_supplier", "link_contact_to_entity"]) assertEquals(porNome.get(n)!.risk, "low", n);
});
