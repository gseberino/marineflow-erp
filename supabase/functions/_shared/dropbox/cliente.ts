// Cliente da API do Dropbox (Fase 2, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
//
// Segredos (Supabase secrets, nunca no código nem no log):
//   DROPBOX_APP_KEY, DROPBOX_APP_SECRET — do app "HBR MarineFlow" (Scoped, Full Dropbox);
//   DROPBOX_TOKEN_KEY — 32 bytes em base64 que cifram o refresh token guardado no banco.
// O refresh token fica em integracao_dropbox (só service_role), cifrado. A edge não consegue
// escrever secrets, por isso o banco; cifrado, quem lê a tabela sem a chave não tem nada.
// O access token dura ~4 h: renovamos a cada execução e guardamos só na memória.
import { argParaCabecalho, cifrar, decidirErro, decifrar } from "./nucleo.ts";

const API = "https://api.dropboxapi.com";
const CONTEUDO = "https://content.dropboxapi.com";

export class ErroDropbox extends Error {
  constructor(
    mensagem: string,
    readonly status: number,
    readonly resumo: string,
    /** Vale tentar de novo mais tarde (429 longo, 5xx, rede). */
    readonly repetivel: boolean,
  ) {
    super(mensagem);
  }
}

export type Credenciais = { appKey: string; appSecret: string; chaveDoToken: string };

/** As três chaves do app. Faltou alguma: o app não foi configurado (erro claro, sem valor nenhum). */
export function credenciaisDoApp(): Credenciais | null {
  const appKey = Deno.env.get("DROPBOX_APP_KEY") ?? "";
  const appSecret = Deno.env.get("DROPBOX_APP_SECRET") ?? "";
  const chaveDoToken = Deno.env.get("DROPBOX_TOKEN_KEY") ?? "";
  if (!appKey || !appSecret || !chaveDoToken) return null;
  return { appKey, appSecret, chaveDoToken };
}

async function postarFormulario(campos: Record<string, string>): Promise<Record<string, unknown>> {
  const r = await fetch(`${API}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(campos).toString(),
  });
  const corpo = await r.json().catch(() => ({})) as Record<string, unknown>;
  if (!r.ok) {
    // Nunca devolver o corpo inteiro: pode ecoar o código. Só o tipo do erro.
    const tipo = String(corpo.error ?? r.status);
    throw new ErroDropbox(`O Dropbox recusou o token (${tipo}).`, r.status, tipo, r.status >= 500);
  }
  return corpo;
}

/** Troca o código da autorização pelo refresh token (que não expira). */
export async function trocarCodigo(codigo: string, redirectUri: string, c: Credenciais) {
  const r = await postarFormulario({
    code: codigo,
    grant_type: "authorization_code",
    redirect_uri: redirectUri,
    client_id: c.appKey,
    client_secret: c.appSecret,
  });
  const refresh = String(r.refresh_token ?? "");
  const acesso = String(r.access_token ?? "");
  if (!refresh || !acesso) throw new ErroDropbox("O Dropbox não devolveu o refresh token.", 502, "sem_refresh_token", false);
  return { refresh, acesso, contaId: String(r.account_id ?? "") };
}

async function renovarAcesso(refresh: string, c: Credenciais): Promise<string> {
  const r = await postarFormulario({
    grant_type: "refresh_token",
    refresh_token: refresh,
    client_id: c.appKey,
    client_secret: c.appSecret,
  });
  const acesso = String(r.access_token ?? "");
  if (!acesso) throw new ErroDropbox("O Dropbox não devolveu o token de acesso.", 502, "sem_access_token", true);
  return acesso;
}

const dormir = (s: number) => new Promise((ok) => setTimeout(ok, s * 1000));

export class Dropbox {
  private acesso: string | null;

  constructor(private readonly refresh: string, private readonly c: Credenciais, acessoInicial?: string) {
    this.acesso = acessoInicial ?? null;
  }

  private async token(forcar = false): Promise<string> {
    if (!this.acesso || forcar) this.acesso = await renovarAcesso(this.refresh, this.c);
    return this.acesso;
  }

  /** Uma chamada com as regras de erro: 401 renova uma vez; 429 curto espera; o resto lança. */
  private async chamar(montar: (token: string) => Request): Promise<Response> {
    let renovou = false;
    for (let tentativa = 0; tentativa < 4; tentativa++) {
      let r: Response;
      try {
        r = await fetch(montar(await this.token()));
      } catch (e) {
        throw new ErroDropbox(`Sem resposta do Dropbox: ${(e as Error).message}`, 0, "rede", true);
      }
      if (r.ok) return r;
      const decisao = decidirErro(r.status, r.headers.get("Retry-After"));
      if (decisao.tipo === "renovar_token" && !renovou) {
        await r.body?.cancel();
        renovou = true;
        await this.token(true);
        continue;
      }
      if (decisao.tipo === "esperar" && decisao.segundos <= 10 && tentativa < 3) {
        await r.body?.cancel();
        await dormir(decisao.segundos);
        continue;
      }
      const texto = await r.text();
      let resumo = String(r.status);
      try {
        resumo = String((JSON.parse(texto) as { error_summary?: string }).error_summary ?? resumo);
      } catch { /* corpo não-JSON */ }
      const repetivel = decisao.tipo === "esperar" || decisao.tipo === "repetir_depois";
      throw new ErroDropbox(`Dropbox respondeu ${r.status}: ${resumo}`, r.status, resumo, repetivel);
    }
    throw new ErroDropbox("Dropbox ocupado demais; tento de novo mais tarde.", 429, "too_many_requests", true);
  }

  /** Endpoint RPC (JSON no corpo). `corpo` null = sem corpo (ex.: get_current_account). */
  async rpc<T>(rota: string, corpo: unknown | null): Promise<T> {
    const r = await this.chamar((token) =>
      new Request(`${API}/2/${rota}`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          ...(corpo === null ? {} : { "Content-Type": "application/json" }),
        },
        body: corpo === null ? undefined : JSON.stringify(corpo),
      })
    );
    return await r.json() as T;
  }

  /**
   * Sobe um arquivo (até 150 MB). Modo "add" nunca sobrescreve; com autorename, um nome repetido
   * vira "arquivo (1).pdf". As pastas que faltarem no caminho o Dropbox cria sozinho.
   */
  async enviar(caminho: string, bytes: Uint8Array<ArrayBuffer>, autorename = true): Promise<MetadadosArquivo> {
    const arg = argParaCabecalho({ path: caminho.normalize("NFC"), mode: "add", autorename, mute: false });
    const r = await this.chamar((token) =>
      new Request(`${CONTEUDO}/2/files/upload`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/octet-stream",
          "Dropbox-API-Arg": arg,
        },
        body: bytes,
      })
    );
    return await r.json() as MetadadosArquivo;
  }

  /** Revoga o token de acesso atual (desconectar). */
  async revogar(): Promise<void> {
    await this.chamar((token) =>
      new Request(`${API}/2/auth/token/revoke`, { method: "POST", headers: { Authorization: `Bearer ${token}` } })
    );
  }
}

export type MetadadosArquivo = {
  id: string;
  name: string;
  path_display: string;
  rev: string;
  size: number;
  content_hash?: string;
};

export type ContaAtual = {
  account_id: string;
  email: string;
  name: { display_name: string };
  root_info: { ".tag": string };
};

// ---------------------------------------------------------------------------------------------
// A conexão guardada (tabela integracao_dropbox, linha única id = 1)
// ---------------------------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
type Admin = any;

export async function guardarConexao(admin: Admin, p: {
  refresh: string;
  c: Credenciais;
  conta: ContaAtual;
  conectadoPor: string | null;
}): Promise<void> {
  const { error } = await admin.from("integracao_dropbox").upsert({
    id: 1,
    conta_id: p.conta.account_id,
    email: p.conta.email,
    nome: p.conta.name?.display_name ?? null,
    refresh_token_cifrado: await cifrar(p.refresh, p.c.chaveDoToken),
    conectado_em: new Date().toISOString(),
    conectado_por: p.conectadoPor,
    ultimo_erro: null,
    ultimo_erro_em: null,
  });
  if (error) throw new Error(`não consegui guardar a conexão (${error.message})`);
}

/** Abre o cliente com a conexão guardada. null = não conectado (ou o app não foi configurado). */
export async function abrirDropbox(admin: Admin): Promise<Dropbox | null> {
  const c = credenciaisDoApp();
  if (!c) return null;
  const { data, error } = await admin.from("integracao_dropbox").select("refresh_token_cifrado").eq("id", 1).maybeSingle();
  if (error) throw new Error(`não consegui ler a conexão do Dropbox (${error.message})`);
  if (!data?.refresh_token_cifrado) return null;
  const refresh = await decifrar(data.refresh_token_cifrado, c.chaveDoToken);
  return new Dropbox(refresh, c);
}

/** Anota o resultado do uso (para a tela mostrar "último uso" e o último erro). */
export async function anotarUso(admin: Admin, erro?: string): Promise<void> {
  const agora = new Date().toISOString();
  await admin.from("integracao_dropbox").update(
    erro ? { ultimo_erro: erro.slice(0, 500), ultimo_erro_em: agora } : { ultimo_uso_em: agora, ultimo_erro: null },
  ).eq("id", 1);
}
