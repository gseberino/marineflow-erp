// Os textos fixos da conversa (seção 3.3 da spec): cabeçalho, passos, resumo, gravação, pendentes,
// cartão, cancelamento e o par do histórico. Os exemplos da spec são conferidos ao pé da letra.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cabecalho,
  caminhoLegivel,
  type CmpResumo,
  ehPerguntaAzul,
  frasesDaGravacao,
  frasesDoPlano,
  historicoDoFluxo,
  type LinhaDoBanco,
  linhaDoExtrato,
  MAX_MENSAGEM,
  type PerguntaDoBanco,
  type PerguntaDoExtrato,
  prefixoDaPergunta,
  prefixoDaPerguntaDoExtrato,
  textoDaPerguntaDoExtrato,
  textoDoLigado,
  textoDoMudou,
  textoDoNaoTrocado,
  textoDoQuemEsperando,
  textoDoRecusado,
  textoDoRegravado,
  textoInvalidaDoExtrato,
  textoInvalidaDoQuemPagou,
  textoNaoLigado,
  motivoDaAprovacao,
  textosDosAvisos,
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
  comAPergunta,
  textoDaCategoriaAnotada,
  textoDoAnotadoNaConversa,
  textosDosItensAnotados,
  textoCorrigirIncompleto,
} from "./conversa.ts";

const OS = { id: "os-1", numero: "OS-00112", barco: "Brisa", cliente: "João", status: "in_progress", faturada: false, assinada: false, pasta_registrada: true };

function cmp(extra: Partial<CmpResumo> = {}): CmpResumo {
  return {
    id: "c-1", codigo: "CMP-00124", numero: 124, situacao: "perguntando", tipo: "nfce", valor: "62.00", valor_lido: "62.00",
    valor_confianca: "alta", data: "2026-10-10", hora: "12:57:56", forma: "debito", fornecedor: "Auto Posto Exemplo",
    fornecedor_origem: "cadastro", cnpj: "11222333000181", cnpj_confianca: "alta", destino: "os", os: OS, tipo_na_os: null,
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
  assertEquals(cabecalho(pergunta("tipo_na_os")), "CMP-00124 (1 de 4) · cupom NFC-e · Auto Posto Exemplo · 10/10 · R$ 62,00");
  assertEquals(cabecalho(pergunta("tipo_na_os", { total: 1 })), "CMP-00124 · cupom NFC-e · Auto Posto Exemplo · 10/10 · R$ 62,00");
  assertEquals(cabecalho(pergunta("tipo_na_os", {}, { fornecedor_origem: "receita", fornecedor: "POSTO LTDA" })).split(" · ")[2], "POSTO LTDA (Receita)");
  assertEquals(cabecalho(pergunta("tipo_na_os", {}, { fornecedor: null, fornecedor_origem: null })).split(" · ")[2], "CNPJ 11.222.333/0001-81");
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
    "CMP-00124: o que corrigir?\n1 Valor\n2 Data\n3 Para quê\n4 Como foi pago\n5 Quem pagou\n6 Peça ou despesa\n7 Categoria\n8 Cancelar este comprovante\n9 Deixar para depois",
  );
  assertEquals(
    textoDaPergunta(pergunta("qual_tecnico", { opcoes: [{ n: 1, rotulo: "Roberto", valor: "payee:1" }, { n: 2, rotulo: "Felipe", valor: "payee:2" }] })),
    `${cab}\nQual técnico pagou?\n1 Roberto\n2 Felipe\nOu escreva o nome.`,
  );
});

Deno.test("passo tipo_na_os (ajustes do dono): peça ou despesa da OS, em qualquer status; nada de cobrar do cliente", () => {
  const esperado = "CMP-00124 (1 de 4) · cupom NFC-e · Auto Posto Exemplo · 10/10 · R$ 62,00\n" +
    "Para a OS-00112 · Brisa: o que foi esta compra?\n" +
    "1 Peça ou material da OS (não lanço custo: a peça entra pela OS)\n" +
    "2 Despesa da OS (combustível, alimentação, frete, ferramenta…): custo interno, não aparece para o cliente";
  assertEquals(textoDaPergunta(pergunta("tipo_na_os")), esperado);
  // as opções do banco valem (o rótulo é o dele); a OS faturada pergunta igual (o total nunca muda)
  const opcoes = [{ n: 1, rotulo: "Peça", valor: "peca" }, { n: 2, rotulo: "Despesa", valor: "despesa" }];
  assertStringIncludes(textoDaPergunta(pergunta("tipo_na_os", { opcoes }, { os: { ...OS, status: "invoiced", faturada: true } })),
    "Para a OS-00112 · Brisa: o que foi esta compra?\n1 Peça\n2 Despesa");
  assertEquals(/cobr/i.test(textoDaPergunta(pergunta("tipo_na_os"))), false);
});

Deno.test("passo quem_pagou do PESSOAL (ajustes do dono): saiu da conta ou do cartão da EMPRESA?", () => {
  const t = textoDaPergunta(pergunta("quem_pagou", {}, { destino: "pessoal", os: null }));
  assertStringIncludes(t, "\nGasto pessoal. Saiu da conta ou do cartão da EMPRESA?\n" +
    "1 Sim, da conta ou do cartão da empresa (vira gasto pessoal do sócio, descontado do pró-labore)\n" +
    "2 Não, do meu bolso ou do meu cartão pessoal (só guardo o arquivo)");
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
    { tipo: "despesa_os", os_id: "os-1", os_numero: "OS-00112", paid_by: "company", categoria: "Combustível e deslocamento" },
    { tipo: "anotar", forma: "debito", categoria: "Peças e materiais", documento: true },
  ],
  avisos: [],
  situacao_final: "gravado",
  pasta: "barco",
};

Deno.test("resumo: o exemplo da spec, linha por linha (despesa da OS = custo interno)", () => {
  const p = pergunta("confirmar", { plano: PLANO_A, versao: 7, pasta: "Brisa/1- DOC's/Compras" }, {
    tipo_na_os: "despesa", categoria: "Combustível e deslocamento", situacao: "aguardando_sim",
  });
  assertEquals(
    textoDoResumo(p),
    [
      "CMP-00124 · confira antes de gravar:",
      "• R$ 62,00 em 10/10 às 12h57 · Auto Posto Exemplo",
      "• Para: OS-00112 Brisa · despesa da OS (custo interno: não aparece para o cliente) · Combustível e deslocamento",
      "• Pago: débito, pela empresa (se não foi a empresa: *corrigir quem*)",
      "Vou: lançar a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS); anotar o débito para quando o banco trouxer (se já trouxe, classifico a linha).",
      "Arquivo: Brisa/1- DOC's/Compras.",
      "Responda *sim* para gravar ou *não* para corrigir.",
    ].join("\n"),
  );
  assertEquals(textoDaPergunta(p), textoDoResumo(p), "no confirmar a pergunta é o resumo");
  assertEquals(/cobr|falta aprovar/i.test(textoDoResumo(p)), false);
});

Deno.test("resumo (ajustes do dono): peça, já lançado na OS, ambíguo e PESSOAL pago pela empresa", () => {
  const para = (c: Partial<CmpResumo>) => textoDoResumo(pergunta("confirmar", { plano: { efeitos: [] } }, c)).split("\n")[2];
  assertEquals(para({ tipo_na_os: "peca", categoria: "Peças e materiais" }),
    "• Para: OS-00112 Brisa · peça/material (só comprova; lance a peça na OS se ainda não lançou)");
  assertEquals(para({ na_os: { tipo: "despesa", categoria: "Combustível e deslocamento", valor: "62.00", data: "2026-10-10" } }),
    "• Para: OS-00112 Brisa · já lançado na OS: Combustível e deslocamento R$ 62,00 de 10/10 (só comprova)");
  assertEquals(para({ na_os: { tipo: "peca", produto: "Filtro de óleo", valor: "62.00" } }),
    "• Para: OS-00112 Brisa · já lançado na OS: Filtro de óleo R$ 62,00 (só comprova)");
  assertEquals(para({ na_os: { ambiguo: 2 } }), "• Para: OS-00112 Brisa · só comprova (há 2 lançamentos iguais na OS)");
  // o que o dono escolheu no corrigir vale antes do lançamento achado (a ordem do plano)
  assertEquals(para({ tipo_na_os: "despesa", na_os: { tipo: "despesa", categoria: "Outras despesas", valor: "62.00" } }),
    "• Para: OS-00112 Brisa · despesa da OS (custo interno: não aparece para o cliente)");
  const pessoal =textoDoResumo(pergunta("confirmar", { plano: { efeitos: [{ tipo: "anotar", forma: "credito" }] } },
    { destino: "pessoal", os: null, quem_pagou: "empresa", forma: "credito", categoria: "Gasto Pessoal Sócio - Descontar PL" }));
  assertStringIncludes(pessoal, "• Para: PESSOAL, pago pela empresa (gasto pessoal do sócio: desconta do pró-labore do mês)");
  assertStringIncludes(pessoal, "• Pago: crédito, pela empresa");
  // do bolso: só o arquivo, sem "Pago:"
  const doBolso = textoDoResumo(pergunta("confirmar", { plano: { efeitos: [{ tipo: "nada", motivo: "pessoal" }] } },
    { destino: "pessoal", os: null, quem_pagou: "socio" }));
  assertStringIncludes(doBolso, "• Para: pessoal\nVou: só guardar o arquivo em PESSOAL (nada no financeiro).");
});

Deno.test("resumo: avisos (vários na OS, almoço no extra, categoria que já estava, duplicado) e os desconhecidos ficam fora", () => {
  const p = pergunta("confirmar", {
    plano: { ...PLANO_A, avisos: ["varios_na_os", "duplicado_ambiguo", "categoria_inativa_x", "os_faturada_total_nao_muda"] },
    avisos: ["os_assinada_pede_nova_assinatura", "valor_incerto"],
  }, { na_os: { ambiguo: 2 } });
  const t = textoDoResumo(p);
  assertStringIncludes(t, 'Há 2 lançamentos de R$ 62,00 na OS-00112 sem comprovante: não liguei a nenhum e não lancei custo. Se for um gasto novo, responda *não* e escolha "Peça ou despesa".');
  assertStringIncludes(t, "Há mais de um lançamento igual já feito: não lanço; fica para classificar no Extrato.");
  assert(!t.includes("faturada") && !t.includes("assinada") && !t.includes("valor_incerto"), "os avisos de cobrança saíram");
  // o almoço que já está no extra da diária (resposta 6): avisa sem bloquear
  const comAlmoco = textoDoResumo(pergunta("confirmar", {
    plano: {
      efeitos: [{ tipo: "reembolso_tecnico", favorecido_nome: "João", valor: "35.00", extra_do_dia: { valor: "20.00", data: "2026-09-16" } }],
      avisos: ["almoco_ja_no_extra"],
    },
  }, { quem_pagou: "tecnico", pagador_nome: "João", categoria: "Alimentação de campo" }));
  // revisão dos ajustes: o aviso diz a saída (o menu do corrigir não tem "não reembolsar")
  assertStringIncludes(semNbsp(comAlmoco), "O João já recebeu R$ 20,00 de almoço (extra da diária de 16/09). Reembolsar mesmo assim? *sim* grava; " +
    'se o extra já pagou este almoço, responda *não* e escolha "Cancelar este comprovante" (nada é lançado).');
  // a categoria do lançamento que já existe não é trocada (regra G)
  assertEquals(
    textosDosAvisos(["categoria_existente_diferente"], cmp(), [{ tipo: "anexar_lancamento", diferente: { categoria: "Outras despesas" } }]),
    ["O lançamento que já existe está como Outras despesas: não troco (só preencho o que está vazio). Se estiver errado, corrija no Extrato."],
  );
});

Deno.test("frasesDoPlano: uma frase por efeito da 3.3 (com os ajustes do dono)", () => {
  const c = cmp({ pagador_nome: "Roberto" });
  const f = (efeitos: Array<Record<string, unknown>>) => frasesDoPlano({ efeitos: efeitos as Array<{ tipo: string }> }, c);
  assertEquals(f([{ tipo: "despesa_os", os_numero: "OS-00112" }]), [
    "lançar a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS)",
  ]);
  assertEquals(f([{ tipo: "despesa_os", os_numero: "OS-00112", paid_by: "technician" }]), [
    "lançar a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS), paga pelo Roberto",
  ]);
  assertEquals(f([{ tipo: "despesa_os", os_numero: "OS-00112", nota: true }])[0].startsWith("lançar o valor da nota na OS-00112 como custo interno"), true);
  assertEquals(f([{ tipo: "anexar_despesa", os_numero: "OS-00112", valor: "62.00", data: "2026-10-10" }]), ["usar a despesa que já está na OS-00112 (R$ 62,00, 10/10): só comprovo, não lanço de novo"]);
  assertEquals(f([{ tipo: "anexar_peca", os_numero: "OS-00112", so_part_id: "sp-1", produto: "Filtro de óleo", valor: "62.00" }]), [
    "usar a peça que já está na OS-00112 (Filtro de óleo, R$ 62,00): só comprovo, não lanço custo",
  ]);
  assertEquals(f([{ tipo: "comprovar_na_os", os_numero: "OS-00112", motivo: "peca" }]), ["guardar o comprovante como prova da peça da OS-00112 (não lanço custo)"]);
  assertEquals(f([{ tipo: "comprovar_na_os", os_numero: "OS-00112", motivo: "ambiguo" }]), [
    "guardar o comprovante como prova da OS-00112 sem escolher lançamento (não lanço custo)",
  ]);
  assertEquals(f([{ tipo: "pendencia", qual: "incluir_na_os" }]), ['deixar a pendência "lançar a peça na OS, se ainda não lançou"']);
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
  const c = cmp({ situacao: "gravado", tipo_na_os: "despesa" });
  const gravacao = {
    situacao: "gravado",
    efeitos: [{ tipo: "despesa_os", so_expense_id: "e-1", os_id: "os-1" }, { tipo: "anotar", anotacao_id: "a-1", resultado: "aguardando" }],
    avisos: [], mensagens: [], mes: "2026-10-01",
  };
  assertEquals(
    textoDaGravacao({ cmp: c, gravacao, proxima: null }),
    "CMP-00124 gravado: lancei a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS); anotei o débito para quando o banco trouxer. Arquivo: Brisa/1- DOC's/Compras.\n\nFila vazia: não há mais comprovantes para conferir.",
  );
  // peça, peça que já estava e despesa que já estava: só comprova
  const g = (ef: Record<string, unknown>) => frasesDaGravacao([ef as { tipo: string }], c);
  assertEquals(g({ tipo: "anexar_despesa" }), ["usei a despesa que já estava na OS-00112: só comprovei, não lancei de novo"]);
  assertEquals(g({ tipo: "anexar_peca", produto: "Filtro de óleo" }), ["usei a peça que já estava na OS-00112 (Filtro de óleo): só comprovei, não lancei custo"]);
  assertEquals(g({ tipo: "comprovar_na_os", motivo: "peca" }), ["guardei o comprovante como prova da peça da OS-00112 (não lancei custo)"]);
  assertEquals(g({ tipo: "comprovar_na_os", motivo: "ambiguo" }), ["guardei o comprovante como prova da OS-00112 sem escolher lançamento (não lancei custo)"]);
  // regra G: o lançamento que já existia só teve o vazio preenchido
  assertEquals(g({ tipo: "anexar_lancamento", corrigido: { linked_service_order_id: { antes: null } } }), [
    "anexei ao lançamento que já existia e preenchi a OS, que estava vazia",
  ]);
  assertEquals(g({ tipo: "anexar_lancamento", corrigido: { linked_service_order_id: {}, expense_category: {} } }), [
    "anexei ao lançamento que já existia e preenchi a OS e a categoria, que estavam vazias",
  ]);
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
  const t = cmp({ situacao: "gravado", quem_pagou: "tecnico", pagador_nome: "Roberto", tipo_na_os: "despesa" });
  assertStringIncludes(
    textoDaGravacao({ cmp: t, gravacao: { situacao: "gravado", efeitos: [{ tipo: "despesa_os" }, { tipo: "nada", motivo: "tecnico_f2b" }] }, proxima: null }),
    "lancei a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS), paga pelo Roberto; anotei que o Roberto pagou",
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
  const c = cmp({ situacao: "gravado", tipo_na_os: "despesa" });
  assertEquals(
    textoDoCartao(c, [{ tipo: "despesa_os" }]),
    "CMP-00124 (gravado): R$ 62,00 em 10/10 · Auto Posto Exemplo · OS-00112 Brisa · despesa da OS (custo interno: não aparece para o cliente). " +
      "Feito: lancei a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS). Para cancelar: *cancelar cmp 124 motivo*.",
  );
  assertStringIncludes(textoDoCartao(cmp({ situacao: "aguardando_xml" }), [{ tipo: "aguardar_nota" }]), "CMP-00124 (esperando a nota)");
  assertEquals(textoDoCartao(cmp({ situacao: "cancelado" }), []).includes("Para cancelar"), false);
});

Deno.test("cancelamento: desfeito, recusado com o caminho, sem nada gravado", () => {
  assertEquals(
    textoDoCancelamento("CMP-00124", "comprei em dobro", { ok: true, desfeitos: [{ tipo: "despesa_os" }, { tipo: "anotar" }, "pendencia"] }),
    "CMP-00124 cancelado (comprei em dobro). Desfeito: a despesa interna da OS, a anotação do extrato, a pendência. Arquivo em COMPROVANTES/_CANCELADOS.",
  );
  assertEquals(
    textoDoCancelamento("CMP-00124", "foi pessoal", { ok: true, desfeitos: [{ tipo: "anexar_peca" }, { tipo: "comprovar_na_os" }] }),
    "CMP-00124 cancelado (foi pessoal). Desfeito: o vínculo com a peça da OS, o comprovante como prova da OS. Arquivo em COMPROVANTES/_CANCELADOS.",
  );  assertEquals(
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

// ─── F3: a conversa da conciliação com o extrato (spec-f3.md, 4.3) ──────────────────────────

const DEBITO: LinhaDoBanco = {
  n: 1, id: "t-1", data: "2026-10-08", valor: "50.98", descricao: "DEBITO DE CARTAO", nome: null, conta: "C6 - Conta PJ HBR",
  cartao: false, parcela: null, total_da_compra: null, pendente: false, acao: "classificar", lancamento: null, conta_aberta: null,
  motivos: ["valor_exato", "sem_nome", "dias:0"], forte: true,
};

/** O CMP da AutoZone (débito de 08/10, R$ 50,98) gravado na OS-00112, esperando o banco. */
function cmpDoExtrato(extra: Partial<CmpResumo> = {}): CmpResumo {
  return cmp({
    situacao: "aguardando_banco", fornecedor: "AutoZone", valor: "50.98", valor_lido: "50.98", data: "2026-10-08",
    categoria: "Peças e materiais", quem_pagou: "empresa", gravado_em: "2026-10-10T22:41:00Z", ...extra,
  });
}

function perguntaDoExtrato(linhas: LinhaDoBanco[], azul: boolean, extra: Partial<PerguntaDoExtrato> = {}, c: Partial<CmpResumo> = {}): PerguntaDoExtrato {
  const opcoes = linhas.map((l, i) => ({ n: i + 1, rotulo: `linha ${i + 1}`, valor: `tx:${l.id}` }));
  return {
    pergunta_id: "p-9", dedupe_key: "cmp:p:p-9", cmp: cmpDoExtrato(c), passo: "banco",
    opcoes: azul ? [...opcoes, { n: 0, rotulo: "Nenhuma destas", valor: "nenhum" }] : opcoes,
    retomada: false, banco: { regra: "debito", nivel: azul ? "azul" : "verde", linhas, mais: 0, hash: "h" }, ...extra,
  };
}

Deno.test("F3 linhaDoExtrato: conta, dia, histórico até 40, valor; cartão, parcela, pendente, já lançada", () => {
  assertEquals(linhaDoExtrato(DEBITO), "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98");
  // a saída pode vir com sinal: o dono vê o valor
  assertEquals(linhaDoExtrato({ ...DEBITO, valor: "-50.98" }), "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98");
  assertEquals(
    linhaDoExtrato({ ...DEBITO, conta: "C6 - Cartão", descricao: "LOJA NAUTICA LTDA", valor: "200.00", cartao: true, parcela: "1/3", total_da_compra: "600.00", pendente: true }),
    "C6 - Cartão · 08/10 · LOJA NAUTICA LTDA · R$ 200,00 (cartão) · parcela 1/3 da compra de R$ 600,00 · ainda pendente no cartão",
  );
  assertEquals(
    linhaDoExtrato({ ...DEBITO, lancamento: { categoria: "Outras despesas", descricao: "x" } }),
    "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98 · já lançada (Outras despesas)",
  );
  assertEquals(linhaDoExtrato({ ...DEBITO, descricao: "X".repeat(80) }).split(" · ")[2].length, 40);
});

Deno.test("F3 pergunta verde: o exemplo da spec, ao pé da letra", () => {
  assertEquals(
    textoDaPerguntaDoExtrato(perguntaDoExtrato([DEBITO], false)),
    [
      "CMP-00124 · cupom NFC-e · AutoZone · 08/10 · R$ 50,98",
      "Apareceu no extrato: C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98.",
      "É deste comprovante? Se for, ligo e lanço a linha no Extrato como Peças e materiais, OS-00112 Brisa (aprovada no seu sim).",
      "Responda *sim* para ligar ou *não* se não for essa.",
    ].join("\n"),
  );
  // a ação de cada linha: anexar (só preenche o vazio: regra G), casar, aguardar
  const t = (l: Partial<LinhaDoBanco>, c: Partial<CmpResumo> = {}) => textoDaPerguntaDoExtrato(perguntaDoExtrato([{ ...DEBITO, ...l }], false, {}, c));
  assertStringIncludes(t({ acao: "anexar", lancamento: { categoria: "Outras despesas", os_numero: null } }),
    "Se for, ligo e uso o lançamento que já existe dela (preencho a OS-00112 Brisa, que está vazia).");
  assertStringIncludes(t({ acao: "anexar", lancamento: { categoria: null, os_numero: null } }),
    "Se for, ligo e uso o lançamento que já existe dela (preencho a OS-00112 Brisa e a categoria Peças e materiais, que estão vazias).");
  assertStringIncludes(t({ acao: "anexar", lancamento: { categoria: "Outras despesas", os_numero: "OS-00090" } }),
    "Se for, ligo e uso o lançamento que já existe dela (nada a preencher).");
  // sem saber da OS do lançamento (banco antigo), não promete preencher a OS
  assertStringIncludes(t({ acao: "anexar", lancamento: { categoria: "Peças e materiais" } }, { destino: "empresa", os: null }),
    "Se for, ligo e uso o lançamento que já existe dela (nada a preencher).");
  assertEquals(/corrijo|corrigir para/.test(t({ acao: "anexar", lancamento: { categoria: "Outras despesas" } })), false);
  assertStringIncludes(t({ acao: "casar", conta_aberta: { descricao: "Fatura AutoZone", valor: "50.98" } }), 'Se for, ligo e dou baixa na conta a pagar "Fatura AutoZone" (R$ 50,98) com ela.');
  assertStringIncludes(t({ acao: "aguardar", cartao: true, pendente: true }), "Se for, ligo e lanço quando o cartão confirmar a compra (aprovada no seu sim).");
  // sem a avaliação (só as opções): a linha pelo rótulo, sem prometer a ação
  const semAvaliacao = textoDaPerguntaDoExtrato({ ...perguntaDoExtrato([DEBITO], false), banco: null, opcoes: [{ n: 1, rotulo: "C6 · 08/10 · R$ 50,98", valor: "tx:t-1" }] });
  assertStringIncludes(semAvaliacao, "Apareceu no extrato: C6 · 08/10 · R$ 50,98.\nÉ deste comprovante?\nResponda *sim*");
  assertEquals(ehPerguntaAzul(perguntaDoExtrato([DEBITO], false)), false);
});

Deno.test("F3 pergunta azul: lista numerada, '0 Nenhuma destas' e 'Há mais N' com mais de 3", () => {
  const segunda = { ...DEBITO, n: 2, id: "t-2", data: "2026-10-09", forte: false };
  const p = perguntaDoExtrato([DEBITO, segunda], true, {}, { destino: "empresa", os: null });
  assertEquals(ehPerguntaAzul(p), true);
  assertEquals(
    textoDaPerguntaDoExtrato(p),
    [
      "CMP-00124 · cupom NFC-e · AutoZone · 08/10 · R$ 50,98",
      "Apareceram no extrato linhas que podem ser deste comprovante:",
      "1 C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98",
      "2 C6 - Conta PJ HBR · 09/10 · DEBITO DE CARTAO · R$ 50,98",
      "0 Nenhuma destas",
      "Responda o número da linha certa (ou 0). Ligando, lanço a linha no Extrato como Peças e materiais (aprovada no seu sim).",
    ].join("\n"),
  );
  const comMais = textoDaPerguntaDoExtrato({ ...p, banco: { ...p.banco!, mais: 2 } });
  assert(comMais.endsWith("\nHá mais 2 linhas iguais nesses dias: se não for nenhuma destas, responda 0 e classifique no Extrato."));
  // ações diferentes entre as linhas: o fechamento não promete uma só
  const misto = textoDaPerguntaDoExtrato(perguntaDoExtrato([DEBITO, { ...segunda, acao: "anexar", lancamento: { categoria: "Outras despesas" } }], true));
  assertStringIncludes(misto, "2 C6 - Conta PJ HBR · 09/10 · DEBITO DE CARTAO · R$ 50,98 · já lançada (Outras despesas)");
  assertStringIncludes(misto, "Ligando, faço o que a linha escolhida pede");
  // a retomada do vigia
  assertEquals(prefixoDaPerguntaDoExtrato({ ...p, retomada: true }, "vigia"), "Ainda falta ligar o CMP-00124 ao extrato.");
  assertEquals(prefixoDaPerguntaDoExtrato({ ...p, retomada: true }, "cmp"), null);
  assert(textoDaPerguntaDoExtrato(p, "Ainda falta ligar o CMP-00124 ao extrato.").startsWith("Ainda falta ligar o CMP-00124 ao extrato.\nCMP-00124 · "));
});

Deno.test("F3 plano: ligar_linha, aguardar_banco (débito, Pix, azul), crédito esperando o cartão e o reembolso do técnico", () => {
  const c = cmpDoExtrato({ situacao: "aguardando_sim", pagador_nome: "Roberto" });
  const f = (efeitos: Array<Record<string, unknown>>, extra: Partial<CmpResumo> = {}) =>
    frasesDoPlano({ efeitos: efeitos as Array<{ tipo: string }> }, { ...c, ...extra });
  const linha = { data: "2026-10-08", valor: "50.98", descricao: "DEBITO DE CARTAO", conta: "C6 - Conta PJ HBR", cartao: false, acao: "classificar", lancamento: null, conta_aberta: null };
  assertEquals(
    f([{ tipo: "ligar_linha", bank_transaction_id: "t-1", nivel: "verde", acao: "classificar", linha }]),
    ["ligar à linha do banco de 08/10 (C6 - Conta PJ HBR, DEBITO DE CARTAO, R$ 50,98) e lançá-la no Extrato como Peças e materiais, OS-00112 Brisa (aprovada no seu sim)"],
  );
  assertEquals(f([{ tipo: "ligar_linha", acao: "casar", linha: { ...linha, acao: "casar" } }])[0].endsWith("e dar baixa na conta a pagar com ela"), true);
  assertEquals(
    f([{ tipo: "ligar_linha", acao: "aguardar", linha: { ...linha, conta: "C6 - Cartão", descricao: "AUTOZONE BALNEARIO CAM", valor: "28.98", cartao: true, acao: "aguardar" } }], { forma: "credito" }),
    ["ligar à compra do cartão de 08/10 (C6 - Cartão, AUTOZONE BALNEARIO CAM, R$ 28,98) e lançá-la no Extrato quando o cartão confirmar a compra (aprovada no seu sim)"],
  );
  assertEquals(
    f([{ tipo: "ligar_linha", acao: "anexar", linha: { ...linha, acao: "anexar", lancamento: { categoria: "Peças e materiais", os_numero: null } } }])[0]
      .endsWith("e usar o lançamento que já existe dela (preencho a OS-00112 Brisa, que está vazia)"),
    true,
  );
  assertEquals(f([{ tipo: "aguardar_banco", regra: "debito", nivel: "cinza" }]), ["nada no financeiro agora: quando o débito aparecer no extrato, pergunto se é este"]);
  assertEquals(f([{ tipo: "aguardar_banco", regra: "pix", nivel: "cinza" }], { forma: "pix" }), ["nada no financeiro agora: quando o Pix aparecer no extrato, pergunto qual linha é"]);
  assertEquals(f([{ tipo: "aguardar_banco", regra: "boleto", nivel: "azul" }], { forma: "boleto" }), [
    "nada no financeiro agora (já há linhas parecidas no extrato: logo depois de gravar pergunto qual é)",
  ]);
  assertEquals(f([{ tipo: "aguardar_fatura" }], { forma: "credito" }), ["nada no financeiro agora: quando a compra aparecer no cartão, pergunto se é esta"]);
  assertEquals(f([{ tipo: "aguardar_fatura" }], { forma: "credito_loja" }), ["nada no financeiro agora: a compra no crédito entra pela fatura"]);
  assertEquals(
    f([{ tipo: "reembolso_tecnico", favorecido_id: "p-rob", favorecido_nome: "Roberto", valor: "62.00", data: "2026-10-08" }]),
    ["lançar R$ 62,00 nas Diárias do Roberto como reembolso de despesa paga pelo técnico (entra no próximo acerto dele)"],
  );
});

Deno.test("F3 gravação e cartão: ligar_linha pelo 'como', aguardar_banco, reembolso; 'No extrato:' no lugar de 'Fila vazia'", () => {
  const ligado = cmpDoExtrato({
    situacao: "conciliado",
    banco: { estado: "ligado", nivel: "verde", desde: "2026-10-10", ate: null, linha: { data: "2026-10-08", valor: "50.98", descricao: "DEBITO DE CARTAO", conta: "C6 - Conta PJ HBR", como: "classificou" } },
  });
  const g = (ef: Record<string, unknown>, c: CmpResumo = ligado) => frasesDaGravacao([ef as { tipo: string }], c);
  // ajustes do dono: o sim aprova a linha — lançada, falhou agora, ou a proposta ainda não está na fila
  assertEquals(g({ tipo: "ligar_linha", como: "classificou" }), [
    "liguei à linha do banco de 08/10 e a classifiquei como Peças e materiais, OS-00112 (lanço no Extrato na próxima rodada)",
  ]);
  assertEquals(g({ tipo: "ligar_linha", como: "classificou", aprovado: { payable_id: "pay-1" } }), [
    "liguei à linha do banco de 08/10 e lancei no Extrato como Peças e materiais, OS-00112",
  ]);
  // revisão dos ajustes: o dono desfez a aprovação no Extrato — a linha é dele, nada de "lanço na próxima rodada"
  assertEquals(g({ tipo: "ligar_linha", como: "classificou", aprovado_desfeito: { payable_id: "pay-1", desfeito_em: "2026-10-11" } }), [
    "liguei à linha do banco de 08/10; a aprovação foi desfeita no Extrato e a linha ficou para você classificar lá",
  ]);
  assertEquals(frasesDaGravacao([{ tipo: "ligar_linha", como: "classificou" }], ligado, { ok: true }), [
    "liguei à linha do banco de 08/10 e lancei no Extrato como Peças e materiais, OS-00112",
  ]);
  assertEquals(frasesDaGravacao([{ tipo: "ligar_linha", como: "classificou" }], ligado, { ok: false, motivo: "Esta linha acabou de ser lançada por outro caminho — revise a fila" }), [
    "liguei à linha do banco de 08/10 e a classifiquei, mas não consegui aprovar agora (Esta linha acabou de ser lançada por outro caminho — revise a fila): tento de novo na próxima rodada do Extrato",
  ]);
  assertEquals(g({ tipo: "ligar_linha", como: "anexou" }), ["liguei à linha do banco de 08/10 e anexei ao lançamento dela"]);
  assertEquals(g({ tipo: "ligar_linha", como: "anexou", corrigido: { linked_service_order_id: { antes: null } } }), [
    "liguei à linha do banco de 08/10 e anexei ao lançamento dela (preenchi a OS, que estava vazia)",
  ]);
  assertEquals(g({ tipo: "ligar_linha", como: "casou" }), ["liguei à linha do banco de 08/10 e dei baixa na conta a pagar"]);
  assertEquals(g({ tipo: "ligar_linha", como: "aguardando" }, { ...ligado, forma: "credito" }), ["liguei à compra do cartão de 08/10 (lanço no Extrato quando ela for confirmada)"]);
  assertEquals(g({ tipo: "aguardar_banco", regra: "debito", nivel: "cinza" }), ["quando o débito aparecer no extrato, pergunto se é este"]);
  assertEquals(g({ tipo: "reembolso_tecnico", reembolso_id: "r-1", valor: "62.00" }, cmpDoExtrato({ quem_pagou: "tecnico", pagador_nome: "Roberto" })), [
    "lancei R$ 62,00 nas Diárias do Roberto como reembolso de despesa paga pelo técnico",
  ]);
  // a anotação da F2 aplicada na hora: o sim aprova também
  assertEquals(frasesDaGravacao([{ tipo: "anotar", resultado: "aplicada" }], ligado, { ok: true }), ["lancei a linha do banco no Extrato como Peças e materiais, OS-00112"]);
  assertEquals(frasesDaGravacao([{ tipo: "anotar", resultado: "aplicada" }], ligado), ["classifiquei a linha do banco (lanço no Extrato na próxima rodada)"]);
  // o reembolso substitui a pendência "acerto do técnico" da F2: nada de "ainda não entra nas Diárias"
  const tecnico = frasesDaGravacao([{ tipo: "despesa_os" }, { tipo: "reembolso_tecnico", valor: "62.00" }], cmpDoExtrato({ quem_pagou: "tecnico", pagador_nome: "Roberto" }));
  assertEquals(tecnico.some((x) => x.includes("ainda não entra")), false);

  // depois de gravar com azul: "No extrato: <a pergunta>" no lugar de "Fila vazia"
  const azul = perguntaDoExtrato([DEBITO, { ...DEBITO, n: 2, id: "t-2", data: "2026-10-09" }], true);
  const t = textoDaGravacao({
    cmp: cmpDoExtrato(), proxima: null, banco: azul,
    gravacao: { situacao: "aguardando_banco", efeitos: [{ tipo: "despesa_os" }, { tipo: "aguardar_banco", regra: "debito", nivel: "azul" }], banco: { nivel: "azul", perguntar: true } },
  });
  assertStringIncludes(t, "CMP-00124 gravado: lancei a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS); já há linhas parecidas no extrato: pergunto qual é. Arquivo: Brisa/1- DOC's/Compras.");
  assertStringIncludes(t, "\n\nNo extrato: CMP-00124 · cupom NFC-e · AutoZone · 08/10 · R$ 50,98\nApareceram no extrato linhas");
  assertEquals(t.includes("Fila vazia"), false);

  // o cartão: "No extrato: <onde está>"
  const cartao = (b: CmpResumo["banco"], extra: Partial<CmpResumo> = {}) => textoDoCartao(cmpDoExtrato({ banco: b, ...extra }), [{ tipo: "aguardar_banco", regra: "debito" }]);
  assertStringIncludes(cartao({ estado: "esperando", ate: "2026-11-09" }), "CMP-00124 (esperando o banco):");
  assertStringIncludes(cartao({ estado: "esperando", ate: "2026-11-09" }), " No extrato: esperando a linha (até 09/11). Para cancelar: *cancelar cmp 124 motivo*.");
  assertStringIncludes(cartao({ estado: "perguntar" }), "No extrato: pergunta pendente (*cmp 124* para responder).");
  assertStringIncludes(cartao(ligado.banco, { situacao: "conciliado" }), "CMP-00124 (ligado ao extrato):");
  assertStringIncludes(cartao(ligado.banco), "No extrato: ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98).");
  assertStringIncludes(cartao({ estado: "abandonado" }, { situacao: "abandonado" }), "No extrato: não apareceu em 30 dias: classifique no Extrato.");
  assertStringIncludes(cartao({ estado: "abandonado" }, { situacao: "abandonado", forma: "credito" }), "não apareceu em 45 dias");
  // regra E: falta o "quem pagou?"
  assertStringIncludes(cartao({ estado: "banco_quem" }), "No extrato: falta saber quem pagou (não apareceu em conta da empresa: *cmp 124* para responder).");
  // CMP que não procura linha (sem banco): o cartão de antes
  assertEquals(textoDoCartao(cmp({ situacao: "gravado" }), [{ tipo: "caixa" }]).includes("No extrato"), false);
});

Deno.test("F3 resultados da resposta: ligado (por como), recusado, mudou, inválida e não ligado", () => {
  const ligado = cmpDoExtrato({
    situacao: "conciliado",
    banco: { estado: "ligado", linha: { data: "2026-10-08", valor: "50.98", descricao: "DEBITO DE CARTAO", conta: "C6 - Conta PJ HBR", como: "classificou" } },
  });
  // ajustes do dono: o sim aprova a linha (lancei), falhou agora (tento de novo) ou a proposta ainda não estava na fila
  assertEquals(
    textoDoLigado(ligado, { tipo: "ligar_linha", como: "classificou", mensagens: [] }, { ok: true }),
    "CMP-00124 ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98): lancei no Extrato como Peças e materiais, OS-00112.",
  );
  assertEquals(
    textoDoLigado(ligado, { tipo: "ligar_linha", como: "classificou" }, { ok: false, motivo: "linha_lancada" }),
    "CMP-00124 ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98): classifiquei a linha como Peças e materiais, OS-00112, mas não consegui aprovar agora (a linha já virou outro lançamento): tento de novo na próxima rodada do Extrato.",
  );
  assertEquals(
    textoDoLigado(ligado, { tipo: "ligar_linha", como: "classificou" }),
    "CMP-00124 ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98): classifiquei como Peças e materiais, OS-00112 (lanço no Extrato na próxima rodada).",
  );
  assertStringIncludes(textoDoLigado(ligado, { tipo: "ligar_linha", como: "classificou" }, { ok: true, nada: true }), "(lanço no Extrato na próxima rodada)");
  // regra G: o lançamento que já existia só teve o vazio preenchido
  assertStringIncludes(textoDoLigado(ligado, { tipo: "ligar_linha", como: "anexou", corrigido: { expense_category: { antes: null, depois: "Peças e materiais" } } }),
    ": a linha já estava lançada: anexei e preenchi a categoria, que estava vazia.");
  assertStringIncludes(textoDoLigado(ligado, { tipo: "ligar_linha", como: "anexou", corrigido: {} }), ": a linha já estava lançada: anexei.");
  assertStringIncludes(textoDoLigado(ligado, { tipo: "ligar_linha", como: "casou", conta_aberta: { descricao: "Fatura AutoZone" } }), ': dei baixa na conta a pagar "Fatura AutoZone".');
  assertStringIncludes(textoDoLigado(ligado, { tipo: "ligar_linha", como: "aguardando" }), ": lanço no Extrato assim que a compra entrar na fila (aprovada no seu sim).");
  // o motivo da aprovação que falhou nunca leva a mensagem crua do Postgres
  assertEquals(motivoDaAprovacao('duplicate key value violates unique constraint "payables_uma_por_transacao"'), "erro no sistema");
  assertEquals(motivoDaAprovacao("approve_cmp:500"), "erro no sistema");
  assertEquals(motivoDaAprovacao(null), "erro no sistema");
  assertEquals(
    textoDoLigado(ligado, { tipo: "ligar_linha", como: "classificou", mensagens: ["O mês 09/2026 está fechado: só classifiquei."] }).split("\n")[1],
    "O mês 09/2026 está fechado: só classifiquei.",
  );
  assertEquals(textoDoRecusado("CMP-00124", "2026-11-07", false), "Ok, não é essa. O CMP-00124 continua esperando a linha certa no extrato (até 07/11).");
  assertEquals(textoDoRecusado("CMP-00124", "2026-11-07", true), "Ok, nenhuma destas. O CMP-00124 continua esperando a linha certa no extrato (até 07/11).");
  assertEquals(
    textoDoMudou("CMP-00124", "2026-11-07", null),
    "As linhas do extrato mudaram desde a pergunta. Não há mais linha que sirva: o CMP-00124 continua esperando o extrato (até 07/11).",
  );
  assert(textoDoMudou("CMP-00124", null, perguntaDoExtrato([DEBITO], false)).startsWith("As linhas do extrato mudaram desde a pergunta.\n\nCMP-00124 · "));
  assertEquals(textoInvalidaDoExtrato("CMP-00124", false), "Responda *sim* se essa linha é do CMP-00124, ou *não*.");
  assertEquals(textoInvalidaDoExtrato("CMP-00124", true, 3), "Responda o número da linha (1 a 3) ou 0 se não for nenhuma.");
  assertEquals(textoInvalidaDoExtrato("CMP-00124", true, 1), "Responda o número da linha (1) ou 0 se não for nenhuma.");
  // não ligado: o erro conhecido em texto fixo; a frase das rotas; a mensagem crua do Postgres nunca
  assertStringIncludes(textoNaoLigado("CMP-00124", "O mês 09/2026 está fechado", 124), "Não liguei o CMP-00124: o mês (09/2026) está fechado no financeiro");
  assertEquals(
    textoNaoLigado("CMP-00124", "P0001: Esta linha já está ligada a outro lançamento.", 124),
    "Não liguei o CMP-00124: Esta linha já está ligada a outro lançamento. Nada mudou. Responda de novo para tentar outra vez.",
  );
  assertEquals(
    textoNaoLigado("CMP-00124", 'new row for relation "payables" violates check constraint "x"', 124, "23514"),
    "Não liguei o CMP-00124: deu um erro no sistema (código 23514). Nada mudou. Responda de novo para tentar outra vez.",
  );
});

Deno.test("F3 pendentes, avisos, cancelamento e bloqueios", () => {
  const t = textoDosPendentes({
    abertos: [
      { codigo: "CMP-00124", numero: 124, data: "2026-10-08", valor: "50.98", fornecedor: "AutoZone", situacao: "aguardando_banco", banco: "perguntar", pendencias: [] },
      { codigo: "CMP-00119", numero: 119, data: "2026-09-01", valor: "80.00", situacao: "abandonado", pendencias: ["classificar_no_extrato"] },
      { codigo: "CMP-00118", numero: 118, data: "2026-10-05", valor: "900.00", situacao: "aguardando_xml", nota_no_email: true },
    ],
    total: 3,
  });
  assertStringIncludes(t ?? "", "1. CMP-00124 · 08/10 · R$ 50,98 · AutoZone — esperando o banco; falta: ligar ao extrato");
  assertStringIncludes(t ?? "", "2. CMP-00119 · 01/09 · R$ 80,00 — sem linha no extrato; falta: classificar no Extrato");
  assertStringIncludes(t ?? "", "3. CMP-00118 · 05/10 · R$ 900,00 — a nota chegou por e-mail: importe em Entrada de Mercadoria");
  // o gravado de sempre não muda
  assertStringIncludes(
    textoDosPendentes({ abertos: [{ codigo: "CMP-00117", situacao: "gravado", pendencias: ["dar_entrada"] }], total: 1 }) ?? "",
    "CMP-00117 — gravado; falta: dar entrada no estoque",
  );
  assertEquals(textosDosAvisos(["tecnico_fora_das_diarias", "linha_lancada_em_outro"], cmpDoExtrato({ pagador_nome: "Alex" })), [
    'O Alex não tem diária nas Diárias: o reembolso fica como pendência "acerto do técnico".',
    "A linha do banco já foi lançada em outro registro: confira no Extrato.",
  ]);
  assertEquals(
    textoDoCancelamento("CMP-00124", "comprei em dobro", { ok: true, desfeitos: [{ tipo: "ligar_linha" }, { tipo: "reembolso_tecnico" }, { tipo: "aguardar_banco" }] }),
    "CMP-00124 cancelado (comprei em dobro). Desfeito: a ligação com a linha do banco (a linha volta para a fila do Extrato), o reembolso nas Diárias. Arquivo em COMPROVANTES/_CANCELADOS.",
  );
  // a linha que o sim aprovou: o cancelar desfaz a aprovação também
  assertEquals(
    textoDoCancelamento("CMP-00124", "comprei em dobro", { ok: true, desfeitos: [{ tipo: "ligar_linha", aprovado: { payable_id: "pay-1" } }] }),
    "CMP-00124 cancelado (comprei em dobro). Desfeito: a aprovação e a ligação com a linha do banco (a linha volta para a fila do Extrato). Arquivo em COMPROVANTES/_CANCELADOS.",
  );
  // regra E nos pendentes: falta o "quem pagou?"
  assertStringIncludes(
    textoDosPendentes({ abertos: [{ codigo: "CMP-00131", situacao: "aguardando_banco", banco: "banco_quem", pendencias: [] }], total: 1 }) ?? "",
    "CMP-00131 — esperando o banco; falta: quem pagou (não apareceu no extrato)",
  );
  // o banco monta o texto do bloqueio com o dia da linha e o nº do acerto (como_destravar)
  assertEquals(
    textoDoCancelamento("CMP-00124", "x", { ok: false, bloqueios: [{
      efeito: "ligar_linha", motivo: "linha_lancada", como_destravar: "a linha do banco de 08/10 já virou lançamento: desfaça pelo Extrato e cancele de novo",
    }] }),
    "Não cancelei o CMP-00124: a linha do banco de 08/10 já virou lançamento: desfaça pelo Extrato e cancele de novo. Nada mudou.",
  );
  assertStringIncludes(
    textoDoCancelamento("CMP-00124", "x", { ok: false, bloqueios: [{
      efeito: "reembolso_tecnico", motivo: "reembolso_acertado", como_destravar: "reabra o acerto nº 0007 em Financeiro › Diárias e cancele de novo",
    }] }),
    "Não cancelei o CMP-00124: reabra o acerto nº 0007 em Financeiro › Diárias e cancele de novo. Nada mudou.",
  );
  // sem o texto do banco: o modelo sem o dia/número
  assertStringIncludes(
    textoDoCancelamento("CMP-00124", "x", { ok: false, bloqueios: [{ efeito: "ligar_linha", motivo: "linha_casada" }] }),
    "a linha do banco já deu baixa na conta a pagar: desfaça pelo Extrato e cancele de novo",
  );
  assertStringIncludes(
    textoDoCancelamento("CMP-00124", "x", { ok: false, bloqueios: [{ efeito: "reembolso_tecnico", motivo: "reembolso_acertado" }] }),
    "o reembolso já está num acerto fechado das Diárias",
  );
});

Deno.test("F3 não ligado: os códigos da ligação viram texto fixo; a gravação que não ligou (baixa recusada) diz que pergunta de novo", () => {
  const casos: Array<[string, string]> = [
    ["linha_de_outro_cmp", "essa linha do extrato já está ligada a outro comprovante"],
    ["linha_nao_serve", "essa linha não serve mais para ele (o extrato mudou)"],
    ["ja_ligado_a_outra", "ele já está ligado a outra linha do extrato"],
    ["cancelado", "ele foi cancelado"],
    ["codigo_novo_qualquer", "essa linha não serve mais para ele"],
  ];
  for (const [codigo, texto] of casos) {
    assertEquals(textoNaoLigado("CMP-00124", codigo, 124), `Não liguei o CMP-00124: ${texto}. Nada mudou. Responda de novo para tentar outra vez.`, codigo);
  }
  // a baixa recusada pela rota de conciliação (mês fechado): o texto do não gravado
  assertStringIncludes(
    textoNaoLigado("CMP-00124", "Não dei baixa na conta a pagar: O mês 09/2026 está fechado.", 124),
    "o mês (09/2026) está fechado no financeiro",
  );
  assertEquals(
    frasesDaGravacao([{ tipo: "aguardar_banco", regra: "debito", nivel: "verde" }], cmpDoExtrato()),
    ["não liguei agora à linha do extrato: pergunto de novo se é esta"],
  );
});

Deno.test("F3 conflito: a conta do CMP em aberto + a linha já lançada em outro registro — não liga e diz para cancelar um dos dois", () => {
  const conta = { descricao: "Fatura AutoZone", valor: "50.98" };
  const lancada = { ...DEBITO, n: 2, id: "t-2", data: "2026-10-09", forte: false, acao: "conflito", lancamento: { categoria: "Outras despesas" }, conta_aberta: conta };
  const outra = { ...DEBITO, forte: false, acao: "casar", conta_aberta: conta };
  const t = textoDaPerguntaDoExtrato(perguntaDoExtrato([outra, lancada], true));
  assertStringIncludes(t, "2 C6 - Conta PJ HBR · 09/10 · DEBITO DE CARTAO · R$ 50,98 · já lançada (Outras despesas)");
  // o "Ligando, …" vale para as outras linhas; a do conflito tem a frase dela
  assertStringIncludes(t, 'Ligando, dou baixa na conta a pagar "Fatura AutoZone" (R$ 50,98) com ela.');
  assertStringIncludes(
    t,
    'A linha 2: não ligo essa: a conta a pagar "Fatura AutoZone" (R$ 50,98) continua em aberto e a linha já virou outro lançamento — o mesmo gasto duas vezes; cancele um dos dois no Financeiro.',
  );
  // o dono escolheu a linha do conflito: não liguei, com o porquê
  assertEquals(
    textoNaoLigado("CMP-00124", "conflito", 124),
    "Não liguei o CMP-00124: a conta a pagar dele continua em aberto e essa linha já virou outro lançamento (o mesmo gasto duas vezes): cancele um dos dois no Financeiro. Nada mudou. Responda de novo para tentar outra vez.",
  );
  assertEquals(textosDosAvisos(["conta_aberta_e_linha_lancada"], cmpDoExtrato()), [
    "A conta a pagar deste gasto continua em aberto e a linha do banco já virou outro lançamento: é o mesmo gasto duas vezes. Cancele um dos dois no Financeiro; não ligo a linha.",
  ]);
});

Deno.test("F2b despesa já reembolsada e F3 estorno: textos do plano, da gravação, do aviso e da pendência", () => {
  const c = cmpDoExtrato({ quem_pagou: "tecnico", pagador_nome: "Roberto" });
  assertEquals(frasesDoPlano({ efeitos: [{ tipo: "nada", motivo: "ja_reembolsado", pagador_nome: "Roberto" }] }, c), [
    "nada no financeiro: a despesa da OS já foi reembolsada ao Roberto",
  ]);
  assertEquals(frasesDaGravacao([{ tipo: "nada", motivo: "ja_reembolsado", pagador_nome: "Roberto" }], c), [
    "nada no financeiro: a despesa da OS já tinha sido reembolsada ao Roberto",
  ]);
  assertEquals(textosDosAvisos(["despesa_ja_reembolsada"], c), [
    "A despesa da OS já foi reembolsada ao Roberto (Financeiro › Reembolsos): não lanço outro reembolso nas Diárias.",
  ]);
  assertStringIncludes(
    textoDosPendentes({ abertos: [{ codigo: "CMP-00130", situacao: "aguardando_banco", pendencias: ["conferir_estorno"] }], total: 1 }) ?? "",
    "falta: conferir a despesa da compra estornada no banco",
  );
});

// ─── revisão dos ajustes do dono (11/10/2026) ───────────────────────────────────────────────────

Deno.test("revisão dos ajustes: a vigia do quem pagou, o sócio com a conta do fornecedor em aberto e o reembolso já dividido", () => {
  const c = cmpDoExtrato({ quem_pagou: "socio" });
  assertStringIncludes(
    textoDosPendentes({ abertos: [{ codigo: "CMP-00131", situacao: "gravado", pendencias: ["conferir_quem_pagou"] }], total: 1 }) ?? "",
    "falta: conferir quem pagou: a compra apareceu numa conta da empresa",
  );
  const [aviso] = textosDosAvisos(["conta_aberta_paga_pelo_socio"], c);
  assertStringIncludes(aviso, "A conta a pagar deste fornecedor (mesmo valor) continua em aberto: não lanço reembolso para você");
  assertEquals(/\n/.test(aviso), false);
  // o bloqueio do reembolso já pago num pagamento dividido: o texto do banco (Pix/Caixa ou bolso do sócio)
  assertEquals(
    textoDoCancelamento("CMP-00124", "x", { ok: false, bloqueios: [{
      efeito: "reembolso_tecnico", motivo: "reembolso_dividido",
      como_destravar: "o reembolso já foi pago ao técnico num pagamento dividido: desfaça a divisão em Financeiro › Diárias (Desfazer a divisão) e cancele de novo",
    }] }),
    "Não cancelei o CMP-00124: o reembolso já foi pago ao técnico num pagamento dividido: desfaça a divisão em Financeiro › Diárias (Desfazer a divisão) e cancele de novo. Nada mudou.",
  );
  assertStringIncludes(
    textoDoCancelamento("CMP-00124", "x", { ok: false, bloqueios: [{ efeito: "reembolso_tecnico", motivo: "reembolso_dividido" }] }),
    "desfaça a divisão em Financeiro › Diárias e cancele de novo",
  );
});

// ─── regra E (ajustes do dono): "quem pagou?" depois de 5 dias sem aparecer em conta da empresa ──

const QUEM_OPCOES = [
  { n: 1, rotulo: "A empresa (ainda vai aparecer no extrato: continuo esperando até 09/11)", valor: "empresa" },
  { n: 2, rotulo: "Eu, do meu bolso ou do meu cartão pessoal (fica como reembolso para você)", valor: "socio" },
  { n: 3, rotulo: "O Roberto (técnico: reembolso nas Diárias)", valor: "payee:p-rob" },
  { n: 4, rotulo: "Foi gasto pessoal, no meu cartão (só guardo o arquivo)", valor: "pessoal" },
];

function perguntaDoQuem(extra: Partial<PerguntaDoExtrato> = {}, c: Partial<CmpResumo> = {}): PerguntaDoExtrato {
  return {
    pergunta_id: "p-q", dedupe_key: "cmp:p:p-q", cmp: cmpDoExtrato({ data: "2026-10-10", ...c }), passo: "banco_quem", opcoes: QUEM_OPCOES,
    retomada: false, banco: { nivel: "cinza", linhas: [], hash: "h" }, ...extra,
  };
}

Deno.test("regra E: a pergunta 'quem pagou?' ao pé da letra e a retomada do vigia", () => {
  assertEquals(
    textoDaPerguntaDoExtrato(perguntaDoQuem()),
    [
      "CMP-00124 · cupom NFC-e · AutoZone · 10/10 · R$ 50,98",
      "Esta compra de 10/10 ainda não apareceu em nenhuma conta da empresa. Quem pagou?",
      "1 A empresa (ainda vai aparecer no extrato: continuo esperando até 09/11)",
      "2 Eu, do meu bolso ou do meu cartão pessoal (fica como reembolso para você)",
      "3 O Roberto (técnico: reembolso nas Diárias)",
      "4 Foi gasto pessoal, no meu cartão (só guardo o arquivo)",
    ].join("\n"),
  );
  assertEquals(prefixoDaPerguntaDoExtrato({ ...perguntaDoQuem(), retomada: true }, "vigia"), "Ainda falta saber quem pagou o CMP-00124.");
  assertEquals(textoInvalidaDoQuemPagou("CMP-00124", 4), "Para o CMP-00124, responda o número de quem pagou (1 a 4).");
});

Deno.test("regra E: esperando, regravado (com o aviso do almoço) e não trocado", () => {
  assertEquals(textoDoQuemEsperando("CMP-00124", "2026-11-09"), "Ok: o CMP-00124 continua esperando o extrato (até 09/11).");
  const pelo = cmpDoExtrato({ situacao: "gravado", quem_pagou: "tecnico", pagador_nome: "Roberto", categoria: "Alimentação de campo" });
  const regravado = textoDoRegravado(pelo, {
    situacao: "gravado", pasta: "Brisa/1- DOC's/Compras",
    efeitos: [{ tipo: "despesa_os" }, { tipo: "reembolso_tecnico", favorecido_nome: "Roberto", valor: "50.98", extra_do_dia: { valor: "20.00", data: "2026-10-10" } }],
    avisos: ["almoco_ja_no_extra"],
  });
  assertStringIncludes(regravado, "CMP-00124 corrigido: pago pelo Roberto. Feito: lancei a despesa na OS-00112 como custo interno");
  assertStringIncludes(regravado, "lancei R$ 50,98 nas Diárias do Roberto como reembolso de despesa paga pelo técnico. Arquivo: Brisa/1- DOC's/Compras.");
  assertStringIncludes(semNbsp(regravado), "O Roberto já tinha recebido R$ 20,00 de almoço (extra da diária de 10/10): confira se o reembolso não ficou em dobro.");
  assertStringIncludes(textoDoRegravado(cmpDoExtrato({ quem_pagou: "socio" }), { situacao: "gravado", efeitos: [{ tipo: "reembolso_socio" }] }),
    "CMP-00124 corrigido: pago por você. Feito: lancei R$ 50,98 como reembolso a você.");
  assertStringIncludes(textoDoRegravado(cmpDoExtrato({ destino: "pessoal", os: null, quem_pagou: "socio" }), { situacao: "gravado", efeitos: [{ tipo: "nada", motivo: "pessoal" }] }),
    "CMP-00124 corrigido: gasto pessoal. Feito: só guardei o arquivo (nada no financeiro).");
  assertEquals(
    textoDoNaoTrocado("CMP-00124", { bloqueios: [{ efeito: "anotar", motivo: "anotacao_aplicada" }] }, 124),
    "Não troquei quem pagou o CMP-00124: a linha do banco já recebeu a classificação; corrija pelo Extrato. Nada mudou.",
  );
  assertEquals(
    textoDoNaoTrocado("CMP-00124", { motivo: "mes_fechado" }, 124),
    "Não troquei quem pagou o CMP-00124: o mês está fechado no financeiro; reabra o mês e mande *cmp 124* para responder de novo. Nada mudou.",
  );
  assertEquals(
    textoDoNaoTrocado("CMP-00124", { motivo: 'new row for relation "x" violates check constraint "y"' }, 124, "23514"),
    "Não troquei quem pagou o CMP-00124: deu um erro no sistema (código 23514). Nada mudou.",
  );
});

Deno.test("F3: nenhum texto passa de 4096, nenhum tem emoji nem CPF; nenhum fala em cobrar nem em 'falta aprovar'", () => {
  const longa = { ...DEBITO, descricao: "Y".repeat(5000), conta: "Z".repeat(5000) };
  const textos = [
    textoDaPerguntaDoExtrato(perguntaDoExtrato([longa, longa, longa], true, { banco: { nivel: "azul", linhas: [longa, longa, longa], mais: 40 } })),
    textoDaPerguntaDoExtrato(perguntaDoExtrato([DEBITO], false)),
    textoDoLigado(cmpDoExtrato(), { tipo: "ligar_linha", como: "classificou", mensagens: ["m".repeat(5000)] }),
    textoDoLigado(cmpDoExtrato(), { tipo: "ligar_linha", como: "classificou" }, { ok: false, motivo: "x".repeat(5000) }),
    textoDoRecusado("CMP-00124", "2026-11-07", true),
    textoDoMudou("CMP-00124", null, null),
    textoNaoLigado("CMP-00124", "x".repeat(5000), 124),
    textoDaPerguntaDoExtrato(perguntaDoQuem({ opcoes: [{ n: 1, rotulo: "r".repeat(5000), valor: "empresa" }] })),
    textoDoRegravado(cmpDoExtrato(), { situacao: "gravado", efeitos: [], mensagens: ["m".repeat(5000)] }),
    textoDoNaoTrocado("CMP-00124", { motivo: "x".repeat(5000) }, 124),
    textoDoResumo(pergunta("confirmar", { plano: PLANO_A })),
    textoDaPergunta(pergunta("tipo_na_os")),
  ];
  for (const s of textos) {
    assert(s.length <= MAX_MENSAGEM, `${s.length}`);
    assertEquals(/\p{Extended_Pictographic}/u.test(s), false, s.slice(0, 80));
    assertEquals(/\d{3}\.?\d{3}\.?\d{3}-?\d{2}/.test(s), false, "sem CPF");
    assertEquals(/cobr|falta aprovar/i.test(s), false, s.slice(0, 120));
  }
});

// ─── o assistente opera o CMP (11/10/2026 — spec-assistente-opera-cmp.md, A e B) ────────────

Deno.test("A: textoDoAnotadoNaConversa — o caso real (categoria, valor com o do comprovante, observação) e o 'Não usei'", () => {
  const itens = [
    { campo: "categoria", valor: "Combustível e deslocamento" },
    { campo: "valor", valor: "235.97", lido: "204.87" },
  ];
  // 12/10/2026: a observação fica guardada no CMP; a frase deixa de ser "Motivo:" e vira "Observação:"
  assertEquals(
    semNbsp(textoDoAnotadoNaConversa("CMP-00001", itens, "cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão", "OS-00999 (não achei essa OS)")),
    "CMP-00001: anotei o que você disse na conversa: categoria Combustível e deslocamento, valor R$ 235,97 (no comprovante: R$ 204,87). " +
      "Observação: cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão. Não usei: OS-00999 (não achei essa OS).",
  );
  // cada item como o dono lê
  assertEquals(textosDosItensAnotados([
    { campo: "data", valor: "2026-10-10" }, { campo: "os", valor: "OS-00112" }, { campo: "para", valor: "estoque" },
    { campo: "para", valor: "insumo" }, { campo: "para", valor: "empresa" }, { campo: "para", valor: "pessoal" },
    { campo: "forma", valor: "credito" }, { campo: "forma", valor: "dinheiro" }, { campo: "forma", valor: "transferencia" },
    { campo: "quem_pagou", valor: "empresa" }, { campo: "quem_pagou", valor: "socio" }, { campo: "quem_pagou", valor: "tecnico", nome: "Roberto" },
    { campo: "quem_pagou", valor: "cliente" }, { campo: "tipo_na_os", valor: "despesa" }, { campo: "tipo_na_os", valor: "peca" },
    { campo: "valor", valor: "62.00", lido: "62.00" },
  ]), [
    "data 10/10", "para a OS-00112", "para o estoque", "para insumo", "para a empresa (sem OS)", "pessoal", "no crédito", "em dinheiro",
    "na transferência", "pago pela empresa", "pago por você (reembolso)", "pago pelo técnico Roberto", "o cliente pagou direto",
    "despesa da OS (custo interno)", "peça da OS", "valor R$ 62,00",
  ]);
  // a observação vai numa linha só e cortada em 120; sem nada anotado, diz isso
  const longo = textoDoAnotadoNaConversa("CMP-00001", itens, `linha 1\nlinha 2 ${"x".repeat(300)}`, null);
  assertEquals(longo.includes("\n"), false);
  const motivo = /Observação: (.*)$/.exec(longo)?.[1] ?? "";
  assert(motivo.length > 100 && motivo.length <= 121, `${motivo.length}`);
  assertEquals(textoDoAnotadoNaConversa("CMP-00001", [], null, null), "CMP-00001: o que você disse na conversa já estava anotado.");
  // nada anotado e algo para o passo dele (quem pagou, peça ou despesa): nunca "já estava anotado"
  assertEquals(textoDoAnotadoNaConversa("CMP-00001", [], null, null, true),
    "CMP-00001: o que você disse na conversa eu pergunto na sequência, um passo por vez.");
  assertEquals(textoDoAnotadoNaConversa("CMP-00001", [], null, "técnico Zé (não achei esse técnico)"),
    "CMP-00001: não anotei nada do que você disse na conversa. Não usei: técnico Zé (não achei esse técnico).");
  // com a pergunta: sem emoji, até 4096
  const p = pergunta("para_que", { opcoes: [{ n: 1, rotulo: "OS-00112 · Brisa", valor: "os:1" }, { n: 2, rotulo: "Empresa (sem OS)", valor: "empresa" }] });
  const msg = comAPergunta(textoDoAnotadoNaConversa("CMP-00124", itens, "y".repeat(500), "z".repeat(500)), p);
  assert(msg.length <= MAX_MENSAGEM);
  assertEquals(/\p{Extended_Pictographic}/u.test(msg), false);
  assertStringIncludes(msg, "\n\nCMP-00124 (1 de 4) · cupom NFC-e");
  assert(comAPergunta("x".repeat(5000), p).length <= MAX_MENSAGEM);
});

Deno.test("A: o resumo mostra o valor do comprovante quando o gravado é outro (o do cartão, o corrigir valor)", () => {
  const linhaDoValor = (c: Partial<CmpResumo>) => semNbsp(textoDoResumo(pergunta("confirmar", { plano: { efeitos: [] } }, c)).split("\n")[1]);
  assertEquals(linhaDoValor({ valor: "235.97", valor_lido: "204.87" }), "• R$ 235,97 (no comprovante: R$ 204,87) em 10/10 às 12h57 · Auto Posto Exemplo");
  // igual (ou diferença de centavo de arredondamento): nada a mais
  assertEquals(linhaDoValor({ valor: "62.00", valor_lido: "62.00" }), "• R$ 62,00 em 10/10 às 12h57 · Auto Posto Exemplo");
  assertEquals(linhaDoValor({ valor: "62.01", valor_lido: "62.00" }), "• R$ 62,01 em 10/10 às 12h57 · Auto Posto Exemplo");
  // sem leitura: nada a comparar
  assertEquals(linhaDoValor({ valor: "70.00", valor_lido: null, valor_confianca: "alta" }), "• R$ 70,00 em 10/10 às 12h57 · Auto Posto Exemplo");
});

Deno.test("B: textoDaCategoriaAnotada — no 'para quê' repergunta o destino; nos outros passos, só a linha", () => {
  assertEquals(textoDaCategoriaAnotada("Combustível e deslocamento", "para_que"),
    "Categoria anotada: Combustível e deslocamento. Foi para qual OS ou para a empresa?");
  assertEquals(textoDaCategoriaAnotada("Combustível e deslocamento", "como_pagou"), "Categoria anotada: Combustível e deslocamento.");
  assertEquals(textoDaCategoriaAnotada("", null), "Categoria anotada.");
  // a mensagem: a linha, uma linha em branco e a pergunta inteira com o MESMO menu
  const p = pergunta("para_que", { opcoes: [{ n: 1, rotulo: "OS-00112 · Brisa", valor: "os:1" }, { n: 2, rotulo: "Empresa (sem OS)", valor: "empresa" }] });
  const msg = comAPergunta(textoDaCategoriaAnotada("Combustível e deslocamento", p.passo), p);
  assert(msg.startsWith("Categoria anotada: Combustível e deslocamento. Foi para qual OS ou para a empresa?\n\nCMP-00124"));
  assertStringIncludes(msg, "Para quê?\n1 OS-00112 · Brisa\n2 Empresa (sem OS)\nResponda o número, o nome do barco ou *os N*.");
});

// ─── A observação guardada no CMP (12/10/2026 — spec-observacao-atomica-prefixo.md, 2.4) ─────

Deno.test("A obs: o resumo traz a linha '• Observação:' depois do '• Pago:', numa linha só e cortada em 120", () => {
  const resumo = (c: Partial<CmpResumo>) => textoDoResumo(pergunta("confirmar", { plano: { efeitos: [] } }, c)).split("\n");
  const linhas = resumo({ destino: "empresa", os: null, quem_pagou: "empresa", observacao: "complemento de R$ 31,10 sem cupom" });
  const i = linhas.findIndex((l) => l.startsWith("• Pago:"));
  assert(i > 0, linhas.join("|"));
  assertEquals(linhas[i + 1], "• Observação: complemento de R$ 31,10 sem cupom");
  // sem pagador: logo depois do "Para:"
  const semPago = resumo({ forma: null, observacao: "taxa de entrega" });
  assertEquals(semPago.some((l) => l.startsWith("• Pago:")), false);
  assertEquals(semPago[semPago.findIndex((l) => l.startsWith("• Para:")) + 1], "• Observação: taxa de entrega");
  // sem observação: nenhuma linha a mais (o resumo de hoje)
  assertEquals(resumo({ observacao: null }).some((l) => l.startsWith("• Observação")), false);
  assertEquals(resumo({}).some((l) => l.startsWith("• Observação")), false);
  // numa linha e cortada em 120 (com "…")
  const longa = resumo({ observacao: `linha 1\nlinha 2 ${"x".repeat(300)}` }).find((l) => l.startsWith("• Observação: "))!;
  assertEquals(longa.length <= "• Observação: ".length + 120, true, `${longa.length}`);
  assert(longa.endsWith("…"));
});

Deno.test("A obs: textoCorrigido anota e apaga; o 'corrigir obs' sem texto ensina; o 'corrigir' sozinho cita *corrigir obs*", () => {
  assertEquals(textoCorrigido("CMP-00001", { campo: "obs", valor: "complemento de R$ 31,10 sem cupom" }),
    "CMP-00001: observação anotada: complemento de R$ 31,10 sem cupom.");
  assertEquals(textoCorrigido("CMP-00001", { campo: "obs", valor: null }), "CMP-00001: observação apagada.");
  assertEquals(textoCorrigido("CMP-00001", { campo: "obs", valor: `a\nb ${"y".repeat(200)}` })!.includes("\n"), false);
  assertEquals(textoCorrigirIncompleto("obs"), "Para corrigir, mande junto o novo dado: *corrigir obs complemento sem cupom*.");
  assertStringIncludes(TEXTO_CORRIGIR_COMO, "*corrigir categoria* ou *corrigir obs <texto>*.");
});

Deno.test("A obs: textoDoAnotadoNaConversa — a observação sai da lista, abre sozinha e vira 'Observação:'; o item da tool é 'a observação'", () => {
  const obs = { campo: "obs", valor: "complemento de R$ 31,10 sem cupom" };
  // com outro item: a lista não repete a observação; a frase "Observação:" vem depois
  assertEquals(
    semNbsp(textoDoAnotadoNaConversa("CMP-00001", [{ campo: "valor", valor: "235.97", lido: "204.87" }, obs], obs.valor, null)),
    "CMP-00001: anotei o que você disse na conversa: valor R$ 235,97 (no comprovante: R$ 204,87). Observação: complemento de R$ 31,10 sem cupom.",
  );
  // só a observação anotada
  assertEquals(textoDoAnotadoNaConversa("CMP-00001", [obs], obs.valor, null),
    "CMP-00001: anotei a observação que você disse na conversa. Observação: complemento de R$ 31,10 sem cupom.");
  // a observação já igual (nada anotado): a frase aparece
  assertEquals(textoDoAnotadoNaConversa("CMP-00001", [], "taxa", null),
    "CMP-00001: o que você disse na conversa já estava anotado. Observação: taxa.");
  // a lista da tool diz "a observação" (o texto nunca vai ao modelo pela lista)
  assertEquals(textosDosItensAnotados([{ campo: "categoria", valor: "Alimentação de campo" }, obs]), ["categoria Alimentação de campo", "a observação"]);
});
