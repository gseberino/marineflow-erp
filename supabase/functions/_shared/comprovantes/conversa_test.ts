// Os textos fixos da conversa (seção 3.3 da spec): cabeçalho, passos, resumo, gravação, pendentes,
// cartão, cancelamento e o par do histórico. Os exemplos da spec são conferidos ao pé da letra.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cabecalho,
  caminhoLegivel,
  type CmpResumo,
  frasesDoPlano,
  historicoDoFluxo,
  MAX_MENSAGEM,
  type PerguntaDoBanco,
  prefixoDaPergunta,
  textoDaGravacao,
  textoDaPergunta,
  textoDoCancelamento,
  textoDoCartao,
  textoDoResumo,
  textoDosPendentes,
  textoFeito,
  textoInvalida,
  textoLote,
  textoNaoGravado,
  textoOcupado,
  textoOkNaoAprova,
  textoSair,
  TEXTO_CORRIGIR_COMO,
  textoCorrigido,
  textoDica,
  textoNaFila,
  textoNaoEntendi,
  textoQualCmp,
  textoRetomadaInterrompida,
} from "./conversa.ts";

const OS = { id: "os-1", numero: "OS-00112", barco: "Brisa", cliente: "João", status: "in_progress", faturada: false, assinada: false, pasta_registrada: true };

function cmp(extra: Partial<CmpResumo> = {}): CmpResumo {
  return {
    id: "c-1", codigo: "CMP-00124", numero: 124, situacao: "perguntando", tipo: "nfce", valor: "62.00", valor_lido: "62.00",
    valor_confianca: "alta", data: "2026-10-10", hora: "12:57:56", forma: "debito", fornecedor: "Auto Posto Exemplo",
    fornecedor_origem: "cadastro", cnpj: "11222333000181", cnpj_confianca: "alta", destino: "os", os: OS, cobrar_cliente: null,
    quem_pagou: null, pagador_nome: null, categoria: null, pendencias: [], gravado_em: null, ...extra,
  };
}

function pergunta(passo: string, extra: Partial<PerguntaDoBanco> = {}, c: Partial<CmpResumo> = {}): PerguntaDoBanco {
  return {
    pergunta_id: "p-1", dedupe_key: "cmp:p:p-1", cmp: cmp(c), passo, opcoes: [], posicao: 1, total: 4, primeira_do_lote: null,
    retomada: false, avisos: [], plano: null, versao: null, pasta: null, ...extra,
  };
}

// ─── cabeçalho ────────────────────────────────────────────────────────────────────────────

Deno.test("cabeçalho: o exemplo da spec, posição só com fila, fornecedor da Receita ou CNPJ, valor (confira)", () => {
  assertEquals(cabecalho(pergunta("cobrar")), "CMP-00124 (1 de 4) · cupom NFC-e · Auto Posto Exemplo · 10/10 · R$ 62,00");
  assertEquals(cabecalho(pergunta("cobrar", { total: 1 })), "CMP-00124 · cupom NFC-e · Auto Posto Exemplo · 10/10 · R$ 62,00");
  assertEquals(cabecalho(pergunta("cobrar", {}, { fornecedor_origem: "receita", fornecedor: "POSTO LTDA" })).split(" · ")[2], "POSTO LTDA (Receita)");
  assertEquals(cabecalho(pergunta("cobrar", {}, { fornecedor: null, fornecedor_origem: null })).split(" · ")[2], "CNPJ 11.222.333/0001-81");
  const semNada = cabecalho(pergunta("valor", { total: 1 }, { fornecedor: null, cnpj: null, valor: null, valor_lido: null, data: null, tipo: "pix" }));
  assertEquals(semNada, "CMP-00124 · comprovante de Pix");
  // selo média, ainda não confirmado: "(confira)"; selo baixa (o banco não copia): "(confira)"
  assertStringIncludes(cabecalho(pergunta("para_que", {}, { valor_confianca: "media" })), "R$ 62,00 (confira)");
  assertStringIncludes(cabecalho(pergunta("valor", {}, { valor: null, valor_confianca: "baixa" })), "R$ 62,00 (confira)");
  // o dono confirmou (selo baixa + valor preenchido = veio dele): sem "(confira)"
  assert(!cabecalho(pergunta("para_que", {}, { valor_confianca: "baixa", valor: "61.50" })).includes("confira"));
  // CPF (11 dígitos) nunca aparece
  assert(!cabecalho(pergunta("valor", {}, { fornecedor: null, cnpj: "12345678901" })).includes("123"));
});

// ─── passos ───────────────────────────────────────────────────────────────────────────────

Deno.test("passos: os textos fixos da tabela 3.3", () => {
  const cab = "CMP-00124 (1 de 4) · cupom NFC-e · Auto Posto Exemplo · 10/10 · R$ 62,00";
  assertEquals(textoDaPergunta(pergunta("valor", {}, { valor: null, valor_lido: null })).split("\n")[1], "Qual o valor? Responda só o número (ex.: 62,50).");
  assertEquals(
    textoDaPergunta(pergunta("valor", {}, { valor: null, valor_confianca: "baixa" })).split("\n")[1],
    "Li R$ 62,00, mas sem certeza. Responda *sim* se está certo, ou o valor certo (ex.: 62,50).",
  );
  const paraQue = textoDaPergunta(pergunta("para_que", {
    opcoes: [{ n: 1, rotulo: "OS-00112 · Brisa", valor: "os:1" }, { n: 2, rotulo: "Estoque", valor: "estoque" }, { n: 3, rotulo: "Empresa (sem OS)", valor: "empresa" }],
  }));
  assertEquals(paraQue, `${cab}\nPara quê?\n1 OS-00112 · Brisa\n2 Estoque\n3 Empresa (sem OS)\nResponda o número, o nome do barco ou *os N*.`);
  assertEquals(textoDaPergunta(pergunta("qual_os")), `${cab}\nQual OS? Responda *os N* ou o nome do barco.`);
  assertEquals(textoDaPergunta(pergunta("como_pagou")), `${cab}\nComo foi pago?\n1 Pix\n2 Débito\n3 Crédito\n4 Dinheiro\n5 Boleto\n6 Transferência`);
  assertEquals(
    textoDaPergunta(pergunta("quem_pagou")),
    `${cab}\nQuem pagou?\n1 A empresa (dinheiro do Caixa)\n2 Eu, do meu bolso (fica como reembolso para você)\n3 Um técnico\n4 O cliente pagou direto`,
  );
  assertEquals(textoDaPergunta(pergunta("data")), `${cab}\nQual a data da compra? (ex.: 10/10)`);
  assertStringIncludes(textoDaPergunta(pergunta("categoria")), "Qual a categoria?\n1 Combustível e deslocamento\n2 Alimentação de campo");
  assertStringIncludes(textoDaPergunta(pergunta("categoria")), "8 Outras despesas\nOu escreva o nome da categoria.");
  assertStringIncludes(
    textoDaPergunta(pergunta("corrigir")),
    "CMP-00124: o que corrigir?\n1 Valor\n2 Data\n3 Para quê\n4 Como foi pago\n5 Quem pagou\n6 Cobrar ou não\n7 Categoria\n8 Cancelar este comprovante\n9 Deixar para depois",
  );
  assertEquals(
    textoDaPergunta(pergunta("qual_tecnico", { opcoes: [{ n: 1, rotulo: "Roberto", valor: "payee:1" }, { n: 2, rotulo: "Felipe", valor: "payee:2" }] })),
    `${cab}\nQual técnico pagou?\n1 Roberto\n2 Felipe\nOu escreva o nome.`,
  );
});

Deno.test("passo cobrar: OS aberta, assinada e já faturada (o número vem das opções do banco)", () => {
  const opcoes = [{ n: 1, rotulo: "x", valor: "cobrar" }, { n: 2, rotulo: "y", valor: "custo" }];
  assertStringIncludes(
    textoDaPergunta(pergunta("cobrar", { opcoes })),
    "Para a OS-00112 · Brisa. Cobrar do cliente?\n1 Cobrar do cliente (entra no total da OS)\n2 Custo da HBR (não entra no total)",
  );
  assertStringIncludes(
    textoDaPergunta(pergunta("cobrar", { opcoes }, { os: { ...OS, assinada: true } })),
    "1 Cobrar do cliente (muda o total e a OS vai pedir nova assinatura)",
  );
  assertStringIncludes(
    textoDaPergunta(pergunta("cobrar", { opcoes }, { os: { ...OS, status: "invoiced", faturada: true } })),
    "A OS-00112 já está faturada: o total dela não muda. Cobrar do cliente à parte ou é custo da HBR?\n1 Cobrar à parte (fica a lembrança de cobrar)\n2 Custo da HBR",
  );
});

Deno.test("prefixos: primeira do lote (4 e 1), retomada do vigia", () => {
  assertEquals(
    prefixoDaPergunta(pergunta("para_que", { primeira_do_lote: { n: 4, codigos: ["CMP-00123", "CMP-00124", "CMP-00125", "CMP-00126"] } }), "abertura"),
    "Recebi 4 comprovantes: CMP-00123 a CMP-00126. Vou perguntar um de cada vez (para parar: *sair*).",
  );
  assertEquals(prefixoDaPergunta(pergunta("para_que", { primeira_do_lote: { n: 1, codigos: ["CMP-00123"] } }), "abertura"), "Recebi o comprovante CMP-00123.");
  assertEquals(prefixoDaPergunta(pergunta("para_que", { retomada: true }), "vigia"), "Ainda falta conferir o CMP-00124.");
  assertEquals(prefixoDaPergunta(pergunta("para_que", { retomada: true }), "pular"), null);
  assertEquals(textoDaPergunta(pergunta("data"), "Ainda falta conferir o CMP-00124.").split("\n")[0], "Ainda falta conferir o CMP-00124.");
});

// ─── resumo ───────────────────────────────────────────────────────────────────────────────

const PLANO_A = {
  efeitos: [
    { tipo: "despesa_os", os_id: "os-1", os_numero: "OS-00112", billable: false, cobrar_a_parte: false, direto: false, paid_by: "company", categoria: "Peças e materiais" },
    { tipo: "anotar", forma: "debito", categoria: "Peças e materiais", documento: true },
  ],
  avisos: [],
  situacao_final: "gravado",
  pasta: "barco",
};

Deno.test("resumo: o exemplo da spec, linha por linha", () => {
  const p = pergunta("confirmar", { plano: PLANO_A, versao: 7, pasta: "Brisa/1- DOC's/Compras" }, { cobrar_cliente: false, situacao: "aguardando_sim" });
  assertEquals(
    textoDoResumo(p),
    [
      "CMP-00124 · confira antes de gravar:",
      "• R$ 62,00 em 10/10 às 12h57 · Auto Posto Exemplo",
      "• Para: OS-00112 Brisa · custo da HBR (não entra no total)",
      "• Pago: débito, pela empresa (se não foi a empresa: *corrigir quem*)",
      "Vou: lançar a despesa na OS-00112 como custo da HBR (o total não muda); anotar o débito para quando o banco trouxer (se já trouxe, classifico a linha).",
      "Arquivo: Brisa/1- DOC's/Compras.",
      "Responda *sim* para gravar ou *não* para corrigir.",
    ].join("\n"),
  );
  assertEquals(textoDaPergunta(p), textoDoResumo(p), "no confirmar a pergunta é o resumo");
});

Deno.test("resumo: avisos (faturada, assinada, duplicado) e os desconhecidos ficam fora", () => {
  const p = pergunta("confirmar", {
    plano: { ...PLANO_A, avisos: ["os_assinada_pede_nova_assinatura", "duplicado_ambiguo", "categoria_inativa"] },
    avisos: ["os_faturada_total_nao_muda", "valor_incerto"],
  });
  const t = textoDoResumo(p);
  assertStringIncludes(t, "A OS-00112 já está faturada: o total não muda.");
  assertStringIncludes(t, "A OS-00112 foi assinada pelo cliente: incluir no total pede nova assinatura.");
  assertStringIncludes(t, "Há mais de um lançamento igual já feito: não lanço; fica para classificar no Extrato.");
  assert(!t.includes("categoria_inativa") && !t.includes("valor_incerto"));
});

Deno.test("frasesDoPlano: uma frase por efeito da 3.3", () => {
  const c = cmp({ pagador_nome: "Roberto" });
  const f = (efeitos: Array<Record<string, unknown>>) => frasesDoPlano({ efeitos: efeitos as Array<{ tipo: string }> }, c);
  assertEquals(f([{ tipo: "despesa_os", os_numero: "OS-00112", billable: true }]), ["lançar a despesa na OS-00112, cobrada do cliente (o total da OS sobe R$ 62,00)"]);
  assertEquals(f([{ tipo: "despesa_os", os_numero: "OS-00112", billable: false, cobrar_a_parte: true }]), ['lançar a despesa na OS-00112 marcada "cobrar à parte" (o total não muda)']);
  assertEquals(f([{ tipo: "despesa_os", os_numero: "OS-00112", billable: false, paid_by: "technician" }]), ["lançar a despesa na OS-00112 como custo da HBR (o total não muda), paga pelo Roberto"]);
  assertEquals(f([{ tipo: "anexar_despesa", os_numero: "OS-00112", valor: "62.00", data: "2026-10-10" }]), ["usar a despesa que já está na OS-00112 (R$ 62,00, 10/10) — não lanço de novo"]);
  assertEquals(f([{ tipo: "itens_da_nota", nfe_numero: "12345", os_numero: "OS-00112", itens: 3 }]), ["ligar os 3 itens da nota 12345 à OS-00112"]);
  assertEquals(f([{ tipo: "aguardar_nota", os_id: null }]), ["esperar a nota (XML) entrar no sistema para ligar os itens"]);
  assertEquals(f([{ tipo: "anotar", forma: "pix" }]), ["anotar o Pix para quando o banco trouxer (se já trouxe, classifico a linha)"]);
  assertEquals(f([{ tipo: "anotar", forma: "transferencia" }])[0].startsWith("anotar a transferência"), true);
  assertEquals(f([{ tipo: "anexar_anotacao", valor: "62.00", data: "2026-10-10" }]), ["usar a anotação que já espera o banco (R$ 62,00, 10/10)"]);
  assertEquals(f([{ tipo: "caixa" }]), ["lançar a saída de R$ 62,00 no Caixa"]);
  assertEquals(f([{ tipo: "reembolso_socio", socio_nome: "Gustavo" }]), ["lançar R$ 62,00 como reembolso a você (Gustavo)"]);
  assertEquals(f([{ tipo: "anexar_lancamento", conta: "NUBANK", valor: "62.00", data: "2026-10-10" }]), ["usar o lançamento que já existe (NUBANK, R$ 62,00, 10/10) — não lanço de novo"]);
  assertEquals(f([{ tipo: "aguardar_fatura" }]), ["nada no financeiro agora: a compra no crédito entra pela fatura"]);
  assertEquals(f([{ tipo: "nada", motivo: "pessoal" }]), ["só guardar o arquivo em PESSOAL (nada no financeiro)"]);
  assertEquals(f([{ tipo: "nada", motivo: "cliente_pagou" }]), ["nada no financeiro: o cliente pagou direto"]);
  assertEquals(f([{ tipo: "nada", motivo: "tecnico_f2b" }]), ['anotar que o Roberto pagou; o reembolso dele ainda não entra nas Diárias: fica a pendência "acerto do técnico" para você acertar com ele']);
  assertEquals(f([{ tipo: "pendencia", qual: "dar_entrada" }]), ['deixar a pendência "dar entrada no estoque"']);
});

// ─── gravação e demais mensagens ──────────────────────────────────────────────────────────

Deno.test("gravado: efeitos no passado, a pasta e o próximo (ou fila vazia)", () => {
  const c = cmp({ situacao: "gravado", cobrar_cliente: false });
  const gravacao = {
    situacao: "gravado",
    efeitos: [{ tipo: "despesa_os", so_expense_id: "e-1", os_id: "os-1", billable: false, direto: false }, { tipo: "anotar", anotacao_id: "a-1", resultado: "aguardando" }],
    avisos: [], mensagens: [], mes: "2026-10-01",
  };
  assertEquals(
    textoDaGravacao({ cmp: c, gravacao, proxima: null }),
    "CMP-00124 gravado: lancei a despesa na OS-00112 como custo da HBR; anotei o débito para quando o banco trouxer. Arquivo: Brisa/1- DOC's/Compras.\n\nFila vazia: não há mais comprovantes para conferir.",
  );
  const proxima = pergunta("para_que", { posicao: 1, total: 3, opcoes: [{ n: 1, rotulo: "Estoque", valor: "estoque" }] }, { codigo: "CMP-00125", numero: 125 });
  const t = textoDaGravacao({ cmp: c, gravacao: { ...gravacao, mensagens: ["o mês está fechado: só anexei"] }, proxima });
  assertStringIncludes(t, "\no mês está fechado: só anexei\n\nPróximo: CMP-00125 (1 de 3)");
  // pessoal: só o arquivo; crédito: espera a fatura
  assertStringIncludes(
    textoDaGravacao({ cmp: cmp({ destino: "pessoal", os: null, situacao: "gravado" }), gravacao: { situacao: "gravado", efeitos: [] }, proxima: null }),
    "CMP-00124 gravado: só guardei o arquivo (nada no financeiro). Arquivo: COMPROVANTES/PESSOAL/2026-10.",
  );
  assertStringIncludes(
    textoDaGravacao({ cmp: cmp({ destino: "empresa", os: null, forma: "credito", situacao: "gravado" }), gravacao: { situacao: "gravado", efeitos: [] }, proxima: null }),
    "nada no financeiro agora: a compra no crédito entra pela fatura. Arquivo: COMPROVANTES/2026/2026-10.",
  );
});

Deno.test("gravado: a anotação recusada pela rota (ambígua) e o técnico (F2b) no passado", () => {
  const c = cmp({ situacao: "gravado", destino: "empresa", os: null, quem_pagou: "empresa" });
  assertStringIncludes(
    textoDaGravacao({ cmp: c, gravacao: { situacao: "gravado", efeitos: [{ tipo: "nada", motivo: "anotacao_recusada" }, { tipo: "pendencia", qual: "classificar_no_extrato" }] }, proxima: null }),
    'CMP-00124 gravado: não anotei no extrato (fica para classificar no Extrato); deixei a pendência "classificar no Extrato".',
  );
  const t = cmp({ situacao: "gravado", quem_pagou: "tecnico", pagador_nome: "Roberto", cobrar_cliente: false });
  assertStringIncludes(
    textoDaGravacao({ cmp: t, gravacao: { situacao: "gravado", efeitos: [{ tipo: "despesa_os", billable: false }, { tipo: "nada", motivo: "tecnico_f2b" }] }, proxima: null }),
    "lancei a despesa na OS-00112 como custo da HBR, paga pelo Roberto; anotei que o Roberto pagou",
  );
});

Deno.test("mensagens curtas da 3.3", () => {
  assertEquals(textoOkNaoAprova("CMP-00124"), "Para gravar o CMP-00124, responda *sim* (ou *não* para corrigir).");
  // erro conhecido: texto fixo com a saída, sem "tentar de novo" (repetiria o mesmo erro)
  assertEquals(
    textoNaoGravado("CMP-00124", "o mês está fechado", 124),
    "Não gravei o CMP-00124: o mês está fechado no financeiro: reabra o mês ou *cancelar cmp 124 motivo*. Nada mudou. Responda *não* para corrigir.",
  );
  // erro desconhecido: nunca o texto cru do banco; só o código (e tentar de novo)
  assertEquals(
    textoNaoGravado("CMP-00124", 'new row for relation "x" violates check constraint "y"', 124, "23514"),
    "Não gravei o CMP-00124: deu um erro no sistema (código 23514). Nada mudou. Responda *sim* para tentar de novo ou *não* para corrigir.",
  );
  assertEquals(textoInvalida({ tipo: "os", numero: 98 }, "para_que", null), "Não achei a OS-00098. ");
  assertEquals(textoInvalida({ tipo: "opcao", n: 9 }, "para_que", null), "Não achei essa opção. ");
  assertEquals(textoInvalida({ tipo: "nome", texto: "x" }, "categoria", null), "Não achei essa categoria. ");
  assertEquals(textoInvalida({ tipo: "os", numero: 98 }, "para_que", "os_cancelada"), "A OS-00098 está cancelada. ");
  // revisão de 11/10/2026: diz quando volta (a pausa é de 12 h) e como continuar antes
  assertEquals(
    textoSair(3),
    "Ok, parei. Faltam 3 comprovantes. Volto a perguntar em até 12 h; para continuar antes: *cmp N* (ou *pendentes* para ver a lista).",
  );
  assertEquals(
    textoSair(1, 125),
    "Ok, parei. Falta 1 comprovante. Volto a perguntar em até 12 h; para continuar antes: *cmp 125* (ou *pendentes* para ver a lista).",
  );
  assertEquals(textoSair(0), "Ok, parei.");
  assertEquals(textoOcupado("CMP-00124", "Enviar PDF"), 'Anotei para o CMP-00124. Continuo depois que você responder: "Enviar PDF".');
  assertEquals(textoFeito("CMP-00124", ["dar_entrada"]), 'CMP-00124: pendência "dar entrada no estoque" marcada como resolvida.');
  assertEquals(
    textoLote(Array.from({ length: 20 }, (_, k) => ({ codigo: `CMP-${String(12 + k).padStart(5, "0")}` })), 17),
    "Coloquei 20 comprovantes antigos na fila (CMP-00012 a CMP-00031). Ainda há 17 antigos: mande *lote antigo* de novo depois.",
  );
  assertEquals(textoLote([{ codigo: "CMP-00012" }], 1), "Coloquei 1 comprovante antigo na fila (CMP-00012). Ainda há 1 antigo: mande *lote antigo* de novo depois.");
  assertEquals(textoLote([], 0), "Não há comprovantes antigos para conferir.");
});

Deno.test("pendentes: o exemplo da spec; vazio não manda; mais de 10 → 'e mais N'", () => {
  const t = textoDosPendentes({
    abertos: [
      { codigo: "CMP-00124", numero: 124, data: "2026-10-10", valor: "62.00", fornecedor: "Auto Posto Exemplo", situacao: "perguntando", falta: "para_que", pendencias: [] },
      { codigo: "CMP-00119", numero: 119, data: "2026-10-08", valor: "187.40", fornecedor: "Loja X", situacao: "gravado", falta: null, pendencias: ["dar_entrada"] },
    ],
    total: 2,
    antigos: 37,
  });
  assertEquals(
    t,
    [
      "Comprovantes em aberto (2):",
      "1. CMP-00124 · 10/10 · R$ 62,00 · Auto Posto Exemplo — falta: para quê",
      "2. CMP-00119 · 08/10 · R$ 187,40 · Loja X — gravado; falta: dar entrada no estoque",
      "Para continuar um: *cmp 124*. Antigos ainda não conferidos: 37 (*lote antigo*).",
    ].join("\n"),
  );
  assertEquals(textoDosPendentes({ abertos: [], total: 0, antigos: 0 }), null);
  const muitos = Array.from({ length: 12 }, (_, k) => ({ codigo: `CMP-${String(100 + k).padStart(5, "0")}`, situacao: "aguardando_vez", falta: null }));
  const tm = String(textoDosPendentes({ abertos: muitos, total: 12, antigos: 0 }));
  assertStringIncludes(tm, "10. CMP-00109");
  assert(!tm.includes("11. "));
  assertStringIncludes(tm, "e mais 2");
});

Deno.test("cartão: gravado, esperando a nota, cancelado (sem 'para cancelar')", () => {
  const c = cmp({ situacao: "gravado", cobrar_cliente: true });
  assertEquals(
    textoDoCartao(c, [{ tipo: "despesa_os", billable: true }]),
    "CMP-00124 (gravado): R$ 62,00 em 10/10 · Auto Posto Exemplo · OS-00112 Brisa · cobrado do cliente (entra no total). Feito: lancei a despesa na OS-00112, cobrada do cliente. Para cancelar: *cancelar cmp 124 motivo*.",
  );
  assertStringIncludes(textoDoCartao(cmp({ situacao: "aguardando_xml" }), [{ tipo: "aguardar_nota" }]), "CMP-00124 (esperando a nota)");
  assertEquals(textoDoCartao(cmp({ situacao: "cancelado" }), []).includes("Para cancelar"), false);
});

Deno.test("cancelamento: desfeito, recusado com o caminho, sem nada gravado", () => {
  assertEquals(
    textoDoCancelamento("CMP-00124", "comprei em dobro", { ok: true, desfeitos: [{ tipo: "despesa_os" }, { tipo: "anotar" }, "pendencia"] }),
    "CMP-00124 cancelado (comprei em dobro). Desfeito: a despesa da OS, a anotação do extrato, a pendência. Arquivo em COMPROVANTES/_CANCELADOS.",
  );
  assertEquals(
    textoDoCancelamento("CMP-00124", "x", { ok: false, bloqueios: [{ efeito: "anotar", motivo: "anotacao_aplicada" }] }),
    "Não cancelei o CMP-00124: a linha do banco já recebeu a classificação; corrija pelo Extrato. Nada mudou.",
  );
  assertStringIncludes(textoDoCancelamento("CMP-00124", "teste", { ok: true, desfeitos: [] }), "Desfeito: nada (ainda não tinha sido gravado)");
});

Deno.test("histórico do fluxo: a marca 🤖 e a referência; caminho legível", () => {
  const h = historicoDoFluxo("CMP-00124 gravado", "CMP-00124 (id c-1)", "CMP-00124 gravado: …");
  assertEquals(h.user, "🤖 Fluxo de comprovantes (respostas do dono pelo menu, não pelo assistente): CMP-00124 gravado.");
  assertEquals(h.assistant, "CMP-00124 gravado: …\n\nReferência: CMP-00124 (id c-1).");
  assertEquals(caminhoLegivel("/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10"), "COMPROVANTES/2026/2026-10");
});

Deno.test("nenhum texto passa de 4096 caracteres e nenhum tem emoji", () => {
  const longo = "x".repeat(5000);
  const t = textoDaPergunta(pergunta("para_que", { opcoes: [{ n: 1, rotulo: longo, valor: "os:1" }] }));
  assertEquals(t.length <= MAX_MENSAGEM, true);
  for (const s of [textoDoResumo(pergunta("confirmar", { plano: PLANO_A })), textoSair(2), textoOkNaoAprova("CMP-00001")]) {
    assertEquals(/\p{Extended_Pictographic}/u.test(s), false, s);
  }
});

const semNbsp = (s: unknown) => String(s).replace(/\u00a0/g, " ");

// ─── revisão de 11/10/2026: textos novos ─────────────────────────────────────────────────

Deno.test("passo mesma_compra: diz qual CMP parece a mesma compra, com valor e data", () => {
  const opcoes = [{ n: 1, rotulo: "Sim, é a mesma compra: só guardar o arquivo", valor: "mesma" }, { n: 2, rotulo: "Não, é outra compra", valor: "outra" }];
  const t = textoDaPergunta(pergunta("mesma_compra", { opcoes, mesma_compra: { codigo: "CMP-00120", valor: "62.00", data: "2026-10-10" } } as never));
  assertStringIncludes(t, "Parece a mesma compra do CMP-00120 (R$ 62,00 em 10/10), que já foi gravado. É a mesma?");
  assertStringIncludes(t, "1 Sim, é a mesma compra: só guardar o arquivo\n2 Não, é outra compra");
});

Deno.test("na fila, qual CMP, corrigido, dica, não entendi, retomada", () => {
  assertEquals(
    textoNaFila(["CMP-00124"], 124, null),
    "Recebi o CMP-00124; está na fila: pergunto daqui a pouco. Para conferir agora: *cmp 124*.",
  );
  assertEquals(
    textoNaFila(["CMP-00124", "CMP-00125"], 124, 'Mandar "PDF"\nao cliente'),
    'Recebi 2 comprovantes (CMP-00124 e CMP-00125); estão na fila: pergunto depois do pedido "Mandar PDF ao cliente". Para conferir agora: *cmp 124*.',
  );
  assertEquals(
    textoQualCmp("CMP-00124", "CMP-00125", "valor 70"),
    "Corrigir o CMP-00124 (já gravado) ou o CMP-00125? Para o CMP-00125: *corrigir cmp 125 valor 70*. " +
      "O CMP-00124 já foi gravado: para mudar, *cancelar cmp 124 motivo* e mande o arquivo de novo.",
  );
  assertEquals(semNbsp(textoCorrigido("CMP-00125", { campo: "valor", valor: "70.00" })), "CMP-00125: valor corrigido para R$ 70,00.");
  assertEquals(textoCorrigido("CMP-00125", { campo: "data", valor: "2026-10-09" }), "CMP-00125: data corrigida para 09/10.");
  assertEquals(textoCorrigido("CMP-00125", { campo: "categoria", valor: "Combustível e deslocamento" }), "CMP-00125: categoria corrigida para Combustível e deslocamento.");
  assertEquals(textoCorrigido("CMP-00125", null), null);
  assertEquals(textoDica("CMP-00125"), "Anotei para o CMP-00125.");
  assertEquals(textoDica(null), "Anotei para o comprovante que está chegando.");
  assertStringIncludes(textoNaoEntendi("CMP-00124"), "Não entendi para o CMP-00124.");
  assertStringIncludes(textoRetomadaInterrompida("CMP-00124"), "Essa resposta é para o CMP-00124?");
  // o "corrigir" sozinho ensina o comando com o que muda (inclui a categoria)
  assertStringIncludes(TEXTO_CORRIGIR_COMO, "*corrigir categoria*");
});

Deno.test("não gravado: os erros conhecidos viram texto fixo com a saída", () => {
  assertEquals(
    semNbsp(textoNaoGravado("CMP-00124", "Categoria \"X\" não existe", 124)),
    "Não gravei o CMP-00124: a categoria não existe mais no plano de contas: *corrigir categoria*. Nada mudou. Responda *não* para corrigir.",
  );
  assertStringIncludes(textoNaoGravado("CMP-00124", "o mês 09/2026 está fechado", 124), "o mês (09/2026) está fechado no financeiro");
  assertStringIncludes(textoNaoGravado("CMP-00124", null, 124), "deu um erro no sistema. Nada mudou. Responda *sim* para tentar de novo");
});
