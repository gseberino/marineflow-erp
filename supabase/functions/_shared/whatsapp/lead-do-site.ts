// Contato que chega pelo formulário do site (hbrmarine.com.br/orcamento), 08/10/2026.
//
// O formulário não grava nada: ele monta a mensagem e abre o WhatsApp do cliente, que envia.
// A mensagem tem formato fixo (src/pages/orcamento.astro no repositório hbr-site):
//
//   Olá, sou <nome> e vim pelo site da HBR Systems.
//   Tipo: Embarcação | Motorhome / trailer | Estaleiro / fábrica
//   Modelo: ...        (opcional)
//   Local: ...         (opcional)
//   Serviço: ... | quero orientação
//   Detalhes: ...      (opcional)
//
// Aqui só se LÊ a mensagem: nada é respondido ao cliente (regra da casa: nada sai para o
// contato sem o "sim" do dono). O webhook usa o resultado para marcar a origem do lead e
// avisar o dono com o que já veio e o que falta pedir.

export interface DadosDoSite {
  nome: string | null;
  tipo: string | null;
  modelo: string | null;
  local: string | null;
  servico: string | null;
  detalhes: string | null;
}

const MARCA = /vim pelo site da hbr systems/i;

const CAMPOS: Record<string, keyof Omit<DadosDoSite, "nome">> = {
  tipo: "tipo",
  modelo: "modelo",
  local: "local",
  "serviço": "servico",
  servico: "servico",
  detalhes: "detalhes",
};

function limpar(v: string | undefined | null, max = 300): string | null {
  const t = (v ?? "").replace(/\s+/g, " ").trim();
  return t ? t.slice(0, max) : null;
}

/** Devolve os campos da mensagem do site, ou null se a mensagem não veio do formulário. */
export function lerMensagemDoSite(body: string | null | undefined): DadosDoSite | null {
  if (!body || !MARCA.test(body)) return null;
  const dados: DadosDoSite = { nome: null, tipo: null, modelo: null, local: null, servico: null, detalhes: null };

  const nome = body.match(/sou\s+(.+?)\s+e\s+vim pelo site/i);
  dados.nome = limpar(nome?.[1], 80);

  for (const linha of body.split(/\r?\n/)) {
    const m = linha.match(/^\s*([A-Za-zÀ-ÿ]+)\s*:\s*(.*)$/);
    if (!m) continue;
    const chave = CAMPOS[m[1].toLowerCase()];
    if (chave) dados[chave] = limpar(m[2], chave === "detalhes" ? 600 : 160);
  }
  if (dados.servico && /^quero orienta/i.test(dados.servico)) dados.servico = null;
  return dados;
}

/** O que ainda falta pedir ao cliente para orçar. Fotos sempre ajudam e o formulário não as leva. */
export function faltaPedir(d: DadosDoSite): string[] {
  const falta: string[] = [];
  if (!d.modelo) falta.push(d.tipo?.startsWith("Estaleiro") ? "modelo e volume de produção" : "modelo e ano");
  if (!d.local) falta.push("cidade ou marina");
  if (!d.servico) falta.push("o que precisa resolver");
  falta.push("fotos do painel, das baterias e do porão ou bagageiro");
  return falta;
}

/** Texto do aviso ao dono (WhatsApp interno). */
export function avisoDoLeadDoSite(d: DadosDoSite, telefone: string, jaCadastrado: boolean): string {
  const quem = d.nome ? `${d.nome} (+${telefone})` : `+${telefone}`;
  const linhas = [
    `🌐 *Contato novo pelo site*${jaCadastrado ? " (já é cliente cadastrado)" : ""}`,
    "",
    quem,
    d.tipo && `Tipo: ${d.tipo}`,
    d.modelo && `Modelo: ${d.modelo}`,
    d.local && `Local: ${d.local}`,
    `Serviço: ${d.servico ?? "quer orientação"}`,
    d.detalhes && `Detalhes: ${d.detalhes}`,
    "",
    `Falta pedir: ${faltaPedir(d).join("; ")}.`,
    "A conversa está no painel do MarineFlow.",
  ].filter((l): l is string => typeof l === "string");
  return linhas.join("\n");
}
