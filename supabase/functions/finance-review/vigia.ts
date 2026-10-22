// O olhar do vigilante de despesas, sem banco: agrupa as saídas do extrato por quem recebeu e
// devolve os avisos. Quem lê o extrato e grava os avisos é o `vigiar` (index.ts).
import { historicoSemIdentidade, mesmoNomeNoExtrato } from "../_shared/banking/proposals.ts";
import { documentoContradiz, nomeDentroDaDescricao } from "../_shared/banking/contraparte.ts";
import { lerParcela } from "../_shared/banking/installments.ts";

/** Uma saída do extrato como o vigilante a lê. */
export interface LinhaDoVigia {
  id: string;
  transaction_date: string;
  amount: number | string;
  description?: string | null;
  counterparty_name?: string | null;
  counterparty_document?: string | null;
  merchant_name?: string | null;
  merchant_document?: string | null;
  dismissed_kind?: string | null;
  installment_label?: string | null;
  source_type?: string | null;
}

export interface AlertaDoVigia {
  tipo: "valor" | "novo" | "parou" | "duplicidade";
  /** suggested_description da proposta: impede repetir o aviso por 45 dias. */
  chave: string;
  titulo: string;
  motivo: string;
  valor: number;
  data: string;
  txId: string | null;
}

/**
 * Os quatro olhares sobre as saídas dos últimos 12 meses (as linhas chegam em ordem de data):
 *   1. valor fora do padrão — ≥ 2× a mediana de ≥3 pagamentos anteriores (e ≥ R$ 200 acima);
 *   2. quem recebeu pela primeira vez — sem histórico em 12 meses e ≥ R$ 500 nos últimos 30 dias;
 *   3. recorrência que parou — pagamento novo em ≥3 dos 4 meses anteriores e o recebedor sumiu há 35 dias;
 *   4. duplicidade — mesmo valor para o mesmo recebedor em até 3 dias.
 */
export function alertasDoVigia(txs: LinhaDoVigia[], hoje: Date): AlertaDoVigia[] {
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  const d30 = iso(new Date(hoje.getTime() - 30 * 86400000));
  const d35 = iso(new Date(hoje.getTime() - 35 * 86400000));

  type Tx = { id: string; transaction_date: string; amount: number; rotulo: string; chave: string; parcela: Parcela | null };
  const grupos = new Map<string, Tx[]>();
  /** Chave → as parcelas já explicadas (dismissed_kind 'parcela'): o dia e qual parcela. */
  const explicadas = new Map<string, Array<{ data: string; parcela: Parcela | null }>>();
  /**
   * Chave → por total de parcelas, a ÚLTIMA parcela vista no grupo (explicada ou não). Se ela é a n/n, o
   * parcelamento chegou ao fim; se é k/n com k < n, ele parou no meio (estorno, cancelamento) — e isso o
   * "parou" deve contar (segunda revisão de 22/10/2026).
   */
  const ultimaDaSerie = new Map<string, Map<number, { data: string; numero: number }>>();
  const quem = new QuemRecebeu(txs ?? []);
  for (const t of txs ?? []) {
    // Transferência entre contas não é despesa de ninguém.
    if (t.dismissed_kind === "transferencia") continue;
    const q = quem.de(t);
    if (!q) continue;
    const data = String(t.transaction_date).slice(0, 10);
    const parcela = parcelaDaLinha(t);
    if (parcela) {
      const series = ultimaDaSerie.get(q.chave) ?? new Map<number, { data: string; numero: number }>();
      const antes = series.get(parcela.total);
      if (!antes || data > antes.data || (data === antes.data && parcela.numero > antes.numero)) {
        series.set(parcela.total, { data, numero: parcela.numero });
      }
      ultimaDaSerie.set(q.chave, series);
    }
    // Parcela já explicada não é despesa nova (fica fora dos olhares), mas pode ser dinheiro indo para o
    // mesmo recebedor por uma compra que contou: o "parou" decide abaixo.
    if (t.dismissed_kind === "parcela") {
      const lista = explicadas.get(q.chave);
      if (lista) lista.push({ data, parcela }); else explicadas.set(q.chave, [{ data, parcela }]);
      continue;
    }
    const tx: Tx = {
      id: t.id, transaction_date: data, amount: Math.abs(Number(t.amount || 0)), rotulo: q.nome.slice(0, 60) || q.chave,
      chave: q.chave, parcela,
    };
    const lista = grupos.get(q.chave);
    if (lista) lista.push(tx); else grupos.set(q.chave, [tx]);
  }
  /** Todas as saídas que entraram em algum grupo, na ordem do extrato (para a pista do "parou"). */
  const todas = [...grupos.values()].flat().sort((a, b) => a.transaction_date.localeCompare(b.transaction_date));
  const mesmoValor = (a: number, b: number) => Math.abs(a - b) < 0.015; // ±1 centavo

  const alertas: AlertaDoVigia[] = [];
  const fmt = (n: number) => n.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
  const mediana = (v: number[]) => {
    const s = [...v].sort((a, b) => a - b); const m = Math.floor(s.length / 2);
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  };
  const mesDe = (d: string) => d.slice(0, 7);
  const mesesAnteriores = [1, 2, 3, 4].map((n) => {
    const d = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth() - n, 1));
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
  });

  for (const [chave, lista] of grupos) {
    const rotulo = lista[lista.length - 1].rotulo;
    const recentes = lista.filter((t) => t.transaction_date >= d30);
    const historico = lista.filter((t) => t.transaction_date < d30);

    if (historico.length >= 3) {
      const med = mediana(historico.map((t) => t.amount));
      for (const t of recentes) {
        if (med > 0 && t.amount >= 2 * med && t.amount - med >= 200) {
          alertas.push({
            tipo: "valor", chave: `vigia:valor:${t.id}`, txId: t.id, valor: t.amount, data: t.transaction_date,
            titulo: `Valor acima do padrão: ${rotulo} — ${fmt(t.amount)} (costuma ser ~${fmt(med)})`,
            motivo: `${historico.length} pagamentos anteriores a ${rotulo} nos últimos 12 meses, mediana ${fmt(med)}. Este é ${(t.amount / med).toFixed(1)}× o normal. Confira o valor antes de lançar.`,
          });
        }
      }
    }

    if (historico.length === 0 && recentes.length > 0) {
      const maior = recentes.reduce((m, t) => (t.amount > m.amount ? t : m), recentes[0]);
      const soma = recentes.reduce((s, t) => s + t.amount, 0);
      if (maior.amount >= 500) {
        alertas.push({
          tipo: "novo", chave: `vigia:novo:${chave}:${mesDe(maior.transaction_date)}`, txId: maior.id, valor: maior.amount, data: maior.transaction_date,
          titulo: `Primeira vez no extrato: ${rotulo} — ${fmt(maior.amount)}`,
          motivo: `Nenhum pagamento a ${rotulo} nos 12 meses anteriores; ${recentes.length} nos últimos 30 dias, somando ${fmt(soma)}. Vale confirmar que é um recebedor legítimo.`,
        });
      }
    }

    // Recorrência é pagamento NOVO todo mês. A parcela 2/n em diante de um parcelamento que chegou ao fim (a
    // n/n está no extrato) é o resto de uma compra que já aconteceu: o fim dele não é "parou". Parcelamento
    // que parou no meio (a última vista é k/n, k < n) conta como os outros pagamentos.
    const series = ultimaDaSerie.get(chave);
    const restoDeCompraTerminada = (t: Tx) => !!t.parcela && t.parcela.numero >= 2 && series?.get(t.parcela.total)?.numero === t.parcela.total;
    const meses = new Set(lista.filter((t) => !restoDeCompraTerminada(t)).map((t) => mesDe(t.transaction_date)));
    const presentes = mesesAnteriores.filter((m) => meses.has(m));
    const ultimo = lista[lista.length - 1];
    // Quem ainda aparece pela parcela já explicada ("Coremma 2/4" em setembro) não parou de aparecer — mas só
    // quando ela é o resto de uma compra que CONTOU: a 1/n da mesma série está nos meses que contaram. A parcela
    // de outra compra no mesmo recebedor não esconde a mensalidade que parou (segunda revisão de 22/10/2026).
    const comprasQueContaram = lista.filter((t) => t.parcela?.numero === 1 && presentes.includes(mesDe(t.transaction_date)));
    const parcelaExplicada = (explicadas.get(chave) ?? [])
      .filter((e) => !!e.parcela && e.parcela.numero >= 2
        && comprasQueContaram.some((c) => c.parcela!.total === e.parcela!.total && c.transaction_date < e.data))
      .reduce((m, e) => (e.data > m ? e.data : m), "");
    const ultimaAparicao = parcelaExplicada > ultimo.transaction_date ? parcelaExplicada : ultimo.transaction_date;
    if (presentes.length >= 3 && ultimaAparicao < d35) {
      // Cobrança fixa — o valor do último pagamento, COM CENTAVOS, está em TODOS os meses que contaram — que
      // reaparece com o mesmo valor e um nome NOVO (que só surge no extrato depois do último pagamento): nome
      // diferente nunca identifica, então os grupos não se juntam e a chave do aviso não muda — mas o aviso
      // pergunta ("Google One" → "Google G1ai101m", R$ 96,99, 14/10/2026). As três condições vêm do extrato real
      // (01/03 a 22/10/2026): sem elas, o R$ 100 do posto e o R$ 20 do lanche "casavam" com o Pix de um
      // freelancer novo, com outra lanchonete e com pagamento de fatura. Valor redondo é o valor de qualquer um.
      const comCentavos = Math.round(ultimo.amount * 100) % 100 !== 0;
      const fixa = comCentavos
        && presentes.every((m) => lista.some((t) => mesDe(t.transaction_date) === m && mesmoValor(t.amount, ultimo.amount)));
      const nomeNovo = (o: Tx) => (grupos.get(o.chave)?.[0]?.transaction_date ?? "") > ultimo.transaction_date;
      const outroNome = fixa
        ? todas.filter((o) => o.chave !== chave && o.transaction_date > ultimo.transaction_date && mesmoValor(o.amount, ultimo.amount)
          && nomeNovo(o)).pop()
        : undefined;
      const pista = outroNome
        ? ` Parece ser a mesma cobrança com outro nome (${outroNome.rotulo}, ${ddmm(outroNome.transaction_date)}): confira.`
        : "";
      alertas.push({
        tipo: "parou", chave: `vigia:parou:${chave}:${mesDe(iso(hoje))}`, txId: ultimo.id, valor: ultimo.amount, data: ultimo.transaction_date,
        titulo: `${rotulo} aparecia todo mês e parou (último em ${ddmm(ultimo.transaction_date)})`,
        motivo: `Pagamentos em ${presentes.slice().reverse().join(", ")}; nenhum nos últimos 35 dias. Pode ser cancelamento, atraso ou outra forma de pagamento — só vale saber.${pista}`,
      });
    }

    for (let i = 0; i < recentes.length; i++) {
      for (let j = i + 1; j < recentes.length; j++) {
        const a = recentes[i], b = recentes[j];
        const dias = Math.abs(new Date(a.transaction_date).getTime() - new Date(b.transaction_date).getTime()) / 86400000;
        if (a.amount > 0 && Math.abs(a.amount - b.amount) < 0.01 && dias <= 3) {
          alertas.push({
            tipo: "duplicidade", chave: `vigia:dup:${a.id}:${b.id}`, txId: b.id, valor: b.amount, data: b.transaction_date,
            titulo: `Possível duplicidade: ${rotulo} — ${fmt(a.amount)} em ${ddmm(a.transaction_date)} e ${ddmm(b.transaction_date)}`,
            motivo: `Dois débitos iguais para o mesmo recebedor com ${Math.round(dias)} dia(s) de diferença. Se for cobrança em dobro, marque a segunda como duplicata na fila.`,
          });
        }
      }
    }
  }

  // Cinto e suspensório: dois grupos que ainda assim descrevam o mesmo fato não avisam duas vezes.
  const vistos = new Set<string>();
  for (let i = alertas.length - 1; i >= 0; i--) {
    const t = alertas[i].titulo;
    if (vistos.has(t)) alertas.splice(i, 1); else vistos.add(t);
  }
  return alertas;
}

/** Só os dígitos do documento da linha (contraparte; senão, o estabelecimento). */
function documentoDaLinha(t: LinhaDoVigia): string {
  return String(t.counterparty_document ?? t.merchant_document ?? "").replace(/\D/g, "");
}

/** O nome inteiro, sem acento, caixa e pontuação: é com ele que se diz "nome igual". */
function nomeComparavel(nome: string): string {
  return nome.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
}

/**
 * A chave de GRUPO de sempre: o nome comparável até 40 letras ("nome:coremma"). Fica cortada para as chaves
 * dos avisos não mudarem; "nome igual" compara o nome inteiro (nomeComparavel).
 */
function chaveDeNome(nome: string): string {
  return nomeComparavel(nome).slice(0, 40);
}

/**
 * Parcela escrita no fim do nome ("Coremma 2/4"): sai do nome, porque é a mesma loja da "COREMMA". Só quando é
 * parcela de verdade (lerParcela): "LOJA 24/7" é o nome da loja e fica como está.
 */
const PARCELA_NO_FIM = /\s*(\d{1,2}\s*\/\s*\d{1,2})\s*$/;
function semParcelaNoFim(nome: string): string {
  const m = nome.match(PARCELA_NO_FIM);
  return m && m.index !== undefined && lerParcela(m[1]) ? nome.slice(0, m.index).trim() : nome;
}

/** Quem recebeu, como o banco escreveu: o campo próprio, o nome dentro da descrição ou a descrição inteira. */
function nomeDaLinha(t: LinhaDoVigia): string {
  return semParcelaNoFim(String(t.merchant_name || t.counterparty_name || nomeDentroDaDescricao(t.description) || t.description || "").trim());
}

type Parcela = { numero: number; total: number };

/** A parcela da linha (o rótulo; senão, a escrita no fim do nome, "Coremma 2/4") — ou null. */
function parcelaDaLinha(t: LinhaDoVigia): Parcela | null {
  const noNome = String(t.merchant_name || t.counterparty_name || "").match(PARCELA_NO_FIM)?.[1];
  return lerParcela(t.installment_label) ?? lerParcela(noNome);
}

/**
 * De quem é cada saída — a regra da casa (decisão do dono, 26/09/2026): o MESMO documento é o mesmo; sem
 * documento, o nome IGUAL ou o nome CORTADO PELO BANCO (com o corte provado, mesmoNomeNoExtrato) a um nome que
 * anda com um documento é daquele documento. Nome parecido nunca. Nome visto com documentos que não se
 * confirmam (dois CPFs) não escolhe nenhum: fica no grupo do próprio nome.
 *
 * Os nomes que andam com documento são o campo próprio E o nome dentro da descrição: o Nubank manda o CPF do
 * Gustavo com o nome só em "Pix enviado para Gustavo Seberino da Silva" — o mesmo nome do cartão, sem
 * documento, que antes virava outro grupo e acusava "parou" com Pix para ele toda semana (aviso de 01/10/2026).
 */
class QuemRecebeu {
  /** nome comparável INTEIRO → documentos vistos com ele, na ordem do extrato (o primeiro é o do grupo). */
  private docsDoNome = new Map<string, string[]>();
  /** Nomes que andam com documento, pela primeira palavra: a prova do corte só compara quem começa igual. */
  private nomesComDoc = new Map<string, Array<{ nome: string; doc: string }>>();
  private memo = new Map<string, string | null>();

  constructor(txs: LinhaDoVigia[]) {
    for (const t of txs) {
      const doc = documentoDaLinha(t);
      if (doc.length < 11) continue;
      const nomes = new Set([t.merchant_name, t.counterparty_name, nomeDentroDaDescricao(t.description)]
        .map((n) => semParcelaNoFim(String(n ?? "").trim())).filter(Boolean));
      for (const nome of nomes) {
        // O nome inteiro, não a chave de 40 letras: "…DA SILVA NETO" não é "…DA SILVA FILHO" (segunda revisão
        // de 22/10/2026). O nome cortado pelo banco segue pela prova do corte (documentoPeloNome).
        const k = nomeComparavel(nome);
        if (!k) continue;
        const docs = this.docsDoNome.get(k) ?? [];
        if (docs.includes(doc)) continue;
        docs.push(doc);
        this.docsDoNome.set(k, docs);
        const primeira = k.split(" ")[0];
        const lista = this.nomesComDoc.get(primeira) ?? [];
        lista.push({ nome, doc });
        this.nomesComDoc.set(primeira, lista);
      }
    }
  }

  /** Um documento só quando todos os vistos são da mesma pessoa ou empresa (CNPJ: a mesma raiz). */
  private umDocumento(docs: string[]): string | null {
    return docs.length > 0 && docs.every((d) => !documentoContradiz(d, docs[0])) ? docs[0] : null;
  }

  /** O documento de uma saída sem documento, pelo nome igual ou cortado pelo banco — ou null. */
  private documentoPeloNome(t: LinhaDoVigia, nome: string): string | null {
    const k = nomeComparavel(nome);
    const exato = this.docsDoNome.get(k);
    if (exato) return this.umDocumento(exato);
    const chaveDoMemo = `${nome}|${t.source_type ?? ""}|${String(t.description ?? "").trim()}`;
    if (this.memo.has(chaveDoMemo)) return this.memo.get(chaveDoMemo) ?? null;
    const linha = { counterparty_name: nome, description: String(t.description ?? ""), source_type: t.source_type ?? null };
    const docs: string[] = [];
    for (const c of this.nomesComDoc.get(k.split(" ")[0]) ?? []) {
      if (mesmoNomeNoExtrato(c.nome, linha) && !docs.includes(c.doc)) docs.push(c.doc);
    }
    const doc = this.umDocumento(docs);
    this.memo.set(chaveDoMemo, doc);
    return doc;
  }

  /** A chave do grupo ("doc:…" ou "nome:…") e o nome para o texto do aviso — ou null, se a linha não diz para quem foi. */
  de(t: LinhaDoVigia): { chave: string; nome: string } | null {
    const doc = documentoDaLinha(t);
    const nome = nomeDaLinha(t);
    if (doc.length >= 11) return { chave: `doc:${doc}`, nome };
    const k = chaveDeNome(nome);
    if (!k) return null;
    // Sem favorecido e com descrição genérica ("TRANSF ENVIADA PIX", "DEBITO DE CARTAO") o grupo mistura
    // dezenas de destinos: mediana, "novo" e "parou" não dizem nada. A lista é a da memória do motor.
    if (historicoSemIdentidade(nome)) return null;
    const docDoNome = this.documentoPeloNome(t, nome);
    return { chave: docDoNome ? `doc:${docDoNome}` : `nome:${k}`, nome };
  }
}
