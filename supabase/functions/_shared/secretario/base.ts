// Peças comuns do "secretário" (Passo 2 do resumo da manhã, 15/10/2026) — lógica pura, sem banco.
// Usadas pela montagem (ai-daily-briefing) e pelos comandos do dono (ai-agent, whatsapp-webhook).
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md

// ─── Letras do dia ──────────────────────────────────────────────────────────────────────────────
//
// Os itens têm LETRA, não número: "1" e "2" já são sim e não da confirmação (whatsapp-channel.ts,
// APPROVE_WORDS/REJECT_WORDS) e qualquer mensagem que começa com "2" recusa o cartão aberto. Fora do
// alfabeto ficam: N e S (o "n" e o "s" sozinhos também são não e sim), E (o "É" sozinho — "é isso" —
// vira "e" sem acento), I e O (parecem 1 e 0). Sobram 21. Mesma lista do CHECK resumo_itens_letra_chk.

export const LETRAS: readonly string[] = "ABCDFGHJKLMPQRTUVWXYZ".split("");

/** A letra da posição `i` (0 = A); null quando passou das 21. */
export function letraDoIndice(i: number): string | null {
  return Number.isInteger(i) && i >= 0 && i < LETRAS.length ? LETRAS[i] : null;
}

/** "a", "A" → "A"; letra fora do alfabeto (N, S, E, I, O, duas letras) → null. */
export function letraValida(s: string | null | undefined): string | null {
  const l = String(s ?? "").trim().toUpperCase();
  return l.length === 1 && LETRAS.includes(l) ? l : null;
}

// ─── Texto ──────────────────────────────────────────────────────────────────────────────────────

/** Sem acento, minúsculo, só letras/números/espaço (o nome_busca do banco e o "volta Flávio"). */
export function paraBusca(s: string | null | undefined): string {
  return String(s ?? "")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9 ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 120);
}

/** Uma linha só: espaços e quebras viram um espaço; corta em `max` com "…" (o nome da Climatec partia a lista). */
export function umaLinha(s: string | null | undefined, max = 40): string {
  const limpo = String(s ?? "").replace(/\s+/g, " ").trim();
  if (limpo.length <= max) return limpo;
  return `${limpo.slice(0, max - 1).trimEnd()}…`;
}

const FMT_BRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

/** "R$ 16.890,00" com espaço comum (o Intl põe um espaço inquebrável). */
export function brl(v: number | string | null | undefined): string {
  return FMT_BRL.format(Math.round(Number(v ?? 0) * 100) / 100).replace(/\u00a0/g, " ");
}

/** Para a linha curta: "R$ 211 mil" a partir de R$ 10 mil (arredondado); abaixo disso, o valor inteiro. */
export function brlCurto(v: number | string | null | undefined): string {
  const n = Number(v ?? 0);
  return n >= 10_000 ? `R$ ${Math.round(n / 1000).toLocaleString("pt-BR")} mil` : brl(n);
}

// ─── Dias (calendário de Brasília; dia de calendário não tem fuso) ─────────────────────────────

/** 'aaaa-mm-dd' → "13/10". */
export function ddmm(dia: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dia ?? ""));
  return m ? `${m[3]}/${m[2]}` : "";
}

/** 0 = domingo … 6 = sábado, do dia de calendário 'aaaa-mm-dd'. */
export function diaDaSemana(dia: string): number {
  const [a, m, d] = dia.slice(0, 10).split("-").map(Number);
  return new Date(Date.UTC(a, m - 1, d)).getUTCDay();
}

const NOMES_DOS_DIAS = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];

/** "Quinta" (com maiúscula: abre a frase). */
export function nomeDoDia(dia: string): string {
  return NOMES_DOS_DIAS[diaDaSemana(dia)];
}

/** Dia de calendário mais `n` dias. */
export function somarDias(dia: string, n: number): string {
  const [a, m, d] = dia.slice(0, 10).split("-").map(Number);
  return new Date(Date.UTC(a, m - 1, d + n)).toISOString().slice(0, 10);
}

/** Dias entre dois dias de calendário (b − a). */
export function diasEntre(a: string, b: string): number {
  const [a1, m1, d1] = a.slice(0, 10).split("-").map(Number);
  const [a2, m2, d2] = b.slice(0, 10).split("-").map(Number);
  return Math.round((Date.UTC(a2, m2 - 1, d2) - Date.UTC(a1, m1 - 1, d1)) / 86_400_000);
}

/** A próxima segunda-feira DEPOIS de `dia` (numa segunda, a da semana que vem). */
export function proximaSegunda(dia: string): string {
  const ds = diaDaSemana(dia);
  return somarDias(dia, ((8 - ds) % 7) || 7);
}

/** "hoje", "amanhã", "segunda (19/10)" ou "dd/mm" — para dizer até quando algo ficou. */
export function quandoEmPalavras(dia: string, hoje: string): string {
  const n = diasEntre(hoje, dia);
  if (n === 0) return "hoje";
  if (n === 1) return "amanhã";
  if (n > 1 && n < 7) return `${nomeDoDia(dia).toLowerCase()} (${ddmm(dia)})`;
  return ddmm(dia);
}
