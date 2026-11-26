// A queda do assistente vista pelo vigia (pacote 1, V1, 25/11/2026). Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/max/queda-do-assistente_test.ts
//
// O que se protege: chave ausente ou ilegível = desligado (o vigia da conexão roda como antes); a frase da causa é a do
// turno do dono, nunca outra; a queda do tipo claude NÃO fecha só porque a pausa do programa venceu (24/11: a pausa do
// login vence em 10 minutos e o programa volta a se dizer disponível sem testar); com o WhatsApp fora, nenhuma queda do
// assistente é aberta; o texto que o dono leria, letra por letra.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  causaDaFalha, type EstadoDoMax, estadoDoMax, FRASE_CURTA_DA_CAUSA, ondeDoTurnoSemResposta, type ProgramaDoPc, SEM_SINAL_QUEDA_S,
} from "./causa-da-falha.ts";
import {
  causaDoMotivo, CAUSAS_DO_ASSISTENTE, CHAVE_DO_VIGIA_DO_ASSISTENTE, CODIGO_DA_FRASE, decidirQuedaDoAssistente, FALHAS_QUE_O_DONO_LEU,
  fraseDaCausaDaQueda, HORAS_ATE_FECHAR_SEM_PROVA, jaDaParaAvisar, lerModoDoVigia, MINUTOS_ATE_AVISAR_ASSISTENTE, modoDoVigia,
  problemaDoAssistente, type QuedaAberta, sinoDoAssistente, textoDaQuedaDoAssistente, textoDaVoltaDoAssistente,
} from "./queda-do-assistente.ts";

// terça-feira, 24/11/2026, 09:35 em Brasília: a primeira rodada do vigia depois da falha de login das 09:32
const T0 = new Date("2026-11-24T12:35:00Z");
const min = (m: number) => new Date(T0.getTime() + m * 60_000);
const haSegundos = (s: number, de: Date = T0) => new Date(de.getTime() - s * 1000).toISOString();

const NO_AR: EstadoDoMax = { ultimoSinal: haSegundos(6), semSinal: false, pausa: null, ocupado: false, pcComSinal: true };
const estado = (p: Partial<EstadoDoMax> = {}): EstadoDoMax => ({ ...NO_AR, ...p });
const pausa = (motivo: string, ate: string | null = null): EstadoDoMax => estado({ pausa: { motivo, ate } });

function aberta(p: Partial<QuedaAberta> = {}): QuedaAberta {
  return {
    id: "q1", tipo: "claude", causa: "login", desde: T0.toISOString(), visto_em: T0.toISOString(), criado_em: T0.toISOString(),
    dono_soube: null, avisado_por: null, aviso_id: null, ...p,
  };
}

/** Os três programas do PC como estão em produção: cada um publica o que atende (o mesmo desenho do teste do C2). */
function programas(p: { assistenteHa?: number; outrosHa?: number; claude?: Record<string, unknown> } = {}): ProgramaDoPc[] {
  return [
    { id: "hbr-pc-doc", last_seen_at: haSegundos(p.outrosHa ?? 14), estado: { providers: { "local-doc": { available: true } } } },
    { id: "hbr-pc-1", last_seen_at: haSegundos(p.assistenteHa ?? 6), estado: { providers: { "claude-local": p.claude ?? { available: true } }, ativos: 0, max: 2 } },
    { id: "hbr-pc-print", last_seen_at: haSegundos(p.outrosHa ?? 9), estado: { providers: { "local-print": { available: true } } } },
  ];
}

// ─── A chave ─────────────────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("chave: só 'sombra' e 'ligado' ligam; ausente, vazio ou valor de fora = desligado", () => {
  assertEquals(CHAVE_DO_VIGIA_DO_ASSISTENTE, "vigia_assistente");
  assertEquals([modoDoVigia("sombra"), modoDoVigia(" Ligado "), modoDoVigia('"sombra"')], ["sombra", "ligado", "sombra"]);
  for (const v of [undefined, null, "", "desligado", "on", "true", 1, {}, "ligada"]) assertEquals(modoDoVigia(v), "desligado", String(v));
});

function bancoDaChave(resposta: { data?: unknown; error?: unknown } | "lanca" | "explode") {
  const pedido: string[] = [];
  const admin = {
    from(tabela: string) {
      if (resposta === "explode") throw new Error("sem banco");
      pedido.push(tabela);
      const q = {
        select(c: string) { pedido.push(c); return q; },
        eq(c: string, v: string) { pedido.push(`${c}=${v}`); return q; },
        maybeSingle() {
          if (resposta === "lanca") return Promise.reject(new Error("rede fora"));
          return Promise.resolve({ data: resposta.data ?? null, error: resposta.error ?? null });
        },
      };
      return q;
    },
  };
  return { admin, pedido };
}

Deno.test("leitura da chave: nunca lança; chave que falta, erro do banco ou exceção = desligado", async () => {
  const { admin, pedido } = bancoDaChave({ data: { value: "sombra" } });
  assertEquals(await lerModoDoVigia(admin), "sombra");
  assertEquals(pedido, ["app_settings", "value", "key=vigia_assistente"]);
  assertEquals(await lerModoDoVigia(bancoDaChave({ data: { value: "ligado" } }).admin), "ligado");
  assertEquals(await lerModoDoVigia(bancoDaChave({ data: null }).admin), "desligado", "a chave não existe (deploy antes da migration)");
  assertEquals(await lerModoDoVigia(bancoDaChave({ error: { message: "permission denied" } }).admin), "desligado");
  assertEquals(await lerModoDoVigia(bancoDaChave("lanca").admin), "desligado");
  assertEquals(await lerModoDoVigia(bancoDaChave("explode").admin), "desligado");
});

// ─── A causa e a frase ───────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("causa do motivo: os cinco motivos do programa; teto por hora e motivo vazio não são queda; o resto é desconhecida", () => {
  assertEquals(
    ["auth_failed", "rate_limited", "provider_unavailable", "isolation_violation", "worker_shutdown"].map(causaDoMotivo),
    ["login", "limite", "indisponivel", "configuracao", "programa_parado"],
  );
  assertEquals([causaDoMotivo("local_quota"), causaDoMotivo(""), causaDoMotivo(null), causaDoMotivo(undefined)], [null, null, null, null]);
  assertEquals([causaDoMotivo(" AUTH_FAILED "), causaDoMotivo("motivo_novo")], ["login", "desconhecida"]);
});

Deno.test("frase: uma voz só — para o mesmo estado, o vigia diz a mesma frase curta que o turno do dono (C2)", () => {
  for (const motivo of ["auth_failed", "rate_limited", "provider_unavailable", "isolation_violation", "worker_shutdown", "motivo_novo"]) {
    const doTurno = causaDaFalha({ job: null, estado: pausa(motivo), agora: T0 }).curta;
    assertEquals(fraseDaCausaDaQueda(causaDoMotivo(motivo)), doTurno, motivo);
  }
  // sem sinal: o turno diz "o PC da oficina está sem sinal", e o vigia, nas duas causas de programa calado, também
  const semSinal = causaDaFalha({ job: null, estado: estado({ semSinal: true }), agora: T0 }).curta;
  assertEquals([fraseDaCausaDaQueda("programa_parado"), fraseDaCausaDaQueda("sem_rede")], [semSinal, semSinal]);
  // toda causa do histórico tem frase, e ela sai do mapa do C2 (nenhuma frase escrita aqui)
  const doC2 = new Set(Object.values(FRASE_CURTA_DA_CAUSA));
  for (const c of CAUSAS_DO_ASSISTENTE) assert(doC2.has(fraseDaCausaDaQueda(c)), c);
  assertEquals(Object.keys(CODIGO_DA_FRASE).sort(), [...CAUSAS_DO_ASSISTENTE].sort());
  // causa que não é do assistente (a do WhatsApp, lixo): a frase do erro comum, nunca undefined
  for (const c of ["pc_fora", "travado", "", null, 7]) assertEquals(fraseDaCausaDaQueda(c), FRASE_CURTA_DA_CAUSA.erro, String(c));
  // nenhuma frase fala de crédito, recarga ou reserva (decisão do dono de 24/11/2026)
  for (const c of CAUSAS_DO_ASSISTENTE) assert(!/cr[eé]dito|recarga|reserva|saldo/i.test(fraseDaCausaDaQueda(c)), c);
});

Deno.test("registros que o dono leu: só os três que respondem pelo WhatsApp COM a causa (o painel, o tratador e o turno sem causa ficam de fora)", () => {
  assertEquals([...FALHAS_QUE_O_DONO_LEU], ["max_sem_reserva", "max_fora_sem_reserva", "turno_whatsapp_com_causa"]);
  // revisão da leva B (25/11/2026): o turno que o dono leu só como "erro do sistema" não prova que ele sabe da queda
  assert(!(FALHAS_QUE_O_DONO_LEU as readonly string[]).includes("turno_whatsapp"), "o turno sem causa não conta como lido");
  // o nome é o que o ai-agent grava quando a causa foi no topo da resposta (a mesma peça do C2)
  const comCausa = ondeDoTurnoSemResposta(causaDaFalha({ job: null, estado: pausa("auth_failed"), agora: T0 }));
  assert((FALHAS_QUE_O_DONO_LEU as readonly string[]).includes(comCausa), comCausa);
  assert(!(FALHAS_QUE_O_DONO_LEU as readonly string[]).includes(ondeDoTurnoSemResposta(undefined)));
});

// ─── O problema à vista ──────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("problema: programa calado com o PC vivo = programa parado; os três calados = sem rede; 170 s ainda não é queda", () => {
  // 07/11: hbr-pc-1 mudo, o leitor de documento e a impressora dando sinal
  const so = problemaDoAssistente(estadoDoMax(programas({ assistenteHa: 3600 }), SEM_SINAL_QUEDA_S, T0));
  assertEquals([so?.tipo, so?.causa, so?.desde], ["gateway", "programa_parado", haSegundos(3600)]);
  const tudo = problemaDoAssistente(estadoDoMax(programas({ assistenteHa: 3600, outrosHa: 3600 }), SEM_SINAL_QUEDA_S, T0));
  assertEquals([tudo?.tipo, tudo?.causa], ["gateway", "sem_rede"]);
  assertEquals(problemaDoAssistente(estadoDoMax(programas({ assistenteHa: 170 }), SEM_SINAL_QUEDA_S, T0)), null);
  assertEquals(problemaDoAssistente(estadoDoMax(programas({ assistenteHa: 190 }), SEM_SINAL_QUEDA_S, T0))?.causa, "programa_parado");
  assertEquals(problemaDoAssistente(estado()), null, "no ar");
});

Deno.test("problema: a pausa com motivo é do tipo claude; o limite leva o horário de liberação; o detalhe nunca passa de 300", () => {
  const login = problemaDoAssistente(estadoDoMax(programas({ claude: { available: false, reason: "auth_failed", until: "2026-11-24T12:42:00.000Z" } }), SEM_SINAL_QUEDA_S, T0));
  assertEquals(login, { tipo: "claude", causa: "login", desde: null, detalhe: "auth_failed até 2026-11-24T12:42:00.000Z", libera: null });
  const limite = problemaDoAssistente(pausa("rate_limited", "2026-11-26T05:00:00.000Z"));
  assertEquals([limite?.causa, limite?.libera], ["limite", "2026-11-26T05:00:00.000Z"]);
  assertEquals(problemaDoAssistente(pausa("local_quota", "2026-11-24T13:00:00.000Z")), null, "o teto por hora do PC passa sozinho");
  assertEquals(problemaDoAssistente(pausa("")), null, "sem motivo não é queda");
  assert((problemaDoAssistente(pausa("x".repeat(500), "2026-11-26T05:00:00.000Z"))?.detalhe?.length ?? 0) <= 300);
  // o programa avisou que estava saindo: é do tipo gateway (fecha pelo sinal), desde o último sinal
  const saindo = problemaDoAssistente(pausa("worker_shutdown"));
  assertEquals([saindo?.tipo, saindo?.causa, saindo?.desde], ["gateway", "programa_parado", NO_AR.ultimoSinal]);
});

// ─── A decisão ───────────────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("decisão: sem queda e sem problema = nada; com problema, abre (claude desde agora; gateway desde o último sinal)", () => {
  assertEquals(decidirQuedaDoAssistente({ aberta: null, estado: estado(), whatsappAberto: true, ultimoJobBomEm: null, agora: T0 }), { acao: "nada" });
  assertEquals(
    decidirQuedaDoAssistente({ aberta: null, estado: pausa("auth_failed"), whatsappAberto: true, ultimoJobBomEm: null, agora: T0 }),
    { acao: "abrir", tipo: "claude", causa: "login", desde: T0.toISOString(), detalhe: "auth_failed" },
  );
  const calado = estado({ semSinal: true, ultimoSinal: haSegundos(600), pcComSinal: true });
  assertEquals(
    decidirQuedaDoAssistente({ aberta: null, estado: calado, whatsappAberto: true, ultimoJobBomEm: null, agora: T0 }),
    { acao: "abrir", tipo: "gateway", causa: "programa_parado", desde: haSegundos(600), detalhe: "sem_sinal" },
  );
  // sem horário do último sinal, ou com ele no futuro (relógios diferentes): desde agora
  for (const ultimoSinal of [null, new Date(T0.getTime() + 60_000).toISOString(), "lixo"]) {
    const p = decidirQuedaDoAssistente({ aberta: null, estado: estado({ semSinal: true, ultimoSinal, pcComSinal: false }), whatsappAberto: true, ultimoJobBomEm: null, agora: T0 });
    assertEquals(p, { acao: "abrir", tipo: "gateway", causa: "sem_rede", desde: T0.toISOString(), detalhe: "sem_sinal" });
  }
});

Deno.test("decisão: com o WhatsApp fora não abre queda do assistente; a que já está aberta fica como está, sem marcar que viu", () => {
  for (const e of [pausa("auth_failed"), estado({ semSinal: true, pcComSinal: false })]) {
    assertEquals(decidirQuedaDoAssistente({ aberta: null, estado: e, whatsappAberto: false, ultimoJobBomEm: null, agora: T0 }), { acao: "nada" });
  }
  // nem o pedido bom fecha: fecha na primeira rodada com o WhatsApp de pé (e aí há por onde avisar a volta)
  const p = decidirQuedaDoAssistente({ aberta: aberta(), estado: estado(), whatsappAberto: false, ultimoJobBomEm: min(30).toISOString(), agora: min(35) });
  assertEquals(p, { acao: "manter", tipo: "claude", causa: "login", visto: false, detalhe: null });
});

Deno.test("decisão: o caso de 24/11 — login cai às 09:32, a pausa vence às 09:42 e NADA fecha até o pedido bom das 10:37", () => {
  const comPausa = pausa("auth_failed", "2026-11-24T12:42:00.000Z");
  // 09:35 abre
  assertEquals(decidirQuedaDoAssistente({ aberta: null, estado: comPausa, whatsappAberto: true, ultimoJobBomEm: null, agora: T0 }).acao, "abrir");
  const q = aberta();
  // 09:40 a pausa ainda está à vista: mantém e marca que viu
  assertEquals(
    decidirQuedaDoAssistente({ aberta: q, estado: comPausa, whatsappAberto: true, ultimoJobBomEm: null, agora: min(5) }),
    { acao: "manter", tipo: "claude", causa: "login", visto: true, detalhe: "auth_failed até 2026-11-24T12:42:00.000Z" },
  );
  // 09:45 a 10:35: a pausa venceu e o programa se diz disponível sem testar. Não fecha.
  for (const m of [10, 15, 30, 60]) {
    assertEquals(
      decidirQuedaDoAssistente({ aberta: q, estado: estado(), whatsappAberto: true, ultimoJobBomEm: null, agora: min(m) }),
      { acao: "manter", tipo: "claude", causa: "login", visto: false, detalhe: null },
      `aos ${m} min`,
    );
  }
  // 10:40: o pedido das 10:37 concluiu. Fecha na hora do pedido, com prova.
  assertEquals(
    decidirQuedaDoAssistente({ aberta: q, estado: estado(), whatsappAberto: true, ultimoJobBomEm: "2026-11-24T13:37:00.000Z", agora: min(65) }),
    { acao: "fechar", ate: "2026-11-24T13:37:00.000Z", provada: true, por: "job_bom" },
  );
  // pedido bom de ANTES do início (ou data ilegível) não é prova
  for (const antes of [haSegundos(60), T0.toISOString(), "lixo", null]) {
    assertEquals(decidirQuedaDoAssistente({ aberta: q, estado: estado(), whatsappAberto: true, ultimoJobBomEm: antes, agora: min(65) }).acao, "manter", String(antes));
  }
});

Deno.test("decisão: a queda do tipo claude sem prova fecha sozinha depois de 24 h sem ver o problema, e não antes", () => {
  const q = aberta({ visto_em: min(5).toISOString() });
  const quase = new Date(min(5).getTime() + HORAS_ATE_FECHAR_SEM_PROVA * 3_600_000 - 60_000);
  assertEquals(decidirQuedaDoAssistente({ aberta: q, estado: estado(), whatsappAberto: true, ultimoJobBomEm: null, agora: quase }).acao, "manter");
  const depois = new Date(min(5).getTime() + HORAS_ATE_FECHAR_SEM_PROVA * 3_600_000);
  assertEquals(
    decidirQuedaDoAssistente({ aberta: q, estado: estado(), whatsappAberto: true, ultimoJobBomEm: null, agora: depois }),
    { acao: "fechar", ate: depois.toISOString(), provada: false, por: "sem_prova" },
  );
  // com o problema à vista (o limite da semana dura dias) ela nunca fecha pelas 24 h
  assertEquals(decidirQuedaDoAssistente({ aberta: q, estado: pausa("rate_limited"), whatsappAberto: true, ultimoJobBomEm: null, agora: depois }).acao, "manter");
  assertEquals(decidirQuedaDoAssistente({ aberta: aberta({ visto_em: "lixo" }), estado: estado(), whatsappAberto: true, ultimoJobBomEm: null, agora: depois }).acao, "manter");
});

Deno.test("decisão: a queda do tipo gateway fecha quando o programa volta a dar sinal; o religamento não vira queda eterna", () => {
  const q = aberta({ tipo: "gateway", causa: "programa_parado", desde: haSegundos(600) });
  assertEquals(
    decidirQuedaDoAssistente({ aberta: q, estado: estado(), whatsappAberto: true, ultimoJobBomEm: null, agora: min(5) }),
    { acao: "fechar", ate: min(5).toISOString(), provada: true, por: "batimento" },
  );
  // continua calado: mantém e marca que viu (a causa pode mudar de "programa parado" para "sem rede")
  assertEquals(
    decidirQuedaDoAssistente({ aberta: q, estado: estado({ semSinal: true, pcComSinal: false }), whatsappAberto: true, ultimoJobBomEm: null, agora: min(5) }),
    { acao: "manter", tipo: "gateway", causa: "sem_rede", visto: true, detalhe: "sem_sinal" },
  );
  // o programa que avisou que estava saindo abre do tipo gateway e fecha pelo sinal, sem precisar de pedido bom
  const saindo = decidirQuedaDoAssistente({ aberta: null, estado: pausa("worker_shutdown"), whatsappAberto: true, ultimoJobBomEm: null, agora: T0 });
  assertEquals([saindo.acao, saindo.acao === "abrir" && saindo.tipo], ["abrir", "gateway"]);
  // o teto por hora do PC não segura a queda do tipo gateway aberta
  assertEquals(decidirQuedaDoAssistente({ aberta: q, estado: pausa("local_quota"), whatsappAberto: true, ultimoJobBomEm: null, agora: min(5) }).acao, "fechar");
});

Deno.test("decisão: o programa volta dizendo que o login caiu = a queda vira do tipo claude (precisa de prova); o contrário nunca", () => {
  const q = aberta({ tipo: "gateway", causa: "programa_parado", desde: haSegundos(600) });
  const virou = decidirQuedaDoAssistente({ aberta: q, estado: pausa("auth_failed"), whatsappAberto: true, ultimoJobBomEm: null, agora: min(5) });
  assertEquals(virou, { acao: "manter", tipo: "claude", causa: "login", visto: true, detalhe: "auth_failed" });
  // a pausa vence: como já é do tipo claude, não fecha pelo sinal
  const depois = decidirQuedaDoAssistente({ aberta: aberta({ tipo: "claude", causa: "login", desde: q.desde }), estado: estado(), whatsappAberto: true, ultimoJobBomEm: null, agora: min(15) });
  assertEquals(depois.acao, "manter");
  // queda do tipo claude e o programa para: a causa muda, o tipo não (quem precisou de prova continua precisando)
  const parou = decidirQuedaDoAssistente({ aberta: aberta(), estado: estado({ semSinal: true, pcComSinal: true }), whatsappAberto: true, ultimoJobBomEm: null, agora: min(5) });
  assertEquals(parou, { acao: "manter", tipo: "claude", causa: "programa_parado", visto: true, detalhe: "sem_sinal" });
  // o login que vira limite
  const limite = decidirQuedaDoAssistente({ aberta: aberta(), estado: pausa("rate_limited", "2026-11-26T05:00:00.000Z"), whatsappAberto: true, ultimoJobBomEm: null, agora: min(5) });
  assertEquals([limite.acao === "manter" && limite.causa, limite.acao === "manter" && limite.visto], ["limite", true]);
});

Deno.test("aviso: só 15 minutos depois de o vigia gravar a queda (o início dela pode ser bem anterior)", () => {
  assertEquals(MINUTOS_ATE_AVISAR_ASSISTENTE, 15);
  // 07/11: o programa parou às 17:27, o WhatsApp voltou às 19:45 e só então a queda foi gravada
  const q = aberta({ tipo: "gateway", causa: "programa_parado", desde: haSegundos(8280), criado_em: T0.toISOString() });
  assertEquals([jaDaParaAvisar(q, min(0)), jaDaParaAvisar(q, min(14)), jaDaParaAvisar(q, min(15))], [false, false, true]);
  assertEquals(jaDaParaAvisar(aberta({ criado_em: "lixo" }), min(60)), false);
});

// ─── O que o dono lê ─────────────────────────────────────────────────────────────────────────────────────────────────

const AS_0947 = min(12);
const DESDE_0932 = "2026-11-24T12:32:00.000Z";
const NORMAIS = "O WhatsApp e o resto do sistema seguem normais; só as mensagens para o assistente ficam sem resposta.";

Deno.test("texto da queda: cada causa, com a frase do C2, sem botão e sem pedir resposta", () => {
  assertEquals(textoDaQuedaDoAssistente({ causa: "login", desde: DESDE_0932 }, AS_0947),
    `*Seu assistente está fora do ar desde as 09:32:* o login do Claude caiu. ${NORMAIS}`);
  assertEquals(textoDaQuedaDoAssistente({ causa: "limite", desde: DESDE_0932, libera: "2026-11-26T05:00:00.000Z" }, AS_0947),
    `*Seu assistente está fora do ar desde as 09:32:* acabou o limite da assinatura. Libera qui 26/11 às 02:00. ${NORMAIS}`);
  assertEquals(textoDaQuedaDoAssistente({ causa: "limite", desde: DESDE_0932 }, AS_0947),
    `*Seu assistente está fora do ar desde as 09:32:* acabou o limite da assinatura. Ainda não sei quando libera. ${NORMAIS}`);
  assertEquals(textoDaQuedaDoAssistente({ causa: "indisponivel", desde: DESDE_0932 }, AS_0947),
    `*Seu assistente está fora do ar desde as 09:32:* o Claude não alcançou o sistema. ${NORMAIS}`);
  for (const causa of ["configuracao", "desconhecida", "causa_de_fora", null]) {
    assertEquals(textoDaQuedaDoAssistente({ causa, desde: DESDE_0932 }, AS_0947),
      `*Seu assistente está fora do ar desde as 09:32:* deu um erro no assistente do PC. ${NORMAIS}`, String(causa));
  }
  // só quando o vigia vê a volta sozinho (o programa calado) ele promete avisar
  for (const causa of ["programa_parado", "sem_rede"]) {
    assertEquals(textoDaQuedaDoAssistente({ causa, desde: DESDE_0932 }, AS_0947),
      `*Seu assistente está fora do ar desde as 09:32:* o PC da oficina está sem sinal. ${NORMAIS} Aviso aqui quando ele voltar.`, causa);
  }
  // queda que começou em outro dia diz o dia; sem horário, não inventa
  assertEquals(textoDaQuedaDoAssistente({ causa: "programa_parado", desde: "2026-11-23T20:27:00.000Z" }, AS_0947),
    `*Seu assistente está fora do ar desde seg 23/11 às 17:27:* o PC da oficina está sem sinal. ${NORMAIS} Aviso aqui quando ele voltar.`);
  assertEquals(textoDaQuedaDoAssistente({ causa: "login", desde: null }, AS_0947),
    `*Seu assistente está fora do ar:* o login do Claude caiu. ${NORMAIS}`);
  // o horário de liberação só aparece no limite
  assert(!textoDaQuedaDoAssistente({ causa: "login", desde: DESDE_0932, libera: "2026-11-26T05:00:00.000Z" }, AS_0947).includes("Libera"));
  for (const causa of CAUSAS_DO_ASSISTENTE) {
    const t = textoDaQuedaDoAssistente({ causa, desde: DESDE_0932 }, AS_0947);
    assert(!/[\p{Extended_Pictographic}]/u.test(t), "sem emoji");
    assert(!t.includes("?"), "não pede resposta");
    assert(!/cr[eé]dito|recarga|reserva|saldo/i.test(t), "nada de crédito");
  }
});

Deno.test("texto da volta: a hora da volta, desde quando esteve fora, e o dia quando não é hoje", () => {
  assertEquals(textoDaVoltaDoAssistente({ desde: DESDE_0932, ate: "2026-11-24T13:37:00.000Z" }, min(65)),
    "*Seu assistente voltou às 10:37* (estava fora desde as 09:32). Pode mandar de novo o que ficou sem resposta.");
  assertEquals(textoDaVoltaDoAssistente({ desde: "2026-11-23T20:27:00.000Z", ate: "2026-11-24T01:10:00.000Z" }, AS_0947),
    "*Seu assistente voltou em 23/11 às 22:10* (estava fora desde seg 23/11 às 17:27). Pode mandar de novo o que ficou sem resposta.");
  assertEquals(textoDaVoltaDoAssistente({ desde: null, ate: null }, AS_0947), "*Seu assistente voltou*. Pode mandar de novo o que ficou sem resposta.");
});

Deno.test("sino: o mesmo texto sem o negrito do WhatsApp, com tipo e título próprios", () => {
  const texto = textoDaQuedaDoAssistente({ causa: "login", desde: DESDE_0932 }, AS_0947);
  assertEquals(sinoDoAssistente("caiu", texto), {
    type: "assistente_caiu", title: "Assistente fora do ar",
    body: `Seu assistente está fora do ar desde as 09:32: o login do Claude caiu. ${NORMAIS}`,
  });
  const volta = sinoDoAssistente("voltou", "*Seu assistente voltou às 10:37* (estava fora desde as 09:32). Pode mandar de novo o que ficou sem resposta.");
  assertEquals([volta.type, volta.title], ["assistente_voltou", "Assistente de volta"]);
  assert(!volta.body.includes("*"));
});
