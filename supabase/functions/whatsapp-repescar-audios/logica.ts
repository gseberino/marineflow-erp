/**
 * A decisão de quando parar, separada do I/O para poder ser testada.
 *
 * O que protege aqui não é o resultado, é o Evolution: ele roda no PC do dono, atrás do
 * túnel, e cada tentativa o faz decifrar uma mídia. Se a janela de duas semanas já passou
 * (ou se ele caiu), as tentativas seguintes vão falhar todas — insistir quarenta vezes
 * transforma um job silencioso numa carga inútil em cima de um serviço já em apuros.
 */

export const DIAS_DA_JANELA = 10;
/**
 * Teto por execução, calibrado pelo tempo: 20 × (4s de pausa + ~2s de transcrição) ≈ 2min,
 * folgado dentro do limite de uma edge function. O que sobrar vem amanhã — é um job diário
 * de repescagem, não uma corrida.
 */
export const TETO_POR_EXECUCAO = 20;
export const DESISTIR_APOS = 5;

/**
 * Pausa entre tentativas. Medida, não chutada: com 1,5s (40 req/min) o Groq começou a
 * responder "Rate limit reached" no meio do backfill de 25/09/2026 — e o mesmo áudio
 * transcreveu de primeira ao ser tentado de novo um minuto depois. 4s mantém o ritmo em
 * ~15/min, abaixo do limite.
 */
export const PAUSA_MS = 4000;

/**
 * Espera extra depois de uma falha. Limite de taxa se resolve com tempo, não com
 * insistência: sem esta pausa, as cinco tentativas seguintes caem no mesmo minuto cheio e
 * o job desiste de um problema que teria passado sozinho.
 */
export const ESPERA_APOS_FALHA_MS = 15000;

/** Só vale tentar o que tem a chave da mídia — sem ela não há o que pedir ao Evolution. */
export function temMidiaPedivel(m: { raw_payload?: unknown }): boolean {
  const key = (m?.raw_payload as any)?.data?.key;
  return typeof key?.id === "string" && key.id.length > 0;
}

/** O corpo ainda é um marcador (`[audio]`), e não uma transcrição? */
export function aindaMudo(body: string | null | undefined): boolean {
  const b = String(body ?? "").trim();
  return b === "" || /^\[[a-z]+\]$/i.test(b);
}

export type Passo = { ok: boolean };

/**
 * Percorre os alvos e devolve o resumo, parando cedo em falha repetida.
 *
 * `tentar` é injetado para o teste poder simular Evolution fora do ar sem rede.
 */
export async function repescar(
  alvos: Array<{ id: string }>,
  tentar: (id: string) => Promise<Passo>,
  pausar: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
): Promise<{ transcritos: number; falhas: number; parouCedo: boolean; tentativas: number }> {
  let transcritos = 0;
  let falhas = 0;
  let seguidas = 0;
  let tentativas = 0;

  for (const alvo of alvos) {
    tentativas++;
    let ok = false;
    try {
      ok = (await tentar(alvo.id)).ok;
    } catch {
      ok = false;
    }
    if (ok) {
      transcritos++;
      seguidas = 0;
      await pausar(PAUSA_MS);
    } else {
      falhas++;
      seguidas++;
      if (seguidas >= DESISTIR_APOS) {
        return { transcritos, falhas, parouCedo: true, tentativas };
      }
      // Depois de falhar, esperar mais: a causa mais comum é limite de taxa, que passa
      // com tempo. Tentar de novo no mesmo minuto só gasta a cota de desistência.
      await pausar(ESPERA_APOS_FALHA_MS);
    }
  }
  return { transcritos, falhas, parouCedo: false, tentativas };
}
