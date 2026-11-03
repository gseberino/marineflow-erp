import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  dddDoTelefone,
  decidirSaidaAutomatica,
  decidirSaidaDoRetorno,
  ehAutomatica,
  ehDaEquipe,
  horaDeBrasilia,
  manterReservaNaFalha,
  proximaAberturaDaJanela,
  reservaImpedeEnvio,
} from "./saida-automatica.ts";

Deno.test("automático é só a chamada de sistema com origem sistema", () => {
  assert(ehAutomatica("sistema", true));
  assert(!ehAutomatica("assistente", true));
  assert(!ehAutomatica("tela", true));
  // Com o JWT de um usuário a origem nunca é "sistema" (origemDoEnvio), mas a regra não depende disso.
  assert(!ehAutomatica("sistema", false));
  // As origens do retorno (F1) ficam fora, mesmo em chamada de sistema: têm portão próprio
  // (decidirSaidaDoRetorno), como diz a JSDoc de ehAutomatica.
  for (const origem of ["retorno_recibo", "retorno_coleta", "retorno_adiamento"] as const) {
    assert(!ehAutomatica(origem, true), origem);
  }
});

Deno.test("equipe: compara pela chave do telefone, com e sem 55, e exige o mesmo DDD", () => {
  assert(ehDaEquipe("5547999990001", ["47999990001"]));
  assert(ehDaEquipe("554799990001", ["5547999990001"]), "com e sem o 9");
  assert(!ehDaEquipe("5547999990002", ["47999990001", null, undefined]));
  // os mesmos 8 dígitos, de outro DDD: não é o dono
  assert(!ehDaEquipe("5511999990001", ["5547999990001"]));
  assertEquals(dddDoTelefone("5547999990001"), "47");
  assertEquals(dddDoTelefone("(47) 3333-0001"), "47");
  assertEquals(dddDoTelefone("99999-0001"), null);
});

Deno.test("hora de Brasília: a hora certa, e null quando não dá para saber", () => {
  assertEquals(horaDeBrasilia(new Date("2026-11-05T11:00:00Z")), 8);
  assertEquals(horaDeBrasilia(new Date("2026-11-05T02:59:00Z")), 23);
  assertEquals(horaDeBrasilia(new Date("2026-11-05T03:00:00Z")), 0);
  assertEquals(horaDeBrasilia(new Date("data inválida")), null);
});

Deno.test("próxima abertura da janela: hoje às 8h antes das 8h; amanhã às 8h depois", () => {
  // 06:30 de Brasília (09:30 UTC) → hoje 08:00 (11:00 UTC)
  assertEquals(proximaAberturaDaJanela(new Date("2026-11-05T09:30:00Z")).toISOString(), "2026-11-05T11:00:00.000Z");
  // 21:10 de Brasília (00:10 UTC do dia seguinte) → amanhã 08:00
  assertEquals(proximaAberturaDaJanela(new Date("2026-11-06T00:10:00Z")).toISOString(), "2026-11-06T11:00:00.000Z");
  // 20:00 de Brasília → amanhã 08:00
  assertEquals(proximaAberturaDaJanela(new Date("2026-11-05T23:00:00Z")).toISOString(), "2026-11-06T11:00:00.000Z");
});

Deno.test("portão: a equipe passa sempre, mesmo com checagem falhando", () => {
  assertEquals(decidirSaidaAutomatica({ daEquipe: true, bloqueio: "erro", hora: null }), { pode: true });
});

Deno.test("portão: checagem que falhou recusa (falha fechada)", () => {
  const d = decidirSaidaAutomatica({ daEquipe: false, bloqueio: "erro", hora: 10 });
  assert(!d.pode && d.codigo === "checagem_indisponivel");
  // Sem saber se é da equipe, segue como de fora.
  const e = decidirSaidaAutomatica({ daEquipe: "erro", bloqueio: "erro", hora: 10 });
  assert(!e.pode && e.codigo === "checagem_indisponivel");
});

Deno.test("portão: cada motivo de canal_bloqueado recusa, com o texto dele", () => {
  for (const motivo of ["cliente_final", "bloqueado", "opt_out"]) {
    const d = decidirSaidaAutomatica({ daEquipe: false, bloqueio: motivo, hora: 10 });
    assert(!d.pode && d.codigo === motivo && d.mensagem.startsWith("Envio automático recusado: "), motivo);
  }
  const final = decidirSaidaAutomatica({ daEquipe: false, bloqueio: "cliente_final", hora: 10 });
  assert(!final.pode && final.mensagem.includes('"Cliente Final"'));
  // Motivo novo que o banco venha a devolver também recusa.
  const novo = decidirSaidaAutomatica({ daEquipe: false, bloqueio: "outro_motivo", hora: 10 });
  assert(!novo.pode && novo.codigo === "outro_motivo");
});

Deno.test("portão: hora desconhecida recusa; fora de 8h–20h recusa; dentro passa", () => {
  const sem = decidirSaidaAutomatica({ daEquipe: false, bloqueio: null, hora: null });
  assert(!sem.pode && sem.codigo === "hora_indisponivel");
  for (const h of [0, 7, 20, 23]) {
    const d = decidirSaidaAutomatica({ daEquipe: false, bloqueio: null, hora: h });
    assert(!d.pode && d.codigo === "fora_de_horario", `${h}h`);
  }
  for (const h of [8, 12, 19]) {
    assertEquals(decidirSaidaAutomatica({ daEquipe: false, bloqueio: null, hora: h }), { pode: true }, `${h}h`);
  }
});

Deno.test("reserva: banco sem resposta impede só o automático a quem é de fora", () => {
  assert(reservaImpedeEnvio("erro", true));
  assert(!reservaImpedeEnvio("erro", false));
  assert(!reservaImpedeEnvio("nova", true));
});

Deno.test("falha incerta mantém a reserva só no automático a quem é de fora", () => {
  assert(manterReservaNaFalha(true, true));
  assert(!manterReservaNaFalha(false, true));
  assert(!manterReservaNaFalha(undefined, true));
  assert(!manterReservaNaFalha(true, false));
});

// ═══ Retorno F1 (16/11/2026): o portão do retorno é retorno_saida_autorizada (banco); aqui só a
// tradução da resposta, falhando fechado.

Deno.test("retorno: chamada que falhou, resposta nula ou sem \"pode\" booleano recusa como checagem_indisponivel", () => {
  type Aut = Parameters<typeof decidirSaidaDoRetorno>[0];
  const casos: Array<[string, Aut]> = [
    ["erro", "erro"],
    ["null", null],
    ["{}", {}],
    ['{pode: "true"}', { pode: "true" }],
    ["{pode: 1}", { pode: 1 }],
    ["{pode: null}", { pode: null }],
    ["lista", [] as unknown as Aut],
    ["texto", "true" as unknown as Aut],
  ];
  for (const [nome, aut] of casos) {
    const d = decidirSaidaDoRetorno(aut);
    assert(!d.pode && d.codigo === "checagem_indisponivel", nome);
    assert(!d.pode && d.mensagem === "Envio automático recusado: não deu para conferir se o número pode receber (banco sem resposta).", nome);
  }
});

Deno.test("retorno: pode false recusa com o motivo do banco (opt-out com a mensagem dele)", () => {
  const opt = decidirSaidaDoRetorno({ pode: false, motivo: "opt_out" });
  assertEquals(opt, {
    pode: false,
    codigo: "opt_out",
    mensagem: "Envio automático recusado: o contato pediu para não receber mensagens automáticas.",
  });
  // Sem motivo (nulo, vazio ou não texto): retorno_nao_autorizado.
  for (const motivo of [undefined, null, "", "   ", 42]) {
    const d = decidirSaidaDoRetorno({ pode: false, motivo });
    assert(!d.pode && d.codigo === "retorno_nao_autorizado", String(motivo));
  }
  // A exceção dentro de retorno_saida_autorizada volta como motivo "erro".
  const erro = decidirSaidaDoRetorno({ pode: false, motivo: "erro" });
  assert(!erro.pode && erro.codigo === "erro" && erro.mensagem.includes("deu erro no banco"));
  // Motivo que não tem texto próprio fica com o genérico, sem perder o código.
  const tipo = decidirSaidaDoRetorno({ pode: false, motivo: "tipo_desligado" });
  assert(!tipo.pode && tipo.codigo === "tipo_desligado" && tipo.mensagem.includes("(tipo_desligado)"));
});

Deno.test("retorno: só pode === true envia, e a janela fixa de 8h–20h não vale para ele", () => {
  assertEquals(decidirSaidaDoRetorno({ pode: true }), { pode: true });
  assertEquals(decidirSaidaDoRetorno({ pode: true, motivo: null }), { pode: true });
  // 07h: o automático de hoje recusa; o retorno autorizado pelo banco (janela K3, 07:00–21:59) sai,
  // porque decidirSaidaDoRetorno não recebe hora nenhuma: a janela é só a do banco.
  const automatico = decidirSaidaAutomatica({ daEquipe: false, bloqueio: null, hora: 7 });
  assert(!automatico.pode && automatico.codigo === "fora_de_horario");
  assertEquals(decidirSaidaDoRetorno.length, 1, "a decisão do retorno só recebe a resposta do banco");
});
