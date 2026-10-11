// Nome final, pasta final e o índice CSV do mês (seção 4 da spec).
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  caminhoDoIndice,
  caminhoDoIndicePessoal,
  campoCsv,
  COLUNAS_DO_INDICE,
  csvDoIndice,
  type DestinoDoArquivo,
  type LinhaDoIndice,
  nomeCancelado,
  nomeDoCaminho,
  nomeFinal,
  pastaFinal,
  semCpf,
  usaPastaDoBarco,
} from "./destino.ts";

function d(extra: Partial<DestinoDoArquivo> = {}): DestinoDoArquivo {
  return {
    id: "c-1", codigo: "CMP-00124", situacao: "gravado", cancelado: false, tipo: "nfce", valor: "62.00", valor_confirmado: true,
    data: "2026-10-10", hora: "12:57:56", fornecedor: "Auto Posto Exemplo", destino: "os",
    os: { numero: "OS-00112", vessel_id: "v-1", client_id: "cl-1", barco: "Brisa", cliente: "João", pasta_registrada: true },
    forma: "debito", conta: "EMPRESA", mes: "2026-10", dropbox_id: "id:abc", dropbox_caminho: "/MANAGEMENT/FINANCIALS/COMPROVANTES/_A CLASSIFICAR/x.jpg",
    dropbox_pendente: "mover", arquivo_path: "2026/10/c-1.jpg", arquivo_mime: "image/jpeg", ...extra,
  };
}

Deno.test("nomeFinal: o exemplo da spec", () => {
  assertEquals(nomeFinal(d()), "2026-10-10 12h57 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - OS-00112 Brisa - DEBITO EMPRESA.jpg");
});

Deno.test("nomeFinal: sem hora, destinos, pagamentos, conta do sócio e pessoal sem pagamento", () => {
  assertEquals(nomeFinal(d({ hora: null, destino: "estoque", os: null, forma: "pix", conta: "NUBANK" })),
    "2026-10-10 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - ESTOQUE - PIX NUBANK.jpg");
  assertEquals(nomeFinal(d({ destino: "empresa", os: null, forma: "dinheiro", conta: "CAIXA" })).endsWith(" - EMPRESA - DINHEIRO CAIXA.jpg"), true);
  assertEquals(nomeFinal(d({ destino: "insumo", os: null, forma: "dinheiro", conta: "BOLSO GUSTAVO" })).endsWith(" - INSUMO - DINHEIRO BOLSO GUSTAVO.jpg"), true);
  assertEquals(nomeFinal(d({ destino: "pessoal", os: null, forma: "credito", conta: null })), "2026-10-10 12h57 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - PESSOAL.jpg");
  // ajustes do dono: PESSOAL do bolso continua sem pagamento; o que saiu da empresa leva "PAGAMENTO CONTA"
  assertEquals(nomeFinal(d({ destino: "pessoal", os: null, forma: "credito", conta: null, quem_pagou: "socio" })).endsWith(" - PESSOAL.jpg"), true);
  assertEquals(nomeFinal(d({ destino: "pessoal", os: null, forma: "credito", conta: null, quem_pagou: "empresa" })),
    "2026-10-10 12h57 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - PESSOAL - CREDITO EMPRESA.jpg");
  assertEquals(nomeFinal(d({ destino: "pessoal", os: null, forma: "debito", conta: "C6 PJ" })).endsWith(" - PESSOAL - DEBITO C6 PJ.jpg"), true);
  assertEquals(nomeFinal(d({ forma: "transferencia" })).includes(" - TRANSF EMPRESA."), true);
  assertEquals(nomeFinal(d({ forma: "credito_loja", conta: null })).endsWith(" - CRED-LOJA.jpg"), true);
  assertEquals(nomeFinal(d({ os: { ...d().os!, barco: null } })).includes(" - OS-00112 João - "), true);
});

Deno.test("nomeFinal: fornecedor sem acento e até 40; sem fornecedor; caracteres proibidos; 1.234,56; extensão do mime", () => {
  assertEquals(nomeFinal(d({ fornecedor: "Ferragens São João: Peças/Náuticas \"Ltda\" e Comércio de Coisas" })).includes(" R$ 62,00 Ferragens Sao Joao- Pecas-Nauticas -Ltda - OS-00112 Brisa - "), true);
  assertEquals(nomeFinal(d({ fornecedor: null })), "2026-10-10 12h57 CMP-00124 NFCE R$ 62,00 - OS-00112 Brisa - DEBITO EMPRESA.jpg");
  assertEquals(nomeFinal(d({ valor: "1234.56" })).includes(" R$ 1.234,56 "), true);
  assertEquals(nomeFinal(d({ arquivo_path: null, arquivo_mime: "application/pdf" })).endsWith(".pdf"), true);
  assertEquals(nomeFinal(d({ tipo: "pix" })).includes(" CMP-00124 PIX "), true);
  assertEquals(nomeFinal(d({ os: { ...d().os!, barco: "Brisa/II: *Top*" } })).includes(" - OS-00112 Brisa-II- -Top- - "), true);
});

Deno.test("nomeFinal: até 200 caracteres, cortando o fornecedor primeiro", () => {
  const longo = nomeFinal(d({ os: { ...d().os!, barco: "B".repeat(150) } }));
  assert(longo.length <= 200, String(longo.length));
  assert(longo.endsWith(".jpg"));
  assert(!longo.includes("Auto Posto Exemplo"), "o fornecedor sai antes do destino");
});

Deno.test("nomeCancelado: ' CANCELADO' antes da extensão, uma vez só", () => {
  assertEquals(nomeCancelado("2026-10-10 CMP-00124 A LER.jpg"), "2026-10-10 CMP-00124 A LER CANCELADO.jpg");
  assertEquals(nomeCancelado("x (1).pdf"), "x (1) CANCELADO.pdf");
  assertEquals(nomeCancelado("x CANCELADO.pdf"), "x CANCELADO.pdf");
  assertEquals(nomeCancelado("sem-extensao"), "sem-extensao CANCELADO");
  assertEquals(nomeDoCaminho("/A/B/c d.jpg"), "c d.jpg");
  assertEquals(nomeDoCaminho(null), null);
});

Deno.test("pastaFinal e usaPastaDoBarco: barco, mês, pessoal, cancelado; nunca /HBR-Testes", () => {
  const base = "/MANAGEMENT/FINANCIALS/COMPROVANTES";
  assertEquals(pastaFinal(d(), "/MANAGEMENT/COMMERCIAL/B2C/0021.002.26_Brisa"), "/MANAGEMENT/COMMERCIAL/B2C/0021.002.26_Brisa/1- DOC's/Compras");
  assertEquals(pastaFinal(d(), null), `${base}/2026/2026-10`);
  assertEquals(pastaFinal(d({ destino: "empresa", os: null }), "/x"), `${base}/2026/2026-10`);
  assertEquals(pastaFinal(d({ destino: "pessoal", os: null }), null), `${base}/PESSOAL/2026-10`);
  assertEquals(pastaFinal(d({ cancelado: true }), "/x"), `${base}/_CANCELADOS`);
  assertEquals(pastaFinal(d({ dropbox_pendente: "cancelar" }), null), `${base}/_CANCELADOS`);
  assertEquals(pastaFinal(d({ mes: null, data: "2026-09-30" }), null), `${base}/2026/2026-09`);

  assertEquals(usaPastaDoBarco(d(), false), true);
  assertEquals(usaPastaDoBarco(d({ os: { ...d().os!, pasta_registrada: false } }), false), false, "sem pasta e sem pasta-base");
  assertEquals(usaPastaDoBarco(d({ os: { ...d().os!, pasta_registrada: false } }), true), true, "a pasta-base cria a do barco");
  assertEquals(usaPastaDoBarco(d({ os: { ...d().os!, cliente: "Cliente Final" } }), true), false, "cliente genérico");
  assertEquals(usaPastaDoBarco(d({ os: { ...d().os!, vessel_id: null } }), true), false, "OS sem barco");
  assertEquals(usaPastaDoBarco(d({ destino: "estoque" }), true), false);
});

Deno.test("caminhoDoIndice: dentro do mês, aceita '2026-10' e '2026-10-01'", () => {
  assertEquals(caminhoDoIndice("2026-10"), "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10.csv");
  assertEquals(caminhoDoIndice("2026-10-01"), "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10.csv");
  assertThrows(() => caminhoDoIndice("outubro"));
});

Deno.test("csvDoIndice: BOM, ';', CRLF, vírgula decimal, aspas, por número, sem CPF, colunas na ordem", () => {
  const linhas: LinhaDoIndice[] = [
    {
      codigo: "CMP-00125", numero: 125, data: "2026-10-11", hora: null, tipo: "pix", valor: "1234.5", fornecedor: 'Loja "A"; B', cnpj: "12345678901",
      destino: "pessoal", situacao: "cancelado", pendencias: [], arquivo: "/MANAGEMENT/FINANCIALS/COMPROVANTES/_CANCELADOS/x CANCELADO.jpg",
    },
    {
      codigo: "CMP-00124", numero: 124, data: "2026-10-10", hora: "12:57:56", tipo: "nfce", valor: "62.00", fornecedor: "Auto Posto Exemplo",
      cnpj: "11222333000181", destino: "os", os_numero: "OS-00112", barco: "Brisa", na_os: "despesa",
      quem_pagou: "socio", forma: "dinheiro", situacao: "gravado", pendencias: ["incluir_na_os", "dar_entrada"],
      arquivo: "/B2C/0021_Brisa/1- DOC's/Compras/a.jpg",
    },
  ];
  const csv = csvDoIndice(linhas);
  assertEquals(csv.charCodeAt(0), 0xfeff);
  assert(csv.endsWith("\r\n"));
  const linhasCsv = csv.slice(1).split("\r\n");
  assertEquals(linhasCsv[0], COLUNAS_DO_INDICE.join(";"));
  assertEquals(linhasCsv[0], "Código;Data;Hora;Tipo;Valor;Fornecedor;CNPJ;Destino;OS;Barco;Na OS;Quem pagou;Forma;Situação;Pendências;Arquivo");
  assertEquals(
    linhasCsv[1],
    "CMP-00124;10/10/2026;12:57;cupom NFC-e;62,00;Auto Posto Exemplo;11.222.333/0001-81;OS;OS-00112;Brisa;despesa interna;sócio;dinheiro;gravado;lançar a peça na OS, dar entrada no estoque;/B2C/0021_Brisa/1- DOC's/Compras/a.jpg",
  );
  assertEquals(
    linhasCsv[2],
    'CMP-00125;11/10/2026;;comprovante de Pix;1234,50;"Loja ""A""; B";;Pessoal;;;;;;cancelado;;/MANAGEMENT/FINANCIALS/COMPROVANTES/_CANCELADOS/x CANCELADO.jpg',
  );
  assert(!csv.includes("12345678901"), "CPF nunca");
  assertEquals(linhasCsv.length, 4); // cabeçalho, 2 linhas, e o vazio depois do CRLF final
  assertEquals(csvDoIndice([]), `﻿${COLUNAS_DO_INDICE.join(";")}\r\n`);
});

Deno.test("csvDoIndice: a forma que a N5 devolve (os = número, na_os em texto, sem numero); nada de cobrar do cliente", () => {
  const csv = csvDoIndice([
    { codigo: "CMP-00125", data: "2026-10-11", tipo: "pix", valor: "10.00", destino: "empresa", na_os: null, situacao: "gravado", pendencias: [] },
    { codigo: "CMP-00124", data: "2026-10-10", tipo: "nfce", valor: "62.00", destino: "os", os: "OS-00112", barco: "Brisa", na_os: "ja_lancado", situacao: "gravado", pendencias: [] },
    { codigo: "CMP-00126", data: "2026-10-12", tipo: "nfce", valor: "5.00", destino: "os", os: "OS-00113", na_os: "peca", situacao: "gravado", pendencias: [] },
  ]);
  const linhas = csv.slice(1).split("\r\n");
  assertEquals(linhas[1].split(";").slice(0, 1), ["CMP-00124"], "por número (o código tem os zeros)");
  assertEquals(linhas[1].split(";").slice(8, 11), ["OS-00112", "Brisa", "já lançado na OS (só comprova)"]);
  assertEquals(linhas[3].split(";")[10], "peça (só comprova)");
  assertEquals(linhas[2].split(";")[10], "");
  assertEquals(/cobrar|cobrança/i.test(csv), false);
});

Deno.test("campoCsv: quebra de linha entre aspas e fórmula neutralizada", () => {
  assertEquals(campoCsv("a\nb"), '"a\nb"');
  assertEquals(campoCsv("=HYPERLINK(\"x\")"), "\"'=HYPERLINK(\"\"x\"\")\"");
  assertEquals(campoCsv("+55"), "'+55");
  assertEquals(campoCsv("normal"), "normal");
});

// Revisão de 11/10/2026: a razão social do MEI traz o CPF do titular; nunca vai ao nome do arquivo nem ao CSV.
Deno.test("semCpf: tira o CPF do titular e o CNPJ básico da frente; o resto do nome fica", () => {
  assertEquals(semCpf("FULANO DA SILVA 12345678900"), "FULANO DA SILVA");
  assertEquals(semCpf("FULANO DA SILVA 123.456.789-00"), "FULANO DA SILVA");
  assertEquals(semCpf("12.345.678 FULANO DA SILVA"), "FULANO DA SILVA");
  assertEquals(semCpf("12345678 FULANO DA SILVA"), "FULANO DA SILVA");
  assertEquals(semCpf("Auto Posto Exemplo"), "Auto Posto Exemplo");
  assertEquals(semCpf("Loja 2000"), "Loja 2000", "número curto no nome não é CPF");
  assertEquals(semCpf("12345678900"), null);
  assertEquals(semCpf(null), null);
});

Deno.test("nomeFinal e índice: o CPF do fornecedor MEI não aparece", () => {
  const nome = nomeFinal(d({ fornecedor: "FULANO DA SILVA 12345678900" }));
  assertEquals(nome.includes("12345678900"), false);
  assert(nome.includes("FULANO DA SILVA"));
});

Deno.test("F3: o índice da pasta PESSOAL mora nela, com nome próprio; as situações da conciliação no CSV", () => {
  assertEquals(caminhoDoIndicePessoal("2026-10"), "/MANAGEMENT/FINANCIALS/COMPROVANTES/PESSOAL/2026-10/_INDICE PESSOAL 2026-10.csv");
  assertEquals(caminhoDoIndicePessoal("2026-10-01"), caminhoDoIndicePessoal("2026-10"));
  assertThrows(() => caminhoDoIndicePessoal("outubro"));
  const csv = csvDoIndice([
    { codigo: "CMP-00001", numero: 1, situacao: "aguardando_banco" },
    { codigo: "CMP-00002", numero: 2, situacao: "conciliado" },
    { codigo: "CMP-00003", numero: 3, situacao: "abandonado" },
  ]);
  const situacoes = csv.split("\r\n").slice(1, 4).map((l) => l.split(";")[13]);
  assertEquals(situacoes, ["esperando o banco", "ligado ao extrato", "sem linha no extrato"]);
});
