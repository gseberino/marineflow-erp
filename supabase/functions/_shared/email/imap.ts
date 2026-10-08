// Cliente IMAP mínimo e SÓ DE LEITURA (08/10/2026) — o adaptador IMAP do contrato InboundEmail.
//
// Por que não uma biblioteca: a mais madura (npm:imapflow) trava no Supabase Edge Runtime ao
// baixar mensagem de ~1 MB (postalsys/imapflow#401, set/2026), e o mesmo relato mostra que uma
// sessão feita à mão sobre Deno.connectTls funciona (1 MB em 379 ms). O que precisamos é pouco:
// LOGIN → EXAMINE (abre a caixa em modo leitura) → UID SEARCH → UID FETCH BODY.PEEK[] → LOGOUT.
//
// Garantias de "não mexer na caixa do dono": EXAMINE em vez de SELECT (a caixa abre somente
// leitura) e BODY.PEEK (não marca como lido). Nenhum comando de escrita existe neste arquivo.

export interface RespostaImap {
  /** Texto da resposta não-tag (sem os literais). */
  texto: string;
  /** Literais {N} que vieram nela, na ordem. */
  literais: Uint8Array[];
}

export interface ResultadoDoComando {
  status: "OK" | "NO" | "BAD";
  linhaFinal: string;
  respostas: RespostaImap[];
}

/** Fonte de bytes: a conexão TLS de verdade ou um dublê no teste. */
export interface Fluxo {
  read(p: Uint8Array): Promise<number | null>;
  write(p: Uint8Array): Promise<number>;
  close(): void;
}

const enc = new TextEncoder();
const dec = new TextDecoder("latin1");

/** String IMAP entre aspas: escapa \ e ". CR/LF não são aceitos (senha com quebra de linha não existe). */
export function aspas(s: string): string {
  if (/[\r\n]/.test(s)) throw new Error("valor IMAP com quebra de linha");
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

/** Data no formato do SEARCH SINCE: 7-Jul-2026. */
export function dataImap(d: Date): string {
  const meses = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${d.getUTCDate()}-${meses[d.getUTCMonth()]}-${d.getUTCFullYear()}`;
}

export class ClienteImap {
  private buf = new Uint8Array(0);
  private seq = 0;
  constructor(private fluxo: Fluxo, private limiteMs = 60_000) {}

  static async conectar(host: string, porta = 993): Promise<ClienteImap> {
    const conn = await Deno.connectTls({ hostname: host, port: porta });
    const c = new ClienteImap(conn as unknown as Fluxo);
    const saudacao = await c.lerLinha();
    if (!/^\* (OK|PREAUTH)/i.test(saudacao)) {
      c.fechar();
      throw new Error(`servidor IMAP não saudou: ${saudacao.slice(0, 120)}`);
    }
    return c;
  }

  fechar() {
    try { this.fluxo.close(); } catch { /* já fechada */ }
  }

  private async encher(): Promise<boolean> {
    const pedaco = new Uint8Array(64 * 1024);
    const n = await Promise.race([
      this.fluxo.read(pedaco),
      new Promise<never>((_, rej) => setTimeout(() => rej(new Error("IMAP: servidor não respondeu a tempo")), this.limiteMs)),
    ]);
    if (n === null || n === 0) return false;
    const novo = new Uint8Array(this.buf.length + n);
    novo.set(this.buf);
    novo.set(pedaco.subarray(0, n), this.buf.length);
    this.buf = novo;
    return true;
  }

  /** Uma linha até CRLF (sem o CRLF). */
  async lerLinha(): Promise<string> {
    for (;;) {
      for (let i = 0; i + 1 < this.buf.length; i++) {
        if (this.buf[i] === 13 && this.buf[i + 1] === 10) {
          const linha = dec.decode(this.buf.subarray(0, i));
          this.buf = this.buf.slice(i + 2);
          return linha;
        }
      }
      if (!(await this.encher())) throw new Error("IMAP: conexão encerrada pelo servidor");
    }
  }

  private async lerBytes(n: number): Promise<Uint8Array> {
    while (this.buf.length < n) {
      if (!(await this.encher())) throw new Error("IMAP: conexão encerrada no meio de um literal");
    }
    const out = this.buf.slice(0, n);
    this.buf = this.buf.slice(n);
    return out;
  }

  /** Lê uma resposta completa: a linha e, se ela terminar em {N}, o literal e o resto. */
  private async lerResposta(): Promise<RespostaImap> {
    let texto = "";
    const literais: Uint8Array[] = [];
    for (;;) {
      const linha = await this.lerLinha();
      const m = linha.match(/\{(\d+)\}$/);
      if (!m) {
        texto += linha;
        return { texto, literais };
      }
      texto += linha.slice(0, linha.length - m[0].length) + `{#${literais.length}}`;
      literais.push(await this.lerBytes(Number(m[1])));
    }
  }

  /** Manda um comando e junta as respostas até a linha com a tag. */
  async comando(cmd: string): Promise<ResultadoDoComando> {
    const tag = `A${++this.seq}`;
    await this.fluxo.write(enc.encode(`${tag} ${cmd}\r\n`));
    const respostas: RespostaImap[] = [];
    for (;;) {
      const r = await this.lerResposta();
      if (r.texto.startsWith(`${tag} `)) {
        const status = r.texto.slice(tag.length + 1, tag.length + 4).toUpperCase().trim();
        return { status: (status === "OK" || status === "NO" ? status : "BAD") as ResultadoDoComando["status"], linhaFinal: r.texto, respostas };
      }
      respostas.push(r);
    }
  }

  private async exigirOk(cmd: string, oQue: string): Promise<ResultadoDoComando> {
    const r = await this.comando(cmd);
    if (r.status !== "OK") throw new Error(`IMAP ${oQue} recusado: ${r.linhaFinal.replace(/^A\d+ /, "").slice(0, 160)}`);
    return r;
  }

  async login(usuario: string, senha: string): Promise<void> {
    const r = await this.comando(`LOGIN ${aspas(usuario)} ${aspas(senha)}`);
    // A mensagem do servidor pode ecoar o usuário, nunca a senha; ainda assim não a repetimos.
    if (r.status !== "OK") throw new Error("IMAP: usuário ou senha recusados pelo servidor");
  }

  /** Abre a caixa em modo LEITURA. Devolve UIDVALIDITY e quantas mensagens há. */
  async examinar(caixa = "INBOX"): Promise<{ uidValidity: number | null; existem: number }> {
    const r = await this.exigirOk(`EXAMINE ${aspas(caixa)}`, "EXAMINE");
    let uidValidity: number | null = null;
    let existem = 0;
    for (const x of r.respostas) {
      const v = x.texto.match(/\[UIDVALIDITY (\d+)\]/i);
      if (v) uidValidity = Number(v[1]);
      const e = x.texto.match(/^\* (\d+) EXISTS/i);
      if (e) existem = Number(e[1]);
    }
    return { uidValidity, existem };
  }

  /** UIDs que casam com o critério (ex.: "UID 120:*" ou "SINCE 9-Jul-2026"). */
  async buscarUids(criterio: string): Promise<number[]> {
    const r = await this.exigirOk(`UID SEARCH ${criterio}`, "SEARCH");
    const uids: number[] = [];
    for (const x of r.respostas) {
      const m = x.texto.match(/^\* SEARCH ?(.*)$/i);
      if (m) for (const n of m[1].trim().split(/\s+/)) if (/^\d+$/.test(n)) uids.push(Number(n));
    }
    return uids.sort((a, b) => a - b);
  }

  /** Tamanho e data de chegada de uma mensagem, sem baixá-la. */
  async tamanho(uid: number): Promise<{ tamanho: number | null; internalDate: string | null }> {
    const r = await this.exigirOk(`UID FETCH ${uid} (RFC822.SIZE INTERNALDATE)`, "FETCH");
    const t = r.respostas.map((x) => x.texto).join(" ");
    const s = t.match(/RFC822\.SIZE (\d+)/i);
    const d = t.match(/INTERNALDATE "([^"]+)"/i);
    return { tamanho: s ? Number(s[1]) : null, internalDate: d ? d[1] : null };
  }

  /**
   * A mensagem inteira (fonte RFC 822), sem marcar como lida. `soCabecalho` baixa só o
   * cabeçalho — para mensagem grande demais para o limite de memória da função.
   */
  async baixar(uid: number, soCabecalho = false): Promise<Uint8Array | null> {
    const parte = soCabecalho ? "BODY.PEEK[HEADER]" : "BODY.PEEK[]";
    const r = await this.exigirOk(`UID FETCH ${uid} (${parte})`, "FETCH");
    for (const x of r.respostas) {
      if (/FETCH \(/i.test(x.texto) && x.literais.length) return x.literais[0];
    }
    return null;
  }

  async sair(): Promise<void> {
    try { await this.comando("LOGOUT"); } catch { /* indo embora de qualquer jeito */ }
    this.fechar();
  }
}

/** "07-Oct-2026 14:30:00 -0300" → ISO. */
export function internalDateParaIso(s: string | null): string | null {
  if (!s) return null;
  const m = s.match(/^\s*(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})$/);
  if (!m) return null;
  const meses: Record<string, number> = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
  const mes = meses[m[2].toLowerCase()];
  if (mes === undefined) return null;
  const utc = Date.UTC(Number(m[3]), mes, Number(m[1]), Number(m[4]), Number(m[5]), Number(m[6]));
  const off = (Number(m[8]) * 60 + Number(m[9])) * (m[7] === "+" ? 1 : -1);
  return new Date(utc - off * 60_000).toISOString();
}
