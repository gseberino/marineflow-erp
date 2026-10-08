// Feed do Instagram para o site público (hbrmarine.com.br), 08/10/2026.
//
// Regras puras (sem I/O), testadas em feed_test.ts. A função instagram-feed usa estas peças.
//
// Instagram API com login do Instagram (a Basic Display foi desligada em 04/12/2024):
// o token de longa duração vale 60 dias e é renovado por GET /refresh_access_token, que só
// aceita token com pelo menos 24 h de vida e ainda válido. Token vencido exige novo login do dono.

export const GRAPH = "https://graph.instagram.com";
export const CAMPOS_DA_MIDIA = "id,caption,media_type,media_url,thumbnail_url,permalink,timestamp";
export const POSTS_GUARDADOS = 12;

const DIA = 24 * 60 * 60 * 1000;

/**
 * Renova quando falta pouco para vencer (15 dias) ou quando a última renovação tem uma semana.
 * Sem data de renovação (token recém-colado), tenta já: se o token tiver menos de 24 h,
 * a API recusa e a próxima rodada tenta de novo, sem estrago.
 */
export function precisaRenovar(expiraEm: Date | null, renovadoEm: Date | null, agora: Date): boolean {
  if (!renovadoEm) return true;
  if (expiraEm && expiraEm.getTime() - agora.getTime() < 15 * DIA) return true;
  return agora.getTime() - renovadoEm.getTime() >= 7 * DIA;
}

export interface PostDaApi {
  id: string;
  caption?: string;
  media_type?: string;
  media_url?: string;
  thumbnail_url?: string;
  permalink?: string;
  timestamp?: string;
}

export interface PostGuardado {
  id: string;
  tipo: string;
  imagem: string;
  permalink: string;
  legenda: string | null;
  publicado_em: string | null;
}

/** Converte o post da API no formato guardado. Vídeo usa a capa; post sem imagem é descartado. */
export function paraGuardar(p: PostDaApi): PostGuardado | null {
  const tipo = (p.media_type ?? "IMAGE").toUpperCase();
  const imagem = tipo === "VIDEO" ? p.thumbnail_url : p.media_url;
  if (!p.id || !imagem || !p.permalink) return null;
  const legenda = (p.caption ?? "").trim();
  return {
    id: p.id,
    tipo,
    imagem,
    permalink: p.permalink,
    legenda: legenda ? legenda.slice(0, 500) : null,
    publicado_em: p.timestamp ? new Date(p.timestamp).toISOString() : null,
  };
}

/** Quantos posts o site pode pedir: padrão 9, entre 1 e 12. */
export function limiteDoPedido(valor: string | null): number {
  const n = Number(valor);
  if (!Number.isFinite(n) || n < 1) return 9;
  return Math.min(Math.floor(n), POSTS_GUARDADOS);
}
