// A data que o cliente responde ao lembrete de revisão (07/10/2026): "dia 15", "15/10",
// "15/10/2026", "semana que vem", "mês que vem". Função pura, com teste; o whatsapp-webhook lê a
// data aqui e passa pronta para registrar_resposta_da_revisao (p_data), que adia o plano até ela.
//
// Por que em TypeScript e não em SQL: aqui dá para testar sem banco (não há banco de teste) e o
// webhook já tem o texto na mão. A RPC só confia na data se ela for futura e em até ~1 ano.
//
// Só mensagem curta (até 80 caracteres): numa conversa longa, "dia 15" pode ser qualquer coisa.

const BRASILIA_MS = 3 * 60 * 60 * 1000;
const DIA_MS = 86_400_000;

const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
const iso = (a: number, m: number, d: number) => `${a}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

function valida(a: number, m: number, d: number): string | null {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  const dt = new Date(Date.UTC(a, m - 1, d));
  return dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d ? iso(a, m, d) : null;
}

/** AAAA-MM-DD da data dita, sempre no futuro (depois de hoje em Brasília); null = não é uma data. */
export function lerDataDaResposta(texto: string | null | undefined, agora: Date = new Date()): string | null {
  const t = norm(String(texto ?? ""));
  if (!t || t.length > 80) return null;
  const hoje = new Date(agora.getTime() - BRASILIA_MS);
  const ah = hoje.getUTCFullYear();
  const mh = hoje.getUTCMonth() + 1;
  const dh = hoje.getUTCDate();
  const hojeIso = iso(ah, mh, dh);
  const futura = (x: string | null) => (x && x > hojeIso ? x : null);

  // 15/10 · 15/10/26 · 15/10/2026 · 15-10
  const barra = t.match(/\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2}|\d{4}))?\b/);
  if (barra) {
    const d = Number(barra[1]);
    const m = Number(barra[2]);
    if (barra[3]) {
      const a = barra[3].length === 2 ? 2000 + Number(barra[3]) : Number(barra[3]);
      return futura(valida(a, m, d));
    }
    const esteAno = valida(ah, m, d);
    if (esteAno && esteAno > hojeIso) return esteAno;
    return futura(valida(ah + 1, m, d));
  }

  // "semana que vem" / "próxima semana" → a segunda-feira seguinte
  if (/\b(semana que vem|proxima semana|semana seguinte)\b/.test(t)) {
    const dow = hoje.getUTCDay();
    const ate = ((8 - dow) % 7) || 7;
    return new Date(hoje.getTime() + ate * DIA_MS).toISOString().slice(0, 10);
  }

  // "mês que vem" / "próximo mês" → dia 1º do mês seguinte
  if (/\b(mes que vem|proximo mes|mes seguinte)\b/.test(t)) {
    return mh === 12 ? iso(ah + 1, 1, 1) : iso(ah, mh + 1, 1);
  }

  // "daqui a 2 semanas" / "daqui 10 dias"
  const daqui = t.match(/\bdaqui (?:a )?(\d{1,2}) (dias?|semanas?)\b/);
  if (daqui) {
    const n = Number(daqui[1]) * (daqui[2].startsWith("semana") ? 7 : 1);
    return n > 0 ? new Date(hoje.getTime() + n * DIA_MS).toISOString().slice(0, 10) : null;
  }

  // "dia 15" (ou só "15"): neste mês se ainda não passou, senão no próximo
  const dia = t.match(/\bdia (\d{1,2})\b/) ?? t.match(/^(\d{1,2})$/);
  if (dia) {
    const d = Number(dia[1]);
    if (d > dh) {
      const x = valida(ah, mh, d);
      if (x) return x;
    }
    return mh === 12 ? valida(ah + 1, 1, d) : valida(ah, mh + 1, d);
  }
  return null;
}
